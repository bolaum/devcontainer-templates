# Verifying this dev container

A checklist for an agent (or a person) to confirm the container is fully wired.
Run it from **inside** the container, from the workspace root.

    Read .devcontainer/VERIFY.md and work through it.

Report one line per item: `ok`, `FAIL` with the command's actual output, or
`skipped` with the reason. Do not repair anything while checking — finish the
sweep first, then propose fixes. Never report an item as `ok` without having run
its command, and never soften a failure into a warning.

Some items cannot be settled from a shell and are marked **[human]**. Do NOT stop
and ask when you reach one: run its command, keep the output, and carry on. They
are all put to the person together at the end, as multiple choice — see
"What only you can confirm".

---

## 1. Claude Code

```bash
claude --version
command -v claude                      # must be $HOME/.local/bin/claude
test -w "$HOME/.local/share/claude" && echo "ok: install dir writable (self-update)"
python3 -c 'import json,os;d=json.load(open(os.path.expanduser("~/.claude.json")));print(d.get("hasCompletedOnboarding"), d.get("installMethod"))'
```

Expected: the CLI is under `$HOME` (not a root-owned global npm install), and the
last line prints `True native` — onboarding pre-answered *and* the installer's own
metadata still there, which is what proves `setup-claude.sh` merged into that file
instead of overwriting it.

```bash
jq '.language, .voice' "$HOME/.claude/settings.json"
test -f "$HOME/.claude/statusline.py" && echo "ok: statusline present"
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
for d in ~/.claude ~/.codex ~/.ssh ~/.config/gh ~/.vscode-server ~/.persist ~/.npm \
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
timeout 8 rec -q -r 16000 -c 1 /tmp/verify-mic.wav trim 0 3 && ls -l /tmp/verify-mic.wav
wl-paste --list-types || echo "clipboard empty or unavailable"
```

**[human]** A non-empty file proves the *input* path exists; whether it captured
real sound is question 1 at the end. Keep the recording rather than deleting it —
you will play it back then. Clipboard contents are question 3.

Output is a separate path and is not covered by the recording above — test it too:

```bash
play -qn synth 1 sine 440 vol 0.4
```

**[human]** A one-second tone should come out of the host's speakers — question 2
at the end. A zero exit status only means the container reached PulseAudio; it says
nothing about whether a sound was produced.

## 4. GitHub access

Two separate mechanisms, on purpose — git signs through the forwarded agent, and
`gh` uses a token scoped to one repository.

```bash
ssh-add -l                              # keys live on the host; this lists them
ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | head -1
[ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && echo "ok: no host token inherited"
gh auth status
```

`ssh -T` succeeds when the reply says "successfully authenticated". The
`accept-new` is there because `known_hosts` may not be populated yet, and what
populates it depends on how the container was started — measured, not assumed:

- **plain `devcontainer up`**: nothing creates `~/.ssh/known_hosts` at all, so
  without the flag the check fails with "Host key verification failed" every time;
- **VS Code**: the Dev Containers extension copies the *host's* whole file in
  shortly after start (here, byte-identical, ~0.4 s in), and only when it is
  absent. Run the checklist inside that window and you get the same failure;
- the file is in neither case part of the image.

Either way it is a timing or transport problem, not an auth problem, and
`accept-new` trusts the key on first use. `~/.ssh` is a persisted volume and the
extension only copies when the file is absent, so once accepted it stays accepted
across rebuilds. Drop the flag and seed `known_hosts`
yourself if you would rather not trust on first use.

A side effect worth being aware of rather than alarmed by: on the VS Code path
your host's entire SSH history — every host in `known_hosts`, hashed or not — ends
up inside the container. No private key crosses; the agent still signs on the
host.

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

Caveat worth knowing before you trust it: `outputDir` only catches files the
server names itself. A screenshot taken with an explicit *relative* `filename` is
resolved against the server's working directory — the repo root — and lands there
regardless.

What actually bounds the damage is the server's allowed roots, which are
`outputDir` and the workspace: an absolute path outside them is refused with
`outside allowed roots: <repo>/.playwright-mcp, <repo>`. So pass no filename at
all, or an absolute path inside `outputDir` — an absolute path elsewhere is
rejected, and a relative one quietly lands in the repo root.

Then actually drive it: use the playwright MCP tools to open `https://example.com`
and take a screenshot. **[human]** With `headless: false` the window opens on the
host desktop — that is question 4 at the end.

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

Everything here needs an **interactive** shell, so run it as one block. `HISTFILE`
and the aliases come from `~/.bashrc`, which a non-interactive shell never reads —
outside this block `$HISTFILE` is simply empty.

```bash
bash -i <<'EOF'
echo "$HISTFILE"
alias ll
verify-marker-$$
grep -c verify-marker "$HISTFILE"
bind -X 2>/dev/null | grep -q fzf && echo "ok: Ctrl+R is fzf"
complete -p just >/dev/null 2>&1 && echo "ok: just completions"
exit
EOF
```

`HISTFILE` must be under `~/.persist`, and the count must be **at least 1** — the
marker is found while that shell is still running, which is the whole point:
history is flushed on every command (`history -a` in `PROMPT_COMMAND`) because a
rebuild kills the container before any shell gets to write its history on exit.

Two things that will mislead you here:

- **The count is not 1.** The `grep` line itself is appended to history before the
  next prompt, so every run of this block adds two more matches — 1, then 3, then
  5. Assert `>= 1`, never equality. And do not try to tighten it by grepping the
  expanded PID: history stores the line as typed, `verify-marker-$$`, so that
  returns 0.
- **Do not use `bash -ic '...'`.** Bash records history for commands it reads from
  its *input*; with `-c` the command comes from the argument instead, so it never
  enters the history list and the grep returns 0 — or errors, on a fresh container
  where the file does not exist yet. That is a false negative on a container that
  is working perfectly. The dividing line is `-c` versus stdin, not whether there
  is a terminal: the heredoc above has no pty and works fine.

## 8. Docker — only if enabled

`installDocker` leaves no variable behind, so the only signal from in here is
whether the CLI exists. Check first, and report `skipped` — not a failure — when
it does not:

```bash
command -v docker >/dev/null || echo "skipped: installDocker is off"
```

The rest only when that found something:

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

`INSTALL_CODEX` carries the option: `true` is on, and **empty** is off — an applied
`devcontainer.json` holds `""` rather than `"false"`, because the CLI substitutes a
falsy option value as an empty string. Decide before running anything, so a missing
binary does not come back as exit 127:

```bash
[ "${INSTALL_CODEX:-}" = "true" ] || echo "skipped: installCodex is off"
```

Only when it is on:

```bash
codex --version
test -s "$HOME/.codex/auth.json" && echo "ok: logged in" || echo "run 'codex login' once"
```

The login is interactive by design and is never automated; the credentials
persist in the `~/.codex` volume.

## 10. GPU — only if passed through

The tooling passes an NVIDIA GPU only when the host's `docker info` lists an
`nvidia` runtime (`hostRequirements.gpu` is `optional`). `nvidia-smi` is injected
with the driver, so its absence means `skipped`, not a failure:

```bash
command -v nvidia-smi >/dev/null || echo "skipped: no NVIDIA gpu passed through"
```

Only when it is there:

```bash
nvidia-smi -L
ls -l /dev/dri/ /dev/nvidia*           # must be rw for you (postStartCommand)
echo "$GBM_BACKENDS_PATH"; ls /usr/lib64/gbm/ /usr/lib/x86_64-linux-gnu/gbm/ 2>/dev/null
```

Then open `chrome://gpu` with the playwright MCP tools and read **`GL_RENDERER`**
— it must name the NVIDIA card. Do not settle for the "Graphics Feature Status"
list: it says "Hardware accelerated" even when EGL fell back to `llvmpipe`, which
is software. Video decode stays in software on NVIDIA (Chromium skips it for
VA-API); that is expected, not a failure.

---

## What only you can confirm

Ask these **after** the sweep, all at once, as multiple-choice questions — one
question per item, with the options given. Never guess an answer, and never mark a
`[human]` item `ok` because its command exited zero: exit status here only proves
the container reached the host, not that anything was seen or heard.

Two of them need a prop first, so set that up before asking:

```bash
play -q /tmp/verify-mic.wav          # question 1: play back what was recorded
rm -f /tmp/verify-mic.wav
```

For question 3, ask the person to copy an image on the host, then run
`wl-paste --list-types` again and expect `image/png` among the types.

**1. Microphone.** "I recorded three seconds from the host microphone and played
it back. What happened?"
- I heard the sound that was in the room → `ok`
- Playback ran but was silent → `FAIL`, the bridge is up but nothing is captured
- I heard nothing at all, not even playback → answer question 2 first, this may be output
- I was not at the machine → `unverified`

**2. Speakers.** "Did a one-second tone play on the host?"
- Yes → `ok`
- No, silence → `FAIL`, output path
- There is no audio on this host → `skipped`

**3. Clipboard.** "You copied an image on the host — did `wl-paste` list
`image/png`?"
- Yes → `ok`
- It listed only text types → `FAIL`, the Wayland socket is reaching the wrong session
- Nothing was listed / error → `FAIL`, no clipboard bridge
- I did not copy anything → `unverified`

**4. Browser window.** "A Chromium window should have opened on your desktop and
navigated to example.com. Did you see it?"
- Yes → `ok`
- No window, but the screenshot came back → `FAIL` for headed mode only; the
  browser works, it is not reaching the compositor
- Neither → `FAIL`
- This container runs `headless: true`, or the host has no desktop → `skipped`

---

## Reporting

Finish with a short summary: how many `ok`, what failed with the actual output,
what was skipped and why, and how each of the four questions above was answered.
An item left `unverified` because the person was not there is not a pass — say so
plainly rather than calling the container verified.
