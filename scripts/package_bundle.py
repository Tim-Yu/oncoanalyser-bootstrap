#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import tarfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_INCLUDE = [
    "README.md",
    "plan.md",
    "repos.example.json",
    "oncoanalyser.sh",
    "test_offline_stub.sh",
    "prepare_offline_cache.sh",
    "conf",
    "igenomes",
    ".nextflow",
    "singularity_cache",
    "ref_cache",
    "samplesheet.csv",
]

DEFAULT_EXCLUDE = [
    "work",
    "output",
    "output_stub",
    "logs",
    ".nextflow.log*",
    "work_offline_stub_retry3",
    "*.tmp",
]


@dataclass
class PartInfo:
    name: str
    size_bytes: int
    sha256: str


@dataclass
class ArtifactInfo:
    name: str
    source_path: str
    archive_name: str
    size_bytes: int
    sha256: str
    parts: list[PartInfo]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def should_exclude(rel_path: str, excludes: list[str]) -> bool:
    rel_name = rel_path.replace(os.sep, "/")
    for pattern in excludes:
        if fnmatch.fnmatch(rel_name, pattern) or rel_name.startswith(pattern.rstrip("/") + "/"):
            return True
    return False


def add_path(tar: tarfile.TarFile, source_root: Path, rel_path: str, excludes: list[str]) -> None:
    abs_path = source_root / rel_path
    if not abs_path.exists() and not abs_path.is_symlink():
        return
    if should_exclude(rel_path, excludes):
        return
    tar.add(abs_path, arcname=rel_path, recursive=False)
    if abs_path.is_dir():
        for child in sorted(abs_path.iterdir()):
            child_rel = str(Path(rel_path) / child.name)
            add_path(tar, source_root, child_rel, excludes)


def make_archive(source_root: Path, include: list[str], excludes: list[str], archive_path: Path) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w:gz") as tar:
        for item in include:
            rel = item.rstrip("/")
            abs_path = source_root / rel
            if not abs_path.exists() and not abs_path.is_symlink():
                continue
            add_path(tar, source_root, rel, excludes)


def split_file(archive_path: Path, part_size_bytes: int, parts_dir: Path, stem: str) -> list[PartInfo]:
    parts: list[PartInfo] = []
    parts_dir.mkdir(parents=True, exist_ok=True)
    with archive_path.open("rb") as source:
        index = 1
        while True:
            chunk = source.read(part_size_bytes)
            if not chunk:
                break
            part_name = f"{stem}.part{index:04d}"
            part_path = parts_dir / part_name
            with part_path.open("wb") as handle:
                handle.write(chunk)
            parts.append(
                PartInfo(
                    name=part_name,
                    size_bytes=len(chunk),
                    sha256=sha256_file(part_path),
                )
            )
            index += 1
    return parts


def main() -> int:
    parser = argparse.ArgumentParser(description="Package the oncoanalyser bundle into split archives.")
    parser.add_argument("--source", required=True, type=Path, help="Source bundle root")
    parser.add_argument("--output", required=True, type=Path, help="Output directory")
    parser.add_argument("--part-size-mib", type=int, default=50, help="Chunk size in MiB")
    parser.add_argument("--mode", choices=["raw", "release"], default="raw", help="Packaging target")
    parser.add_argument("--include", nargs="*", default=DEFAULT_INCLUDE, help="Relative paths to include")
    parser.add_argument("--exclude", nargs="*", default=DEFAULT_EXCLUDE, help="Relative paths or patterns to exclude")
    parser.add_argument(
        "--include-ref-cache-extracted",
        action="store_true",
        help="Include ref_cache_extracted payload (large, optional).",
    )
    args = parser.parse_args()

    source_root = args.source.resolve()
    output_root = args.output.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    archives_dir = output_root / "archives"
    parts_dir = output_root / "parts"
    parts_dir.mkdir(parents=True, exist_ok=True)

    part_size_bytes = args.part_size_mib * 1024 * 1024
    if args.mode == "raw" and args.part_size_mib > 95:
        raise SystemExit("Raw mode part size must be <= 95 MiB to stay below GitHub's 100 MiB hard limit.")
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    artifacts = []
    manifest = {
        "created_utc": timestamp,
        "source_root": str(source_root),
        "mode": args.mode,
        "part_size_bytes": part_size_bytes,
        "artifacts": artifacts,
    }

    bootstrap_items = [item for item in args.include if item in {"README.md", "plan.md", "repos.example.json", "oncoanalyser.sh", "test_offline_stub.sh", "prepare_offline_cache.sh", "conf", "igenomes", ".nextflow", "samplesheet.csv"}]
    payload_groups = [
        ("bootstrap", bootstrap_items),
        ("singularity-cache", ["singularity_cache"]),
        ("ref-cache", ["ref_cache"]),
    ]

    if args.include_ref_cache_extracted:
        payload_groups.append(("ref-cache-extracted", ["ref_cache_extracted"]))

    for name, include in payload_groups:
        archive_path = archives_dir / f"{name}.tar.gz"
        make_archive(source_root, include, args.exclude, archive_path)
        archive_sha = sha256_file(archive_path)
        parts = split_file(archive_path, part_size_bytes, parts_dir / name, name)
        artifacts.append(
            asdict(
                ArtifactInfo(
                    name=name,
                    source_path=str(source_root),
                    archive_name=archive_path.name,
                    size_bytes=archive_path.stat().st_size,
                    sha256=archive_sha,
                    parts=parts,
                )
            )
        )

    manifest_path = output_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
