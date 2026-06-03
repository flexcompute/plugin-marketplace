# Flexcompute Plugins

[Tidy3D](https://docs.flexcompute.com/projects/tidy3d/en/latest/) and [PhotonForge](https://docs.flexcompute.com/projects/photonforge/en/latest/) for your AI coding assistant.

## Why This Exists

Instead of pasting docs, setup notes, [Tidy3D notebooks](https://github.com/flexcompute/tidy3d-notebooks), and simulation workflow context into every chat, install these plugins once. Your agent can retrieve semantically indexed Flexcompute guidance, including notebooks that capture real workflows, and use the right [Tidy3D](https://docs.flexcompute.com/projects/tidy3d/en/latest/) or [PhotonForge](https://docs.flexcompute.com/projects/photonforge/en/latest/) approach while it writes, debugs, or reviews code.

## Install

macOS or Linux:

```bash
curl -LsSf https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.sh | bash
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.ps1 | iex"
```

The installer checks `uvx` and `tidy3d-mcp` first. If `uvx` is missing in an interactive terminal, it asks before running Astral's official [`uv`](https://docs.astral.sh/uv/) installer. When you pipe the installer from `curl`, pass `--install-uv` to opt in up front. It then asks which AI coding tool you use and sets up the plugins.

In non-interactive terminals, pass `--client auto`, `--client codex`, `--client claude`, `--client copilot`, or `--client none`. In PowerShell, use `-Client` instead.

## What You Can Ask

| Goal | Example prompt |
| --- | --- |
| Build or debug Tidy3D simulations | `use FlexAgent to set up a Tidy3D silicon waveguide simulation` |
| Use current Flexcompute docs | `look up the Tidy3D API for ModeSource` |
| Author PhotonForge components | `create a parameterized MMI component` |
| Review layout connectivity | `check this PhotonForge layout for port issues` |

## Reference Links

- [`uv` documentation](https://docs.astral.sh/uv/)
- [Tidy3D documentation](https://docs.flexcompute.com/projects/tidy3d/en/latest/)
- [Tidy3D notebooks](https://github.com/flexcompute/tidy3d-notebooks)
- [PhotonForge documentation](https://docs.flexcompute.com/projects/photonforge/en/latest/)

## Included Plugins

This README is the current public catalog. Until a plugin needs longer examples, each plugin's installed skills and MCP tools are listed here.

### `tidy3d`

| Installed surface | Name | What it enables |
| --- | --- | --- |
| Skill | `flexagent` | Tidy3D simulation setup, API usage, troubleshooting, geometry import, result analysis, cost-aware workflow guidance, and script review. |
| MCP server | `tidy3d` via `uvx tidy3d-mcp` | Flexcompute docs search and doc fetch tools. Host-specific tool names can vary, but the tools end in `search_flexcompute_docs` and `fetch_flexcompute_doc`. |

### `photonforge`

| Installed surface | Name | What it enables |
| --- | --- | --- |
| Skill | `photonforge-pcell-authoring` | PhotonForge PCell authoring, custom technologies, ports, hierarchy, schema-aware component definitions, and layout preview guidance. |
| Skill | `photonforge-layout-verification` | Schematic-to-layout assembly, routing, physical and virtual connection checks, netlist inspection, LVS-style review, and overlap sanity checks. |
| MCP server | `tidy3d` via `uvx tidy3d-mcp` | Flexcompute docs search and doc fetch tools for PhotonForge and related API guidance. Host-specific tool names can vary, but the tools end in `search_flexcompute_docs` and `fetch_flexcompute_doc`. |

## Manual Install

Use this path if you want to run the steps yourself. Install [`uv`](https://docs.astral.sh/uv/), then verify that the MCP server starts:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx tidy3d-mcp --help
```

On Windows PowerShell:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uvx tidy3d-mcp --help
```

<details>
<summary>Claude Code</summary>

```bash
claude plugin marketplace add flexcompute/plugin-marketplace
claude plugin install tidy3d@flexcompute
claude plugin install photonforge@flexcompute
```

</details>

<details>
<summary>Codex</summary>

```bash
codex plugin marketplace add flexcompute/plugin-marketplace
codex plugin add tidy3d@flexcompute
codex plugin add photonforge@flexcompute
```

</details>

<details>
<summary>VS Code Agent Plugins (Preview)</summary>

Agent plugins are currently a VS Code preview feature. In VS Code user
settings JSON, make sure plugin support is enabled and add the Flexcompute
marketplace:

```json
{
  "chat.plugins.enabled": true,
  "chat.plugins.marketplaces": [
    "flexcompute/plugin-marketplace"
  ]
}
```

If `chat.plugins.enabled` is locked, it is managed by your GitHub Copilot
organization policy. Ask your administrator to enable agent plugins.

Then open the Extensions view, search `@agentPlugins`, and install `tidy3d`
and `photonforge`.

</details>

<details>
<summary>GitHub Copilot CLI</summary>

```bash
copilot plugin marketplace add flexcompute/plugin-marketplace
copilot plugin install tidy3d@flexcompute
copilot plugin install photonforge@flexcompute
```

</details>

## Troubleshooting

If the plugins do not appear, restart or reload the AI coding tool first.

If MCP tools do not start, run `uvx tidy3d-mcp --help`.

If installation still fails, open an issue at https://github.com/flexcompute/plugin-marketplace/issues with your operating system, AI coding tool, install command, and terminal output.
