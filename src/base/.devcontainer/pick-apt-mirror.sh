#!/usr/bin/env bash
# Point apt at the fastest mirror reachable from this machine, at image build
# time and before any apt layer runs.
#
# Why this exists: the default archive.ubuntu.com is not fast everywhere, and on
# some networks it is effectively unreachable — on one machine it timed out
# entirely while that country's mirrors served 6-9 MB/s, turning a 40 MB install
# into a 4-minute layer. Every apt layer in the Dockerfile pays that difference.
#
# The default mirror competes in the benchmark like any other candidate, and it
# has to be beaten by a clear margin to be replaced. Where the default is
# already the best choice — plenty of networks, and CI runners in particular —
# nothing changes.
#
# Not `apt-select` or `netselect`: installing either needs a working apt, which
# is exactly what is slow. Everything here uses curl, already in the base image.
#
# The argument comes from the aptMirror template option:
#   auto     benchmark the official mirrors for the detected country and use
#            the fastest one
#   keep     leave the image's sources untouched
#   <CC>     two-letter country code (e.g. BR) — skip country detection
#   <URL>    use this mirror as-is, no benchmarking
#
# Every failure path leaves the image default in place: a slow mirror is an
# annoyance, a broken build is not. This never exits non-zero.
set -uo pipefail

MODE="${1:-auto}"

# ---------------------------------------------------------------------------

log() { echo "apt mirror: $*"; }

# Rewrite the URIs pointing at $2 to $1, in whichever format this release uses
# (deb822 on 24.04, one-line sources.list on 22.04).
apply_mirror() {
    local url="${1%/}/" host_re="$2" deb822=/etc/apt/sources.list.d/ubuntu.sources
    local applied=0

    if [ -f "$deb822" ]; then
        sed -i -E "s|^([[:space:]]*URIs:[[:space:]]*)https?://[^[:space:]]*${host_re}/ubuntu/?|\1$url|" "$deb822" && applied=1
    fi
    if [ -f /etc/apt/sources.list ]; then
        sed -i -E "s|https?://[^[:space:]]*${host_re}/ubuntu/?|$url|g" /etc/apt/sources.list && applied=1
    fi

    [ "$applied" = "1" ]
}

apply_archive_mirror() { apply_mirror "$1" 'archive\.ubuntu\.com'; }
apply_security_mirror() { apply_mirror "$1" 'security\.ubuntu\.com'; }

# Download a real index file and report bytes/s. 0 means unusable.
measure_speed() {
    local url="${1%/}" suite="$2" speed
    speed="$(curl -sS -o /dev/null -m 8 -w '%{speed_download}' \
        "$url/dists/$suite/main/binary-amd64/Packages.gz" 2>/dev/null)" || speed=0
    printf '%s' "${speed%%.*}"
}

# Same, formatted for the parallel benchmark below (sortable, carries the URL).
measure() {
    printf '%s %s\n' "$(measure_speed "$1" "$2")" "${1%/}"
}

# The security pocket lives on its own host, and it is the one the distribution
# publishes fixes to *first* — mirrors sync afterwards. So it is only moved when
# the official host is genuinely worse: on a network where security.ubuntu.com is
# unreachable, "updates a bit late" beats "no updates at all".
maybe_switch_security() {
    local mirror="$1" codename="$2"
    local official="http://security.ubuntu.com/ubuntu"
    local suite="${codename}-security"
    local mirror_speed official_speed

    # In parallel: when the official host is the unreachable one, measuring the
    # two in sequence means sitting through its whole timeout for nothing.
    local tmp_mirror tmp_official
    tmp_mirror="$(mktemp)"
    tmp_official="$(mktemp)"
    measure_speed "$mirror" "$suite" >"$tmp_mirror" &
    measure_speed "$official" "$suite" >"$tmp_official" &
    wait
    mirror_speed="$(cat "$tmp_mirror")"
    official_speed="$(cat "$tmp_official")"
    rm -f "$tmp_mirror" "$tmp_official"
    mirror_speed="${mirror_speed:-0}"
    official_speed="${official_speed:-0}"

    if [ "$mirror_speed" -eq 0 ]; then
        log "security: mirror does not carry $suite; keeping $official"
        return
    fi
    if [ "$mirror_speed" -lt $((official_speed * 3 / 2)) ]; then
        log "security: official host is competitive ($((official_speed / 1024)) KB/s); keeping it"
        return
    fi
    if apply_security_mirror "$mirror"; then
        log "security: using $mirror ($((mirror_speed / 1024)) KB/s vs $((official_speed / 1024)) KB/s official)"
    else
        log "security: could not rewrite the sources; keeping $official"
    fi
}

# ---------------------------------------------------------------------------

case "$MODE" in
    keep | '')
        log "keeping the image default"
        exit 0
        ;;
esac

codename="$( . /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}" )"
if [ -z "$codename" ]; then
    log "could not read the Ubuntu codename; keeping the image default"
    exit 0
fi

# An explicit URL is used as given — no benchmarking, the choice was made for us.
# The security pocket still has to be checked: not every mirror carries it.
case "$MODE" in
    http://* | https://*)
        if apply_archive_mirror "$MODE"; then
            log "set to $MODE"
            maybe_switch_security "$MODE" "$codename"
        else
            log "could not rewrite the sources; keeping the image default"
        fi
        exit 0
        ;;
esac

DEFAULT_MIRROR="http://archive.ubuntu.com/ubuntu"

if [ "$MODE" = "auto" ]; then
    # Two providers: this runs inside a build, where one flaky endpoint should
    # not silently cost everyone the optimisation.
    for svc in https://ipinfo.io/country https://ifconfig.co/country-iso; do
        country="$(curl -sS -m 8 "$svc" 2>/dev/null | tr -d '[:space:]')"
        printf '%s' "$country" | grep -qE '^[A-Za-z]{2}$' && break
        country=""
    done
    if [ -z "$country" ]; then
        log "could not detect the country; keeping the image default"
        exit 0
    fi
    log "detected country: $country"
else
    country="$MODE"
fi

country="$(printf '%s' "$country" | tr '[:lower:]' '[:upper:]')"
mirrors="$(curl -sS -m 10 "http://mirrors.ubuntu.com/${country}.txt" 2>/dev/null |
    grep -E '^https?://' | grep -v 'archive\.ubuntu\.com' | head -12)"

if [ -z "$mirrors" ]; then
    log "no mirror list for $country; keeping the image default"
    exit 0
fi

log "benchmarking $(printf '%s\n' "$mirrors" | wc -l) mirror(s) for $country against the default..."

# In parallel: a dozen mirrors measured one by one at an 8s timeout could cost
# more than the whole optimisation saves. Together they cost one timeout.
results="$(mktemp)"
while IFS= read -r m; do
    [ -n "$m" ] && measure "$m" "$codename" >>"$results" &
done <<<"$mirrors"
measure "$DEFAULT_MIRROR" "$codename" >>"$results" &
wait

best_line="$(sort -rn "$results" | head -1)"
best_speed="${best_line%% *}"
best_url="${best_line#* }"
default_speed="$(awk -v u="$DEFAULT_MIRROR" '$2 == u {print $1; exit}' "$results")"
rm -f "$results"
default_speed="${default_speed:-0}"

if [ -z "$best_url" ] || [ "${best_speed:-0}" -eq 0 ]; then
    log "no mirror responded; keeping the image default"
    exit 0
fi

# Only switch for a clear win. Measurements taken once, in parallel, over a few
# seconds are noisy; swapping the well-maintained default for a random mirror
# that happened to look 10% better is not worth it.
if [ "$best_url" = "$DEFAULT_MIRROR" ] ||
    [ "$best_speed" -lt $((default_speed * 3 / 2)) ]; then
    log "default is already competitive ($((default_speed / 1024)) KB/s); keeping it"
    exit 0
fi

if apply_archive_mirror "$best_url"; then
    log "using $best_url ($((best_speed / 1024)) KB/s vs $((default_speed / 1024)) KB/s default)"
    maybe_switch_security "$best_url" "$codename"
else
    log "could not rewrite the sources; keeping the image default"
fi

exit 0
