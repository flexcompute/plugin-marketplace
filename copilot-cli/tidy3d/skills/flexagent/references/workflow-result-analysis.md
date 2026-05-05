# Result Analysis Workflow

Behave like a photonics engineer interpreting simulation results. The goal is to extract physically meaningful metrics and visualize them clearly.

Process sequentially. Solicit user feedback after each step.

---

## Step 1: Data Analysis

**Read the simulation code to understand what monitors were used and what data is available.**

- Identify every monitor by name and type (FluxMonitor, ModeMonitor, FieldMonitor, etc.).
- Use Docs Search to verify the data structure for each monitor type.
- Apply the correct access pattern (see below) — wrong access patterns are the most common analysis error.
- Do not change any code in this step.

### Monitor Data Access Patterns

```python
# FluxMonitor → FluxData
flux = sim_data["flux_mon"].flux            # DataArray (f,)

# ModeMonitor → ModeSolverData
amps  = sim_data["mode_mon"].amps           # DataArray (mode_index, f, direction)
n_eff = sim_data["mode_mon"].n_eff          # DataArray (mode_index, f)

# FieldMonitor → FieldData
ex = sim_data["field_mon"].Ex               # DataArray (x, y, z, f)

# ModeSimulation → ModeSimulationData
modes = mode_sim_data.modes                 # ModeSolverData
n_eff = mode_sim_data.modes.n_eff           # DO NOT use mode_sim_data.n_eff
```

**Always use `.values` before NumPy operations on xarray DataArrays.**

## Step 2: Proposed Actions

- Plan the analysis: what metric, what plot, what axis labels.
- Use `plot_field` for field profiles (preferred over manual `imshow`).
- Set appropriate figure and font sizes for readability.
- Ask about formatting preferences (wavelength vs frequency axis, linear vs dB scale, etc.).
- Do not change any code in this step.

## Step 3: Apply Changes

- If accepted: write the analysis code, offer further analyses.
- If rejected: ask for clarification.

---

## Matplotlib Rules

- Use `matplotlib.pyplot` — **not Plotly**.
- Tidy3D's `.plot*()` methods use matplotlib internally — use them as-is.
- `plt.show()` is fine; do **not** call `plt.savefig()`.
- Colormaps:
  - `'inferno'` — magnitude/intensity plots
  - `'RdBu'` (centered at 0) — real/imaginary/phase plots
  - `'viridis'` — general default
- Heatmap data must be 2D — call `.values` on xarray DataArrays before passing to `imshow`.
- Always set axis labels, a title, and a colorbar for heatmaps.

---

## Recommended Analyses by Simulation Type

See `references/recommended-analyses.md` for the full breakdown. Key defaults:

**FDTD:**
- FluxMonitor → transmission/reflection spectrum, insertion loss (dB), extinction ratio
- FieldMonitor → `sim_data.plot_field(name, "Ey", val="abs")` for field profile
- ModeMonitor → mode-resolved transmission `amps.sel(direction="+", mode_index=0)`, then `|amps|²`

**MODE:**
- `mode_sim_data.modes.n_eff` → effective index vs. wavelength
- `mode_sim_data.modes.Ex` (or Ey, Ez) → field profiles
- Group index: `n_g = n_eff - λ · (dn_eff/dλ)`

**EME:**
- S-parameters: S11 (reflection), S21 (transmission) vs. wavelength
- Insertion loss: `-10·log10(|S21|²)` dB

**BATCH:**
- Metric vs. swept parameter; identify optimum; overlay multiple metrics

---

## Common Normalization Patterns

**Transmission from FluxMonitor (Tidy3D normalizes to source power by default):**
```python
# P_in = 1.0 (Tidy3D default normalization)
T = sim_data["port_out"].flux.values   # already normalized
IL_dB = -10 * np.log10(np.clip(T, 1e-20, None))
```

**Transmission from ModeMonitor:**
```python
amps = sim_data["through_port"].amps.sel(direction="+", mode_index=0)
T = (np.abs(amps.values) ** 2)
```

**Wavelength axis from frequency:**
```python
freqs = sim_data["mon"].flux.f.values   # Hz
wavelengths_um = td.C_0 / freqs        # µm (Tidy3D uses micrometers)
wavelengths_nm = wavelengths_um * 1e3  # nm for plotting
```
