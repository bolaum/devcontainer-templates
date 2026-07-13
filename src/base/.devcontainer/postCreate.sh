#!/usr/bin/env bash
# postCreate orchestrator: runs the container's setup steps in order.
# Add new setup steps here rather than chaining them in devcontainer.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/setup-claude.sh"
bash "$SCRIPT_DIR/setup-shell.sh"
