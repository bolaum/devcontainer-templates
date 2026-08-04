# GitHub authentication helpers — sourced by rc.sh.
#
# This container inherits NO GitHub credential from the host, on purpose. The
# host's token lives in the desktop keyring and reaches every repository you can;
# anything running in here (a dependency's install script, an agent with broad
# permissions) could read it. So each project authenticates with its own
# fine-grained token, scoped to that repository alone and revocable on its own.
#
# The token is stored in ~/.config/gh, which is a named volume scoped to this
# project: it survives rebuilds, never touches the host's ~/.config/gh, and stays
# out of $HOME where backups and sync tools would pick it up.
#
# Git needs none of this. Cloning, fetching and pushing go over ssh through the
# forwarded agent, which signs on the host. The token is exclusively for what
# talks to the GitHub API: gh pr, gh issue, gh release, gh api.

# Print the setup walkthrough, with this repository already filled in.
gh-login-help() {
    local repo name
    repo="$(command git config --get remote.origin.url 2>/dev/null |
        sed -E 's#^(git@|ssh://git@|https://)github\.com[:/]+##; s#\.git$##')"
    if [ -n "$repo" ]; then
        # Letters, digits and dashes only — a name you can paste without
        # wondering whether some character will be rejected.
        name="devcontainer-$(printf '%s' "$repo" | tr -c 'A-Za-z0-9' '-')"
    else
        # No remote yet (brand new project, or not a git repo): placeholders keep
        # the walkthrough readable instead of failing.
        repo="<owner>/<repo>"
        name="devcontainer"
    fi

    cat >&2 <<EOF

This container has no GitHub credentials — by design.

Git already works: it pushes over ssh through the forwarded agent. The token
below is only for the commands that call the GitHub API.

Create one that can reach ONLY this repository:

  1. Open  https://github.com/settings/personal-access-tokens/new
  2. Token name:  $name
  3. Repository access -> Only select repositories -> $repo
  4. Repository permissions (grant just what you need):
       Metadata        Read-only        mandatory, added for you
       Pull requests   Read and write   gh pr ...
       Issues          Read and write   gh issue ...
       Contents        Read and write   gh release ..., gh api on files
  5. Expiration: the shortest that gets you through the work

Then run:  gh-login

EOF
}

# Ask for the token and hand it to gh. Read from the terminal with echo off, so
# it never lands in the shell history nor in a process listing.
gh-login() {
    local token
    gh-login-help
    printf 'Paste the token (input is hidden): ' >&2
    IFS= read -rs token </dev/tty || return 1
    printf '\n' >&2
    if [ -z "$token" ]; then
        echo "gh-login: no token given, nothing done." >&2
        return 1
    fi

    printf '%s' "$token" | command gh auth login --with-token || return 1
    unset token
    # No `gh auth setup-git` on purpose: git is covered by the forwarded ssh
    # agent, so registering a credential helper would only add a second, weaker
    # path to the same thing.
    command gh auth status
}

# Wrap gh only to nudge on failure: run the real command, and if it failed
# *because* there is no auth, point at gh-login. Checking auth up front would
# cost a network round-trip on every single invocation.
gh() {
    command gh "$@"
    local rc=$?
    if [ "$rc" -ne 0 ] && ! command gh auth status >/dev/null 2>&1; then
        gh-login-help
    fi
    return "$rc"
}
