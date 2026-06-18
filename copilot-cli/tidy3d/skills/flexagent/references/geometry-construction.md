# Geometry Construction — Decision Tree, Hierarchy, Patterns

## Core Principle: Compose, Don't Compute

Complex geometry is **composed from simple primitives** with boolean operations and path construction — not built by computing raw vertex arrays. Think CSG: an L-shape is `ClipOperation("union", arm_h, arm_v)`, a ring is two concentric `Cylinder`s, a rib waveguide is a slab with a ridge on top.

Manual trigonometry on vertex arrays is the failure mode this section exists to prevent.

---

## Shape → Construction Decision Tree

| Shape type | Approach | Example |
|---|---|---|
| Rectangular prism | `td.Box` or `td.Box.from_bounds` | Waveguide core, substrate, cladding |
| Cylinder, sphere, cone | `td.Cylinder` | Fiber, via, pillar |
| Straight taper | `gdstk.RobustPath` with width function + `td.PolySlab.from_gds()` | Mode converter, spot-size converter |
| S-bend | `gdstk.RobustPath` with parametric offset + `td.PolySlab.from_gds()` | Waveguide routing, Y-junction arms |
| Circular / arc bend | `gdstk.RobustPath.arc()` + `td.PolySlab.from_gds()` | 90° bend, ring coupler section |
| Multi-segment waveguide | `gdstk.RobustPath` with chained `.segment()` / `.arc()` calls | Routed waveguides with corners |
| Boolean combination (L, T, slot, rib) | `td.ClipOperation(operation="union"/"difference"/"intersection", ...)` on simple primitives, **or** `gdstk.boolean()` for 2D polygon-level ops + `PolySlab.from_gds()` | Rib WG = slab + ridge, slotted structures |
| Ring / annulus | `gdstk` arcs + `td.PolySlab.from_gds()`, or two concentric `td.Cylinder` + `ClipOperation("difference")` | Ring resonator, circular slot |
| Custom polygon (last resort) | `td.PolySlab(vertices=..., slab_bounds=..., axis=2)` with mandatory geometry-inspection check | Arbitrary cross-sections |
| Polygon with arc edges | `td.PolySlab(vertices=..., bulges=..., slab_bounds=...)` using bulge = `tan(theta/4)` | Curved 2D cross-sections without RobustPath (v2.11+) |
| Repeated unit cells / arrays | `td.GeometryArray(geometry=..., offsets=..., transforms=...)` or `geom.array(offsets=..., transforms=...)` | Metasurfaces, gratings, phased pillar arrays (v2.11+) |
| GDS file import | `td.PolySlab.from_gds(cell, ...)` | External layout |

---

## Construction Hierarchy (mandatory ordering)

Use the highest-level method available. Each step down increases the risk of shape errors:

1. **`gdstk.RobustPath`** — for any path-like shape (straight, tapered, bent, S-bend, arc). Default. Handles width transitions, tight bends, and end-caps correctly.
2. **`gdstk.FlexPath`** — when `RobustPath` doesn't support a needed feature (e.g., custom offset functions).
3. **`td.ClipOperation`** — for boolean combinations of simple primitives (union / difference / intersection).
4. **`gdstk.boolean()`** — for 2D polygon-level booleans before extruding with `PolySlab.from_gds()`.
5. **`td.PolySlab(vertices=...)`** — last resort. Allowed only for simple rectilinear polygons (all straight edges, no curves). For anything with curves, go back up to options 1–2.

For any path-like shape with curves (tapers, bends, arcs, waveguides), `gdstk.RobustPath` or `gdstk.FlexPath` is **mandatory**. Manual vertex arrays computed via trigonometry are forbidden for curved geometry.

---

## Bulk replication (v2.11+)

For N copies of a single base geometry (metasurface unit cells, periodic gratings, phased pillar arrays, hole rows in photonic crystals), prefer `td.GeometryArray` over both `td.GeometryGroup` of N copies and hand-written `for`-loops:

```python
hole = td.Cylinder(center=(0, 0, 0), radius=0.1, length=0.22, axis=2)
offsets = np.array([(i * 0.4, 0, 0) for i in range(num_periods)])
hole_array = hole.array(offsets=offsets)              # td.GeometryArray
```

- Lower memory + faster validation than `GeometryGroup` of N entries.
- `transforms` allows per-element rotation / scaling — useful for metasurface unit cells whose phase response is encoded in rotation rather than geometry.
- A `Structure(geometry=GeometryArray, medium=...)` treats the whole array as one structure; group multiple `GeometryArray`s under a `GeometryGroup` if you need different media per array.

For 2D cross-sections with curved edges (rounded corners, partial circles, ovals), prefer `td.PolySlab(bulges=...)` over high-vertex polygon approximations — see the decision-tree row above.

---

## Polygon Quality

These rules prevent the two most common failures with free-form geometry: too few vertices (jagged curves) and completely wrong shapes (incorrect vertex math).

### Vertex density

- **Curved segments**: minimum **50 vertices per curve** (arc, bend, taper profile). With `gdstk`, set `tolerance=1e-3` (µm) or smaller to achieve this.
- **After `cell.get_polygons()`**: inspect `len(polys[0])`. If a polygon representing a curve has < 20 vertices, the tolerance is too coarse — reduce it and regenerate.
- **Straight segments**: no minimum, but avoid degenerate edges (zero-length segments, duplicate adjacent vertices).

### Mandatory sanity checks

After generating vertices (from `gdstk` or manually for rectilinear shapes):

1. **Bounding-box check.** Compute `x_min/x_max, y_min/y_max` from the vertices. Verify these match expected physical dimensions within 10%. A bounding box orders of magnitude off indicates a units / coordinate error.
2. **Non-empty polygon check.** Verify `len(vertices) >= 3`. An empty or degenerate polygon means the construction failed silently.
3. **State dimensions explicitly** when presenting geometry: *"The taper polygon spans 10.0 µm in x and 0.5 µm in y with 87 vertices."*

### Shape decomposition

If a shape has both straight and curved sections (e.g., a waveguide with a straight section that transitions into a bend):
- **Preferred:** build the whole path as a single `gdstk.RobustPath` with multiple `.segment()` and `.arc()` calls.
- **Alternative:** decompose into separate structures (`Box` for straight, `PolySlab` from gdstk for curved) joined via `ClipOperation("union", ...)`.
- **Forbidden:** computing a single large vertex array with manual trigonometry for the curved portions concatenated with straight portions.

---

## Critical Rules

- **NEVER pass `center=...` to `td.PolySlab`.** Position is determined by `vertices` (2D polygon) + `slab_bounds` (z extents).
- **NEVER skip geometry inspection** for custom `PolySlab` / `gdstk` geometry. Render the cross-section, apply `protocols/geometry-inspection.md`, then describe what you see before moving on.
- **NEVER skip the post-build audit** (`protocols/post-build-audit.md`) for custom builds, import builds, or image-referenced builds.
- For curves, use `gdstk.RobustPath` / `FlexPath` — manual trigonometric vertex computation is forbidden.
- Prefer `td.ClipOperation` or `gdstk.boolean()` for boolean composition over manually computing merged vertex arrays.
- When using `td.PolySlab(vertices=...)` directly, vertices must be **counterclockwise** for the exterior boundary.
- Verify constructor parameters with docs search before first use of any unfamiliar class (e.g., `td.ClipOperation`, `td.PolySlab` keyword names).

---

## Verified Code Patterns

`gdstk.RobustPath` is the default for any curved or tapered waveguide geometry. The patterns below are validated against current Tidy3D.

### Taper (width transition)

```python
import gdstk
import tidy3d as td

cell = gdstk.Cell("taper")
path = gdstk.RobustPath((0, 0), wg_width_in, layer=1)
path.segment((taper_length, 0), width=wg_width_out)
cell.add(path)
polys = cell.get_polygons()
taper = td.Structure(
    geometry=td.PolySlab(vertices=polys[0], axis=2, slab_bounds=(0, height)),
    medium=si,
)
```

### S-bend (lateral offset with sine profile)

```python
import numpy as np

cell = gdstk.Cell("sbend")
path = gdstk.RobustPath((0, 0), wg_width, layer=1)
path.segment(
    (bend_length, bend_offset),
    offset=lambda u: bend_offset * (u - np.sin(2 * np.pi * u) / (2 * np.pi)),
)
cell.add(path)
polys = cell.get_polygons()
```

### Circular arc bend (90°)

```python
cell = gdstk.Cell("bend")
path = gdstk.RobustPath((0, 0), wg_width, layer=1)
path.arc(bend_radius, 0, np.pi / 2)  # 90-degree bend
cell.add(path)
polys = cell.get_polygons()
```

### Boolean L-shape (via `ClipOperation`)

```python
arm_h = td.Box.from_bounds(rmin=(0, 0, 0), rmax=(3, 0.5, 0.22))
arm_v = td.Box.from_bounds(rmin=(0, 0, 0), rmax=(0.5, 2, 0.22))
l_shape_geo = td.ClipOperation(operation="union", geometry_a=arm_h, geometry_b=arm_v)
l_shape = td.Structure(geometry=l_shape_geo, medium=si)
```

### Polygon quality check

After every `cell.get_polygons()`:

```python
polys = cell.get_polygons()
assert len(polys) > 0, "No polygons returned — check path definition"
if len(polys[0]) < 20:
    # Curve has too few vertices — reduce tolerance in RobustPath
    path = gdstk.RobustPath(..., tolerance=1e-4)  # smaller = more vertices
```

Target: **≥ 50 vertices per curved segment** for smooth geometry.

---

## Geometry Guardrails (physics-side rules)

- Extend infinite structures (I/O waveguides, substrates) **beyond the PML boundaries** so they reach the simulation domain faces. Verify via cross-section render after building.
- Keep all finite structures **≥ 0.5 · λ_max** away from any PML interface.
- All sources and monitors must remain inside the simulation domain.
- Waveguide sources / monitors: **size ≥ 6 × cross-section**; keep centered on the waveguide core.
- No gaps between interconnected waveguide sections.
- Use `td.GeometryGroup` for a small set of different geometries that share a medium, or to group multiple `GeometryArray`s under one medium. Do not use it as a replacement for `td.GeometryArray` when representing N repeated copies of the same base geometry.
- Use `td.Transformed` for mirror / rotate / scale operations.

For broader physics rules (units, materials, mesh strategy, cost controls), see the relevant sections of `workflow-build.md` and `references/api-pitfalls.md`.
