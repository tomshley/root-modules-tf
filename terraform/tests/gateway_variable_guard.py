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

"""Reject routing inputs, with exact exceptions for existing public contracts.

The route/backend/rewrite/redirect tokens match anywhere in a variable name.
URL-path names match an underscore-delimited path, paths, path_prefix or
path_prefixes component, including names such as public_path and path_pattern.
Nested object attributes are not module variables. Strings and comments do not
declare variables.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
EXCEPTIONS = {
    ("cloudflare-redirect-domain", "redirect_target"): "Existing Cloudflare edge-redirect product.",
    ("cloudflare-redirect-domain", "redirect_code"): "Existing Cloudflare edge-redirect product.",
    ("cloudflare-redirect-domain", "preserve_path"): "Existing Cloudflare edge-redirect product.",
    ("cloudflare-website-acceleration", "canonical_redirect"): "Existing Cloudflare edge-redirect product.",
    ("aws-keycloak", "realm_json_path"): "Existing filesystem path, not a URL path.",
    ("aws-eks-keycloak", "realm_json_path"): "Existing filesystem path, not a URL path.",
    ("gcp-keycloak", "realm_json_path"): "Existing filesystem path, not a URL path.",
    ("gcp-gke-keycloak", "realm_json_path"): "Existing filesystem path, not a URL path.",
    ("k8s-keycloak", "realm_json_path"): "Existing filesystem path, not a URL path.",
}
ROUTING_NAME = re.compile(r"route|backend|rewrite|redirect|(?:^|_)(?:paths?|path_prefix(?:es)?)(?:_|$)", re.I)
DECLARATION = re.compile(r'\b(?P<keyword>variable)\s+"(?P<name>[^"]+)"\s*\{')


def declarations(source: str, live_hcl: Callable) -> set[str]:
    live = live_hcl(source)
    code = live_hcl(live, blank=True)
    return {
        match["name"]
        for match in DECLARATION.finditer(live)
        if code[match.start("keyword"):match.end("keyword")] == "variable"
    }


def violations(module: str, names: set[str]) -> set[tuple[str, str]]:
    return {
        (module, name) for name in names
        if ROUTING_NAME.search(name) and (module, name) not in EXCEPTIONS
    }


def check_gateway_variable_guard(live_hcl: Callable) -> None:
    samples = {
        '': set(),
        'variable "listeners" { type = map(object({ allowed_route_namespaces = string })) }': {"listeners"},
        '# variable "route" {}\n/* variable "backend" {} */\nvariable "name" {}': {"name"},
        'locals { sample = <<EOT\nvariable "redirect" {}\nEOT\n}': set(),
        'locals { sample = "variable \\"rewrite\\" {}" }': set(),
    }
    for source, expected in samples.items():
        if declarations(source, live_hcl) != expected:
            raise SystemExit("routing variable guard misread a declaration")
    if violations("synthetic", set()) or violations("synthetic", {"listeners", "namespace"}):
        raise SystemExit("routing variable guard rejected an empty or valid interface")
    forbidden = {
        "route", "routes", "http_routes", "backend", "backend_service", "rewrite",
        "canonical_redirect", "path", "paths", "public_path", "path_prefix",
        "public_path_prefix", "public_path_prefixes", "path_pattern",
    }
    for name in sorted(forbidden):
        source = 'variable "' + name + '" { type = string }'
        if violations("synthetic", declarations(source, live_hcl)) != {("synthetic", name)}:
            raise SystemExit(f"routing variable guard accepted mutation: {name}")
    for module, name in EXCEPTIONS:
        if violations(module, {name}) or not violations("synthetic", {name}):
            raise SystemExit(f"routing variable guard has a non-exact exception: {module}.{name}")
    print("PASS gateway-routing-guard empty-valid-comment-string-and-heredoc")
    print("PASS gateway-routing-guard rejects-new-variables-and-copied-exceptions")

    found: set[tuple[str, str]] = set()
    failures: set[tuple[str, str]] = set()
    modules = ROOT / "terraform/modules"
    for path in sorted(modules.rglob("*.tf")):
        if ".terraform" in path.parts:
            continue
        module = path.relative_to(modules).parts[0]
        names = declarations(path.read_text(), live_hcl)
        found.update((module, name) for name in names)
        failures.update(violations(module, names))
    stale = set(EXCEPTIONS) - found
    if stale:
        raise SystemExit(f"routing variable guard has stale exceptions: {sorted(stale)}")
    if failures:
        raise SystemExit(f"forbidden routing module variables: {sorted(failures)}")
    print(f"PASS gateway-routing-guard repository exact-exceptions={len(EXCEPTIONS)}")


def check_gateway_mirrors(live_hcl: Callable) -> None:
    modules = ROOT / "terraform/modules"
    base_source = (modules / "k8s-gateway/variables.tf").read_text()
    base = declarations(base_source, live_hcl)
    outputs = set(re.findall(r'output "([^"]+)"', (modules / "k8s-gateway/outputs.tf").read_text()))
    additions = {
        "aws-eks-gateway": {"nlb_scheme", "nlb_eip_allocations", "nlb_cross_zone", "nlb_target_type", "nlb_additional_resource_tags", "tags"},
        "gcp-gke-gateway": {"load_balancer_ip", "internal"},
    }
    for module, allowed in additions.items():
        variables = (modules / module / "variables.tf").read_text()
        def matches(source: str) -> bool:
            return source.startswith(base_source) and declarations(source, live_hcl) == base | allowed
        if not matches(variables):
            raise SystemExit(f"gateway adapter variables differ from base plus allow-list: {module}")
        wiring = live_hcl((modules / module / "resources.tf").read_text())
        for name in base - {"service_annotations"}:
            if not re.search(rf'\b{re.escape(name)}\s*=\s*var\.{re.escape(name)}\b', wiring):
                raise SystemExit(f"gateway adapter does not forward {module}.{name}")
        if not re.search(r'service_annotations\s*=\s*(?:\{ for key, value in )?merge\(var\.service_annotations, local\.attachment_annotations\)', wiring):
            raise SystemExit(f"gateway adapter annotation mapping changed: {module}")
        if re.search(r'\b(resource|data)\s+"', wiring):
            raise SystemExit(f"gateway adapter declares resources or lookups: {module}")
        forwarding = live_hcl((modules / module / "outputs.tf").read_text())
        if set(re.findall(r'output "([^"]+)"', forwarding)) != outputs:
            raise SystemExit(f"gateway adapter output set differs: {module}")
        for name in outputs:
            conditions = ""
            if name == "gateway_name":
                base_outputs = live_hcl((modules / "k8s-gateway/outputs.tf").read_text())
                conditions = re.escape("\n".join(re.findall(r"  precondition \{[\s\S]*?\n  \}", base_outputs)))
            if not re.search(rf'output "{name}"\s*\{{\s*value\s*=\s*module\.gateway\.{name}\s*{conditions}\s*\}}', forwarding):
                raise SystemExit(f"gateway adapter output is not passed through: {module}.{name}")
        if matches(variables + '\nvariable "backend" { type = string }\n'):
            raise SystemExit("gateway mirror guard accepted an extra input")
        print(f"PASS gateway-adapter-mirror {module} inputs={len(base | allowed)} outputs={len(outputs)}")
