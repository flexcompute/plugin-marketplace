# Flexcompute Plugins

Install Flexcompute plugins for AI coding assistants. Use the section for your assistant below.

## Available Plugins

### Tidy3D

Tidy3D adds `tidy3d-mcp` and the [FlexAgent](https://www.flexcompute.com/resources/ai-agent/) simulation skill to your assistant. The MCP server provides current Flexcompute documentation search and document fetch tools. The skill guides agents through Tidy3D simulation creation, API lookup, troubleshooting, geometry import, result analysis, physics guardrails, and cost-control checks before remote simulation runs.

### PhotonForge

PhotonForge adds skills for parametric component authoring and layout verification. The skills guide agents through PCells, technologies, hierarchy, ports, schema-aware component definitions, routing, physical connectivity, virtual connections, LVS-style checks, and layout-overlap risk review. PhotonForge also uses MCP-backed Flexcompute documentation lookup.

## Prerequisites

The plugins start `tidy3d-mcp` with `uvx`. Install [`uv`](https://docs.astral.sh/uv/getting-started/installation/) so `uvx` is on your `PATH`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

For Homebrew or Windows, see the [uv install docs](https://docs.astral.sh/uv/getting-started/installation/).

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
