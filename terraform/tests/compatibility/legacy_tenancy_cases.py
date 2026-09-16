from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

CASES = {
    "long-key-explicit-role": ({"a" * 64: {"database_name": "alpha_db", "db_role_name": "alpha_role"}}, {"a" * 64: "alpha_role"}, None),
    "omitted-role": ({"alpha-beta": {"database_name": "alpha_db"}}, {"alpha-beta": "alpha_beta"}, None),
    "null-role": ({"alpha-beta": {"database_name": "alpha_db", "db_role_name": None}}, {"alpha-beta": "alpha_beta"}, None),
    "empty-tenants": ({}, {}, None),
    "derived-role-too-long": ({"a" * 64: {"database_name": "alpha_db"}}, None, "must be <= 63 bytes"),
    "explicit-role-too-long": ({"alpha": {"database_name": "alpha_db", "db_role_name": "a" * 64}}, None, "must be <= 63 bytes"),
}


def run(command: list[str], directory: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=directory, text=True, capture_output=True, check=False)


def prepare(source: Path, destination: Path, candidate: bool) -> None:
    module = source / "terraform/modules/aws-eks-aurora-cluster"
    destination.mkdir()
    for name in ("variables.tf", "locals.tf"):
        (destination / name).write_bytes((module / name).read_bytes())
    if candidate:
        blocks = re.findall(r'(?ms)^module "(?:tenancy_contract|workload_contract)" \{.*?^\}', (module / "resources.tf").read_text())
        if len(blocks) != 2:
            raise SystemExit("expected both resource-free contract calls in the candidate adapter")
        contract_calls = "\n\n".join(blocks)
        for name in ("postgres-tenancy-contract", "postgres-workload-contract"):
            contract = source / "terraform/modules" / name
            for path in contract.glob("*.tf"):
                if re.search(r'(?m)^\s*(?:resource|data|provider|module)\s+"', path.read_text()):
                    raise SystemExit("legacy tenancy fixture requires resource-free contract modules")
            contract_calls = contract_calls.replace(f'"../{name}"', json.dumps(str(contract)))
        (destination / "contracts.tf").write_text(contract_calls + "\n")
    (destination / "outputs.tf").write_text('output "roles" { value = local.resolved_tenant_role_names }\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--cases", type=Path)
    args = parser.parse_args()
    cases = dict(CASES)
    if args.cases:
        extra = json.loads(args.cases.read_text())
        if not extra or cases.keys() & extra.keys():
            raise SystemExit("extra case names must be nonempty and distinct")
        cases.update({name: (case["tenants"], case["expected_roles"], None) for name, case in extra.items()})
    tofu = os.environ.get("TOFU", "tofu")
    with tempfile.TemporaryDirectory(prefix="root-modules-legacy-tenancy-") as temporary:
        for label, source in (("baseline", args.baseline.resolve()), ("candidate", args.candidate.resolve())):
            for name, (tenants, expected, diagnostic) in cases.items():
                directory = Path(temporary) / f"{label}-{name}"
                prepare(source, directory, label == "candidate")
                inputs = {
                    "project_name_prefix": "example", "workload_name": "product", "database_name": "bootstrap",
                    "vpc_id": "vpc-fixture", "subnet_ids": [], "allowed_security_group_ids": [], "tenants": tenants,
                }
                (directory / "terraform.tfvars.json").write_text(json.dumps(inputs))
                initialized = run([tofu, "init", "-backend=false", "-input=false", "-no-color"], directory)
                if initialized.returncode != 0:
                    raise SystemExit(f"{label}/{name}: initialization failed\n{initialized.stdout}{initialized.stderr}")
                plan = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=case.plan"], directory)
                if diagnostic:
                    if plan.returncode == 0 or diagnostic not in plan.stdout + plan.stderr:
                        raise SystemExit(f"{label}/{name}: intended validation was not observed\n{plan.stdout}{plan.stderr}")
                    print(f"PASS legacy-tenancy {label}/{name} (fail: {diagnostic})")
                    continue
                if plan.returncode != 0:
                    raise SystemExit(f"{label}/{name}: valid input failed\n{plan.stdout}{plan.stderr}")
                shown = run([tofu, "show", "-json", "case.plan"], directory)
                if shown.returncode != 0:
                    raise SystemExit(f"{label}/{name}: cannot inspect planned output\n{shown.stderr}")
                actual = json.loads(shown.stdout)["planned_values"]["outputs"]["roles"]["value"]
                if actual != expected:
                    raise SystemExit(f"{label}/{name}: resolved tenant roles differ from the declared expectation")
                print(f"PASS legacy-tenancy {label}/{name} (exact roles)")
    print(f"PASS legacy-tenancy cases={len(cases)} sources=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
