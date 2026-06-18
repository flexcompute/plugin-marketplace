# Structural Blueprint Protocol

> **Scope.** Applies to Learn / Debug / Build / Analysis.

Before writing any simulation code for a custom build or imported layout, produce a **structural blueprint** in the conversation and get user confirmation. This catches the "single block instead of grating" class of failure that no API check would surface.

## When This Applies

- **Custom path** — mandatory.
- **Import path** — mandatory after file inspection and layer / cell selection, before generated import code.
- **Any path with a reference image in scope** — mandatory. The blueprint verifies the structure count and topology before any code is generated.
- **Modifications that add entirely new structures** — mandatory.
- **Does NOT apply** to Quick Modify (single-parameter tweaks).

## What the Blueprint Must Contain

1. **Enumerate every `td.Structure`** you plan to create. For each:
   - Name (e.g., `si_slab`, `etch_box`, `substrate`).
   - Geometry type (`Box`, `PolySlab`, `Cylinder`, `ClipOperation`, etc.).
   - Material (medium identifier or refractive index).
   - Approximate dimensions and position.

2. **Identify repeating / periodic features.** If a physical feature repeats N times (grating teeth, photonic-crystal holes, array elements), state explicitly: *"N copies via `td.GeometryArray` / `geom.array(...)`, for-loop, or list comprehension, pitch P."* Never plan to hardcode N > 3 individual structures.

3. **Identify curved geometry.** For each structure with curves (bends, tapers, arcs), state the construction method per `references/geometry-construction.md`:
   - `gdstk.RobustPath` (preferred for path-like shapes).
   - `gdstk.FlexPath`, `ClipOperation`, `gdstk.boolean()`.
   - `td.PolySlab(vertices=...)` only as last resort, with expected vertex count (minimum 50 for curves).

4. **State the expected structural inventory.** Include both:
   - **Physical-feature count** — what should appear in the geometry (example: *"25 grating teeth at 0.63 um pitch, 1 slab, 1 BOX, 1 substrate"*).
   - **Tidy3D container count** — expected `td.Structure` containers. A `td.GeometryArray` may represent many physical copies inside one `Structure`; state that intentionally instead of treating it as a mismatch.

5. **Cross-reference known patterns.** If docs examples or installed project files show a similar device, note which patterns (loop structure, gdstk usage, layer stacking) you will follow.

6. **Present the blueprint to the user. Stop. Wait for confirmation before writing code.**

For imported GDS / STL layouts, the blueprint is an import blueprint: enumerate the selected source file, selected cell or body, selected layer / datatype pairs, extrusion bounds, material assignment, and expected imported polygon / structure inventory from inspection. Do not invent topology that is not present in the file.

## Code Construction Constraints (enforced when writing code after approval)

- If the blueprint lists N > 3 repeating physical features, the code **must** use `td.GeometryArray` / `geom.array(...)`, a `for` loop, or a list comprehension. Hardcoding individual structures is forbidden.
- For any curved geometry, use the construction method specified in the blueprint — never fall back to manual trigonometric vertex computation.
- The generated code's physical-feature inventory and container inventory must match the blueprint. Do not use raw `len(sim.structures)` as the only invariant when `GeometryArray` or grouped geometry intentionally compresses repeated features. If a real mismatch shows up while writing, stop and revise the approach before proceeding.

After the code is generated, run `protocols/post-build-audit.md` to verify the build matches the blueprint.
