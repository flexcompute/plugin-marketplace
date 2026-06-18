# Cloud Execution Protocol

> **Scope.** Applies to Learn / Debug / Build / Analysis.

Follow this protocol whenever Tidy3D code will trigger **cloud compute** — from any scenario, regardless of the API entry point used. The cost-estimate / consent gate is the same for all of them.

## Scope — Which API Calls Are Gated

**Gated** (cost is incurred when these execute). Every one needs an estimate + explicit user consent before running:

- `td.web.run(sim, task_name=...)` — shorthand that uploads + starts + downloads in one call.
- `td.web.run_async(sim, task_name=...)` — async equivalent of the above.
- `td.web.Job(simulation=..., task_name=...).run()` — explicit single-job pattern.
- `td.web.Batch(simulations={...}, ...).run()` — sweep / batch pattern.
- `td.web.start(task_id)` — starts a task that was previously uploaded with `td.web.upload(...)`.
- `ModeSolver(...).run()` — cloud mode solve (distinct from local `ModeSolver.solve()` — see below).
- Any helper wrapping the above (`run_async` variants, custom utilities).

**Not gated** — these are upload-only, query-only, or local-only and do not initiate compute:

- `td.web.upload(sim, task_name=...)` — uploads the spec; no compute starts.
- `td.web.estimate_cost(task_id)` — returns cost; no compute.
- `td.web.load(task_id)` / `td.web.get_info(task_id)` / `td.web.monitor(task_id)` — read-only.
- `td.web.delete(task_id)` — gated only in the sense that destructive operations need user confirmation (see Destructive Operations below).
- `ModeSolver(...).solve()` — local mode solve, no cloud.
- All plotting, validation, and `td.Simulation.from_*` / `.to_*` methods.

## Steps

Apply these in order. Skipping any step before consent is a hard violation.

1. **Identify the execution pattern.** Is the user's code (or the code about to be written) using the shorthand `td.web.run(...)`, an explicit `Job` / `Batch`, or upload+start split? Each takes slightly different handling at step 6.

2. **Check for existing tasks.** Search the user's file and any related sibling files for an already-uploaded `task_id`, an existing `Job` / `Batch` bound to the target simulation, or a previous `.run()` call. Do not duplicate. If a task already ran and the user wants to re-run with changes, route through `protocols/modify-existing-results.md` first.

3. **Ensure a `task_id` exists before estimating.** `td.web.estimate_cost(task_id)` requires a task that has been uploaded.
   - For `Job` / `Batch`: instantiate the object first (uploading happens implicitly when needed); the `task_id` is on `job.task_id` or per-task in the Batch.
   - For the upload+start split: generate the `td.web.upload(...)` call now (or run it with the available local execution capability if execution is granted) so the task_id is available for the estimate.
   - For the shorthand `td.web.run(sim)` / `run_async(sim)`: **do not write this call yet** — it would auto-start compute. Refactor temporarily into `upload` + `estimate_cost` + `start`, OR use the `Job(...)` pattern, so the estimate can be gated separately.

4. **Estimate cost.** Generate / run:
   - `td.web.estimate_cost(task_id)` for single tasks.
   - `batch.estimate_cost()` (aggregated) plus per-task breakdown for sweeps.
   - Translate any `ValidationError`, `ValidationWarning`, or unexpected errors into physics terms before showing the user. Raw tracebacks stay out of the chat.

5. **Present cost + warnings, then STOP for consent.** Report:
   - Aggregate cost in FlexCredits.
   - Expected runtime (rough order of magnitude is fine when the API provides it).
   - Any warnings from the estimate.
   - For a Batch: per-task cost too, so the user can spot outliers.

   Wait for an explicit *"yes, run it"* (or equivalent) in direct response to this estimate and warning summary. That approval remains valid for Step 6 in the next assistant turn. **Never** reuse approval that predates the current estimate, broad *"just run it"* shortcuts before the estimate, or implicit approval.

6. **Run — pick the right form for the pattern.**

   Write the run call **cleanly into the user's working file** (see `protocols/single-file-discipline.md`) — same notebook cell or same script as the rest of the workflow. **Do not leave a commented placeholder** like `# sim_data = job.run(...)  # Uncomment to run after reviewing cost`. The consent gate happens in the *conversation*, not by leaving half-armed code in the file. Once the user has approved, the code goes in active; before approval, it doesn't go in at all.

   | Pattern at step 1 | What to write / run at step 6 |
   |---|---|
   | Single `Job` | `job.run()` |
   | `Batch` | `batch.run()` |
   | Upload+start split | `td.web.start(task_id)` |
   | Shorthand requested by user, gate already satisfied | `td.web.run(sim, task_name=...)` — acceptable now, because the estimate + consent already happened. Same for `run_async`. |
   | `ModeSolver` cloud run | `mode_solver.run()` (only after estimate gate — `ModeSolver` solves on the cloud unless the user used `.solve()` for local) |

   Stream progress info back from stdout; describe what's happening in physics terms.

7. **Post-completion.** Once the run finishes, route through `workflow-analysis.md` to inspect results and suggest analyses.

## Hard Rules

- **Never write or execute** `td.web.run(sim)` / `td.web.run_async(sim)` / `td.web.start(task_id)` / `job.run()` / `batch.run()` / `mode_solver.run()` (cloud) **without an estimate and explicit consent tied to that exact estimate** in the same conversation turn or the prior turn's gate.
- **Never skip the estimate.** Cost surprises are the user's #1 complaint about cloud runs.
- **Never silently refactor** a user's `td.web.run(sim)` call into a started form — explain the refactor (you're splitting it so the cost can be gated) and apply it transparently.
- `td.web.estimate_cost()` requires a `task_id`, not a simulation object. Upload first.
- Local `ModeSolver.solve()` is exempt — no cloud, no gate.
- Re-running a modified simulation? Route through `protocols/modify-existing-results.md` *before* invoking this protocol.

## Destructive Operations

`td.web.delete(task_id)`, `td.web.abort(task_id)`, and similar lifecycle calls don't trigger compute, but they are destructive — get explicit user consent before generating or executing them. Same rule as for `rm -rf` in any other tooling.

## v2.11 Execution Notes

- **Local cache is on by default.** `td.config.local_cache.enabled = True` since v2.11.0. Repeated identical submissions hit the local cache and return cached results without re-running on the cloud — this is great for iterative development but can mask "did my edit actually take effect?" questions. For benchmarking or when verifying a fresh run, disable explicitly: `td.config.local_cache.enabled = False`. Cache contents can be inspected with the CLI: `tidy3d cache info` / `tidy3d cache list` / `tidy3d cache clear`.
- **Parallel adjoint execution.** For dedicated adjoint workflows, `td.config.adjoint.parallel_run = True` runs adjoint sims in parallel where eligible — up to 2× faster gradient calculations. Not relevant to non-adjoint Build / Debug / Analysis work.
- **`vgpu_allocation` parameter.** v2.11 added `vgpu_allocation` to `web.run`, `web.run_async`, `Job`, and `Batch`. Leave it unset by default — the standard cost-gate flow above is sufficient for FlexCredits and most users. **Only consult `protocols/vgpu-submission.md` when the user explicitly mentions vGPU, Reserved vGPU, Time-Shared vGPU, or GPU-Hours.** Pulling vGPU semantics into a non-vGPU conversation only adds noise.
