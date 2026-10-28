#!/usr/bin/env python3
# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Check the operator bundle catalog and prove a catalog mutation is detected."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLBOX = ROOT / "toolbox" / "operator-tools"
RENDERER = "render-bundle.sh"


def listing(toolbox: Path) -> str:
    result = subprocess.run(
        ["bash", str(toolbox / RENDERER), "--list"],
        cwd=toolbox,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout


def run_bundle(toolbox: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    # TOFU=true neutralises the raw-tofu fallback in read_tf_output: against a
    # fake stack dir with no .tf files, `tofu output -raw` prints a "No outputs
    # found" warning on STDOUT, which the helper would capture as a non-empty
    # value. A stub make-output table plus TOFU=true keeps reads deterministic.
    merged = {**os.environ, "TOFU": "true", **(env or {})}
    return subprocess.run(
        ["bash", str(toolbox / RENDERER), *args],
        cwd=toolbox,
        text=True,
        capture_output=True,
        check=False,
        env=merged,
    )


def expect_failure(result: subprocess.CompletedProcess[str], fragment: str, label: str) -> None:
    if result.returncode == 0 or fragment not in (result.stdout + result.stderr):
        raise SystemExit(f"{label}: expected failure containing '{fragment}'\n{result.stdout}{result.stderr}")


def expect_skip(result: subprocess.CompletedProcess[str], out: Path, label: str) -> None:
    if result.returncode != 0 or out.exists():
        raise SystemExit(f"{label}: expected a skip with no file written\n{result.stdout}{result.stderr}")


def write_stub_stack(directory: Path, outputs: dict[str, str]) -> None:
    """A fake applied stack: `make output` prints the `key = "value"` table
    that read_tf_output greps, so no tofu state is needed."""
    lines = "\n".join(f'\t@echo \'{key} = "{value}"\'' for key, value in outputs.items())
    (directory / "Makefile").write_text(f".PHONY: output\noutput:\n{lines}\n")


def check_cloudsql_bundles(toolbox: Path, work: Path) -> None:
    out = work / "cloudsql.env"

    # Argument validation.
    expect_failure(run_bundle(toolbox, "cloudsql-config", "--data-dir", str(work)),
                   "--out is required", "cloudsql-config missing --out")
    expect_failure(run_bundle(toolbox, "cloudsql-config", "--out", str(out)),
                   "--data-dir is required", "cloudsql-config missing --data-dir")
    expect_failure(run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--secret-id", "s"),
                   "--project is required", "cloudsql-master missing --project")
    expect_failure(run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--project", "p"),
                   "provide --secret-id or --secret-id-output", "cloudsql-master missing secret selector")
    expect_failure(
        run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--project", "p",
                   "--secret-id-output", "master_secret_id"),
        "--data-dir is required when using --secret-id-output",
        "cloudsql-master missing --data-dir")

    # Refusal paths: required output absent, or the secret is unreadable.
    empty_stack = work / "empty-stack"
    empty_stack.mkdir()
    expect_failure(run_bundle(toolbox, "cloudsql-config", "--out", str(out), "--data-dir", str(empty_stack)),
                   "empty or missing", "cloudsql-config unapplied data stack")
    expect_skip(run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--project", "p",
                           "--secret-id-output", "master_secret_id", "--data-dir", str(empty_stack)),
                out, "cloudsql-master secret id absent from outputs")

    failing_gcloud = work / "bin-fail"
    failing_gcloud.mkdir()
    stub = failing_gcloud / "gcloud"
    stub.write_text("#!/usr/bin/env bash\nexit 1\n")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    fail_env = {**os.environ, "PATH": f"{failing_gcloud}:{os.environ['PATH']}"}
    # A failed credential read is fatal, not a skip: the master credential is
    # a required payload and a silent skip lets a stale or empty file become
    # Kubernetes Secret data, surfacing as an auth failure far from its cause.
    unreadable = run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--project", "p",
                            "--secret-id", "db-master", env=fail_env)
    expect_failure(unreadable, "could not read Secret Manager",
                   "cloudsql-master unreadable secret is fatal")
    if out.exists():
        raise SystemExit("cloudsql-master wrote a file on unreadable secret")

    # A readable but passwordless payload is equally fatal — `username=` /
    # `password=` empty lines must never be written.
    empty_pass_bin = work / "bin-empty-pass"
    empty_pass_bin.mkdir()
    stub = empty_pass_bin / "gcloud"
    stub.write_text("#!/usr/bin/env bash\nprintf '%s\\n' '{\"username\":\"appuser\"}'\n")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    empty_pass_env = {**os.environ, "PATH": f"{empty_pass_bin}:{os.environ['PATH']}"}
    passwordless = run_bundle(toolbox, "cloudsql-master", "--out", str(out), "--project", "p",
                              "--secret-id", "db-master", env=empty_pass_env)
    expect_failure(passwordless, "no password field",
                   "cloudsql-master empty password is fatal")
    if out.exists():
        raise SystemExit("cloudsql-master wrote a file on empty password")

    # aurora-master carries the same required-credential contract on AWS.
    failing_aws = work / "bin-aws-fail"
    failing_aws.mkdir()
    stub = failing_aws / "aws"
    stub.write_text("#!/usr/bin/env bash\nexit 1\n")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    aws_fail_env = {**os.environ, "PATH": f"{failing_aws}:{os.environ['PATH']}"}
    aurora_out = work / "aurora-master.env"
    aurora = run_bundle(toolbox, "aurora-master", "--out", str(aurora_out), "--region", "r",
                        "--secret-arn", "arn:aws:secretsmanager:r:0:secret:x", env=aws_fail_env)
    expect_failure(aurora, "could not read Secrets Manager",
                   "aurora-master unreadable secret is fatal")
    if aurora_out.exists():
        raise SystemExit("aurora-master wrote a file on unreadable secret")

    # Happy paths: stub TF outputs and a stub gcloud serving the payload.
    stack = work / "data-stack"
    stack.mkdir()
    write_stub_stack(stack, {
        "cluster_endpoint": "10.0.0.5",
        "port": "5433",
        "database_name": "appdb",
        "master_secret_id": "projects/p/secrets/db-master",
    })
    config = run_bundle(toolbox, "cloudsql-config", "--out", str(out), "--data-dir", str(stack))
    if config.returncode != 0 or not out.exists():
        raise SystemExit(f"cloudsql-config render failed\n{config.stdout}{config.stderr}")
    content = out.read_text()
    for line in ("host=10.0.0.5", "port=5433", "database=appdb"):
        if line not in content:
            raise SystemExit(f"cloudsql-config output missing '{line}':\n{content}")
    if stat.S_IMODE(out.stat().st_mode) != 0o600:
        raise SystemExit("cloudsql-config did not chmod 600 the rendered file")

    ok_gcloud = work / "bin-ok"
    ok_gcloud.mkdir()
    stub = ok_gcloud / "gcloud"
    # Reproduces the real binary's contract: `secrets versions access
    # --secret=` rejects the projects/*/secrets/* resource-id form with a
    # 404 — only the short name is accepted.
    stub.write_text(
        "#!/usr/bin/env bash\n"
        "for arg in \"$@\"; do\n"
        "  case \"$arg\" in --secret=*/*) exit 1 ;; esac\n"
        "done\n"
        "printf '%s\\n' '{\"username\":\"appuser\",\"password\":\"s3cret-pass\"}'\n")
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    ok_env = {**os.environ, "PATH": f"{ok_gcloud}:{os.environ['PATH']}"}
    master_out = work / "cloudsql-master.env"
    master = run_bundle(toolbox, "cloudsql-master", "--out", str(master_out), "--project", "p",
                        "--secret-id-output", "master_secret_id", "--data-dir", str(stack), env=ok_env)
    if master.returncode != 0 or not master_out.exists():
        raise SystemExit(f"cloudsql-master render failed\n{master.stdout}{master.stderr}")
    content = master_out.read_text()
    for line in ("username=appuser", "password=s3cret-pass"):
        if line not in content:
            raise SystemExit(f"cloudsql-master output missing '{line}':\n{content}")

    print("PASS renderer-cases cloudsql-config")
    print("PASS renderer-cases cloudsql-master")
    print("PASS renderer-negative cloudsql-flag-validation")
    print("PASS renderer-negative cloudsql-missing-secret")
    print("PASS renderer-negative cloudsql-unreadable-credential-fatal")
    print("PASS renderer-negative cloudsql-empty-password-fatal")
    print("PASS renderer-negative aurora-unreadable-credential-fatal")


def write_stub_tofu(directory: Path) -> Path:
    """A stub `tofu` reproducing the real binary's observable contract:
    `output -raw` prints a "No outputs found" warning on STDOUT and exits 0
    in a stateless directory (the captured-warning defect this tests);
    `output -json` prints nothing and exits 1 for an absent output, and
    prints the JSON value for a present one (keyed by output name)."""
    stub = directory / "tofu"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "$1 $2" == "output -json" ]]; then\n'
        '  case "$3" in\n'
        '    present_string) printf \'"10.114.0.3"\\n\'; exit 0 ;;\n'
        '    present_number) printf \'42\\n\'; exit 0 ;;\n'
        '    present_object) printf \'{"tls":true,"n":1}\\n\'; exit 0 ;;\n'
        '    present_null)   printf \'null\\n\'; exit 0 ;;\n'
        '    sensitive_token) printf \'"tok3n-real"\\n\'; exit 0 ;;\n'
        '    *) exit 1 ;;\n'
        '  esac\n'
        'elif [[ "$1 $2" == "output -raw" ]]; then\n'
        "  printf '\\033[33mWarning:\\033[0m No outputs found\\n'\n"
        '  exit 0\n'
        'elif [[ "$1" == "output" ]]; then\n'
        "  printf '{}\\n'; exit 0\n"
        'fi\n'
        'exit 1\n'
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return stub


def read_helper(toolbox: Path, stack: Path, key: str, env: dict[str, str]) -> str:
    """Invoke read_tf_output directly — the sharpest assertion for the
    fallback's unquoting/null/compaction behaviour."""
    result = subprocess.run(
        ["bash", "-c", 'source "$1" && read_tf_output "$2" "$3"',
         "_", str(toolbox / "lib" / "render-helpers.sh"), str(stack), key],
        text=True, capture_output=True, check=False,
        env={**os.environ, "TOFU": "true", **env},
    )
    if result.returncode != 0:
        raise SystemExit(f"read_tf_output {key} failed:\n{result.stdout}{result.stderr}")
    return result.stdout.rstrip("\n")


def check_read_tf_output_fallback(toolbox: Path, work: Path) -> None:
    stub_dir = work / "bin-tofu"
    stub_dir.mkdir()
    stub = write_stub_tofu(stub_dir)
    env = {"TOFU": str(stub)}
    stateless = work / "stateless-stack"
    stateless.mkdir()

    # The defect itself: a stateless dir must now refuse rather than write
    # the captured warning into the rendered file.
    out = work / "refusal.env"
    result = run_bundle(toolbox, "cloudsql-config", "--out", str(out),
                        "--data-dir", str(stateless), env=env)
    expect_failure(result, "empty or missing", "stateless dir must refuse")
    expect_failure(result, "Has the stack been applied", "stateless dir must say why")
    if out.exists():
        raise SystemExit("stateless dir wrote a file — captured-warning defect still present")

    # An absent OPTIONAL output yields empty: the line is omitted and no
    # warning text leaks into the file.
    ok = work / "partial.env"
    result = run_bundle(toolbox, "cloudsql-config", "--out", str(ok),
                        "--data-dir", str(stateless),
                        "--host-output", "present_string",
                        "--database-output", "absent_db", env=env)
    if result.returncode != 0 or not ok.exists():
        raise SystemExit(f"optional-missing render failed\n{result.stdout}{result.stderr}")
    content = ok.read_text()
    for line in ("host=10.114.0.3", "port=5432"):
        if line not in content:
            raise SystemExit(f"rendered file missing '{line}':\n{content}")
    if "database=" in content or "Warning" in content or "\x1b" in content:
        raise SystemExit(f"rendered file contains an absent-output leak:\n{content}")

    # Helper-level contract: string unquoted, non-string compacted to JSON,
    # null and absent both empty — byte-identical happy path to -raw.
    cases = {
        "present_string": "10.114.0.3",
        "present_number": "42",
        "present_object": '{"tls":true,"n":1}',
        "present_null": "",
        "absent_key": "",
    }
    for key, expected in cases.items():
        actual = read_helper(toolbox, stateless, key, env)
        if actual != expected:
            raise SystemExit(f"read_tf_output {key}: expected {expected!r}, got {actual!r}")

    # A sensitive output: `make output` prints the redaction marker, which is
    # not a value — the read must fall through to -json for the real value
    # rather than emit the marker into a rendered file.
    sensitive_stack = work / "sensitive-stack"
    sensitive_stack.mkdir()
    write_stub_stack(sensitive_stack, {"sensitive_token": "<sensitive>"})
    actual = read_helper(toolbox, sensitive_stack, "sensitive_token", env)
    if actual != "tok3n-real":
        raise SystemExit(f"sensitive redaction marker leaked as a value: {actual!r}")

    print("PASS renderer-cases read-tf-output-json-fallback")
    print("PASS renderer-negative read-tf-output-sensitive-marker")
    print("PASS renderer-negative read-tf-output-stateless")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="root-modules-renderer-") as temporary:
        work = Path(temporary)
        baseline = work / "baseline"
        candidate = work / "candidate"
        shutil.copytree(TOOLBOX, baseline)
        shutil.copytree(TOOLBOX, candidate)
        for toolbox in (baseline, candidate):
            syntax = subprocess.run(["bash", "-n", str(toolbox / RENDERER)], text=True, capture_output=True, check=False)
            if syntax.returncode != 0:
                raise SystemExit(syntax.stdout + syntax.stderr)
        expected = listing(baseline)
        if listing(candidate) != expected:
            raise SystemExit("unchanged operator bundles differ")
        comparator = Path(__file__).with_name("renderer_compare.py")
        unchanged = subprocess.run(
            ["python3", str(comparator), "--baseline", str(baseline), "--candidate", str(candidate)],
            text=True,
            capture_output=True,
            check=False,
        )
        if unchanged.returncode != 0:
            raise SystemExit(unchanged.stdout + unchanged.stderr)
        candidate_script = candidate / RENDERER
        candidate_script.write_text(candidate_script.read_text().replace('"keycloak:aws-eks-keycloak:', '"keycloak-mutated:aws-eks-keycloak:', 1))
        mutated = subprocess.run(
            ["python3", str(comparator), "--baseline", str(baseline), "--candidate", str(candidate)],
            text=True,
            capture_output=True,
            check=False,
        )
        if mutated.returncode == 0 or "bytes differ" not in (mutated.stdout + mutated.stderr):
            raise SystemExit("operator renderer mutation was not rejected by the independent comparator")
        print("PASS renderer-cases independent-baseline-candidate")
        print("PASS renderer-negative catalog-mutation")
        gcp_work = work / "gcp"
        gcp_work.mkdir()
        check_cloudsql_bundles(baseline, gcp_work)
        check_read_tf_output_fallback(baseline, gcp_work)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
