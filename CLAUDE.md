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
.github/workflows/  test (manual) + release (release/manual, gated on tests)
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
- `postCreateCommand` runs `postCreate.sh`, which orchestrates the setup steps:
  `setup-claude.sh` copies `claude/settings.json` and `claude/statusline.py` into
  `~/.claude` and seeds a minimal `~/.claude.json` (`hasCompletedOnboarding: true`)
  so Claude does not launch the onboarding/login flow — the token alone (mounted
  credentials) is not enough to skip it; `setup-shell.sh` sources
  `.devcontainer/shell/rc.sh` (aliases/functions) into `~/.bashrc` and `~/.zshrc`.
- **Auth is reused** via a bind-mount of the host's `~/.claude/.credentials.json`
  (declared in `mounts`). History/MCP/other state stay isolated per container.
- The `Dockerfile` creates and `chown`s `~/.claude` to the non-root user **before**
  the mount, so the bind-mount lands in a user-writable dir and `postCreate` can
  write into it.
- `initializeCommand` `touch`es the host credentials file so the mount is always
  a valid file.
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
  manually. Publishing is **gated on the smoke tests passing**. The published
  version comes from each template's `devcontainer-template.json`, not the git tag.
- **Adding a template:** copy `src/base` to `src/<new-id>`, set `id`, reuse the
  Claude wiring, and add `test/<new-id>/test.sh`. `scripts/test.sh` and the
  workflows discover it automatically from `src/*`; its README is generated by the hook.
