# Image Analysis Protocol

Follow this protocol whenever the user attaches an image to a message — schematic, paper figure, photo, error screenshot, or 3D model render. Images carry concrete information that must be extracted and carried into the build, not ignored or paraphrased.

## Step 1 — Identify the Image Type and Mode

Classify the image and state the resulting scenario:
- **Device schematic / cross-section diagram** → Build (Custom path).
- **Paper / reference figure** → Build, with mandatory Reference Image Comparison below.
- **Simulation result plot** (field maps, spectra, mode profiles) → Analysis or Debug.
- **Error screenshot** → Debug.
- **3D model from another tool** → Build, with topology extraction.

## Step 2 — Extract Information

Extract everything the image visibly contains. Three layers:

1. **Parameters.** Device type, dimensions, materials, BCs, monitor placements, wavelength ranges, source types, simulation parameters. Collect into a parameter map: `{"wg_width": 0.5, "wg_length": 10.0, "wavelength": 1.55, ...}`.

2. **Structural topology.**
   - Count distinct geometric structures visible.
   - Identify repeating / periodic features and estimate count ("~25 grating teeth at ~0.63 µm pitch").
   - Identify layer stack (substrate, cladding, device, oxide).
   - Note curved vs. straight features per structure.

3. **Ambiguities.** Anything not clearly readable. Ask focused follow-ups before guessing.

## Step 3 — Never Hallucinate

- If a value is not clearly readable, **ask the user**. Do not guess.
- If units are ambiguous (nm vs µm), ask before proceeding.
- This rule overrides every "be concise" / "build fast" instruction. A wrong dimension costs more than a clarifying question.

## Step 4 — Carry Values Into the Build

When the conversation proceeds to building:
- **Custom path**: incorporate extracted values directly into the geometry / source / monitor code during the Phased Incremental Build (Phase 1).
- **Modifying existing setup**: edit with the extracted values; follow `protocols/modify-existing-results.md` if results already exist.

## Step 5 — Structural Blueprint (mandatory for image-referenced builds)

Every image-referenced build must run `protocols/structural-blueprint.md`. The extracted topology from step 2 is the blueprint's starting point. Expand it into the full blueprint: geometry types, materials, construction methods, and expected structure count.

## Step 6 — Reference Image Comparison (after every preview / render)

When a reference image is in scope, run this checklist after every `sim.plot(...)` or 3D render:

1. **Identify the reference.** State explicitly: *"Comparing against reference image provided by user."*
2. **Checklist comparison.** For each property, state **MATCH** or **MISMATCH** with a one-line explanation:
   - Overall shape / outline (vertex count vs. reference contour).
   - Number of distinct geometric regions / layers (component count).
   - Angles and symmetry (interior angles vs. reference, within 5°).
   - Relative proportions (edge-length ratios vs. reference, within 10%).
   - Edge quality (no zig-zag artifacts, jagged edges, or boolean-junction teeth).
   - Junction quality (clean transitions where shapes meet).
   - Layer stacking order.
   - Periodic feature count.
3. **Verdict.** A MATCH requires both visual and quantitative agreement. If any property is MISMATCH, fix it before proceeding — state exactly what you will change (which vertices, angles, dimensions) and apply the edit. Re-run the comparison after the fix.
4. **Zoom-in verification.** After a full-shape comparison passes, render again with axes zoomed into junction regions or areas of concern to catch artifacts invisible at full scale.
5. **Iteration limit.** If the geometry still doesn't match after 3 iterations, stop and present the comparison to the user for guidance — do not keep iterating blindly.

## Rule

**Never** say "I need to refine the geometry" and proceed without actually refining. If a MISMATCH is identified, the fix must happen in the same turn.
