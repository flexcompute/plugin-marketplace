# Post-Build Structural Audit

> **Scope.** Applies to Learn / Debug / Build / Analysis.

After writing simulation code that follows a structural or import blueprint, audit the result before moving on to source / monitors / running.

## When This Applies

Same scope as `protocols/structural-blueprint.md` — the Custom path, Import path, image-referenced builds, and modifications that add new structures.

## Procedure

1. **Render cross-section plots — automated agent scratch, not in the user's file.**

   The audit render is **agent scratch** per `protocols/single-file-discipline.md` — the user doesn't need to keep the rendering code, they just need the verdict. Do not write the audit code into the user's notebook or script.

   - **Create scratch code outside the user's project** (for example, a temporary file under `/tmp/` when local command execution is available) containing:
     - The geometry-building code (copy / replicate from what you just wrote into the user's file — usually a short block).
     - `import matplotlib; matplotlib.use("Agg")` (headless).
     - `sim.plot(z=...)`, `sim.plot(y=...)`, `sim.plot(x=...)` for the relevant planes; save each via `plt.savefig("/tmp/audit_<plane>.png", dpi=120, bbox_inches="tight")`.
     - Print the container count and any repeated-feature counts needed by the blueprint. For `GeometryArray`, print the array length from `offsets` / `transforms` or an explicit variable used to build the array.
   - **Execute** with the available local command runner. Capture stdout + stderr.
   - **Inspect the generated PNGs** with the available image-viewing capability. Inspect all relevant planes.
   - **Delete scratch code and generated PNGs** after inspection. They're audit artifacts, not user data.
   - **Report only the verdict to the user** in physics terms (*"verified 25 grating teeth at 0.63 µm pitch; layers stacked correctly at z = −2 µm and z = −10 µm"*). The user doesn't see the scratch code or the PNGs.
   - **If the user explicitly asks** to keep the audit code in the notebook / script (e.g., *"I want to re-render this later"*), then promote it from scratch to production using the available notebook or script editing capability. The default is scratch.
   - **If execution fails** (`ModuleNotFoundError`, `tidy3d` missing, etc.) — report what's missing and stop. First diagnose (is the tidy3d env activated? `which python`, `python -c "import tidy3d"`). If genuinely unable to execute, surface as a setup blocker, not a user task.

2. **Verify structural inventory.** Compare the generated code to the blueprint's expected inventory:
   - **Physical-feature inventory** — each repeated feature appears the expected number of times in the rendered geometry or in the construction data. For `GeometryArray`, count the intended physical copies from `offsets` / `transforms`; do not reject the build just because those copies live inside one `Structure`.
   - **Tidy3D container inventory** — `len(sim.structures)` (or `len(scene.structures)` for a separately-built `td.Scene`) matches the expected container count from the blueprint.
   - **Mismatch** → the build is wrong. Report the mismatch in physics terms, identify which features or containers are missing or duplicated by name, and rebuild. Do not proceed.

3. **Inspect cross-sections for correctness.** Apply `protocols/geometry-inspection.md` to each captured PNG:
   - Periodic features visible and evenly spaced (not a single block).
   - Curved shapes are smooth (no visible polygonal vertices or jagged edges).
   - Layers stacked in the right order at the right heights.

4. **Reference-image comparison.** If a reference image is in scope, also apply the comparison checklist in `protocols/image-analysis.md` (vertex count, interior angles within 5°, edge-length ratios within 10%).

5. **Audit pass.** Describe what you verified to the user — specifically, not vaguely. Acceptable: *"Verified 25 grating teeth evenly spaced at 0.63 µm pitch, BOX and substrate layers stacked correctly at z = −2 µm and z = −10 µm."* Not acceptable: *"Geometry looks good."*

6. **Audit fail.** Diagnose, fix via edit (not by deleting and rebuilding from scratch), and re-run the audit. Do not move on to monitors / running with a failed audit.

## Rule

"Quick Build" means "build it correctly fast", not "skip verification." Even when the user picks a fast path, the audit is non-negotiable for any custom build, imported layout build, or image-referenced build.
