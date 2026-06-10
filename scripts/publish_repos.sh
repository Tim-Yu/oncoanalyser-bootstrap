#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
	publish_repos.sh --build-dir BUILD_DIR --owner OWNER --repo-map REPO_MAP_JSON

Required environment:
	GITHUB_TOKEN or GH_TOKEN

REPO_MAP_JSON format:
{
	"bootstrap": "oncoanalyser-bootstrap",
	"singularity-cache": "oncoanalyser-singularity",
	"ref-cache": "oncoanalyser-reference",
	"ref-cache-extracted": "oncoanalyser-reference-extracted"
}

This script creates repos (if missing) and pushes shard files to:
	parts/<artifact>/<part_name>
EOF
}

BUILD_DIR=""
OWNER=""
REPO_MAP_JSON=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--build-dir)
			BUILD_DIR="$2"
			shift 2
			;;
		--owner)
			OWNER="$2"
			shift 2
			;;
		--repo-map)
			REPO_MAP_JSON="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown arg: $1" >&2
			usage
			exit 1
			;;
	esac
done

if [[ -z "$BUILD_DIR" || -z "$OWNER" || -z "$REPO_MAP_JSON" ]]; then
	usage
	exit 1
fi

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
	echo "Set GITHUB_TOKEN or GH_TOKEN in the terminal environment." >&2
	exit 1
fi

if [[ ! -f "$BUILD_DIR/manifest.json" ]]; then
	echo "Missing manifest: $BUILD_DIR/manifest.json" >&2
	exit 1
fi

if [[ ! -f "$REPO_MAP_JSON" ]]; then
	echo "Missing repo map: $REPO_MAP_JSON" >&2
	exit 1
fi

command -v python3 >/dev/null
command -v git >/dev/null
command -v curl >/dev/null

api_create_repo() {
	local repo_name="$1"
	local payload
	payload=$(cat <<JSON
{"name":"$repo_name","private":true,"auto_init":true}
JSON
)

	local status
	status=$(curl -sS -o /tmp/repo_create_resp.json -w "%{http_code}" \
		-X POST \
		-H "Accept: application/vnd.github+json" \
		-H "Authorization: Bearer $TOKEN" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		https://api.github.com/user/repos \
		-d "$payload")

	if [[ "$status" == "201" || "$status" == "422" ]]; then
		return 0
	fi

	echo "Failed to create repo $repo_name (HTTP $status)" >&2
	cat /tmp/repo_create_resp.json >&2 || true
	return 1
}

push_artifact_parts() {
	local artifact="$1"
	local repo_name="$2"
	local workdir
	workdir=$(mktemp -d)
	trap 'rm -rf "$workdir"' RETURN

	git clone "https://x-access-token:$TOKEN@github.com/$OWNER/$repo_name.git" "$workdir/repo" >/dev/null 2>&1
	mkdir -p "$workdir/repo/parts/$artifact"

	local src_dir="$BUILD_DIR/parts/$artifact"
	if [[ ! -d "$src_dir" ]]; then
		echo "Skipping $artifact (no parts dir at $src_dir)"
		return 0
	fi

	rsync -a --delete "$src_dir/" "$workdir/repo/parts/$artifact/"

	pushd "$workdir/repo" >/dev/null
	git add "parts/$artifact"
	if git diff --cached --quiet; then
		echo "No changes for $artifact in $repo_name"
		popd >/dev/null
		return 0
	fi

	git commit -m "Update $artifact shard set"
	git push origin HEAD:main
	popd >/dev/null
}

python3 - <<PY
import json
from pathlib import Path

manifest = json.loads(Path("$BUILD_DIR/manifest.json").read_text())
repo_map = json.loads(Path("$REPO_MAP_JSON").read_text())

missing = [a["name"] for a in manifest["artifacts"] if a["name"] not in repo_map]
if missing:
		raise SystemExit(f"Missing repo mapping for artifacts: {missing}")

print("ok")
PY

for repo_name in $(python3 - <<PY
import json
from pathlib import Path
repo_map = json.loads(Path("$REPO_MAP_JSON").read_text())
for _, repo in sorted(repo_map.items()):
		print(repo)
PY
); do
	api_create_repo "$repo_name"
done

while IFS='|' read -r artifact repo_name; do
	push_artifact_parts "$artifact" "$repo_name"
done < <(python3 - <<PY
import json
from pathlib import Path
manifest = json.loads(Path("$BUILD_DIR/manifest.json").read_text())
repo_map = json.loads(Path("$REPO_MAP_JSON").read_text())
for a in manifest["artifacts"]:
		print(f"{a['name']}|{repo_map[a['name']]}")
PY
)

echo "Publish complete."
