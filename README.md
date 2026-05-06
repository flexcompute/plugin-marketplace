# Flexcompute Plugins

Install Flexcompute plugins for AI coding assistants.
Use the section for your assistant below.

## Available Plugins

- Tidy3D: AI-assisted Tidy3D documentation search, API lookup, and simulation-focused help through `tidy3d-mcp`. Available for Claude Code, Codex, and GitHub Copilot CLI.

## Claude Code

In Claude Code:

```text
/plugin marketplace add flexcompute/plugin-marketplace
/plugin install tidy3d@flexcompute
```

If Claude Code is already running, reload plugins after installation:

```text
/reload-plugins
```

## Codex

Add this repository as a Codex plugin marketplace:

```bash
codex plugin marketplace add flexcompute/plugin-marketplace
```

Then open Codex, run `/plugins`, choose the Flexcompute marketplace, and install Tidy3D.

## GitHub Copilot CLI

Install the Tidy3D plugin from its Copilot CLI plugin directory:

```bash
copilot plugin install flexcompute/plugin-marketplace:copilot-cli/tidy3d
```

## Requirements

The Tidy3D plugin starts `tidy3d-mcp` with `uvx`. Install `uv` if `uvx` is not available on your `PATH`.
