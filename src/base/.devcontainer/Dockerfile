# Pinned to the current Ubuntu LTS rather than exposed as an option: the layers
# below install packages this release has (`just` arrived in 26.04, ImageMagick
# is 7 here), so an older base would fail the build instead of degrading. Bump
# this line when the next LTS lands, and note the tag has NO dash — the
# devcontainers base image publishes `ubuntu26.04`, not `ubuntu-26.04`.
FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04

# Point apt at the fastest mirror reachable from this machine, BEFORE any layer
# below installs anything — on a network where archive.ubuntu.com is slow, that
# single decision is worth minutes on every uncached build. Leaves the default
# in place unless another mirror clearly beats it (see the script).
ARG APT_MIRROR=auto
COPY pick-apt-mirror.sh /tmp/pick-apt-mirror.sh
RUN bash /tmp/pick-apt-mirror.sh "$APT_MIRROR" && rm -f /tmp/pick-apt-mirror.sh

# Let apt's lists and downloaded .deb files live in BuildKit cache mounts (see
# the apt layers below), which is what stops every one of them from re-running a
# full `apt-get update` — the old `rm -rf /var/lib/apt/lists/*` at the end of
# each layer existed only to keep those ~45 MB out of the image, and a cache
# mount keeps them out of the image by construction.
#
# The base image ships hooks that wipe the archives after every install/update;
# with them in place the cache mount would always be empty.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
        > /etc/apt/apt.conf.d/keep-downloaded-packages

# Every package the image always needs, in ONE layer. Kept together on purpose:
# each additional apt layer pays its own `apt-get update` round-trip, and these
# groups change together in practice — they are all "the base environment".
# Project-specific additions go in EXTRA_PACKAGES further down, which is the last
# layer and therefore never invalidates this one.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo '=== apt: base packages (pyenv build deps, desktop bridges, CLI toolbox) ===' \
    && apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        # Build dependencies so pyenv can compile CPython on demand
        # (pyenv install <version>). This is the list the pyenv wiki gives for
        # Ubuntu; `llvm` is deliberately NOT here — CPython builds with gcc, and
        # llvm pulled in 232 MB for nothing.
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        # Desktop bridges for Claude Code: /voice records through SoX's `rec` or
        # ALSA's `arecord`, image paste shells out to `wl-paste` or `xclip`. The
        # container has no /dev/snd and no display, so both talk to the host
        # through the sockets bind-mounted in devcontainer.json.
        # libsox-fmt-pulse is what makes `rec` work without an ALSA card —
        # installing sox alone only pulls the ALSA backend, which has nothing to
        # open here.
        sox \
        libsox-fmt-pulse \
        alsa-utils \
        libasound2-plugins \
        pulseaudio-utils \
        wl-clipboard \
        xclip \
        # Command-line toolbox: what Claude reaches for in shell commands and a
        # bare Ubuntu image does not have. ffmpeg and imagemagick are here rather
        # than in the extras layer below because they are the expensive part
        # (183 and 38 packages) and general-purpose enough to be worth paying for
        # once, up here where the cache almost never invalidates.
        # jq/tree/less/unzip/zip already ship in the base image; listed so the
        # image does not silently lose them.
        jq \
        ripgrep \
        fd-find \
        tree \
        unzip \
        zip \
        less \
        ffmpeg \
        imagemagick \
    # Debian/Ubuntu ship fd as `fdfind` (name clash with another package)
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# Route ALSA through the PulseAudio socket: without this, `arecord` (and SoX's
# ALSA backend) fail with "cannot find card '0'" since there is no /dev/snd.
RUN printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf

# Chromium's system libraries, baked into the image so creating a container does
# not re-install ~200 MB of packages every time. The list is what
# `playwright install-deps --dry-run chromium` asks for on Ubuntu; the
# browser binary itself is installed in postCreate into a shared volume.
ARG INSTALL_PLAYWRIGHT=true
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
        echo '=== apt: Chromium system libraries ===' \
        && apt-get update && export DEBIAN_FRONTEND=noninteractive \
        && apt-get -y install --no-install-recommends \
            at-spi2-common \
            fonts-freefont-ttf \
            fonts-ipafont-gothic \
            fonts-liberation \
            fonts-noto-color-emoji \
            fonts-tlwg-loma-otf \
            fonts-unifont \
            fonts-wqy-zenhei \
            libatk-bridge2.0-0t64 \
            libatk1.0-0t64 \
            libatspi2.0-0t64 \
            libavahi-client3 \
            libavahi-common-data \
            libavahi-common3 \
            libcups2t64 \
            libfontenc1 \
            libxaw7 \
            libxcomposite1 \
            libxdamage1 \
            libxfont2 \
            libxkbfile1 \
            libxmuu1 \
            libxpm4 \
            x11-xkb-utils \
            xauth \
            xfonts-cyrillic \
            xfonts-encodings \
            xfonts-scalable \
            xfonts-utils \
            xserver-common \
            xvfb; \
    fi

# Create every mount point declared in devcontainer.json, owned by the non-root
# user, BEFORE Docker mounts anything on them. Two reasons:
#   - Docker creates a missing mount point (and any missing parent) as root, which
#     would leave e.g. ~/.claude unwritable for the postCreate step;
#   - a fresh named volume inherits the ownership of the image directory it is
#     mounted over, so these must already be vscode-owned for the persisted
#     volumes to be writable on first use.
RUN mkdir -p \
        /home/vscode/.claude \
        /home/vscode/.codex \
        /home/vscode/.config/gh \
        /home/vscode/.vscode-server \
        /home/vscode/.persist \
        /home/vscode/.npm \
        /home/vscode/.cache/pip \
        /home/vscode/.cache/pypoetry \
        /home/vscode/.cache/ms-playwright \
    && chown -R vscode:vscode \
        /home/vscode/.claude \
        /home/vscode/.codex \
        /home/vscode/.config \
        /home/vscode/.vscode-server \
        /home/vscode/.persist \
        /home/vscode/.npm \
        /home/vscode/.cache

# XDG_RUNTIME_DIR for the container (see devcontainer.json): a headed Chromium
# talking to the host's Wayland compositor expects one, and there is no logind
# session in a container to create it. libwayland insists on mode 0700 owned by
# the running user, and this `chown` bakes in whatever uid `vscode` has at BUILD
# time — `updateRemoteUserUID` can change it afterwards, which is why
# setup-persist.sh re-checks the owner at postCreate.
#
# In /run, not /tmp: a plain directory in the image, so it survives whatever a
# feature's entrypoint mounts over /tmp. A `--tmpfs` in runArgs would be the
# other way to get one, but it would have to hardcode uid=1000 — the mount is
# set up before any of the container's own code can ask what the UID actually is.
RUN mkdir -p /run/xdg-runtime && chown vscode:vscode /run/xdg-runtime && chmod 700 /run/xdg-runtime

# The docker CLI's config dir (DOCKER_CONFIG in devcontainer.json). Created here,
# owned by vscode, so the very first `docker` command has somewhere to write
# instead of falling back to ~/.docker — which VS Code fills with a credential
# helper that does not work in here. Empty and harmless when the docker-in-docker
# feature is not enabled.
RUN mkdir -p /home/vscode/.docker-cli && chown vscode:vscode /home/vscode/.docker-cli

# pyenv for the vscode user (extra Python versions compiled on demand)
USER vscode
ENV PYENV_ROOT="/home/vscode/.pyenv"
# $PYENV_ROOT/versions is a persisted volume (see devcontainer.json): create it
# here, as vscode, so the volume is writable on first use.
RUN curl -fsSL https://pyenv.run | bash \
    && mkdir -p "$PYENV_ROOT/versions" \
    && for rc in /home/vscode/.bashrc /home/vscode/.zshrc; do \
        { \
            echo ''; \
            echo '# pyenv'; \
            echo 'export PYENV_ROOT="$HOME/.pyenv"'; \
            echo '[ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"'; \
            echo 'eval "$(pyenv init -)"'; \
        } >> "$rc"; \
    done

# Claude Code via the official native installer, run as the non-root user.
# NOT the claude-code devcontainer feature: that feature runs `npm install -g`
# as root, leaving the package root-owned inside the shared nvm global
# node_modules, so the CLI cannot update itself (EACCES) from the vscode user.
# The native installer keeps everything under $HOME (~/.local/bin/claude ->
# ~/.local/share/claude/versions/), which is user-owned and self-updating.
# HOME is set explicitly because it is not guaranteed after `USER vscode`.
ENV PATH="/home/vscode/.local/bin:${PATH}"
RUN HOME=/home/vscode bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
USER root

# Smaller conveniences, and whatever this project wants on top. Deliberately the
# LAST layer of this Dockerfile: this is the list that actually changes over time
# (you add a tool, you drop one), and being last means editing it leaves every apt
# layer, pyenv and the Claude installer above untouched in the cache.
# (The dev container CLI still appends the features on top of this image, and
# those do get rebuilt — see "Build speed" in the README.)
ARG EXTRA_PACKAGES=""
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "=== apt: extra tools ${EXTRA_PACKAGES:+(+ $EXTRA_PACKAGES)} ===" \
    && apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        sqlite3 \
        postgresql-client \
        shellcheck \
        shfmt \
        fzf \
        # A command runner for the project's own tasks. Only packaged from Ubuntu
        # 26.04 on, which is one reason the base image is pinned to it.
        just \
        $EXTRA_PACKAGES
