#!/usr/bin/env bash
# Install the OpenAI Codex CLI alongside Claude Code (option installCodex).
#
# Only the CLI. The login is deliberately NOT automated: it is an interactive
# browser round trip against a personal account, and which account a container
# gets to spend is a person's decision, not a setup step's.
#
# What a rebuild has to KEEP is the volume mounted at ~/.codex (see "mounts" in
# devcontainer.json), where the login writes auth.json. What it merely has to
# redo is this npm install — global packages live in the nvm tree, which is
# container filesystem and not persisted, the same reason setup-playwright.sh
# reinstalls its own every time.
set -euo pipefail

if [ "${INSTALL_CODEX:-false}" != "true" ]; then
    echo "⏭️  Codex CLI skipped (installCodex=false)"
    exit 0
fi

if command -v codex >/dev/null 2>&1; then
    echo "✅ Codex CLI already present ($(codex --version 2>/dev/null | head -1 || true))."
else
    echo "⏳ Installing the Codex CLI (npm)..."
    npm install -g @openai/codex
    echo "✅ Codex CLI installed."
fi

# Report where the login stands. Worth the two lines: with no credentials the
# first `codex` run drops into an auth flow with no explanation of why the
# previous container did not need one.
if [ -s "$HOME/.codex/auth.json" ]; then
    echo "✅ Codex credentials present (~/.codex/auth.json)."
else
    echo "⚠️  No Codex credentials yet — run 'codex login' once."
    echo "   The token lands in the persisted ~/.codex volume and survives rebuilds."
fi
