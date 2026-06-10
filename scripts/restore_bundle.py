#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
from pathlib import Path
from urllib.request import urlopen, Request


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(request) as response, dest.open("wb") as handle:
        shutil.copyfileobj(response, handle)


def resolve_base_url(artifact: dict, base_map: dict[str, str]) -> str:
    name = artifact["name"]
    if name in base_map:
        return base_map[name].rstrip("/")
    if artifact.get("base_url"):
        return artifact["base_url"].rstrip("/")
    raise SystemExit(f"No base URL for artifact: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Restore split oncoanalyser artifacts from GitHub-hosted parts.")
    parser.add_argument("--manifest", required=True, type=Path, help="Manifest JSON")
    parser.add_argument("--base-map", type=Path, help="JSON mapping from artifact name to base URL")
    parser.add_argument("--output", required=True, type=Path, help="Restore destination")
    parser.add_argument("--work", type=Path, default=Path("restore-work"), help="Temporary download directory")
    args = parser.parse_args()

    manifest = load_json(args.manifest)
    base_map = load_json(args.base_map) if args.base_map else {}
    output_root = args.output.resolve()
    work_root = args.work.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    work_root.mkdir(parents=True, exist_ok=True)

    for artifact in manifest["artifacts"]:
        name = artifact["name"]
        base_url = resolve_base_url(artifact, base_map)
        archive_path = work_root / f"{name}.tar.gz"

        with archive_path.open("wb") as archive_handle:
            for part in artifact["parts"]:
                part_name = part["name"]
                part_url = f"{base_url}/{part_name}"
                part_path = work_root / name / part_name
                if not part_path.exists() or sha256_file(part_path) != part["sha256"]:
                    download(part_url, part_path)
                if sha256_file(part_path) != part["sha256"]:
                    raise SystemExit(f"Checksum mismatch for {part_url}")
                with part_path.open("rb") as handle:
                    shutil.copyfileobj(handle, archive_handle)

        if sha256_file(archive_path) != artifact["sha256"]:
            raise SystemExit(f"Checksum mismatch for archive {name}")

        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(output_root)

    print(output_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
