#!/usr/bin/env bash
# Regenerate the per-template README.md files from each devcontainer-template.json.
# Run by the pre-commit hook; can also be run manually.
#
# Override the target repo with GITHUB_OWNER / GITHUB_REPO env vars.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GITHUB_OWNER="${GITHUB_OWNER:-bolaum}"
GITHUB_REPO="${GITHUB_REPO:-devcontainer-templates}"

if ! command -v devcontainer >/dev/null 2>&1; then
    echo "error: '@devcontainers/cli' not found. Install it (see README):" >&2
    echo "       npm install -g @devcontainers/cli" >&2
    exit 1
fi

devcontainer templates generate-docs -p src \
    --github-owner "$GITHUB_OWNER" --github-repo "$GITHUB_REPO"

echo "✅ per-template docs generated"
