# Tidy3D API Pitfall Catalog

> **Version caveat:** these patterns were verified against a specific Tidy3D release. Before applying any correction, confirm the behaviour against the installed version using the available docs-search. If the live source disagrees with an entry here, trust the live source.

## Tidy3D API Pitfalls

| Pitfall                                 | Fix                                                                                                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run_time="auto"` or `run_time=None`    | Use `td.RunTimeSpec(quality_factor=Q)` (preferred) or a positive float in seconds                                                                               |
| `ModeSpec(filter_pol=...)`              | `filter_pol` is deprecated in newer releases; prefer `sort_spec`. Verify the available parameter name against the installed version before modifying user code. |
| `Box.from_bounds` with `td.inf`         | Infinity support for bounds varies by version — verify before modifying user code.                                                                              |
| `PolySlab` with `center=...`            | `PolySlab` has no `center` parameter — position is set via `vertices` (2D polygon) + `slab_bounds` (z extents)                                                  |
| `plot_3d(...)` customization            | `plot_3d` returns nothing and accepts no parameters                                                                                                             |
| `plot_field(..., cmap=...)`             | `plot_field` does not accept a colormap argument                                                                                                                |
| `web.estimate_cost(simulation)`         | `web.estimate_cost()` requires a `task_id`: `web.estimate_cost(job.task_id)`                                                                                    |
| `np.max(xarray_data)`                   | Always convert first: `data.values` before numpy operations                                                                                                     |
| `sim_data.y.values`                     | Coordinate access requires selecting a dataset first: `sim_data["monitor"].Ey.y.values`                                                                         |
| `ModeSolverData.plot_field()`           | In some versions, plotting methods live on the solver object (`ModeSolver`) rather than the data object — verify before modifying user code.                    |
| Unverified gdstk/trimesh/cma/optax APIs | Always verify versions and usage with Docs Search                                                                                                               |

## run_time Quality Factor Guide

Use `td.RunTimeSpec(quality_factor=Q)`:

| Device type                                          | quality_factor |
| ---------------------------------------------------- | -------------- |
| Non-resonant (waveguides, couplers, splitters)       | 1              |
| Low-Q resonant (Bragg gratings, Fabry-Pérot)         | 10             |
| High-Q resonant (ring resonators, photonic crystals) | 200+           |

## MODE Results Access Patterns

`ModeSimulation` produces `ModeSimulationData`. Access mode data via `.modes`:

```python
# Correct
modes = mode_sim_data.modes          # ModeSolverData
n_eff = mode_sim_data.modes.n_eff    # DataArray(mode_index, f)
ex    = mode_sim_data.modes.Ex       # DataArray

# Wrong — do NOT do this
n_eff = mode_sim_data.n_eff          # AttributeError
```

## Monitor Data Access Patterns

```python
# ModeMonitor → ModeSolverData
amps  = sim_data["mode_mon"].amps    # DataArray (mode_index, f, direction)
n_eff = sim_data["mode_mon"].n_eff   # DataArray (mode_index, f)

# FluxMonitor → FluxData
flux = sim_data["flux_mon"].flux     # DataArray (f,)

# FieldMonitor → FieldData
ex = sim_data["field_mon"].Ex        # DataArray (x, y, z, f)

# ModeSimulation
modes = mode_sim_data.modes          # ModeSolverData
n_eff = mode_sim_data.modes.n_eff    # DO NOT use mode_sim_data.n_eff
```

## Geometry and Setup Pitfalls

- Units/scale mismatches — Tidy3D uses micrometers for length, Hz for frequency
- Polygon/trimesh orientation or scale errors after import
- Mode/source/monitor misalignment (polarization, n_eff, injection band)
- Sources or monitors placed outside the simulation domain
- Waveguide port placement/sizing drifting after geometry edits
- PML thickness not per documentation recommendations
- Gaps between interconnected waveguide sections

## Batch and Analysis Pitfalls

- Batch task names must use underscore format: `"width_0.4"` not `"width=0.4"`
- Always verify monitor names against actual simulation data to avoid `KeyError`
- Use `matplotlib.pyplot` for all plots — NOT Plotly

## Parameter Consistency

The `params` list defines the function signature. The code body MUST use exactly the same variable names as declared in `params`. If `params` declares `wg_height`, the body must use `wg_height` — not `height`, not `h`.
