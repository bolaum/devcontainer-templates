# CLAUDE.md

Guidance for working in this repository.

## What this repo is

A personal collection of [Dev Container Templates](https://containers.dev/implementors/templates/).
Goal: make it **trivial to start any new project in an isolated environment**
(install deps without polluting the host) with **Claude Code preconfigured**
(settings, statusline and auth reused from the host, no re-authentication).
See [README.md](./README.md) for full details.

## Language

- **All repository content is in English** — code, comments, docs, identifiers,
  commit messages, workflow names. No other language in files.
- Conversation with the user may be in another language, but nothing that lands
  in the repo should be.

## Commits

- Write commit messages in English.
- **Do not add a `Co-Authored-By` trailer** (or any AI/agent attribution) to
  commit messages.

## Conventions

- **Assume `@devcontainers/cli` is already installed** on the machine. Local
  scripts require it and error out if missing — they must **not** install it
  (no `npm install` in local scripts). Only the CI workflows install it.
- **`jq`** and **Docker** are also assumed present for the local test runner.

## Layout

```
src/<id>/        each template: devcontainer-template.json + .devcontainer/ (+ generated README.md)
test/<id>/       test.sh for each template
test/test-utils/ shared test helpers (check / reportResults)
scripts/         test.sh, bump-version.sh, generate-docs.sh, setup.sh
.githooks/       pre-commit (regenerates per-template docs)
.github/workflows/  test (manual only) + release (release/manual, publish only)
```

## The Claude wiring (shared by every template — reuse it, don't reinvent)

Each template's `.devcontainer/` sets up Claude the same way:

- Installs the CLI in the `Dockerfile` with the official **native installer**
  (`curl -fsSL https://claude.ai/install.sh | bash`), run as the non-root user, so
  everything lands under `$HOME` (`~/.local/bin/claude` →
  `~/.local/share/claude/versions/`) and the CLI can update itself.
  **Do not use the `ghcr.io/anthropics/devcontainer-features/claude-code` feature:**
  it runs `npm install -g` as root, which leaves the package root-owned inside the
  shared nvm global `node_modules` and makes every update fail with `EACCES`.
- **Desktop bridges (Linux hosts):** `/voice` records with SoX's `rec` or ALSA's
  `arecord`, and image paste shells out to `wl-paste`/`xclip`. The container has
  no `/dev/snd` and no display, so `mounts` bind the host's PipeWire/PulseAudio
  socket (`$XDG_RUNTIME_DIR/pulse/native`) and Wayland socket
  (`$XDG_RUNTIME_DIR/wayland-0`) to fixed paths under `/tmp`, pointed at by
  `containerEnv` (`PULSE_SERVER`, absolute `WAYLAND_DISPLAY`). The `Dockerfile`
  installs `sox` **plus `libsox-fmt-pulse`** (sox alone only gets the ALSA backend,
  which has no card to open here) and writes `/etc/asound.conf` routing ALSA to
  pulse so `arecord` works too.
- `postCreateCommand` runs `postCreate.sh`, which orchestrates the setup steps:
  `setup-apt.sh` runs `apt-get update` so `sudo apt install <pkg>` works in a fresh
  container (the image ships with `/var/lib/apt/lists` emptied);
  `setup-claude.sh` copies `claude/settings.json` and `claude/statusline.py` into
  `~/.claude` and **merges** `hasCompletedOnboarding: true` into `~/.claude.json`
  so Claude does not launch the onboarding/login flow — the token alone (mounted
  credentials) is not enough to skip it. It must merge, not overwrite: the native
  installer already creates `~/.claude.json` at build time (`installMethod`,
  `machineID`, …), and a plain "create if absent" silently skips the seeding while
  overwriting would drop the install metadata. `setup-shell.sh` sources
  `.devcontainer/shell/rc.sh` (aliases/functions) into `~/.bashrc` and `~/.zshrc`.
- **Auth is reused** via a bind-mount of the host's `~/.claude/.credentials.json`
  (declared in `mounts`). History/MCP/other state stay isolated per container.
- The `Dockerfile` creates and `chown`s `~/.claude` to the non-root user **before**
  the mount, so the bind-mount lands in a user-writable dir and `postCreate` can
  write into it.
- `initializeCommand` runs `initialize.sh` **on the host**, which creates every
  bind-mount source that may be missing (credentials file, desktop sockets) —
  Docker would otherwise create a root-owned directory in its place.
- The VS Code Claude Code extension (`anthropic.claude-code`) is preinstalled via
  `customizations.vscode.extensions`, so the in-container VS Code Server exposes the
  IDE integration; an external terminal in the same container can connect with `/ide`.
- Bind-mount permissions rely on the container user's UID/GID matching the host's.
  `remoteUser: vscode` + `updateRemoteUserUID: true` (the default, set explicitly)
  make the tooling remap the container user to the host UID/GID on Linux, so the
  mounted credentials file is owned correctly even when the host UID is not 1000.

Do not mount the whole `~/.claude` — only the credentials file is shared by design.

## Templates: features in `base`

- Python: official `devcontainers/features/python` (option `pythonVersion`).
- Poetry: `devcontainers-extra/features/poetry` (installs after Python).
- Node: official `devcontainers/features/node` (nvm-based; option `nodeVersion`; no pnpm).
- pyenv: installed with build deps in the `Dockerfile` for compiling Python
  versions on demand (the official feature provides the default Python).
- GitHub CLI: official `devcontainers/features/github-cli`, with the host's
  `~/.config/gh` mounted and `GH_TOKEN`/`GITHUB_TOKEN` forwarded via `containerEnv`
  (host auth is often env-based, so the mount alone carries nothing).
- Playwright (option `installPlaywright`, default `true`): Chromium's ~31 apt
  dependencies live in the `Dockerfile` behind `ARG INSTALL_PLAYWRIGHT` (baked in,
  not reinstalled per container); `setup-playwright.sh` npm-installs `playwright` +
  `@playwright/mcp`, downloads the browser into the shared named volume
  `devcontainer-playwright-browsers`, writes `~/.claude/playwright-mcp.json` and
  registers the server with `playwright-mcp --config <that file>`.
  **`--no-sandbox` is mandatory** — Chrome's sandbox core-dumps in the container.
  Headed by default (option `playwrightHeadless`, default `false`): the browser is a
  native Wayland client of the host compositor via `--ozone-platform=wayland` and the
  socket already mounted for the clipboard, so you can watch Claude navigate.
- CLI toolbox in the `Dockerfile`: jq, ripgrep, fd-find (symlinked to `fd`), tree,
  unzip/zip, less, sqlite3, postgresql-client, shellcheck, shfmt, ffmpeg, imagemagick.

## Working here

- **Testing:** `bash scripts/test.sh <id|all>` — builds the container, brings it
  up, runs `test/<id>/test.sh` inside, then cleans up. Local and CI use the same
  script. Tests do not run on every PR.
- **Docs are generated, not hand-written:** `src/<id>/README.md` is produced from
  `devcontainer-template.json` by `scripts/generate-docs.sh`. A pre-commit hook
  regenerates and stages it when a `devcontainer-template.json` is committed. Never
  edit `src/*/README.md` by hand. Enable the hook with `bash scripts/setup.sh`.
- **Releasing:** bump the version with `bash scripts/bump-version.sh <id> <major|minor|patch|X.Y.Z>`,
  commit, then publish a GitHub Release (with a tag) or run the release workflow
  manually. **Run `bash scripts/test.sh all` locally first** — the release workflow
  only publishes, it does not run the smoke tests. The published version comes from
  each template's `devcontainer-template.json`, not the git tag.
- **Adding a template:** copy `src/base` to `src/<new-id>`, set `id`, reuse the
  Claude wiring, and add `test/<new-id>/test.sh`. `scripts/test.sh` and the
  workflows discover it automatically from `src/*`; its README is generated by the hook.
