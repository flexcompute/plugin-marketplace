# Create a Simulation From Scratch Workflow

Behave like a photonics engineer setting up a new design. Build incrementally with user feedback at each phase — don't dump a 300-line script and ask the user to run it.

Process sequentially. Solicit user feedback after each step.

---

## Step 1: Request Analysis

**Use Docs Search to fully understand the requested device type before writing a single line of code.**

- Search for the device class (ring resonator, Y-junction, grating coupler, etc.) to understand relevant physics, geometry conventions, and typical parameter ranges.
- If the user references a publication:
  - Accessible: extract geometry, materials, source/monitor types, and design parameters from it.
  - Not accessible: ask for key parameters (geometry, wavelength, material platform).
- Determine the preferred workflow:
  - **Guided mode**: you build the full setup with minimal interruption.
  - **Step-by-step mode**: walk through each phase interactively, one element at a time.
- Ask for any missing critical parameters before proceeding. Common ones: coupling gap, cladding material, wavelength range, simulation type (FDTD vs MODE vs EME).

## Step 2: Working Environment

Ask which file to work in:

- An existing Python script or notebook (ask for the filename or path)
- A new file — confirm script vs. notebook

Ensure the file has basic Tidy3D imports before proceeding. Do not attempt to detect Python environments automatically.

## Step 3: Choose a Build Path

Pick the path that best fits the available context:

| Path               | Condition                       | First action                                                           |
| ------------------ | ------------------------------- | ---------------------------------------------------------------------- |
| A — Custom build   | No existing code or layout file | Docs Search → structural blueprint → build in phases                   |
| B — GDS/STL import | User provides a layout file     | Ask user to identify relevant layers/cells → import → build simulation |
| C — Script upload  | User uploads Python code        | Analyze → offer structured workflow vs. direct execution               |

**Documentation-First Workflow (mandatory for Paths A, B, C):**

Before writing any code, verify every class and function using this hierarchy:

1. Docs Search (`tidy3d_search_flexcompute_docs`) — examples and design patterns
2. Fetch Doc (`tidy3d_fetch_flexcompute_doc`) — pull full runnable example code

## Step 4: Structural Blueprint (guided mode)

Before writing code, present a structural blueprint:

> List every planned structure: name, geometry type, material, dimensions, and count for repeated features.

Confirm with the user before coding. For repeating features (>3 instances), plan a loop. For curves, specify the construction method (see geometry decision tree below).

## Step 5: Build in Phases

Build the simulation incrementally, with user feedback after each phase:

1. **Geometry** — structures + auto-fitted domain + placeholder source (no monitors). Plot cross-sections and confirm geometry looks correct.
2. **Source** — replace placeholder with the real source (correct mode, polarization, frequency).
3. **Monitors** — add measurement points appropriate to the simulation type.
4. **Refinement** — boundary conditions, `GridSpec`, `run_time` (use `RunTimeSpec`), symmetry.
5. **Review** — final check before cost estimation.

Collapse phases when the user has provided enough information to cover multiple at once.

### run_time Guide

Use `td.RunTimeSpec(quality_factor=Q)`:

| Device type                                          | quality_factor |
| ---------------------------------------------------- | -------------- |
| Non-resonant (waveguides, couplers, splitters)       | 1              |
| Low-Q resonant (Bragg gratings, Fabry-Pérot)         | 10             |
| High-Q resonant (ring resonators, photonic crystals) | 200+           |

Never use `run_time="auto"` or `run_time=None` — these are invalid.

## Step 6: Simulation Inspection

- Add code to plot cross-sections using `sim.plot(z=...)` or `sim.plot(y=...)`.
- Instruct the user to run the plotting code and describe what they see.
- Check for errors or warnings; refer to the Troubleshooting workflow if found.

## Step 7: Cost Estimation

- Add cost estimation code: `web.estimate_cost(job.task_id)`.
- Ask the user to run it and report back before proceeding.
- **Never submit a job without an explicit cost confirmation.**

## Step 8: Run the Simulation

- Only if the user consents: provide the run code (`job.run(...)`) as a block they execute themselves.
- Never call `job.run()` without the user's explicit "yes, run it."

## Step 9: Analyze Results

- Suggest analyses based on the simulation type and available monitors.
- See `references/recommended-analyses.md` for the full list.
- If the user wants analysis, follow the Result Analysis workflow.

---

## Geometry Construction Decision Tree

_These are recommended defaults. Adapt based on device requirements and the installed Tidy3D version._

| Shape                    | Preferred approach                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------ |
| Rectangular prism        | `td.Box` or `td.Box.from_bounds` (verify `td.inf` support against installed version) |
| Cylinder / sphere / cone | `td.Cylinder`                                                                        |
| Straight taper           | `gdstk.RobustPath` + `td.PolySlab.from_gds()`                                        |
| S-bend                   | `gdstk.RobustPath` with parametric offset + `td.PolySlab.from_gds()`                 |
| Circular / arc bend      | `gdstk.RobustPath.arc()` + `td.PolySlab.from_gds()`                                  |
| Multi-segment waveguide  | `gdstk.RobustPath` with multiple segments                                            |
| Boolean combination      | `td.ClipOperation` or `gdstk.boolean()`                                              |
| Ring / annulus           | Two concentric `td.Cylinder` + `td.ClipOperation("difference")`                      |
| Custom polygon           | `td.PolySlab(vertices=...)` — last resort only; preview required                     |
| GDS import               | `td.PolySlab.from_gds(cell, ...)`                                                    |

**Construction hierarchy (try in this order):**
`gdstk.RobustPath` → `gdstk.FlexPath` → `td.ClipOperation` → `gdstk.boolean()` → `td.PolySlab(vertices=...)` as last resort.

Polygon quality rules _(recommended defaults — adjust for geometry complexity)_:

- Curved segments: minimum 50 vertices per curve.
- After `cell.get_polygons()`: if `len(polys[0]) < 20`, reduce tolerance.
- Bounding box must match expected physical dimensions within 10%.

See `references/gdstk-patterns.md` for verified code patterns.

## Geometry Guardrails

- Extend infinite structures (waveguides, substrates) beyond PML boundaries.
- All finite structures ≥ 0.5·λ_max from any PML face.
- All sources and monitors inside the simulation domain.
- Waveguide sources/monitors: size ≥ 6× cross-section; centered on waveguide core.
- No gaps between interconnected waveguide sections.
- Use `GeometryGroup` for groups sharing a medium.
- Use `Transformed` for mirror/rotate/scale.
- Variable names in the code body must match `params` declarations exactly.
