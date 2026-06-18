# Parameter Sweep Protocol

> **Scope.** Applies to Learn / Debug / Build / Analysis.

Follow this protocol whenever the user wants to sweep one or more parameters — from any scenario.

## Step 1 — Plan the Sweep

- Identify which parameter(s) to sweep and a reasonable range based on the physics. Examples:
  - Ring radius for FSR / Q tuning.
  - Coupling gap for critical coupling.
  - Grating pitch for centre-wavelength alignment.
- Verify the parameter is exposed in the simulation code as a top-level variable (not buried inside a helper). If not, refactor the script to lift it out first.
- Propose sweep range, number of points, and expected behaviour. Suggest coarse-first / refine-second when the range is wide or the cost per point is high.
- Stop and wait for the user to confirm the plan.

## Step 2 — Create the Batch

- Wrap the simulation in a `td.web.Batch(simulations={...}, ...)` keyed by descriptive task names. Task names follow `{param}_{value}` format (e.g., `radius_3`, `radius_5`, `width_0.4`) — this is the format `BatchData.items()` exposes during analysis.
- Sweeps work with any Tidy3D simulation type — FDTD, MODE, EME, etc. The Batch accepts any sim type.
- **Do not create a separate Job for a Batch** — Batch handles its own execution. **Do not create a duplicate** if a Batch for this sweep already exists.
- Briefly describe how many variants will be generated and which parameters are swept.
- Stop and wait for the user to confirm.

## Step 3 — Estimate and Run

- Route through `protocols/simulation-execution.md`. Call `batch.estimate_cost()` (the Batch equivalent of `web.estimate_cost(task_id)`). Total cost = sum of per-task estimates; report both per-task and aggregate.
- Apply cost controls before submitting: confirm symmetry, mesh, and frequency-point counts are reasonable; suggest reducing the sweep grid if the total cost is large.
- Get explicit user consent before `batch.run()`.

## Step 4 — Analyze the Sweep

Once results return, route through `workflow-analysis.md` with these sweep-specific suggestions:

- **Metric vs. swept parameter** — line plot of the key figure-of-merit (transmission, n_eff, loss, Q, etc.) against the sweep variable.
- **Optimal point** — find and annotate the swept value that optimizes the target metric.
- **Multi-metric overlay** — when multiple metrics matter (e.g., insertion loss + bandwidth), overlay them with a secondary y-axis.

When iterating over results, use the `BatchData` dict interface:

```python
for task_name, sim_data in batch_data.items():
    # task_name is e.g. "radius_3"; parse with task_name.split("_") if needed
    flux = sim_data["flux_monitor"].flux
    ...
```

Match the exact monitor names — wrong names cause `KeyError` at runtime.

## Cost Controls (apply at every step)

- Start coarse, downselect, refine. Never run a fine 50-point sweep before a coarse 5-point sweep tells you where the action is.
- Cap budgets — if the estimated total cost is large, propose a smaller grid and offer to refine after the user sees the coarse result.
- Reuse the same simulation object across the batch; do not rebuild geometry per task unless the swept parameter actually changes structure.
