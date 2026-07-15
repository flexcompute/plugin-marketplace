# PhotonForge Serialization And Schema

Use this reference when saving/loading designs or explaining how PhotonForge represents them on disk. PhotonForge has two distinct schema surfaces: the full export format (save/load) and a lightweight frontend representation (Node/Netlist) used by the GUI.

## Contents

- Full-state PHF save/load
- Layout interchange (GDS/OASIS)
- Touchstone S-parameters
- Full-export structure
- Object type IDs
- Coordinates and transforms
- Connectivity inspection
- Frontend Node/Netlist schema (concept)

## Full-state PHF Save/Load

PHF is the comprehensive format: it captures everything needed to reconstruct PhotonForge objects (components, references, ports, technologies, models).

```python
import photonforge as pf

# Save one or more top-level objects
pf.write_phf("design.phf", component)
pf.write_phf("design.phf", component_a, component_b, technology)

# Load. IMPORTANT: the loaders return CONTAINERS, not the bare object. [verified 1.5.0]
objs = pf.load_phf("design.phf")             # -> dict {'components': [...], 'technologies': [...]}
component = objs["components"][0]            # pull your component out of the dict
tech      = objs["technologies"][0] if objs["technologies"] else None

comps = pf.load_full_phf("design.phf")       # -> tuple of the top-level components
component = comps[0]

# Avoid clobbering the active session config / default technology
objs = pf.load_phf("design.phf", set_config=False)
```

- `load_phf(filename, only_explicit=True, set_config=True)` returns a **dict** with `'components'` and `'technologies'` lists (the explicitly stored top-level objects). `load_full_phf(filename, set_config=True)` returns a **tuple** of the top-level components (dependencies reconstructed). Both preserve full state - hierarchy, ports, technology, and models. [verified 1.5.0]
- `set_config=True` lets the loaded file set the default technology and config. Pass `set_config=False` when loading into a live session you do not want disturbed.

Always round-trip verify before trusting a file:

```python
c = pf.load_phf("design.phf")["components"][0]
assert c.name == component.name
assert set(c.ports) == set(component.ports)
assert len(c.models) == len(component.models)     # PHF preserves models
assert c.bounds() is not None                     # bounds() is a method
```

## Layout Interchange (GDS/OASIS)

For masks and tool interchange, export/import layout. This is geometry-only: models and behavioral state are not preserved, and ports do NOT survive as functional ports (at most drawn as markers, and only if the technology defines a pin/port layer - `basic_technology` writes none).

```python
pf.write_layout("mask.gds", component)              # also OASIS by extension
pf.write_layout("mask.oas", top_a, top_b)

cells = pf.load_layout("mask.gds", technology=my_tech)   # -> dict {cell_name: Component} [verified 1.5.0]
top = cells["<top cell name>"]                           # or: list(cells.values())
tops = pf.find_top_level(*cells.values())               # cells not referenced by any other cell [verified 1.5.0]
```

`write_layout(filename, *components, paths_to_polygons=True, compression_level=9, fracture_limit=0, library_name='LIBRARY', ...)`. `load_layout(filename, technology=None, layers=[], cell_names=[], ...)` returns a **dict keyed by cell name** (each value a `Component`); the `technology=` you pass drives layer mapping, so verify layers resolved as intended after import. Geometry-only: the reloaded cells carry no models and their ports are layout markers. Use PHF (not layout) when you need full state.

## Touchstone S-parameters

```python
S, freqs = pf.load_snp("measurement.s2p")   # -> TUPLE (S, frequencies) [verified 1.5.0]
# S is a numpy array indexed [frequency, output_port, input_port];
# freqs is the frequency vector (Hz), length = S.shape[0].
```

Use this to bring measured or externally simulated S-parameters into a PhotonForge workflow. `load_snp` returns a `(S_array, frequencies)` tuple - NOT an `SMatrix` object - so unpack it. There is no `pf.write_snp` in 1.5.0 (import only).

GOTCHA (verified 1.5.0): `load_snp` parses `# Hz ...` Touchstone files correctly, but for **non-Hz unit lines (`# GHz`/`MHz`/`THz`)** - which most real VNA/simulator files use - it silently drops trailing frequency points and double-scales the last frequency. Its shape self-check (`S.shape[0] == len(freqs)`) still passes, so the corruption is easy to miss. After loading, VERIFY `freqs` against the file's own frequency column. The robust fix is a unit-aware reader that honors the declared unit: `scikit-rf` returns frequencies already in Hz (`rf.Network("meas.s2p").f`), so read there and feed those to PhotonForge. Do NOT just relabel the header `# GHz` -> `# Hz`: that leaves the numeric column unchanged, so `193.4` (meaning 193.4 GHz) is then read as 193.4 Hz. If you must normalize the file to `# Hz`, convert the frequency column too (multiply GHz values by 1e9). (This is an upstream `load_snp` bug, not a skill issue.)

## Full-export structure (internal/conceptual - NOT the on-disk bytes)

**A `.phf` written by `pf.write_phf` is a BINARY file** (it begins with the magic
bytes `FLEX`); `json.loads` on it fails. The JSON below is only a *conceptual* view
of what the store holds, to build intuition - it does NOT correspond to the file
on disk, and you cannot read or hand-edit a `.phf` as JSON. Always reconstruct
with `load_phf` / `load_full_phf` and work with the returned objects.

```json
// conceptual only - the real file is binary
{
  "type": "Store",
  "config": { "default_technology": "uuid", ... },
  "top_content": [ "<object_id>", ... ],   // top-level objects
  "data": [ "<object_id>", { ... } ]       // every object incl. dependencies
}
```

Conceptually each object carries its type, id, optional properties, and
type-specific fields (a Component references its name, sub-references, structures,
ports, and technology by id).

## Object Type Tags

The full export tags each object with a numeric type id (Store, Component, Reference, Port, Technology, and so on). These ids and the helpers that map them to names are an internal serialization detail: there is no public conversion API, and the values can change between releases with no backwards-compatibility guarantee. Do not depend on the numbers or reach into private helpers to decode them. Reconstruct objects with `load_phf` / `load_full_phf` and work with the returned PhotonForge objects instead.

## Coordinates And Transforms

Internally, coordinates are stored as scaled integers (a small fixed micrometer-per-unit factor), NOT as micrometers - so never read the raw integers as physical lengths. Layers are `(layer_number, datatype)` tuples. A reference transform holds fields like:

```json
{ "origin": [0, 0], "rotation": 90.0, "scaling": 1.0,
  "x_reflection": false, "columns": 1, "rows": 1, "spacing": [0, 0] }
```

Do not read the raw integers as micrometers; apply the scale factor. Better, query the live object (`ref.origin`, `ref.rotation`, `ref[port].center`) instead of parsing serialized integers.

## Connectivity Inspection

For circuit connectivity, use the public netlist on the component:

```python
nl = component.get_netlist()
# {
#   "instances": [Reference, ...],
#   "ports": {(idx, name, modes): name},
#   "terminals": {(idx, term): name},
#   "connections": [((i1, p1, m), (i2, p2, m)), ...],
#   "virtual connections": [...],
#   "butt couplings": [...],
# }
```

This is the supported way to inspect or debug topology. `component.tree_view()` is useful for hierarchy.

## Frontend Node/Netlist Schema (Concept)

Separately from the full export, the GUI consumes a lightweight representation:

- Node schema: a per-component UI view (display name, parameter schema, ports/terminals with canvas side+offset, preview/thumbnail SVG, active models).
- Netlist schema: nodes plus virtual connections and exposed external ports/terminals, for the schematic canvas.
- Parameter schema: JSON Schema derived from a parametric function's signature and `photonforge.typing` annotations, used to render dynamic parameter forms (e.g. `$units`, `$ref` to common numeric types like positive/non-negative float, unit interval, complex number).

These are produced by internal backend modules and are not a stable public API. When the user is building public tooling, depend on `write_phf`/`load_phf`, `write_layout`/`load_layout`, and `component.get_netlist()`; reach into backend conversion helpers only for backend work and verify the current names against the installed package first.
