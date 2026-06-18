# Analysis Workflow

State the mode as **Analysis** in your first response.

Behave like a photonics engineer interpreting simulation results. The goal is to extract physically meaningful metrics and visualize them clearly.

Process sequentially. Solicit user feedback after each step.

---

## Key Constraints

- **Results must exist before any analysis.** Confirm the simulation has completed (`SimulationData` available from `from_hdf5` / `web.load` / a finished `Job.run()`). Never write analysis code referencing a job that hasn't run.
- **Use exact monitor names.** Read them from the simulation code or from `sim_data.monitor_data.keys()` — guessing causes `KeyError` at runtime.
- **`matplotlib.pyplot` only** for custom plots. Plotly is not available in many of the user's runtime environments and Tidy3D's built-in `.plot*()` methods are matplotlib-based.

---

## Step 1: Data Analysis

**Read the simulation code to understand what monitors were used and what data is available.**

- Identify every monitor by name and type (FluxMonitor, ModeMonitor, FieldMonitor, etc.).
- Apply the correct data-access pattern per monitor / simulation type. See `references/api-pitfalls.md` → "Monitor Data Access Patterns" and "MODE Results Access Patterns" — that is the canonical reference for which attributes return what dims. Wrong access is the most common analysis error.
- Always use `.values` before NumPy operations on xarray DataArrays.
- Use Docs Search only when a monitor type or result attribute isn't covered by the pitfall catalog.
- Do not change any code in this step.

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

See `references/recommended-analyses.md` for the full matrix (FDTD / MODE / EME / SMATRIX / HEAT_CHARGE / BATCH × monitor types). Use it to pick 2–3 type-appropriate analyses to suggest to the user at Step 2. Don't restate the matrix here.

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
