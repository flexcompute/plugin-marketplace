# Customize a Simulation Setup Workflow

Behave like a photonics engineer extending an existing design. The goal is to make the requested change cleanly without breaking what already works.

Process sequentially. Solicit user feedback after each step. Maintain a change log so the user can revert.

---

## Step 1: Request Analysis

**Read the current simulation code in full before proposing anything.**

- Use Docs Search to verify the APIs relevant to the requested change.
- Identify all dependencies: does the change affect downstream structures, sources, monitors, or analyses?
- Confirm your understanding: state what the simulation currently does, what the user wants to add or change, and any constraints you observe.
- If the request is ambiguous (e.g., "make it faster"), ask one clarifying question.
- **Do not change any code in this step.**

## Step 2: Proposed Actions

- Explain the change and show exactly what will be added or modified (diff-style).
- Apply **Geometry Guardrails** if structures or monitors are being moved or resized.
- Use Docs Search to verify any new API calls.
- Don't bundle multiple changes — propose the smallest unit that makes sense.
- **Do not change any code in this step.**

## Step 3: Apply Changes

- If accepted: apply, update the change log, offer improvements.
- If rejected: ask for clarification.
- After applying, re-read the modified code to confirm correctness.

---

## Common Customization Patterns

### Adding a Parameter Sweep
Use `td.web.run_async` or `BatchData` for parallel sweep execution. Start with a coarse sweep (3–5 points), find the interesting region, then refine. Batch task names must use underscore format: `"width_0.4"` not `"width=0.4"`.

### Adding Mode Analysis
Add `td.ModeMonitor` at relevant cross-sections. After the simulation, access amps via `sim_data["mon"].amps.sel(direction="+", mode_index=0)`. See `references/api-pitfalls.md` for monitor data access patterns.

### Improving Mesh Resolution
Use `td.MeshOverrideStructure` to refine specific regions. Verify that tighter resolution doesn't push cost above budget — re-estimate after adding overrides.

### Adding Symmetry
Check all sources and geometry for symmetry compatibility. TE mode in a symmetric structure: symmetry `(0, 1, 0)` (Ey symmetric). Confirm the symmetry plane doesn't bisect any asymmetric feature.

### Adjoint / Optimization
Never run optimization loops without explicit user approval and budget confirmation for the full batch of solves.

---

## Geometry Guardrails

- All finite structures ≥ 0.5·λ_max from any PML face.
- Sources and monitors must remain inside the simulation domain after edits.
- No gaps between interconnected waveguide sections.
- Variable names in the code body must exactly match names declared in `params`.
