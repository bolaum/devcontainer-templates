#!/usr/bin/env bash
# Runs on the HOST (initializeCommand) before the container is created.
#
# Its only job is to guarantee that every bind-mount source declared in
# devcontainer.json exists: Docker creates a root-owned *directory* for a
# missing source, which then shadows the file the container expects.
set -euo pipefail

# Claude auth token reused from the host.
mkdir -p "$HOME/.claude"
touch "$HOME/.claude/.credentials.json"

# SSH agent socket, forwarded so the container can sign with your key without
# ever holding it. The agent picks a random socket name per session (and the path
# differs per desktop), so point a fixed path at whatever is live right now —
# that fixed path is what devcontainer.json mounts.
agent_link="$HOME/.ssh/devcontainer-agent.sock"
mkdir -p "$HOME/.ssh"
rm -f "$agent_link"
if [ -S "${SSH_AUTH_SOCK:-}" ]; then
    ln -s "$SSH_AUTH_SOCK" "$agent_link"
else
    # No agent running (or a headless host): a placeholder keeps the mount valid
    # and the container simply ends up without agent forwarding.
    touch "$agent_link"
fi

# Desktop sockets (Linux): PipeWire/PulseAudio for the microphone, Wayland for
# clipboard image paste. On a host without them (no desktop session, CI, macOS)
# a placeholder file keeps the mount valid and the container simply ends up
# without audio/clipboard instead of failing to start.
runtime_dir="${XDG_RUNTIME_DIR:-}"
if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ]; then
    mkdir -p "$runtime_dir/pulse"
    [ -e "$runtime_dir/pulse/native" ] || touch "$runtime_dir/pulse/native"
    # Keep this display name in sync with the mount in devcontainer.json.
    [ -e "$runtime_dir/wayland-0" ] || touch "$runtime_dir/wayland-0"
fi
