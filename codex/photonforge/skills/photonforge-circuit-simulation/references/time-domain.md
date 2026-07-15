# PhotonForge Circuit And Time-Domain Simulation

Use this reference when assembling a circuit, simulating it in the time domain, or running ring/MRM and WDM-cascade time-domain simulations. Verify exact names/signatures against the installed `photonforge` before relying on them.

## Contents

- Two ways to run a time-domain simulation
- Build the circuit (abstract building blocks + CircuitModel)
- High-level: CircuitTimeStepper (recommended)
- S-matrix conventions
- Low-level: pole-residue fit + TimeDomainModel
- Rings / MRMs: parameters and the rotating frame
- Recurring WDM ring-cascade pitfalls
- Detection: the built-in photodiode
- Validation checklist

## Two Ways To Run A Time-Domain Simulation

1. **`CircuitTimeStepper` (recommended).** Assemble a circuit `Component`, then let the time-stepper do everything: it builds each element's own active-model time stepper (a laser/ring/modulator/photodiode uses its dedicated stepper; a plain S-matrix model falls back to an automatic pole-residue fit) and propagates your input waveforms. No manual fitting or convolution code.
2. **`pole_residue_fit` + `TimeDomainModel` (low-level).** Fit a single S-matrix yourself and drive the resulting model. Use this only when you have a standalone S-matrix (e.g. measured data) and do not have a full circuit to hand to `CircuitTimeStepper`.

Both consume and return `pf.TimeSeries` objects and run a whole input vector in one `step` call.

## Build The Circuit (Abstract Building Blocks + CircuitModel)

`photonforge.abstract` provides analytic building blocks with models already attached: `cw_laser`, `signal_source`, `straight`, `directional_coupler`, `y_splitter`, `ring_resonator`, `mach_zehnder_modulator`, `phase_modulator`, `amplitude_modulator`, `photodiode`, `optical_amplifier`, `optical_noise`, `mux_demux`, `grating_coupler`, and more.

Their NATIVE ports are `P0`, `P1`, ... (optical) and `E0`, `E1`, ... (electrical). For example: `cw_laser` -> `P0`; `mach_zehnder_modulator` -> `E0` (drive) + `P0`/`P1` (optical); `photodiode` -> `P0` (optical in) + `E0` (current/voltage out); `ring_resonator` -> `E0` (tuning) + `P0`/`P1` (bus). Wire instances with `"connections"` and expose/rename top-level ports with `"ports"`. [verified PF 1.5.0]

```python
import photonforge as pf

laser = pf.abstract.cw_laser(power=1e-3)                                   # W; port P0
mzm   = pf.abstract.mach_zehnder_modulator(v_pi=3.0, extinction_ratio=25)  # E0 drive, P0/P1 optical
pd    = pf.abstract.photodiode(responsivity=0.9, gain=1e3)                # P0 optical in, E0 out

link = pf.component_from_netlist({
    "instances": {"L": laser, "M": mzm, "D": pd},
    "connections": [                       # each item: ((inst, port), (inst, port))
        (("M", "P0"), ("L", "P0")),        # laser out     -> modulator optical in
        (("D", "P0"), ("M", "P1")),        # modulator out -> photodiode in
    ],
    "ports": [("M", "E0", "DRIVE"), ("D", "E0", "OUT")],   # expose + rename
})
link.add_model(pf.CircuitModel())          # required for frequency-domain s_matrix; NOT needed by CircuitTimeStepper
```

Without an activated `pf.CircuitModel()` on the parent, a frequency-domain `link.s_matrix(...)` raises `RuntimeError: No active model found in component ''`. (`CircuitTimeStepper` builds its own per-element steppers from each element's active model and does NOT require the parent `CircuitModel` - it steps fine without it. [verified 1.5.0])

## High-level: CircuitTimeStepper (Recommended)

`CircuitTimeStepper.setup(component, time_step, *, carrier_frequency=..., frequencies=..., show_progress=...)` builds and connects a stepper for every element by **selecting that element's active-model time stepper** - a component with a dedicated stepper (laser, ring, modulator, photodiode) uses it directly; the pole-residue **S-matrix fitter is only the fallback** for a plain S-matrix model (`frequencies` is the spectral grid for that fallback fit; extra fit kwargs like `rms_error_tolerance=` are forwarded). Then `step` runs the whole input series at once. Because the laser and photodiode are inside the circuit, you feed only the electrical drive - the laser generates the optical carrier and the photodiode returns the detected signal. [end-to-end verified 1.5.0: 12-bit NRZ through this link gives a clean on/off; per-bit extinction is settling-limited at this baud, deepen it with more samples/bit]

```python
import numpy as np
import photonforge as pf

dt = 2e-14                                     # seconds (Nyquist ~25 THz baseband)
carrier = pf.C_0 / 1.31                        # Hz; pf.C_0 is um/s, wavelength in um
fit_bw = 0.5 / dt
fit_freqs = np.linspace(carrier - 0.9 * fit_bw, carrier + 0.9 * fit_bw, 151)

ts = pf.CircuitTimeStepper(verbose=False)
ts.setup(link, time_step=dt, carrier_frequency=carrier, frequencies=fit_freqs, show_progress=False)
# (no reset needed right after setup; call ts.reset() only to clear internal
#  state BETWEEN successive step runs of the same stepper)

spb  = 128
bits = np.array([0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0])
z0 = 50.0                                             # modulator electrical port impedance
v_swing = 1.5                                         # volts: 0 -> v_pi/2 = full on/off (v_pi=3)
drive = np.repeat(bits * v_swing / np.sqrt(z0), spb).astype(complex)  # port applies V = A*sqrt(Re(Z0))

out = ts.step(pf.TimeSeries({"DRIVE@0": drive}, time_step=dt), show_progress=False)
detected = np.real(np.asarray(out["OUT@0"]))         # index a TimeSeries by "port@mode"
```

Key points:

- **Carrier:** pass it once as `carrier_frequency` and **omit it from inputs**, which are baseband complex envelopes. Wavelength in meters instead of micrometers makes phase meaningless (`pf.C_0` is um/s).
- **Electrical drive convention (must scale by sqrt(Z0)):** an electrical port applies voltage `V = A*sqrt(Re(Z0))` from the fed complex amplitude `A`. So to apply a real voltage waveform, feed `A = V/sqrt(Re(Z0))` (at `Z0=50`, divide volts by ~7.07). Feeding raw volts over-drives by `sqrt(Z0)`. [verified 1.5.0]
- **Push-pull MZM extinction:** `mach_zehnder_modulator(v_pi=V)` in the default `drive="push-pull"` mode reaches full extinction at `V/2` **volts** (the two arms swing +/-V and hit differential pi at half `v_pi`). Combined with the scaling above, a clean on/off feeds amplitude `(v_pi/2)/sqrt(Re(Z0))`. [verified 1.5.0: transmission null at 1.5 V = fed amplitude 0.212 at Z0=50; feeding raw 1.5 applies ~10.6 V and only modulates by luck]
- **Sources/detectors inside the circuit are stepped for you** - do not hand-feed `cw_laser` / `photodiode` ports. If instead you build a passive circuit that exposes an optical INPUT port (no laser inside), feed its envelope as another `TimeSeries` entry, e.g. `{"IN@0": np.ones(N, dtype=complex), "DRIVE@0": drive}`.
- `step` takes and returns a `TimeSeries`; index outputs by `"port@mode"` and wrap with `np.asarray(...)`. Call it once on the full vector, never per sample.

## S-matrix Conventions

`SMatrix` is not a dict. Access by `(input, output)` port-mode keys - **input first, output second** [verified 1.5.0: a directional coupler with light in `P0` populates `("P0@0","P2@0")`/`("P0@0","P3@0")`]:

```python
s = component.s_matrix(frequencies)
s[("P0@0", "P1@0")]          # complex array vs frequency: input P0 mode 0 -> output P1 mode 0
list(s.elements.keys())       # all (input, output) keys
```

Key order follows `sorted(component.ports)`; confirm which key is through vs cross before wiring. Run FDTD for a single input only with `component.s_matrix(frequencies, model_kwargs={"inputs": ("P0",)})` (a whole port), or `model_kwargs={"inputs": ("P0@0",)}` to excite a single port MODE. Keep wavelengths in micrometers (`pf.C_0` is in um/s, so `frequency = pf.C_0 / 1.55`).

## Low-level: Pole-residue Fit + TimeDomainModel

Why this exists: an S-matrix is a frequency response, but time stepping needs an
impulse response. `pole_residue_fit` approximates the S-matrix as a rational
function (a sum of poles + residues), which has an exact, cheap time-domain
recurrence - that is how any S-matrix becomes a steppable time-domain model. The
high-level `CircuitTimeStepper` applies this fit automatically to any component that needs it (those without a dedicated stepper);
call `pole_residue_fit` yourself only for a STANDALONE S-matrix (e.g. measured
Touchstone) with no surrounding circuit.

`pole_residue_fit(s_matrix, *, min_poles=0, max_poles=30, rms_error_tolerance=1e-4, passive=True, stable=True, ...)` returns a `(PoleResidueMatrix, rms_error)` TUPLE - unpack it. Then build a `TimeDomainModel` and run the whole input vector in one `step` (never per sample): [verified PF 1.5.0]

```python
import numpy as np
import photonforge as pf

carrier = pf.C_0 / 1.31                          # the frequency your baseband envelope rides on
s = component.s_matrix(pf.C_0 / np.linspace(1.26, 1.36, 401))

# CRITICAL: TimeDomainModel steps a BASEBAND envelope at dt (Nyquist ~1/2dt << optical freq),
# so the fit must be about the carrier. Shift the S-matrix to baseband BEFORE fitting, or the
# model aliases and a CW input does NOT reproduce s_matrix(carrier). [verified 1.5.0: without
# the shift the CW through-port reads 0.53 vs the true 1.00; with it, 0.9999]
s_bb = pf.SMatrix(s.frequencies - carrier, s.elements, ports=s.ports)
prm, fit_rms = pf.pole_residue_fit(s_bb, max_poles=24, rms_error_tolerance=1e-4)   # TUPLE

dt = 2e-14
td = pf.TimeDomainModel(prm, time_step=dt)      # (pole_residue_matrix, time_step)
td.reset()

# a constant baseband envelope of 1.0 == CW at `carrier`
inputs = pf.TimeSeries({"P0@0": np.ones(8192, dtype=complex)}, time_step=dt)
out = td.step(inputs, show_progress=False)       # one call -> TimeSeries (NOT a per-sample loop)
through = np.asarray(out["P1@0"])
```

- `td.keys` lists the model's input/output `"port@mode"` keys (a `list`).
- Defaults keep the fit `passive=True` and `stable=True`; a poor fit (large
  `fit_rms`, too few poles) gives unstable traces - raise `max_poles` or narrow
  the band. Cross-check the CW steady state (constant `1.0` envelope) against
  `s_matrix(carrier)` - it matches to ~1e-4 when the fit is baseband-shifted
  (verified 1.5.0). If you'd rather not manage the shift, wrap the S-matrix in a
  `pf.DataModel` on a black-box component + `pf.CircuitModel()` and step it with
  `CircuitTimeStepper(carrier_frequency=...)`, which shifts internally (raise its
  `max_poles` above the default 6 for wideband/resonant data).
- Time-domain models cannot be attached to components; component models are
  frequency-domain only.

## Rings / MRMs: Parameters And The Rotating Frame

Configure a ring through `pf.abstract.ring_resonator` parameters rather than hand-deriving phases: `n_eff`, `n_group` (dispersion), `length`, `kappa1`/`kappa2`, `propagation_loss`, `reference_frequency`, and the electro-optic/thermo-optic tuning terms (`dn_dv`, `dn_dT`, ...). The stepper works in the rotating frame at the single `carrier_frequency` passed to `setup`; each ring's detuning follows from its `reference_frequency` and `n_eff` relative to that carrier.

The two parameters that most affect time-domain fidelity:

- **`n_group`** sets the round-trip group delay `n_group * length / pf.C_0` (use `pf.C_0`, which is µm/s, so it matches the µm `length` this skill uses everywhere - NOT the SI speed of light in m/s, which would underestimate the delay by ~1e6). The simulation must resolve it: keep the delay at least ~10 time steps (shrink `time_step` if needed), or sharp ring extinction is mangled.
- **`reference_frequency`** anchors the dispersive index. Across a WDM grid, keep it consistent for all channels (see pitfalls).

## Recurring WDM Ring-cascade Pitfalls

When cascading rings/MRMs at different channel frequencies:

1. **Missing dispersion (`n_group`).** Leaving `n_group=None` (so it defaults to `n_eff`) detunes channels far from the carrier. Set a realistic `n_group` on every ring.
2. **Inconsistent anchoring across channels.** Configure all channels against the same `reference_frequency` and carrier so their resonances line up symmetrically; per-channel ad-hoc anchoring makes the cascade asymmetric.
3. **Round-trip delay too small.** If `n_group * length / pf.C_0 / time_step` falls below ~10 samples, extinction is corrupted. Reduce `time_step` (raise samples-per-symbol). (`pf.C_0` is µm/s, matching the µm `length`; using SI `c` in m/s here underestimates the delay by ~1e6.)

## Detection: The Built-in Photodiode

Use `pf.abstract.photodiode` (backed by `PhotodiodeTimeStepper`) instead of hand-rolling detection and noise in numpy. It already models the full front-end:

```python
pd = pf.abstract.photodiode(
    responsivity=0.8,          # A/W
    gain=1e3,                  # TIA transimpedance, V/A
    dark_current=5e-9,         # A
    thermal_noise=1e-22,       # one-sided input-referred current PSD, A^2/Hz
    saturation_current=2e-3,   # space-charge saturation (0 disables)
    saturation_voltage=1.0,    # TIA output saturation (0 disables)
    filter_frequency=50e9,     # bandwidth low-pass (0 disables)
    seed=0,                    # reproducible noise
)
```

Include it as a component in the circuit so its electrical output port carries the detected photocurrent/voltage after `step`. It covers responsivity, dark current, thermal noise, space-charge and TIA saturation, pink (1/f) noise, and a bandwidth filter — shot noise and these effects are modeled internally, so a separate numpy noise pass is unnecessary.

**Electrical output units (same Z0 convention as the drive input, inverted).** Like every electrical port, the photodiode's `E0` output is a wave amplitude (sqrt(W)), not volts directly; its `z0` (default 50 Ω) is the port impedance that converts between the two. So to recover the physical voltage from the output wave amplitude, multiply by `sqrt(Re(z0))` — the inverse of the `V = A*sqrt(Re(z0))` drive convention above (divide that voltage by the TIA `gain` in V/A for photocurrent). `[verified 1.5.0 — photodiode docstring: z0 converts the output voltage to field amplitude]`

## Validation Checklist

- `circuit.add_model(pf.CircuitModel())` is present for a frequency-domain `s_matrix` call (the time stepper does not need it).
- Carrier omitted from inputs and passed once as `carrier_frequency`.
- `step` is called once on a full `TimeSeries`, not in a per-sample loop.
- Cross-check a CW (single-frequency) steady state against the frequency-domain S-matrix at that frequency.
- For rings, confirm the round-trip delay is at least ~10 time steps and `n_group` is set.
- For cascades, confirm channels share a consistent `reference_frequency`/carrier.
- Keep wavelengths/lengths in micrometers and times in seconds.
- For a standalone S-matrix fit, check `fit_rms` and passivity before stepping.
