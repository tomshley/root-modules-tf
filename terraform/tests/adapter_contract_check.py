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

"""Check that adapters consume shared decisions and the future publisher uses closure assembly."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def require(text: str, pattern: str, label: str) -> None:
    if not re.search(pattern, text, re.MULTILINE):
        raise SystemExit(f"missing {label}: {pattern}")


def reject_mutation(text: str, pattern: str, label: str) -> None:
    mutated = re.sub(pattern, "", text, count=1, flags=re.MULTILINE)
    try:
        require(mutated, pattern, label)
    except SystemExit:
        print(f"PASS adapter-negative {label}")
        return
    raise SystemExit(f"adapter guard failed to detect mutation: {label}")


def live_hcl(text: str, blank: bool = False) -> str:
    """Drop HCL comments, so a guard matches configuration that takes effect.

    Scans each character so a # or // inside a quoted string, a ${ }
    interpolation's own strings, or a heredoc body is kept, and removes
    /* */ blocks and #, // line comments everywhere else. With blank, the
    result keeps text's length and line breaks instead: comments, strings
    (with their templates), and heredocs become spaces, leaving only code.
    """
    out: list[str] = []

    def literal(part: str) -> str:
        return re.sub(r"[^\n]", " ", part) if blank else part

    modes: list[str | list[object]] = []  # "string", or ["template", brace depth]
    i, length = 0, len(text)
    while i < length:
        char = text[i]
        mode = modes[-1] if modes else None
        if mode == "string":
            step = 1
            if text.startswith(("$${", "%%{"), i):
                step = 3
            elif text.startswith(("${", "%{"), i):
                step = 2
                modes.append(["template", 0])
            elif char == "\\":
                step = 2
            elif char in '"\n':
                modes.pop()
            out.append(literal(text[i:i + step]))
            i += step
            continue
        heredoc = re.compile(r"<<-?([A-Za-z_][\w-]*)[ \t]*\n").match(text, i)
        if heredoc:
            closing = re.compile(rf"^[ \t]*{re.escape(heredoc.group(1))}[ \t]*$", re.MULTILINE).search(text, heredoc.end())
            end = length if closing is None else closing.end()
            out.append(literal(text[i:end]))
            i = end
        elif char == '"':
            modes.append("string")
            out.append(literal(char))
            i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = length if end == -1 else end + 2
            out.append(literal(text[i:end]) if blank else "")
            i = end
        elif char == "#" or text.startswith("//", i):
            end = text.find("\n", i)
            end = length if end == -1 else end
            out.append(literal(text[i:end]) if blank else "")
            i = end
        else:
            if mode is not None and char == "{":
                mode[1] += 1
            elif mode is not None and char == "}":
                if mode[1] == 0:
                    modes.pop()
                else:
                    mode[1] -= 1
            out.append(literal(char) if modes else char)
            i += 1
    return "".join(out)


def check_live_hcl() -> None:
    probes = (
        ('a = "x # y" # c\n', 'a = "x # y" \n'),
        ('a = "p//q" // c\n', 'a = "p//q" \n'),
        ('a = "q\\"#" # c\n', 'a = "q\\"#" \n'),
        ('a = "${trimprefix(x, "https://")}" # c\n', 'a = "${trimprefix(x, "https://")}" \n'),
        ('a = "$${x}#" # c\n', 'a = "$${x}#" \n'),
        ('a = "%{ if x == "#" }z%{ endif }" # c\n', 'a = "%{ if x == "#" }z%{ endif }" \n'),
        ('a = <<-EOT\n  /var/*.log "\n  # kept\n  EOT\nb = 1 # c\n/* d */c = 2\n', 'a = <<-EOT\n  /var/*.log "\n  # kept\n  EOT\nb = 1 \nc = 2\n'),
    )
    for source, expected in probes:
        if live_hcl(source) != expected:
            raise SystemExit(f"live_hcl kept or dropped the wrong text: {source!r} -> {live_hcl(source)!r}")
        if len(live_hcl(source, blank=True)) != len(source):
            raise SystemExit(f"live_hcl blank changed the length of {source!r}")
    blocks = (
        'module "x" {\n  b = "${f("{")}"\n}\nmodule "y" {\n  count = 1\n}\n',
        'module "x" {\n  b = <<-EOT\n    {\n  EOT\n}\nmodule "y" {\n  count = 1\n}\n',
        'module "x" {\n  b = "}" # }\n}\nmodule "y" {\n  count = 1\n}\n',
    )
    for source in blocks:
        if "count" in module_block(source, "x") or not module_block(source, "x").endswith("}"):
            raise SystemExit(f"module_block read past or short of its block: {source!r}")
    source = 'module "x" {\n  n = "{"\n  a = 1\n  m = "${f("}")}"\n  t = {\n    b = 2\n  }\n  h = <<-EOT\n    c = 3\n  EOT\n}\n'
    block = module_block(source, "x")
    arguments = module_arguments(block)
    if (
        "a = 1" not in arguments or "t = {" not in arguments or "h =" not in arguments
        or "b = 2" in arguments or "c = 3" in arguments or len(arguments) != len(block)
    ):
        raise SystemExit(f"module_arguments kept or dropped the wrong text: {source!r} -> {arguments!r}")
    print("PASS live-hcl-probes")


def text_floor(text: str) -> tuple[int, int] | None:
    """The highest lower bound among the live required_version constraints."""
    floors = []
    for constraints in re.findall(r'required_version\s*=\s*"([^"]*)"', live_hcl(text)):
        for constraint in constraints.split(","):
            bound = re.fullmatch(r"\s*(?:>=|~>|=)?\s*v?(\d+)\.(\d+)\S*\s*", constraint)
            if bound:
                floors.append((int(bound.group(1)), int(bound.group(2))))
    return max(floors) if floors else None


def declared_floor(module: Path) -> tuple[int, int]:
    """The lowest Terraform release a module's live required_version admits."""
    floors = [floor for path in sorted(module.glob("*.tf")) if (floor := text_floor(path.read_text()))]
    return max(floors) if floors else (0, 0)


def bracket_depth(text: str) -> int:
    """Brackets opened minus brackets closed in text, outside strings."""
    depth, quoted, i = 0, False, 0
    while i < len(text):
        char = text[i]
        if quoted:
            if char == "\\":
                i += 1
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        i += 1
    return depth


def without_outer_parentheses(expression: str) -> str:
    """expression with any parentheses that wrap all of it removed."""
    expression = expression.strip()
    while expression.startswith("(") and expression.endswith(")"):
        inner = expression[1:-1]
        depth = 0
        for char in inner:
            depth += {"(": 1, ")": -1}.get(char, 0)
            if depth < 0:
                return expression
        expression = inner.strip()
    return expression


def attribute_expressions(text: str) -> list[str]:
    """Each attribute's whole expression, its lines joined by single spaces.

    An attribute starts a line or follows a block's opening brace on it, as in
    output "x" { value = ... }. An expression runs on while its brackets are
    open, or while a line ends with, or the next starts with, ||, &&, ? or :.
    """
    lines = text.splitlines()
    expressions = []
    index = 0
    while index < len(lines):
        attribute = re.match(r'\s*(?:[\w-]+(?:\s+"[^"]*")*\s*\{\s*)?[\w-]+\s*=(?!=)\s*(.*)', lines[index])
        index += 1
        if not attribute:
            continue
        parts, depth = [attribute.group(1).strip()], bracket_depth(attribute.group(1))
        while index < len(lines) and (
            depth > 0 or re.search(r"(\|\||&&|\?|:)$", parts[-1]) or re.match(r"\s*(\|\||&&|\?|:)", lines[index])
        ):
            parts.append(lines[index].strip())
            depth += bracket_depth(lines[index])
            index += 1
        expression = " ".join(part for part in parts if part)
        while depth < 0 and expression.endswith("}"):
            expression, depth = expression[:-1].rstrip(), depth + 1
        expressions.append(expression)
    return expressions


# The expressions that combine a null test with || or && in the modules
# unsafe_null_guards covers, each checked on Terraform 1.5.7 with its values
# null, valid, and invalid.
REVIEWED_NULL_GUARDS = {
    ("aws-eks-nodegroup/variables.tf", "var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)"),
    ("gcp-gke-nodepool/variables.tf", "var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)"),
    ("karpenter-controller-contract/variables.tf", "var.contract.replicas == null || try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)"),
    ("karpenter-controller-contract/variables.tf", 'var.contract.priority_class_name == null || try(length(var.contract.priority_class_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.contract.priority_class_name)), false)'),
    ("cloudflare-access-guard/resources.tf", "local.normalized_zone_id != null || local.normalized_account_id != null"),
    ("cloudflare-access-guard/resources.tf", "!(local.normalized_zone_id != null && local.normalized_account_id != null)"),
}


def null_test_locals(text: str) -> set[str]:
    """Names of attributes, in any block, whose whole expression is a null test.

    The test is of a plain reference; parentheses around the expression or
    the test, and a ! before them, are allowed, as in (X == null) or
    !(X != null). Only a local's name is ever read back, as local.<name>, so
    another block's attribute of the same name at worst flags a guard.
    """
    names = set()
    null_test = re.compile(r'[\w.\[\]"-]+\s*(?:==|!=)\s*null|null\s*(?:==|!=)\s*[\w.\[\]"-]+')
    lines = text.splitlines()
    for index, line in enumerate(lines):
        named = re.match(r'\s*(?:[\w-]+(?:\s+"[^"]*")*\s*\{\s*)?([\w-]+)\s*=(?!=)', line)
        if not named:
            continue
        expression = without_outer_parentheses(attribute_expressions("\n".join(lines[index:]))[0])
        while expression.startswith("!"):
            expression = without_outer_parentheses(expression[1:])
        if null_test.fullmatch(expression):
            names.add(named.group(1))
    return names


def unsafe_null_guards(file: str, text: str, aliases: set[str] = frozenset()) -> list[str]:
    """Attribute expressions whose null test may not keep a null value out.

    Under a Terraform release whose || and && evaluate both sides, whatever a
    null test guards still runs on null, and whether a given guard survives
    that depends on what it calls. So an attribute expression that combines a
    null test with || or && must be one REVIEWED_NULL_GUARDS lists, unless it
    is a ternary whose condition is a null test of a plain reference alone,
    X == null ? ... : ..., with no other null test after the ?. Expressions
    are judged whole, however their lines are laid out and whatever
    parentheses wrap them; the condition may sit in one pair of its own. A
    local in aliases, one whose
    whole expression is a null test (null_test_locals), counts as a null
    test.

    This is a tripwire for the common ways to write a guard, not a parser.
    It does not follow other indirection (a variable, a nested local, a
    function's result, or a guard split across attributes), and it reads a
    heredoc body line that looks like an attribute as it reads any other
    line. A new guard in these modules is checked on a
    Terraform release whose || evaluates both sides before it joins
    REVIEWED_NULL_GUARDS.
    """
    null_test = re.compile(r"(?:==|!=)\s*null\b|\bnull\s*(?:==|!=)")
    ternary = re.compile(r'(\(?)\s*(?:[\w.\[\]"-]+\s*(?:==|!=)\s*null|null\s*(?:==|!=)\s*[\w.\[\]"-]+)\s*(\)?)\s*\?(.*)')
    found = []
    for expression in attribute_expressions(text):
        expression = without_outer_parentheses(expression)
        for alias in aliases:
            expression = re.sub(rf"\blocal\.{re.escape(alias)}\b", f"local_{alias} == null", expression)
        if not null_test.search(expression) or not re.search(r"\|\||&&", expression):
            continue
        if (file, expression) in REVIEWED_NULL_GUARDS:
            continue
        branches = ternary.fullmatch(expression)
        if branches and len(branches.group(1)) == len(branches.group(2)) and not null_test.search(branches.group(3)):
            continue
        found.append(expression)
    return found


def matching_bracket_end(text: str, start: int) -> int:
    """Index just past the bracket that closes the one at start, in code.

    Brackets in comments, strings and their templates, and heredocs do not
    count: the scan runs on live_hcl(text, blank=True).
    """
    code, depth = live_hcl(text, blank=True), 0
    for end in range(start, len(code)):
        if code[end] in "([{":
            depth += 1
        elif code[end] in ")]}":
            depth -= 1
            if depth == 0:
                return end + 1
    return len(text)


def ignored_size_fields(text: str) -> list[str]:
    """ignore_changes values in text that name a node pool's or group's size."""
    size_fields = re.compile(r"\b(?:scaling_config|desired_size|min_size|max_size|node_count|autoscaling|all)\b")
    found = []
    for start in re.finditer(r"ignore_changes\s*=\s*", text):
        end = start.end()
        if text.startswith("[", end):
            end = matching_bracket_end(text, end)
        else:
            end += len(re.match(r"\w*", text[end:]).group(0))
        ignored = text[start.end():end]
        if size_fields.search(ignored):
            found.append(ignored)
    return found


def module_block(text: str, name: str) -> str:
    """The whole module "name" { ... } block, or "" when there is none."""
    start = text.find(f'module "{name}" {{')
    if start == -1:
        return ""
    return text[start:matching_bracket_end(text, text.index("{", start))]


def module_arguments(block: str) -> str:
    """block with only its own top-level arguments left, at the same length.

    Text inside brackets nested in the block's braces, and heredoc body
    lines, become spaces (line breaks kept), so a line there is not read as
    one of the block's arguments.
    """
    code = live_hcl(block, blank=True)
    depth = 0
    kept = []
    for i, char in enumerate(code):
        if char in "([{":
            depth += 1
        kept.append(block[i] if char == "\n" or depth <= 1 or char in "(){}[]" else " ")
        if char in ")]}":
            depth -= 1
    own = "".join(kept)
    return "\n".join(
        line if line.strip() == "" or live.strip() != "" else " " * len(line)
        for line, live in zip(own.split("\n"), code.split("\n"))
    )


def main() -> int:
    publisher = (ROOT / ".gitlab-ci.yml").read_text()
    require(publisher, r"CICD_PIPELINES_PYTHON_IMAGE", "pinned Python publication image")
    require(publisher, r"tools/module-package/package_module\.py", "dependency-closed publication assembly")
    require(publisher, r"tools/module-package/publish_module\.py", "verified module uploader")
    if "tar -vczf" in publisher:
        raise SystemExit("old module-only tar publication path remains")
    print("PASS publisher-uses-closure-assembly")

    aurora_locals = (ROOT / "terraform/modules/aws-eks-aurora-cluster/locals.tf").read_text()
    aurora_resources = (ROOT / "terraform/modules/aws-eks-aurora-cluster/resources.tf").read_text()
    require(aurora_locals, r"module\.tenancy_contract\.tenant_bindings", "shared tenant role derivation")
    require(aurora_resources, r"module \"tenancy_contract\"", "AWS tenancy contract consumer")
    require(aurora_locals, r"resolved_backup_retention_period", "AWS retention derivation")
    reject_mutation(aurora_locals, r"module\.tenancy_contract\.tenant_bindings", "tenant derivation ownership")
    gcp_karpenter = live_hcl((ROOT / "terraform/modules/gcp-karpenter-controller-release/resources.tf").read_text())
    aws_karpenter = live_hcl((ROOT / "terraform/modules/aws-eks-karpenter-controller/resources.tf").read_text())
    for label, text in (("GCP", gcp_karpenter), ("AWS", aws_karpenter)):
        require(text, r"module \"controller_contract\"\s*\{\s*source\s*=\s*\"\.\./karpenter-controller-contract\"", f"{label} Karpenter controller contract consumer")
        require(text, r"module\.controller_contract\.contract", f"{label} Karpenter controller contract decisions")
        require(text, r"module\.controller_contract\.node_affinity_off_karpenter_nodes", f"{label} shared Karpenter controller node affinity")
    print("PASS karpenter-controller-contract-consumers")
    reject_mutation(gcp_karpenter, r"module\.controller_contract\.node_affinity_off_karpenter_nodes", "GCP Karpenter node affinity ownership")
    reject_mutation(aws_karpenter, r"module\.controller_contract\.node_affinity_off_karpenter_nodes", "AWS Karpenter node affinity ownership")
    # Environment pause: each cloud keeps its half of every pause capability.
    # Matching runs on live_hcl text, so commented-out wiring does not count.
    pause_twins = (
        ("gcp-gke-nodepool", "aws-eks-nodegroup", "node_count", "node_count must be null or a whole number of nodes, 0 or more."),
        ("gcp-cloudsql-postgres", "aws-eks-aurora-cluster", "activation_policy", 'var.activation_policy == null ? true : contains(["ALWAYS", "NEVER"], var.activation_policy)'),
    )
    twin_variables = {}
    for gcp_module, aws_module, variable, shared in pause_twins:
        for module in (gcp_module, aws_module):
            text = live_hcl((ROOT / f"terraform/modules/{module}/variables.tf").read_text())
            twin_variables[module] = text
            require(text, rf'variable "{variable}" \{{', f"{module} pause input {variable}")
            require(text, re.escape(shared), f"{module} {variable} shared rule")
    # node_count reaches the live size only while nothing ignores it.
    for module, kind, field in (("gcp-gke-nodepool", "google_container_node_pool", "autoscaling"), ("aws-eks-nodegroup", "aws_eks_node_group", "scaling_config[0].desired_size")):
        resources = live_hcl((ROOT / f"terraform/modules/{module}/resources.tf").read_text())
        for ignored in ignored_size_fields(resources):
            raise SystemExit(f"{module} ignores changes to its size, so node_count cannot pause it: {ignored}")
        resource = re.search(rf'resource "{kind}" "[^"]+" \{{\n', resources).group(0)
        for ignored in (f"[{field}]", "[node_count]", "all", f"[launch_template[0].version, {field}]"):
            mutated = resources.replace(resource, f"{resource}  lifecycle {{\n    ignore_changes = {ignored}\n  }}\n", 1)
            if not ignored_size_fields(mutated):
                raise SystemExit(f"adapter guard failed to detect mutation: {module} ignoring {ignored}")
        existing = re.search(r"ignore_changes\s*=\s*\[", resources)
        if existing:
            close = matching_bracket_end(resources, existing.end() - 1) - 1
            appended = resources[:close] + "  node_count,\n    " + resources[close:]
            if not ignored_size_fields(appended):
                raise SystemExit(f"adapter guard failed to detect mutation: {module} appending node_count to its ignore_changes")
        print(f"PASS adapter-negative {module} size ignored")
    print("PASS pause-node-count-not-ignored")
    reject_mutation(twin_variables["gcp-gke-nodepool"], r'variable "node_count" \{', "GKE pause input node_count")
    reject_mutation(twin_variables["aws-eks-nodegroup"], r'variable "node_count" \{', "EKS pause input node_count")
    reject_mutation(twin_variables["aws-eks-aurora-cluster"], r'variable "activation_policy" \{', "Aurora pause input activation_policy")
    # Aurora readers go after the writer, so removing every instance
    # deletes them first and the writer's deletion causes no failover.
    aurora_live = live_hcl(aurora_resources)
    require(aurora_live, r"depends_on = \[aws_rds_cluster_instance\.writer\]", "Aurora readers ordered after the writer")
    reject_mutation(aurora_live, r"depends_on = \[aws_rds_cluster_instance\.writer\]", "Aurora reader ordering")
    # Each pause example wires every pause capability of its cloud.
    nodeclaim_lookup = (
        r'data "kubernetes_resources" "nodeclaim_crd" \{\s*count\s*=\s*var\.paused \? 1 : 0\s*'
        r'api_version\s*=\s*"apiextensions\.k8s\.io/v1"\s*kind\s*=\s*"CustomResourceDefinition"\s*'
        r'field_selector\s*=\s*"metadata\.name=nodeclaims\.karpenter\.sh"\s*\}'
    )
    nodeclaim_guard = (
        r'data "kubernetes_resources" "nodeclaims" \{\s*count\s*=\s*var\.paused && length\(coalesce\(try\(data\.kubernetes_resources\.nodeclaim_crd\[0\]\.objects, null\), \[\]\)\) > 0 \? 1 : 0\s*'
        r'api_version\s*=\s*"karpenter\.sh/v1"\s*kind\s*=\s*"NodeClaim"\s*lifecycle\s*\{\s*postcondition\s*\{\s*'
        r"condition\s*=\s*length\(coalesce\(self\.objects, \[\]\)\) == 0\s*error_message\s*=\s*\"[^\"]*\"\s*\}\s*\}\s*\}"
    )
    gmp_guard = (
        r'data "kubernetes_resources" "gmp_priority_class" \{\s*count\s*=\s*var\.paused \? 0 : 1\s*'
        r'api_version\s*=\s*"scheduling\.k8s\.io/v1"\s*kind\s*=\s*"PriorityClass"\s*field_selector\s*=\s*"metadata\.name=gmp-critical"\s*'
        r"lifecycle\s*\{\s*postcondition\s*\{\s*condition\s*=\s*length\(coalesce\(self\.objects, \[\]\)\) == 1\s*error_message\s*=\s*\"[^\"]*\"\s*\}\s*\}\s*\}"
    )
    example_wiring = (
        ("gcp-gke-environment-pause/node-provisioning", r'module "karpenter_controller" \{\s*count\s*=\s*var\.paused \? 0 : 1[ \t]*$', "GKE example controller removed"),
        ("gcp-gke-environment-pause/node-provisioning", gmp_guard, "GKE example gmp-critical guard"),
        ("gcp-gke-environment-pause/node-provisioning", nodeclaim_lookup, "GKE example NodeClaim CRD lookup"),
        ("gcp-gke-environment-pause/node-provisioning", nodeclaim_guard, "GKE example NodeClaim guard"),
        ("aws-eks-environment-pause/node-provisioning", r'module "karpenter_controller" \{\s*count\s*=\s*var\.paused \? 0 : 1[ \t]*$', "EKS example controller removed"),
        ("aws-eks-environment-pause/node-provisioning", nodeclaim_lookup, "EKS example NodeClaim CRD lookup"),
        ("aws-eks-environment-pause/node-provisioning", nodeclaim_guard, "EKS example NodeClaim guard"),
    )
    raw_examples: dict[str, str] = {}
    examples: dict[str, str] = {}
    for root in (
        "gcp-gke-environment-pause/cluster",
        "aws-eks-environment-pause/cluster",
        "gcp-gke-environment-pause/node-provisioning",
        "aws-eks-environment-pause/node-provisioning",
    ):
        raw_examples[root] = (ROOT / "terraform/examples" / root / "main.tf").read_text()
        examples[root] = live_hcl(raw_examples[root])
    # Each pause input is a whole top-level argument of the module it pauses
    # or places, so a lookalike such as initial_node_count, or the same line
    # nested in a map or inside a heredoc, does not count.
    block_wiring = (
        ("gcp-gke-environment-pause/cluster", "baseline_pool", r"node_count\s*=\s*var\.paused \? 0 : null", "GKE example pool at zero"),
        ("gcp-gke-environment-pause/cluster", "database", r'activation_policy\s*=\s*var\.paused \? "NEVER" : null', "GKE example Cloud SQL stopped"),
        ("gcp-gke-environment-pause/cluster", "cluster", r"managed_prometheus\s*=\s*!var\.paused", "GKE example Managed Prometheus restored"),
        ("gcp-gke-environment-pause/cluster", "cluster", r"monitoring_components\s*=\s*var\.paused \? null : local\.\w+", "GKE example monitoring components restored"),
        ("aws-eks-environment-pause/cluster", "baseline_nodes", r"node_count\s*=\s*var\.paused \? 0 : null", "EKS example node group at zero"),
        ("aws-eks-environment-pause/cluster", "database", r'activation_policy\s*=\s*var\.paused \? "NEVER" : null', "EKS example Aurora instances removed"),
        ("gcp-gke-environment-pause/node-provisioning", "karpenter_controller", r"keep_controller_off_karpenter_nodes\s*=\s*true", "GKE example controller off Karpenter nodes"),
        ("gcp-gke-environment-pause/node-provisioning", "karpenter_controller", r'preference_policy\s*=\s*"Ignore"', "GKE example Ignore preference policy"),
        ("aws-eks-environment-pause/node-provisioning", "karpenter_controller", r"controller_replicas\s*=\s*1", "EKS example single controller replica"),
    )
    for root, module, pattern, label in block_wiring:
        require(module_arguments(module_block(examples[root], module)), rf"^\s*{pattern}\s*$", label)
    for root, module, pattern, label in block_wiring:
        attribute = pattern.split("\\s*")[0]
        block = module_block(examples[root], module)
        lookalike = re.sub(rf"^(\s*){attribute}\b", rf"\1initial_{attribute}", block, count=1, flags=re.MULTILINE)
        if lookalike == block or re.search(rf"^\s*{pattern}\s*$", module_arguments(module_block(examples[root].replace(block, lookalike), module)), re.MULTILINE):
            raise SystemExit(f"adapter guard failed to detect mutation: {label}")
        line = re.search(rf"^\s*{pattern}", block, re.MULTILINE).group(0)
        continued = block.replace(line, line + " ? null : false", 1)
        if re.search(rf"^\s*{pattern}\s*$", module_arguments(module_block(examples[root].replace(block, continued), module)), re.MULTILINE):
            raise SystemExit(f"adapter guard failed to detect mutation: {label} continued")
        indent = re.match(r"\s*", line).group(0)
        nested = block.replace(line, f"{indent}tags = {{\n  {line}\n{indent}}}", 1)
        if re.search(rf"^\s*{pattern}\s*$", module_arguments(module_block(examples[root].replace(block, nested), module)), re.MULTILINE):
            raise SystemExit(f"adapter guard failed to detect mutation: {label} nested")
        heredoc = block.replace(line, f"{indent}note = <<-EOT\n{line}\n{indent}EOT", 1)
        if re.search(rf"^\s*{pattern}\s*$", module_arguments(module_block(examples[root].replace(block, heredoc), module)), re.MULTILINE):
            raise SystemExit(f"adapter guard failed to detect mutation: {label} in a heredoc")
        print(f"PASS adapter-negative {label} renamed, continued, nested, or in a heredoc")
    for root, pattern, label in example_wiring:
        if root not in examples:
            path = ROOT / "terraform/examples" / root / "main.tf"
            if not path.is_file():
                raise SystemExit(f"missing pause example root: {root}")
            raw_examples[root] = path.read_text()
            examples[root] = live_hcl(raw_examples[root])
        require(examples[root], pattern, label)
    gke_cluster_example = raw_examples["gcp-gke-environment-pause/cluster"]
    reject_mutation(module_block(examples["gcp-gke-environment-pause/cluster"], "cluster"), r"managed_prometheus\s*=\s*!var\.paused", "GKE example Managed Prometheus restore")
    commented_source = gke_cluster_example.replace("managed_prometheus    = !var.paused", "# managed_prometheus    = !var.paused")
    if commented_source == gke_cluster_example:
        raise SystemExit("GKE example Managed Prometheus restore comment probe did not match the example")
    commented = live_hcl(commented_source)
    if re.search(r"managed_prometheus\s*=\s*!var\.paused", commented):
        raise SystemExit("adapter guard failed to detect mutation: GKE example Managed Prometheus restore commented out")
    print("PASS adapter-negative GKE example Managed Prometheus restore commented out")
    reject_mutation(module_block(examples["gcp-gke-environment-pause/cluster"], "cluster"), r"monitoring_components\s*=\s*var\.paused \? null : local\.\w+", "GKE example monitoring components restore")
    commented_source = gke_cluster_example.replace("monitoring_components = var.paused ? null : local.monitoring_components", "# monitoring_components = var.paused ? null : local.monitoring_components")
    if commented_source == gke_cluster_example:
        raise SystemExit("GKE example monitoring components restore comment probe did not match the example")
    commented = live_hcl(commented_source)
    if re.search(r"monitoring_components\s*=\s*var\.paused", commented):
        raise SystemExit("adapter guard failed to detect mutation: GKE example monitoring components restore commented out")
    print("PASS adapter-negative GKE example monitoring components restore commented out")
    reject_mutation(examples["gcp-gke-environment-pause/node-provisioning"], r'module "karpenter_controller" \{\s*count\s*=\s*var\.paused \? 0 : 1[ \t]*$', "GKE example controller removal")
    reject_mutation(examples["gcp-gke-environment-pause/node-provisioning"], gmp_guard, "GKE example gmp-critical guard")
    for root in ("gcp-gke-environment-pause/node-provisioning", "aws-eks-environment-pause/node-provisioning"):
        removed = r'module "karpenter_controller" \{\s*count\s*=\s*var\.paused \? 0 : 1[ \t]*$'
        continued = examples[root].replace("count  = var.paused ? 0 : 1\n", "count  = var.paused ? 0 : 1 - 1\n", 1)
        if continued == examples[root] or re.search(removed, continued, re.MULTILINE):
            raise SystemExit(f"adapter guard failed to detect mutation: {root} controller removal continued")
        print(f"PASS adapter-negative {root} controller removal continued")
    reject_mutation(examples["aws-eks-environment-pause/node-provisioning"], nodeclaim_guard, "EKS example NodeClaim guard")
    # Everything but the controller stays through a pause: the cluster roots'
    # network, cluster, baseline nodes, and database, and the node-provisioning
    # roots' prerequisites and CRDs. Their blocks carry no count or for_each,
    # wherever in the block one would go.
    repeated = re.compile(r"^\s*(?:count|for_each)\s*=", re.MULTILINE)
    kept_modules = (
        ("gcp-gke-environment-pause/cluster", "network"),
        ("gcp-gke-environment-pause/cluster", "cluster"),
        ("gcp-gke-environment-pause/cluster", "baseline_pool"),
        ("gcp-gke-environment-pause/cluster", "database"),
        ("aws-eks-environment-pause/cluster", "vpc"),
        ("aws-eks-environment-pause/cluster", "cluster"),
        ("aws-eks-environment-pause/cluster", "baseline_nodes"),
        ("aws-eks-environment-pause/cluster", "database"),
        ("gcp-gke-environment-pause/node-provisioning", "karpenter_prereqs"),
        ("gcp-gke-environment-pause/node-provisioning", "karpenter_crds"),
        ("aws-eks-environment-pause/node-provisioning", "karpenter_prereqs"),
    )
    for root, module in kept_modules:
        block = module_block(examples[root], module)
        if not block or repeated.search(block):
            raise SystemExit(f"{root} no longer keeps module {module} through a pause")
    print("PASS environment-pause-examples-keep-everything-but-the-controller")
    for root, module in kept_modules:
        block = module_block(examples[root], module)
        source = re.search(r"^(\s*source\s*=.*\n)", block, re.MULTILINE).group(1)
        for extra in ("  count  = var.paused ? 0 : 1\n", '  for_each = var.paused ? {} : { kept = true }\n'):
            if not repeated.search(module_block(examples[root].replace(block, block.replace(source, source + extra)), module)):
                raise SystemExit(f"adapter guard failed to detect mutation: {root} {module} removed on pause")
        print(f"PASS adapter-negative {root} {module} removed on pause")
    check_live_hcl()
    # The controller contract and the AWS controller keep their 1.2 floor: a
    # higher one raises callers' floor in a patch release and takes both out
    # of this rule.
    for module in ("karpenter-controller-contract", "aws-eks-karpenter-controller"):
        if declared_floor(ROOT / "terraform/modules" / module) != (1, 2):
            raise SystemExit(f"{module} no longer declares required_version >= 1.2")
    contract_provider = (ROOT / "terraform/modules/karpenter-controller-contract/provider.tf").read_text()
    if (
        text_floor(contract_provider + 'terraform {\n  required_version = ">= 1.9"\n}\n') != (1, 9)
        or text_floor(contract_provider.replace('">= 1.2"', '">= 1.2, >= 1.9"')) != (1, 9)
        or text_floor(contract_provider.replace('required_version', '# required_version')) is not None
    ):
        raise SystemExit("adapter guard failed to detect mutation: Karpenter controller floor raised or commented out")
    print("PASS adapter-negative Karpenter controller floor raised or commented out")
    # Modules that declare no floor, or one below 1.9, also run under Terraform
    # releases whose || and && evaluate both sides, so a null check there is
    # a ternary or one REVIEWED_NULL_GUARDS lists; see unsafe_null_guards.
    for module in sorted((ROOT / "terraform/modules").iterdir()):
        if module.is_dir() and declared_floor(module) < (1, 9):
            aliases = set().union(*(null_test_locals(live_hcl(path.read_text())) for path in module.glob("*.tf")))
            for path in sorted(module.glob("*.tf")):
                for line in unsafe_null_guards(f"{module.name}/{path.name}", live_hcl(path.read_text()), aliases):
                    raise SystemExit(f"null check that does not keep a null value out in {module.name}/{path.name}: {line}")
    null_mutations = (
        ("contract preference_policy", "karpenter-controller-contract/variables.tf", "preference_policy == null ? true : contains(", "preference_policy == null || contains("),
        ("contract replicas", "karpenter-controller-contract/variables.tf", "replicas == null || try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)", "replicas == null || var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas"),
        ("EKS node_count", "aws-eks-nodegroup/variables.tf", "node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)", "node_count == null || floor(var.node_count) == var.node_count"),
        ("AWS preference_policy precondition", "aws-eks-karpenter-controller/resources.tf", "preference_policy == null ? true : local.karpenter_reads_preference", "preference_policy != null && local.karpenter_version_major >= 1"),
        ("contract replicas narrowed try", "karpenter-controller-contract/variables.tf", "try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)", "try(var.contract.replicas >= 1, false) && floor(var.contract.replicas) == var.contract.replicas"),
        ("contract replicas trailing call", "karpenter-controller-contract/variables.tf", "try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)", "try(var.contract.replicas, 0) == floor(var.contract.replicas)"),
        ("contract priority class extra alternative", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name)), false)", "var.contract.priority_class_name)), false) || length(var.contract.priority_class_name) > 0"),
        ("EKS node_count reversed null test on its own line", "aws-eks-nodegroup/variables.tf", "var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)", "null == var.node_count\n    || var.node_count >= 0"),
        ("contract priority class parenthesised null test", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name == null || try(", "(var.contract.priority_class_name == null) || length(var.contract.priority_class_name) > 0 || try("),
        ("contract priority class negated null test", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name == null || try(", "!(var.contract.priority_class_name != null) || length(var.contract.priority_class_name) > 0 || try("),
        ("contract priority class try without fallback", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name)), false)", "var.contract.priority_class_name)))"),
        ("contract priority class try with null fallback", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name)), false)", "var.contract.priority_class_name)), null)"),
        ("contract priority class try with number fallback", "karpenter-controller-contract/variables.tf", "var.contract.priority_class_name)), false)", "var.contract.priority_class_name)), 0)"),
        ("contract priority class guard continued in parentheses", "karpenter-controller-contract/variables.tf", 'condition     = var.contract.priority_class_name == null || try(', 'condition     = (\n      var.contract.priority_class_name == null ||\n      try('),
        ("contract priority class compound guard", "karpenter-controller-contract/variables.tf", 'var.contract.priority_class_name == null || try(', '(var.contract.priority_class_name == null || var.contract.replicas == null) || length(var.contract.priority_class_name) > 0 || try('),
        ("contract priority class guard over a call", "karpenter-controller-contract/variables.tf", 'var.contract.priority_class_name == null || try(', 'try(var.contract.priority_class_name, null) == null || var.contract.priority_class_name.x == null || try('),
        ("contract priority class negated reference", "karpenter-controller-contract/variables.tf", 'var.contract.priority_class_name == null || try(', '!var.contract.priority_class_name == null || try('),
        ("contract priority class null test parenthesised across lines", "karpenter-controller-contract/variables.tf", "condition     = var.contract.priority_class_name == null || try(", "condition     = (\n      var.contract.priority_class_name == null\n    ) || length(var.contract.priority_class_name) > 0 || try("),
        ("contract priority class guard line ending in ||", "karpenter-controller-contract/variables.tf", "condition     = var.contract.priority_class_name == null || try(", "condition     = (var.contract.priority_class_name == null ||\n      var.contract.priority_class_name > 0) || try("),
        ("contract replicas nullable index key", "karpenter-controller-contract/variables.tf", "var.contract.replicas == null || try(", "var.contract.replicas == null || local.m[var.contract.replicas] == null || try("),
        ("contract replicas try returning the null value", "karpenter-controller-contract/variables.tf", "var.contract.replicas == null || try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)", "var.contract.replicas == null || try(var.contract.replicas, false)"),
        ("contract replicas ternary branch with its own null guard", "karpenter-controller-contract/variables.tf", "var.contract.replicas == null || try(var.contract.replicas >= 1 && floor(var.contract.replicas) == var.contract.replicas, false)", "var.contract.replicas == null ? true : var.contract.priority_class_name == null || length(var.contract.priority_class_name) > 0"),
        ("contract one-line output block", "karpenter-controller-contract/variables.tf", 'variable "contract" {', 'output "probe" { value = var.contract.replicas == null || floor(var.contract.replicas) > 0 }\nvariable "contract" {'),
        ("contract null test through a local", "karpenter-controller-contract/variables.tf", 'variable "contract" {', 'locals { replicas_unset = var.contract.replicas == null }\noutput "probe" {\n  value = local.replicas_unset || floor(var.contract.replicas) > 0\n}\nvariable "contract" {'),
        ("contract null test through a parenthesised local", "karpenter-controller-contract/variables.tf", 'variable "contract" {', 'locals { replicas_unset = (var.contract.replicas == null) }\noutput "probe" {\n  value = local.replicas_unset || floor(var.contract.replicas) > 0\n}\nvariable "contract" {'),
        ("contract null test through a negated local across lines", "karpenter-controller-contract/variables.tf", 'variable "contract" {', 'locals {\n  replicas_unset = !(\n    var.contract.replicas != null\n  )\n}\noutput "probe" {\n  value = local.replicas_unset || floor(var.contract.replicas) > 0\n}\nvariable "contract" {'),
        ("EKS node_count attribute behind its null test", "aws-eks-nodegroup/variables.tf", "var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)", "var.node_count == null || var.node_count.min == null"),
    )
    for label, path, live, broken in null_mutations:
        text = live_hcl((ROOT / "terraform/modules" / path).read_text())
        if live not in text:
            raise SystemExit(f"null-check mutation no longer applies to {path}: {live}")
        mutated = text.replace(live, broken)
        if not unsafe_null_guards(path, mutated, null_test_locals(mutated)):
            raise SystemExit(f"adapter guard failed to detect mutation: unguarded null check in {label}")
        print(f"PASS adapter-negative unguarded null check in {label}")
    allowed = (
        "  condition     = var.x == null ? true : (var.x >= 1 && var.x <= 10)\n"
        '  condition     = var.p == null ? true : contains(["a"], var.p) || var.p == "b"\n'
        "  condition     = (var.x == null ? true : var.x >= 1 && var.x <= 10)\n"
        "  condition     = (\n    var.x == null ? true : var.x >= 1 && var.x <= 10\n  )\n"
        "  condition     = (var.x == null) ? true : var.x >= 1 && var.x <= 10\n"
    )
    if unsafe_null_guards("probe.tf", allowed):
        raise SystemExit(f"null-guard rule refuses the ternary it asks for: {unsafe_null_guards('probe.tf', allowed)}")
    print("PASS null-guard rule accepts a ternary on a null test")
    print("PASS environment-pause-parity")
    keycloak_wrapper = (ROOT / "terraform/modules/aws-eks-keycloak/resources.tf").read_text()
    metrics_variables = (ROOT / "terraform/modules/aws-eks-metrics-server/variables.tf").read_text()
    metrics_resources = (ROOT / "terraform/modules/aws-eks-metrics-server/resources.tf").read_text()
    require(keycloak_wrapper, r"app\.kubernetes\.io/managed-by", "legacy Keycloak managed label")
    require(keycloak_wrapper, r"secrets-manager/arn", "legacy Keycloak secret annotations")
    keycloak_adapter = (ROOT / "terraform/modules/aws-keycloak/resources.tf").read_text()
    keycloak_outputs = (ROOT / "terraform/modules/aws-keycloak/outputs.tf").read_text()
    admin_credential_condition = r"var\.admin_password != null \|\| var\.admin_secret_arn != null"
    admin_credential_message = "Either admin_password or admin_secret_arn must be provided. Without both, Keycloak would start with no usable admin credentials."
    require(keycloak_adapter, r'check "admin_credentials_provided"', "legacy Keycloak credential check")
    require(keycloak_adapter, admin_credential_condition, "legacy Keycloak credential check condition")
    require(keycloak_adapter, re.escape(admin_credential_message), "legacy Keycloak credential warning message")
    require(keycloak_outputs, admin_credential_condition, "legacy Keycloak credential hard gate")
    require(keycloak_outputs, re.escape(admin_credential_message), "legacy Keycloak credential hard-gate message")
    reject_mutation(keycloak_adapter, re.escape(admin_credential_message), "Keycloak credential warning message")
    reject_mutation(keycloak_outputs, re.escape(admin_credential_message), "Keycloak credential hard-gate message")
    require(metrics_variables, r'variable "metrics_server_version"', "legacy Metrics Server version input")
    require(metrics_variables, r'variable "metrics_server_namespace"', "legacy Metrics Server namespace input")
    require(metrics_resources, r"var\.metrics_server_version", "legacy Metrics Server version wiring")
    require(metrics_resources, r"var\.metrics_server_namespace", "legacy Metrics Server namespace wiring")
    reject_mutation(keycloak_wrapper, r"app\.kubernetes\.io/managed-by", "Keycloak managed label")
    reject_mutation(metrics_variables, r'variable "metrics_server_version"', "Metrics Server version input")
    for moved_file, marker in {
        "aws-eks-keycloak/moved.tf": "module.keycloak.module.keycloak",
        "aws-eks-grafana-alloy/moved.tf": "module.alloy.helm_release.k8s_monitoring",
        "aws-eks-metrics-server/moved.tf": "module.metrics_server.helm_release.metrics_server",
    }.items():
        require((ROOT / "terraform/modules" / moved_file).read_text(), re.escape(marker), f"reviewed state move {moved_file}")
    print("PASS aws-legacy-interface-and-state-map")

    gcp_resources = (ROOT / "terraform/modules/gcp-cloudsql-postgres/resources.tf").read_text()
    gcp_variables = (ROOT / "terraform/modules/gcp-cloudsql-postgres/variables.tf").read_text()
    require(gcp_resources, r"transaction_log_retention_days\s*=\s*module\.workload_contract\.contract\.retention_days", "GCP elapsed retention mapping")
    require(gcp_resources, r"retention_days\s*<=\s*7", "GCP unsupported-retention refusal")
    require(gcp_variables, r"retention_days\s*<=\s*7", "GCP retention input validation")
    reject_mutation(gcp_resources, r"transaction_log_retention_days\s*=\s*module\.workload_contract\.contract\.retention_days", "GCP retention mapping")
    print("PASS gcp-retention-contract")

    print("PASS adapter-source-guard")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
