#!/usr/bin/env bash
# Make the persisted named volumes (see "mounts" in devcontainer.json) usable by
# the current user.
#
# A fresh volume inherits the ownership of the image directory it covers, i.e.
# uid 1000 — but `updateRemoteUserUID` remaps the vscode user to the *host* UID,
# which is not always 1000. When it is not, every persisted directory lands
# owned by a stranger and the container silently loses its state (Claude cannot
# write transcripts, npm cannot write its cache, ...).
#
# This runs first in postCreate, before anything writes to those directories.
set -euo pipefail

# Kept in sync with the volume mounts in devcontainer.json.
PERSISTED_DIRS=(
    "$HOME/.claude"
    "$HOME/.codex"
    "$HOME/.ssh"
    "$HOME/.config/gh"
    "$HOME/.vscode-server"
    "$HOME/.persist"
    "$HOME/.npm"
    "$HOME/.cache/pip"
    "$HOME/.cache/pypoetry"
    "$HOME/.cache/ms-playwright"
    "$HOME/.pyenv/versions"
)

# Not a volume, and not persisted — but it has the same problem for the same
# reason. The Dockerfile creates XDG_RUNTIME_DIR as uid 1000 at build time, and
# the UID remap happens afterwards, so on a host whose user is not 1000 it ends
# up owned by a stranger. libwayland then refuses it and a headed Chromium dies
# with "Failed to connect to Wayland display". Nothing here may assume 1000:
# `id -u` is the only honest source.
PERSISTED_DIRS+=("${XDG_RUNTIME_DIR:-}")

fixed=0
for dir in "${PERSISTED_DIRS[@]}"; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || continue
    # -O is true when the current user owns it: the common case, no sudo needed.
    [ -O "$dir" ] && continue
    sudo chown -R "$(id -u):$(id -g)" "$dir"
    fixed=$((fixed + 1))
done

# ssh refuses to use a key whose directory is group- or world-readable, and the
# mode of a fresh volume is whatever Docker gave it rather than the image's.
[ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"

if [ "$fixed" -gt 0 ]; then
    echo "✅ Persisted volumes: ownership fixed on $fixed director$([ "$fixed" -eq 1 ] && echo y || echo ies)."
else
    echo "✅ Persisted volumes ready (state survives a rebuild)."
fi
