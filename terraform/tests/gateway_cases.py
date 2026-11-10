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

"""Gateway contracts and rendered Helm-value assertions."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = {
    "name": "public-gateway", "namespace": "gateway-system", "chart_version": "v1.9.3",
    "listeners": {"public": {"hostname": "login.example.test", "tls_secret_name": "public-example-tls"}},
}
CASES: dict[str, dict] = {}


def case(name: str, changes: dict | None = None, diagnostic: str | None = None, module: str = "k8s-gateway") -> None:
    inputs = copy.deepcopy(DEFAULT)
    inputs.update(changes or {})
    CASES[name] = {"module": module, "inputs": inputs, "diagnostic": diagnostic}


def listener_case(name: str, changes: dict, diagnostic: str | None = None, **inputs) -> None:
    listener = copy.deepcopy(DEFAULT["listeners"]["public"])
    listener.update(changes)
    case(name, {"listeners": {"public": listener}, **inputs}, diagnostic)


case("gateway-default")
case("gateway-requests-only", {"resources_requests_cpu": "100m"})
case("gateway-large-timeout", {"helm_timeout": 1000030, "network_policy_enabled": True})
case("gateway-controller-name-collision", {"name": "envoy-gateway"})
case("gateway-other-namespace", {"namespace": "other-gateway-system"})
case("gateway-long-name", {"name": "a" * 53})
case("gateway-mixed-tls-sources", {"listeners": {
    "issuer": {"hostname": "one.example.test", "tls_issuer": {"name": "public-ca"}},
    "secret": {"hostname": "two.example.test", "tls_secret_name": "public-example-tls"},
}}, "When any listener uses tls_issuer, every HTTPS listener must use tls_issuer")
case("gateway-shared-port-protocol", {"listeners": {
    "https": {"hostname": "login.example.test", "tls_secret_name": "public-example-tls"},
    "tls": {"hostname": "passthrough.example.test", "protocol": "TLS"},
}}, "Listeners on a shared port must use the same protocol.")
case("gateway-duplicate-listeners", {"listeners": {
    "one": DEFAULT["listeners"]["public"], "two": DEFAULT["listeners"]["public"],
}}, "Listener port, protocol and hostname combinations must be unique.")
case("gateway-nodeport", {"service_type": "NodePort"})
case("gateway-empty", {"listeners": {}}, "listeners must contain between 1 and 64 entries.")
case("gateway-name", {"name": "Bad_Name"}, "name must be a DNS-1035 label of at most 53 characters.")
case("gateway-namespace", {"namespace": "Bad_Name"}, "namespace must be a DNS label.")
case("gateway-version", {"chart_version": "latest"}, "chart_version must be v1.9.3")
case("gateway-service-type", {"service_type": "ClusterIP"}, "service_type must be LoadBalancer or NodePort.")
case("gateway-replicas", {"replicas": 0}, "replicas must be a positive integer.")
case("gateway-pdb-negative", {"pdb_min_available": -1}, "pdb_min_available must be a non-negative integer smaller than replicas.")
case("gateway-pdb-equal", {"pdb_min_available": 2}, "pdb_min_available must be a non-negative integer smaller than replicas.")
for timeout in (1, 2, 31):
    for module in ("k8s-gateway", "aws-eks-gateway", "gcp-gke-gateway"):
        case(f"{module}-timeout-{timeout}", {"helm_timeout": timeout},
             "helm_timeout must be an integer of at least 2 seconds." if timeout == 1 else None, module)
case("aws-gateway-empty-eips", {"nlb_eip_allocations": [], "nlb_scheme": "internet-facing"},
     "nlb_eip_allocations must contain at least one EIP allocation identifier.", "aws-eks-gateway")
case("gateway-timeout", {"helm_timeout": 0}, "helm_timeout must be an integer of at least 2 seconds.")
case("gateway-listener-name", {"listeners": {"Bad_Name": DEFAULT["listeners"]["public"]}}, "Listener names must be DNS labels.")
listener_case("gateway-hostname", {"hostname": "https://login.example.test"}, "Listener hostnames must be valid DNS hostnames.")
listener_case("gateway-protocol", {"protocol": "TCP"}, "Listener protocol must be HTTPS, HTTP or TLS.")
listener_case("gateway-port", {"port": 65536}, "Listener ports must be integers between 1 and 65535.")
listener_case("gateway-port-fraction", {"port": 1.5}, "Listener ports must be integers between 1 and 65535.")
listener_case("gateway-zero-tls", {"tls_secret_name": None}, "HTTPS listeners require exactly one of tls_secret_name or tls_issuer.")
listener_case("gateway-two-tls", {"tls_issuer": {"name": "public-ca"}}, "HTTPS listeners require exactly one of tls_secret_name or tls_issuer.")
listener_case("gateway-secret-empty", {"tls_secret_name": ""}, "tls_secret_name must be a DNS-1123 subdomain of at most 253 characters.")
listener_case("gateway-http-credentials", {"protocol": "HTTP"}, "Only HTTPS listeners may specify termination credentials.")
listener_case("gateway-issuer-kind", {"tls_secret_name": None, "tls_issuer": {"name": "public-ca", "kind": "Other"}}, "tls_issuer needs a non-empty name and kind ClusterIssuer or Issuer.")
listener_case("gateway-issuer-empty", {"tls_secret_name": None, "tls_issuer": {"name": ""}}, "tls_issuer needs a non-empty name and kind ClusterIssuer or Issuer.")
listener_case("gateway-route-namespaces", {"allowed_route_namespaces": "Other"}, "allowed_route_namespaces must be Same, All or Selector.")
listener_case("gateway-selector-missing", {"allowed_route_namespaces": "Selector"}, "Selector requires a non-empty allowed_route_selector")
listener_case("gateway-selector-empty", {"allowed_route_namespaces": "Selector", "allowed_route_selector": {}}, "Selector requires a non-empty allowed_route_selector")
listener_case("gateway-selector-unused", {"allowed_route_selector": {"team": "public"}}, "Selector requires a non-empty allowed_route_selector")
listener_case("gateway-all-policy", {"allowed_route_namespaces": "All"}, "network_policy_enabled cannot be combined with All route namespaces.", network_policy_enabled=True)
listener_case("gateway-all", {"allowed_route_namespaces": "All"})
listener_case("gateway-http", {"protocol": "HTTP", "port": 80, "tls_secret_name": None})
listener_case("gateway-tls", {"protocol": "TLS", "tls_secret_name": None})
listener_case("gateway-wildcard", {"hostname": "*.example.test"})
listener_case("gateway-cluster-issuer", {"tls_secret_name": None, "tls_issuer": {"name": "public-ca"}})
listener_case("gateway-issuer", {"tls_secret_name": None, "tls_issuer": {"name": "public-ca", "kind": "Issuer"}})
listener_case("gateway-policy-same", {}, network_policy_enabled=True)
listener_case("gateway-policy-selector", {"allowed_route_namespaces": "Selector", "allowed_route_selector": {"access": "public"}}, network_policy_enabled=True, labels={"team": "public"})
for suffix, second in [("name", {"name": "other-ca"}), ("kind", {"name": "public-ca", "kind": "Issuer"})]:
    case("gateway-mixed-issuer-" + suffix, {"listeners": {
        "one": {"hostname": "one.example.test", "tls_issuer": {"name": "public-ca"}},
        "two": {"hostname": "two.example.test", "tls_issuer": second},
    }}, "All issuer-backed listeners must use the same issuer name and kind.")
case("gateway-shared-issuer", {"listeners": {
    "one": {"hostname": "one.example.test", "tls_issuer": {"name": "public-ca"}},
    "two": {"hostname": "two.example.test", "tls_issuer": {"name": "public-ca"}},
}})
case("gateway-overrides", {
    "extra_helm_values": ["deployment:\n  replicas: 3\n"],
    "resources_requests_cpu": "100m", "resources_limits_memory": "256Mi",
    "labels": {"team": "public"}, "service_annotations": {"example.test/attachment": "shared"},
})
for module in ["aws-eks-gateway", "gcp-gke-gateway"]:
    case(module + "-default", module=module)
    case(module + "-attachments", {
        **({"nlb_scheme": "internet-facing", "nlb_target_type": "ip", "nlb_cross_zone": False,
            "nlb_eip_allocations": ["eipalloc-0123456789abcdef0"],
            "tags": {"environment": "example", "team": "base"}, "nlb_additional_resource_tags": {"team": "public"}}
           if module.startswith("aws") else {"internal": True, "load_balancer_ip": "public-example-address"}),
        "service_annotations": {"example.test/attachment": "shared"},
    }, module=module)
for suffix, cross_zone, raw, expected in [
    ("merge", True, " access_logs.s3.enabled=true, ,deletion_protection.enabled=true, ", "access_logs.s3.enabled=true,deletion_protection.enabled=true,load_balancing.cross_zone.enabled=true"),
    ("override", False, "load_balancing.cross_zone.enabled=true, access_logs.s3.enabled=true, load_balancing.cross_zone.enabled = true", "access_logs.s3.enabled=true,load_balancing.cross_zone.enabled=false"),
    ("empty", True, " , , ", "load_balancing.cross_zone.enabled=true"),
    ("null", None, " access_logs.s3.enabled=true,load_balancing.cross_zone.enabled=true, ", " access_logs.s3.enabled=true,load_balancing.cross_zone.enabled=true, "),
    ("null-value", None, None, None),
    ("null-value-override", True, None, "load_balancing.cross_zone.enabled=true"),
    ("null-map", True, None, "load_balancing.cross_zone.enabled=true"),
]:
    case("aws-gateway-cross-zone-" + suffix, {"nlb_cross_zone": cross_zone,
         "service_annotations": None if suffix == "null-map" else {"service.beta.kubernetes.io/aws-load-balancer-attributes": raw}}, module="aws-eks-gateway")
    CASES["aws-gateway-cross-zone-" + suffix]["expected_attributes"] = expected
for name, value, diagnostic in [
    ("nlb_scheme", "public", "nlb_scheme must be internet-facing or internal."),
    ("nlb_target_type", "pod", "nlb_target_type must be instance or ip."),
    ("nlb_eip_allocations", ["bad"], "Every nlb_eip_allocations entry must match ^eipalloc-[0-9a-f]+$."),
]:
    case("aws-gateway-invalid-" + name,
         {name: value, **({"nlb_scheme": "internet-facing"} if name == "nlb_eip_allocations" else {})},
         diagnostic, "aws-eks-gateway")
case("gcp-gateway-invalid-address", {"load_balancer_ip": "203.0.113.10"}, "load_balancer_ip must name a reserved GCP address resource", "gcp-gke-gateway")
for scheme in [None, "internal"]:
    case("aws-gateway-eip-" + ("unset-scheme" if scheme is None else "internal"),
         {"nlb_eip_allocations": ["eipalloc-0123456789abcdef0"], "nlb_scheme": scheme},
         "nlb_eip_allocations requires nlb_scheme = internet-facing.", "aws-eks-gateway")
for internal in [None, False]:
    case("gcp-gateway-address-" + ("unset-internal" if internal is None else "external"),
         {"load_balancer_ip": "public-example-address", "internal": internal},
         "load_balancer_ip requires internal = true", "gcp-gke-gateway")
for variable in ["tags", "nlb_additional_resource_tags"]:
    for suffix, tags, message in [
        ("key-too-long", {"k" * 129: "value"}, " keys must be at most 128 characters."),
        ("value-too-long", {"key": "v" * 257}, " values must be at most 256 characters."),
        ("reserved-prefix", {"AwS:example": "value"}, " keys must not start with aws: (case-insensitive)."),
    ]:
        case("aws-gateway-" + variable.replace("_", "-") + "-" + suffix,
             {variable: tags}, variable + message, "aws-eks-gateway")
    case("aws-gateway-" + variable.replace("_", "-") + "-null-value", {variable: {"example": None}},
         variable + " values must not be null.", "aws-eks-gateway")
    for suffix, tags in [("empty-key", {"": "value"}), ("blank-key", {" \t ": "value"}),
                         ("leading-space-key", {" key": "value"}), ("trailing-space-key", {"key ": "value"}),
                         ("comma-key", {"bad,key": "value"}),
                         ("equals-key", {"bad=key": "value"}), ("comma-value", {"key": "bad,value"}),
                         ("equals-value", {"key": "bad=value"})]:
        case("aws-gateway-" + variable.replace("_", "-") + "-" + suffix, {variable: tags},
             None if suffix == "equals-value" else variable + " keys must be non-empty without edge whitespace, comma or equals; values must not contain comma.", "aws-eks-gateway")
case("gcp-gateway-external", {"internal": False, "service_annotations": {
    "cloud.google.com/load-balancer-type": "Internal", "networking.gke.io/load-balancer-type": "Internal", "example.test/attachment": "shared",
}}, module="gcp-gke-gateway")
for suffix, addresses, service_type, expected in [
    ("empty", [], "LoadBalancer", (None, None)),
    ("hostname", [{"hostname": "lb.example.test", "ip": ""}], "LoadBalancer", ("lb.example.test", None)),
    ("ip", [{"hostname": "", "ip": "203.0.113.10"}], "LoadBalancer", (None, "203.0.113.10")),
    ("dual", [{"hostname": "", "ip": ""}, {"hostname": "lb.example.test", "ip": "203.0.113.10"}], "LoadBalancer", ("lb.example.test", "203.0.113.10")),
    ("nodeport", [{"hostname": "lb.example.test", "ip": "203.0.113.10"}], "NodePort", (None, None)),
]:
    CASES["gateway-output-" + suffix] = {
        "module": "k8s-gateway", "diagnostic": None, "addresses": addresses,
        "service_type": service_type, "expected": expected,
    }



case("gateway-name-leading-digit", {"name": "1public"}, "name must be a DNS-1035 label")
for count in (64, 65):
    case(f"gateway-listener-count-{count}", {"listeners": {
        f"listener-{i}": {"hostname": f"listener-{i}.example.test", "tls_secret_name": "public-example-tls"}
        for i in range(count)
    }}, "listeners must contain between 1 and 64 entries." if count > 64 else None)
for port in (80, 443):
    case(f"gateway-translated-port-collision-{port}", {"listeners": {
        "low": {"hostname": "low.example.test", "port": port, "tls_secret_name": "public-example-tls"},
        "high": {"hostname": "high.example.test", "port": port + 10000, "tls_secret_name": "public-example-tls"},
    }}, "Listener ports must not collide after Envoy's privileged-port translation.")
for port in (19000, 19001, 19002, 19003):
    listener_case(f"gateway-reserved-port-{port}", {"port": port}, "Listener ports must not use Envoy's reserved pod ports")
for field in ("secret", "issuer"):
    for suffix, value in [
        ("uppercase", "Bad-name"), ("empty-label", "bad..name"), ("edge-hyphen", "bad.-name"),
        ("whitespace", " public-ca "), ("long", "a" * 254),
    ]:
        changes = {"tls_secret_name": value} if field == "secret" else {"tls_secret_name": None, "tls_issuer": {"name": value}}
        diagnostic = "tls_secret_name" if field == "secret" else "tls_issuer.name"
        listener_case(f"gateway-{field}-name-{suffix}", changes, diagnostic + " must be a DNS-1123 subdomain")
    changes = {"tls_secret_name": "a" * 253} if field == "secret" else {"tls_secret_name": None, "tls_issuer": {"name": "a" * 253}}
    listener_case(f"gateway-{field}-name-boundary", changes)

for target in ("selector", "labels", "annotations"):
    for suffix, key in [
        ("empty", ""), ("prefix-uppercase", "Bad.test/key"), ("extra-slash", "example.test/extra/key"),
        ("long-prefix", "a" * 254 + "/key"), ("long-name", "a" * 64), ("edge", "_bad"),
    ]:
        name = f"gateway-{target}-key-{suffix}"
        if target == "selector":
            listener_case(name, {"allowed_route_namespaces": "Selector", "allowed_route_selector": {key: "public"}},
                          "allowed_route_selector keys must be Kubernetes qualified names.")
        else:
            variable = "labels" if target == "labels" else "service_annotations"
            case(name, {variable: {key: "public"}}, None if target == "annotations" and suffix == "prefix-uppercase" else variable + " keys must be Kubernetes qualified names.")
for target in ("selector", "labels"):
    for suffix, value in [("whitespace", "bad value"), ("long", "a" * 64), ("unicode", "é"), ("null", None)]:
        if target == "selector":
            listener_case(f"gateway-selector-value-{suffix}", {"allowed_route_namespaces": "Selector", "allowed_route_selector": {"access": value}},
                          "allowed_route_selector values must be Kubernetes label values")
        else:
            case(f"gateway-labels-value-{suffix}", {"labels": {"access": value}}, "labels values must be Kubernetes label values")
qualified = "a" * 253 + "/" + "A" * 63
listener_case("gateway-qualified-metadata", {"allowed_route_namespaces": "Selector", "allowed_route_selector": {qualified: ""}},
              labels={qualified: "a" * 63, "example.test/Key_Name.1": "", "Unprefixed_Key.1": "Upper.Value_1"},
              service_annotations={qualified: "free-form ☃", "example.test/Key_Name.1": "line\nvalue"})
for variable in ("resources_requests_cpu", "resources_requests_memory", "resources_limits_cpu", "resources_limits_memory"):
    for suffix, value in [("empty", ""), ("unit", "1MiB"), ("number", "1.2.3"), ("whitespace", " 1")]:
        case(f"gateway-{variable.replace('_', '-')}-{suffix}", {variable: value}, variable + " must be null or use Kubernetes Quantity syntax.")
for suffix, quantities in [
    ("decimal", ["+1.", ".5", "1000k", "1M"]),
    ("binary", [".5Ki", "1Mi", "2Gi", "3Ei"]),
    ("exponent", ["1e3", "1E-3", "1e+3", "1"]),
]:
    case("gateway-quantity-" + suffix, dict(zip(
        ("resources_requests_cpu", "resources_requests_memory", "resources_limits_cpu", "resources_limits_memory"), quantities)))
case("gcp-gateway-raw-internal-unset", {"internal": None, "service_annotations": {
    "networking.gke.io/load-balancer-type": "Internal", "cloud.google.com/load-balancer-type": "Internal",
    "example.test/attachment": "shared",
}}, module="gcp-gke-gateway")

def config(spec: dict) -> str:
    if "addresses" in spec:
        source = (ROOT / "terraform/modules/k8s-gateway/outputs.tf").read_text()
        result = []
        for name in ["hostname", "ip"]:
            expression = re.search(r'output "load_balancer_' + name + r'"\s*\{\s*value\s*=\s*([^\n]+)', source)[1]
            expression = expression.replace("var.service_type", json.dumps(spec["service_type"]))
            expression = expression.replace("data.kubernetes_service_v1.proxy[0].status[0].load_balancer[0].ingress", json.dumps(spec["addresses"]))
            result.append(f'output "{name}" {{ value = {expression} }}')
        return "\n".join(result)
    providers = '''
provider "helm" {
  kubernetes {
    host = "https://127.0.0.1:65535"
    insecure = true
  }
}
provider "kubernetes" {
  host = "https://127.0.0.1:65535"
  insecure = true
}
'''
    attributes = "\n".join(f"  {key} = {json.dumps(value)}" for key, value in spec["inputs"].items())
    return providers + f'\nmodule "gateway" {{\n  source = "./modules/{spec["module"]}"\n{attributes}\n}}\n'


listener_case("gateway-hostname-ipv4", {"hostname": "192.0.2.1"}, "Listener hostnames must not be IP literals.")
RESERVED_LABELS = [
    "app.kubernetes.io/name", "app.kubernetes.io/component", "app.kubernetes.io/managed-by",
    "gateway.envoyproxy.io/owning-gateway-name", "gateway.envoyproxy.io/owning-gateway-namespace",
    "gateway.envoyproxy.io/owning-gatewayclass", "gateway.networking.k8s.io/gateway-name", "gateway-instance", "app.kubernetes.io/part-of",
    "app.kubernetes.io/instance", "app.kubernetes.io/version", "helm.sh/chart", "control-plane",
]
for i, label in enumerate(RESERVED_LABELS):
    for module in ("k8s-gateway", "aws-eks-gateway", "gcp-gke-gateway"):
        case(f"{module}-reserved-label-{i}", {"labels": {label: "public-gateway"}},
             "labels must not override reserved Envoy", module)
for key in ("requests_cpu", "requests_memory", "limits_cpu", "limits_memory"):
    for i, value in enumerate(("-1", "-.1n")):
        case(f"gateway-negative-{key}-{i}", {"resources_" + key: value}, "resources_" + key + " must not be negative.")
for resource, request, limit, suffix in [
    ("cpu", "1500m", "1", "milli"), ("cpu", "2", "1999m", "whole"),
    ("memory", "1Gi", "1000Mi", "binary"), ("memory", "1G", "999M", "decimal"),
    ("memory", "2e9", "1Gi", "exponent"), ("memory", "2E", "1Ei", "exa"),
]:
    case(f"gateway-request-over-limit-{suffix}", {"resources_requests_" + resource: request, "resources_limits_" + resource: limit},
         "resources_requests_" + resource + " must not exceed resources_limits_" + resource + ".")
for i, (request, limit) in enumerate([
    ("1Ki", "1024"), ("1Mi", "1024Ki"), ("1Gi", "1024Mi"), ("1Ti", "1024Gi"),
    ("1Pi", "1024Ti"), ("1Ei", "1024Pi"), ("1k", "1000"), ("1M", "1000k"),
    ("1G", "1000M"), ("1T", "1000G"), ("1P", "1000T"), ("1E", "1000P"),
    ("100n", ".0000001"), ("1u", "1000n"), ("1m", ".001"), ("1e3", "1k"),
    (".1n", ".2n"), ("10Ei", "9Ei"), ("0", "0"),
]):
    case(f"gateway-quantity-equivalent-{i}", {"resources_requests_memory": request, "resources_limits_memory": limit})
case("gateway-quantity-cpu-equivalent", {"resources_requests_cpu": "1000m", "resources_limits_cpu": "1"})


CONFIGS = {name: config(spec) for name, spec in CASES.items()}
DIAGNOSTICS = {name: spec["diagnostic"] for name, spec in CASES.items() if spec["diagnostic"]}


def resources(module: dict) -> list[dict]:
    return module.get("resources", []) + [
        resource for child in module.get("child_modules", []) for resource in resources(child)
    ]


def check_plan(name: str, plan: dict) -> None:
    if "addresses" in CASES[name]:
        outputs = plan["planned_values"].get("outputs", {})
        assert tuple(outputs.get(key, {}).get("value") for key in ["hostname", "ip"]) == CASES[name]["expected"], "address output semantics changed"
        return
    planned = resources(plan["planned_values"]["root_module"])
    managed = [resource for resource in planned if resource["mode"] == "managed"]
    assert len(managed) == 2 and all(resource["type"] == "helm_release" for resource in managed), "unexpected managed resources"
    controller = next(resource["values"] for resource in managed if resource["name"] == "controller")
    configuration = next(resource["values"] for resource in managed if resource["name"] == "configuration")
    inputs = CASES[name]["inputs"]
    expected_controller = "eg-controller-" + hashlib.sha256((inputs["namespace"] + "/" + inputs["name"]).encode()).hexdigest()[:20]
    assert controller["name"] == expected_controller and len(controller["name"]) <= 53, "controller release must isolate cluster RBAC by namespace/name"
    assert controller["version"] == "v1.9.3" and controller["skip_crds"] is True
    values = json.loads(configuration["values"][0]) if configuration["values"][0].startswith("{") else None
    if values is None:
        raise AssertionError("configuration values must be encoded as JSON (valid YAML)")
    helm_timeout = CASES[name]["inputs"].get("helm_timeout", 600)
    assert configuration["timeout"] == helm_timeout
    assert values["timeout"] == max(1, helm_timeout - 30) < helm_timeout
    base = json.loads(controller["values"][0])
    assert base["crds"]["enabled"] is False
    assert controller["values"][1:] == CASES[name]["inputs"].get("extra_helm_values", [])
    assert "@sha256:" in base["global"]["images"]["envoyGateway"]["image"]
    assert "@sha256:" in base["config"]["envoyGateway"]["provider"]["kubernetes"]["shutdownManager"]["image"]
    objects = {obj["kind"]: obj for obj in values["objects"]}
    assert set(objects) == {"GatewayClass", "Gateway", "EnvoyProxy", "ClientTrafficPolicy"} | ({"NetworkPolicy"} if CASES[name]["inputs"].get("network_policy_enabled") else set())
    gateway = objects["Gateway"]
    gateway_name = CASES[name]["inputs"]["name"]
    assert gateway["metadata"]["name"] == gateway_name
    assert gateway["spec"]["gatewayClassName"] == objects["GatewayClass"]["metadata"]["name"]
    assert objects["ClientTrafficPolicy"]["spec"]["tls"]["minVersion"] == "1.2"
    proxy = objects["EnvoyProxy"]["spec"]["provider"]["kubernetes"]
    deployment = proxy["envoyDeployment"]
    expected_resources = {
        section: {resource: inputs["resources_" + section + "_" + resource]
                  for resource in ("cpu", "memory") if inputs.get("resources_" + section + "_" + resource) is not None}
        for section in ("requests", "limits")
    }
    expected_resources = {section: values for section, values in expected_resources.items() if values}
    if expected_resources:
        assert deployment["container"]["resources"] == expected_resources, "resource overrides must omit empty sections"
    else:
        assert "resources" not in deployment["container"], "unset resources must preserve upstream defaults"
    assert not (set(deployment["pod"]["labels"]) & (set(RESERVED_LABELS) - {"gateway-instance", "app.kubernetes.io/part-of"}))
    assert deployment["pod"]["labels"]["gateway-instance"] == gateway_name
    assert deployment["replicas"] == 2 and proxy["envoyPDB"]["minAvailable"] == 1
    security = deployment["container"]["securityContext"]
    assert "readOnlyRootFilesystem" not in security and security["runAsNonRoot"] and security["capabilities"]["drop"] == ["ALL"]
    assert deployment["pod"]["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault"
    assert "@sha256:" in deployment["container"]["image"] and "@sha256:" in values["waitImage"]
    service = proxy["envoyService"]
    assert service["name"] == gateway_name + "-proxy"
    for listener in gateway["spec"]["listeners"]:
        original = CASES[name]["inputs"]["listeners"][listener["name"]]
        assert listener["hostname"] == original["hostname"]
        assert listener["allowedRoutes"]["namespaces"]["from"] == original.get("allowed_route_namespaces", "Same")
        if listener["protocol"] == "HTTPS":
            expected = original.get("tls_secret_name") or f'public-gateway-{listener["name"]}-tls'
            assert listener["tls"]["certificateRefs"][0]["name"] == expected
        elif listener["protocol"] == "TLS":
            assert listener["tls"] == {"mode": "Passthrough"}
        else:
            assert "tls" not in listener
    issuers = [listener["tls_issuer"] for listener in CASES[name]["inputs"]["listeners"].values() if listener.get("tls_issuer")]
    annotations = gateway["metadata"]["annotations"]
    if issuers:
        key = "cert-manager.io/issuer" if issuers[0].get("kind") == "Issuer" else "cert-manager.io/cluster-issuer"
        assert annotations == {key: issuers[0]["name"]}
    else:
        assert annotations == {}
    if "NetworkPolicy" in objects:
        policy = objects["NetworkPolicy"]["spec"]
        assert policy["podSelector"]["matchLabels"] == {"gateway-instance": "public-gateway"}
        assert policy["ingress"] == [{"ports": [{"protocol": "TCP", "port": 10443}]}]
        assert policy["egress"][0]["ports"] == [{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}]
        assert policy["egress"][1]["ports"] == [{"protocol": "TCP", "port": 18000}]
        assert policy["egress"][1]["to"][0]["podSelector"]["matchLabels"] == {"control-plane": "envoy-gateway"}
        expected = {"access": "public"} if name.endswith("selector") else {"kubernetes.io/metadata.name": "gateway-system"}
        assert policy["egress"][2]["to"] == [{"namespaceSelector": {"matchLabels": expected}}]
    if name.endswith("-attachments"):
        assert service["annotations"]["example.test/attachment"] == "shared"
        if name.startswith("aws"):
            assert service["annotations"] == {
                "example.test/attachment": "shared",
                "service.beta.kubernetes.io/aws-load-balancer-type": "external",
                "service.beta.kubernetes.io/aws-load-balancer-scheme": "internet-facing",
                "service.beta.kubernetes.io/aws-load-balancer-eip-allocations": "eipalloc-0123456789abcdef0",
                "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
                "service.beta.kubernetes.io/aws-load-balancer-attributes": "load_balancing.cross_zone.enabled=false",
                "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags": "environment=example,team=public",
            }
        else:
            assert service["annotations"]["networking.gke.io/load-balancer-type"] == "Internal"
            assert service["annotations"]["networking.gke.io/load-balancer-ip-addresses"] == "public-example-address"
    if name.startswith("aws-gateway-") and name.endswith("-equals-value"):
        assert service["annotations"]["service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags"] == "key=bad=value"
    if "expected_attributes" in CASES[name]:
        assert service["annotations"]["service.beta.kubernetes.io/aws-load-balancer-attributes"] == CASES[name]["expected_attributes"]
    if name == "gateway-overrides":
        assert deployment["container"]["resources"] == {"requests": {"cpu": "100m"}, "limits": {"memory": "256Mi"}}
        assert service["labels"] == {"team": "public"}
    if name == "gcp-gateway-external":
        assert service["annotations"] == {"example.test/attachment": "shared"}
    if name == "gcp-gateway-raw-internal-unset":
        assert service["annotations"] == {
            "networking.gke.io/load-balancer-type": "Internal", "cloud.google.com/load-balancer-type": "Internal",
            "example.test/attachment": "shared",
        }
    if os.environ.get("GATEWAY_RENDER_OUTPUT") and name == "gateway-policy-selector":
        destination = Path(os.environ["GATEWAY_RENDER_OUTPUT"])
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "configuration.json").write_text(json.dumps(values))
        (destination / "controller.json").write_text(json.dumps(base))
