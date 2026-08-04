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
    "$HOME/.config/gh"
    "$HOME/.vscode-server"
    "$HOME/.persist"
    "$HOME/.npm"
    "$HOME/.cache/pip"
    "$HOME/.cache/pypoetry"
    "$HOME/.cache/ms-playwright"
    "$HOME/.pyenv/versions"
)

fixed=0
for dir in "${PERSISTED_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    # -O is true when the current user owns it: the common case, no sudo needed.
    [ -O "$dir" ] && continue
    sudo chown -R "$(id -u):$(id -g)" "$dir"
    fixed=$((fixed + 1))
done

if [ "$fixed" -gt 0 ]; then
    echo "✅ Persisted volumes: ownership fixed on $fixed director$([ "$fixed" -eq 1 ] && echo y || echo ies)."
else
    echo "✅ Persisted volumes ready (state survives a rebuild)."
fi
