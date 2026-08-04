
# Base (Ubuntu + Claude + pyenv/nvm) (base)

Isolated Ubuntu environment to start any project without polluting the host. Python via the official feature + Poetry, pyenv (with build deps) to compile other versions on demand, Node via nvm, GitHub CLI and a CLI toolbox (jq, ripgrep, fd, sqlite3, ffmpeg…). Claude Code comes preinstalled and preconfigured — settings.json, statusline and auth reused from the host — plus microphone, clipboard and a Playwright browser bridged from the host desktop.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| imageVariant | Base Ubuntu version. | string | ubuntu-24.04 |
| pythonVersion | Python version installed by the official feature (os-provided uses the system one; pyenv stays available for others). | string | os-provided |
| nodeVersion | Node version installed via nvm (lts, none, or X / X.Y.Z). Install more later with: nvm install <v>. | string | lts |
| aptMirror | Which Ubuntu mirror apt uses. 'auto' benchmarks the official mirrors for your country against the default and switches only if one is clearly faster — worth minutes per uncached build on networks where archive.ubuntu.com is slow. 'keep' leaves the image untouched; you can also pass a country code (e.g. BR, DE) to skip detection, or a full mirror URL. | string | auto |
| extraPackages | Extra apt packages for this project, space-separated. The image ships only tools useful in any project (jq, ripgrep, fd, tree, less, zip); anything project-specific goes here — e.g. 'sqlite3 postgresql-client' for database work, 'ffmpeg imagemagick' for media, 'shellcheck shfmt' for shell. Installed in the last layer of the Dockerfile, so changing it leaves every other layer cached. | string | - |
| buildProgress | Docker build output. 'plain' prints every step in full, so you can tell which layer is slow; the compact 'auto' view truncates them all to the same 'RUN --mount=type=cache,' and hides that. Set it to 'auto' if you prefer the quieter output. | string | plain |
| installPlaywright | Install Playwright with Chromium and register the Playwright MCP server, so Claude can browse pages. Adds a few hundred MB (browsers are cached in a shared volume). | boolean | true |
| claudeLanguage | Language for Claude's answers AND voice dictation (a single setting controls both). Without it, /voice transcribes as English. Claude Code has no pt-BR variant: use portuguese. | string | portuguese |
| playwrightHeadless | Run Claude's browser headless. Keep it false on a Wayland desktop to watch the browser window on your screen; set it to true on machines with no desktop session. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bolaum/devcontainer-templates/blob/main/src/base/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
