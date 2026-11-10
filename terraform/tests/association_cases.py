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

"""Positive association fixtures and the dedicated negative renderer runner."""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
DIGEST = "sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"
FINGERPRINT = ":".join(["AB"] * 32)
APP = {
    "name": "example",
    "ios": {"team_id": "ABCDE12345", "bundle_id": "test.example.app", "paths": ["/auth/callback/example"]},
    "android": {"package_name": "test.example.app", "sha256_fingerprints": [FINGERPRINT]},
}
FILES = {"/.well-known/example.json": {"content": '{"example":"fixed bytes"}\n', "content_type": "application/json"}}
ESCAPED_FILES = {'/quoted"; return 200 "unexpected': {"content": "fixed", "content_type": 'text/plain"; return 200 "unexpected'}}
ESCAPED_FILES.update({
    "/back\\\\slash": {"content": "backslash", "content_type": "application/x-back\\\\slash"},
    "/dollar$": {"content": "dollar", "content_type": "application/x-dollar$"},
    "/with space": {"content": "space", "content_type": "application/x-with space"},
    "/brace{": {"content": "brace", "content_type": "application/x-brace{"},
})
CASES: dict[str, str] = {}
DIAGNOSTICS: dict[str, str] = {}
EXPECTED_FILES: dict[str, dict] = {}
EXPECTED_PORTS: dict[str, int] = {}
EXPECTED_NAMES = {"static-responder-max-name": "a" * 63}
EXPECTED_SCALING: dict[str, tuple[int, int]] = {"static-responder-single-replica": (1, 0)}


def render_apps(apps: object) -> str:
    return """
module "subject" {
  source = "../../../modules/k8s-app-links"
  apps = jsondecode(%s)
}
output "result" {
  value = {
    files = module.subject.files
    paths = module.subject.paths
    callback_paths = module.subject.callback_paths
  }
}
""" % json.dumps(json.dumps(apps))


def render_files(expression: str, image: str | None = DIGEST) -> str:
    image_input = "" if image is None else f'  image = "nginxinc/nginx-unprivileged@{image}"'
    return """
provider "kubernetes" { host = "https://127.0.0.1:65535" }
module "subject" {
  source = "../../../modules/k8s-static-responder"
  name = "example-static"
  namespace = "example"
%s
  files = %s
}
output "result" {
  value = {
    service_name = module.subject.service_name
    service_port = module.subject.service_port
    paths = module.subject.paths
  }
}
""" % (image_input, expression)


def files_expression(files: object) -> str:
    return "jsondecode(" + json.dumps(json.dumps(files)) + ")"


def add(name: str, config: str, diagnostic: str | None = None) -> None:
    CASES[name] = config
    if diagnostic:
        DIAGNOSTICS[name] = diagnostic


minimum_provider = re.search(r'version\s*=\s*"~> (\d+\.\d+)"', (ROOT / "terraform/modules/k8s-static-responder/provider.tf").read_text())[1] + ".0"
minimum_case = "static-responder-minimum-provider"
EXPECTED_FILES[minimum_case] = FILES
add(minimum_case, """
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "= %s"
    }
  }
}
""" % minimum_provider + render_files(files_expression(FILES)))

for name, apps in {
    "app-links-golden": [APP],
    "app-links-empty": [],
    "app-links-ios-only": [{"name": "example", "ios": APP["ios"]}],
    "app-links-android-only": [{"name": "example", "android": APP["android"]}],
    "app-links-multiple": [APP, {"name": APP["name"], "ios": {**APP["ios"], "bundle_id": "test.example.other", "paths": ["/other", "/other/*"]},
                                 "android": {**APP["android"], "package_name": "test.example.other"}}],
}.items():
    add(name, render_apps(apps))

for suffix, name in [
    ("null-name", None), ("empty-name", ""), ("space-only-name", " "),
    ("leading-space-name", " example"), ("trailing-space-name", "example "),
    ("leading-tab-name", "\texample"), ("trailing-unicode-space-name", "example\u00a0"),
]:
    add("app-links-" + suffix, render_apps([{**APP, "name": name}]),
        "App name must be non-null, non-empty and have no leading or trailing whitespace.")

for name, apps, message in [
    ("team-id", [{**APP, "ios": {**APP["ios"], "team_id": "invalid"}}], "iOS team_id"),
    ("fingerprint", [{**APP, "android": {**APP["android"], "sha256_fingerprints": ["invalid"]}}], "Android fingerprints must be uppercase colon-separated SHA-256."),
    ("lowercase-fingerprint", [{**APP, "android": {**APP["android"], "sha256_fingerprints": [FINGERPRINT.lower()]}}], "Android fingerprints must be uppercase colon-separated SHA-256."),
    ("empty-fingerprints", [{**APP, "android": {**APP["android"], "sha256_fingerprints": []}}], "Android sha256_fingerprints must be a non-empty list."),
    ("empty-paths", [{**APP, "ios": {**APP["ios"], "paths": []}}], "iOS paths must be a non-empty list."),
    ("path-prefix", [{**APP, "ios": {**APP["ios"], "paths": ["callback"]}}], "Each iOS path must begin with /."),
    ("no-platform", [{"name": "example"}], "Each app"),
    ("duplicate-bundle", [APP, {**APP, "android": None}], "iOS bundle identifiers must be unique."),
    ("duplicate-package", [APP, {**APP, "ios": None}], "Android package identifiers must be unique."),
    ("empty-bundle", [{**APP, "ios": {**APP["ios"], "bundle_id": ""}}], "iOS bundle_id must be non-empty."),
    ("empty-package", [{**APP, "android": {**APP["android"], "package_name": ""}}], "Android package_name must be non-empty."),
    ("null-app", [None], "Each app"),
    ("null-apps", None, "required variable may not be set to null"),
    ("null-paths", [{**APP, "ios": {**APP["ios"], "paths": None}}], "iOS paths must be a non-empty list."),
    ("null-path", [{**APP, "ios": {**APP["ios"], "paths": [None]}}], "Each iOS path must begin with /."),
]:
    add("app-links-" + name, render_apps(apps), message)

for platform, field in [("ios", "bundle_id"), ("android", "package_name")]:
    for suffix, value in [
        ("leading-space", " test.example.app"),
        ("internal-space", "test.example app"),
        ("control", "test.example\u0085app"),
    ]:
        add(f"app-links-{field}-{suffix}",
            render_apps([{**APP, platform: {**APP[platform], field: value}}]),
            field + " must be trimmed and must not contain whitespace or control characters.")

for suffix, path in [
    ("query", "/callback?query"), ("fragment", "/callback#fragment"),
    ("space", "/callback path"), ("tab", "/callback\tpath"),
    ("newline", "/callback\npath"), ("nul", "/callback\x00path"),
    ("c1", "/callback\u0085path"),
    ("delete", "/callback\x7fpath"), ("unicode-space", "/callback\u00a0path"),
]:
    add("app-links-path-" + suffix,
        render_apps([{**APP, "ios": {**APP["ios"], "paths": [path]}}]),
        "iOS paths must not contain ?, #, whitespace or control characters.")

for name, files in {
    "static-responder-fixed": FILES,
    "static-responder-max-name": FILES,
    "static-responder-null-defaults": FILES,
    "static-responder-single-replica": FILES,
    "static-responder-updated": {path: {**file, "content": "changed"} for path, file in FILES.items()},
    "static-responder-empty": {},
    "static-responder-escaped": ESCAPED_FILES,
}.items():
    EXPECTED_FILES[name] = files
    config = render_files(files_expression(files))
    if name in EXPECTED_NAMES:
        config = config.replace('  name = "example-static"', f'  name = "{EXPECTED_NAMES[name]}"')
    if name == "static-responder-null-defaults":
        config = config.replace('  namespace = "example"', '  namespace = "example"\n  replicas = null\n  pdb_min_available = null\n  service_port = null')
    if name in EXPECTED_SCALING:
        replicas, min_available = EXPECTED_SCALING[name]
        config = config.replace('  namespace = "example"', f'  namespace = "example"\n  replicas = {replicas}\n  pdb_min_available = {min_available}')
    add(name, config)

for name, files, message in [
    ("root-key", {"/": next(iter(FILES.values()))}, "File keys must not end in /"),
    ("trailing-slash-key", {"/file/": next(iter(FILES.values()))}, "File keys must not end in /"),
    ("trailing-dot-key", {"/file/.": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("double-slash-key", {"/file//part": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("dot-key", {"/file/./part": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("parent-key", {"/file/../part": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("trailing-parent-key", {"/file/..": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("percent-key", {"/file%2fpart": next(iter(FILES.values()))}, "File keys must not contain //"),
    ("relative-key", {"relative": next(iter(FILES.values()))}, "File keys"),
    ("query-key", {"/file?query": next(iter(FILES.values()))}, "File keys"),
    ("fragment-key", {"/file#fragment": next(iter(FILES.values()))}, "File keys"),
    ("wildcard-key", {"/file*": next(iter(FILES.values()))}, "File keys"),
    ("content-type-space-only", {"/file": {"content": "fixed", "content_type": " "}}, "Files must have non-null content and a non-empty content_type."),
    ("null-content", {"/file": {"content": None, "content_type": "application/json"}}, "non-null content"),
    ("null-file", {"/file": None}, "non-null content"),
    ("null-files", None, "required variable may not be set to null"),
]:
    add("static-responder-" + name, render_files(files_expression(files)), message)

for suffix, control in [("nul", "\x00"), ("lf", "\n"), ("cr", "\r"), ("unit-separator", "\x1f"), ("delete", "\x7f")]:
    add("static-responder-key-control-" + suffix,
        render_files(files_expression({"/file" + control + "part": next(iter(FILES.values()))})),
        "File keys must not contain control characters.")
    add("static-responder-content-type-control-" + suffix,
        render_files(files_expression({"/file": {"content": "fixed", "content_type": "text/plain" + control + "X-Injected: yes"}})),
        "content_type must contain only printable ASCII characters.")

for suffix, content_type in [
    ("trailing-tab", "text/plain\t"), ("leading-lf", "\ntext/plain"),
    ("trailing-cr", "text/plain\r"), ("only-tab", "\t"),
]:
    add("static-responder-content-type-control-" + suffix,
        render_files(files_expression({"/file": {"content": "fixed", "content_type": content_type}})),
        "content_type must contain only printable ASCII characters.")

add("static-responder-key-control-c1",
    render_files(files_expression({"/file\u0085part": next(iter(FILES.values()))})),
    "File keys must not contain control characters.")

for suffix, content_type in [("empty", ""), ("null", None)]:
    add("static-responder-content-type-" + suffix,
        render_files(files_expression({"/file": {"content": "fixed", "content_type": content_type}})),
        "Files must have non-null content and a non-empty content_type.")

for suffix, content_type, diagnostic in [
    ("space-control", " text/plain\t", "content_type must contain only printable ASCII characters."),
    ("leading-space", " text/plain", "content_type must not have leading or trailing whitespace."),
    ("trailing-space", "text/plain ", "content_type must not have leading or trailing whitespace."),
    ("unicode", "text/pl\u00e1in", "content_type must contain only printable ASCII characters."),
    ("unicode-space", "text/plain\u00a0charset=utf-8", "content_type must contain only printable ASCII characters."),
]:
    add("static-responder-content-type-" + suffix,
        render_files(files_expression({"/file": {"content": "fixed", "content_type": content_type}})),
        diagnostic)

add("static-responder-content-type-first-offending-file",
    render_files(files_expression({
        "/c": {"content": "fixed", "content_type": ""},
        "/a": {"content": "fixed", "content_type": "text/plain"},
        "/b": {"content": "fixed", "content_type": " text/plain"},
    })),
    "content_type must not have leading or trailing whitespace.")

oversize = '{"/file" = { content = join("", [for i in range(1000) : format("%01000d", 0)]), content_type = "text/plain" }}'
add("static-responder-oversize", render_files(oversize), "900 KiB ConfigMap budget")
add("static-responder-unicode-size",
    render_files(oversize.replace('format("%01000d", 0)', 'replace(format("%0500d", 0), "0", "é")')), "900 KiB ConfigMap budget")
add("static-responder-config-size",
    render_files('{ for i in range(1000) : format("/%s-%s", i, format("%0700d", 0)) => { content = "", content_type = "text/plain" }}'),
    "Files and generated configuration")
add("static-responder-unpinned-image", render_files(files_expression(FILES), "latest"), "image must be pinned")
add("static-responder-required-image", render_files(files_expression(FILES), None), 'The argument "image" is required')
for variable, value in [("name", "Bad/name"), ("namespace", "a" * 64)]:
    config = render_files(files_expression(FILES))
    original = '  name = "example-static"' if variable == "name" else '  namespace = "example"'
    add("static-responder-invalid-" + variable,
        config.replace(original, f"  {variable} = {json.dumps(value)}"),
        variable + " must be a DNS-" + ("1035" if variable == "name" else "1123") + " label of at most 63 characters.")

for suffix, value in [("leading-digit-name", "1example"), ("long-name", "a" * 64)]:
    add("static-responder-" + suffix,
        render_files(files_expression(FILES)).replace('  name = "example-static"', f'  name = "{value}"'),
        "name must be a DNS-1035 label of at most 63 characters.")

for suffix, arguments, message in [
    ("zero-replicas", "replicas = 0", "replicas must be a positive integer."),
    ("negative-pdb", "pdb_min_available = -1", "pdb_min_available must be a non-negative integer."),
    ("fractional-replicas", "replicas = 1.5", "replicas must be a positive integer."),
    ("fractional-pdb", "pdb_min_available = 0.5", "pdb_min_available must be a non-negative integer."),
    ("zero-port", "service_port = 0", "service_port must be an integer between 1 and 65535."),
    ("large-port", "service_port = 65536", "service_port must be an integer between 1 and 65535."),
    ("fractional-port", "service_port = 80.5", "service_port must be an integer between 1 and 65535."),
    ("equal-pdb", "pdb_min_available = 2", "pdb_min_available must be smaller than replicas."),
]:
    add("static-responder-" + suffix,
        render_files(files_expression(FILES)).replace('  namespace = "example"', '  namespace = "example"\n  ' + arguments), message)

for suffix, port in [("minimum-port", 1), ("maximum-port", 65535)]:
    name = "static-responder-" + suffix
    EXPECTED_FILES[name] = FILES
    EXPECTED_PORTS[name] = port
    add(name,
        render_files(files_expression(FILES)).replace('  namespace = "example"', f'  namespace = "example"\n  service_port = {port}'))


def resources(module: dict) -> list[dict]:
    return module.get("resources", []) + [
        resource for child in module.get("child_modules", []) for resource in resources(child)
    ]


def config_checksum(config: dict) -> str:
    encoded = json.dumps(config, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    for literal, escaped in [("&", "\\u0026"), ("<", "\\u003c"), (">", "\\u003e"), ("\u2028", "\\u2028"), ("\u2029", "\\u2029")]:
        encoded = encoded.replace(literal, escaped)
    return hashlib.sha256(encoded.encode()).hexdigest()


def problems(name: str, planned: dict) -> list[str]:
    result = planned["outputs"]["result"]["value"]
    all_resources = resources(planned["root_module"])
    if name.startswith("app-links-"):
        if all_resources:
            return ["app links must remain resource-free"]
        if result["paths"] != sorted(result["files"]):
            return ["file paths differ from keys"]
        if name in {"app-links-golden", "app-links-multiple"}:
            golden = json.loads((Path(__file__).parent / "fixtures" / "app-links-golden.json").read_text())
            callback_paths = APP["ios"]["paths"]
            if name == "app-links-multiple":
                golden["/.well-known/apple-app-site-association"]["applinks"]["details"].append({
                    "appIDs": [APP["ios"]["team_id"] + ".test.example.other"],
                    "components": [{"/": "/other"}, {"/": "/other/*"}],
                })
                golden["/.well-known/assetlinks.json"].append({
                    "relation": ["delegate_permission/common.handle_all_urls"],
                    "target": {"namespace": "android_app", "package_name": "test.example.other", "sha256_cert_fingerprints": [FINGERPRINT]},
                })
                callback_paths = callback_paths + ["/other", "/other/*"]
            expected = {
                path: {"content": json.dumps(content, sort_keys=True, separators=(",", ":")), "content_type": "application/json"}
                for path, content in golden.items()
            }
            if result != {"files": expected, "paths": sorted(expected), "callback_paths": callback_paths}:
                return ["golden association bytes or outputs differ"]
        elif name == "app-links-empty" and result != {"files": {}, "paths": [], "callback_paths": []}:
            return ["empty apps rendered placeholder files"]
        elif name == "app-links-ios-only" and (
            result["paths"] != ["/.well-known/apple-app-site-association"] or result["callback_paths"] != APP["ios"]["paths"]
        ):
            return ["iOS-only outputs differ"]
        elif name == "app-links-android-only" and (
            result["paths"] != ["/.well-known/assetlinks.json"] or result["callback_paths"] != []
        ):
            return ["Android-only outputs differ"]
        return []
    by_type = {resource["type"]: resource["values"] for resource in all_resources}
    expected_name = EXPECTED_NAMES.get(name, "example-static")
    if any(resource["metadata"][0]["name"] != expected_name for resource in by_type.values()):
        return ["resource names must equal the supplied name without suffixes"]
    if len(all_resources) != 4 or set(by_type) != {
        "kubernetes_config_map_v1", "kubernetes_deployment_v1", "kubernetes_service_v1", "kubernetes_pod_disruption_budget_v1"
    }:
        return ["responder must own exactly ConfigMap, Deployment, Service and PDB"]
    config = by_type["kubernetes_config_map_v1"]["data"]
    deployment = by_type["kubernetes_deployment_v1"]["spec"][0]
    template = deployment["template"][0]
    pod = template["spec"][0]
    container = pod["container"][0]
    security = container["security_context"][0]
    pod_security = pod["security_context"][0]
    tmp_volumes = [volume for volume in pod["volume"] if volume["name"] == "tmp"]
    if len(tmp_volumes) != 1 or tmp_volumes[0]["empty_dir"] != [{"medium": "Memory", "size_limit": "16Mi"}]:
        return ["writable tmpfs must be memory-backed and limited to 16Mi"]
    expected_files = EXPECTED_FILES[name]
    expected_replicas, expected_min_available = EXPECTED_SCALING.get(name, (2, 1))
    expected_checksum = config_checksum(config)
    if template["metadata"][0]["annotations"]["checksum/files"] != expected_checksum:
        return ["pod template checksum must cover the complete generated ConfigMap"]
    if name == "static-responder-updated":
        fixed_config = {**config, **{hashlib.sha256(path.encode()).hexdigest(): file["content"] for path, file in FILES.items()}}
        if expected_checksum == config_checksum(fixed_config):
            return ["updated content must change the fixed case's pod checksum"]
    for path, file in expected_files.items():
        escaped_path = path.replace("\\", "\\\\").replace('"', '\\"')
        escaped_type = file["content_type"].replace("\\", "\\\\").replace('"', '\\"')
        digest = hashlib.sha256(path.encode()).hexdigest()
        if config.get(digest) != file["content"] or f'location = "{escaped_path}"' not in config["nginx.conf"]:
            return ["fixed bytes or exact location differ"]
        if f'default_type "{escaped_type}";' not in config["nginx.conf"]:
            return ["content type was not safely quoted"]
    lines = config["nginx.conf"].splitlines()
    if name == "static-responder-fixed" and [line.strip() for line in lines if line.strip().startswith("listen ")] != ["listen 8080;"]:
        return ["nginx must listen on IPv4 only at port 8080"]
    if any(not line.strip() or line != line.rstrip() for line in lines):
        return ["nginx configuration must have no blank lines or trailing whitespace"]
    if "server_tokens off;" not in config["nginx.conf"]:
        return ["server version tokens must be disabled"]
    if "merge_slashes off;" not in config["nginx.conf"]:
        return ["nginx must not merge duplicated slashes"]
    if any(line.lstrip().startswith("location =") and not line.startswith("    location =") for line in config["nginx.conf"].splitlines()):
        return ["exact locations must be indented within the server block"]
    if "worker_processes 1;" not in config["nginx.conf"] or "location / { return 404; }" not in config["nginx.conf"] or "proxy_pass" in config["nginx.conf"]:
        return ["responder must return 404 otherwise and never proxy"]
    if not (
        pod_security["run_as_non_root"] and pod_security["run_as_user"] == "101"
        and pod_security["seccomp_profile"][0]["type"] == "RuntimeDefault"
        and security["read_only_root_filesystem"] and not security["allow_privilege_escalation"]
        and security["capabilities"][0]["drop"] == ["ALL"] and not pod["automount_service_account_token"] and not pod["enable_service_links"]
        and container["readiness_probe"] and container["liveness_probe"]
    ):
        return ["pod hardening or probes differ"]
    selector = deployment["selector"][0]["match_labels"]
    if not (
        deployment["replicas"] == str(expected_replicas)
        and by_type["kubernetes_service_v1"]["spec"][0]["selector"] == selector
        and by_type["kubernetes_pod_disruption_budget_v1"]["spec"][0]["selector"][0]["match_labels"] == selector
        and by_type["kubernetes_pod_disruption_budget_v1"]["spec"][0]["min_available"] == str(expected_min_available)
        and result == {"paths": sorted(expected_files), "service_name": expected_name, "service_port": EXPECTED_PORTS.get(name, 80)}
    ):
        return ["service, replicas, PDB or outputs differ"]
    return []


def nginx_problems(work: Path, planned: dict, case: str) -> list[str]:
    nginx = shutil.which("nginx")
    if nginx is None:
        print(f"SKIP native-nginx {case}: nginx is not on PATH")
        return []
    data = next(resource["values"]["data"] for resource in resources(planned["root_module"])
                if resource["type"] == "kubernetes_config_map_v1")
    config = data["nginx.conf"]
    config_path = work / "nginx.conf"
    config_path.write_text(config)
    (work / "logs").mkdir(exist_ok=True)
    checked = subprocess.run([nginx, "-t", "-p", str(work) + "/", "-c", str(config_path)],
                             text=True, capture_output=True)
    print(checked.stdout + checked.stderr, end="")
    if checked.returncode:
        return [f"nginx -t rejected the rendered {case} configuration"]
    print(f"PASS native-nginx {case} nginx -t")
    files = work / "files"
    files.mkdir()
    for key, content in data.items():
        if key != "nginx.conf":
            (files / key).write_text(content)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    config_path.write_text(config.replace("listen 8080;", f"listen 127.0.0.1:{port};")
                           .replace("/tmp/", str(work) + "/").replace("/srv/files/", str(files) + "/"))
    with (work / "runtime-nginx.log").open("w") as log:
        process = subprocess.Popen([nginx, "-p", str(work) + "/", "-c", str(config_path),
                                    "-g", "daemon off; master_process off;"], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 5
            while True:
                if process.poll() is not None or time.monotonic() >= deadline:
                    return ["native nginx did not start: " + (work / "runtime-nginx.log").read_text()]
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.02)
            requests = [(quote(path, safe="/"), 200, file) for path, file in EXPECTED_FILES[case].items()]
            if case == "static-responder-fixed":
                path = next(iter(FILES))
                requests.extend((target, status, FILES[path] if status == 200 else None) for target, status in [
                    (path + "?ignored=yes", 200), ("/unused/.." + path, 200),
                    ("/.well-known%2fexample.json", 200), ("/.well-known/%2e%2e/.well-known/example.json", 200),
                    ("/" + path, 404), (path.replace("/", "//", 2), 404),
                    (path.replace("/example.json", "//example.json"), 404), ("/missing", 404),
                ])
            for target, status, file in requests:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                try:
                    connection.request("GET", target)
                    response = connection.getresponse()
                    body = response.read()
                    content_type = response.getheader("Content-Type")
                    if response.status != status or (status == 200 and (
                        body != file["content"].encode() or content_type != file["content_type"]
                    )):
                        return [f"native nginx {target}: expected {status} with exact bytes and Content-Type for successful responses, got {response.status}, Content-Type={content_type!r}"]
                finally:
                    connection.close()
                print(f"PASS native-nginx GET {target} status={status} Content-Type={content_type!r}")
        except (OSError, http.client.HTTPException) as error:
            return [f"native nginx request failed: {error}"]
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    return []


def main() -> int:
    tofu = os.environ.get("TOFU", "tofu")
    with tempfile.TemporaryDirectory(prefix="association-renderer-") as scratch:
        root = Path(scratch)
        cache = root / "cache"
        cache.mkdir()
        env = {**os.environ, "TF_PLUGIN_CACHE_DIR": os.environ.get("TF_PLUGIN_CACHE_DIR", str(cache)),
               "TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE": "1"}
        registry = json.loads((ROOT / "terraform/contracts/scenarios/contract-cases.json").read_text())
        cases = [case for case in registry["cases"] if case["module"] in {"k8s-app-links", "k8s-static-responder"} and case["outcome"] == "fail"]
        if {case["name"] for case in cases} != set(DIAGNOSTICS):
            raise SystemExit("negative association manifest and executable cases differ")
        for case in cases:
            name = case["name"]
            work = root / name
            work.mkdir()
            (work / "main.tf").write_text(CASES[name].replace("../../../modules", str(ROOT / "terraform" / "modules")))
            init = subprocess.run([tofu, "init", "-backend=false", "-input=false", "-no-color"], cwd=work, env=env, text=True, capture_output=True)
            if init.returncode:
                raise SystemExit(init.stdout + init.stderr)
            plan = subprocess.run([tofu, "plan", "-refresh=false", "-input=false", "-lock=false", "-no-color", "-out=case.plan"],
                                  cwd=work, env=env, text=True, capture_output=True)
            diagnostics = " ".join((plan.stdout + plan.stderr).split())
            if plan.returncode == 0 or DIAGNOSTICS[name] not in diagnostics:
                raise SystemExit(name + ": wrong diagnostic\n" + plan.stdout + plan.stderr)
            if (name.startswith("static-responder-content-type-") or DIAGNOSTICS[name].startswith(("App name must", "name must be a DNS-1035"))) and len(re.findall(r"(?m)^Error:", plan.stdout + "\n" + plan.stderr)) != 1:
                raise SystemExit(name + ": expected exactly one diagnostic\n" + plan.stdout + plan.stderr)
            print(f"PASS renderer-negative {name} (fail: {DIAGNOSTICS[name]})")
    print(f"PASS renderer-negative association cases={len(cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
