# Verifying this dev container

A checklist for an agent (or a person) to confirm the container is fully wired.
Run it from **inside** the container, from the workspace root.

    Read .devcontainer/VERIFY.md and work through it.

Report one line per item: `ok`, `FAIL` with the command's actual output, or
`skipped` with the reason. Do not repair anything while checking — finish the
sweep first, then propose fixes. Never report an item as `ok` without having run
its command, and never soften a failure into a warning.

Some items cannot be settled from a shell and are marked **[human]** — ask the
person to look and tell you, or report `needs a human`.

---

## 1. Claude Code

```bash
claude --version
command -v claude                      # must be $HOME/.local/bin/claude
test -w "$HOME/.local/share/claude"    # self-update needs this writable
python3 -c 'import json,os;d=json.load(open(os.path.expanduser("~/.claude.json")));print(d.get("hasCompletedOnboarding"), d.get("installMethod"))'
```

Expected: the CLI is under `$HOME` (not a root-owned global npm install), and the
last line prints `True native` — onboarding pre-answered *and* the installer's own
metadata still there, which is what proves `setup-claude.sh` merged into that file
instead of overwriting it.

```bash
jq '.language, .voice' "$HOME/.claude/settings.json"
test -f "$HOME/.claude/statusline.py"
```

`language` drives both Claude's answers and `/voice` dictation.

## 2. State that must survive a rebuild

The real test is the two-phase one — it is the only item here that proves
anything about a *rebuild*:

```bash
bash .devcontainer/check-persistence.sh     # phase 1: seeds markers
# now rebuild: "Dev Containers: Rebuild Container",
# or  devcontainer up --remove-existing-container --workspace-folder .
bash .devcontainer/check-persistence.sh     # phase 2: reports what survived
```

Phase 2 must end with every target `ok` **and** the control-file line saying the
file in `$HOME` is gone. If that line says the control file survived, the
container was not actually rebuilt and the rest of the report means nothing.

Without a rebuild you can still confirm the mounts are in place:

```bash
for d in ~/.claude ~/.codex ~/.config/gh ~/.vscode-server ~/.persist ~/.npm \
         ~/.cache/pip ~/.cache/pypoetry ~/.cache/ms-playwright ~/.pyenv/versions; do
    mountpoint -q "$d" && [ -w "$d" ] && echo "ok    $d" || echo "FAIL  $d"
done
```

A plain directory instead of a mount point means the volume silently did not
attach and everything in it dies on the next rebuild.

## 3. Host bridges (audio, clipboard, ssh agent)

```bash
printf '%s\n' "$PULSE_SERVER" "$WAYLAND_DISPLAY" "$SSH_AUTH_SOCK" "$XDG_RUNTIME_DIR"
```

All four must live under `/run`. Anything under `/tmp` is one `tmpfs` away from
vanishing — the docker-in-docker feature's entrypoint mounts exactly that over
`/tmp` on every container start, which hides the sockets with no error anywhere.

```bash
ls -l /run/host-pulse /run/host-wayland /run/host-ssh-agent
```

Each should be a **socket** (`s` in the mode). A regular empty file means the host
had nothing to bind there — `initialize.sh` creates a placeholder so the container
still starts, and the corresponding feature is simply unavailable.

```bash
timeout 5 rec -q -r 16000 -c 1 /tmp/verify-mic.wav trim 0 1 && \
    ls -l /tmp/verify-mic.wav && rm -f /tmp/verify-mic.wav
wl-paste --list-types || echo "clipboard empty or unavailable"
```

**[human]** Recording a non-empty file proves the audio path; whether it captured
actual sound needs a person. Ask them to copy an image on the host, then re-run
`wl-paste --list-types` and expect an `image/png`.

## 4. GitHub access

Two separate mechanisms, on purpose — git signs through the forwarded agent, and
`gh` uses a token scoped to one repository.

```bash
ssh-add -l                              # keys live on the host; this lists them
ssh -T git@github.com 2>&1 | head -1    # "successfully authenticated" is success
[ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && echo "ok: no host token inherited"
gh auth status
```

A host token being present is a **failure**, not a convenience: it would reach
every repository the user can. If `gh` is logged out, that is expected on a fresh
container — check that it points you at `gh-login`, and if you have a token to
hand, run `gh-login` and re-check with `gh api user --jq .login`.

## 5. Playwright / browser

```bash
claude mcp list | grep playwright
jq '.outputDir, .browser.launchOptions.headless, .browser.launchOptions.args' \
    "$HOME/.claude/playwright-mcp.json"
```

`--no-sandbox` must be among the args (Chrome's sandbox core-dumps in here), and
`outputDir` must point inside the workspace, so screenshots do not land at the top
of the repository.

Then actually drive it: use the playwright MCP tools to open `https://example.com`
and take a screenshot. **[human]** With `headless: false` the window opens on the
host desktop — ask whether they saw it.

## 6. Command-line toolbox

```bash
for t in python3 poetry pyenv node npm git gh jq rg fd tree magick ffmpeg \
         sqlite3 psql shellcheck shfmt fzf just; do
    printf '%-12s %s\n' "$t" "$(command -v "$t" || echo MISSING)"
done
sudo apt-get install -s -qq htop >/dev/null && echo "ok: apt usable without update"
```

ImageMagick 7 uses `magick`; `convert` still works as a legacy alternative.

## 7. Shell

```bash
echo "$HISTFILE"                        # must be under ~/.persist
verify-marker-$$ 2>/dev/null; grep -c "verify-marker" "$HISTFILE"
bind -X 2>/dev/null | grep -q fzf && echo "ok: Ctrl+R is fzf"
complete -p just >/dev/null 2>&1 && echo "ok: just completions"
alias ll
```

The `grep` must find the marker **while this shell is still running**. History is
flushed on every command precisely because a rebuild kills the container before
any shell gets to write its history on exit.

Note these last two need an *interactive* shell: run them in a terminal, not
through a non-interactive `bash -c`.

## 8. Docker — only if enabled

Only when `installDocker` is `on` — with the default (`off`) there is no docker
CLI, and that is a `skipped`, not a failure.

```bash
docker info >/dev/null && echo "ok: nested daemon up"
docker compose version && docker buildx version | head -1
echo "$DOCKER_CONFIG"                   # must NOT be ~/.docker
docker run --rm hello-world             # proves an anonymous pull works
```

`DOCKER_CONFIG` pointing at `~/.docker-cli` is what keeps VS Code's host
credential helper out of the way; in `~/.docker` it breaks every pull with
`error getting credentials - err: exit status 255`.

## 9. Codex — only if enabled

Report `skipped` when `installCodex` is false.

```bash
codex --version
test -s "$HOME/.codex/auth.json" && echo "ok: logged in" || echo "run 'codex login' once"
```

The login is interactive by design and is never automated; the credentials
persist in the `~/.codex` volume.

---

## Reporting

Finish with a short summary: how many `ok`, what failed with the actual output,
what was skipped and why, and which **[human]** items are still open. If
everything passed except items needing a person, say that plainly rather than
calling the container verified.
