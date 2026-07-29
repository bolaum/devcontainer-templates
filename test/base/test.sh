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
# The native installer writes ~/.claude.json at build time, so setup-claude.sh
# must merge into it: onboarding skipped AND the install metadata preserved.
check "onboarding marked complete" python3 -c "import json,os,sys; sys.exit(0 if json.load(open(os.path.expanduser('~/.claude.json'))).get('hasCompletedOnboarding') is True else 1)"
check "install metadata preserved" python3 -c "import json,os,sys; sys.exit(0 if json.load(open(os.path.expanduser('~/.claude.json'))).get('installMethod') == 'native' else 1)"

# Desktop bridges: tools Claude Code shells out to for /voice and image paste.
# Only their presence is asserted — whether the host sockets are live depends on
# the machine running the test (a CI runner has no desktop session).
check "sox rec (voice)" bash -lic "command -v rec"
check "sox pulse backend" bash -c "sox --help 2>&1 | grep -qw pulseaudio"
check "arecord (voice fallback)" bash -lic "command -v arecord"
check "alsa routed to pulse" bash -c "grep -q pulse /etc/asound.conf"
check "PULSE_SERVER set" bash -c '[ -n "$PULSE_SERVER" ]'
check "wl-paste (clipboard)" bash -lic "command -v wl-paste"
check "xclip (clipboard fallback)" bash -lic "command -v xclip"
check "WAYLAND_DISPLAY set" bash -c '[ -n "$WAYLAND_DISPLAY" ]'

# apt is usable without running `apt update` first
check "apt lists populated" bash -c "sudo apt-get install -s -qq htop"

# Command-line toolbox
check "jq" bash -lic "jq --version"
check "ripgrep" bash -lic "rg --version"
check "fd" bash -lic "fd --version"
check "tree" bash -lic "tree --version"
check "sqlite3" bash -lic "sqlite3 --version"
check "psql" bash -lic "psql --version"
check "shellcheck" bash -lic "shellcheck --version"
check "shfmt" bash -lic "shfmt --version"
check "ffmpeg" bash -lic "ffmpeg -version"
check "imagemagick" bash -lic "convert --version"
check "gh" bash -lic "gh --version"

# Playwright (installPlaywright defaults to true)
check "playwright cli" bash -lic "playwright --version"
check "chromium installed" bash -lic '[ -n "$(find "$HOME/.cache/ms-playwright" -maxdepth 1 -name "chromium*" -print -quit)" ]'
check "playwright MCP registered" bash -lic "grep -q playwright-mcp \$HOME/.claude.json"
# Chrome's sandbox needs privileges the container lacks: without --no-sandbox the
# browser aborts, so the MCP server would be registered but useless.
check "MCP config generated" test -f "$HOME/.claude/playwright-mcp.json"
check "MCP disables chrome sandbox" bash -c "grep -q -- '--no-sandbox' \$HOME/.claude/playwright-mcp.json"
# Headed by default, rendering on the host compositor through the Wayland socket.
check "browser is headed" bash -c "grep -q '\"headless\": false' \$HOME/.claude/playwright-mcp.json"
check "wayland platform flag" bash -c "grep -q -- '--ozone-platform=wayland' \$HOME/.claude/playwright-mcp.json"
check "XDG_RUNTIME_DIR writable" bash -c '[ -w "$XDG_RUNTIME_DIR" ]'
check "chromium actually runs" bash -lic 'CHROME=$(find "$HOME/.cache/ms-playwright" -type f -name chrome | head -1); "$CHROME" --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null'

# Shell customization
check "shell rc wired" bash -c 'grep -q shell/rc.sh "$HOME/.bashrc"'
check "alias from rc.sh" bash -lic "alias ll"

# Report results
reportResults
