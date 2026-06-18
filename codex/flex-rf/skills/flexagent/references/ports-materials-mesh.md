# Ports, Materials, And Mesh — Cross-Document Decisions

The User Guide pages *Lumped Ports and Elements*, *Wave Ports*, *Mediums*,
*Meshing*, *Monitors*, and *Boundary Conditions* carry the full catalog,
validity rules, and worked examples. Search them via
`tidy3d_search_flexcompute_docs(package="flex-rf", ...)`.

This reference carries only the cross-page decisions and quick reminders the
agent needs at glance-time.

## Lumped Vs Wave Port — Decision Rule

The User Guide states the rule across two separate pages; the unified summary:

- **Use a lumped port** when the port region is electrically compact (≲ λ/10 of the highest frequency) and is a non-transmission-line connection — a feed gap, a coax pin to a planar structure. `LumpedPort` for planar gaps, `CoaxialLumpedPort` for true cylindrical coaxial sources.
- **Use a wave port** when the excitation is a guided line (CPW, microstrip, stripline, waveguide, multimode line, imported / tessellated coaxial connector). The mode is solved in 2D first, then injected. Required for accurate transmission-line impedance, broadband sweeps, multimode, or differential / common-mode measurements.

If the user says "a coax cable plugged into the board": ask whether the connector body is modeled (imported STEP / STL with tessellation) — if yes, use `WavePort` or `TerminalWavePort`. `CoaxialLumpedPort` assumes the analytical inner / outer geometry matches the physical geometry exactly.

## Wave Port Sizing And Verification

Open boundary (microstrip, CPW): port plane should be at least 5× the signal line dimensions so the mode decays well within the plane. For micron-sized structures, the port plane likely needs to be even larger. Closed boundary (coaxial, waveguide): port plane only needs to contain the outer conductor.

Always inspect the port plane with `plot_port(...)`. Treat the outer frame of the port window as an effective PEC with implications for electrical connectivity and ground in the simulated metal structures.  

Always call `WavePort.to_mode_solver(simulation=..., freqs=...)` and inspect `n_eff`, `Z0`, and the mode field profile before committing to the 3D run. This is the cheap sanity check.

## `LossyMetalMedium` Validity Quick Reminder

The User Guide *Mediums* page covers the full SIBC story. The rule that bites quietly:

`LossyMetalMedium` is a Surface Impedance Boundary Condition. It is accurate only when the metal cross-section size *h* is large compared to the skin depth *δ*. When *h* and *δ* are comparable — thin films, high-frequency edge currents on thin traces, low-conductivity layers — stop and confirm whether SIBC is appropriate. Suggest switch to a volumetric `Medium` with conductivity.

But, if switching to a volumetric `Medium` with conductivity, it is imperative not to blindly use the automesher as it will refine everywhere and blow up cell count. Use the following workflow: first, build dummy metal structures with `LossyMetalMedium` -> create dummy simulation with auto grid. Use `corner_refinement` to resolve skin depth, suggest 1-3 cells per skin depth for two skin depths. Then, create actual structures with `Medium`. Create `GridSpec` with `GridSpec.from_grid(sim_dummy.grid)` where `sim_dummy` was previous dummy sim. Use `GridSpec` to define actual `Simulation`. 

For pre-measured PCB and RF substrate data, use `rf_material_library` lookups instead of hand-rolled `PoleResidue` fits. When fitting a lossy model (`constant_loss_tangent_model`), pass the simulation `frequency_range` so the fit is accurate where the simulation cares.

## Monitor Placement Quick Rules

- `DirectivityMonitor` for antenna far-field goes in `TerminalComponentModeler(radiation_monitors=[...])`, **not** in `Simulation(monitors=[...])`. This is the most-missed placement rule.
- The `DirectivityMonitor` must completely surround the radiating structure.
- `FieldMonitor` and `FieldTimeMonitor` produce large data sets if 2D or 3D — use a sparse `freqs` subset of the simulation frequency range, and suggest `interval_space` for spatial subsampling.
- Add monitors only for outputs you will postprocess.

## `structure_priority_mode` Quick Rule

When structures overlap and you need non-default priority, set `structure_priority_mode` on the `TerminalComponentModeler`, **not** on the `Simulation` or `Scene`. The TCM setting overrides the others unless it is `None`. The User Guide *Structure and Scene* page calls this out explicitly because the multi-location setting has caused historical confusion.

Default behavior: `conductor` mode (PEC > LossyMetalMedium > others, then list order). For order-only priority, use `equal`.

## Path Integrals And `ImpedanceCalculator`

The User Guide *Working with Results* page covers `ImpedanceCalculator` after a run. For mode-solver impedance, `Z0` is already precalculated — `ImpedanceCalculator` is rarely needed unless the voltage / current path is part of the engineering question (asymmetric line, multiconductor, non-standard cross section). When it is, use `AxisAlignedVoltageIntegralSpec` and `AxisAlignedCurrentIntegralSpec` (or `Custom2D` variants); do not pick path placement arbitrarily.
