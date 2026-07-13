
# Base (Ubuntu + Claude + pyenv/nvm) (base)

Lean, isolated Ubuntu environment to start any project without polluting the host. Python via the official feature + Poetry, pyenv (with build deps) to compile other versions on demand, Node via nvm, and Claude Code preinstalled and preconfigured — settings.json, statusline and auth reused from the host.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| imageVariant | Base Ubuntu version. | string | ubuntu-24.04 |
| pythonVersion | Python version installed by the official feature (os-provided uses the system one; pyenv stays available for others). | string | os-provided |
| nodeVersion | Node version installed via nvm (lts, none, or X / X.Y.Z). Install more later with: nvm install <v>. | string | lts |



---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bolaum/devcontainer-templates/blob/main/src/base/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
