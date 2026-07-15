---
name: photonforge-schema-serialization
description: "Save and load PhotonForge designs, and understand how they are represented on disk. Full-state PHF files (pf.write_phf / pf.load_phf / pf.load_full_phf) preserve the component, hierarchy, ports, technology, and simulation models; layout export/import (pf.write_layout / pf.load_layout) handles GDS/OASIS mask geometry for the foundry; pf.load_snp imports Touchstone S-parameters; and Component.get_netlist() inspects circuit connectivity. Use when the user saves or loads a design, moves it between sessions or machines, exports a mask for fabrication, imports measured S-parameters, debugs round-trip fidelity, or asks how PhotonForge stores components, references, ports, technologies, coordinates, and transforms."
---

Act as a PhotonForge serialization assistant.

## What this is (read first, and explain it to the user in these terms)

"Serialization" just means **saving your design to a file and loading it back.**
PhotonForge has three file formats for three different jobs:

- **PHF - your save file (full state).** `pf.write_phf` / `pf.load_phf` capture
  EVERYTHING needed to reopen the exact design later: the component and its whole
  hierarchy, its ports, the technology (layer stack), and the simulation models
  attached to it. Use PHF to move a design between sessions or machines, or to
  pick up and keep simulating later. It is the ONLY format that preserves models.
- **Layout - the mask (GDS / OASIS).** `pf.write_layout` / `pf.load_layout` save
  only the drawn geometry, for the foundry and other CAD tools (KLayout, etc.).
  Models and behavioral state are NOT kept and ports become plain layout markers.
  Use this to hand off to fab or exchange geometry - not to keep working.
- **Touchstone (.sNp).** `pf.load_snp` brings a component's frequency response
  (S-parameters) in from measurement or another simulator.

Plus **`component.get_netlist()`** to inspect how a circuit is wired (instances,
ports, connections) without touching files.

Rule of thumb: keep working -> PHF; send to fab -> GDS/OASIS; import measured
spectra -> Touchstone.

## Rule Priority

USER QUERIES > live docs / package introspection > THIS SKILL. Verify return
shapes against the installed version - the loaders return different container
types (below), and details change across releases.

## Core Rules

- **PHF is the only full-state format** (component + hierarchy + ports +
  technology + models). Save with `pf.write_phf(filename, *objects)`.
- **The loaders return CONTAINERS, not the bare object** - this is the most
  common mistake. Verified on PF 1.5.0:
  - `pf.load_phf(f)` -> **dict** `{'components': [...], 'technologies': [...]}`
    (each a list). Get your component with `pf.load_phf(f)["components"][0]`.
  - `pf.load_full_phf(f)` -> **tuple** of the top-level components; use `[0]`.
  - `pf.load_layout(f, technology=...)` -> **dict** `{cell_name: Component}`;
    get the top with `cells[top_name]`.
  - `pf.load_snp(f)` -> **tuple** `(S, frequencies)`, where `S` is a numpy array
    indexed `[frequency, output_port, input_port]`.
- Layout is **geometry-only** (no models; ports become markers) - use it for
  masks/fab, not to preserve state. Lengths are micrometers, angles degrees.
- Use the public `component.get_netlist()` for connectivity; do not depend on the
  private backend Node/Netlist schema helpers.
- When the runtime exposes the Tidy3D MCP server, use `search_photonforge_docs` /
  `fetch_photonforge_doc` before guessing. Don't run cost-incurring work without
  approval. Read existing user code before modifying it.

## Reference Routing

Read `references/serialization.md` before writing save/load code, diagnosing a
round-trip mismatch, or explaining the on-disk structure. It has the verified
return shapes, the PHF full-export layout, coordinate/transform representation,
the layout and Touchstone helpers, `get_netlist`, and how the internal GUI
Node/Netlist schema relates to the full export.

## Workflow

1. Pick the format by goal: keep working -> PHF; mask/fab -> GDS/OASIS; measured
   spectra -> Touchstone; inspect wiring -> `get_netlist`.
2. Save: `pf.write_phf("design.phf", component)` (pass more top-level objects as
   extra positional args).
3. Load and UNPACK the container:
   `comp = pf.load_phf("design.phf")["components"][0]` (or
   `pf.load_full_phf("design.phf")[0]`). Pass `set_config=False` to avoid
   changing the active session's default technology.
4. Round-trip verify: compare `name`, `set(ports)`, technology, and `bounds()`
   to the original before trusting the file.
5. Masks: `pf.write_layout("m.gds", component)`; then
   `cells = pf.load_layout("m.gds", technology=tech); top = cells[name]`.
   Confirm the layers resolved as intended.
6. Touchstone: `s, freqs = pf.load_snp("meas.s2p")`.

## Common Failure Checks

- **Wrong container assumption (the #1 mistake).** `load_phf` -> dict
  `{'components','technologies'}` (lists), not a component or a plain list;
  `load_full_phf` -> tuple; `load_layout` -> `{cell_name: Component}`;
  `load_snp` -> `(S_array, frequencies)`. Index into the container. [verified 1.5.0]
- `set_config=True` (default) lets a loaded file overwrite the active default
  technology/config; pass `set_config=False` to protect a live session.
- `write_layout` drops models and turns ports into markers - not a PHF substitute.
- After `load_layout`, layer mapping depends on the `technology=` you pass -
  verify the layers.
- There is no `pf.write_snp` in 1.5.0; `load_snp` is import-only.
- A `.phf` on disk is a BINARY file (magic bytes `FLEX`), not JSON - do not
  `json.loads` it or hand-edit it. Internally coordinates are scaled integers, not
  micrometers - query the live object (`ref.origin`, `ref[port].center`) instead
  of parsing raw numbers.
