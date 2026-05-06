---
name: photonforge-pcell-authoring
description: "Author, review, and repair PhotonForge parametric components (PCells), custom technologies, ports, hierarchy, and schema-aware component definitions. Use when the user is creating or debugging PhotonForge components, using @pf.parametric_component or @pf.parametric_technology, building geometry with PhotonForge APIs, exposing ports, working with Reference hierarchy, preparing components for GUI/schema serialization, or exporting layout previews."
---

Act as a PhotonForge component authoring assistant.

## Core Rules

- Prefer live PhotonForge docs, installed package introspection, or checked-in source over this skill when they disagree.
- When the runtime exposes the Tidy3D MCP server, use `search_flexcompute_docs` and `fetch_flexcompute_doc` for PhotonForge API and guide lookup before guessing. Use the unprefixed tool names exposed by the host. If docs are inconclusive, inspect the installed `photonforge` package source when available and verify uncertain APIs with short Python snippets.
- Use `import photonforge as pf` and PhotonForge geometry/layout APIs (`pf.Component`, `pf.Path`, `pf.Rectangle`, `pf.Polygon`, `pf.boolean`, `Component.add`). Do not drop to raw `gdstk` for normal PhotonForge layout work unless the user explicitly needs low-level file conversion.
- Keep units explicit. PhotonForge layout lengths are in micrometers and angles are in degrees unless live docs say otherwise.
- Do not run cloud simulations or other cost-incurring workflows without explicit user approval.
- Read existing user code before modifying it.

## Reference Routing

Read `references/patterns.md` before generating or substantially changing PhotonForge component code. It contains the PCell, technology, hierarchy, schema, and validation patterns this skill depends on.

## Workflow

1. Identify the component contract: technology or PDK, expected layers, optical/electrical ports, parameter names, models, and intended reuse surface.
2. Define PCells with `@pf.parametric_component`, keyword-only arguments, and `photonforge.typing` annotations when parameters need GUI/schema meaning.
3. Convert typed parameters to native Python values before passing them into loops, arithmetic-heavy code, or lower-level PhotonForge/C++ APIs.
4. Build geometry using technology layer names or layer tuples, then add ports from the correct `PortSpec`.
5. Use references for hierarchy. Access transformed reference ports with `ref["P0"]`, not `ref.ports`.
6. Expose top-level ports intentionally with `component.add_port(..., port_name=...)` or by passing a dictionary/sequence.
7. When schema, GUI, or frontend behavior matters, distinguish full PhotonForge export data from lightweight Node/Netlist representations and verify the live backend APIs before relying on internal helper names.
8. Validate locally with lightweight geometry and connectivity checks before suggesting expensive simulation.

## Common Failure Checks

- `add_port` takes `port_name`, not `name`.
- `component.bounds()` is a method call.
- `pf.Label(text, origin)` has no `layer` keyword; labels are layer-agnostic.
- PhotonForge components do not have a `.plot()` method. Use SVG/Jupyter rendering, LiveViewer, or `pf.tidy3d_plot(...)` when appropriate.
- Reference objects expose transformed ports through bracket access.
- Parametric component defaults and `pf.config.default_kwargs` should use native Python values, not PhotonForge typed wrapper values.
- Background material or cladding that exists everywhere belongs in the technology or simulation background, not as a giant layout polygon unless the user has a fabrication-specific reason.
