# vGPU Submission Protocol

> **Scope.** Apply this protocol **only when the user explicitly mentions "vGPU", "Reserved vGPU", "Time-Shared vGPU", "GPU-Hours", or asks about Flexcompute's pre-paid GPU licensing**. Generic `web.run` / `Job` / `Batch` submissions follow `protocols/simulation-execution.md` — they don't need this protocol. License type is account state; most users on FlexCredits never see vGPU, and pulling the vGPU material into a non-vGPU conversation only adds noise. If unsure whether a user is on a vGPU license, ask before quoting allocation tiers or daily-budget mechanics.

A **vGPU license** is Flexcompute's pre-paid alternative to per-simulation FlexCredit billing. The customer purchases a slice of high-end GPU capacity and runs Tidy3D jobs against that capacity instead of consuming FlexCredits per run. Two flavours exist: **Reserved vGPU** (full capacity 24/7) and **Time-Shared vGPU** (daily GPU-Hour allowance, resets at 00:00 UTC). Customers without a vGPU license fall back to per-simulation FlexCredits billing — this is the default if no license is attached.

This protocol covers the two license types, the GUI submission flow, the Python SDK, and the decision rules the agent should apply when generating cloud-submission code.

## 1. The two license types

| | Reserved vGPU | Time-Shared vGPU |
|---|---|---|
| Concurrency cap | Up to N effective A100 GPUs concurrently | Up to N effective A100 GPUs concurrently |
| Daily limit | None — full capacity 24/7 | Daily GPU-Hour budget, resets 00:00 UTC |
| FlexCredits consumed | No | No |
| FlexCredits override per-sim | Yes (`pay_type=CREDITS`) | Yes (`pay_type=CREDITS`) |
| Best for | Steady, around-the-clock workloads | Concentrated peak workloads, mixed projects |

Both types share the same submission controls and dashboard; Time-Shared adds a daily-budget dashboard with cards for Daily Total GPU-Hours, Queue, Reset Timer, and vGPU Usage.

Solver caveats (v2.11.x):

- **FDTD** — fully integrated. Runs on vGPU, consumes Time-Shared daily allowance, GUI shows GPU-Hours estimate.
- **Mode / EME** — run on vGPU but **do not yet subtract** from the Time-Shared daily allowance (planned to change). No GPU-Hours estimate in the GUI.
- **Heat** — runs on vGPU, consumes Time-Shared allowance, but no GPU-Hours estimate yet (placeholder `--- GPU-Hrs`).

Do not promise Time-Shared customers that Mode / EME stay free of the daily quota — that's a current gap, not a guarantee.

## 2. GUI submission (Tidy3D Workbench)

When a user describes the GUI flow or asks "how do I run this from the website", surface the following — abbreviated; the full walk-through with screenshots lives in the customer-facing vGPU manual:

1. **Validate.** In the Workbench, click **Check Simulation**. After validation the toolbar shows a green **▶ Run Simulation With vGPU** button (or *With FlexCredits* if the user has no vGPU license) plus a **Simulation Info** chip linking to the estimate breakdown.
2. **Open the Run popover** (the small ▾ dropdown on the green button). Two pay-type options:
   - **vGPU** (default for vGPU customers) — set `Priority` (1-10, default 5) and `GPU Allocation` (`Auto` or one of `2, 4, 8, 12, 16, 20, 24, 32, 64`, capped at the license tier). For Time-Shared, the popover also shows **Estimated GPU-Hours**.
   - **FlexCredits** — shows estimated FlexCredits cost, bypasses the vGPU queue / daily allowance for this single run.
3. **Memory rules.** If estimated GPU memory exceeds `80 GB × N` for the selected allocation, the vGPU option is greyed out and an **Ignore Memory Limit** checkbox appears (re-enables with runtime-error warning, up to 2× the cap). Above 2×, vGPU is hard-blocked and only FlexCredits is available.
4. **Daily-budget rule (Time-Shared only).** If a single simulation's estimated GPU-Hours exceed the license's total daily allowance, the vGPU option is blocked outright — even a fresh day's reset cannot cover it. FlexCredits is the only path.
5. **Track jobs.** *Avatar → Account → Virtual GPU Scheduler.* Reserved customers see only the queue table; Time-Shared customers see four summary cards (Daily Total GPU-Hours, Queue, Reset Timer, vGPU Usage) above the table. Row action menu lets users edit priority, change allocation, or switch a queued task to FlexCredits.

## 3. Python SDK submission

The SDK exposes the same submission knobs via `web.run` / `web.run_async` / `Job` / `Batch`.

> **Gate first.** `web.run(...)`, `web.run_async(...)`, `Job.run(...)`, and `Batch.run(...)` start cloud compute. Treat the snippets below as post-consent call shapes. Before writing or executing an active run call, route through `protocols/simulation-execution.md` so the task is uploaded / estimated, the cost or GPU-Hour impact is reported, and the user explicitly consents.

**Default — use the license:**

```python
import tidy3d as td
import tidy3d.web as web

sim_data = web.run(
    sim,
    task_name="my_simulation",
    folder_name="default",
)
```

With no `pay_type` argument the call uses `PayType.AUTO`: vGPU for vGPU customers, FlexCredits otherwise. This is the right default for almost every script.

**Specifying vGPU options explicitly:**

```python
sim_data = web.run(
    sim,
    task_name="my_simulation",
    priority=8,                 # vGPU queue priority, 1 (lowest) to 10 (highest); default 5
    vgpu_allocation=4,          # one of 2, 4, 8, 12, 16, 20, 24, 32, 64 (capped at license tier)
    ignore_memory_limit=False,  # set True to allow runs above the per-GPU memory cap (up to 2x)
)
```

`priority`, `vgpu_allocation`, and `ignore_memory_limit` are silently ignored on FlexCredits-only accounts — code stays portable across license types.

**Forcing FlexCredits for one run** (e.g. urgent job when the vGPU queue is full or the Time-Shared daily allowance is exhausted):

```python
from tidy3d.web.core.types import PayType

sim_data = web.run(
    sim,
    task_name="urgent_run",
    pay_type=PayType.CREDITS,   # equivalent to the string "FLEX_CREDIT"
)
```

`PayType.AUTO` (default) = license default. `PayType.CREDITS` / `"FLEX_CREDIT"` = force FlexCredits.

**Account-wide defaults:**

```python
import tidy3d as td

td.config.run.pay_type = "AUTO"          # or "FLEX_CREDIT"
td.config.vgpu.priority = 5              # 1..10
td.config.vgpu.vgpu_allocation = 4       # 2, 4, 8, 12, 16, 20, 24, 32, or 64
td.config.vgpu.ignore_memory_limit = False
```

Per-call arguments override the config defaults.

**Batch / parameter sweeps.** The same `priority` / `vgpu_allocation` / `ignore_memory_limit` arguments apply at the batch level — every simulation in the batch inherits them. On Time-Shared, if a batch's estimated total GPU-Hours exceeds today's remaining allowance, the overflow stays in `Queued` state and resumes automatically after the next 00:00 UTC reset.

## 4. Decision rules for the agent

When generating cloud-submission code or answering "how do I run this":

- **Default to `PayType.AUTO`** (omit the `pay_type` argument). It does the right thing on every account type.
- **Do not set `vgpu_allocation` explicitly** unless the user has asked for a specific count or the script is benchmarking allocation trade-offs. `Auto` (the GUI default) and the license default (`vgpu_allocation` unset) almost always pick well.
- **Do not raise `priority` above 5** without a stated reason — bumping someone's job to priority 10 just because they asked impatiently is rude to their teammates running against the same license.
- **Surface `pay_type=PayType.CREDITS` only when** (a) the user asked for it explicitly, (b) a Time-Shared customer has exhausted today's allowance and the job is urgent, or (c) the simulation hits the hard memory block and FlexCredits is the only path. In every case, state the cost implication before generating the call: vGPU runs are pre-paid, FlexCredits draws on the FlexCredit balance.
- **For Time-Shared users, surface daily-budget context** when relevant: "this simulation is estimated at X GPU-Hours; today's remaining allowance is Y" if the SDK provides that info via the Job estimate. The Virtual GPU Scheduler is the source of truth — point users at it for budget questions.
- **Inside any autonomous-design loop**: never silently raise `priority` or `vgpu_allocation` mid-loop. The budget gate authorized a specific cost profile; bumping it requires escalating back to the user.
- **License type is account state, not code state.** The agent generally cannot tell from a script whether the user is on Reserved, Time-Shared, or FlexCredits — if the answer materially depends on the license type, ask.

## 5. Cost interaction with `protocols/simulation-execution.md`

`simulation-execution.md`'s cost-estimate / consent gate still applies — the choice between vGPU and FlexCredits changes *which pool* the cost is drawn from, not whether estimation + consent is needed. Sequence:

1. Generate the simulation and choose the intended `pay_type` / `priority` / `vgpu_allocation`.
2. Upload or create a `Job` / `Batch` through the safe estimate path in `protocols/simulation-execution.md`; do not call an active run shorthand before the gate.
3. Run `web.estimate_cost(job.task_id)` or the matching batch estimate and report the estimate (FlexCredits) plus, for Time-Shared, the estimated GPU-Hours when available.
4. Wait for explicit user consent before launching.
5. On consent, write or execute the submission with the agreed `pay_type` / `priority` / `vgpu_allocation`.

The estimate reflects the chosen pay_type; if you flip from `AUTO` to `CREDITS`, re-estimate before launching.

## 6. What this protocol does NOT cover

- License purchase, seat assignment, or admin setup — those are operational concerns owned by Flexcompute sales / admins.
- Switching between Reserved and Time-Shared mid-account — admin action, not a Python call.
- Performance tuning of `vgpu_allocation` for a specific device class — measure empirically; defaults are usually fine.
- Background on FlexCredit pricing — see the public Tidy3D docs.
