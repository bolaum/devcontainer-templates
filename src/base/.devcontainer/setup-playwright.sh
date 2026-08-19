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
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A fresh named volume is mounted root-owned; without this the install cannot
# write into it.
if [ -d "$BROWSERS_DIR" ] && [ ! -w "$BROWSERS_DIR" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$BROWSERS_DIR"
fi
mkdir -p "$BROWSERS_DIR"

# The MCP server decides which Playwright version everything else uses.
#
# @playwright/mcp pins an *alpha* Playwright build (0.0.78 -> 1.62.0-alpha-…),
# and that build expects a different Chromium revision than the stable release
# (chromium-1232 vs chromium-1234). Installing playwright@latest next to it
# downloads the wrong revision: postCreate succeeds, then the very first
# browser_navigate fails with `Browser "chromium" is not installed`, and the
# volume ends up holding both revisions (~1.3 GB). Reading the pin from the MCP
# package keeps a single revision shared by the server and your own scripts, and
# survives future MCP bumps.
mcp_playwright_version="$(npm view @playwright/mcp@latest dependencies.playwright 2>/dev/null || true)"
if [ -z "$mcp_playwright_version" ]; then
    echo "⚠️  could not read the playwright version pinned by @playwright/mcp; using latest"
    mcp_playwright_version="latest"
fi

echo "⏳ Installing playwright@$mcp_playwright_version and @playwright/mcp (npm)..."
npm install -g "playwright@$mcp_playwright_version" @playwright/mcp@latest

# The browser itself, cached in the shared volume — already there on every
# container after the first one on this machine.
echo "⏳ Fetching Chromium (cached in the shared volume after the first time)..."
playwright install chromium

# Chromium's system libraries are already baked into the image (see Dockerfile).
# `playwright install-deps` would confirm that, but it runs a full `apt-get
# update` first — the slowest step of postCreate, paid on every container even
# though it almost never has anything to do. Ask the binary instead, and only
# self-heal when a library really is missing.
chrome_bin="$(find "$HOME/.cache/ms-playwright" -type f -name chrome -print -quit 2>/dev/null)"
if [ -n "$chrome_bin" ] && ldd "$chrome_bin" 2>/dev/null | grep -q 'not found'; then
    echo "⏳ Chromium is missing system libraries, installing them..."
    playwright install-deps chromium
fi

# Fail here, at create time, rather than at Claude's first navigation: resolve
# playwright-core the way the MCP server does and check that the Chromium build
# it points at is really on disk.
node -e 'const {createRequire}=require("module"); const fs=require("fs");
const req=createRequire(process.argv[1]+"/@playwright/mcp/");
const p=req("playwright-core").chromium.executablePath();
if(!fs.existsSync(p)){console.error("Chromium build expected by @playwright/mcp is missing: "+p);process.exit(1);}
console.log("   browser for the MCP server: "+p);' "$(npm root -g)"

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

# Written only when absent, so hand edits (a different viewport, extra browser
# flags, another output directory) survive every rebuild. Delete the file to get
# these defaults back.
#
# outputDir keeps screenshots and page snapshots out of the project root: with no
# setting the server resolves them against its own working directory, which is
# wherever Claude was started — which in practice means image files appearing at
# the top of the repository. Add .playwright-mcp/ to the project's .gitignore.
# Caveat: only a *default* filename lands there. An explicit relative `filename`
# is still resolved against the working directory, so pass an absolute path or no
# filename at all.
if [ -e "$CONFIG_FILE" ]; then
    echo "   keeping the existing MCP config: $CONFIG_FILE (delete it to regenerate)"
else
    cat > "$CONFIG_FILE" <<EOF
{
  "outputDir": "$WORKSPACE_DIR/.playwright-mcp",
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
fi

# Register the MCP server for the container user. Re-running is fine: the old
# entry is dropped first so the command never fails on "already exists".
claude mcp remove -s user playwright >/dev/null 2>&1 || true
claude mcp add -s user playwright -- playwright-mcp --config "$CONFIG_FILE"

if [ "$HEADLESS" = "true" ]; then
    echo "✅ Playwright ready: Chromium (headless) and the 'playwright' MCP server registered"
else
    echo "✅ Playwright ready: Chromium opens on your desktop via Wayland; MCP server registered"
fi
