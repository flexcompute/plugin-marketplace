# Recommended Analyses by Simulation Type

## FDTD

| Monitor type | Recommended analyses |
|---|---|
| FluxMonitor | Transmission/reflection spectrum, insertion loss (dB), 3 dB bandwidth, extinction ratio |
| FieldMonitor | Field profile heatmap (\|E\|, \|H\|, Poynting vector), cross-section field cuts, mode confinement. Prefer `sim_data.plot_field(name, "Ey", val="abs")` (built-in, handles axes / colormap) over manual `imshow`. v2.11+ adds `SurfaceFieldMonitor` / `SurfaceFieldTimeMonitor` for fields tangential to PEC surfaces — useful for plasmonic / metallic structures. |
| ModeMonitor | Mode-resolved transmission per mode index, coupling efficiency, effective index. For fiber-coupling and Gaussian-port problems, v2.11+ adds `GaussianOverlapMonitor` / `AstigmaticGaussianOverlapMonitor` which project the field onto a target Gaussian profile directly. |
| DiffractionMonitor | Diffraction efficiency by order, zeroth-order transmission, angular distribution |
| FieldProjectionAngleMonitor | Far-field radiation pattern, directivity, beam profile. The `DirectivityMonitor` symmetry handling was fixed in v2.11 — drop any prior workarounds. |

## MODE

- Effective index vs. wavelength
- Mode field profiles (Ex, Ey, Ez for fundamental and higher-order modes)
- Confinement factor
- Group index: `n_g = n_eff − λ · (dn_eff/dλ)`
- TE/TM identification via dominant field components

## EME

- S-parameter spectrum: S11 (reflection) and S21 (transmission) vs. wavelength
- Insertion loss: `−10·log10(|S21|²)` dB
- Port mode profiles
- Length sweep convergence
- v2.11 raised default `EMEModeSpec.interp_spec.num_points` from 3 to 5 for sharper frequency interpolation; v2.11.1 added a local-propagation API (`EMESimulation.propagate`, `compute_overlaps`, `propagate_from_overlaps`) — for iterative parameter sweeps that reuse the same modal basis, compute overlaps once and reuse them across sweep points rather than re-running the full pipeline each iteration.

## SMATRIX

- S-parameter matrix (magnitude and phase of all Sij vs. wavelength)
- Return loss: `−20·log10(|S11|)` dB per port
- Isolation (cross-port coupling levels)

## HEAT_CHARGE

- Temperature distribution (2D heatmap)
- Max temperature and location
- Thermal gradient magnitude
- Carrier density (electrons / holes) profile for charge sims; depletion-region width vs reverse bias
- For active-device workflows, chain the TCAD output into FDTD: map ΔT (heat) into Δn via `dn/dT` (~1.8e-4 /K for Si), or map ΔN_e / ΔN_h (charge) via Soref-Bennett plasma dispersion, then drive a downstream FDTD `CustomMedium`.

## BATCH (parameter sweep)

- Metric vs. swept parameter
- Optimal value identification
- Multi-metric comparison overlay

## Sweep Analysis Tips

For sweeps: start coarse to map the response, downselect to the interesting region, then run a refined sweep. This reduces cost while finding optima reliably.

## Device-Specific Analysis Starting Points

When the user's analysis question matches a common device class, use the matching analysis pattern below and route any new build through Build mode's docs-backed Custom path:

- **Interferometer fringes / FSR extraction** — FSR = c / (n_g · ΔL).
- **Polarization extinction ratio / TE-TM separation** — run twice, once per input polarization, to populate the 2×2 transfer matrix.
- **Cavity Q-factor / mode localization** — FFT of `FieldTimeMonitor` → resonance + linewidth → Q.
- **Edge / fiber coupling efficiency** — use `GaussianOverlapMonitor` for direct Gaussian-mode overlap reporting.
- **Taper adiabaticity** — sweep taper length for the loss-vs-length curve.
- **1×N power split uniformity** — imbalance = (max − min) / mean across the N output monitors.
- **Thermo-optic phase shifter / heater efficiency** — ΔT_avg × `dn/dT` × heater length × 2π/λ for phase shift.
- **Carrier-depletion modulator** — apply Soref-Bennett to ΔN_e / ΔN_h to get Δn, then compute phase shift.
