#!/usr/bin/env python3
"""Claude Code status line.

Renders three progress bars from the status-line stdin JSON:
  - ctx: context window used  (context_window.*)
  - 5h:  rolling 5-hour rate-limit quota used, with reset countdown
         (rate_limits.five_hour.*)
  - 7d:  weekly quota across all models — the "Current week (all models)"
         bar in /usage — with reset countdown (rate_limits.seven_day.*)

All numbers come straight from Claude Code — the quota bars are the actual
credit consumed (not elapsed time), and their countdowns derive from
`resets_at`. The rate-limit block is absent for non-subscribers and until the
first API response of a session, in which case those bars are omitted.
"""
import json
import sys
import time

BAR_WIDTH = 10
RESET = "\033[0m"
DIM = "\033[2m"


def color(pct):
    """Green < 60% < yellow < 85% < red."""
    if pct < 0.60:
        return "\033[32m"
    if pct < 0.85:
        return "\033[33m"
    return "\033[31m"


def bar(pct, label, suffix=""):
    pct = max(0.0, min(1.0, pct))
    filled = int(round(pct * BAR_WIDTH))
    c = color(pct)
    body = c + "█" * filled + RESET + DIM + "░" * (BAR_WIDTH - filled) + RESET
    return f"{DIM}{label}{RESET} {body} {c}{pct * 100:3.0f}%{RESET}{suffix}"


def context_fraction(data):
    cw = data.get("context_window") or {}
    size = cw.get("context_window_size") or 0
    cu = cw.get("current_usage") or {}
    used = (cu.get("input_tokens", 0)
            + cu.get("cache_creation_input_tokens", 0)
            + cu.get("cache_read_input_tokens", 0))
    if size and used:
        return used / size
    return (cw.get("used_percentage") or 0) / 100.0


def fmt_countdown(secs):
    """Coarse countdown: days once the window is longer than a day."""
    secs = max(0, int(secs))
    d, h, m = secs // 86400, (secs % 86400) // 3600, (secs % 3600) // 60
    if d:
        return f"{d}d{h:02d}h"
    return f"{h}h{m:02d}m" if h else f"{m}m"


def quota_bar(limits, key, label):
    """One rate-limit bar, or None when Claude Code did not report that window."""
    window = limits.get(key) or {}
    if not window:
        return None
    pct = (window.get("used_percentage") or 0) / 100.0
    suffix = ""
    resets_at = window.get("resets_at")
    if resets_at:
        suffix = f" {DIM}({fmt_countdown(resets_at - time.time())} left){RESET}"
    return bar(pct, label, suffix)


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        data = {}

    model = data.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or "Claude"

    parts = [f"\033[1m{model_name}{RESET}", bar(context_fraction(data), "ctx")]

    limits = data.get("rate_limits") or {}
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        rendered = quota_bar(limits, key, label)
        if rendered:
            parts.append(rendered)

    cost = (data.get("cost") or {}).get("total_cost_usd")
    if cost:
        parts.append(f"{DIM}${cost:.2f}{RESET}")

    print("  ".join(parts))


if __name__ == "__main__":
    main()
