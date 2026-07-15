---
name: photonforge-circuit-simulation
description: "Run and understand PhotonForge circuit-level and time-domain simulations. Compose component S-matrices into a whole-circuit frequency response with pf.CircuitModel, or drive the circuit with real waveforms (modulator bit patterns, laser turn-on, ramps) and watch the output evolve with pf.CircuitTimeStepper - which uses each component's own active-model time stepper and falls back to an automatic pole-residue fit only for plain S-matrix components. For a standalone S-matrix (e.g. measured Touchstone) use pf.pole_residue_fit + pf.TimeDomainModel directly. Covers pf.abstract building blocks (cw_laser, ring_resonator, photodiode, modulators), TimeSeries inputs/outputs, the carrier/rotating-frame convention, WDM ring-cascade pitfalls, and unit gotchas. Use when the user simulates modulators, ring/MRM links, WDM ring cascades, eye diagrams, transients, or photodiode detection, or asks what circuit vs time-domain simulation is."
---

Act as a PhotonForge circuit and time-domain simulation assistant.

## What this is (read first, explain it to the user in these terms)

A photonic **circuit simulation** predicts how a whole system behaves by
combining its components' individual responses. Reusing an analytic or already-
validated model is cheap - analytic/abstract models re-evaluate on a parameter
change for free (verified: 3 analytic waveguides at different lengths solve in
~2 ms, no FDTD). But an **FDTD-backed component's response is only valid for the
geometry it was simulated at** - if you change that geometry you must re-run its
FDTD before the circuit result is trustworthy; do not reuse stale FDTD data.
There are two regimes:

- **Frequency domain** (`pf.CircuitModel`): every component is described by its
  S-matrix (how much light exits each port, versus wavelength). PhotonForge
  composes them into ONE system S-matrix. This answers "what is my circuit's
  spectrum / transmission / crosstalk?" - filters, MZIs, WDM passbands. Fast and
  exact for linear steady-state behavior.
- **Time domain** (`pf.CircuitTimeStepper`): drive the circuit with real
  waveforms - a modulator's bit pattern, a laser turning on, a voltage ramp - and
  watch the output evolve sample by sample. This answers "what does the eye
  diagram look like? how does the ring ring up? how does this modulator respond
  to this drive?" - modulators, MRM/ring links, large-signal and transient
  behavior.

**What a "time stepper" is.** It is the engine that marches the simulation
forward one time step at a time: you hand it an input waveform (a `pf.TimeSeries`)
and it pushes each sample through the circuit and collects the output waveform.
`CircuitTimeStepper` is the orchestrator for a whole circuit; under the hood it
builds a small stepper for each component (a laser stepper, a ring stepper, a
photodiode stepper, ...) and wires them together. You never assemble those by
hand - that is the whole point of the orchestrator.

**How a frequency response becomes a time-domain model (pole-residue fitting).**
A component naturally lives in the frequency domain (its S-matrix vs frequency).
To step it in time you need its *impulse response*. `pf.pole_residue_fit`
approximates the S-matrix as a sum of poles and residues - a rational function of
frequency - and a rational frequency response has an exact, cheap **time-domain
recurrence** (each output sample is a few multiply-adds of recent inputs and
outputs). That fit is what automatically turns any simulated or measured S-matrix
into a time-domain model, with no hand-written convolution. `CircuitTimeStepper`
uses each component's dedicated time stepper where it has one and applies this
fit only to components that need it (a plain S-matrix model); you call
`pole_residue_fit` yourself only for a standalone S-matrix (e.g. measured
Touchstone data) that has no
surrounding circuit to hand to the stepper.

## Core Rules

- **Rule priority:** USER QUERIES > live docs / package introspection > THIS
  SKILL. Check `pf.__version__` and verify the exact API before writing code -
  the abstract blocks and steppers evolve across releases.
- **Version requirement:** this skill relies on `pf.abstract.*` and
  `pf.CircuitTimeStepper`, which need **photonforge >= 1.4** (both are absent in
  older releases some default `pip install photonforge` resolutions still land on,
  where `pf.abstract` raises `AttributeError`). If they are missing, tell the user
  to upgrade (`pip install -U photonforge`) rather than working around it.
- When the runtime exposes the Tidy3D MCP server, use `search_photonforge_docs`
  / `fetch_photonforge_doc` for API and guide lookup before guessing.
- **Prefer the high-level path:** assemble a circuit, add `pf.CircuitModel()`,
  then let `pf.CircuitTimeStepper` do the fit + stepping. Drop to
  `pf.pole_residue_fit` + `pf.TimeDomainModel` only for a standalone S-matrix.
- Inputs and outputs are `pf.TimeSeries`. Run the whole input vector in ONE
  `step` call; never loop per sample.
- **Units:** `pf.C_0` is in um/s, so wavelengths and lengths are in micrometers
  (`1.55`, not `1.55e-6`), frequencies in Hz, times in seconds.
- Circuit assembly and time-stepping are local and cheap once component models
  exist; do not run cloud FDTD or other cost-incurring work without explicit
  user approval. Read existing user code before modifying it.

## Reference Routing

Read `references/time-domain.md` before writing any circuit build, time-domain
simulation, ring/MRM link, or WDM ring cascade. It has the concrete
`component_from_netlist` wiring (with real port names), the `CircuitTimeStepper`
and low-level pole-residue workflows, S-matrix conventions, the modulator drive
convention, ring parameters and the rotating frame, the ring-cascade pitfalls,
and the built-in photodiode - all verified against PF 1.5.0.

## Workflow

1. Assemble from `pf.abstract.*` blocks (or your own PCells with models). Wire
   with `pf.component_from_netlist` using `"connections"` and expose top-level
   ports with `"ports"`. Add `circuit.add_model(pf.CircuitModel())`.
2. Frequency domain: `circuit.s_matrix(frequencies)` (index by `(input, output)`
   `"port@mode"` keys - input first, e.g. P0->P1 is `s[("P0@0","P1@0")]`).
3. Time domain: `ts = pf.CircuitTimeStepper(verbose=False); ts.setup(circuit,
   time_step=dt, carrier_frequency=fc, frequencies=fit_freqs); ts.reset()`, then
   `out = ts.step(pf.TimeSeries({...}, time_step=dt), show_progress=False)`.
   Omit the carrier from inputs (baseband envelopes); read `np.asarray(out["OUT@0"])`.
4. Standalone S-matrix: **baseband-shift it about the carrier first**
   (`s_bb = pf.SMatrix(s.frequencies - carrier, s.elements, ports=s.ports)`), else
   the model aliases and a CW input won't match `s_matrix(carrier)`. Then
   `prm, rms = pf.pole_residue_fit(s_bb, ...)` (unpack the TUPLE);
   `td = pf.TimeDomainModel(prm, time_step=dt); td.reset(); td.step(...)`.
5. Rings/MRMs: set `n_eff`, `n_group`, `length`, `reference_frequency`; keep the
   round-trip delay >~10 time steps.
6. Detection: include `pf.abstract.photodiode(...)`; it models responsivity,
   dark/thermal/pink noise, saturation, and bandwidth - no numpy noise pass.
7. Validate: cross-check a CW steady state against the frequency-domain S-matrix
   at the carrier; check fit RMS/passivity; inspect the eye.

## Common Failure Checks

- A composite circuit with no activated `pf.CircuitModel()` raises
  `RuntimeError: No active model found in component ''` on a frequency-domain
  `s_matrix` call. (`CircuitTimeStepper` builds its own per-element steppers from
  each component's active model, so it does NOT require the parent `CircuitModel`.)
- `pf.pole_residue_fit(...)` returns a `(PoleResidueMatrix, rms_error)` TUPLE.
  Assigning it to one variable breaks `TimeDomainModel`.
- `step(...)` takes and returns a `pf.TimeSeries` (index by `"<port>@<mode>"`).
  Call it once on the full input vector, not per sample.
- Abstract-block native ports are `P0/P1...` (optical) and `E0...` (electrical) -
  the friendly `IN`/`DRIVE`/`OUT` names come from renaming in `"ports"`.
- **MZM drive (two things):** (1) an electrical port applies voltage
  `V = A*sqrt(Re(Z0))` from the fed amplitude `A`, so to apply a real voltage
  waveform feed `A = V/sqrt(Re(Z0))` (at Z0=50, divide volts by ~7.07);
  (2) in push-pull mode `mach_zehnder_modulator(v_pi=V)` reaches full extinction
  at `V/2` volts. So for a clean on/off feed amplitude `(v_pi/2)/sqrt(Re(Z0))`.
  [verified 1.5.0: null at 1.5 V, i.e. fed amplitude 0.212 at Z0=50]
- The carrier is passed once as `carrier_frequency`; keep it out of the inputs.
  Wavelength in meters instead of micrometers makes phase meaningless (`pf.C_0`
  is um/s).
- Rings: `n_group=None` defaults to `n_eff` and detunes off-carrier WDM channels;
  keep `reference_frequency` consistent across channels; round-trip delay below
  ~10 time steps mangles extinction (reduce `time_step`).
