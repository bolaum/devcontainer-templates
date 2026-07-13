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

# Ensure ~/.claude exists and is owned by the non-root user BEFORE the credentials
# bind-mount — otherwise Docker creates the parent directory as root and the
# postCreate step (running as vscode) cannot write settings.json/statusline.py.
RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude

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
USER root
