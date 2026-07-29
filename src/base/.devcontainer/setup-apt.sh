#!/usr/bin/env bash
# Refresh the apt package lists so `sudo apt install <pkg>` works right away.
#
# The Dockerfile and every devcontainer feature delete /var/lib/apt/lists to
# keep the image small, so a fresh container starts with no package index and
# the first install fails with "Unable to locate package". Doing it here (and
# not in the Dockerfile) also means the index is fresh at container creation
# instead of frozen at image build time.
set -euo pipefail

sudo apt-get update -qq

echo "✅ apt package lists refreshed (sudo apt install <pkg> works without apt update)"
