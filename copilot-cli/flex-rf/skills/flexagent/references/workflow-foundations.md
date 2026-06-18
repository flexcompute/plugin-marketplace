# Workflow Foundations

Read before generating new simulation code. Complements the Flex RF User Guide
*Overview* page, which carries units, the `exp(-i ωt)` phase convention, the
`TerminalComponentModeler` / `ModeSolver` class structure, and basic data
access. Search for those via
`tidy3d_search_flexcompute_docs(package="flex-rf", ...)` rather than restating
them here.

## Imports And Namespace

```python
import flex_rf.tidy3d as rf
import flex_rf.web as web
```

Use these imports for any new Flex RF code. The `flex_rf.tidy3d` alias signals that many objects are shared with Tidy3D during the migration period; a future release will move to a flat `flex_rf` namespace.

## Migration Nuance Beyond Mechanical Replacement

The User Guide *Migrating from Tidy3D* page covers the search-and-replace mechanics. Additional points for real-project migrations:

- The migration is not a deprecation. Legacy `tidy3d.rf` keeps running for RF-licensed users in the short term but is frozen. New features land only in Flex RF.
- `web` is now `flex_rf.web`. Credentials live under `~/.config/flex-rf/config.toml` and are overridden by `FLEX_RF_APIKEY`, separate from Tidy3D's config.
- Cache and logging are configurable through `flex_rf.config` for process-local settings; persistent cache control goes through the `flex-rf cache` CLI.

Preserve the user's existing convention unless they explicitly ask for migration. A one-line import change cascades into PR-sized diffs.

## Modeling Sequence (Decision Order)

The User Guide *Overview* and *Quickstart* show the API shape. This is the order of *decisions* for any new Python workflow:

1. **Frequency grid.** Set `f_min`, `f_max`, density per output type (dense for sweeps, sparse for radiation and field monitors). Many downstream auto-defaults derive from it. Monitor frequency grid points must be a subset of frequency sweep grid points. 
2. **Dimensions.** Use a single length convention with a conversion helper (`mm = 1000` is the standard). Do not mix length scales in one expression.
3. **Materials before structures.** A `Structure` is geometry plus medium. Build the materials dictionary first so geometry definitions stay short.
4. **Base `rf.Simulation`.** Center, size, structures, monitors (only those you will use), `grid_spec` (with `LayerRefinementSpec` for metal layers), `boundary_spec` (PML default when omitted), `lumped_elements` if any, `run_time`. Set `plot_length_units` for readable plots.
5. **`TerminalComponentModeler`** wrapping the base simulation, with `ports`, `freqs`, and optional `radiation_monitors`.
6. **Inspect.** `plot_sim`, `plot_sim_grid`, `plot_port`, optionally `plot_3d`. Verify port planes, grid refinement, and structure correctness near critical regions. For 2D plots, zoom into critical regions with `ax.set_xlim/ylim` (default distance unit = micron).
7. **Cost estimate** unless the user has already approved the run.
8. **Extract by name.** `.sel(...)` on the returned data. Per-excitation monitor data lives at `tcm_data.data[port_index]` where the index is the port name (lumped), `<name>@<mode_num>` (wave), or `<name>@<terminal>` (terminal-wave).

## Which Simulation Object To Use

The User Guide describes each object in isolation. The decision rule:

- **`TerminalComponentModeler`** — default for any finite 3D RF problem with named ports and an S-matrix as the answer.
- **`ModeSolver` attached to a `WavePort`** — when the structure has a wave port and you want to verify the launched mode (impedance, propagation constant, attenuation) before committing to a 3D run. Call `WavePort.to_mode_solver(simulation=..., freqs=...)`. Always do this before any new wave-port 3D job.
- **`ModeSimulation`** — standalone 2D problem with no enclosing 3D run. Use for pure transmission-line characterization, dispersion sweeps, mode-catalog generation.
- **Bare `Simulation`** — for problems whose output is not a port S-matrix: plane-wave scattering, RCS, absorber characterization, periodic metasurfaces, time-domain pulse propagation study. Avoid for port problems.

`Simulation.from_scene(...)` is available if the user already has a separately constructed `Scene` to reuse. Otherwise build the `Simulation` directly.

## What To Confirm Before Generating Code

When the user asks for "an S-parameter simulation" or similar, confirm:

- The named port set, with a one-line description of each (location, line type, reference impedance).
- The frequency range and required grid density.
- Whether the run is broadband (FDTD-natural) or narrowband / high-Q (needs `run_time` and `shutoff` consideration).
- Whether antenna metrics are wanted (radiation monitors must be present *before* the run, not added later).
- Whether the structure has a translationally-invariant cross section that should be mode-solved first.

When any of these is ambiguous, stop and ask. Do not invent.
