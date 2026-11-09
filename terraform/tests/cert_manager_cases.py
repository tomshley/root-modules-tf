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

"""cert-manager input contracts and planned Helm release assertions."""

from __future__ import annotations

import copy
import hashlib
import json

DEFAULT = {
    "chart_version": "v1.21.3",
    "issuer": {
        "name": "public-acme",
        "acme_email": "platform@example.test",
        "dns01": {"provider": "cloudflare", "credential_secret_name": "cloudflare-api-token"},
    },
}
NAMESPACE = "namespace must be a non-null DNS-1123 label of at most 63 characters."
NAME = "issuer.name must be a non-null DNS-1123 label of at most 63 characters."
EMAIL = "issuer.acme_email must be a non-null email address with a supported ASCII dot-atom local part of at most 64 characters and a dotted domain, at most 254 characters."
SERVER = "issuer.acme_server must be an HTTPS URL with a DNS hostname, an optional port from 1 to 65535, well-formed percent escapes, and no credentials, whitespace or fragment."
SECRET = "issuer.dns01.credential_secret_name must be a non-null DNS-1123 subdomain of at most 253 characters, with labels of at most 63 characters."
ACCOUNT_KEY = "issuer.dns01.credential_secret_name must differ from the generated ACME account-key Secret name."
KEY = "issuer.dns01.credential_secret_key must contain 1 to 253 letters, digits, dots, underscores or hyphens, must not be a single dot, and must not start with two dots."
EXTRA = "extra_helm_values must be a non-null list of non-null YAML mappings."
CASES: dict[str, dict] = {}


def add(name: str, changes: dict | None = None, diagnostic: str | None = None) -> None:
    inputs = copy.deepcopy(DEFAULT)
    for path, value in (changes or {}).items():
        parts = path.split(".")
        target = inputs
        for part in parts[:-1]:
            target = target[part]
        target[parts[-1]] = value
    CASES["cert-manager-" + name] = {"inputs": inputs, "diagnostic": diagnostic}


add("default")
add("overrides", {
    "namespace": "certificate-system", "create_namespace": False,
    "issuer.name": "staging-acme", "issuer.acme_email": "acme+staging@example.test",
    "issuer.acme_server": "https://acme-staging-v02.api.letsencrypt.org:443/directory?profile=test",
    "issuer.dns01.credential_secret_name": "dns.credentials.example.test",
    "issuer.dns01.credential_secret_key": "API_TOKEN.v2",
    "extra_helm_values": ["replicaCount: 2\n", "replicaCount: 3\n"],
})
add("name-boundaries", {
    "namespace": "1" * 63, "issuer.name": "1" * 63,
    "issuer.dns01.credential_secret_name": ".".join(["a" * 63] * 3 + ["b" * 61]),
    "issuer.dns01.credential_secret_key": "A" * 253,
})
add("optional-null-defaults", {"issuer.acme_server": None, "issuer.dns01.credential_secret_key": None})
add("server-escaped", {"issuer.acme_server": "https://acme.example.test/%64irectory?profile=a%2fb%25"})
add("email-dot-atom", {"issuer.acme_email": "AZaz09_acme-registration+tag.second@example.test"})
add("email-local-boundary", {"issuer.acme_email": "a" * 64 + "@example.test"})
add("server-query-colon", {"issuer.acme_server": "https://acme.example.test?x=a:99999"})
add("dns-label-boundaries", {"issuer.acme_server": "https://" + "a" * 63 + ".test", "issuer.acme_email": "a@" + "b" * 63 + ".test"})

for prefix, path, message in (("namespace", "namespace", NAMESPACE), ("issuer-name", "issuer.name", NAME)):
    for label, value in (("null", None), ("empty", ""), ("uppercase", "Bad"), ("long", "a" * 64), ("edge", "-bad"), ("space", " bad")):
        add(prefix + "-" + label, {path: value}, message)
add("create-namespace-null", {"create_namespace": None}, "create_namespace must be non-null.")
for label, value in (("floating", "latest"), ("other-pin", "v1.20.0"), ("null", None), ("empty", "")):
    add("chart-" + label, {"chart_version": value}, "chart_version must be v1.21.3, the version supported by the pinned image digests.")
add("issuer-null", {"issuer": None}, "issuer must be non-null.")
add("dns01-null", {"issuer.dns01": None}, "issuer.dns01 must be non-null.")
for label, value in (("null", None), ("empty", ""), ("shape", "not-email"), ("domain", "mail@localhost"), ("space", " mail@example.test"), ("control", "mail\u0000@example.test"), ("long", "a" * 242 + "@example.test")):
    add("email-" + label, {"issuer.acme_email": value}, EMAIL)
for label, value in (("domain-ip", "a@127.0.0.1"), ("domain-label-long", "a@" + "b" * 64 + ".test")):
    add("email-" + label, {"issuer.acme_email": value}, EMAIL)
for label, delimiter in (
    ("comma", ","), ("semicolon", ";"), ("colon", ":"), ("angle-left", "<"), ("angle-right", ">"),
    ("square-left", "["), ("square-right", "]"), ("parenthesis-left", "("), ("parenthesis-right", ")"),
    ("backslash", "\\"), ("quote", '"'),
    ("uri-fragment", "#"), ("uri-query", "?"), ("uri-percent", "%"), ("uri-slash", "/"),
):
    add("email-" + label, {"issuer.acme_email": "a" + delimiter + "b@example.test"}, EMAIL)
for label, value in (
    ("leading-dot", ".a@example.test"), ("trailing-dot", "a.@example.test"), ("repeated-dot", "a..b@example.test"),
    ("quoted", '"a,b"@example.test'), ("unicode", "müller@example.test"), ("local-long", "a" * 65 + "@example.test"),
):
    add("email-" + label, {"issuer.acme_email": value}, EMAIL)
for label, value in (
    ("host-ip", "https://127.0.0.1/directory"), ("host-label-long", "https://" + "a" * 64 + ".test/directory"),
    ("empty", ""), ("http", "http://acme.example.test/directory"), ("hostless", "https:///directory"),
    ("hostname", "https://acme..example.test/directory"), ("space", "https://acme.example.test/dir ectory"),
    ("control", "https://acme.example.test/dir\u0000ectory"), ("credentials", "https://user:password@acme.example.test/directory"),
    ("fragment", "https://acme.example.test/directory#fragment"), ("port-zero", "https://acme.example.test:0/directory"),
    ("port-high", "https://acme.example.test:65536/directory"),
    ("bad-percent", "https://acme.example.test/%zz"), ("short-percent", "https://acme.example.test/%2"),
    ("bare-percent", "https://acme.example.test/%"), ("mixed-percent", "https://acme.example.test/%20%zz"),
    ("query-percent", "https://acme.example.test/directory?profile=%zz"),
):
    add("server-" + label, {"issuer.acme_server": value}, SERVER)
for label, value in (("null", None), ("empty", ""), ("unsupported", "route53"), ("case", "Cloudflare")):
    add("provider-" + label, {"issuer.dns01.provider": value}, "issuer.dns01.provider must be cloudflare.")
for label, value in (("null", None), ("empty", ""), ("uppercase", "Bad"), ("long", "a" * 254), ("label-long", "a" * 64 + ".test"), ("empty-label", "a..test"), ("edge", "a-.test")):
    add("secret-" + label, {"issuer.dns01.credential_secret_name": value}, SECRET)
add("secret-account-key-collision", {
    "issuer.dns01.credential_secret_name": "cm-acme-" + hashlib.sha256(DEFAULT["issuer"]["name"].encode()).hexdigest()[:24],
}, ACCOUNT_KEY)
add("secret-webhook-ca-collision", {"issuer.dns01.credential_secret_name": "cert-manager-webhook-ca"}, "issuer.dns01.credential_secret_name must differ from the cert-manager webhook CA Secret name.")
for label, value in (("empty", ""), ("long", "a" * 254), ("slash", "api/token"), ("space", "api token"), ("dot", "."), ("dot-prefix", "..token")):
    add("key-" + label, {"issuer.dns01.credential_secret_key": value}, KEY)
for label, value in (("null", None), ("null-entry", [None]), ("empty", [""]), ("list", ["[]"]), ("scalar", ["true"]), ("malformed", ["x: ["]), ("multi-document", ["x: 1\n---\ny: 2"])):
    add("values-" + label, {"extra_helm_values": value}, EXTRA)


def config(inputs: dict) -> str:
    arguments = "\n".join(f"  {key} = {json.dumps(value)}" for key, value in inputs.items())
    return '''provider "helm" {
  kubernetes {
    host = "https://127.0.0.1:65535"
    insecure = true
  }
}
module "cert_manager" {
  source = "../../../modules/k8s-cert-manager"
''' + arguments + '\n}\n' + "\n".join(
        f'output "{name}" {{ value = module.cert_manager.{name} }}'
        for name in ("issuer_name", "issuer_kind", "namespace", "release_status")
    )


CONFIGS = {name: config(spec["inputs"]) for name, spec in CASES.items()}
DIAGNOSTICS = {name: spec["diagnostic"] for name, spec in CASES.items() if spec["diagnostic"]}
DIGESTS = {
    "controller": "sha256:9f4f96a33c7774cef24466fcd85031997531a03a8d117f151126baa8d1290dcc",
    "webhook": "sha256:055ac8e9de6a0ba6763794838fe38944acc650f68ebe1b01dd8be079e580f458",
    "cainjector": "sha256:083d0e906f8eb44e255fe4ff817ae54e49f9ed82e22f1011bb4e9e4f4b8a641f",
    "startupapicheck": "sha256:1c519d4afca1413d1e4ccd78bdc756184418ab55a34569a3b3de39d32f9974e1",
    "acmesolver": "sha256:c8c1225bb2fe8ab37a330b77f0d8c2ee6a41210fcb54fc07ca606ab9a022b8b7",
}


def resources(root: dict) -> list[dict]:
    return root.get("resources", []) + [resource for child in root.get("child_modules", []) for resource in resources(child)]


def check_plan(name: str, plan: dict) -> None:
    inputs = CASES[name]["inputs"]
    root = plan["planned_values"]
    managed = resources(root["root_module"])
    assert len(managed) == 2 and all(resource["mode"] == "managed" and resource["type"] == "helm_release" for resource in managed), "only two Helm releases are permitted"
    releases = {resource["name"]: resource["values"] for resource in managed}
    controller, configuration = releases["controller"], releases["configuration"]
    namespace = inputs.get("namespace", "cert-manager")
    assert controller["name"] == "cert-manager"
    assert controller["namespace"] == configuration["namespace"] == root["outputs"]["namespace"]["value"] == namespace
    assert controller["create_namespace"] is inputs.get("create_namespace", True)
    assert (controller["repository"], controller["chart"], controller["version"]) == ("https://charts.jetstack.io", "cert-manager", "v1.21.3")
    assert configuration["chart"].endswith("/chart") and not configuration["repository"], "issuer chart must be local to the installed module"
    assert controller["wait"] and controller["wait_for_jobs"] and configuration["wait"] and configuration["wait_for_jobs"]
    assert controller["timeout"] == configuration["timeout"] == 600
    assert controller["values"][1:] == inputs.get("extra_helm_values", [])
    generated = json.loads(controller["values"][0])
    assert generated["config"] == {"gatewayAPI": {"enabled": True}}
    assert generated["crds"] == {"enabled": True, "keep": True}
    assert generated["clusterResourceNamespace"] == generated["global"]["leaderElection"]["namespace"] == namespace
    for component, digest in DIGESTS.items():
        actual = generated["image"] if component == "controller" else generated[component]["image"]
        assert actual == {"repository": f"quay.io/jetstack/cert-manager-{component}", "tag": "v1.21.3", "digest": digest}, component
    issuer = inputs["issuer"]
    issuer_id = hashlib.sha256(issuer["name"].encode()).hexdigest()[:24]
    assert configuration["name"] == "cm-issuer-" + issuer_id
    assert len(configuration["name"]) <= 53
    assert len(configuration["values"]) == 1
    assert json.loads(configuration["values"][0]) == {"issuer": {
        "apiVersion": "cert-manager.io/v1", "kind": "ClusterIssuer", "metadata": {"name": issuer["name"]},
        "spec": {"acme": {
            "email": issuer["acme_email"],
            "server": issuer.get("acme_server") or "https://acme-v02.api.letsencrypt.org/directory",
            "privateKeySecretRef": {"name": "cm-acme-" + issuer_id},
            "solvers": [{"dns01": {"cloudflare": {"apiTokenSecretRef": {
                "name": issuer["dns01"]["credential_secret_name"],
                "key": issuer["dns01"].get("credential_secret_key") or "api-token",
            }}}}],
        }},
    }}
    assert root["outputs"]["issuer_name"]["value"] == issuer["name"]
    assert root["outputs"]["issuer_kind"]["value"] == "ClusterIssuer"
    module = plan["configuration"]["root_module"]["module_calls"]["cert_manager"]
    configured = {resource["name"]: resource for resource in module["module"]["resources"]}
    assert configured["configuration"]["depends_on"] == ["helm_release.controller"]
    assert module["module"]["outputs"]["release_status"]["expression"]["references"] == ["helm_release.controller.status", "helm_release.controller"]
