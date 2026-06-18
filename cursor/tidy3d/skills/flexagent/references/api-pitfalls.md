# Tidy3D API Pitfall Catalog

> **Version caveat:** these patterns were verified against Tidy3D **v2.11.x** (released 2026-04-06 through 2026-05-03). Before applying any correction, confirm the behaviour against the installed version using the available docs-search. If the live source disagrees with an entry here, trust the live source.

## v2.11 Breaking Changes

The following changes shipped in v2.11.0 and apply to any code targeting v2.11+. If user code was written for an older Tidy3D, surface these before "fixing" symptoms.

- **`ModeSortSpec.sort_key` is now required.** Default is `"n_eff"`. `ModeSortSpec()` without a `sort_key` raises a validation error. `sort_order` becomes optional with a smart default: ascending when a `sort_reference` is provided (closest first), descending for `n_eff` and polarization fractions, ascending for `k_eff` and `mode_area`.
- **Gaussian-beam `waist_distance` semantics changed for `direction="-"`.** A positive `waist_distance` (or `waist_distances`) now always places the waist behind the source/monitor plane on the negative normal axis, independent of `direction`. Pre-v2.11 simulations with backward-propagating `GaussianBeam` / `AstigmaticGaussianBeam` and non-zero waist distance need the sign flipped on `waist_distance` to reproduce the same beam.
- **`web.Batch(simulations={...})` requires string task-name keys.** Numeric keys (e.g. `{0: sim, 1: sim2}`) are no longer auto-converted and now raise. Use string keys (`"0"`, `"1"`, or the documented `"{param}_{value}"` convention).
- **1-D lumped elements are forbidden.** A `LumpedElement` with zero lateral extent now raises a validation error. Use a small finite extent (e.g. `1e-6`) on at least one transverse axis.

## Tidy3D API Pitfalls

| Pitfall                                 | Fix                                                                                                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run_time="auto"` or `run_time=None`    | Use `td.RunTimeSpec(quality_factor=Q)` (preferred) or a positive float in seconds                                                                               |
| `ModeSpec(filter_pol=...)`              | Use `ModeSpec(sort_spec=td.ModeSortSpec(sort_key=...))`. The `filter_pol` API is gone in v2.11; `sort_key` is the supported replacement (default `"n_eff"`).    |
| `Box.from_bounds` with `td.inf`         | Infinity support for bounds varies by version — verify before modifying user code.                                                                              |
| `PolySlab` with `center=...`            | `PolySlab` has no `center` parameter — position is set via `vertices` (2D polygon) + `slab_bounds` (z extents)                                                  |
| `plot_3d(...)` customization            | `plot_3d` returns nothing and accepts no parameters                                                                                                             |
| `plot_field(..., cmap=...)`             | `plot_field` does not accept a colormap argument                                                                                                                |
| `web.estimate_cost(simulation)`         | `web.estimate_cost()` requires a `task_id`: `web.estimate_cost(job.task_id)`                                                                                    |
| `np.max(xarray_data)`                   | Always convert first: `data.values` before numpy operations                                                                                                     |
| `sim_data.y.values`                     | Coordinate access requires selecting a dataset first: `sim_data["monitor"].Ey.y.values`                                                                         |
| `ModeSolverData.plot_field()`           | In some versions, plotting methods live on the solver object (`ModeSolver`) rather than the data object — verify before modifying user code.                    |
| Unverified gdstk/trimesh/cma/optax APIs | Always verify versions and usage with Docs Search                                                                                                               |
| Unsure about ANY constructor parameter  | Search docs (`tidy3d_search_flexcompute_docs`) before generating the call. Never guess parameter names or value ranges — wrong guesses fail at validation time. |

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

For physics-side geometry rules (PML extension, structure-to-PML spacing, source / monitor placement inside the domain, waveguide port sizing, gaps between waveguide sections), see `references/geometry-construction.md` → "Geometry Guardrails". That is the canonical home — don't restate the same rules in two places.

The items below are **API-surface** pitfalls specific to import, alignment, and units that aren't captured by the physics guardrails:

- **Units / scale mismatches** — Tidy3D uses micrometers for length, Hz for frequency. Mixing nm with µm, or wavelengths with frequencies, is a frequent silent error.
- **Polygon / trimesh orientation or scale errors after import** — GDS / STL files may use a different coordinate frame or unit; verify the bounding box after `from_gds` / `from_stl` matches expected dimensions.
- **Mode / source / monitor misalignment** — polarization, target `n_eff`, and injection-frequency band must agree across the source and any mode-resolving monitor at the matching port.
- **Waveguide port placement / sizing drifting after geometry edits** — when geometry parameters change (width, position), source / monitor positions and sizes don't auto-update. Re-derive them from the updated geometry.
- **PML thickness not per documentation recommendations** — Tidy3D's defaults are usually right; only override after checking the docs for your device class.

## Batch and Analysis Pitfalls

- Batch task names must be **strings** in v2.11+ (`Batch(simulations={"0": sim, "1": sim2})` not `{0: sim, 1: sim2}`). The underscore convention (`"width_0.4"` not `"width=0.4"`) still applies and is a good default. See `protocols/parameter-sweeps.md`.
- Always verify monitor names against actual simulation data to avoid `KeyError`
- Use `matplotlib.pyplot` for all plots — NOT Plotly

## Parameter Consistency

The `params` list defines the function signature. The code body MUST use exactly the same variable names as declared in `params`. If `params` declares `wg_height`, the body must use `wg_height` — not `height`, not `h`.

## Newer API Tips (v2.11)

Surfaces from the v2.11 release that the agent should reach for when applicable. These are not pitfalls — they're capabilities that didn't exist or weren't recommended earlier:

- **Broadband mode injection via `pole_residue`.** `ModeSource` and `GaussianBeam` accept `broadband_method="pole_residue"` (vector-fitting with auxiliary differential equations) as an alternative to the default Chebyshev interpolation. Useful when Chebyshev interpolation oscillates over a wide frequency span or when the underlying mode has strong dispersion.
- **`DirectivityMonitor` symmetry fix.** Far-field results from `DirectivityMonitor` with `symmetry` were broken before v2.11. If the user has a workaround for this in older code, drop it on upgrade.
- **`td.PolySlab(bulges=...)`.** Arc-edged 2D polygon cross-sections via the standard bulge convention (`bulge = tan(theta/4)`). Use this instead of approximating curved edges by very high-vertex polygons. See `references/geometry-construction.md` ("Bulk replication" subsection neighbouring it has more on `GeometryArray`).
