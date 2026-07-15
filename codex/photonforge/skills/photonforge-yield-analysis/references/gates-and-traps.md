# Variation-Aware Yield: Gates and Traps

The three blocking user gates in full, the non-negotiable numerical rules, and
the trap catalog assembled from real studies across several device classes and
foundries. Each rule was paid for in credits or days.

## The three blocking gates

### Gate A — pre-flight simulation plan (never launch without it)

Build the plan, quote it LIVE, present it in plain language, wait for explicit
approval.

1. **Enumerate the runs.** Unique scattering components (couplers / MMIs /
   crossings) need FDTD; propagation components (straights / bends) need only
   remote mode solves. Determine FDTD inputs per corner: declare
   `port_symmetries` but treat them as hypotheses (see traps). A coupler with
   inequivalent through paths (e.g. bus-to-ring) needs one extra input row.
2. **Pick the tier** (the DoE geometries; hold-outs are EXTRA runs beyond these,
   never carved out of them, and non-negotiable at every tier):
   - **quick estimate**: 5-run star (center + 4 axial) plus 1-2 hold-outs.
     Linear sensitivity slopes (fit `quadratic=False`) and a first yield number;
     an axial star cannot identify curvature or the cross term.
   - **standard**: 8-9-run DoE (e.g. a 3x3 grid) plus 2 hold-outs. The full
     quadratic response surface (6 geometric terms), the minimum for defensible
     statistics.
   - **high-confidence**: 11+ runs with 5 LEVELS on any axis needing cubic
     terms, plus 2-3 hold-outs. Adds curvature redundancy and cross-axis
     couplings.
   The DoE must be full geometric rank for the basis order you fit: the fit
   REFUSES a rank-deficient design (see `surrogate-and-wafer-code.md`), so a star
   cannot feed a quadratic basis and a 3-level axis cannot feed a cubic one.
3. **Quote cost LIVE, per distinct task shape.** Components do NOT all cost the
   same, and one corner is not one task: quote EACH unique component as (its
   corners) x (FDTD input-tasks per corner), then add the mode-solve line. A
   symmetric coupler may be one input-task per corner; an asymmetric / dual-thru
   coupler (inequivalent through paths) needs an extra input row, so its corner
   is two tasks. Upload one representative corner of EACH shape with
   `cost_estimation=True`, multiply by that shape's task count, and sum across
   shapes. Present: variations + ranges, tier, per-component task breakdown,
   total simulations, total estimated credits. Estimates are UPPER bounds (real
   cost often runs well below). Wait for sign-off.
4. **Spec sanity check.** Evaluate the NOMINAL device against the proposed spec
   BEFORE launching. If the nominal itself fails (e.g. a plain coupler cannot
   hold an absolute ratio window over a wide band), that is a design-bandwidth
   property, not process yield — surface it as a finding and offer the
   deviation-from-nominal spec framing.
5. **Tier pre-upgrade rule.** Predict the corner-box phase swing
   (|Delta-n|*L_path) and whether the coupling crosses an extremum (sweeps past
   3 dB) from CACHED/analytic index and the variation ranges, with NO paid solve
   at this stage. If phase swing > pi/2 or an extremum is crossed along an axis,
   plan 5 samples on that axis and cubic width terms UP FRONT and price them into
   the quote; do not discover them mid-study and come back for an overage. Any
   real index probe that spends credits belongs INSIDE this approved plan (run in
   the step-4 corner batch), never ahead of the gate.

### Gate B — post-fit showcase (before using any surrogate)

Show what the fitted models look like, framed as: "dots are the full-wave
simulations, lines are the fitted model — including the highlighted points the
fit never saw." Include the validation card per component, the sensitivity table
in device terms ("every 1 nm of extra silicon shifts your resonances by X nm;
every 1 nm of width by Y nm"), pass/fail against the accuracy gates, and credits
actually spent vs quoted. Proceed on confirmation.

### Gate C — end-to-end validation (before any Monte Carlo)

Compose the nominal circuit from the surrogates and overlay it against the
original full-physics circuit simulation. Present as: "the fast model reproduces
the full simulation of your complete circuit to X pm — safe to use for
statistics." Gate on metric-level agreement (expect pm-level when healthy). This
gate catches what component-level gates cannot — gauge and branch bugs are often
invisible until the full circuit is assembled. Show the overlay.

## Accuracy gates per surrogate

- anchor error < 1e-12 (modulo gauge sign)
- hold-out coupling-ratio error < 0.01
- hold-out phase error < 25 mrad (modulo pi)
- hold-out group-delay error < 20 fs

Interpret every gate against the DATA's own noise floor. Corner-to-corner FDTD
scatter at economy grids can exceed a gate on its own (order ~1.5 ratio points
at a coarse grid). When the fit hits that floor, do NOT iterate forever — present
the choice: accept with an explicit uncertainty band on all downstream
statistics, or re-run corners at higher fidelity (priced).

## Non-negotiable numerical rules

1. `pf.config.grid = 1e-5` in every training and ground-truth script — the
   coarser default quantizes eroded geometry (plateaus in n(Delta-w < 0)) and
   the error is invisible on-grid.
2. NEVER fit sensitivities from the LOCAL mode solver — it staircases geometry
   perturbations (observed dn/dt ~3x too low). Remote solves only. (If a local
   solver is required, confirm `tidy3d_extras` matches the `tidy3d` version, or
   subpixel is silently disabled.)
3. Hold-out points off the training grid are mandatory at every tier — every
   geometry-quantization and gauge bug was invisible on the training grid.
4. Symmetry hypotheses: coarse-grid `test_port_symmetries` can FALSE-PASS, and
   element-level audits of multi-input runs are gauge-ambiguous. Only Gate C
   arbitrates a symmetry.
5. Multi-input FDTD gauge: separate per-input tasks carry arbitrary port-mode
   signs (apparent exact-pi reciprocity violations, BETWEEN corners as well as
   between rows of one corner). Detect via the unitarity branch distance of the
   cross phase; repair by flipping the channel that does NOT set resonance
   positions; make validators gauge-aware (compare phases modulo pi, anchors
   modulo sign).
6. Corner phase wrap: long paths (> ~15 um) exceed |Delta-phi| = pi at far
   corners and the wrapped difference aliases SILENTLY (a naive |wrap| <= pi
   assert can never fire). Branch-resolve using the nominal phase slope
   (effective length) plus the waveguide Delta-n fit prediction.
7. Baseline discipline: all statistics compare against the all-surrogate (0,0)
   baseline, never against a different-fidelity composition.
8. Report costs as spent (`web.real_cost`) at the end and reconcile against the
   quote. Keep task IDs in `STUDY_LOG.md` as you launch — post-hoc `web.get_tasks`
   archaeology is unreliable.
9. Announce workflow steps and state changes throughout; silence during long
   batches is a defect.
10. Evaluate the nominal against the spec BEFORE any corner run; reframe
    design-property failures (bandwidth) as findings, not process yield.

## Trap catalog

- **Auto-detect port pairing.** Never hardcode thru/cross partners by topology;
  read them from the nominal S row (largest |S| = thru partner, second = cross).
  Real data overrules the geometric guess, especially for asymmetric couplers.
- **Dual-thru couplers.** A coupler whose two through paths are inequivalent
  (bus path vs ring arc) needs a second thru channel and its own phase fit; the
  cross phase then is (phi1 + phi2)/2 + pi/2 + delta to stay unitary. This costs
  one extra FDTD input row per corner — account for it at Gate A.
- **Null-safe phase extraction.** An overcoupled corner can sweep a single
  channel through an in-band amplitude null where its phase is undefined. Extract
  the common phase from the coherent sum `t_c*conj(t_nom) + c_c*conj(c_nom)`,
  which never vanishes for a unitary pair.
- **Two-pass branch resolution.** Resolve phase branches on a pi grid (2pi from
  wrapping PLUS pi from the per-task mode-sign gauge): first pass with the
  waveguide-probe predictor, defer near-midpoint corners, then arbitrate them
  with a fit built from the unambiguous corners.
- **Wide corner boxes break quadratic fits.** An honest +-3sigma CD span can
  sweep a coupler past its 3 dB point (sin^2 rollover); a quadratic surface then
  fails hold-outs. Use 5 samples on that axis and cubic/quartic width terms —
  and predict this at Gate A from the probe, not after a failed fit.
- **Nested reference updates.** Multi-level paths (outer, occ, inner, occ) work;
  never use a blanket (name, occ, None) update when surrogate models are among
  the children — target straights/bends by name so the surrogate kwargs are not
  clobbered.
- **Retry policy scales with runtime; never re-upload across processes.** Poll
  server task status until success, THEN collect. In-process restarts reuse the
  uploaded task; a restart from a NEW process may re-upload and re-bill (a
  long-running batch re-launched from a fresh process caused a duplicate,
  re-billed batch). Save collected data to npz incrementally.
- **Resonant metric extraction past FSR/2.** When shifts can exceed half an FSR,
  track with an analytic guide (arm/ring Delta-n) plus FSR folding; naive peak
  finding aliases. Report common-mode (tunable) vs differential (untunable)
  separately for collectively-tuned WDM.
- **NaN metrics hide box plots.** A single NaN silently removes a whole box in
  matplotlib. Filter NaN before plotting and report the unmeasurable count.

## Failure handling

- Surrogate gate fails → diagnose with random off-grid probes (sub-nm steps
  expose quantization; element tables expose gauge), fix, refit from cached npz
  (fits are pure CPU, free).
- Gate C off by ~FSR/2 → a gauge flip on the wrong channel.
- Composed circuit shows gain (> 0 dB) → non-unitary reconstruction (gauge or
  delta-branch); rebuild from physical parameters, not raw S-elements.
- Kill any running Monte Carlo the moment its baseline is suspect — every free
  chip after a bad baseline is wasted, and the wrong conclusion is worse than no
  conclusion.
