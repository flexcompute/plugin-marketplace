# Cloud Execution Protocol

> **Scope.** Applies whenever Tidy3D code can start cloud compute. The estimate and consent gate is mandatory regardless of the API surface or billing method.

## Calls That Need the Gate

The following operations can start paid or quota-consuming work:

- `web.Job(...).run()` and `web.Job(...).step()`
- `web.Batch(...).run()`
- `web.run(...)` and `web.run_async(...)`
- `web.start(task_id)` after a separate upload
- wrappers around any of those calls

This includes non-FDTD work submitted through the web API. For example, a cloud mode solve uses a `web.Job(simulation=mode_solver, ...)`; do not invent a `ModeSolver.run()` method. A local `ModeSolver.solve()` does not use cloud compute, but verify that the installed API and the user's requested execution surface still make it local before treating it as exempt.

Read-only operations such as loading task information, monitoring an existing task, or estimating cost do not start compute. Uploading prepares a task but does not start it. Deleting or aborting a task does not incur compute, but it is destructive and still requires explicit confirmation.

## Single-Step Jobs

1. **Identify the submitted object and execution surface.** Verify the installed signature before writing code. `web.run_async` is a collection-oriented API in current releases; do not assume it has the same arguments as `web.run`.
2. **Reuse existing work.** Search the user's code for task IDs, `Job` or `Batch` objects, saved results, and earlier run calls. Route modified simulations with existing results through `modify-existing-results.md` before creating another task.
3. **Create an estimable task without starting it.** Prefer `web.Job(simulation=..., task_name=...)` for one simulation. The submitted object may be an FDTD simulation, a cloud `ModeSolver`, or another type accepted by the installed `Job` API. For an upload/start flow, call `web.upload(...)` to obtain a task ID. Do not call a run shorthand just to obtain an estimate.
4. **Estimate.** Use `job.estimate_cost()` when the live `Job` API provides it, `web.estimate_cost(task_id)` for an uploaded task, or `batch.estimate_cost()` for a batch. Verify the exact return shape before extracting totals or per-task values.
5. **Report and stop.** Show the FlexCredit estimate, any available runtime or quota estimate, and warnings. Then end the turn. Approval must be an explicit response to this exact estimate; an earlier “just run it” is not consent.
6. **Run only after consent.** In the next turn, add or execute the active `job.run()`, `batch.run()`, `web.start(task_id)`, or already-gated shorthand. Do not leave commented run calls for the user to arm manually.
7. **Analyze the completed result.** Route the saved or returned data through `workflow-analysis.md`.

Use the maintained [Job documentation](https://docs.flexcompute.com/projects/tidy3d/en/latest/api/_autosummary/tidy3d.web.Job.html) and [cost-estimation guidance](https://docs.flexcompute.com/projects/tidy3d/en/latest/faq/docs/faq/how-do-i-estimate-the-cost-of-running-a-simulation.html) when the installed API is unclear.

## Multi-Step Jobs

Some submitted objects have more than one cloud step. Cost estimates for these jobs can describe only the next incomplete step. Consent for one estimate therefore authorizes only that step.

Use a separate conversation turn for every gate:

1. Call `job.estimate_cost()` for the next incomplete step, report the step and estimate, then **stop**.
2. After explicit consent, call `job.step()` exactly once. Do not use `job.run()` and do not put estimate-and-step in a Python loop.
3. If another step remains, estimate it, report it, and **stop again** for new consent.
4. Repeat until the job is complete, then analyze the result.

Persist or reload the `Job` between turns if the runtime requires it. Never reinterpret approval for one step as approval for the rest of the workflow.

## Batch and Sweep Details

- Report aggregate and per-task estimates so outliers are visible.
- For a multi-step batch, state which next step the estimate covers. Re-estimate after completing it.
- Keep task names and result paths stable so retries do not create duplicate work.
- If billing changes between vGPU and FlexCredits, re-estimate before running. Consult `vgpu-submission.md` only when the user explicitly asks about vGPU or GPU-Hours.

## Hard Rules

- Never write or execute an active cloud run call without an estimate and explicit consent tied to that estimate.
- Never skip an estimate because a similar job ran before, a local cache may exist, or the user asked for speed.
- Never silently replace the user's execution pattern. Explain a temporary `Job` or upload/start refactor when it is needed to create a safe estimate gate.
- Keep production execution code in the user's chosen script or notebook. Scratch probes remain temporary.
- Translate validation and execution failures into physics terms; do not paste raw tracebacks.

## Destructive Operations

Get explicit confirmation before `web.delete(task_id)`, `web.abort(task_id)`, overwriting saved results, or similar lifecycle operations. These calls are not cost-gated, but they can destroy recoverable work.
