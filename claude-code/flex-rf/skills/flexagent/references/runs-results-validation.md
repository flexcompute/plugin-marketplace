# Runs, Results, And Validation

The User Guide *Web Workflow* page covers `web` module mechanics. The *Working with Results* page
covers S-matrix access, renormalization, de-embedding, per-excitation monitor
data, antenna metrics, lobe measurement, and mode data. Search there via
`tidy3d_search_flexcompute_docs(package="flex-rf", ...)`.

This reference carries the agent-side discipline that the docs do not encode.

## Picking The Right Run Pattern

The User Guide describes the mechanics. The choice:

- **`web.run(model, task_name=..., path=...)`** — single approved run. Submits, monitors, downloads, returns data. Best when writing code that the user will execute.
- **`web.upload → web.start → web.get_info → web.load`** — when non-blocking execution, recovery after disconnection, or fire-and-forget submission matters. Use for autonomous agent-driven workflows or for very large jobs. 
- **Nested dict / list / tuple passed to `web.run`** — preserves input container shape in the returned results. The cleanest sweep pattern. Note: currently `web.upload` does not support the dict/list/tuple pattern. For non-blocking batch execution, upload each job individually and maintain a local task id manifest.
- **`web.abort`** — stop a running task. 

`web.estimate_cost` can over-report when energy shutoff triggers early; use `web.real_cost` after the run for the actual bill if asked. `task_id` is recoverable using `web.get_tasks(num_tasks=x)` to fetch `x` most recent tasks. Always maintain a job manifest: a simple document that tracks the `task_id` values of each submitted web job and their status. 

## Web Queue Times

It is normal for jobs to be in queue after being submitted to the web. The queue time can be highly variable, between seconds to hours. If the job(s) are in queue for a long time, set up a recurring status check using `web.get_info` and inform the user.

## Sweep Ergonomics

```python
def build_model(param_a, param_b):
    sim = rf.Simulation(...)
    return rf.TerminalComponentModeler(simulation=sim, ports=[...], freqs=freqs)

sweep = {
    f"a={a}_b={b}": build_model(a, b)
    for a in a_values for b in b_values
}

data = web.run(sweep, task_name="sweep")  # returns dict with matching keys
```

For non-blocking batch submission, prefer to submit/track each job individually using `web.upload -> web.start -> web.get_info -> web.load` and keep track of task IDs/data in a local manifest document. 

## S-Parameter Convention When Comparing To Measurements

The User Guide advanced-topics *S-parameter definitions* page covers the convention matrix. The agent's job is to ask the user which convention their reference data uses:

- For **real `Z_ref`** (typical), all three (`pseudo`, `power`, `symmetric_pseudo`) are equivalent. Default `pseudo` is fine.
- For **complex `Z_ref`** (lossy lines, complex termination), the three definitions diverge. Ask the user which definition their measurement tool or comparison reference uses before generating code.

Independent of S-parameter definition: Flex RF uses `exp(-i ωt)`; most RF measurement tools use `exp(+i ωt)`. Apply `np.conjugate(...)` before comparing complex values.

## Low-Frequency And High-Q Broadband

For content below ~1 GHz, deep resonances, or target S-parameter levels around −60 dB to −70 dB, the default `run_time` and `shutoff` may end the FDTD run before the response decays. This typically manifests as spurious oscillations in the S-parameter plot. 

To debug, check:
- **Primary:** read the `SimulationData.log` for each port and confirm field energy decayed to the desired level before the run ended. This is the direct evidence of whether the simulation ran long enough.
- **Supporting:** `web.real_cost` close to `web.estimate_cost` means early shutoff did not trigger and the full requested `run_time` was used. That is consistent with under-decay but does not prove it — confirm with the log/energy decay rather than the cost comparison alone. 

Modify:
- `Simulation.run_time` — extend it if the time-domain response has not decayed.
- `Simulation.shutoff` — lower shutoff for resolving deep resonances or long-lived low frequency content.
- `TerminalComponentModeler.remove_dc_component` should be `False` if sweep range extends below 1 GHz.
- `RunTimeSpec` exists to auto-define runtime based on quality and source factors. 

Note that broadband or narrowband simulation may require different settings.

## Validation Habits

Require at least one validation surface beyond a final plot when the user wants the result trusted:

- Inspect structure, port, and mesh slices *before* running.
- Standalone mode-solver check before any 3D wave-port run.
- Compare to a transmission-line model, circuit model, or scikit-rf model.
- Compare to a published paper or measurement benchmark when one exists.
- Coarse-vs-refined mesh comparison around the target metric. Convergence is the credibility argument.
- Field plots that explain an S-parameter feature.
- For antennas, present radiation pattern *and* `S11` together. A great pattern with a poor match means realized gain is poor.

Flag residual risk when the result depends on mesh convergence, material validity, port de-embedding, boundary placement, long decay time, or an undocumented modeling convention.

## Inspecting Simulation

Available methods on `TerminalComponentModeler`: `plot_sim`, `plot_sim_grid`, `plot_port`. Available methods on the base `Simulation`: `plot`, `plot_grid`. Use these methods to plot a 2D slice plane of the simulation. The plotting methods uses `matplotlib` behind the scenes. 

Note that `plot_sim_grid` and `plot_grid` are slightly different in their output - the latter shows layer refinement features as purple markers/lines. The former only shows the final grid.

By default, `plot_sim` and `plot_sim_grid` shows the entire simulation domain, including PML regions (in gray). The `plot_port` method sizes according to the port size. Zoom into critical regions and resolve details of interest with `ax.set_xlim/ylim` (distance unit = micron).

Other tips for `plot_sim`, `Simulation.plot`, `plot_port`:
- Set `monitor_alpha=0`  to hide monitors (useful to prevent obscuring other details).
- Set `fill_structures=False` to plot structure outline only. Useful to prevent obscuring other details, or to overlay multiple plot slices in one plot. 