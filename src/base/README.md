
# Base (Ubuntu + Claude + pyenv/nvm) (base)

Isolated Ubuntu environment to start any project without polluting the host. Python via the official feature + Poetry, pyenv (with build deps) to compile other versions on demand, Node via nvm, GitHub CLI and a CLI toolbox (jq, ripgrep, fd, sqlite3, ffmpeg…). Claude Code comes preinstalled and preconfigured — settings.json, statusline and auth reused from the host — plus microphone, clipboard and a Playwright browser bridged from the host desktop.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| imageVariant | Base Ubuntu version. | string | ubuntu-24.04 |
| pythonVersion | Python version installed by the official feature (os-provided uses the system one; pyenv stays available for others). | string | os-provided |
| nodeVersion | Node version installed via nvm (lts, none, or X / X.Y.Z). Install more later with: nvm install <v>. | string | lts |
| installPlaywright | Install Playwright with Chromium and register the Playwright MCP server, so Claude can browse pages. Adds a few hundred MB (browsers are cached in a shared volume). | boolean | true |
| playwrightHeadless | Run Claude's browser headless. Keep it false on a Wayland desktop to watch the browser window on your screen; set it to true on machines with no desktop session. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bolaum/devcontainer-templates/blob/main/src/base/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
