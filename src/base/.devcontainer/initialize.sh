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

# gh config reused from the host (may legitimately be empty when you authenticate
# with GH_TOKEN/GITHUB_TOKEN instead of `gh auth login`).
mkdir -p "$HOME/.config/gh"

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
