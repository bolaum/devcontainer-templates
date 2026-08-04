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
- **State that survives a rebuild** lives in named volumes scoped to the project
  with `${devcontainerId}`: `~/.claude` (whole dir — transcripts, `history.jsonl`,
  file-history), `~/.vscode-server` (hand-installed extensions + server binary),
  `~/.persist` (shell history, via `HISTFILE` in `shell/rc.sh`), `~/.npm`,
  `~/.cache/pip`, `~/.cache/pypoetry` (holds the virtualenvs too),
  `~/.pyenv/versions` and `~/.config/gh`. `~/.cache/ms-playwright` is the **one
  global** volume on purpose: Chromium is immutable content, not per-project state.
  Two consequences to keep in mind when touching this: the mount points must be
  created and `chown`ed in the `Dockerfile` (a fresh volume inherits the image
  dir's ownership, and Docker creates a missing one as root), and
  `setup-persist.sh` runs first in `postCreate` to re-`chown` them when
  `updateRemoteUserUID` remapped the user to a host UID other than 1000.
  `~/.claude.json` is deliberately not persisted — it is a file in `$HOME`, and
  `postCreate` rebuilds what matters in it anyway.
  Shell history needs more than `HISTFILE`: a shell only writes it on exit and a
  rebuild kills the container first, so `rc.sh` flushes every command as it is
  entered (`history -a` in `PROMPT_COMMAND` for bash, `INC_APPEND_HISTORY` for
  zsh). Append to `PROMPT_COMMAND`, never overwrite — VS Code's shell integration
  uses it too.
  `check-persistence.sh` verifies all of this from inside a container (run it,
  rebuild, run it again). It infers the phase from two markers with different
  lifetimes — state in the workspace (bind mount, always survives) and a session
  marker in `/tmp` (dies with the container) — plus a control file in `$HOME`
  that *must* disappear, which is what stops a "rebuild" that never happened from
  reporting success. Keep `TARGETS` in it in sync with the volume mounts.
- `postCreateCommand` runs `postCreate.sh`, which iterates over a `STEPS` array
  and prints `▶ [n/total] <script>` before each one, so a slow step is visibly a
  slow step and not a hang. Two positions are deliberate: `setup-persist.sh`
  first (volumes must be writable before anything writes to them) and
  `setup-apt.sh` **last** (the slowest step, hostage to mirror speed, and nothing
  else depends on it). The steps are:
  `setup-apt.sh` runs `apt-get update` so `sudo apt install <pkg>` works in a fresh
  container (the image ships with `/var/lib/apt/lists` emptied);
  `setup-claude.sh` copies `claude/settings.json` and `claude/statusline.py` into
  `~/.claude` (its `language` comes from the `claudeLanguage` option — the same key
  drives Claude's answers and `/voice` dictation, which otherwise defaults to English)
  and **merges** `hasCompletedOnboarding: true` into `~/.claude.json`
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

## Build speed (the `Dockerfile` apt layers)

Two mechanisms, both load-bearing — do not "simplify" them away:

- **`pick-apt-mirror.sh` runs before any package is installed.** It detects the
  country by IP, benchmarks that country's official mirrors (from
  `mirrors.ubuntu.com/<CC>.txt`) in parallel *against the default*, and switches
  only on a clear win (1.5x). It is primarily **resilience**: it was written
  during a Canonical outage that took `archive.ubuntu.com` and
  `security.ubuntu.com` down, where the two big apt layers went from 253s/206s to
  49s/36s just by using a working mirror (the benchmark costs ~9s). Do not read
  those numbers as a typical speedup — with a healthy default the 1.5x margin
  usually keeps it in place, which is the intent. Every failure path keeps the
  image default and exits 0 — a slow mirror is an annoyance, a broken build is
  not. Option `aptMirror`: `auto` | `keep` | country code | URL.
  `security.ubuntu.com` is left alone on purpose: it gets security updates first
  and mirrors lag behind.
- **apt lists and `.deb`s are BuildKit cache mounts**, not deleted at the end of
  each layer. The old `rm -rf /var/lib/apt/lists/*` only existed to keep ~45 MB
  out of the image, at the cost of making every later layer re-run a full
  `apt-get update`; a cache mount keeps them out of the image by construction and
  shares them across layers *and* builds. This requires deleting the base image's
  `/etc/apt/apt.conf.d/docker-clean` hook, which wipes the archives after every
  install and would leave the cache empty. **BuildKit is therefore mandatory** —
  documented in the README's Requirements.

## Templates: features in `base`

- Python: official `devcontainers/features/python` (option `pythonVersion`).
- Poetry: `devcontainers-extra/features/poetry` (installs after Python).
- Node: official `devcontainers/features/node` (nvm-based; option `nodeVersion`; no pnpm).
- pyenv: installed with build deps in the `Dockerfile` for compiling Python
  versions on demand (the official feature provides the default Python).
- GitHub CLI: official `devcontainers/features/github-cli`. **No host credential
  is inherited** — no `~/.config/gh` bind, no `GH_TOKEN`/`GITHUB_TOKEN` forwarding:
  a host token reaches every repo the user can, and anything in the container could
  read it. Two mechanisms replace it, and both are deliberate:
  - `git push` over ssh works through the **forwarded agent** — `initialize.sh`
    keeps `~/.ssh/devcontainer-agent.sock` symlinked to the live `$SSH_AUTH_SOCK`
    (random name per session) and that fixed path is mounted at
    `/tmp/host-ssh-agent`, matching `SSH_AUTH_SOCK` in `containerEnv`. Signing
    happens on the host, so the private key never enters the container. VS Code
    does its own forwarding and overrides the variable in its terminals; this
    mount is what makes the CLI path (`devcontainer exec`, `docker exec`) work.
  - `gh` authenticates per project with a **fine-grained token** scoped to one
    repository, via `gh-login` (`shell/gh.sh`). It is stored in the
    `devcontainer-gh-${devcontainerId}` volume mounted at `~/.config/gh`.
    The split is intentional: **git is covered by the agent, the token is only for
    the GitHub API** (`gh pr`, `gh issue`, `gh release`, `gh api`). Do not add
    `gh auth setup-git` — it would register a credential helper as a second,
    weaker path to what ssh already does, and its config lands in `~/.gitconfig`,
    which is not persisted.
    `shell/gh.sh` also wraps `gh` to print the walkthrough when a command fails
    *for lack of auth* — it runs the real `gh` first and only then checks, so
    normal use costs no extra API round-trip. Do not make it check up front.
    `shell/rc.sh` sources it via `$_DEVCONTAINER_SHELL_DIR`, which `setup-shell.sh`
    exports when wiring the rc files (a sourced file cannot locate itself the same
    way in bash and zsh).
- Playwright (option `installPlaywright`, default `true`): Chromium's ~31 apt
  dependencies live in the `Dockerfile` behind `ARG INSTALL_PLAYWRIGHT` (baked in,
  not reinstalled per container); `setup-playwright.sh` npm-installs `@playwright/mcp`
  plus **the exact `playwright` version the MCP package pins** — never `latest`, since
  the server pins an alpha build expecting a different Chromium revision and the
  mismatch only surfaces at Claude's first navigation — downloads the browser into
  the shared named volume
  `devcontainer-playwright-browsers`, writes `~/.claude/playwright-mcp.json` and
  registers the server with `playwright-mcp --config <that file>`.
  **`--no-sandbox` is mandatory** — Chrome's sandbox core-dumps in the container.
  Headed by default (option `playwrightHeadless`, default `false`): the browser is a
  native Wayland client of the host compositor via `--ozone-platform=wayland` and the
  socket already mounted for the clipboard, so you can watch Claude navigate.
- CLI tools are split across two layers on purpose:
  - the **base layer** has jq, ripgrep, fd-find (symlinked to `fd`), tree,
    unzip/zip, less, ffmpeg, imagemagick. ffmpeg and imagemagick live here because
    they are the expensive part (183 and 38 packages) and general-purpose enough
    to pay for once, up where the cache almost never invalidates.
    jq/tree/less/unzip/zip already ship in the base image and are listed only so
    it cannot silently lose them;
  - the **extra tools layer** (sqlite3, postgresql-client, shellcheck, shfmt) is
    the LAST layer of the Dockerfile. That is where new tools go: it is the list
    that actually churns, and being last means editing it leaves every apt layer,
    pyenv and the Claude installer cached. It also appends `$EXTRA_PACKAGES` from
    the `extraPackages` template option, for per-project additions.

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
  only publishes, it does not run the smoke tests (deliberately: releasing should
  be fast). The published version comes from each template's
  `devcontainer-template.json`, not the git tag.
  Republishing is safe: the CLI fetches the registry's tag list first and skips a
  version that is already there ("Version X already exists, skipping"), and only
  moves `latest` when the new version is higher than every published one.
- **Release tags once there is more than one template** — decided, not yet needed:
  switch the repo's release tag to a **date with a same-day counter**
  (`2026-08-04-01`, `2026-08-04-02`). Today's `v1.4.0` mirrors the single
  template's version, which stops making sense the moment `base` is at 1.4.0 and,
  say, `go` at 1.0.0: there is no honest number for the repo tag. Under the date
  scheme the GitHub Release is the *repository's* changelog, while each template's
  version lives in its `devcontainer-template.json` — and is traceable to a commit
  through the `template_<id>_<version>` tags the release workflow pushes (which is
  why that job needs `contents: write`).
- **Adding a template:** copy `src/base` to `src/<new-id>`, set `id`, reuse the
  Claude wiring, and add `test/<new-id>/test.sh`. `scripts/test.sh` and the
  workflows discover it automatically from `src/*`; its README is generated by the hook.
