#!/usr/bin/env python3
"""Build a clean Terraform module archive with its local dependency closure."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

SOURCE_RE = re.compile(r'(?m)^(?P<prefix>\s*source\s*=\s*")(?P<source>[^"\n]+)(?P<suffix>")')
EXCLUDED_NAMES = {".git", ".terraform", ".terraform.lock.hcl", ".DS_Store"}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def local_sources(module_dir: Path) -> list[str]:
    sources: list[str] = []
    for path in module_dir.rglob("*.tf"):
        if any(part in EXCLUDED_NAMES for part in path.parts):
            continue
        for match in SOURCE_RE.finditer(path.read_text()):
            source = match.group("source")
            if source.startswith("."):
                sources.append(source)
    return sources


def package_name(root: Path, module_dir: Path) -> str:
    relative = module_dir.relative_to(root).as_posix()
    return relative.replace("/", "__")


def collect(root: Path, entry: Path) -> dict[Path, str]:
    modules: dict[Path, str] = {}
    pending = [entry]
    while pending:
        module_dir = pending.pop()
        module_dir = module_dir.resolve()
        if module_dir in modules:
            continue
        if root not in module_dir.parents and module_dir != root:
            raise ValueError(f"local module escapes repository: {module_dir}")
        if not module_dir.is_dir():
            raise ValueError(f"local module directory does not exist: {module_dir}")
        package_path = "" if module_dir == entry else f"_dependencies/{package_name(root, module_dir)}"
        modules[module_dir] = package_path
        for source in local_sources(module_dir):
            target = (module_dir / source).resolve()
            if root not in target.parents and target != root:
                raise ValueError(f"local source escapes repository: {module_dir} -> {source}")
            pending.append(target)
    return modules


def copy_module(module_dir: Path, package_dir: Path, package_path: str, modules: dict[Path, str]) -> list[dict[str, str]]:
    destination = package_dir / package_path
    destination.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, str]] = []
    for source in sorted(module_dir.rglob("*")):
        if not source.is_file() or any(part in EXCLUDED_NAMES for part in source.parts):
            continue
        relative = source.relative_to(module_dir)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        content = source.read_text() if source.suffix in {".tf", ".tofu"} else None
        if content is not None:
            current_package_dir = PurePosixPath(package_path or ".")
            rewritten = SOURCE_RE.sub(
                lambda match: rewrite_source(match, source.parent, current_package_dir, modules),
                content,
            )
            target.write_text(rewritten)
        else:
            shutil.copy2(source, target)
        records.append({"path": str(Path(package_path, relative)), "sha256": digest(target)})
    return records


def rewrite_source(match: re.Match[str], current_source_dir: Path, current_package_dir: PurePosixPath, modules: dict[Path, str]) -> str:
    source = match.group("source")
    if not source.startswith("."):
        return match.group(0)
    target = current_source_dir.joinpath(source).resolve()
    target = target if target.is_dir() else target.parent
    target_package = modules.get(target)
    if target_package is None:
        raise ValueError(f"local source was not collected: {source}")
    target_posix = PurePosixPath(target_package or ".")
    rewritten = PurePosixPath(__import__("posixpath").relpath(str(target_posix), str(current_package_dir)))
    rewritten_text = rewritten.as_posix()
    if rewritten_text == ".":
        rewritten_text = "."
    elif not rewritten_text.startswith("."):
        rewritten_text = f"./{rewritten_text}"
    return f'{match.group("prefix")}{rewritten_text}{match.group("suffix")}'


def build(root: Path, module: str, output: Path, manifest_path: Path) -> None:
    entry = (root / module).resolve()
    modules = collect(root, entry)
    with tempfile.TemporaryDirectory(prefix="module-package-") as temporary:
        package_dir = Path(temporary) / "package"
        package_dir.mkdir()
        files: list[dict[str, str]] = []
        for module_dir, package_path in sorted(modules.items(), key=lambda item: item[1]):
            files.extend(copy_module(module_dir, package_dir, package_path, modules))
        manifest = {
            "schema_revision": "module-package-v1",
            "source_root": module,
            "modules": [
                {"source": str(path.relative_to(root)), "package_path": package_path}
                for path, package_path in sorted(modules.items(), key=lambda item: item[1])
            ],
            "files": files,
        }
        (package_dir / "MODULE-PACKAGE-MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        output.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(output, "w:gz") as archive:
            for path in sorted(package_dir.rglob("*")):
                if path.is_file():
                    archive.add(path, arcname=path.relative_to(package_dir).as_posix(), recursive=False)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps({**manifest, "archive_sha256": digest(output)}, indent=2, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    build(args.root.resolve(), args.module, args.output.resolve(), args.manifest.resolve())
    print(f"PASS package-build module={args.module} archive={args.output} manifest={args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
