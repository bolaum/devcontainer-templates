# Shell init for the dev container — sourced by ~/.bashrc and ~/.zshrc.
# Put your aliases, functions and exports here. Edit this file and open a new
# terminal to pick up the changes (no rebuild needed).

alias ll='ls -alF'
alias la='ls -AFl'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gd='git diff'

# --- template plumbing (you can leave this alone) ---------------------------
# `gh-login` — authenticate gh with a token scoped to this repository only.
[ -f "${_DEVCONTAINER_SHELL_DIR:-}/gh.sh" ] && . "$_DEVCONTAINER_SHELL_DIR/gh.sh"

# Keep the shell history in the persisted volume: ~/.bash_history and
# ~/.zsh_history live in $HOME, which is thrown away on every rebuild.
#
# Pointing HISTFILE at the volume is not enough. A shell only writes its history
# when it exits, and a rebuild kills the container without giving it the chance —
# closing the terminal first does not help either, since that is not a clean exit
# as far as the shell is concerned. So each command is flushed as it is entered.
if [ -d "$HOME/.persist" ]; then
    HISTSIZE=10000
    if [ -n "${ZSH_VERSION:-}" ]; then
        HISTFILE="$HOME/.persist/zsh_history"
        SAVEHIST=10000
        setopt APPEND_HISTORY     # never truncate what other sessions wrote
        setopt INC_APPEND_HISTORY # write on entry, not on exit
    else
        HISTFILE="$HOME/.persist/bash_history"
        HISTFILESIZE=10000
        # Append instead of overwriting, so parallel terminals do not clobber it.
        shopt -s histappend
        # `history -a` on every prompt is bash's equivalent. Appended to whatever
        # PROMPT_COMMAND already holds — VS Code's shell integration uses it too,
        # and overwriting would break the terminal's command decorations.
        case "${PROMPT_COMMAND:-}" in
            *'history -a'*) ;;
            *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
        esac
    fi
fi

# fzf on Ctrl+R: fuzzy search over the (now persisted) history instead of bash's
# one-match-at-a-time reverse search.
#
# The binding is written out here rather than sourced from the package's
# key-bindings script, because that script does not survive in a container image:
# Ubuntu's Docker images set `path-exclude=/usr/share/doc/*` in dpkg, so
# installing fzf gives you the binary and drops its integration files. Newer fzf
# (0.48+) can emit them itself with `fzf --bash`, which Ubuntu 24.04's 0.44 cannot
# — so try that first and fall back to defining the widget by hand.
if command -v fzf >/dev/null 2>&1 && case "$-" in *i*) true ;; *) false ;; esac; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        if fzf --zsh >/dev/null 2>&1; then
            eval "$(fzf --zsh)"
        else
            __fzf_history() {
                local sel
                sel="$(fc -rl 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' |
                    awk '!seen[$0]++' |
                    fzf --height 40% --reverse --tiebreak=index --query "$LBUFFER")" || return 0
                LBUFFER="$sel"
                zle redisplay
            }
            zle -N __fzf_history
            bindkey '^R' __fzf_history
        fi
    else
        if fzf --bash >/dev/null 2>&1; then
            eval "$(fzf --bash)"
        else
            __fzf_history() {
                local sel
                # `history` (not the file) so the current session's commands are
                # searchable too; newest first, duplicates collapsed.
                sel="$(HISTTIMEFORMAT= history |
                    sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | tac |
                    awk '!seen[$0]++' |
                    fzf --height 40% --reverse --tiebreak=index --query "$READLINE_LINE")" || return 0
                READLINE_LINE="$sel"
                READLINE_POINT=${#READLINE_LINE}
            }
            bind -x '"\C-r": __fzf_history'
        fi
    fi
fi

# `just` recipe completion. Generated at shell start rather than vendored: the
# completion script comes from the `just` binary itself, so it reads the
# justfile's recipes at the moment you press Tab — including one added five
# seconds ago — and can never be out of step with the installed version.
#
# Guarded on the binary because `just` is only packaged from Ubuntu 26.04 on (see
# the extra tools layer in the Dockerfile).
if command -v just >/dev/null 2>&1; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        # zsh registers a completion only after compinit has run, and the image
        # does not run it by default. It is idempotent and costs milliseconds, so
        # this calls it unconditionally rather than testing whether a user's own
        # .zshrc got there first.
        autoload -Uz compinit && compinit -u 2>/dev/null
        eval "$(just --completions zsh)"
    elif [ -n "${BASH_VERSION:-}" ]; then
        eval "$(just --completions bash)"
    fi
fi
