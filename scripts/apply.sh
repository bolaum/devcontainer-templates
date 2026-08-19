#!/usr/bin/env bash
# Apply a LOCAL template to a target project folder.
#
# The devcontainer CLI's `templates apply -t` only accepts an OCI reference (a
# published template), not a local path. This script fills that gap for local
# iteration: it prompts for each option, substitutes ${templateOption:*}, and
# copies the template files into the target folder.
#
# Usage:
#   scripts/apply.sh <template-id> <target-dir> [--defaults]
#
# Examples:
#   scripts/apply.sh base ~/projects/my-new-project        # prompt for each option
#   scripts/apply.sh base .                                # apply into the current directory
#   scripts/apply.sh base ~/projects/my-new-project --defaults   # use defaults, no prompts
set -euo pipefail

# Resolve the repo (for reading the template) without changing the working
# directory, so a relative <target-dir> stays relative to where you ran this.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "usage: scripts/apply.sh <template-id> <target-dir> [--defaults]" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }

id=""; target=""; use_defaults=0
for arg in "$@"; do
    case "$arg" in
        --defaults|-y) use_defaults=1 ;;
        -*) echo "error: unknown option '$arg'" >&2; usage ;;
        *)
            if [ -z "$id" ]; then id="$arg"
            elif [ -z "$target" ]; then target="$arg"
            else usage
            fi ;;
    esac
done
[ -n "$id" ] && [ -n "$target" ] || usage

tmpl_dir="$REPO_ROOT/src/${id}"
meta="$tmpl_dir/devcontainer-template.json"
[ -f "$meta" ] || { echo "error: template '$id' not found ($meta)" >&2; exit 1; }

# Resolve the target relative to the current directory, then make it absolute.
mkdir -p "$target"
target="$(cd "$target" && pwd)"
echo "Applying template '$id' to: $target" >&2

# Build a sed script mapping each ${templateOption:opt} to the chosen value.
sed_script="$(mktemp)"
trap 'rm -f "$sed_script"' EXIT

if [ "$(jq -r '.options // empty' "$meta")" != "" ]; then
    while IFS= read -r opt; do
        # `has("default")` rather than `.default // ""`: jq's alternative
        # operator also fires on `false`, which turned every boolean option
        # defaulting to false into an empty string.
        default="$(jq -r ".options.${opt} | if has(\"default\") then .default else \"\" end" "$meta")"
        desc="$(jq -r ".options.${opt}.description // \"\"" "$meta")"
        proposals="$(jq -r "(.options.${opt}.proposals // .options.${opt}.enum // []) | join(\", \")" "$meta")"
        value="$default"
        if [ "$use_defaults" = "0" ]; then
            [ -n "$desc" ] && echo "# $desc" >&2
            field_prompt="$opt"
            [ -n "$proposals" ] && field_prompt="$field_prompt ($proposals)"
            read -r -p "$field_prompt [$default]: " answer < /dev/tty || answer=""
            [ -n "$answer" ] && value="$answer"
        fi
        # Reject a bad value here rather than substituting it. Neither the
        # official CLI's `-a` nor the VS Code prompt validates anything, and a
        # wrong value does not fail at apply time — it lands in devcontainer.json
        # and blows up much later, in a message that points at the symptom rather
        # than at the answer you typed. `installDocker` is the cautionary tale:
        # anything other than true/false there selects a feature directory that
        # does not exist.
        otype="$(jq -r ".options.${opt}.type // \"string\"" "$meta")"
        allowed=""
        case "$otype" in
            boolean) allowed="$(printf 'true\nfalse')" ;;
            *) allowed="$(jq -r "(.options.${opt}.enum // []) | .[]" "$meta")" ;;
        esac
        if [ -n "$allowed" ] && ! printf '%s\n' "$allowed" | grep -qxF "$value"; then
            echo "error: '${value}' is not a valid value for '${opt}' (type ${otype})." >&2
            echo "       choose one of: $(printf '%s' "$allowed" | paste -sd', ')" >&2
            exit 1
        fi
        esc="$(printf '%s' "$value" | sed -e 's/[]\/$*.^[&]/\\&/g')"
        printf 's/\\${templateOption:%s}/%s/g\n' "$opt" "$esc" >> "$sed_script"
        echo "  -> ${opt} = ${value}" >&2
    done < <(jq -r '.options | keys[]' "$meta")
fi

# Copy template files (all but the metadata/docs) into the target, substituting options.
while IFS= read -r -d '' f; do
    rel="${f#"$tmpl_dir"/}"
    case "$rel" in
        devcontainer-template.json | README.md | NOTES.md) continue ;;
    esac
    dest="$target/$rel"
    mkdir -p "$(dirname "$dest")"
    sed -f "$sed_script" "$f" > "$dest"
    [ -x "$f" ] && chmod +x "$dest"
done < <(find "$tmpl_dir" -type f -print0)

echo "✅ applied template '$id' to '$target'."
echo "   Open it in VS Code → 'Reopen in Container' (or: devcontainer up --workspace-folder '$target')."
