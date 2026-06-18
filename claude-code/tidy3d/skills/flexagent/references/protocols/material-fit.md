# Material Fit Protocol

> **Scope.** Applies to Build whenever the user supplies tabular n/k or ε data (CSV, NumPy array, ASCII text) and wants a dispersive `td.PoleResidue` medium that downstream simulations can consume.

Use this protocol for any "fit this material" or "make a Tidy3D medium from this n/k data" request. It is the canonical implementation of the Build mode's **Material Fit Path**.

## Step 1 — Plan

Inspect the input data and confirm understanding **with the user** before generating code:

- **Format detection.** Open the file (CSV, TXT, NumPy `.npz`, JSON). Report:
  - Columns present: wavelength vs frequency, n vs ε, real vs complex.
  - Units: wavelength in nm or µm, frequency in Hz / THz.
  - Whether extinction `k` (or `Im(ε)`) is present, or only real index `n`.
  - Number of data points and the spectral range covered.
- **Confirm intent.** Show the parsed data range to the user. Ask: *"Fit over the full range [a, b] µm, or restrict to [c, d] µm to match the downstream simulation band?"* Restricting the fit range usually gives a better fit and is the right call when the user has a target wavelength range.
- **Materials library check.** If the material has a well-known name (cSi, SiO2, Au, Ag, TiO2, Si3N4), surface the existing `td.material_library` entries before fitting from scratch — they're already fitted and validated. Only fit when the user's data is non-standard, a different stoichiometry, or measured at a different temperature.

## Step 2 — Fit

Use `td.plugins.dispersion.FastDispersionFitter`. Sensible defaults:

```python
from tidy3d.plugins.dispersion import FastDispersionFitter

fitter = FastDispersionFitter(
    wvl_um=wvl_um_array,
    n_data=n_array,
    k_data=k_array_or_None,            # None for lossless fit
    wvl_range=(wvl_min, wvl_max),       # optional: restrict the fit band
)
medium, rms_error = fitter.fit(
    min_num_poles=1,
    max_num_poles=5,
    tolerance_rms=1e-2,
)
```

- Always pass `wvl_um` (not Hz) to `FastDispersionFitter` — the API is wavelength-native.
- `k_data=None` produces a real-valued (lossless) `PoleResidue`. Pass `k_data` when the user wants absorption.
- Start with `max_num_poles=5`; bump to 8-10 only if the fit is poor at step 3.
- Add `wvl_range=(wvl_min, wvl_max)` when the user gave you a target wavelength band — restricting the fit dramatically improves the RMS inside the band of interest.

The fitter returns a `td.PoleResidue` medium ready to use in any `td.Structure`.

## Step 3 — Report

Translate the RMS error into a one-line verdict for the user. Do not just print the number — anchor it to what it means.

| RMS | Verdict to surface | Next step |
|---|---|---|
| < 1e-2 | *"The fit is good; the fitted material is ready to use."* | Step 4 — use it. |
| 1e-2 to 0.1 | *"Reasonable but could be improved. Want me to try more poles or a tighter tolerance?"* | Offer `max_num_poles=8` or `tolerance_rms=5e-3` and re-fit; or accept and move on if the user is OK. |
| > 0.1 | *"Poor fit. I recommend `max_num_poles=8-10`, narrowing the wavelength range, or checking the input data for spikes / discontinuities."* | Either re-fit with more poles / narrower range, or surface the data anomaly to the user. |

Also surface a quick plot: target n / k overlay against the fitted `medium.eps_model(freqs)`. The eyeball check catches systematic offsets the RMS does not (e.g., a slow drift across the band that averages out to a low RMS but is locally bad at the user's wavelength of interest).

## Step 4 — Use

Once the fit passes, route back into the appropriate Build path with the new `medium` substituted:

- **Custom path** — pass the fitted medium directly into the Structures during the Phased Incremental Build.
- **Modifying existing setup** — route through `protocols/modify-existing-results.md` if results already exist for the un-fitted material.

If the simulation will run on the cloud, cost-estimate via `protocols/simulation-execution.md` before submitting — dispersive media can increase per-task cost compared to a non-dispersive `Medium`. Mention this if it is the user's first dispersive run.

## What this protocol does NOT cover

- Custom dispersion models (`Sellmeier`, `Lorentz`, `Drude`, `Debye`) when the physical model is known a priori. Use those constructors directly; this protocol is for tabular n/k data.
- Multi-physics media (`SemiconductorMedium`, `MultiPhysicsMedium`) for TCAD workflows. Use the Tidy3D TCAD docs and examples for those workflows.
- Anisotropic-tensor fitting. `FastDispersionFitter` is isotropic; anisotropic materials need either three independent fits per axis or a custom workflow.
