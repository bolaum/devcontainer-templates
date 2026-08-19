#!/usr/bin/env bash
# Check that rebuilding this container keeps everything it is supposed to keep.
#
# Run it inside the container, rebuild, run it again. It works out on its own
# which of the two runs it is:
#
#   1. first run    seeds a marker in every persisted volume
#   2. rebuild      VS Code: "Dev Containers: Rebuild Container"
#                   CLI:     devcontainer up --remove-existing-container ...
#   3. second run   reports what survived and what did not
#
# Telling the runs apart needs two markers with different lifetimes:
#   - the state file lives next to this script, i.e. in the workspace, which is
#     a bind mount and survives everything, so the script knows a seed happened
#     at all (in .devcontainer/ rather than the workspace root so it does not
#     litter the project; the .gitignore next to it keeps it out of git);
#   - a session marker lives in /tmp, which belongs to the container, so its
#     absence is what proves the container was really replaced.
# Without the second one, running twice without rebuilding would cheerfully
# report success.
#
# Usage: bash .devcontainer/check-persistence.sh [--reset]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$SCRIPT_DIR/.persistence-check.state"
SESSION="/tmp/.persistence-check-session"
MARKER_NAME=".persistence-check"
# Written to $HOME, which is NOT a volume: it must disappear. Without this
# control a "rebuild" that never happened would pass every other assertion.
CONTROL="$HOME/.persistence-check-control"

# path | what you lose if it does not persist
TARGETS=(
    "$HOME/.claude|Claude sessions, prompt history, file history"
    "$HOME/.config/gh|GitHub token for this repo"
    "$HOME/.codex|Codex login, when installCodex is on"
    "$HOME/.vscode-server|VS Code extensions and server binary"
    "$HOME/.persist|Shell history"
    "$HOME/.npm|npm cache"
    "$HOME/.cache/pip|pip cache"
    "$HOME/.cache/pypoetry|Poetry cache and virtualenvs"
    "$HOME/.pyenv/versions|Pythons built with pyenv"
    "$HOME/.cache/ms-playwright|Chromium (shared across projects)"
)

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m' "$1"; }

# --- facts worth reporting beyond the synthetic markers ---------------------
# Real state the container accumulates; the numbers should never go down.
count_claude_sessions() { find "$HOME/.claude/projects" -name '*.jsonl' 2>/dev/null | wc -l; }
count_extensions()      { find "$HOME/.vscode-server/extensions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l; }
# The redirection is what fails when the file is not there yet, and a redirect
# error is reported by the shell — outside any redirection on `wc` itself — so
# the whole group has to be silenced.
count_history_lines()   { { wc -l <"$HOME/.persist/bash_history"; } 2>/dev/null || echo 0; }
count_pyenv_versions()  { find "$HOME/.pyenv/versions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l; }
gh_account()            { command gh auth status 2>/dev/null | sed -n 's/.*account \([^ ]*\).*/\1/p' | head -1; }

collect_facts() {
    echo "fact_claude_sessions=$(count_claude_sessions)"
    echo "fact_extensions=$(count_extensions)"
    echo "fact_history_lines=$(count_history_lines)"
    echo "fact_pyenv_versions=$(count_pyenv_versions)"
    echo "fact_gh_account=$(gh_account)"
}

get() { sed -n "s/^$1=//p" "$STATE" | head -1; }

# --- phases -----------------------------------------------------------------

do_reset() {
    rm -f "$STATE" "$SESSION" "$CONTROL"
    local entry
    for entry in "${TARGETS[@]}"; do
        rm -f "${entry%%|*}/$MARKER_NAME"
    done
    echo "Reset done — the next run starts a fresh check."
}

do_seed() {
    local nonce entry dir
    nonce="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

    : >"$STATE"
    {
        echo "nonce=$nonce"
        echo "container=$(hostname)"
        echo "seeded_at=$(date -Is)"
        collect_facts
    } >>"$STATE"

    echo
    echo "Seeding markers (run 1 of 2)"
    echo
    for entry in "${TARGETS[@]}"; do
        dir="${entry%%|*}"
        if [ -d "$dir" ] && [ -w "$dir" ]; then
            echo "$nonce" >"$dir/$MARKER_NAME" 2>/dev/null &&
                printf '  %s %s\n' "$(green ok)" "$dir" ||
                printf '  %s %s (could not write)\n' "$(red '!!')" "$dir"
        else
            printf '  %s %s (missing or read-only)\n' "$(red '!!')" "$dir"
        fi
    done

    echo "$nonce" >"$CONTROL"   # must NOT survive
    echo "$nonce" >"$SESSION"   # proves we are still in the same container

    cat <<EOF

Also recorded, to compare afterwards:
  Claude sessions   $(get fact_claude_sessions)
  VS Code ext.      $(get fact_extensions)
  History lines     $(get fact_history_lines)
  pyenv versions    $(get fact_pyenv_versions)
  gh account        $(gh_account || true)$([ -z "$(gh_account)" ] && echo "(not logged in)")

Container: $(hostname)

Next: rebuild the container, then run this script again.
  VS Code   F1 -> "Dev Containers: Rebuild Container"
  CLI       devcontainer up --workspace-folder . --remove-existing-container
EOF
}

do_same_container() {
    cat <<EOF

Nothing to check yet: this is the same container that was seeded
(container $(hostname), seeded at $(get seeded_at)).

Rebuild it and run this script again — that is what the check is about.
Starting over instead? bash .devcontainer/check-persistence.sh --reset
EOF
}

do_verify() {
    local nonce entry dir label got failures=0 warnings=0

    nonce="$(get nonce)"
    echo
    echo "Verifying after rebuild (run 2 of 2)"
    printf '%s\n' "$(dim "container $(get container) -> $(hostname)")"
    echo

    for entry in "${TARGETS[@]}"; do
        dir="${entry%%|*}"
        label="${entry##*|}"
        got="$(cat "$dir/$MARKER_NAME" 2>/dev/null)"

        if [ "$got" = "$nonce" ]; then
            printf '  %s %-28s %s\n' "$(green 'kept ')" "${dir/#$HOME/\~}" "$(dim "$label")"
        elif [ -n "$got" ]; then
            # A marker from an older run: this volume is persisting, but it did
            # not take part in the seed — usually a leftover from a previous check.
            printf '  %s %-28s %s\n' "$(red 'stale')" "${dir/#$HOME/\~}" "marker from an earlier run — use --reset"
            warnings=$((warnings + 1))
        else
            printf '  %s %-28s %s\n' "$(red 'LOST ')" "${dir/#$HOME/\~}" "$label"
            failures=$((failures + 1))
        fi
    done

    echo
    # The control proves the container is actually new. If it survived, the run
    # above proves nothing at all.
    if [ -e "$CONTROL" ]; then
        printf '  %s control file in $HOME survived — this container was NOT rebuilt,\n' "$(red 'BAD  ')"
        printf '        so the results above are meaningless.\n'
        failures=$((failures + 1))
    else
        printf '  %s %s\n' "$(green 'ok   ')" "$(dim 'control file in $HOME is gone, so the container really was replaced')"
    fi

    echo
    echo "Real state, before -> after:"
    compare_fact "Claude sessions" "$(get fact_claude_sessions)" "$(count_claude_sessions)"
    compare_fact "VS Code ext."    "$(get fact_extensions)"      "$(count_extensions)"
    compare_fact "History lines"   "$(get fact_history_lines)"   "$(count_history_lines)"
    compare_fact "pyenv versions"  "$(get fact_pyenv_versions)"  "$(count_pyenv_versions)"

    local gh_before gh_after
    gh_before="$(get fact_gh_account)"
    gh_after="$(gh_account)"
    if [ -z "$gh_before" ]; then
        printf '  %-18s %s\n' "gh account" "$(dim 'was not logged in — nothing to check')"
    elif [ "$gh_before" = "$gh_after" ]; then
        printf '  %-18s %s -> %s  %s\n' "gh account" "$gh_before" "$gh_after" "$(green ok)"
    else
        printf '  %-18s %s -> %s  %s\n' "gh account" "$gh_before" "${gh_after:-(logged out)}" "$(red LOST)"
        failures=$((failures + 1))
    fi

    echo
    if [ "$failures" -gt 0 ]; then
        printf '%s %d problem(s) found. Anything marked LOST is not being persisted;\n' "$(red '✗')" "$failures"
        printf '  check the "mounts" section of .devcontainer/devcontainer.json.\n'
    elif [ "$warnings" -gt 0 ]; then
        printf '%s Everything persisted, but %d stale marker(s) got in the way — rerun with --reset.\n' "$(green '✓')" "$warnings"
    else
        printf '%s Everything survived the rebuild.\n' "$(green '✓')"
    fi

    do_reset >/dev/null
    echo
    [ "$failures" -eq 0 ]
}

# Numbers may grow between the two runs (you kept using the container); they
# must never shrink.
compare_fact() {
    local label="$1" before="$2" after="$3"
    if [ "$after" -ge "$before" ] 2>/dev/null; then
        printf '  %-18s %s -> %s  %s\n' "$label" "$before" "$after" "$(green ok)"
    else
        printf '  %-18s %s -> %s  %s\n' "$label" "$before" "$after" "$(red 'went down')"
    fi
}

# --- entry point ------------------------------------------------------------

case "${1:-}" in
    --reset) do_reset; exit 0 ;;
    -h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [ ! -f "$STATE" ]; then
    do_seed
elif [ -e "$SESSION" ]; then
    do_same_container
else
    do_verify
fi
