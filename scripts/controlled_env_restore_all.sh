#!/usr/bin/env bash
# Restore full oncoanalyser structure in controlled env.
#
# What this does:
# 1) Download + extract bootstrap and runtime payloads
# 2) Use preloaded singularity/ref caches if provided
# 3) Otherwise fallback to cache restore scripts
# 4) Write env helper for cache variables
#
# Usage:
#   bash controlled_env_restore_all.sh \
#     /path/to/oncoanalyser_bundle \
#     /path/to/singularity_cache \
#     /path/to/ref_cache
#
# Example with your screenshot layout:
#   bash controlled_env_restore_all.sh \
#     /re_gecip/cancer_sarcoma/36.oncoanalyser_CCS_GMScases \
#     /re_gecip/cancer_sarcoma/36.oncoanalyser_CCS_GMScases/36.1.1.Singularity_cache/singularity_cache \
#     /re_gecip/cancer_sarcoma/36.oncoanalyser_CCS_GMScases/36.1.2.Ref_cache/ref_cache
set -euo pipefail

ROOT_DIR="${1:-/path/to/oncoanalyser_bundle}"
SING_CACHE_SRC="${2:-}"
REF_CACHE_SRC="${3:-}"

BOOTSTRAP_BASE="https://github.com/Tim-Yu/oncoanalyser-bootstrap/raw/refs/heads/main/parts/bootstrap"
RUNTIME_BASE="https://github.com/Tim-Yu/oncoanalyser-runtime-parts/raw/refs/heads/main/parts/runtime"

BOOTSTRAP_PARTS=2
RUNTIME_PARTS=2

mkdir -p "$ROOT_DIR"
mkdir -p "$ROOT_DIR/download_parts/bootstrap" "$ROOT_DIR/download_parts/runtime"

echo "[1/5] Downloading bootstrap parts..."
for i in $(seq 1 "$BOOTSTRAP_PARTS"); do
  part="bootstrap.part$(printf '%04d' "$i")"
  dest="$ROOT_DIR/download_parts/bootstrap/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "$BOOTSTRAP_BASE/$part"
  fi
done

echo "[2/5] Downloading runtime parts..."
for i in $(seq 1 "$RUNTIME_PARTS"); do
  part="runtime.part$(printf '%04d' "$i")"
  dest="$ROOT_DIR/download_parts/runtime/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "$RUNTIME_BASE/$part"
  fi
done

echo "[3/5] Extracting bootstrap + runtime..."
cat "$ROOT_DIR"/download_parts/bootstrap/bootstrap.part* > "$ROOT_DIR/bootstrap.tar.gz"
cat "$ROOT_DIR"/download_parts/runtime/runtime.part* > "$ROOT_DIR/runtime.tar.gz"
tar -xzf "$ROOT_DIR/bootstrap.tar.gz" -C "$ROOT_DIR"
tar -xzf "$ROOT_DIR/runtime.tar.gz" -C "$ROOT_DIR"

echo "[4/5] Wiring singularity_cache + ref_cache..."
if [[ -n "$SING_CACHE_SRC" ]]; then
  if [[ ! -d "$SING_CACHE_SRC" ]]; then
    echo "ERROR: singularity cache path not found: $SING_CACHE_SRC"
    exit 1
  fi
  rm -rf "$ROOT_DIR/singularity_cache"
  ln -s "$SING_CACHE_SRC" "$ROOT_DIR/singularity_cache"
  echo "      Linked singularity_cache -> $SING_CACHE_SRC"
else
  echo "      No singularity cache path provided; restoring from GitHub..."
  bash "$(dirname "$0")/controlled_env_restore_singularity_cache.sh" "$ROOT_DIR"
fi

if [[ -n "$REF_CACHE_SRC" ]]; then
  if [[ ! -d "$REF_CACHE_SRC" ]]; then
    echo "ERROR: ref cache path not found: $REF_CACHE_SRC"
    exit 1
  fi
  rm -rf "$ROOT_DIR/ref_cache"
  ln -s "$REF_CACHE_SRC" "$ROOT_DIR/ref_cache"
  echo "      Linked ref_cache -> $REF_CACHE_SRC"
else
  echo "      No ref cache path provided; restoring from GitHub..."
  bash "$(dirname "$0")/controlled_env_restore_ref_cache.sh" "$ROOT_DIR"
fi

echo "[5/5] Writing environment helper..."
cat > "$ROOT_DIR/env_controlled.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NXF_SINGULARITY_CACHEDIR="$ROOT_DIR/singularity_cache"
export HMFTOOLS_GENOME_CACHEDIR="$ROOT_DIR/ref_cache"
export NXF_OFFLINE=true
EOF
chmod +x "$ROOT_DIR/env_controlled.sh"

echo ""
echo "Restore complete."
echo "Root: $ROOT_DIR"
echo "Env helper: $ROOT_DIR/env_controlled.sh"
echo "Use: source $ROOT_DIR/env_controlled.sh"
