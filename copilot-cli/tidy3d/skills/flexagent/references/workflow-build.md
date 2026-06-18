# Build Workflow

Use this workflow whenever the user wants to **create a new simulation** OR **modify an existing one**. State the mode as **Build** in your first response.

Behave like a photonics engineer setting up a design. Build incrementally with user feedback at the right gates — never dump a 300-line script for the user to discover errors in.

---

## Step 1 — Triage: Quick Modify vs. Full Build

Before doing anything else, classify the request:

- **Quick Modify** — pick this when the request targets a single known parameter or a small set of clearly-scoped values, there is no ambiguity about what to change, and no structural additions / removals are needed.
  Examples: *"Change the waveguide width to 500 nm"*, *"Set the wavelength to 1.31 µm"*, *"Increase `run_time` for the Bragg sim"*.

- **Full Build** — pick this when no simulation exists yet, the request adds new structures / sources / monitors, changes the simulation type or physics, is ambiguous, or the user explicitly asks for guidance.
  Examples: *"Build a ring resonator"*, *"Add a grating coupler to my script"*, *"Switch from strip to rib waveguide"*, *"Replicate the device in this paper"*.

The triage is internal — don't announce the chosen path to the user. If unsure, ask one clarifying question and stop.

---

## Step 2 — Quick Modify (skip if you picked Full Build)

1. Read the current code in full before changing anything. Never overwrite changes you haven't seen.
2. **Results already exist?** Check for saved result files, `SimulationData.from_hdf5(...)`, `web.load(...)`, bound `task_id` values, or previous `.run()` calls. If results exist and the change would require a re-run, route through `protocols/modify-existing-results.md` before editing.
3. Verify the API for the parameter you're touching via `tidy3d_search_flexcompute_docs` / `tidy3d_fetch_flexcompute_doc` (or by reading the installed Tidy3D source). Don't guess.
4. Apply the edit only after the results-preservation path is settled. Describe what you changed in physics terms ("Waveguide width is now 500 nm — n_eff will drop by ~0.05 at 1550 nm").
5. If the change affects geometry, regenerate the cross-section render and apply `protocols/geometry-inspection.md`.
6. Suggest the next action (re-estimate cost, refresh analyses, etc.).

Quick Modify does not need a blueprint, audit, or full phased build. Don't add ceremony where it's not needed.

---

## Step 3 — Full Build: Working Environment

Ask which file to work in:
- Existing Python script / notebook (ask for filename or path).
- New file — confirm `.py` vs `.ipynb`.

**Once a working file is chosen, production workflow code stays in it** — geometry, cost estimate, run, and analysis. Do not create sibling helper files (`_audit.py`, `_run_sim.py`, `_analyze.py`, …) for code the user is meant to keep. Audit and inspection code is agent scratch by default; see `protocols/post-build-audit.md` and `protocols/single-file-discipline.md`.

Use the closest available editing capability for the file type: notebook-cell edits for notebooks, inline text edits for scripts.

Ensure basic imports (`import tidy3d as td`, `import numpy as np`, `from tidy3d import web`) exist before writing simulation code. Don't try to auto-detect the Python environment.

---

## Step 4 — Full Build: Choose a Path

Pick the path matching the user's input. Check in this order:

| Path | Condition | First action |
|---|---|---|
| **Custom** | A standard photonic device is requested (ring resonator, MMI, grating coupler, etc.), no simulation exists yet, or the user wants a substantially novel structure | Docs search → structural blueprint → phased build |
| **Import** | User provides a layout file (`.gds`, `.stl`) | Ask user to identify cells / layers; import via `gdstk` and `td.PolySlab.from_gds()` |
| **Script** | User uploaded a `.py` / `.ipynb` containing simulation code | Read the script; identify intent; offer to adapt or run as-is |
| **Material Fit** | User uploaded a `.csv` / `.txt` with refractive-index / permittivity data | Inspect format; fit with `FastDispersionFitter`; report quality |

If a reference image is in scope, apply `protocols/image-analysis.md` **before** picking the path — the topology extraction may change whether the build is a standard-device Custom path or a novel-geometry Custom path.

---

## Custom Path

1. **Research.** Use `tidy3d_search_flexcompute_docs` for relevant examples and design patterns. Use `tidy3d_fetch_flexcompute_doc` to retrieve full runnable example code when a good match is found. Verify every Tidy3D class you plan to use — never rely on training-data memory.
2. **Structural blueprint.** Run `protocols/structural-blueprint.md`. Stop after presenting the blueprint; wait for confirmation before any code generation.
3. **Start Step 5 at Phase 1.** Build geometry first, then let the Phase 1 audit gate determine whether sources, monitors, and settings may be added.

---

## Import Path (GDS / STL)

1. **Inspect the file.** For GDS, list cell names and layer / datatype pairs. Ask the user which cell and which layers to import.
2. **Ask for missing parameters per layer.** Z-position (`z0`), extrusion thickness, material.
3. **Import blueprint.** Run `protocols/structural-blueprint.md` in import mode: enumerate the selected cell, selected layer / datatype pairs, extrusion bounds, material assignment, and expected imported polygon / structure inventory from file inspection. Stop after presenting the blueprint; wait for confirmation before any code generation.
4. **Import.** Generate code using `gdstk.read_gds(...)`, `lib.top_level()[0]` (or the user-selected cell), and `td.PolySlab.from_gds(cell, gds_layer=L, gds_dtype=D, axis=2, slab_bounds=(z0, z0+t))` for each layer.
5. Wrap into `td.Structure(geometry=g, medium=material)` for each imported polygon.
6. **Start Step 5 at Phase 1.** Use the imported geometry as Phase 1 of the Phased Incremental Build. Write only imported structures first; source, monitors, and settings come in later phases after the Phase 1 audit gate passes.
7. **Propagation note.** When the user later changes import parameters (selected layer, thickness), the simulation must be re-built downstream — point this out so they don't expect automatic propagation.

---

## Script Path (user-provided Python)

1. **Read the script in full.** Identify the simulation intent: device type, physics, structures, analysis. Never modify the file before the user has chosen a path below.
2. **Present two options. Stop and wait for the user's reply.**
   - *Adapt into a structured workflow.* Re-create the simulation following the appropriate path (Custom / Import / Material Fit) using the script as a blueprint. Useful when the user wants the agent to take ownership of the code structure.
   - *Run as-is.* Apply minor fixes only (broken imports, deprecated APIs) and execute via `protocols/simulation-execution.md`. Useful when the user wants their original code preserved.
3. Apply the chosen path.

---

## Material Fit Path

Follow `protocols/material-fit.md` — a four-step protocol (Plan → Fit → Report → Use) for converting tabular n/k or ε data into a `td.PoleResidue` medium via `FastDispersionFitter`. The protocol covers format detection, fit-range selection, RMS-anchored quality reporting, and handoff back into the Custom or Modify-existing build paths once the fit passes.

---

## Simulation-Type Defaults

Before applying Phase 1 defaults, identify the Tidy3D simulation type. Do not apply FDTD sources, monitors, PML, wavelength grids, or `run_time` defaults to non-FDTD simulations.

| Simulation type | Minimum build objects | Avoid |
|---|---|---|
| **FDTD** | `td.Simulation`, optical source (`PlaneWave`, `ModeSource`, `GaussianBeam`, etc.), wavelength / frequency grid, monitors, PML defaults, `td.RunTimeSpec` or positive `run_time` | `run_time="auto"` / `None`; cost-incurring run calls before the gate |
| **HEAT / CHARGE** | `td.HeatChargeSimulation`, heat / charge sources, temperature / carrier / electrical monitors, thermal or electrical boundary specs, material models appropriate to TCAD | FDTD optical sources, PML assumptions, optical `run_time` |
| **EME** | `td.EMESimulation`, ports, EME cells / `EMEGrid`, mode specs, propagation settings | FDTD optical source placeholders, FDTD monitors, FDTD `run_time` |
| **MODE** | Local mode-solver workflow when the user wants modal properties; cloud `ModeSimulation` only when the task specifically needs that surface | FDTD source placeholders, FDTD monitors, FDTD `run_time` |
| **SMATRIX** | Docs-backed S-matrix / component-modeler setup, ports / terminals, sweep settings, and result extraction matched to the selected API | FDTD source placeholders, FDTD monitors, FDTD `run_time` unless the docs-backed workflow explicitly uses an FDTD-backed setup |

When a non-FDTD type is requested and the exact class or argument names are unclear, verify against live docs or installed source before writing code. State the chosen simulation type in the blueprint so the audit uses the right inventory.

---

## Step 5 — Phased Incremental Build (sub-workflow)

Used by the Custom and Import paths. Build the simulation in phases, each ending with a visible result the user can confirm.

> **Guiding principle.** Use *all* the information the user has already provided. Only ask about what is genuinely missing. If the user gave geometry, source, and monitor details in one message, build with all of them — don't artificially split the phases.

1. **Phase 1 — Geometry.**
   Write the minimum type-appropriate code into the user's working file: structures, materials, an auto-fitted simulation domain with margin, and only the placeholder objects required for that simulation type. For FDTD, a single placeholder source, `td.GridSpec.auto(wavelength=...)`, and `run_time=td.RunTimeSpec(quality_factor=1)` are sensible defaults. For HEAT / CHARGE, EME, MODE, and SMATRIX, use the Simulation-Type Defaults table instead.
   Run `protocols/post-build-audit.md` for Custom path, Import path, or image-referenced builds. The audit owns the scratch-rendering mechanics; do not duplicate them here.
   Stop. Wait for confirmation.

2. **Phase 2 — Source & excitation.**
   Add the type-appropriate drive, excitation, or solve request. For FDTD, replace the placeholder source with the real one — type (PlaneWave / ModeSource / GaussianBeam), wavelength / frequency, placement, polarization, injection axis. For HEAT / CHARGE, add heat or charge sources and material specs. For EME, configure ports, mode injection, cells, and propagation settings. For MODE, configure the solve plane and mode spec rather than an optical source.
   Describe what changed in physics terms: *"Added a ModeSource at x = −5 µm, injecting the fundamental TE mode at 1550 nm."* For non-FDTD builds, use the equivalent domain language, such as the heat load, port excitation, or mode solve target.
   Stop. Wait.

3. **Phase 3 — Monitors & observables.**
   Add type-appropriate observables matched to the user's measurement intent. For FDTD, examples include `FluxMonitor` for transmission/reflection, `FieldMonitor` for field profiles, and `ModeMonitor` for mode-resolved transmission. For HEAT / CHARGE, EME, MODE, and SMATRIX, use the Simulation-Type Defaults table plus `references/recommended-analyses.md` rather than FDTD monitor defaults.
   Stop. Wait.

4. **Phase 4 — Refinement.**
   Type-appropriate boundary conditions, grid / discretization, termination settings, and symmetry where applicable. For FDTD only, PML defaults are usually fine, `td.GridSpec.auto` with wavelength is the default grid starting point, and `run_time` follows the FDTD `RunTimeSpec` guide below.
   Often this is a quick confirmation step. Stop. Wait.

5. **Phase 5 — Review & estimate.**
   Summarize the complete setup (structures, source, monitors, BCs, grid, run_time). Offer to estimate cost via `protocols/simulation-execution.md`.

**Collapsing phases.** If the user provided enough information to cover multiple phases at once, combine them. Example: *"silicon strip waveguide, 0.5 × 0.22 µm, ModeSource at 1550 nm, want transmission and field monitors"* → build geometry + source + monitors in one Phase 1, skip to Phase 4.

### FDTD `run_time` guide

For FDTD simulations, use `td.RunTimeSpec(quality_factor=Q)`:

| Device type | quality_factor |
|---|---|
| Non-resonant (waveguides, couplers, splitters, gratings, tapers) | 1 |
| Low-Q resonant (Bragg gratings, Fabry-Pérot cavities) | 10 |
| High-Q resonant (ring resonators, photonic-crystal cavities) | 200+ |

Never use `run_time="auto"` or `run_time=None` for FDTD — invalid. A hardcoded float in seconds is acceptable as a fallback but `RunTimeSpec` adapts to geometry. Non-FDTD simulation types have their own termination / solve semantics; verify those before writing code.

---

## Step 6 — Inspect, Estimate, Run, Analyze

1. **Inspect — automated scratch.** Reuse the latest passing Phase 1 `protocols/post-build-audit.md` result when the geometry is unchanged. Run `post-build-audit.md` here only if the current geometry has not been audited yet or changed after Phase 1. Don't write inspection code into the user's file and don't ask the user to run audit code on your behalf. For FDTD waveguides / substrates, verify PML extension (see `protocols/geometry-inspection.md` step 3).
2. **Estimate + run.** Route through `protocols/simulation-execution.md`. Never call `job.run()` without explicit consent at the cost gate.
3. **Analyze.** Once results return, route through `workflow-analysis.md`. See `references/recommended-analyses.md` for type-specific analysis suggestions.

If errors appear at any step, route through `workflow-debug.md`.

---

## Cross-Cutting Hooks

- Parameter sweeps → `protocols/parameter-sweeps.md`.
- Modifying a simulation with existing results → `protocols/modify-existing-results.md`.
- Image attached → `protocols/image-analysis.md`.
- Cost / consent → `protocols/simulation-execution.md`.
- API pitfalls catalog → `references/api-pitfalls.md` (consult before every code generation).
- Geometry construction patterns → `references/geometry-construction.md`.
