# Modifying a Simulation With Existing Results

> **Scope.** Applies to Learn / Debug / Build / Analysis.

When the user asks to change a simulation that has already been run — meaning result data exists somewhere accessible (a `.hdf5` file in the workspace, a cached `web.load(task_id)` result, an open `SimulationData` variable, or a `td.web.Job` whose `task_id` is bound in the script) — do not silently overwrite. The results may have taken hours of compute and cost real FlexCredits.

## When This Applies

- The user explicitly asks to "modify" / "change" / "tweak" a simulation that previously ran.
- The script contains a `SimulationData.from_hdf5(...)` / `web.load(...)` call referencing an existing results file.
- An analysis based on a previous run already exists in the workspace.

## Procedure

1. **Detect.** Confirm results exist. Check for: `.hdf5` files in the workspace named after the task, a `data_var` already populated from a previous run, or job-id references in the script.

2. **Ask the user before changing anything.** Present two options and STOP — wait for the user's reply before editing or re-running:

   - **Override** — apply the edit in place, re-run the simulation, and replace the existing results. Old results are lost.
   - **New chain** — keep the original simulation and results untouched. If the user chooses this path, create a copy of the script (e.g., `<name>_v2.py`) and treat that copy as the chosen working file for the new run, not as a helper script. Apply the modifications there, run it separately, and produce parallel results so the user can compare.

   Use plain language: *"You have results from the previous run saved in `sim_data.hdf5`. Do you want me to (a) override — re-run with the new parameters and replace the existing results, or (b) create a parallel chain — copy the script to compare both setups side by side?"*

3. **Apply the chosen path.**
   - **Override path**: edit the existing script. Then route through `protocols/simulation-execution.md` for the re-run (estimate → consent → run).
   - **New chain path**: copy the existing script to a new filename only after the user chooses this option. The copy becomes the one working file for the new chain; apply the modifications there and route it through `protocols/simulation-execution.md`. Keep the original untouched.

4. **Pre-run analyses.** If analyses (custom plots, computed metrics) depended on the previous results, flag them as **stale** after an override — they reference data that no longer matches the current setup. Offer to refresh them after the new run completes.

## Edge Case — Simulation Not Yet Run

If the script defines a `Job` / `Batch` but it has not been uploaded or run yet (no `task_id` populated, no result file), there are no results to protect. Apply the edit in place without asking.

## Rule

Never override a successful run without explicit consent. The data is the user's, not yours.
