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
# Drives both Claude's answers and /voice dictation; unset means English.
check "dictation language set" bash -c "grep -q '\"language\": \"portuguese\"' \$HOME/.claude/settings.json"
# Voice dictation on from the first session (hold space), instead of /voice each time.
check "voice dictation enabled" python3 -c "import json,os,sys; v=json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('voice',{}); sys.exit(0 if v.get('enabled') is True and v.get('mode')=='hold' else 1)"
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
# Under /run, not /tmp — see the mounts in devcontainer.json. A bridge in /tmp is
# one tmpfs away from being silently invisible (the docker-in-docker entrypoint
# mounts exactly that, on every container start).
check "host bridges under /run" bash -c '
    for p in "$PULSE_SERVER" "$WAYLAND_DISPLAY" "$SSH_AUTH_SOCK" "$XDG_RUNTIME_DIR"; do
        case "${p#unix:}" in /run/*) ;; *) echo "not under /run: $p"; exit 1 ;; esac
    done'
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
check "ffmpeg" bash -lic "ffmpeg -version"
check "imagemagick" bash -lic "magick --version"
# Installed by the "extra tools" layer, the last one in the Dockerfile.
check "sqlite3" bash -lic "sqlite3 --version"
check "psql" bash -lic "psql --version"
check "shellcheck" bash -lic "shellcheck --version"
check "shfmt" bash -lic "shfmt --version"
check "just" bash -lic "just --version"
check "fzf" bash -lic "fzf --version"
# fzf takes over Ctrl+R for fuzzy history search — wired in shell/rc.sh, which
# has to cope with the integration script having moved between fzf releases.
# -X lists bindings to shell commands (what fzf 0.44 uses), -p the macro ones.
check "fzf bound to Ctrl+R" bash -lic 'bind -X 2>/dev/null | grep -q fzf || bind -p 2>/dev/null | grep -q fzf'
# Generated from the `just` binary at shell start, so it can never lag the justfile.
check "just completions loaded" bash -lic 'complete -p just'
check "gh" bash -lic "command gh --version"
# Set even with the docker feature off: the variable and the directory are what
# stop VS Code's host credential helper from landing in ~/.docker later, where it
# breaks every `docker pull`, anonymous ones included.
check "DOCKER_CONFIG kept off ~/.docker" bash -c '[ "$DOCKER_CONFIG" = "$HOME/.docker-cli" ] && [ -w "$DOCKER_CONFIG" ]'

# GitHub auth: the container holds no host credential. The key signs on the host
# through the forwarded agent, and `gh` gets a per-repo token via `gh-login`.
check "ssh agent forwarded" bash -c '[ "$SSH_AUTH_SOCK" = "/run/host-ssh-agent" ] && [ -e "$SSH_AUTH_SOCK" ]'
# A host token would reach every repo the user can — nothing should inherit one.
check "no host GitHub token" bash -lic '[ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]'
check "gh-login available" bash -lic "type gh-login"
check "gh nudges when logged out" bash -lic "gh auth status 2>&1 | grep -q 'gh-login'"

# Playwright (installPlaywright defaults to true)
check "playwright cli" bash -lic "playwright --version"
check "chromium installed" bash -lic '[ -n "$(find "$HOME/.cache/ms-playwright" -maxdepth 1 -name "chromium*" -print -quit)" ]'
check "playwright MCP registered" bash -lic "grep -q playwright-mcp \$HOME/.claude.json"
# Chrome's sandbox needs privileges the container lacks: without --no-sandbox the
# browser aborts, so the MCP server would be registered but useless.
check "MCP config generated" test -f "$HOME/.claude/playwright-mcp.json"
# With no outputDir the server resolves screenshots against its working
# directory, i.e. wherever Claude was started — in practice the project root.
check "MCP output kept out of the repo root" bash -c 'grep -q outputDir "$HOME/.claude/playwright-mcp.json"'
check "MCP disables chrome sandbox" bash -c "grep -q -- '--no-sandbox' \$HOME/.claude/playwright-mcp.json"
# Headed by default, rendering on the host compositor through the Wayland socket.
check "browser is headed" bash -c "grep -q '\"headless\": false' \$HOME/.claude/playwright-mcp.json"
check "wayland platform flag" bash -c "grep -q -- '--ozone-platform=wayland' \$HOME/.claude/playwright-mcp.json"
check "XDG_RUNTIME_DIR writable" bash -c '[ -w "$XDG_RUNTIME_DIR" ]'
check "chromium actually runs" bash -lic 'CHROME=$(find "$HOME/.cache/ms-playwright" -type f -name chrome | head -1); "$CHROME" --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null'
# @playwright/mcp pins an alpha Playwright whose Chromium revision differs from
# the stable release: installing the wrong one still passes every check above and
# only blows up on Claude's first navigation.
check "MCP browser revision present" bash -lic 'node -e "const {createRequire}=require(\"module\"); const fs=require(\"fs\"); const req=createRequire(process.argv[1]+\"/@playwright/mcp/\"); const p=req(\"playwright-core\").chromium.executablePath(); if(!fs.existsSync(p)){console.error(p);process.exit(1)}" "$(npm root -g)"'

# Shell customization
check "shell rc wired" bash -c 'grep -q shell/rc.sh "$HOME/.bashrc"'
check "alias from rc.sh" bash -lic "alias ll"

# Persistence across rebuilds. Each of these is a named volume scoped to the
# project via ${devcontainerId}, so the state behind it outlives the container.
# A plain directory here means the mount silently did not happen and everything
# in it is lost on the next rebuild.
check "claude state persisted" mountpoint -q "$HOME/.claude"
check "vscode-server persisted" mountpoint -q "$HOME/.vscode-server"
check "shell history persisted" mountpoint -q "$HOME/.persist"
check "npm cache persisted" mountpoint -q "$HOME/.npm"
check "pip cache persisted" mountpoint -q "$HOME/.cache/pip"
check "poetry cache persisted" mountpoint -q "$HOME/.cache/pypoetry"
check "pyenv versions persisted" mountpoint -q "$HOME/.pyenv/versions"
check "gh config persisted" mountpoint -q "$HOME/.config/gh"
check "codex login persisted" mountpoint -q "$HOME/.codex"
check "playwright browsers persisted" mountpoint -q "$HOME/.cache/ms-playwright"
# A fresh volume takes the image directory's ownership (uid 1000), which is the
# wrong user whenever updateRemoteUserUID remaps vscode to a host UID != 1000.
check "persisted dirs writable" bash -c '
    for d in "$HOME/.claude" "$HOME/.codex" "$HOME/.config/gh" "$HOME/.vscode-server" "$HOME/.persist" \
             "$HOME/.npm" "$HOME/.cache/pip" "$HOME/.cache/pypoetry" \
             "$HOME/.cache/ms-playwright" "$HOME/.pyenv/versions"; do
        [ -w "$d" ] || { echo "not writable: $d"; exit 1; }
    done'
# Bash keeps history in $HOME by default, which is rebuilt every time.
check "HISTFILE in persisted volume" bash -lic '[ "$HISTFILE" = "$HOME/.persist/bash_history" ]'
# Pointing HISTFILE at the volume is not enough: a shell only writes its history
# when it exits, and a rebuild kills it first. Run a command in a real
# interactive shell (script provides the pty) and look for it in the file while
# that shell is STILL RUNNING — which only holds if each command is flushed as
# it is entered.
check "history flushed on every command" bash -c '
    marker="hist-marker-$$"
    printf "echo %s\nsleep 6\n" "$marker" | script -qc "bash -i" /dev/null >/dev/null 2>&1 &
    sleep 3
    grep -q "$marker" "$HOME/.persist/bash_history"'
# The end-to-end checker ships with the template (cwd here is <workspace>/test-project).
check "persistence checker present" bash -c 'test -x "$(dirname "$PWD")/.devcontainer/check-persistence.sh"'

# Docker, only when the installDocker option selected the real feature. With the
# default (./features/no-docker) there is no docker CLI and these are skipped —
# run them with:
#   TEMPLATE_OPTIONS='installDocker=ghcr.io/devcontainers/features/docker-in-docker:2' \
#       bash scripts/test.sh base
if command -v docker >/dev/null 2>&1; then
    check "nested docker daemon up" docker info
    check "docker compose plugin" docker compose version
    check "docker buildx plugin" docker buildx version
    # Fails with "error getting credentials - err: exit status 255" if the CLI
    # falls back to ~/.docker and finds VS Code's host credential helper there.
    check "anonymous pull works" docker run --rm hello-world
    # The feature's entrypoint mounts a tmpfs over /tmp on every container start.
    # This is the check that would have caught the sockets being shadowed, back
    # when they lived there.
    check "host bridges survive the dind entrypoint" bash -c '
        for p in "$PULSE_SERVER" "$WAYLAND_DISPLAY" "$SSH_AUTH_SOCK" "$XDG_RUNTIME_DIR"; do
            [ -e "${p#unix:}" ] || { echo "shadowed: $p"; exit 1; }
        done'
else
    echo "⏭️  docker checks skipped (installDocker is off)"
fi

# Report results
reportResults
