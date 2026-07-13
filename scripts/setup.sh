#!/usr/bin/env bash
# One-time setup: point git at the versioned hooks in .githooks/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

git config core.hooksPath .githooks
echo "✅ git hooks enabled (core.hooksPath=.githooks)"
