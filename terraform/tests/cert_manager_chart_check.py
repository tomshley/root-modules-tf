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

"""Render the official and local cert-manager charts without a Kubernetes API."""

from __future__ import annotations

import json
from pathlib import Path

from cert_manager_cases import DIGESTS, resources


def check_rendered(proof: dict, releases: dict, replicas: int) -> None:
    expected = json.loads(releases["configuration"]["values"][0])["issuer"]
    assert proof["configuration"] == [expected], "the local chart must render exactly the planned ClusterIssuer"
    objects = proof["controller"]
    assert objects and all(isinstance(obj, dict) and "kind" in obj for obj in objects)
    assert not {"ClusterIssuer", "Issuer", "Certificate", "Gateway", "Secret"} & {obj["kind"] for obj in objects}, "the controller chart must not create workload custom resources or Secrets"
    crds = [obj for obj in objects if obj["kind"] == "CustomResourceDefinition"]
    assert len(crds) == 6 and {obj["spec"]["group"] for obj in crds} == {"cert-manager.io", "acme.cert-manager.io"}, "only cert-manager's six CRDs may be installed"
    assert all(obj["metadata"]["annotations"]["helm.sh/resource-policy"] == "keep" for obj in crds)
    assert proof["controller_config"]["gatewayAPI"]["enabled"] is True
    deployments = [obj for obj in objects if obj["kind"] == "Deployment"]
    controller = next(obj for obj in deployments if obj["metadata"]["name"] == "cert-manager")
    assert controller["spec"]["replicas"] == replicas, "later extra values must take precedence"
    containers = [container for obj in objects if obj["kind"] in {"Deployment", "Job"} for container in obj["spec"]["template"]["spec"]["containers"]]
    expected_images = {
        component: f"quay.io/jetstack/cert-manager-{component}:v1.21.3@{digest}"
        for component, digest in DIGESTS.items()
    }
    assert {container["image"] for container in containers} == {image for component, image in expected_images.items() if component != "acmesolver"}, "all deployed chart images must match registry digest pins"
    main = controller["spec"]["template"]["spec"]["containers"][0]
    assert "--acme-http01-solver-image=" + expected_images["acmesolver"] in main["args"]
    assert "--cluster-resource-namespace=" + releases["controller"]["namespace"] in main["args"]


def chart_problems(tofu: str, work: Path, planned: dict, run, replicas: int) -> list[str]:
    releases = {resource["name"]: resource["values"] for resource in resources(planned["root_module"]) if resource["type"] == "helm_release"}
    fixture = ""
    for name, release in releases.items():
        attributes = {key: release[key] for key in ("chart", "name", "namespace", "values")}
        if name == "controller":
            attributes.update({key: release[key] for key in ("repository", "version")})
        attributes.update({"validate": False, "kube_version": "1.35.0", "include_crds": True})
        fixture += f'data "helm_template" "cert_manager_{name}" {{\n'
        fixture += "\n".join(f"  {key} = {json.dumps(value)}" for key, value in attributes.items()) + "\n}\n"
        fixture += f'locals {{ cert_manager_{name}_objects = [for document in split("\\n---\\n", data.helm_template.cert_manager_{name}.manifest) : yamldecode(document) if trimspace(document) != ""] }}\n'
    fixture += '''output "cert_manager_chart_proof" {
  value = {
    controller = local.cert_manager_controller_objects
    configuration = local.cert_manager_configuration_objects
    controller_config = yamldecode(one([for object in local.cert_manager_controller_objects : object.data["config.yaml"] if object.kind == "ConfigMap" && object.metadata.name == "cert-manager"]))
  }
}
'''
    (work / "cert-manager-chart-proof.tf").write_text(fixture)
    rendered = run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=chart-proof.plan"], work)
    if rendered.returncode:
        return ["chart rendering failed: " + rendered.stdout + rendered.stderr]
    shown = run([tofu, "show", "-json", "chart-proof.plan"], work)
    if shown.returncode:
        return ["could not inspect chart rendering: " + shown.stderr]
    proof = json.loads(shown.stdout)["planned_values"].get("outputs", {}).get("cert_manager_chart_proof", {}).get("value")
    if proof is None:
        return ["charts must render known objects without a Kubernetes API"]
    try:
        check_rendered(proof, releases, replicas)
    except (AssertionError, KeyError, StopIteration, TypeError, ValueError) as error:
        return ["chart assertions failed: " + str(error)]
    print("PASS cert-manager-chart-render " + work.name)
    return []
