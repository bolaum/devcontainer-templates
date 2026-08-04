#!/usr/bin/env bash
# Wire the container shells to source the project's shell rc
# (.devcontainer/shell/rc.sh): aliases, functions, exports. Edit that file and open
# a new terminal to pick up changes — no rebuild needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC_FILE="$SCRIPT_DIR/shell/rc.sh"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -qF "$RC_FILE" "$rc" && continue
    {
        echo ''
        echo '# dev-container shell rc'
        # Exported here rather than derived inside rc.sh: locating your own path
        # from a sourced file differs between bash and zsh, and rc.sh is sourced
        # by both.
        echo "export _DEVCONTAINER_SHELL_DIR=\"$SCRIPT_DIR/shell\""
        echo "[ -f \"$RC_FILE\" ] && . \"$RC_FILE\""
    } >> "$rc"
done

echo "✅ shell rc wired: ~/.bashrc and ~/.zshrc source $RC_FILE"
