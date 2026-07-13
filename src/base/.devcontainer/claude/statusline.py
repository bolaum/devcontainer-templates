#!/usr/bin/env python3
"""Claude Code status line.

Renders two progress bars from the status-line stdin JSON:
  - ctx: context window used  (context_window.*)
  - 5h:  rolling 5-hour rate-limit quota used, with reset countdown
         (rate_limits.five_hour.*)

Both numbers come straight from Claude Code — the 5h bar is the actual quota
consumed (not elapsed time), and its countdown is derived from `resets_at`.
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
    secs = max(0, int(secs))
    h, m = secs // 3600, (secs % 3600) // 60
    return f"{h}h{m:02d}m" if h else f"{m}m"


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        data = {}

    model = data.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or "Claude"

    parts = [f"\033[1m{model_name}{RESET}", bar(context_fraction(data), "ctx")]

    five = (data.get("rate_limits") or {}).get("five_hour") or {}
    if five:
        pct = (five.get("used_percentage") or 0) / 100.0
        suffix = ""
        resets_at = five.get("resets_at")
        if resets_at:
            suffix = f" {DIM}({fmt_countdown(resets_at - time.time())} left){RESET}"
        parts.append(bar(pct, "5h", suffix))

    cost = (data.get("cost") or {}).get("total_cost_usd")
    if cost:
        parts.append(f"{DIM}${cost:.2f}{RESET}")

    print("  ".join(parts))


if __name__ == "__main__":
    main()
