#!/usr/bin/env bash
set -euo pipefail

# Restore singularity-cache from raw GitHub shard files.
# Usage:
#   bash controlled_env_restore_singularity_cache.sh /path/to/oncoanalyser_bundle

ROOT_DIR="${1:-/path/to/oncoanalyser_bundle}"
PARTS_DIR="$ROOT_DIR/download_parts/singularity-cache"
ARCHIVE_PATH="$ROOT_DIR/singularity-cache.tar.gz"
BASE_URL="https://raw.githubusercontent.com/Tim-Yu/oncoanalyser-singularity-cache-parts/main/parts/singularity-cache"

mkdir -p "$PARTS_DIR"

# Current published shard count for singularity-cache.
START=1
END=511

for i in $(seq "$START" "$END"); do
  part="singularity-cache.part$(printf '%04d' "$i")"
  wget -q -c -O "$PARTS_DIR/$part" "$BASE_URL/$part"
done

cat "$PARTS_DIR"/singularity-cache.part* > "$ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$ROOT_DIR"

echo "Restore complete: $ROOT_DIR/singularity_cache"
echo "Set NXF_SINGULARITY_CACHEDIR to: $ROOT_DIR/singularity_cache"
