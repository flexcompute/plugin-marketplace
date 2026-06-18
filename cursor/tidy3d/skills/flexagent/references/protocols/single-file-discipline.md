# Single-File Discipline

> **Scope.** Applies to Learn / Debug / Build / Analysis.

**Rule.** Everything you write for the user stays in the **one working file they chose** at the start of the task — script (`.py`) or notebook (`.ipynb`). Do not spawn sibling helper files (`_audit.py`, `_run.py`, `_analyze.py`, …) to host audit, render, estimate, run, or analysis code.

**Why.** Sibling helper files create three problems:
1. **Drift.** Analysis logic in `_analyze.py` and the user's notebook will diverge the moment either is edited; one becomes silently stale.
2. **Useless notebook.** If the user chose a notebook, the notebook is meant to be the durable record of setup + results. Moving execution and analysis into `.py` siblings leaves the notebook as a half-finished sketch.
3. **Lost provenance.** A single self-contained file lets the user (or a future reader / reviewer) see *exactly* what was built and ran. Scattered files require navigating a tree to reconstruct it.

The user's file is the canonical record. Treat it that way.

---

## Notebook (.ipynb)

- **Edit cells with the available notebook-editing capability.** Add a cell, modify a cell, or insert at a specific position. Do not rewrite the whole notebook unless asked.
- **Cell layout.** Use markdown cells to title each phase (*"## Geometry"*, *"## Source"*, *"## Cost estimate"*, *"## Run"*, *"## Analysis"*) and code cells underneath. The notebook should read top-to-bottom as the full story.
- **Execution.** Execute production notebook cells only when the user has asked you to run them or the workflow requires local validation. Use the available notebook/kernel execution path or local notebook execution support; inspect saved outputs with the available file or image-reading capability.
- **Never write a sibling `.py` to drive the notebook.** The notebook drives itself.
- **Do not put audit scratch cells in the notebook by default.** `protocols/post-build-audit.md` owns the scratch-render workflow. Add reusable audit / plotting cells only when the user explicitly asks to keep them.

## Script (.py)

- **Edit with the available script-editing capability.** Append, modify, or insert in place.
- **Section the script** with comment headers (`# ----- Cost estimate -----`, `# ----- Run -----`) so its top-to-bottom flow matches the workflow phases.
- **Execution.** Run via `python <file>.py` once it's at a runnable state. Capture stdout / stderr; inspect any generated artifacts (PNGs, HDF5 metadata) with the available file or image-reading capability.
- **Never split** the simulation, the cost estimate, and the analysis into three sibling scripts. They all belong in one file (or one notebook).

## After the Cost Gate

When the user grants explicit consent at the cost gate in `protocols/simulation-execution.md` — *"Yes, run it"* — write the run call cleanly into the working file. **Do not leave it as `# sim_data = job.run(...)` with a `# Uncomment to run after reviewing cost above` placeholder.** The consent already happened in the conversation; the file should reflect the executed state, not a half-armed checkpoint.

This rule applies symmetrically to *before* the consent: do not generate uncommented run code in the file before the user has explicitly approved. Add it once, with the user's approval, and leave it there.

## Narrow Exceptions

Sibling files are acceptable only when the user **explicitly asks for them**:
- *"Pull this helper into a reusable module"* → fine, create `utils.py` or similar.
- *"Save the post-processing as a separate script I can rerun"* → fine.
- User chooses the **New chain** path in `protocols/modify-existing-results.md` → fine, copy the original script to a new filename and treat that copy as the single working file for the new run.

Without an explicit ask, default to one file.

## What This Doesn't Cover

### Generated artifacts

PNGs, HDF5 result files, GDS exports — these are outputs, not source code. They live outside the working file (in the project directory or `/tmp/`). This protocol governs **executable code placement the user is meant to keep**, not generated data.

### Agent scratch — exempt from the single-file rule

The rule covers **production code the user keeps**: geometry, sources, monitors, simulation, upload, cost estimate, run, analysis. These all go in the working file.

It does **not** cover ephemeral inspection / verification / sanity computation the *agent* does as part of its workflow. That kind of code is throwaway — the user never needs to read it or re-run it. Examples:

| Scratch use case | Typical mechanics |
|---|---|
| Geometry audit render — agent checks `sim.plot(z=...)` matches the blueprint before continuing | Build the sim in scratch code outside the project, save the PNG, inspect it, delete the scratch |
| API introspection — verifying a constructor signature, exploring a method's return type | `python -c "import tidy3d as td; help(td.GridSpec.auto)"` |
| Numerical sanity check — *"is this `n_eff` plausible?"*, *"how many vertices does this polygon have?"*, *"what's the bounding box of this gdstk path?"* | `python -c "..."` one-liner |
| Reading a `.hdf5` to discover available monitor names before writing analysis code | `python -c "import tidy3d as td; d = td.SimulationData.from_hdf5('x.hdf5'); print(list(d.monitor_data.keys()))"` |

Scratch code is **ephemeral by default**: temp file in `/tmp/`, or `python -c "..."`, or — if you wrote to a sibling file for tractability — `rm` it after reading the result.

**Don't promote scratch into the user's file.** If you used a scratch render to verify geometry, just confirm to the user in chat (*"verified 25 grating teeth at 0.63 µm pitch"*) — don't paste the audit code into their notebook unless they ask.

**Don't promote production into scratch either.** The cost estimate, the run call, the analysis plot — these are part of the user's workflow record and stay in their file.
