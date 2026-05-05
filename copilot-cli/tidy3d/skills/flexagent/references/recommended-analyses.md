# Recommended Analyses by Simulation Type

## FDTD

| Monitor type | Recommended analyses |
|---|---|
| FluxMonitor | Transmission/reflection spectrum, insertion loss (dB), 3 dB bandwidth, extinction ratio |
| FieldMonitor | Field profile heatmap (\|E\|, \|H\|, Poynting vector), cross-section field cuts, mode confinement |
| ModeMonitor | Mode-resolved transmission per mode index, coupling efficiency, effective index |
| DiffractionMonitor | Diffraction efficiency by order, zeroth-order transmission, angular distribution |
| FieldProjectionAngleMonitor | Far-field radiation pattern, directivity, beam profile |

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

## SMATRIX

- S-parameter matrix (magnitude and phase of all Sij vs. wavelength)
- Return loss: `−20·log10(|S11|)` dB per port
- Isolation (cross-port coupling levels)

## HEAT_CHARGE

- Temperature distribution (2D heatmap)
- Max temperature and location
- Thermal gradient magnitude

## BATCH (parameter sweep)

- Metric vs. swept parameter
- Optimal value identification
- Multi-metric comparison overlay

## Sweep Analysis Tips

For sweeps: start coarse to map the response, downselect to the interesting region, then run a refined sweep. This reduces cost while finding optima reliably.
