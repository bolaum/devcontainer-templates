#!/usr/bin/env bash
# postCreate orchestrator: runs the container's setup steps in order.
# Add new setup steps here rather than chaining them in devcontainer.json.
#
# Order matters in three places:
#   - setup-persist.sh goes FIRST: the persisted volumes must be writable before
#     anything writes to them;
#   - setup-docker.sh goes LATE: it waits for the nested daemon, which the
#     feature's entrypoint starts in the background, so every step before it is
#     free waiting time and the check itself normally returns instantly;
#   - setup-apt.sh goes LAST: refreshing the package lists is the slowest step
#     and the one most at the mercy of slow mirrors, and nothing else here needs
#     it — so everything you are actually waiting for is ready before it starts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STEPS=(
    setup-persist.sh
    setup-claude.sh
    setup-codex.sh
    setup-playwright.sh
    setup-shell.sh
    setup-docker.sh
    setup-apt.sh
)

total=${#STEPS[@]}
step_no=0
for step in "${STEPS[@]}"; do
    step_no=$((step_no + 1))
    printf '\n▶ [%d/%d] %s\n' "$step_no" "$total" "$step"
    bash "$SCRIPT_DIR/$step"
done

printf '\n🎉 postCreate finished — %d steps.\n' "$total"
