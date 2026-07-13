#!/bin/bash
cd "$(dirname "$0")"

set -e

# Import the shared test helpers (check / reportResults)
source test-utils.sh

# Tools (bash -lic loads the rc files so pyenv/nvm/poetry are on PATH)
check "python3" bash -lic "python3 --version"
check "poetry" bash -lic "poetry --version"
check "pyenv" bash -lic "pyenv --version"
check "node (via nvm)" bash -lic "node --version"
check "claude-code" bash -lic "claude --version"

# Claude wiring
check "settings.json present" test -f "$HOME/.claude/settings.json"
check "statusline.py present" test -f "$HOME/.claude/statusline.py"
check "settings has bypassPermissions" bash -lic "grep -q bypassPermissions \$HOME/.claude/settings.json"

# Report results
reportResults
