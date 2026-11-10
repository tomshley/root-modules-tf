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

"""Render both Gateway charts with planned values through the Helm provider."""

import copy
import json
import os
import re
from pathlib import Path

from gateway_cases import resources

GATEWAY_RESOURCE = "gateways.gateway.networking.k8s.io"


def check_label_keys(manifest: str) -> None:
    def unique(pairs):
        keys = [key for key, _ in pairs]
        assert len(keys) == len(set(keys)), "duplicate label keys: " + str(keys)
        return dict(pairs)

    lines = manifest.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r"^( *)labels:(.*)$", line)
        if match is None:
            continue
        if match[2].strip():
            assert isinstance(json.loads(match[2], object_pairs_hook=unique), dict), "labels must be a map"
            continue
        pairs = []
        for child in lines[index + 1:]:
            if not child.strip() or child.lstrip().startswith("#"):
                continue
            if len(child) - len(child.lstrip()) <= len(match[1]):
                break
            pairs.append((child.strip().split(":", 1)[0].strip("'\""), None))
        unique(pairs)


def check_rendered(proof: dict, configuration: dict, controller: dict) -> None:
    for name in ("configuration", "controller"):
        objects = proof[name]
        check_label_keys(proof["manifests"][name])
        assert objects and all(isinstance(obj, dict) and "kind" in obj for obj in objects), name + " must render objects"
        assert all(obj["kind"] != "CustomResourceDefinition" and not obj["kind"].endswith("Route") for obj in objects), name + " must not render CRDs or Routes"
    objects = {obj["kind"]: obj for obj in proof["configuration"]}
    assert len(proof["configuration"]) == 9 and set(objects) == {
        "GatewayClass", "Gateway", "EnvoyProxy", "ClientTrafficPolicy", "NetworkPolicy",
        "ServiceAccount", "Role", "RoleBinding", "Job",
    }, "configuration must render Gateway infrastructure and wait Job/RBAC only"
    expected = json.loads(configuration["values"][0])
    for obj in expected["objects"]:
        assert objects[obj["kind"]] == obj, obj["kind"] + " rendering changed"
    assert expected["timeout"] == max(1, configuration["timeout"] - 30) < configuration["timeout"]
    assert "readOnlyRootFilesystem" not in objects["EnvoyProxy"]["spec"]["provider"]["kubernetes"]["envoyDeployment"]["container"]["securityContext"]
    job = objects["Job"]
    assert job["metadata"]["name"] == expected["waitName"]
    assert job["metadata"]["annotations"] == {
        "helm.sh/hook": "post-install,post-upgrade",
        "helm.sh/hook-delete-policy": "before-hook-creation,hook-succeeded",
    }
    selector = objects["NetworkPolicy"]["spec"]["podSelector"]["matchLabels"]
    wait_labels = job["spec"]["template"]["metadata"].get("labels") or {}
    proxy_labels = objects["EnvoyProxy"]["spec"]["provider"]["kubernetes"]["envoyDeployment"]["pod"]["labels"]
    assert all(proxy_labels.get(key) == value for key, value in selector.items()), "policy must select proxy pods"
    assert not all(wait_labels.get(key) == value for key, value in selector.items()), "policy must never select the readiness Job"
    pod = job["spec"]["template"]["spec"]
    assert pod["serviceAccountName"] == objects["ServiceAccount"]["metadata"]["name"] == expected["waitName"]
    assert pod["securityContext"] == {
        "runAsNonRoot": True, "runAsUser": 65532, "runAsGroup": 65532, "seccompProfile": {"type": "RuntimeDefault"},
    }
    container = pod["containers"][0]
    assert container["image"] == expected["waitImage"]
    assert container["command"] == ["kubectl"]
    assert container["args"] == [
        "wait", "--namespace=" + configuration["namespace"], "--for=condition=Programmed",
        "--timeout=" + str(expected["timeout"]) + "s", GATEWAY_RESOURCE + "/" + expected["gateway"],
    ]
    assert job["spec"]["activeDeadlineSeconds"] == expected["timeout"] and job["spec"]["backoffLimit"] == 0
    assert re.search(r"(?m)^\s*activeDeadlineSeconds: " + str(expected["timeout"]) + r"\s*$", proof["manifests"]["configuration"]), "Job deadline must render as a decimal integer"
    role = objects["Role"]
    assert role["metadata"]["name"] == expected["waitName"]
    resource, group = GATEWAY_RESOURCE.split(".", 1)
    assert role["rules"] == [{
        "apiGroups": [group], "resources": [resource],
        "resourceNames": [expected["gateway"]], "verbs": ["get", "watch", "list"],
    }]
    binding = objects["RoleBinding"]
    assert binding["roleRef"] == {"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": expected["waitName"]}
    assert binding["subjects"] == [{"kind": "ServiceAccount", "name": expected["waitName"], "namespace": configuration["namespace"]}]
    controller_objects = proof["controller"]
    assert {"Deployment", "Service", "ServiceAccount", "ClusterRole", "ClusterRoleBinding", "Role", "RoleBinding", "ConfigMap", "PodDisruptionBudget", "Job"} <= {obj["kind"] for obj in controller_objects}
    deployment = next(obj for obj in controller_objects if obj["kind"] == "Deployment")
    assert deployment["metadata"]["name"] == "envoy-gateway" and deployment["spec"]["replicas"] == 2
    gateway_container = next(container for container in deployment["spec"]["template"]["spec"]["containers"] if container["name"] == "envoy-gateway")
    assert gateway_container["image"] == json.loads(controller["values"][0])["global"]["images"]["envoyGateway"]["image"]
    for obj in controller_objects:
        if obj["kind"] in ("ClusterRole", "ClusterRoleBinding"):
            assert obj["metadata"]["name"].startswith(controller["name"]), "cluster RBAC must be release-isolated"
    assert proof["controller_config"]["gateway"]["controllerName"] == objects["GatewayClass"]["spec"]["controllerName"]


def chart_problems(tofu: str, work: Path, planned: dict, run) -> list[str]:
    releases = {resource["name"]: resource["values"] for resource in resources(planned["root_module"]) if resource["type"] == "helm_release"}
    controller, configuration = releases["controller"], releases["configuration"]
    if (controller["repository"], controller["chart"], controller["version"]) != ("oci://docker.io/envoyproxy", "gateway-helm", "v1.9.3"):
        return ["chart proof must use the pinned official Envoy Gateway chart"]
    fixture = ""
    for name, release in (("controller", controller), ("configuration", configuration)):
        attributes = {key: release[key] for key in ("chart", "name", "namespace", "values")}
        if name == "controller":
            attributes.update({key: release[key] for key in ("repository", "version")})
        attributes.update({"validate": False, "kube_version": "1.30.0", "include_crds": True})
        fixture += f'data "helm_template" "gateway_{name}" {{\n'
        fixture += "\n".join(f"  {key} = {json.dumps(value)}" for key, value in attributes.items()) + "\n}\n"
        fixture += f'locals {{ gateway_{name}_objects = [for document in split("\\n---\\n", data.helm_template.gateway_{name}.manifest) : yamldecode(document) if trimspace(document) != ""] }}\n'
    fixture += """
output "gateway_chart_proof" {
  value = {
    manifests = {
      controller = data.helm_template.gateway_controller.manifest
      configuration = data.helm_template.gateway_configuration.manifest
    }
    controller = local.gateway_controller_objects
    configuration = local.gateway_configuration_objects
    controller_config = yamldecode(one([for object in local.gateway_controller_objects : object.data["envoy-gateway.yaml"] if object.kind == "ConfigMap" && object.metadata.name == "envoy-gateway-config"]))
  }
}
"""
    (work / "gateway-chart-proof.tf").write_text(fixture)
    rendered = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=gateway-chart-proof.plan"], work)
    if rendered.returncode:
        return ["Gateway chart rendering failed: " + rendered.stdout + rendered.stderr]
    shown = run([tofu, "show", "-json", "gateway-chart-proof.plan"], work)
    if shown.returncode:
        return ["could not inspect Gateway chart rendering: " + shown.stderr]
    proof = json.loads(shown.stdout)["planned_values"].get("outputs", {}).get("gateway_chart_proof", {}).get("value")
    if proof is None:
        return ["Gateway charts must produce known manifests at plan time"]
    try:
        check_rendered(proof, configuration, controller)
    except (AssertionError, KeyError, StopIteration, TypeError, ValueError) as error:
        return ["Gateway chart assertions failed: " + str(error)]
    duplicate = "metadata:\n  labels:\n    example: first\n    example: second\n"
    wrong_resource = copy.deepcopy(proof)
    job = next(obj for obj in wrong_resource["configuration"] if obj["kind"] == "Job")
    job["spec"]["template"]["spec"]["containers"][0]["args"][-1] = "gateway.networking.k8s.io/" + json.loads(configuration["values"][0])["gateway"]
    for name, mutation in [
        ("empty", {}),
        ("wrong-wait-resource", wrong_resource),
        *[(f"duplicate-{chart}-labels", {**proof, "manifests": {**proof["manifests"], chart: duplicate}})
          for chart in ("configuration", "controller")],
        ("missing-hook", {**proof, "configuration": [obj for obj in proof["configuration"] if obj["kind"] != "Job"]}),
        ("crd", {**proof, "controller": proof["controller"] + [{"kind": "CustomResourceDefinition"}]}),
        ("route", {**proof, "controller": proof["controller"] + [{"kind": "HTTPRoute"}]}),
    ]:
        try:
            check_rendered(mutation, configuration, controller)
        except (AssertionError, KeyError, StopIteration, TypeError):
            continue
        return ["Gateway chart guard missed " + name]
    if os.environ.get("GATEWAY_RENDER_OUTPUT"):
        destination = Path(os.environ["GATEWAY_RENDER_OUTPUT"])
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "chart-proof.json").write_text(json.dumps(proof))
    print("PASS gateway-chart-proof local+pinned=v1.9.3 hook-Job/RBAC no-CRDs no-Routes")
    print("PASS gateway-chart-guard empty wrong-wait-resource missing-hook crd route duplicate-configuration-labels duplicate-controller-labels")
    if configuration["timeout"] == 1000030:
        print("PASS gateway-chart-large-timeout deadline=1000000 --timeout=1000000s")
    return []
