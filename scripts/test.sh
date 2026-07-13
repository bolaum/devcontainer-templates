#!/usr/bin/env bash
# Smoke test a template end to end: apply the option defaults, bring the dev
# container up, run the template's test.sh inside it, then clean up.
# Works locally and in CI.
#
# Usage: scripts/test.sh [<template-id> | all] [--no-cache]   (default: all)
#
#   --no-cache   force a clean rebuild (also honored via NO_CACHE=1); passes
#                --build-no-cache --remove-existing-container to `devcontainer up`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v devcontainer >/dev/null 2>&1; then
    echo "error: '@devcontainers/cli' not found. Install it (see README):" >&2
    echo "       npm install -g @devcontainers/cli" >&2
    exit 1
fi

smoke_one() {
    local id="$1"
    local src_dir="/tmp/devcontainer-test-${id}"
    local id_label="devcontainer-test=${id}"

    echo "==> [${id}] preparing"
    rm -rf "$src_dir"
    cp -R "src/${id}" "$src_dir"

    # Substitute ${templateOption:x} with each option's default (mimics `apply`).
    if [ "$(jq -r '.options // empty' "$src_dir/devcontainer-template.json")" != "" ]; then
        while IFS= read -r opt; do
            local val esc
            val="$(jq -r ".options.${opt}.default" "$src_dir/devcontainer-template.json")"
            esc="$(printf '%s' "$val" | sed -e 's/[]\/$*.^[]/\\&/g')"
            find "$src_dir" -type f -print0 \
                | xargs -0 sed -i "s/\${templateOption:${opt}}/${esc}/g"
        done < <(jq -r '.options | keys[]' "$src_dir/devcontainer-template.json")
    fi

    # Stage the test project (test.sh + shared helpers) inside the workspace.
    if [ -d "test/${id}" ]; then
        mkdir -p "$src_dir/test-project"
        cp -Rp "test/${id}/." "$src_dir/test-project/"
        cp -Rp test/test-utils/. "$src_dir/test-project/"
    fi

    local up_args=(--id-label "$id_label" --workspace-folder "$src_dir")
    if [ "${NO_CACHE:-0}" = "1" ]; then
        up_args+=(--build-no-cache --remove-existing-container)
        echo "==> [${id}] devcontainer up (no-cache rebuild)"
    else
        echo "==> [${id}] devcontainer up"
    fi
    DOCKER_BUILDKIT=1 devcontainer up "${up_args[@]}"

    if [ -d "$src_dir/test-project" ]; then
        echo "==> [${id}] running test.sh"
        devcontainer exec --workspace-folder "$src_dir" --id-label "$id_label" \
            /bin/sh -c 'if [ "$(id -u)" = "0" ]; then chmod +x ./test-project/test.sh; else sudo chmod +x ./test-project/test.sh; fi && cd ./test-project && ./test.sh'
    fi

    echo "==> [${id}] cleanup"
    docker rm -f "$(docker container ls -f "label=${id_label}" -q)" 2>/dev/null || true
    rm -rf "$src_dir"
}

NO_CACHE="${NO_CACHE:-0}"
target=""
for arg in "$@"; do
    case "$arg" in
        --no-cache) NO_CACHE=1 ;;
        -*) echo "error: unknown option '$arg'" >&2; exit 2 ;;
        *) target="$arg" ;;
    esac
done
target="${target:-all}"

if [ "$target" = "all" ]; then
    for d in src/*/; do smoke_one "$(basename "$d")"; done
else
    smoke_one "$target"
fi

echo "✅ all smoke tests passed"
