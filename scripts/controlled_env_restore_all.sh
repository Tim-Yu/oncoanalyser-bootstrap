#!/usr/bin/env bash
# Restore full oncoanalyser structure in controlled env.
#
# What this does:
# 1) Download + extract bootstrap and runtime payloads
# 2) Use preloaded singularity/ref caches if provided
# 3) Otherwise fallback to cache restore scripts
# 4) Ensure oncoanalyser.sh + samplesheet.csv are present and tuned for controlled env
# 5) Write env helper for cache variables
#
# Usage:
#   bash controlled_env_restore_all.sh \
#     /path/to/oncoanalyser_bundle \
#     /path/to/singularity_cache \
#     /path/to/ref_cache
#
# Example with your screenshot layout:
#   bash controlled_env_restore_all.sh \
#     /re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases \
#     /re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases/36.1.workflow/36.1.1.Singularity_cache/singularity_cache \
#     /re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases/36.1.workflow/36.1.2.Ref_cache/ref_cache
set -euo pipefail

ROOT_DIR="${1:-/re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases}"
SING_CACHE_SRC="${2:-/re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases/36.1.workflow/36.1.1.Singularity_cache/singularity_cache}"
REF_CACHE_SRC="${3:-/re_gecip/cancer_sarcoma/36.Oncoanalyser_CCS_GMScases/36.1.workflow/36.1.2.Ref_cache/ref_cache}"

# Workflow content lives in this subfolder.
WORKFLOW_DIR="$ROOT_DIR/36.1.workflow"

BOOTSTRAP_BASE="https://github.com/Tim-Yu/oncoanalyser-bootstrap/raw/refs/heads/main/parts/bootstrap"
RUNTIME_BASE="https://github.com/Tim-Yu/oncoanalyser-runtime-parts/raw/refs/heads/main/parts/runtime"

BOOTSTRAP_PARTS=2
RUNTIME_PARTS=2

mkdir -p "$WORKFLOW_DIR"
mkdir -p "$WORKFLOW_DIR/download_parts/bootstrap" "$WORKFLOW_DIR/download_parts/runtime"

echo "[1/5] Downloading bootstrap parts..."
for i in $(seq 1 "$BOOTSTRAP_PARTS"); do
  part="bootstrap.part$(printf '%04d' "$i")"
  dest="$WORKFLOW_DIR/download_parts/bootstrap/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "$BOOTSTRAP_BASE/$part"
  fi
done

echo "[2/5] Downloading runtime parts..."
for i in $(seq 1 "$RUNTIME_PARTS"); do
  part="runtime.part$(printf '%04d' "$i")"
  dest="$WORKFLOW_DIR/download_parts/runtime/$part"
  if [[ ! -s "$dest" ]]; then
    wget -q -c -O "$dest" "$RUNTIME_BASE/$part"
  fi
done

echo "[3/5] Extracting bootstrap + runtime..."
cat "$WORKFLOW_DIR"/download_parts/bootstrap/bootstrap.part* > "$WORKFLOW_DIR/bootstrap.tar.gz"
cat "$WORKFLOW_DIR"/download_parts/runtime/runtime.part* > "$WORKFLOW_DIR/runtime.tar.gz"
tar -xzf "$WORKFLOW_DIR/bootstrap.tar.gz" -C "$WORKFLOW_DIR"
tar -xzf "$WORKFLOW_DIR/runtime.tar.gz" -C "$WORKFLOW_DIR"

echo "[4/5] Wiring singularity_cache + ref_cache..."
if [[ -n "$SING_CACHE_SRC" ]]; then
  if [[ ! -d "$SING_CACHE_SRC" ]]; then
    echo "ERROR: singularity cache path not found: $SING_CACHE_SRC"
    exit 1
  fi
  rm -rf "$WORKFLOW_DIR/singularity_cache"
  ln -s "$SING_CACHE_SRC" "$WORKFLOW_DIR/singularity_cache"
  echo "      Linked singularity_cache -> $SING_CACHE_SRC"
else
  echo "      No singularity cache path provided; restoring from GitHub..."
  bash "$(dirname "$0")/controlled_env_restore_singularity_cache.sh" "$WORKFLOW_DIR"
fi

if [[ -n "$REF_CACHE_SRC" ]]; then
  if [[ ! -d "$REF_CACHE_SRC" ]]; then
    echo "ERROR: ref cache path not found: $REF_CACHE_SRC"
    exit 1
  fi
  rm -rf "$WORKFLOW_DIR/ref_cache"
  ln -s "$REF_CACHE_SRC" "$WORKFLOW_DIR/ref_cache"
  echo "      Linked ref_cache -> $REF_CACHE_SRC"
else
  echo "      No ref cache path provided; restoring from GitHub..."
  bash "$(dirname "$0")/controlled_env_restore_ref_cache.sh" "$WORKFLOW_DIR"
fi

echo "[5/6] Ensuring oncoanalyser.sh + samplesheet.csv in controlled env..."
if [[ ! -f "$WORKFLOW_DIR/oncoanalyser.sh" ]]; then
  echo "ERROR: oncoanalyser.sh not found after runtime extraction at $WORKFLOW_DIR/oncoanalyser.sh"
  exit 1
fi

chmod +x "$WORKFLOW_DIR/oncoanalyser.sh"

if [[ ! -f "$WORKFLOW_DIR/samplesheet.csv" ]]; then
  echo "group_id,subject_id,sample_id,sample_type,sequence_type,filetype,filepath" > "$WORKFLOW_DIR/samplesheet.csv"
  echo "      Created placeholder samplesheet.csv (header only)."
else
  echo "      Found samplesheet.csv; leaving content unchanged."
fi

# Tune defaults for controlled env while preserving user-overrides via environment variables.
sed -i 's|^REF_CACHE_DIR=.*|REF_CACHE_DIR="${REF_CACHE_DIR:-${HMFTOOLS_GENOME_CACHEDIR:-$ROOT_DIR/ref_cache}/GRCh38_hmf}"|' "$WORKFLOW_DIR/oncoanalyser.sh"
sed -i 's|^INPUT_SHEET=.*|INPUT_SHEET="${INPUT_SHEET:-$ROOT_DIR/samplesheet.csv}"|' "$WORKFLOW_DIR/oncoanalyser.sh"
sed -i 's|^--outdir .*|  --outdir "${OUTDIR:-$ROOT_DIR/output}" \\|' "$WORKFLOW_DIR/oncoanalyser.sh"
echo "      Patched oncoanalyser.sh defaults for controlled env."

echo "[6/6] Writing environment helper..."
cat > "$WORKFLOW_DIR/env_controlled.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NXF_SINGULARITY_CACHEDIR="$WORKFLOW_DIR/singularity_cache"
export HMFTOOLS_GENOME_CACHEDIR="$WORKFLOW_DIR/ref_cache"
export NXF_OFFLINE=true
EOF
chmod +x "$WORKFLOW_DIR/env_controlled.sh"

echo ""
echo "Restore complete."
echo "Workflow dir: $WORKFLOW_DIR"
echo "Env helper:   $WORKFLOW_DIR/env_controlled.sh"
echo "Use:  source $WORKFLOW_DIR/env_controlled.sh"
echo "Run:  $WORKFLOW_DIR/oncoanalyser.sh"
