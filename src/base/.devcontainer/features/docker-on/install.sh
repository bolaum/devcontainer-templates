#!/usr/bin/env bash
# The work is done by the dependency declared in devcontainer-feature.json: the
# official docker-in-docker feature, which this exists only to pull in.
#
# `moby: false` is set there and is required on Ubuntu 26.04 — the Moby packages
# are not built for 'resolute' and the feature refuses to install rather than
# fall back. With false it installs Docker CE from download.docker.com, which is
# the package set Docker's own Ubuntu instructions use.
echo "docker-on: Docker daemon enabled via the docker-in-docker feature."
