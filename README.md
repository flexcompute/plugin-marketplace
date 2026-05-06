# Flexcompute Plugins

Install Flexcompute plugins for AI coding assistants.
Use the section for your assistant below.

## Available Plugins

- Tidy3D: AI-assisted Tidy3D documentation search, API lookup, and simulation-focused help through `tidy3d-mcp`. Available for Claude Code, Codex, and GitHub Copilot CLI.
- PhotonForge: AI guidance for PhotonForge PCells, layout routing, LVS, and MCP-backed documentation lookup. Available for Claude Code, Codex, and GitHub Copilot CLI.

## Claude Code

In Claude Code:

```text
/plugin marketplace add flexcompute/plugin-marketplace
/plugin install tidy3d@flexcompute
/plugin install photonforge@flexcompute
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

Then open Codex, run `/plugins`, choose the Flexcompute marketplace, and install Tidy3D or PhotonForge.

## GitHub Copilot CLI

Install a plugin from its Copilot CLI plugin directory:

```bash
copilot plugin install flexcompute/plugin-marketplace:copilot-cli/tidy3d
copilot plugin install flexcompute/plugin-marketplace:copilot-cli/photonforge
```

## Requirements

The Tidy3D and PhotonForge plugins start `tidy3d-mcp` with `uvx`. Install `uv` if `uvx` is not available on your `PATH`.
