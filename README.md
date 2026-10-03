# devcontainer-templates

Personal collection of [Dev Container Templates](https://containers.dev/implementors/templates/)
for spinning up any new project inside an **isolated** environment (install deps
without polluting the host) with **Claude Code already configured** — settings,
statusline and auth reused from the host, no re-authentication.

Publishable to GHCR following the official
[template-starter](https://github.com/devcontainers/template-starter) layout.

## Requirements

Assumed to be already installed on your machine (they are **not** installed for
you locally — the GitHub Actions workflows install the CLI themselves):

- [`@devcontainers/cli`](https://github.com/devcontainers/cli), installed either way:
  ```bash
  npm install -g @devcontainers/cli
  # or, with a bundled Node.js (no npm needed):
  curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh
  ```
- Docker **with BuildKit** — the default since Docker 23, and what both `buildx`
  and the devcontainer CLI use. The `Dockerfile` mounts BuildKit caches for apt
  (see [Build speed](#build-speed)), so building with `DOCKER_BUILDKIT=0` fails.
- `jq` (used by the local test runner)

## Templates

| Template | Description |
|----------|-------------|
| [`base`](./src/base) | Lean Ubuntu + Python (official feature) + Poetry + pyenv (build deps) + Node via nvm + preconfigured Claude Code. |

## `base`

A general-purpose, isolated Ubuntu environment. Everything you need to start
hacking on anything, with version managers so bumping runtimes is trivial.

### What's inside

- **Base image:** `mcr.microsoft.com/devcontainers/base:ubuntu26.04`, pinned to the
  current Ubuntu LTS rather than offered as an option — the layers install packages
  that release has, so an older base would fail the build rather than degrade.
- **Python:** official `devcontainers/features/python` feature (option `pythonVersion`, default `os-provided`).
- **Poetry:** `devcontainers-extra/features/poetry` feature (installs after Python).
- **pyenv:** installed with the required build dependencies (via the `Dockerfile`)
  so you can compile other Python versions on demand: `pyenv install 3.13.1`.
- **Node:** official `devcontainers/features/node` feature (via nvm; option
  `nodeVersion`, default `lts`). Add more with `nvm install 22`. No pnpm.
- **Claude Code:** installed with the official native installer
  (`https://claude.ai/install.sh`) as the non-root user, so it lives under
  `~/.local` and updates itself — the `claude-code` devcontainer feature is not
  used because its root-owned `npm install -g` breaks self-updates. Wired with:
  - `~/.claude/settings.json` (bypassPermissions, dark theme, fullscreen TUI, statusline);
  - `~/.claude/statusline.py` (copy of the host script);
  - `hasCompletedOnboarding: true` merged into `~/.claude.json` so it skips the login flow;
  - `language` (option `claudeLanguage`, default `portuguese`) — one setting drives both
    Claude's answers and `/voice` dictation; without it dictation transcribes as English;
  - **reused auth** via a bind-mount of the host's `~/.claude/.credentials.json`;
  - the VS Code Claude Code extension (`anthropic.claude-code`) preinstalled in the container.
- **Browser for Claude (option `installPlaywright`, default `true`):** Playwright with
  Chromium plus the `@playwright/mcp` server registered in Claude, so it can actually
  open and read pages. See [Browsing with Playwright](#browsing-with-playwright).
- **GitHub CLI:** official `devcontainers/features/github-cli` feature. The container
  inherits **no** GitHub credential from the host — `gh-login` sets up a token scoped
  to the current repository, and `git push` over ssh uses the forwarded agent.
  See [GitHub access](#github-access).
- **Command-line toolbox:** `jq`, `ripgrep` (`rg`), `fd`, `tree`, `unzip`/`zip`,
  `less`, `ffmpeg`, `imagemagick` (ImageMagick 7 — the command is `magick`) in the
  base layer; `sqlite3`, `postgresql-client` (`psql`), `shellcheck`, `shfmt`,
  `fzf` (bound to Ctrl+R) and `just` in a final **extra tools**
  layer you can extend — either by editing that list in the `Dockerfile` or via the
  `extraPackages` option. Being last, changing it leaves every other layer cached.
- **Microphone and clipboard (Linux hosts):** `/voice` dictation and image paste
  work inside the container. The host's PipeWire/PulseAudio and Wayland sockets are
  bind-mounted, and `sox` + `libsox-fmt-pulse`, `alsa-utils`, `wl-clipboard` and
  `xclip` are preinstalled. See [Microphone and clipboard](#microphone-and-clipboard).
- **apt ready to use:** `postCreate` runs `apt-get update`, so `sudo apt install <pkg>`
  works in a fresh container without running `apt update` first.
- **Shell:** `.devcontainer/shell/rc.sh` (aliases/functions/exports) is sourced by
  `~/.bashrc` and `~/.zshrc` — edit it and open a new terminal to pick up changes.
- **State that survives a rebuild:** Claude sessions, shell history, VS Code
  extensions installed by hand and the package manager caches live in named
  volumes scoped to the project. See [What survives a rebuild](#what-survives-a-rebuild).

### Options

| Option | Default | Values |
|--------|---------|--------|
| `pythonVersion` | `os-provided` | `os-provided`, `3.12`, `3.11`, … |
| `nodeVersion` | `lts` | `lts`, `none`, `22`, `20`, … |
| `claudeLanguage` | `portuguese` | `portuguese`, `english`, `spanish`, … |
| `aptMirror` | `auto` | `auto`, `keep`, a country code (`BR`), a mirror URL |
| `buildProgress` | `plain` | `plain`, `auto` |
| `installPlaywright` | `true` | `true`, `false` |
| `playwrightHeadless` | `false` | `true`, `false` |
| `installCodex` | `false` | `true`, `false` |
| `installDocker` | `on` | `on`, `off` (**not** `true`/`false` — see below) |

### Verified versions

The smoke test builds the container and asserts the toolchain end to end. A fresh
build on Ubuntu 26.04 currently yields: Python 3.14.4, Poetry 2.4.1, pyenv 2.8.4,
Node v24.19.0 (nvm), Claude Code 2.1.235, gh 2.97.0, ImageMagick 7.1.2 (`magick`),
just 1.45.0, fzf 0.67.0, and the Playwright release that `@playwright/mcp` pins.

## Usage

### Apply to a new project

`devcontainer templates apply -t` (and the VS Code wizard) take an **OCI reference**
to a *published* template — **not a local path**. So publish to GHCR first (see
[Publishing](#publishing-to-ghcr)), then, in an empty project folder:

```bash
# requires @devcontainers/cli — see Requirements
devcontainer templates apply -t ghcr.io/bolaum/devcontainer-templates/base
```

Then open the folder in VS Code → **"Reopen in Container"**, or run
`devcontainer up --workspace-folder .`.

The CLI does not prompt for options; set them non-interactively with `-a` (JSON):

```bash
devcontainer templates apply -t ghcr.io/bolaum/devcontainer-templates/base \
  -a '{"pythonVersion":"3.12","nodeVersion":"22","installCodex":"true"}'
```

### Use a local template (before publishing)

Since the CLI can't apply a local path, `scripts/apply.sh` fills the gap: it prompts
for each option, substitutes the `${templateOption:…}` placeholders, and copies the
template into a target folder (copying `.devcontainer/` by hand is not enough — the
placeholders would stay literal).

```bash
bash scripts/apply.sh base ~/projects/my-new-project              # prompt for each option
bash scripts/apply.sh base ~/projects/my-new-project --defaults   # use defaults, no prompts
```

Then open that folder in VS Code → **"Reopen in Container"**. To just verify the
template builds and its tools work, run the smoke test instead: `bash scripts/test.sh base`.

### Claude auth (important)

The container reuses your login by **bind-mounting `~/.claude/.credentials.json`**
from the host (read-write, so token refresh persists back). Claude therefore
starts already authenticated, no re-login. History, MCP and other state stay
**isolated** per container — only the credential is shared.

An `initializeCommand` runs `.devcontainer/initialize.sh` on the host first, which
creates `~/.claude/.credentials.json` if missing (even on machines that never logged
in) along with the other bind-mount sources, so no mount ever resolves to a
root-owned directory created by Docker.

`setup-claude.sh` also merges `hasCompletedOnboarding: true` into `~/.claude.json`.
Without it, Claude runs its onboarding/login flow even when a valid token is
mounted — the token is not enough on its own to mark the CLI as onboarded. It has to
*merge*: the native installer already writes that file during the image build, so
creating it only when missing would silently skip the flag.

Bind-mount permissions on Linux depend on the container user's UID/GID matching the
host's. `remoteUser: vscode` + `updateRemoteUserUID: true` let the tooling remap the
container user to the host UID/GID on container creation, so the mounted credentials
file is readable even when the host user's UID is not the image default (1000).

> ⚠️ **Security note:** any process inside the container gains access to your
> Claude token. That is the trade-off for not re-authenticating; it is meant for
> a personal dev environment.

### Attach a terminal from outside VS Code

When VS Code opens the project in the dev container, you can attach a shell to that
**same running container** from any host terminal (e.g. tmux) — not only the VS Code
integrated terminal. The container must already be up (VS Code running it).

```bash
# Preferred: uses the configured remote user and workspace folder automatically.
devcontainer exec --workspace-folder /path/to/project bash
# From the project directory, "$PWD" works too. Run a command directly, e.g. Claude:
devcontainer exec --workspace-folder "$PWD" claude
```

```bash
# Fallback with plain Docker (VS Code labels the container with the workspace path):
cid=$(docker ps -q --filter "label=devcontainer.local_folder=/path/to/project")
docker exec -it -u vscode "$cid" bash
```

Since the container ships Claude preconfigured and authenticated, running `claude`
from such an external terminal just works with your reused auth.

To make Claude in that external terminal see your **VS Code context** (open file,
line selection, diagnostics), run `/ide` inside it and pick the VS Code instance —
the external terminal shares the container's filesystem and localhost with the
in-container VS Code Server, so it connects. The `anthropic.claude-code` extension
is preinstalled in the container (via `customizations.vscode.extensions`), which is
what makes the IDE discoverable. (The integrated terminal connects automatically; an
external terminal needs `/ide`.)

## Browsing with Playwright

With `installPlaywright` (default `true`), the container gets Chromium **and** the
`@playwright/mcp` server registered in Claude's user scope, which is what turns
"Claude can run browser scripts" into "Claude can browse". Check it with
`claude mcp list` or `/mcp` inside a session.

How the pieces are split, and why:

| Piece | Where | Why |
|-------|-------|-----|
| Chromium's system libraries (31 apt packages) | `Dockerfile`, behind `ARG INSTALL_PLAYWRIGHT` | Baked into the image so creating a container does not reinstall ~200 MB each time. The list comes from `playwright install-deps --dry-run chromium`. |
| `playwright` + `@playwright/mcp` (npm, global) | `setup-playwright.sh` (postCreate) | Node comes from a feature, which only exists after the image is built. |
| The browser binary | `setup-playwright.sh`, into a **named volume** (`devcontainer-playwright-browsers`) | Shared by every container from this template, so the ~150 MB download is paid once per machine, not once per project. |

The Playwright version is **not** `latest`: `setup-playwright.sh` reads the version
`@playwright/mcp` pins (`npm view @playwright/mcp@latest dependencies.playwright`)
and installs exactly that. The MCP server pins an *alpha* build whose Chromium
revision differs from the stable release — installing `playwright@latest` next to it
downloads a revision the server never looks for, so postCreate succeeds and then the
first navigation fails with `Browser "chromium" is not installed` while the volume
holds two revisions (~1.3 GB). Reading the pin keeps one revision, shared by the
server and by your own scripts, and it keeps working across MCP bumps.
`setup-playwright.sh` verifies the browsers the server resolves are on disk and fails
at create time instead of at Claude's first navigation.

### Watching the browser (headed by default)

With `playwrightHeadless` at its default `false`, Chromium renders **on your desktop
through the same Wayland socket used for the clipboard** — the window opens on your
screen and you watch Claude drive it. Set the option to `true` on a machine with no
desktop session.

The launch flags live in `~/.claude/playwright-mcp.json` (generated by
`setup-playwright.sh`, passed with `playwright-mcp --config`):

| Flag | Why |
|------|-----|
| `--no-sandbox` | Chrome's sandbox needs privileges the container does not have; without it the browser aborts with a core dump, leaving an MCP server that is registered but useless. |
| `--disable-dev-shm-usage` | Docker's default `/dev/shm` is 64 MB, too small for Chromium. |
| `--ozone-platform=wayland` (headed only) | Makes Chromium a native Wayland client of your compositor. |
| `--ignore-gpu-blocklist` (headed only) | Without it Chromium refuses a passed-through GPU in the container and renders in software. |

**GPU (NVIDIA).** With an NVIDIA card and `nvidia-container-toolkit` on the
host, headed Chromium renders on the GPU — canvas, compositing, rasterization,
WebGL and WebGPU (check `GL_RENDERER` in `chrome://gpu`). It needs one step per
host, because the tooling only detects a GPU through an `nvidia` runtime that
the toolkit does not register by itself:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

`hostRequirements.gpu` is `optional`, so a host without that runtime — a GPU-less
one, CI — just starts without a GPU and renders in software. Video **decoding**
stays in software on NVIDIA regardless: Chromium skips NVIDIA for VA-API, and the
GPU process says so in its log ("Should skip nVidia device"). Chromium logs D-Bus
and DRM errors on startup in a container — they are noise, not failures.

`~/.claude/playwright-mcp.json` is only written when absent and lives in a
persisted volume, so a container created before a flag change keeps the old
flags: delete the file and rebuild to pick the new ones up.

Set `installPlaywright` to `false` when applying the template to skip all of it.

## Microphone and clipboard

Claude Code shells out to host tools for two features, and neither works in a
container out of the box: `/voice` dictation records through SoX's `rec` (or ALSA's
`arecord`), and pasting an image reads the clipboard with `wl-paste` (or `xclip`).
A container has no `/dev/snd` and no display of its own.

The template bridges both from the host, on **Linux**:

| What | How |
|------|-----|
| Audio | `$XDG_RUNTIME_DIR/pulse/native` bind-mounted to `/run/host-pulse`, with `PULSE_SERVER=unix:/run/host-pulse` |
| Clipboard | `$XDG_RUNTIME_DIR/wayland-0` bind-mounted to `/run/host-wayland`, with `WAYLAND_DISPLAY=/run/host-wayland` (an absolute value is used as-is by libwayland) |
| Packages | `sox`, `libsox-fmt-pulse`, `alsa-utils`, `libasound2-plugins`, `pulseaudio-utils`, `wl-clipboard`, `xclip` |
| ALSA | `/etc/asound.conf` routes `default` to pulse, so `arecord` finds a device |

`libsox-fmt-pulse` is the non-obvious bit: installing `sox` alone only brings the
ALSA backend, which has no card to open here, so `rec` fails even though sox is
installed.

The sockets land in `/run`, not `/tmp`, and that is load-bearing: `/tmp` is fair
game for anything that runs before you. The docker-in-docker feature's entrypoint,
for instance, mounts a `tmpfs` over `/tmp` on every container **start**, long after
Docker bound the sockets there — so they get shadowed with no error anywhere.
`docker inspect` still lists the mounts, and what you see instead is a silent
microphone, a browser that cannot reach the compositor, and `git push` without an
agent.

Check it from inside the container with `pactl info` (should report the host's
PulseAudio/PipeWire server), `rec -q -t wav /tmp/t.wav trim 0 1` (should produce a
non-empty file) and `wl-paste --list-types` (should list what you last copied — copy
an image and it lists `image/png`).

Notes:

- If your Wayland session is not `wayland-0`, change the mount source in
  `.devcontainer/devcontainer.json` and the placeholder in `.devcontainer/initialize.sh`.
- On a host with no desktop session (macOS, a CI runner), `initialize.sh` creates
  placeholder files so the container still builds — it just has no audio or clipboard.
- The VS Code Claude Code extension does **not** support dictation in Dev Containers
  (the microphone is on the local machine and the extension runs on the remote host);
  this bridge is for the CLI running inside the container.

## Build speed

Two things in the `Dockerfile` exist purely so an uncached build does not crawl.

### It picks the fastest apt mirror

Before any package is installed, `pick-apt-mirror.sh` detects the country by IP,
fetches the official mirror list for it (`mirrors.ubuntu.com/<CC>.txt`),
benchmarks those mirrors **in parallel** against the default, and switches only
if one wins by a clear margin.

The point is resilience as much as speed. This was written during a Canonical
outage that took `archive.ubuntu.com` and `security.ubuntu.com` down: the two apt
layers were taking 253s and 206s to move 42 MB, and dropped to 49.5s and 35.8s
once the build was pointed at a working mirror. Picking the mirror costs ~9s.

Those numbers are what a *broken* default looks like, not a typical gain — when
`archive.ubuntu.com` is healthy it usually wins the benchmark or loses by too
little to matter, and stays. That is the intent: the 1.5x margin exists so a
well-maintained default is not swapped for a random mirror that measured slightly
better once. Every failure path (no network, unknown country, no mirror list,
nothing faster) keeps the image default and never fails the build.

Controlled by the `aptMirror` option: `auto` (default), `keep` to disable, a
country code like `BR` to skip detection, or a full mirror URL.

`security.ubuntu.com` is deliberately left alone — it publishes security updates
first and mirrors lag behind it.

### apt caches live in BuildKit, not in the image

Each apt layer would normally end with `rm -rf /var/lib/apt/lists/*`, purely to
keep ~45 MB of package indexes out of the image — which forces the *next* layer
to run a full `apt-get update` again.

Instead, the lists and the downloaded `.deb` files are mounted as BuildKit
caches:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y ...
```

They stay out of the image by construction, are shared across layers, and
survive between builds. The base image's `docker-clean` hook is removed for this
to work — it wipes the archives after every install, which would leave the cache
permanently empty.

This is why BuildKit is a hard requirement (see [Requirements](#requirements)).

### Seeing which layer is slow

BuildKit's compact progress output truncates each step at around 60 characters,
and `RUN --mount=type=cache,target=/var/cache/apt,sharing=locked` fills that on
its own — so every apt layer shows up as the same unhelpful
`RUN --mount=type=cache,` and you cannot tell which one is taking the time.

That is why **`buildProgress` defaults to `plain`**: the template passes
`--progress=plain` to `docker build` through `build.options`, so every step is
printed in full. It works the same in VS Code and from the CLI, since the
extension runs the same code. Set the option to `auto` for the quieter view.

(`BUILDKIT_PROGRESS=plain` in the environment does the same thing for a one-off
run, but for VS Code it has to be set on the VS Code process itself — the
template option avoids that.)

Each apt layer starts by echoing what it is, so they announce themselves:

```
=== apt: pyenv build dependencies ===
=== apt: desktop bridges (microphone + clipboard) ===
=== apt: CLI toolbox (ffmpeg and imagemagick make this the slow one) ===
=== apt: Chromium system libraries ===
```

## GitHub access

A container is a place where a lot of code you did not write gets to run: install
scripts, build tooling, an agent with broad permissions. So the template gives it
**no credential that reaches more than the project itself**.

The split is deliberate: **git goes through the forwarded ssh agent, the token is
only for the GitHub API.** Neither one can reach beyond what it needs.

### Git: the ssh agent is forwarded

The host's `$SSH_AUTH_SOCK` is mounted at `/run/host-ssh-agent`. The container
asks the agent **on the host** to sign; the private key never enters the
container, so there is nothing to leak into a log, a volume or an image layer.
Clone, fetch and push over ssh just work — no token involved.

Because the agent socket has a random per-session name, `initialize.sh` keeps
`~/.ssh/devcontainer-agent.sock` pointed at the live one and that fixed path is
what gets mounted. With no agent running, it drops a placeholder and the
container simply has no forwarding.

`~/.ssh` inside the container is a persisted volume, so `known_hosts`, an ssh
config and any key you deliberately generate in there survive a rebuild. None of
that changes where *your* key lives: it stays on the host, and the agent is still
what signs.

One thing worth knowing, because it is not obvious and nothing announces it: on
the **VS Code** path the Dev Containers extension copies the host's entire
`~/.ssh/known_hosts` into the container shortly after it starts — measured here as
a byte-identical copy, hundreds of hosts, arriving about 0.4 s in. No private key
crosses over, but your SSH *history* — every host you have connected to, hashed or
not — does. If that matters for a project, delete the file inside the container;
it will not come back (see below).

It copies **only when the file is absent**. The extension's helper tests
`[ -e '<dest>' ] && exit 1` before writing, so now that `~/.ssh` is a persisted
volume the host's file is snapshotted **once**, on the container's first start,
and left alone from then on. Two consequences: a host key you accept inside the
container stays accepted across rebuilds, and hosts you add on the *host* after
that first copy never appear in the container. On the plain `devcontainer up` path
nothing creates the file at all, which is why the checklist passes
`-o StrictHostKeyChecking=accept-new`.

This works the same whether you open the folder in VS Code or run
`devcontainer up` from the CLI. (VS Code also does its own agent forwarding and
overrides `SSH_AUTH_SOCK` in the terminals it opens; the mount above is what
covers `devcontainer exec` and any terminal attached with plain `docker exec`.)

The honest limit: while the container is up, anything in it can *use* the agent
to sign. What it cannot do is take the key with it.

### `gh`: one token per repository

Nothing is inherited — not `~/.config/gh` (which on a keyring-based host carries
no token anyway), not `GH_TOKEN`, not `GITHUB_TOKEN`. A host token reaches every
repository you can; that is exactly what should not be in here.

Instead, run `gh-login` inside the container. It walks you through creating a
**fine-grained token** limited to the current repository — repo name and a
paste-ready token name are filled in from `git remote` — then reads it with echo
off (so it never reaches the shell history) and hands it to
`gh auth login --with-token`.

Forget to authenticate and `gh` will tell you: the shell wraps it so that a
command failing *for lack of auth* prints the walkthrough. It runs the real `gh`
first and only checks on failure, so there is no round-trip on normal use.

There is no `gh auth setup-git`: git is already covered by the agent, and
registering a credential helper would only add a second, weaker path to the same
thing. If you deliberately want an https remote to use the token, run that
command yourself.

The token lands in `~/.config/gh`, a named volume scoped to this project: it
survives rebuilds, the host's own config is never touched, and it stays out of
`$HOME` where backups and sync tools would find it. To revoke, delete the token
on GitHub or `docker volume rm devcontainer-gh-<id>`.

Why a fine-grained token rather than `gh auth login` in the browser: OAuth scopes
are per *capability*, not per repository — the smallest one that makes `gh` work
is `repo`, which opens every private repository you have.

## What survives a rebuild

Rebuilding a dev container throws away the container's filesystem: without help,
every Claude session transcript, every shell command you ran and every package
you downloaded is gone. The template puts that state in **named volumes scoped to
the project**, so `devcontainer up --build-no-cache` (or *Rebuild Container* in
VS Code) is a cheap operation.

| Volume | Mounted at | What you keep |
|--------|------------|---------------|
| `devcontainer-claude-<id>` | `~/.claude` | Session transcripts (`claude --resume` / `--continue`), prompt history (`history.jsonl`), file history, plugins |
| `devcontainer-vscode-server-<id>` | `~/.vscode-server` | Extensions you installed by hand, the VS Code Server binary (~100 MB), editor state |
| `devcontainer-persist-<id>` | `~/.persist` | Shell history (`HISTFILE` is pointed here by `shell/rc.sh`) |
| `devcontainer-npm-<id>` | `~/.npm` | npm cache |
| `devcontainer-pip-<id>` | `~/.cache/pip` | pip cache |
| `devcontainer-poetry-<id>` | `~/.cache/pypoetry` | Poetry cache **and its virtualenvs** — the project's env, not just the downloads |
| `devcontainer-pyenv-<id>` | `~/.pyenv/versions` | Pythons compiled with `pyenv install` (minutes each) |
| `devcontainer-gh-<id>` | `~/.config/gh` | The project's GitHub token (see [GitHub access](#github-access)) |
| `devcontainer-codex-<id>` | `~/.codex` | The Codex login, when `installCodex` is on (mounted either way) |
| `devcontainer-ssh-<id>` | `~/.ssh` | `known_hosts`, an ssh config, and any key you generate inside the container |
| `devcontainer-playwright-browsers` | `~/.cache/ms-playwright` | Chromium — the one **global** volume (see below) |

`<id>` is `${devcontainerId}`, which the tooling derives from the workspace: two
projects built from this same template get different volumes and never see each
other's sessions or history.

### Checking it yourself

`.devcontainer/check-persistence.sh` verifies the whole thing end to end. Run it,
rebuild, run it again — it figures out which run it is:

```bash
bash .devcontainer/check-persistence.sh   # 1. seeds a marker in every volume
# rebuild: F1 -> "Dev Containers: Rebuild Container"
bash .devcontainer/check-persistence.sh   # 2. reports what survived
```

The second run prints a line per volume (`kept` / `LOST`) and compares real state
before and after — Claude sessions, VS Code extensions, shell history lines,
pyenv versions, the `gh` account. It exits non-zero if anything was lost.

Two details make the result trustworthy. It writes a **control file in `$HOME`**,
which is *not* a volume: if that file is still there on the second run, the
container was never rebuilt and the script says so instead of reporting a
meaningless success. And it keeps its state in `.devcontainer/`
— i.e. in the workspace, a bind mount that always survives — plus a marker in
`/tmp` (which dies with the container), so running it twice without rebuilding is
detected rather than passed.

`--reset` starts over.

Notes and caveats:

- **Playwright is deliberately global.** Chromium is immutable content, not
  per-project state, so the ~150 MB download is paid once per machine. Scoping it
  per project would cost bandwidth and buy no isolation.
- **Moving or renaming the project folder changes `${devcontainerId}`.** The old
  volumes are not deleted, they just stop being attached — the state looks lost.
- **`~/.claude.json` is *not* persisted.** It lives in `$HOME` (not in `~/.claude`)
  and is a file, which cannot be a volume. Nothing important is lost: `postCreate`
  re-registers the Playwright MCP server and re-applies `hasCompletedOnboarding`
  on every rebuild, and sessions are read from `~/.claude/projects`.
- **Shell history needs more than a volume.** A shell only writes its history when
  it exits, and a rebuild kills the container first — closing the terminal
  beforehand does not help either. So `rc.sh` flushes every command as it is
  entered (`history -a` in `PROMPT_COMMAND` for bash, `INC_APPEND_HISTORY` for zsh).
- **Ownership.** A fresh volume inherits the ownership of the image directory it
  covers (uid 1000), which is the wrong user when `updateRemoteUserUID` remaps
  `vscode` to a host UID other than 1000. `setup-persist.sh` runs first in
  `postCreate` and fixes it — including `XDG_RUNTIME_DIR`, which is not persisted
  but is created at build time and has the same problem. Nothing in the template
  assumes uid 1000 at runtime; `id -u` is the only source.
- **Cleaning up.** Volumes accumulate as projects come and go:

  ```bash
  docker volume ls --filter name=devcontainer-
  docker volume rm devcontainer-claude-<id> …   # or `docker volume prune` for all unused
  ```

## Verifying a container

`.devcontainer/VERIFY.md` is a checklist written for an agent. Point Claude at it
from inside the container and it sweeps everything the template wires up — the
Claude install, the persisted volumes, the host bridges, GitHub access, the
browser, the toolbox, the shell — and reports per item:

```
Read .devcontainer/VERIFY.md and work through it.
```

It marks the handful of things a shell cannot settle (did the microphone actually
capture sound? did the browser window appear?) as needing a person, so a clean run
is not mistaken for a fully verified one. The repo's own `scripts/test.sh` covers
the same ground non-interactively, but only for this repository — `VERIFY.md`
ships with the template and works in the project you applied it to.

## Docker inside the container

Option `installDocker`, `on` by default: a Docker daemon inside this container,
so a project's own `compose.yaml` is built and run from in here. Set it to `off`
for a container without one:

```bash
devcontainer templates apply -t ghcr.io/bolaum/devcontainer-templates/base \
    -a '{"installDocker":"off"}'
```

**`on`/`off`, never `true`/`false`.** The CLI substitutes options with
`templateArgs[name] || ""`, so any falsy value — a JSON `false` above all — lands
as an **empty string**. A boolean option here would resolve to a feature path that
does not exist, on its own default. (The same quirk is why `PLAYWRIGHT_HEADLESS`
and `INSTALL_CODEX` come out as `""` rather than `"false"` in an applied
`devcontainer.json`; the scripts reading them treat empty as false on purpose.)
Neither the CLI's `-a` nor the VS Code prompt validates a value against `enum`, so
a wrong one is only caught much later, by whatever tries to use it.

**Why it selects a directory.** The Template spec only substitutes strings — it
cannot add or remove a features entry — and docker-in-docker has no off switch of
its own (`version: "none"` still applies its static metadata: `privileged`, the
entrypoint, the volumes). So the option picks `./features/docker-on` or
`./features/docker-off`. The first installs nothing itself and declares
`dependsOn` on the real feature; the CLI aggregates metadata across every
installed feature, so `privileged`, the entrypoint and the two volumes come along.
The second is empty.

It is on by default, and that has a price: the container is **privileged**,
which the feature requires and does not let you turn off. `off` is the way to an
unprivileged container.

`moby: false` is set on the dependency and is **required on Ubuntu 26.04**: the
feature defaults to the Moby packages, which are not built for `resolute`, and it
refuses to install rather than fall back. With `false` it installs Docker CE from
`download.docker.com` — `docker-ce`, `docker-ce-cli`, `containerd.io`,
`docker-buildx-plugin`, `docker-compose-plugin`, i.e. exactly the package set in
[Docker's own Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/).

What the feature adds on top of that `apt install` is the part worth not
rewriting: a container has no systemd, so something has to start and supervise
`dockerd` and `containerd`, set up cgroup v2 delegation and pick between iptables
and nftables. That is ~200 lines of generated entrypoint
(`/usr/local/share/docker-init.sh`).

The rest is wired around it, and stays inert when it is off:

- `setup-docker.sh` in `postCreate` waits for the daemon and checks `compose` and
  `buildx`, so a broken daemon fails the create instead of surfacing later as a
  confusing project error;
- `DOCKER_CONFIG=/home/vscode/.docker-cli` keeps the CLI's config out of
  `~/.docker`, where VS Code writes a `credsStore` pointing at a host credential
  helper that fails in here and breaks **every** `docker pull`, anonymous ones
  included;
- `init: true` reaps the zombies a background `dockerd`/`containerd` leaves behind;
- the host bridges live in `/run` precisely because this feature's entrypoint
  mounts a `tmpfs` over `/tmp` on every start.

Not the host's socket (docker-outside-of-docker): handing over
`/var/run/docker.sock` is root on the host, and bind-mount paths in a sibling
container resolve against the **host** filesystem, so a relative path in a
`compose.yaml` would silently point at nothing.

The nested daemon's images, containers and volumes persist in
`dind-var-lib-docker-<id>` and `dind-var-lib-containerd-<id>`, named per workspace
like the rest.

## Codex alongside Claude (opt-in)

Option `installCodex` (default `false`) installs the OpenAI Codex CLI next to
Claude Code. Only the CLI: `codex login` is an interactive browser round trip
against a personal account, and which account a container gets to spend is your
decision, not a setup step's.

The credentials it writes to `~/.codex/auth.json` live in the per-project
`devcontainer-codex-<id>` volume, so the login survives rebuilds. The volume is
mounted whether or not the CLI is installed — an empty volume costs nothing, and a
mount cannot be made conditional either.

## Publishing to GHCR

The [`release.yaml`](./.github/workflows/release.yaml) workflow publishes the
templates to `ghcr.io/<owner>/<repo>/<template>`. It runs when a **GitHub Release
(with its tag) is published**, or manually (Actions → *Run workflow*). It only
publishes — **run `bash scripts/test.sh all` locally before releasing**.

Typical flow:

1. Bump the template version: `bash scripts/bump-version.sh base patch`
   (or `minor` / `major` / an explicit `X.Y.Z`; `all` bumps every template).
2. Commit (the pre-commit hook regenerates the docs) and push.
3. On GitHub, **create a Release** with a tag (e.g. `v1.1.0`) and publish it.
4. The release workflow runs the tests, then publishes each template at the semver
   from its own `devcontainer-template.json` (the git tag only triggers the run).

The namespace is derived automatically from the repository (`owner/repo`). Publishing
uses the built-in `GITHUB_TOKEN` (needs `write:packages`, granted by the workflow's
`packages: write` permission).

## Testing

[`test.yaml`](./.github/workflows/test.yaml) runs the smoke test **manually**
(Actions → *Test Templates* → *Run workflow*, pick one template or `all`) — not on
every PR. The **release workflow does not run it**: the smoke test is meant to be
run locally before releasing, since a runner build takes minutes. It brings up each
template's container and executes `test/<template>/test.sh` (checks python3, poetry,
pyenv, node/nvm, claude and the `~/.claude` wiring).

Both the workflow and local runs use the same script — run it locally with:

```bash
bash scripts/test.sh base              # one template (build + up + test.sh + cleanup)
bash scripts/test.sh all               # every template under src/
bash scripts/test.sh base --no-cache   # force a clean rebuild (bypass Docker layer cache)
```

Use `--no-cache` (or `NO_CACHE=1`) when you want the build to run from scratch —
a cached image can hide a broken `Dockerfile`/feature step. It passes
`--build-no-cache --remove-existing-container` to `devcontainer up`. CI runners are
ephemeral, so CI already builds fresh every run.

A value other than an option's default is not exercised by that run. Override it:

```bash
TEMPLATE_OPTIONS='installDocker=off' bash scripts/test.sh base
```

The docker checks in `test/base/test.sh` are skipped when there is no docker CLI,
so both runs are green for the right reason.

## Docs & git hooks

Per-template `README.md` files (e.g. [`src/base/README.md`](./src/base/README.md))
are **auto-generated** from each `devcontainer-template.json` by
[`scripts/generate-docs.sh`](./scripts/generate-docs.sh). A **pre-commit hook**
regenerates and stages them whenever a `devcontainer-template.json` is part of the
commit — so the docs never drift.

Enable the hook once after cloning:

```bash
bash scripts/setup.sh        # sets git config core.hooksPath=.githooks
```

Regenerate manually if needed: `bash scripts/generate-docs.sh`
(override the target repo with `GITHUB_OWNER=… GITHUB_REPO=…`).

## Repository layout

```
src/<template>/          # each template (devcontainer-template.json + .devcontainer/)
test/<template>/         # test.sh for each template
test/test-utils/         # test helpers (check / reportResults)
scripts/                 # test.sh (smoke test), apply.sh (local apply), bump-version.sh, generate-docs.sh, setup.sh
.githooks/               # pre-commit hook (regenerates per-template docs)
.github/workflows/       # release (publish to GHCR) + test (manual smoke test)
```

## Adding a new template

1. Copy `src/base` to `src/<new-id>` and set `id` in `devcontainer-template.json`.
2. Reuse the Claude wiring (`.devcontainer/setup-claude.sh`, `claude/`, the
   credentials mount and the `~/.claude` chown in the `Dockerfile`).
3. Add `test/<new-id>/test.sh` — `scripts/test.sh` and the `test` workflow discover
   it automatically from `src/*`. The doc README is generated by the pre-commit hook.

## License

[MIT](./LICENSE)
