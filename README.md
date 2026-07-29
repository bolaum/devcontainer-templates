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
- Docker
- `jq` (used by the local test runner)

## Templates

| Template | Description |
|----------|-------------|
| [`base`](./src/base) | Lean Ubuntu + Python (official feature) + Poetry + pyenv (build deps) + Node via nvm + preconfigured Claude Code. |

## `base`

A general-purpose, isolated Ubuntu environment. Everything you need to start
hacking on anything, with version managers so bumping runtimes is trivial.

### What's inside

- **Base image:** `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (option `imageVariant`).
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
  - a seeded `~/.claude.json` (`hasCompletedOnboarding: true`) so it skips the login flow;
  - **reused auth** via a bind-mount of the host's `~/.claude/.credentials.json`;
  - the VS Code Claude Code extension (`anthropic.claude-code`) preinstalled in the container.
- **Shell:** `.devcontainer/shell/rc.sh` (aliases/functions/exports) is sourced by
  `~/.bashrc` and `~/.zshrc` — edit it and open a new terminal to pick up changes.

### Options

| Option | Default | Values |
|--------|---------|--------|
| `imageVariant` | `ubuntu-24.04` | `ubuntu-24.04`, `ubuntu-22.04` |
| `pythonVersion` | `os-provided` | `os-provided`, `3.12`, `3.11`, … |
| `nodeVersion` | `lts` | `lts`, `none`, `22`, `20`, … |

### Verified versions

The smoke test builds the container and asserts the toolchain end to end. A fresh
build currently yields: Python 3.12.3, Poetry 2.4.1, pyenv 2.7.3, Node v24.18.1
(nvm), Claude Code 2.1.220.

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
  -a '{"pythonVersion":"3.12","nodeVersion":"22","imageVariant":"ubuntu-24.04"}'
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

An `initializeCommand` runs `touch ~/.claude/.credentials.json` on the host first,
so the bind-mount is always a valid file (even on machines that never logged in).

`setup-claude.sh` also seeds a minimal `~/.claude.json` (`hasCompletedOnboarding: true`).
Without it, Claude runs its onboarding/login flow even when a valid token is
mounted — the token is not enough on its own to mark the CLI as onboarded.

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

## Publishing to GHCR

The [`release.yaml`](./.github/workflows/release.yaml) workflow publishes the
templates to `ghcr.io/<owner>/<repo>/<template>`. It runs when a **GitHub Release
(with its tag) is published**, or manually (Actions → *Run workflow*). It runs the
**full smoke-test suite first and publishes only if it passes**.

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
every PR. The **release workflow runs the same smoke test** (`scripts/test.sh all`)
in its own `test` job and publishes only if it passes. Both bring up each
template's container and execute `test/<template>/test.sh` (checks python3, poetry,
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
