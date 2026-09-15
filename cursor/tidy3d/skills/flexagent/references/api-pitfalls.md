# Tidy3D API Pitfall Catalog

> **Live-version rule:** determine the installed Tidy3D version and verify any constructor, method, or migration claim against installed source or maintained docs. This catalog records recurring failure patterns, not a frozen release contract.

## Common API Pitfalls

| Pitfall | Safer response |
|---|---|
| `run_time="auto"` or `run_time=None` | Verify the active `Simulation` signature. For FDTD, use a positive duration or the documented `RunTimeSpec` form. |
| Treating `ModeSortSpec.sort_key` as required | Current maintained docs provide a default such as `"n_eff"`; inspect the installed signature before adding it. |
| Treating `ModeSpec(filter_pol=...)` as invalid | Some supported versions still accept it but mark it deprecated. Report the deprecation, verify the installed migration path, and do not present it as the cause of a validation error without evidence. |
| `Box.from_bounds` with `td.inf` | Infinity support is version-dependent; verify before modifying working code. |
| `PolySlab(center=...)` | Position is defined by 2D `vertices` and `slab_bounds`, not a `center` argument. |
| Assuming a plotting signature | Inspect the installed `plot_3d` or `plot_field` signature before passing output paths, colormaps, or other options. For headless setup images, use 2D `sim.plot(...)` plus matplotlib saving. |
| `web.estimate_cost(simulation)` | Estimate an uploaded task ID or use the documented `Job.estimate_cost()` / `Batch.estimate_cost()` surface. |
| A cloud `ModeSolver.run()` call | Submit an accepted mode-solver object through `web.Job(simulation=..., ...)` and follow the execution gate. |
| Guessing `web.run_async` arguments | Verify its collection-oriented live signature; do not copy the single-`web.run` call shape. |
| `np.max(xarray_data)` | Convert to `.values` before NumPy operations unless an xarray-aware operation is intended. |
| `sim_data.y.values` | Select a monitor and field dataset before accessing coordinates. |
| Assuming plotting methods live on result data | Mode plotting APIs can live on the solver or data object depending on the installed surface; verify before changing code. |
| Unverified gdstk, trimesh, or optimization APIs | Inspect the installed dependency and the Tidy3D import docs before writing the call. |

## Result Access Patterns

Verify monitor names against `sim_data.monitor_data.keys()` before indexing.

```python
# ModeSimulationData
modes = mode_sim_data.modes
n_eff = mode_sim_data.modes.n_eff

# ModeMonitor
amps = sim_data["mode_mon"].amps
n_eff = sim_data["mode_mon"].n_eff

# FluxMonitor
flux = sim_data["flux_mon"].flux

# FieldMonitor
ex = sim_data["field_mon"].Ex
```

Do not assume `mode_sim_data.n_eff` exists when the documented value is nested under `.modes`.

## Geometry and Setup Pitfalls

The physics-side guardrails live in `geometry-construction.md`. The recurring API and data issues are:

- Tidy3D lengths are micrometers and frequencies are hertz. Confirm external GDS, STL, and tabular units before conversion.
- Inspect imported polygon or mesh bounding boxes before constructing the simulation.
- Recompute source and monitor positions after geometry changes; they do not follow a moved waveguide automatically.
- Keep mode source, monitor, polarization, target effective index, and frequency band mutually consistent.
- Prefer documented boundary defaults. Override PML or other boundaries only with device-specific evidence.

## Batch and Analysis Pitfalls

- Use stable string task names in batch mappings and verify the installed `Batch` signature.
- Report aggregate and per-task cost estimates.
- Use matplotlib for custom plots because Tidy3D's plotting surfaces are matplotlib-based.
- Convert xarray data intentionally and preserve coordinates until labels and selections are complete.

## Parameter Consistency

The parameter list, function signature, and implementation must use the same names. If the public input is `wg_height`, do not silently consume a different variable such as `height`.

## Capability Leads

These APIs are useful leads, but verify availability and signatures before using them:

- `GeometryArray` or geometry `.array(...)` for repeated features;
- `PolySlab(bulges=...)` for arc-edged polygons;
- `GaussianOverlapMonitor` for Gaussian-mode coupling;
- `broadband_method="pole_residue"` for broadband mode injection;
- local EME propagation helpers when a sweep can reuse modal overlaps.

Do not attach a release number to one of these capabilities unless the user's compatibility question requires it and the current changelog confirms it.
