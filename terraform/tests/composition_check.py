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

"""Plan consumer resources with mocks and render their real Gateway chart."""

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "composition-aws": ("aws-eks", None),
    "composition-gcp": ("gcp-gke", None),
    "composition-route-drift": ("aws-eks", "route"),
    "composition-hostname-drift": ("aws-eks", "hostname"),
}

ASSERTIONS = '''
run "composition" {
  command = plan
  assert {
    condition = module.keycloak.public_url == "https://${var.public_hostname}"
    error_message = "Keycloak public hostname drifted"
  }
  assert {
    condition = toset([for match in kubernetes_manifest.route_well_known.manifest.spec.rules[0].matches : match.path.value]) == toset(module.app_links.paths) && alltrue([for match in kubernetes_manifest.route_well_known.manifest.spec.rules[0].matches : match.path.type == "Exact"])
    error_message = "well-known exact-match paths drifted"
  }
  assert {
    condition = kubernetes_manifest.route_keycloak.manifest.spec.rules[0].matches[0].path.type == "PathPrefix" && kubernetes_manifest.route_keycloak.manifest.spec.rules[0].matches[0].path.value == "/" && length(kubernetes_manifest.route_keycloak.manifest.spec.rules[0].matches) == 1
    error_message = "Keycloak prefix drifted"
  }
  assert {
    condition = alltrue([for route in [kubernetes_manifest.route_well_known.manifest, kubernetes_manifest.route_keycloak.manifest] : route.spec.parentRefs == [{name = module.gateway.gateway_name, namespace = module.gateway.gateway_namespace}] && route.spec.hostnames == [var.public_hostname]])
    error_message = "route parent or hostname drifted"
  }
  assert {
    condition = kubernetes_manifest.route_well_known.manifest.spec.rules[0].backendRefs[0].name == module.static_responder.service_name && kubernetes_manifest.route_well_known.manifest.spec.rules[0].backendRefs[0].port == module.static_responder.service_port && kubernetes_manifest.route_keycloak.manifest.spec.rules[0].backendRefs[0].name == module.keycloak.keycloak_service_name && kubernetes_manifest.route_keycloak.manifest.spec.rules[0].backendRefs[0].port == module.keycloak.keycloak_service_port
    error_message = "route backend drifted"
  }
}
'''


def resources(module):
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from resources(child)


def run_case(name, tofu, work, run):
    cloud, negative = CASES[name]
    example = cloud + "-gateway-keycloak-app-links"
    example_root = work / "terraform" / "examples" / example
    (work / "terraform").mkdir()
    (work / "terraform" / "modules").symlink_to(ROOT / "terraform" / "modules", target_is_directory=True)
    shutil.copytree(ROOT / "terraform" / "examples" / example, example_root)
    if negative:
        path = example_root / "main.tf"
        source = path.read_text()
        original, changed = {
            "route": ('path = { type = "Exact", value = path }', 'path = { type = "Exact", value = "/drift" }'),
            "hostname": ('public_hostname  = var.public_hostname', 'public_hostname  = "drift.example.test"'),
        }[negative]
        assert source.count(original) == 1, f"{negative} drift fixture no longer matches example"
        path.write_text(source.replace(original, changed))
    provider = "aws" if cloud == "aws-eks" else "google"
    mocks = "".join('mock_provider "' + item + '" {}\n' for item in (provider, "helm", "kubernetes", "cloudflare"))
    (example_root / "composition.tftest.hcl").write_text('variables { public_hostname = "rendered.example.test" }\n' + mocks + ASSERTIONS)
    init = run([tofu, "init", "-backend=false", "-input=false", "-no-color"], example_root)
    if init.returncode:
        return ["composition initialization failed: " + (init.stdout + init.stderr)[-3000:]]
    tested = run([tofu, "test", "-json", "-verbose", "-no-color"], example_root)
    events = [json.loads(line) for line in tested.stdout.splitlines() if line.startswith("{")]
    if negative:
        errors = [event.get("diagnostic", {}) for event in events if event.get("type") == "diagnostic" and event.get("diagnostic", {}).get("severity") == "error"]
        expected = {"route": "well-known exact-match paths drifted", "hostname": "Keycloak public hostname drifted"}[negative]
        if tested.returncode and len(errors) == 1 and expected in errors[0].get("detail", ""):
            print(f"PASS composition-negative actual {negative} mutation rejected by consumer test")
            return []
        return [f"{negative} mutation must fail only the intended assertion: " + (tested.stdout + tested.stderr)[-4000:]]
    if tested.returncode:
        return ["composition test failed: " + (tested.stdout + tested.stderr)[-6000:]]
    plans = [event["test_plan"] for event in events if event.get("type") == "test_plan"]
    if len(plans) != 1:
        return ["composition did not emit exactly one verbose plan"]
    plan = plans[0]
    planned = list(resources(plan["planned_values"]["root_module"]))
    assert not any(item["type"].startswith("kubernetes_secret") for item in planned), "consumer must not create credential Secrets"
    realm_files = list(example_root.glob("realm/*.json"))
    assert len(realm_files) == 1 and realm_files[0].name == "realm.json", "consumer must have one realm file"
    imports = [item["values"]["data"]["realm.json"] for item in planned if item["type"] == "kubernetes_config_map" and item["name"] == "realm_import"]
    assert imports == [realm_files[0].read_text()], "Keycloak must import the sole realm file"
    keycloak = next(item["values"] for item in planned if item["type"] == "helm_release" and item["address"].startswith("module.keycloak.") and item["name"] == "keycloak")
    cli_environment = json.loads(keycloak["values"][-1])["keycloakConfigCli"]["extraEnvVars"]
    assert cli_environment == [
        {"name": "IMPORT_VARSUBSTITUTION_ENABLED", "value": "true"},
        {"name": "PUBLIC_ORIGIN", "value": "https://" + plan["variables"]["public_hostname"]["value"]},
    ], "realm importer must use the consumer hostname"
    releases = [item["values"] for item in planned if item["type"] == "helm_release" and item["address"].startswith("module.gateway.") and item["name"] == "configuration"]
    assert len(releases) == 1, "expected one actual Gateway configuration release"
    release = releases[0]
    chart = str((example_root / release["chart"]).resolve())
    proof = example_root / "render"
    proof.mkdir()
    config = {
        "terraform": {"required_providers": {"helm": {"source": "hashicorp/helm", "version": "~> 2.0"}}},
        "provider": {"helm": {"kubernetes": {"host": "https://127.0.0.1:1", "insecure": True}}},
        "data": {"helm_template": {"gateway": {"name": release["name"], "namespace": release["namespace"], "chart": chart, "values": release["values"], "validate": False}}},
        "output": {"objects": {"value": '${[for document in split("\\n---", data.helm_template.gateway.manifest) : yamldecode(document) if trimspace(document) != ""]}'}},
    }
    (proof / "main.tf.json").write_text(json.dumps(config))
    init = run([tofu, "init", "-backend=false", "-input=false", "-no-color"], proof)
    rendered = run([tofu, "plan", "-refresh=false", "-input=false", "-no-color", "-out=proof.plan"], proof) if not init.returncode else init
    if rendered.returncode:
        return ["Gateway chart proof failed: " + (rendered.stdout + rendered.stderr)[-4000:]]
    shown = run([tofu, "show", "-json", "proof.plan"], proof)
    if shown.returncode:
        return ["Gateway chart proof JSON failed: " + shown.stderr[-2000:]]
    objects = json.loads(shown.stdout)["planned_values"]["outputs"]["objects"]["value"]
    gateways = [item for item in objects if item.get("kind") == "Gateway"]
    assert len(gateways) == 1, "expected exactly one rendered Gateway"
    gateway = gateways[0]
    listeners = gateway["spec"]["listeners"]
    assert len(listeners) == 1 and listeners[0]["protocol"] == "HTTPS" and listeners[0]["port"] == 443, "expected one HTTPS listener"
    assert listeners[0]["hostname"] == plan["variables"]["public_hostname"]["value"], "listener hostname drifted"
    routes = [item["values"]["manifest"] for item in planned if item["type"] == "kubernetes_manifest"]
    assert len(routes) == 2 and all(route["kind"] == "HTTPRoute" for route in routes), "consumer must own exactly two HTTPRoutes"
    expected_parent = {"name": gateway["metadata"]["name"], "namespace": gateway["metadata"]["namespace"]}
    assert all(route["spec"]["parentRefs"] == [expected_parent] for route in routes), "rendered Gateway and route parents differ"
    assert not any(item["kind"].endswith("Route") for item in objects), "Gateway module must not render routes"
    print(f"PASS composition-chart-render {example} HTTPS listener and both consumer routes")
    return []
