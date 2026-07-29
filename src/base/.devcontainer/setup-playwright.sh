#!/usr/bin/env bash
# Install Playwright + Chromium and expose it to Claude as an MCP server, so it
# can actually browse pages instead of only writing browser scripts.
#
# This runs in postCreate and not in the Dockerfile because Node comes from a
# devcontainer feature, which is only installed after the image is built.
# The browsers land in a named volume (see "mounts"), so the download is paid
# once per machine rather than once per project.
set -euo pipefail

if [ "${INSTALL_PLAYWRIGHT:-true}" != "true" ]; then
    echo "⏭️  Playwright skipped (installPlaywright=false)"
    exit 0
fi

BROWSERS_DIR="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
CONFIG_FILE="$HOME/.claude/playwright-mcp.json"
HEADLESS="${PLAYWRIGHT_HEADLESS:-false}"

# A fresh named volume is mounted root-owned; without this the install cannot
# write into it.
if [ -d "$BROWSERS_DIR" ] && [ ! -w "$BROWSERS_DIR" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$BROWSERS_DIR"
fi
mkdir -p "$BROWSERS_DIR"

# Both packages at latest so the MCP server and the installed browser build match.
npm install -g playwright@latest @playwright/mcp@latest

# Chromium's system libraries are already baked into the image (see Dockerfile);
# this is a cheap no-op that self-heals if Playwright ever adds a dependency.
playwright install-deps chromium

# The browser itself, cached in the shared volume.
playwright install chromium

# Browser flags:
#   --no-sandbox           Chrome's sandbox needs privileges the container does
#                          not have; without it the browser aborts with a core dump.
#   --disable-dev-shm-usage  Docker's default /dev/shm is 64 MB, too small for Chromium.
#   --ozone-platform=wayland (headed only) render on the host's compositor through
#                          the Wayland socket bind-mounted in devcontainer.json, so
#                          you can watch Claude drive the browser.
if [ "$HEADLESS" = "true" ]; then
    browser_args='"--no-sandbox", "--disable-dev-shm-usage"'
else
    browser_args='"--no-sandbox", "--disable-dev-shm-usage", "--ozone-platform=wayland", "--enable-features=UseOzonePlatform"'
fi

cat > "$CONFIG_FILE" <<EOF
{
  "browser": {
    "browserName": "chromium",
    "launchOptions": {
      "headless": $HEADLESS,
      "args": [$browser_args]
    },
    "contextOptions": {
      "viewport": { "width": 1280, "height": 820 }
    }
  }
}
EOF

# Register the MCP server for the container user. Re-running is fine: the old
# entry is dropped first so the command never fails on "already exists".
claude mcp remove -s user playwright >/dev/null 2>&1 || true
claude mcp add -s user playwright -- playwright-mcp --config "$CONFIG_FILE"

if [ "$HEADLESS" = "true" ]; then
    echo "✅ Playwright ready: Chromium (headless) and the 'playwright' MCP server registered"
else
    echo "✅ Playwright ready: Chromium opens on your desktop via Wayland; MCP server registered"
fi
