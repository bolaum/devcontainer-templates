#!/usr/bin/env bash
# Bump the semver `version` in a template's devcontainer-template.json.
#
# Usage:
#   scripts/bump-version.sh <template-id | all> <major | minor | patch | X.Y.Z>
#
# Examples:
#   scripts/bump-version.sh base patch      # 1.0.0 -> 1.0.1
#   scripts/bump-version.sh base minor      # 1.0.1 -> 1.1.0
#   scripts/bump-version.sh base 2.0.0      # set exactly
#   scripts/bump-version.sh all patch       # bump every template under src/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
    echo "usage: scripts/bump-version.sh <template-id | all> <major|minor|patch|X.Y.Z>" >&2
    exit 2
}

[ $# -eq 2 ] || usage
target="$1"
bump="$2"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ ! "$bump" =~ ^(major|minor|patch)$ ]] && [[ ! "$bump" =~ $semver_re ]]; then
    echo "error: invalid bump '$bump' (expected major|minor|patch or X.Y.Z)" >&2
    usage
fi

compute_new() {
    local cur="$1"
    if [[ "$bump" =~ $semver_re ]]; then
        echo "$bump"; return
    fi
    local ma mi pa
    IFS=. read -r ma mi pa <<<"$cur"
    case "$bump" in
        major) echo "$((ma + 1)).0.0" ;;
        minor) echo "${ma}.$((mi + 1)).0" ;;
        patch) echo "${ma}.${mi}.$((pa + 1))" ;;
    esac
}

bump_one() {
    local id="$1"
    local f="src/${id}/devcontainer-template.json"
    [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }

    local cur new
    cur="$(jq -r '.version' "$f")"
    if [[ ! "$cur" =~ $semver_re ]]; then
        echo "error: current version '$cur' in $f is not semver" >&2
        exit 1
    fi
    new="$(compute_new "$cur")"

    # Targeted replace to keep the diff minimal (top-level version only).
    sed -i "s/\"version\": \"${cur}\"/\"version\": \"${new}\"/" "$f"
    echo "  ${id}: ${cur} -> ${new}"
}

echo "Bumping version(s):"
if [ "$target" = "all" ]; then
    for d in src/*/; do bump_one "$(basename "$d")"; done
else
    bump_one "$target"
fi

cat <<'EOF'

Next steps:
  git commit -am "chore: bump template version"   # pre-commit hook regenerates the docs
  # then publish a GitHub Release (with a tag) to run test + release,
  # or trigger the workflows manually from the Actions tab.
EOF
