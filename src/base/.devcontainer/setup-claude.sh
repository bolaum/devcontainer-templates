#!/usr/bin/env bash
# Seed the container's ~/.claude with the desired settings and statusline.
#
# The auth token (~/.claude/.credentials.json) is intentionally left untouched:
# it is a bind-mount from the host (see "mounts" in devcontainer.json), so the
# container reuses the existing login without re-authenticating. History, MCP
# and other state stay isolated per container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json"
cp "$SCRIPT_DIR/claude/statusline.py" "$CLAUDE_DIR/statusline.py"
chmod +x "$CLAUDE_DIR/statusline.py" || true

# Mark onboarding as complete so Claude Code does not launch the login/onboarding
# flow — the actual token comes from the bind-mounted ~/.claude/.credentials.json.
# Only create it if absent, so a host-mounted ~/.claude.json (if you add one) wins.
if [ ! -f "$HOME/.claude.json" ]; then
    echo '{ "hasCompletedOnboarding": true }' > "$HOME/.claude.json"
fi

echo "✅ Claude configured: $CLAUDE_DIR (settings.json + statusline.py) + ~/.claude.json. Auth via host bind-mount."
