# Troubleshooting Workflow

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

1. Never delete a component to fix an error — diagnose and fix in place.
2. Read the full code and full error message before forming a hypothesis.
3. Verify the correct API before proposing a fix.
4. Apply one targeted fix at a time; confirm it resolves the issue before proceeding.
5. Describe the problem in physics terms when explaining it to the user.

---

## Geometry Guardrails (check these for geometry-related errors)

- All finite structures must be ≥ 0.5·λ_max from any PML face.
- Infinite structures (waveguides, substrates) must extend beyond PML boundaries.
- All sources and monitors must be inside the simulation domain.
- Waveguide sources/monitors: cross-section ≥ 6× waveguide cross-section, centered on core.
- No gaps between interconnected waveguide sections.

---

## Common Causes by Error Type

| Error | Most likely cause |
|---|---|
| `AttributeError` on result | Wrong data accessor — check `references/api-pitfalls.md` for the correct pattern |
| `ValidationError` on construction | Invalid parameter — `filter_pol`, `center` on PolySlab, `td.inf` in Box.from_bounds |
| Wrong `n_eff` values | `ModeSimulationData.n_eff` accessed directly — must use `.modes.n_eff` |
| Simulation finishes too fast | `run_time` too short for resonant device — use `RunTimeSpec(quality_factor=Q)` |
| Field energy doesn't decay | `shutoff` not reached — increase `run_time` or lower `shutoff` threshold |
| No resonance dips in spectrum | Ring not in domain, gap too large, or source not in bus waveguide |
| `KeyError` on monitor name | Monitor name mismatch — check `sim_data.monitor_data.keys()` |
