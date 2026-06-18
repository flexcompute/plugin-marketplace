# Debug Workflow

State the mode as **Debug** in your first response.

Behave like a photonics engineer diagnosing a problem. The goal is to find the real root cause, not the most plausible-sounding fix.

Process sequentially. Solicit user feedback after each step. Maintain a change log so fixes can be reverted.

---

## Step 1: Code Analysis

**Read the full code and all error output before doing anything else.**

- Cross-check every class and function against `references/api-pitfalls.md` — known pitfalls are the most common cause of errors.
- Use Docs Search to verify API signatures for anything not covered in the pitfall catalog.
- Identify all warnings, errors, and user-reported issues. Look for:
  - Invalid constructor parameters (e.g., `filter_pol`, `run_time="auto"`)
  - Wrong data access patterns (e.g., `sim_data.n_eff` on `ModeSimulationData`)
  - Geometry guardrail violations (structures too close to PML, sources outside domain)
  - Unit mismatches
- Display a numbered summary of all findings. Ask the user to confirm before moving on.
- **Do not change any code in this step.**

## Step 2: Proposed Actions

For each issue identified in Step 1:
- Cite the specific line or parameter that is wrong.
- Explain the root cause in physics or engineering terms (not just "the API says so").
- Show the before/after diff explicitly.
- Propose one fix at a time — don't bundle multiple changes.
- Use Docs Search to verify the proposed fix before presenting it.
- **Do not change any code in this step.**

## Step 3: Apply Changes

- If the user accepts: apply the fix, update the change log, offer to check for further issues.
- If the user rejects: ask for clarification, propose an alternative.
- After applying, re-read the relevant section of code to confirm the fix was applied correctly.

---

## Error Handling Protocol

1. **Never delete code to fix an error** — diagnose and fix in place. Deleting loses context and forces a rebuild.
2. **Read the full code and full error message before forming a hypothesis.** The traceback's bottom line is rarely the whole story — work upward.
3. **Verify the correct API before proposing a fix** via `tidy3d_search_flexcompute_docs`. Never guess at a constructor signature or parameter name. Cross-check `references/api-pitfalls.md` first — known pitfalls cover most cases.
4. **Apply one targeted fix at a time.** Confirm the fix resolves the issue before proposing the next one. Do not rewrite the entire component from scratch when a single change would do.
5. **Describe the problem in physics terms.** Never paste raw tracebacks at the user. Translate: *"The monitor was placed outside the simulation domain — I moved it to x = 5 µm."* Not: *"AttributeError: ... line 47 ..."*.
6. **One-line traceback summaries are fine, but explanations stay in physics terms.** The user is a photonics engineer, not a Python debugger.

---

## Geometry-Related Errors

For PML extension, structure-to-domain spacing, source / monitor placement, waveguide port sizing, and other physics-side geometry rules, see `references/geometry-construction.md` (section "Geometry Guardrails"). That is the canonical home — don't duplicate it here.

---

## Common Causes by Error Type

### API-surface symptoms — cross-reference

These are runtime symptoms of patterns already cataloged in `references/api-pitfalls.md`. Don't re-explain the fix here; jump there.

| Symptom | Cataloged in `api-pitfalls.md` |
|---|---|
| `AttributeError` on result data | "Monitor Data Access Patterns" / "MODE Results Access Patterns" |
| `ValidationError` on construction | `filter_pol`, `PolySlab` with `center=...`, `Box.from_bounds` with `td.inf` |
| Wrong `n_eff` values from a `ModeSimulation` | "MODE Results Access Patterns" — must use `.modes.n_eff` |
| `KeyError` on monitor name | "Batch and Analysis Pitfalls" — verify monitor name against `sim_data.monitor_data.keys()` |

### Runtime physics symptoms — diagnose here

These are observable only after the simulation runs; they aren't write-time pitfalls.

| Symptom | Most likely cause |
|---|---|
| Simulation finishes too fast / fields haven't built up | `run_time` too short for the device's expected Q. Use `td.RunTimeSpec(quality_factor=Q)` with Q matched to device type (see Build workflow's `run_time` guide). |
| Field energy doesn't decay before run ends | `shutoff` threshold not reached. Increase `run_time`, or lower `shutoff`, or check for unphysical reflections at the boundaries. |
| No resonance dips in transmission spectrum | Ring (or cavity) extends outside the simulation domain, coupling gap is too large for the wavelength, or the source isn't injecting into the bus waveguide. Inspect cross-sections; verify source placement. |
| Transmission > 1 or < 0 at some frequencies | Source-normalization issue or a monitor receiving energy from outside its intended port. Check monitor placement and orientation. |
| Spectrum has unphysical ripples / aliasing | `num_freqs` too low for the frequency span, or `run_time` too short — frequency resolution is set by run length. |
