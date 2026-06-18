# Critical Geometry Inspection Protocol

> **Scope.** Applies to Learn / Debug / Build / Analysis.

Apply this checklist **every time you read back a cross-section plot or 3D render** — after `sim.plot(...)`, `sim.plot_3d()`, or any preview of custom geometry. This is not optional; the checks below catch the failures that no API verification will surface.

## The 6-Point Checklist

1. **Shape fidelity.**
   - Do all structures have the expected shape?
   - Are curves smooth, not polygonal?
   - Are edges clean?
   - Are interior angles correct (within 5° of expected values)?

2. **Dimensional check.**
   - Do bounding-box dimensions (x_min/x_max, y_min/y_max, z_min/z_max) match expected values within 10%?
   - Are aspect ratios correct?
   - A bounding box off by orders of magnitude indicates a units or coordinate error — stop and fix before continuing.

3. **PML extension** (for waveguides and substrates that should reach the domain boundary).
   - Do these structures appear flush with the simulation-domain faces in the cross-section?
   - If a structure visibly stops short of the boundary where it should extend into the PML, flag and fix — extend the structure beyond the domain so it penetrates the PML.

4. **Gaps and overlaps.**
   - No unintended gaps between structures that should be touching (especially at waveguide-to-junction interfaces).
   - No overlapping regions where two structures shouldn't co-occupy space.

5. **Completeness.**
   - All expected physical features present? Cross-check the rendered geometry and construction data against the blueprint.
   - Periodic features show the expected count of repeats (not collapsed to a single block). If repeats are represented by `td.GeometryArray`, count the intended copies from `offsets` / `transforms`, not just `len(sim.structures)`.
   - Tidy3D container count matches the blueprint's expected container inventory.

6. **Quantitative contour comparison** (when a reference image is in scope).
   - Vertex count matches the reference contour.
   - Interior angles within 5° of reference values.
   - Edge-length ratios within 10% of reference ratios.

   Visual agreement alone is not enough — if any quantitative metric is off, the geometry needs correction.

## Rules

- **If ANY check fails, fix before proceeding.**
- **Never say "looks correct" or "geometry is correct" without explicitly addressing each of the 6 points above.** Vague confirmations like "the shape looks good" are not acceptable. Describe what you specifically verified.
- After a fix, re-run the inspection. Do not move on to monitors / running with a failed inspection.

## Where to Use This

- Inside `protocols/post-build-audit.md` step 3.
- Whenever the user asks "what does the geometry look like?" — render, then run this checklist before describing.
- Before every cost estimate — sanity-check that what you're about to upload matches the intent.
