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

# Claude must be installed under $HOME and owned by the current user, otherwise
# it cannot update itself (the npm-global install from the claude-code feature
# was root-owned and failed with EACCES).
check "claude installed in \$HOME" bash -lic '[ "$(command -v claude)" = "$HOME/.local/bin/claude" ]'
check "claude install dir writable" test -w "$HOME/.local/share/claude"

# Claude wiring
check "settings.json present" test -f "$HOME/.claude/settings.json"
check "statusline.py present" test -f "$HOME/.claude/statusline.py"
check "settings has bypassPermissions" bash -lic "grep -q bypassPermissions \$HOME/.claude/settings.json"

# Shell customization
check "shell rc wired" bash -c 'grep -q shell/rc.sh "$HOME/.bashrc"'
check "alias from rc.sh" bash -lic "alias ll"

# Report results
reportResults
