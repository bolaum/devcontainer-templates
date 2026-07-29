ARG VARIANT=ubuntu-24.04
FROM mcr.microsoft.com/devcontainers/base:${VARIANT}

# Build dependencies so pyenv can compile CPython on demand
# (pyenv install <version>). The "working" Python comes from the official feature.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
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
        llvm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Desktop bridges for Claude Code:
#   - voice dictation (/voice) records through SoX's `rec` or ALSA's `arecord`;
#   - image paste shells out to `wl-paste` (Wayland) or `xclip` (X11).
# The container has no /dev/snd and no display of its own, so both talk to the
# host through the sockets bind-mounted in devcontainer.json ("mounts").
# libsox-fmt-pulse is what makes `rec` work without an ALSA card — installing
# sox alone only pulls the ALSA backend, which has nothing to open here.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        sox \
        libsox-fmt-pulse \
        alsa-utils \
        libasound2-plugins \
        pulseaudio-utils \
        wl-clipboard \
        xclip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Route ALSA through the PulseAudio socket: without this, `arecord` (and SoX's
# ALSA backend) fail with "cannot find card '0'" since there is no /dev/snd.
RUN printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf

# Command-line toolbox. These are the tools Claude reaches for in shell commands
# and that a bare Ubuntu image does not have — without them it burns turns on
# "command not found" and falls back to clumsier alternatives.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        jq \
        ripgrep \
        fd-find \
        tree \
        unzip \
        zip \
        less \
        sqlite3 \
        postgresql-client \
        shellcheck \
        shfmt \
        ffmpeg \
        imagemagick \
    # Debian/Ubuntu ship fd as `fdfind` (name clash with another package)
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Chromium's system libraries, baked into the image so creating a container does
# not re-install ~200 MB of packages every time. The list is what
# `playwright install-deps --dry-run chromium` asks for on Ubuntu 24.04; the
# browser binary itself is installed in postCreate into a shared volume.
ARG INSTALL_PLAYWRIGHT=true
RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
        apt-get update && export DEBIAN_FRONTEND=noninteractive \
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
            xvfb \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Ensure ~/.claude exists and is owned by the non-root user BEFORE the credentials
# bind-mount — otherwise Docker creates the parent directory as root and the
# postCreate step (running as vscode) cannot write settings.json/statusline.py.
RUN mkdir -p /home/vscode/.claude /home/vscode/.config/gh \
    && chown -R vscode:vscode /home/vscode/.claude /home/vscode/.config

# XDG_RUNTIME_DIR for the container (see devcontainer.json): a headed Chromium
# talking to the host's Wayland compositor expects one, and there is no logind
# session in a container to create it.
RUN mkdir -p /tmp/xdg-runtime && chown vscode:vscode /tmp/xdg-runtime && chmod 700 /tmp/xdg-runtime

# pyenv for the vscode user (extra Python versions compiled on demand)
USER vscode
ENV PYENV_ROOT="/home/vscode/.pyenv"
RUN curl -fsSL https://pyenv.run | bash \
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
