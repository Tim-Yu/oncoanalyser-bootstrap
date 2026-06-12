#!/usr/bin/env bash
# Restore ref-cache from raw GitHub shard files.
#
# Parts are split across two repos:
#   Main repo  : parts 0001–0990  (Tim-Yu/oncoanalyser-ref-cache-parts)
#   Tail repo  : parts 0991–1028  (Tim-Yu/oncoanalyser-ref-cache-tail-parts)
#
# Usage:
#   bash controlled_env_restore_ref_cache.sh /path/to/oncoanalyser_bundle
#
# The script is resumable: already-downloaded parts are skipped.
set -euo pipefail

ROOT_DIR="${1:-/path/to/oncoanalyser_bundle}"
PARTS_DIR="$ROOT_DIR/download_parts/ref-cache"
ARCHIVE_PATH="$ROOT_DIR/ref-cache.tar.gz"

MAIN_BASE="https://github.com/Tim-Yu/oncoanalyser-ref-cache-parts/raw/refs/heads/main/parts/ref-cache"
TAIL_BASE="https://github.com/Tim-Yu/oncoanalyser-ref-cache-tail-parts/raw/refs/heads/main/parts/ref-cache"

MAIN_END=990
TAIL_START=991
TAIL_END=1028

mkdir -p "$PARTS_DIR"

echo "[1/3] Downloading ref-cache parts 0001–${MAIN_END} from main repo..."
for i in $(seq 1 "$MAIN_END"); do
  part="ref-cache.part$(printf '%04d' "$i")"
  dest="$PARTS_DIR/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "${MAIN_BASE}/${part}"
  fi
done
echo "      Main parts done."

echo "[2/3] Downloading ref-cache parts ${TAIL_START}–${TAIL_END} from tail repo..."
for i in $(seq "$TAIL_START" "$TAIL_END"); do
  part="ref-cache.part$(printf '%04d' "$i")"
  dest="$PARTS_DIR/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "${TAIL_BASE}/${part}"
  fi
done
echo "      Tail parts done."

echo "[3/3] Reassembling and extracting ref-cache..."
cat "$PARTS_DIR"/ref-cache.part* > "$ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$ROOT_DIR"
echo "      Done."

echo ""
echo "Restore complete: $ROOT_DIR/ref_cache"
echo "Set HMFTOOLS_GENOME_CACHEDIR to: $ROOT_DIR/ref_cache"
