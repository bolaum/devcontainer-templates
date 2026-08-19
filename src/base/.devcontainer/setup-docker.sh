#!/usr/bin/env bash
# Prove the nested Docker daemon works, HERE, at create time.
#
# Does nothing unless the docker-in-docker feature is enabled in
# devcontainer.json (it is commented out by default) — with no docker CLI there
# is nothing to check and this is not an error.
#
# When it IS enabled: the daemon is started by the feature's entrypoint
# (/usr/local/share/docker-init.sh) in the background, so it is usually up before
# postCreate reaches this step and the check costs nothing. When it is not up,
# the failure is worth catching now — without this the first symptom is
# `docker compose up` failing much later, and the error it prints ("cannot
# connect to the Docker daemon") looks like a project problem rather than a
# container one.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
    echo "⏭️  Docker skipped (the docker-in-docker feature is not enabled)"
    exit 0
fi

# The daemon needs a moment on a cold container. 30s is far more than it takes in
# practice and still bounded, so a broken daemon fails the create instead of
# hanging it.
deadline=$((SECONDS + 30))
until docker info >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "❌ the nested Docker daemon did not come up within 30s"
        echo "   last error:"
        docker info 2>&1 | sed 's/^/   /' | head -20
        echo "   logs: /tmp/dockerd.log and /tmp/containerd.log"
        exit 1
    fi
    sleep 1
done

# Both plugins are what a project's compose.yaml will rely on, so a missing one
# is better found here than in the middle of the first build. Checked before
# being printed: under `set -e` a failing plugin inside a command substitution
# would kill the script with its own error instead of this message.
for plugin in compose buildx; do
    docker "$plugin" version >/dev/null 2>&1 || {
        echo "❌ the docker $plugin plugin is missing"
        exit 1
    }
done

printf '   %s\n' \
    "$(docker --version)" \
    "$(docker compose version)" \
    "$(docker buildx version | head -1)"

# The feature's entrypoint mounts a tmpfs over /tmp when /tmp is not already a
# mount point, which is exactly what would hide the host sockets and the runtime
# dir if they lived there (they are in /run; devcontainer.json explains why).
# Checked here because the failure is silent by nature: nothing errors, the
# sockets simply stop being visible, and the symptom shows up much later as a
# mute microphone, a browser that cannot reach the compositor, or a `git push`
# with no agent.
missing=""
for path in "${XDG_RUNTIME_DIR:-/run/xdg-runtime}" /run/host-pulse /run/host-wayland /run/host-ssh-agent; do
    [ -e "$path" ] || missing="$missing $path"
done
if [ -n "$missing" ]; then
    echo "⚠️  host bridges not visible:$missing"
    echo "   if any of them is under /tmp, the docker-in-docker entrypoint shadowed it"
fi

echo "✅ Docker ready: nested daemon up, compose and buildx present"
