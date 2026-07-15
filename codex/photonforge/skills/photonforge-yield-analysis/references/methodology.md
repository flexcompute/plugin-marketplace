# Variation-Aware Yield: Methodology

How to turn a bounded, one-time full-wave budget into unlimited circuit-level
yield statistics. Read this before designing a study.

## Why not brute-force Monte Carlo

Sampling the full circuit with a fresh FDTD run per random wafer is
combinatorially hopeless: hundreds of chips x several unique components x
several frequencies is thousands of paid simulations. Instead, characterize each
UNIQUE subcomponent once over its process corners, build a fast validated
surrogate, and let the circuit solver compose thousands of virtual chips for
free. The physics lives in the components; the statistics live in the circuit.

## Three layers

1. **Component surrogates.** For each unique scattering element (coupler, MMI,
   crossing, ...), run a small FDTD design-of-experiments over the variation
   axes (thickness Delta-t, width/CD Delta-w) and fit a smooth, validated
   surrogate. Propagation elements (straights, bends, tapers) need only remote
   multi-frequency mode solves -> a dispersive effective-index fit; no FDTD.
2. **Positional assignment.** Each virtual chip assigns every component instance
   its local (Delta-t, Delta-w) from the wafer maps and evaluates the circuit
   once (~1 s, zero simulations) via per-reference model updates.
3. **Wafer/lot Monte Carlo + statistics.** A hierarchical variation generator
   produces correlated wafer maps; a fixed chip sample plan measures the same
   sites on every wafer; metrics are aggregated into box plots, yield numbers,
   and lot/wafer/chip variance decompositions.

## Variation axes

Delta-t and Delta-w are quoted in NANOMETERS throughout, but PhotonForge lengths
are MICRONS: convert (x1e-3) at the one place they enter the layer stack, or a
+-4 nm corner silently becomes +-4 um. [verified 1.5.0]

- **Delta-t** — device-layer (silicon) thickness deviation, nm. Enters through
  the process/layer stack: re-instantiate the technology with the thickness
  kwarg, converting nm to um (e.g. `si_thickness=nominal + dt*1e-3`, NOT
  `nominal + dt`).
- **Delta-w** — waveguide width / CD deviation, nm, from litho + etch bias.
  Enters as a mask dilation: `MaskSpec(layer, dilation=dw*1e-3/2)` moves every
  drawn silicon edge by dw/2 nm, so cores widen by dw and gaps shrink by dw
  (physically the litho bias). Many PDKs expose this natively (a
  `si_mask_dilation` / `si_wg_bias` kwarg, also in um); if not, add one thin
  wrapper kwarg per guiding mask.
- **Optional third axis** — etch depth, slab thickness, sidewall angle, or
  temperature. Two axes are cleanly fit by low-order polynomials; move to
  Gaussian-process regression (scikit-learn) at 3-5 axes; consider a neural net
  only beyond 5. For a thermal axis, `AnalyticWaveguideModel.dn_dT` /
  `MuxDemuxModel.temperature_sensitivity` are the hooks.

Corner generation works identically for parametric cells and imported GDS
cells: for an imported cell, `comp.copy(True)` then reassign
`comp.technology = corner_tech` — no parametric rebuild needed.

## Choosing the parametrization by device class

Before inventing a surrogate decomposition for a new device class, read the
matching PhotonForge analytical model: its parameter set IS the physical
parametrization to anchor-and-perturb, its S-matrix structure encodes the
correct port relations and unitarity constraints, and it doubles as a
sanity cross-check for the fits.

| Device class | PF reference model | Anchor + fit vs (Delta-t, Delta-w) |
|---|---|---|
| Straight / bend / taper / 2-port | `TwoPortModel`, `AnalyticWaveguideModel` | n_eff(lambda)*L phase (+ loss); reflections usually negligible |
| Y-splitter / 1x2 MMI (3-port) | `PowerSplitterModel` (t, i, r) | split ratio + common phase + excess loss; isolation if the design cares |
| Directional coupler / 2x2 MMI | `DirectionalCouplerModel`, `AnalyticDirectionalCouplerModel` | the (theta, phi, a) scheme below; dual-thru variant for asymmetric paths |
| Waveguide crossing | `CrossingModel` (t, x, r) | transmission phase+loss, crosstalk x, reflection r — all scalar surfaces |
| Ring / racetrack (add-drop) | `RingModel` (kappa1, kappa2, n_eff, L, loss) | prefer the parameter-fit route: extract kappa's, n_eff, loss per corner and surface-fit THOSE |
| Coupled / dual ring | `DualRingModel` | same, with per-ring parameters |
| MZI as one block | `AnalyticMZIModel` | usually better decomposed into couplers+arms, but valid as a behavioral block |
| PSR / PBS / polarization | `PolarizationSplitterRotatorModel`, `PolarizationBeamSplitterModel` | NOT one unitary angle — fit the model's explicit s_ij set; polarization-crosstalk terms are the yield metric |
| WDM bank (behavioral) | `MuxDemuxModel` | band-level: center lambdas, bandwidth, IL; note `temperature_sensitivity` |
| Termination / stub | `TerminationModel` (r) | reflection magnitude+phase |

Coupler-class devices are the most-exercised; MMIs, crossings, grating couplers,
PSRs, and any thermal axis are less-travelled — validate hold-outs carefully and
lean on the matching analytical model as a cross-check.

## Two construction routes

- **Anchored-S route** (best for arbitrary geometry / imported cells, or when no
  compact analytical model fits). Store the nominal FDTD response exactly and fit
  only smooth perturbations that vanish at the origin. See the coupler class in
  `surrogate-and-wafer-code.md`.
- **Parameter-fit route** (best when a faithful analytical model exists — rings
  especially). Extract the model's own parameters (kappa, n_eff, loss) from each
  corner run, surface-fit those few scalars vs (Delta-t, Delta-w), and
  instantiate the analytical model per sample. Fewer coefficients,
  passive/unitary by construction, extrapolates best, and gauge/branch problems
  largely disappear because the fitted quantities are magnitudes and index-like
  scalars.
- **Metric-surface route** (best for a SINGLE component with no circuit
  composition). Skip the S-matrix entirely and fit the measured metrics (split
  ratio, excess loss, ... vs lambda, Delta-t, Delta-w) directly. Scalar,
  gauge-free, branch-free, anchored to the nominal curve. Use the unitary
  S-surrogate only when the component will be composed into a circuit.

Cross-check one route against another wherever both apply.

## Phase-correctness rules (what makes "right phase and delay" work)

- **Never fit the raw wrapped phase of S-elements.** Unwrap along lambda, then
  convert phase to an effective-index-like quantity phi(lambda) =
  2*pi*n_phi(lambda)*L / lambda with L the known physical path. Fit
  n_phi(lambda; Delta-t, Delta-w) — smooth, low-order, correctly extrapolating —
  and reconstruct phase exactly. Group delay is preserved by construction
  (it comes from dn/dlambda, which the fit carries).
- **Fit physical parameters, not S-elements.** For a lossless symmetric
  directional coupler: `S_thru = cos(theta)*a*exp(i*phi)`,
  `S_cross = i*sin(theta)*a*exp(i*phi)`. Fit theta(lambda; Dt, Dw) (coupling
  angle), n_phi (common phase index), and a small a(lambda; Dt, Dw) <= 1 (excess
  loss). Extract from FDTD: `theta = atan2(|S_cross|, |S_thru|)`,
  `phi = unwrapped common phase`.
- **Unitarity/reciprocity by construction.** Assembling coupler S-matrices from
  independent, slightly non-unitary runs compounds into spurious loss (or gain)
  through a cascade. A surrogate built from (theta, phi, a) is unitary and
  reciprocal PROVIDED you clamp a <= 1 (row power is a^2) and keep the
  cross-vs-thru phase deviation small; a large deviation breaks column
  orthogonality so S^H S exceeds I (artificial gain), so validate max singular
  value <= 1 per corner. Fitting raw complex S-elements independently is not
  unitary, and reintroduces exactly that failure. Declaring `port_symmetries`
  reduces FDTD inputs per corner, but treat symmetries as hypotheses (only the
  end-to-end Gate C arbitrates them; see `gates-and-traps.md`).

## Waveguides carry variation too

Bus/routing straights and bends are not variation-free — their effective index
shifts with Delta-t and Delta-w just like the couplers. Capture it with remote
multi-frequency mode solves on the same corner grid, fit
n_eff(lambda; Delta-t, Delta-w) (quadratic in each, ~18 coefficients), and inject
the fitted dispersive index into each waveguide instance during the Monte Carlo.
For a symmetric interferometer the arm-length imbalance is what converts arm
index shift into phase, so the arms often dominate the passband shift — never
model only the couplers.

## Hierarchical wafer/lot model

Per parameter p in {thickness, CD}, in nm:

    p(x, y) = delta_lot + delta_wafer + S(x, y) + G(x, y)

- **delta_lot, delta_wafer** — `N(0, sigma)` hierarchical offsets (lot-to-lot and
  wafer-to-wafer). These are usually the dominant, common-mode contributions and
  the reason a single collective tuner can recover a whole comb.
- **S(x, y)** — deterministic systematic map: a radial bow for thickness, an
  across-wafer tilt for CD.
- **G(x, y)** — a Gaussian-correlated random field (smooth white noise rescaled
  to sigma) with a physical correlation length: cm-scale for thickness,
  mm-scale for CD. Colocated components (rings a few um apart) see almost
  identical values — hence common-mode misalignment; components far apart
  decorrelate.

Evaluate the maps at EVERY component's absolute wafer position, with the chip
site in mm and the component-instance origin CONVERTED from um to mm (x1e-3):
adding raw um reads a 100 um offset as 100 mm and lands off the wafer. Do it per
instance (not once per chip) and give each instance its OWN (Delta-t, Delta-w),
so intra-chip gradients are captured; a single shared index per chip erases the
differential that shifts an unbalanced interferometer. Use a FIXED chip sample
plan (the same sites on every wafer) to mimic how a fab measures a wafer.
Calibrate every sigma and correlation length from the foundry DRM when available;
otherwise state literature-typical values as placeholders. Common-mode (tunable)
vs differential (untunable) split is the key reporting distinction for
collectively-tuned WDM designs.
