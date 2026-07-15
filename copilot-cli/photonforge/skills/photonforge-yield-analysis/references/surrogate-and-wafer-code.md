# Variation-Aware Yield: Code

Copy-adaptable building blocks. Verify APIs against the installed `photonforge`
version; the model base class and per-reference update paths have changed across
releases. All code assumes `import numpy as np` and `import photonforge as pf`.

## Polynomial basis

Two variation axes (dt, dw in nm) with a wavelength-dependent coefficient
(dlam = lambda - LAMBDA0 in um). The "full" basis (with constant) fits absolute
quantities like waveguide n_eff; the "perturbation" basis (no constant) fits
deviations that must vanish at the nominal corner. `quadratic=False` drops to a
linear (slopes-only) geometric basis for the quick tier; `w_cubic=True` adds
width cubics for a coupler swept past 3 dB. dt, dw stay in NANOMETERS here and
are converted to um only at technology instantiation (see "Corner construction").

```python
LAMBDA0 = 1.58  # um; expansion center for the wavelength basis

def design_matrix(dt, dw, wl, include_const, quadratic=True, w_cubic=False):
    """Basis rows for arrays dt, dw, wl (same length)."""
    dt, dw, wl = (np.asarray(x, float) for x in (dt, dw, wl))
    dlam = wl - LAMBDA0
    g = [np.ones_like(dt), dt, dw]           # linear (quick tier): 3 geo terms
    if quadratic:                            # curved surface (standard tier)
        g += [dt*dt, dt*dw, dw*dw]
    if w_cubic:                              # strongly width-nonlinear devices
        g += [dw**3, dt*dw**2]              # (e.g. coupler swept past 3 dB)
    if not include_const:
        g = g[1:]
    h = [np.ones_like(dlam), dlam, dlam*dlam]
    return np.stack([gi*hj for gi in g for hj in h], axis=-1)

def fit_surface(dt, dw, wl, values, include_const, quadratic=True, w_cubic=False,
                cond_max=1e8):
    """Least squares; returns (coeffs, rms_resid, max_resid). [verified 1.5.0]

    Rejects a rank-deficient / ill-conditioned design so lstsq cannot SILENTLY
    return a min-norm answer when the DoE has too few geometries for the basis
    order (a mandatory hold-out carved from a 5-run quick tier leaves 4 training
    geometries but a quadratic basis needs 6). Keeps `values` complex if complex,
    so an imaginary n_eff (propagation loss) survives into the insertion-loss
    statistics instead of being silently dropped by a float cast.
    """
    A = design_matrix(dt, dw, wl, include_const, quadratic, w_cubic)
    if np.linalg.matrix_rank(A) < A.shape[1]:
        raise ValueError(f"design under-determined: rank < {A.shape[1]} basis "
                         "terms; add DoE geometries or lower the basis order")
    sv = np.linalg.svd(A, compute_uv=False)
    if sv[0] / sv[-1] > cond_max:
        raise ValueError(f"design ill-conditioned (cond {sv[0]/sv[-1]:.1e})")
    values = np.asarray(values)              # NOT ...,float: keep complex (loss)
    coeffs, *_ = np.linalg.lstsq(A, values, rcond=None)
    resid = A @ coeffs - values
    return (coeffs.tolist(), float(np.sqrt(np.mean(np.abs(resid)**2))),
            float(np.abs(resid).max()))

def eval_fit(coeffs, wl, dt, dw, include_const, quadratic=True, w_cubic=False):
    """Evaluate a fitted surface at scalar (dt, dw) over a wavelength array."""
    wl = np.asarray(wl, float); dlam = wl - LAMBDA0
    g = [1.0, dt, dw]
    if quadratic: g += [dt*dt, dt*dw, dw*dw]
    if w_cubic: g += [dw**3, dt*dw**2]
    if not include_const: g = g[1:]
    g = np.array(g)
    h = np.stack([np.ones_like(dlam), dlam, dlam*dlam])   # (3, N)
    c = np.asarray(coeffs).reshape(g.size, 3)             # dtype-agnostic (complex ok)
    return (g @ c) @ h                                    # (N,)
```

Match the basis order to the DoE (verified 1.5.0): quick tier fits
`quadratic=False` (3 geometric terms, an axial star suffices); standard fits the
quadratic surface (6 terms, needs a 3x3-style grid); high-confidence adds
`w_cubic=True` and needs 5 LEVELS on the width axis. Hold-outs are EXTRA runs
beyond the DoE, never carved out of it; the rank guard fires if the DoE cannot
identify the basis. For a lossy (complex) fit, store the coeffs as separate real
and imag lists so JSON round-trips (json rejects complex), then recombine on load.

## Corner construction (nm -> um)

Delta-t and Delta-w are in NANOMETERS; PhotonForge lengths are in MICRONS. Convert
(x1e-3) at the ONE place the corner enters the layer stack; a raw `nominal + dt`
turns a +-4 nm corner into a +-4 um slab. Works the same for parametric and
imported cells. [verified 1.5.0]

```python
NOMINAL_T = 0.22  # um device-layer thickness (220 nm SOI)

def corner_technology(dt_nm, dw_nm):
    """Technology re-instantiated at one process corner. dt/dw in nm -> um."""
    return pdk_technology(                       # your PDK's tech factory
        si_thickness=NOMINAL_T + dt_nm * 1e-3,   # nm -> um  (NOT nominal + dt)
        si_mask_dilation=dw_nm * 1e-3 / 2.0,     # nm -> um; dilation d -> width +2d
    )
# imported GDS cell: comp = comp.copy(True); comp.technology = corner_technology(dt, dw)
```

If the PDK has no dilation kwarg, wrap one thin kwarg per guiding mask that
applies `MaskSpec(layer, dilation=dw_nm*1e-3/2)`, still nm -> um.

## Phase-exact waveguide surrogate (propagation, no FDTD)

```python
import warnings

def _check_domain(model, wl):
    """Guard against silent extrapolation: raise (strict) or warn. [verified 1.5.0]"""
    d = model.domain
    msgs = []
    if not (d["dt"][0]-1e-9 <= model.delta_t <= d["dt"][1]+1e-9):
        msgs.append(f"delta_t={model.delta_t} outside {d['dt']}")
    if not (d["dw"][0]-1e-9 <= model.delta_w <= d["dw"][1]+1e-9):
        msgs.append(f"delta_w={model.delta_w} outside {d['dw']}")
    if wl.min() < d["wl"][0]-1e-6 or wl.max() > d["wl"][1]+1e-6:
        msgs.append(f"wl [{wl.min():.4f},{wl.max():.4f}] outside {d['wl']}")
    if msgs:
        msg = f"{type(model).__name__}: extrapolation outside training domain: " + "; ".join(msgs)
        if model.strict:
            raise ValueError(msg)
        warnings.warn(msg)

class SurrogateWaveguide2Port(pf.Model):
    """S21 = exp(i 2pi n_eff(lam;dt,dw) L / lam). coeffs: 18-term full-basis fit."""
    def __init__(self, *, coeffs, domain, length=None, delta_t=0.0, delta_w=0.0, strict=True):
        super().__init__(coeffs=coeffs, domain=domain, length=length,
                         delta_t=delta_t, delta_w=delta_w, strict=strict)
        self.coeffs, self.domain, self.length = coeffs, domain, length
        self.delta_t, self.delta_w, self.strict = delta_t, delta_w, strict

    def n_eff(self, wl):
        wl = np.asarray(wl, float)
        _check_domain(self, wl)              # actually enforce the domain (no silent extrapolation)
        return eval_fit(self.coeffs, wl, self.delta_t, self.delta_w, include_const=True)

    def start(self, component, frequencies, **kwargs):
        f = np.asarray(frequencies, float); wl = pf.C_0 / f
        length = self.length
        if length is None:                       # correct for straights only;
            p = list(component.ports.values())   # pass arc length for bends
            length = float(np.hypot(*(np.asarray(p[1].center) - np.asarray(p[0].center))))
        s21 = np.exp(2j*np.pi*self.n_eff(wl)*length/wl)
        n = sorted(component.ports); k0, k1 = f"{n[0]}@0", f"{n[1]}@0"
        return pf.SMatrix(f, {(k0, k1): s21, (k1, k0): s21}, ports=dict(component.ports))
```

## Anchored-perturbation coupler surrogate (4-port)

The nominal FDTD response is stored EXACTLY (theta/amp/phi arrays on the
simulation wavelength grid) and reproduced bit-perfectly at (dt, dw) = (0, 0).
Variations add fitted smooth perturbations that vanish at the origin (no constant
term in the basis). Reconstruction through (theta, phi, amp) keeps the matrix
unitary-structured and reciprocal, so a long cascade cannot accumulate spurious
loss.

```python
def detect_pairing(s_nominal, in_ports=("P0", "P1")):
    """Derive thru/cross pairs from the NOMINAL |S| (largest = thru partner,
    second = cross), overruling the topological P2/P3 guess for asymmetric
    couplers. Returns (thru_pairs, cross_pairs). Validate + pass to the model at
    BUILD time; never rely on the topology default alone. [verified 1.5.0]"""
    mid = len(next(iter(s_nominal.elements.values()))) // 2   # mid-band sample
    thru_pairs, cross_pairs = [], []
    for a in in_ports:
        row = {k[1].split("@")[0]: abs(v[mid])
               for k, v in s_nominal.elements.items() if k[0] == f"{a}@0"}
        ranked = sorted(((p, m) for p, m in row.items() if p not in in_ports),
                        key=lambda pm: pm[1], reverse=True)
        if len(ranked) < 2 or ranked[1][1] < 1e-6:
            raise ValueError(f"port {a}: cannot resolve thru/cross from |S|={row}")
        thru, cross = ranked[0][0], ranked[1][0]
        thru_pairs += [[a, thru], [thru, a]]
        cross_pairs += [[a, cross], [cross, a]]
    return thru_pairs, cross_pairs

class SurrogateCoupler4Port(pf.Model):
    """Nominal stored as theta_nom (coupling angle), amp_nom (transmission),
    phi_nom (unwrapped common thru phase), delta_nom (cross-vs-thru deviation
    from ideal +pi/2). Perturbation coeffs: {"dtheta":[...], "dphi":[...],
    "dlogamp":[...]} (+ "dphi2" for a dual-thru coupler).
    Ports: P0,P1 in / P2 thru of P0 / P3 cross of P0. Pass thru_pairs/cross_pairs
    from detect_pairing(nominal_S) at build; the P2/P3 defaults are only a
    last-resort fallback and are WRONG for a cross-dominant / asymmetric coupler."""
    DEFAULT_THRU  = [["P0","P2"],["P2","P0"],["P1","P3"],["P3","P1"]]
    DEFAULT_CROSS = [["P0","P3"],["P3","P0"],["P1","P2"],["P2","P1"]]

    def __init__(self, *, wl_grid, theta_nom, amp_nom, phi_nom, delta_nom,
                 coeffs, domain, delta_t=0.0, delta_w=0.0, strict=True,
                 thru_pairs=None, cross_pairs=None,
                 phi2_nom=None, thru2_pairs=None, w_cubic=False):
        super().__init__(wl_grid=wl_grid, theta_nom=theta_nom, amp_nom=amp_nom,
                         phi_nom=phi_nom, delta_nom=delta_nom, coeffs=coeffs,
                         domain=domain, delta_t=delta_t, delta_w=delta_w, strict=strict,
                         thru_pairs=thru_pairs, cross_pairs=cross_pairs,
                         phi2_nom=phi2_nom, thru2_pairs=thru2_pairs, w_cubic=w_cubic)
        wl_grid   = np.asarray(wl_grid, float)
        order     = np.argsort(wl_grid)      # np.interp needs ASCENDING xp; a grid
        self.wl_grid   = wl_grid[order]      # built from C_0/freqs is DESCENDING
        self.theta_nom = np.asarray(theta_nom, float)[order]
        self.amp_nom   = np.asarray(amp_nom, float)[order]
        self.phi_nom   = np.asarray(phi_nom, float)[order]
        self.delta_nom = np.asarray(delta_nom, float)[order]
        self.coeffs, self.domain = coeffs, domain
        self.delta_t, self.delta_w, self.strict, self.w_cubic = delta_t, delta_w, strict, bool(w_cubic)
        self.thru_pairs  = [tuple(p) for p in (thru_pairs  or self.DEFAULT_THRU)]
        self.cross_pairs = [tuple(p) for p in (cross_pairs or self.DEFAULT_CROSS)]
        self.phi2_nom    = None if phi2_nom is None else np.asarray(phi2_nom, float)[order]
        self.thru2_pairs = [tuple(p) for p in (thru2_pairs or [])]

    def channels(self, wl):
        """(thru, thru2, cross) at wl; thru2 is None for a symmetric coupler."""
        wl = np.asarray(wl, float)
        _check_domain(self, wl)              # enforce the training domain
        wc = self.w_cubic
        theta = np.interp(wl, self.wl_grid, self.theta_nom) + eval_fit(self.coeffs["dtheta"],   wl, self.delta_t, self.delta_w, include_const=False, w_cubic=wc)
        phi   = np.interp(wl, self.wl_grid, self.phi_nom)   + eval_fit(self.coeffs["dphi"],     wl, self.delta_t, self.delta_w, include_const=False, w_cubic=wc)
        amp   = np.interp(wl, self.wl_grid, self.amp_nom)   * np.exp(eval_fit(self.coeffs["dlogamp"], wl, self.delta_t, self.delta_w, include_const=False, w_cubic=wc))
        amp   = np.minimum(amp, 1.0)         # passivity: row power = amp^2 <= 1 (no gain)
        delta = np.interp(wl, self.wl_grid, self.delta_nom)
        thru = amp*np.cos(theta)*np.exp(1j*phi)
        if self.phi2_nom is None:
            return thru, None, amp*np.sin(theta)*np.exp(1j*(phi + np.pi/2 + delta))
        phi2 = np.interp(wl, self.wl_grid, self.phi2_nom) + eval_fit(self.coeffs["dphi2"], wl, self.delta_t, self.delta_w, include_const=False, w_cubic=wc)
        thru2 = amp*np.cos(theta)*np.exp(1j*phi2)
        cross = amp*np.sin(theta)*np.exp(1j*((phi+phi2)/2 + np.pi/2 + delta))   # unitary-structured
        return thru, thru2, cross

    @staticmethod
    def _project_passive(el, ports, f, tol=1e-9):
        """Scale the reconstructed S onto the passive set (max singular value <= 1
        at every frequency) WITHOUT inventing off-structure paths. Clamping `amp`
        alone bounds each ROW's power but not S^H S: a non-zero `delta` (cross-vs-
        thru phase) makes the columns non-orthogonal, so a 2x2/4x4 coupler can
        still show sigma_max > 1. A per-frequency SVD *clamp* gives the closest
        passive matrix but fills in reflection/isolation entries an ideal coupler
        does not have; keeping only the declared keys then DROPS those corrections
        and can leave sigma_max > 1. Instead, uniformly scale every declared entry
        by 1/sigma_max at any frequency where sigma_max > 1: that is
        structure-preserving (undeclared paths stay exactly zero) AND guarantees
        sigma_max <= 1 exactly, since M/sigma_max has sigma_max = 1. Assumes one
        mode per port (all keys end in '@0')."""
        names = list(ports)
        idx = {n: i for i, n in enumerate(names)}
        n, nf = len(names), len(f)
        M = np.zeros((nf, n, n), complex)
        for (a, b), v in el.items():
            M[:, idx[a.split("@")[0]], idx[b.split("@")[0]]] = v
        smax = np.linalg.svd(M, compute_uv=False).max(axis=1)   # sigma_max per frequency
        if smax.max() <= 1.0 + tol:
            return el                                           # already passive; no-op
        scale = 1.0 / np.maximum(smax, 1.0)                     # <=1 where over-unity, else 1
        return {k: el[k] * scale for k in el}                   # scale declared entries; zeros stay zero

    def start(self, component, frequencies, **kwargs):
        f = np.asarray(frequencies, float); wl = pf.C_0 / f
        thru, thru2, cross = self.channels(wl)
        el = {}
        for a, b in self.thru_pairs:  el[(f"{a}@0", f"{b}@0")] = thru
        for a, b in self.thru2_pairs: el[(f"{a}@0", f"{b}@0")] = thru2 if thru2 is not None else thru
        for a, b in self.cross_pairs: el[(f"{a}@0", f"{b}@0")] = cross
        ports = dict(component.ports)
        el = self._project_passive(el, ports, f)           # enforce sigma_max <= 1
        return pf.SMatrix(f, el, ports=ports)

pf.register_model_class(SurrogateWaveguide2Port, SurrogateCoupler4Port)  # for .phf round-trip
```

Passivity is subtle here. Clamping `amp <= 1` bounds each ROW's power (`amp^2`)
but NOT `S^H S`: a non-zero `delta_nom` (cross-vs-thru phase) makes the columns
non-orthogonal, so a coupler can still show max singular value `> 1` (artificial
gain) even with `amp <= 1`. `_project_passive` above fixes this by uniformly
scaling every declared entry by `1/sigma_max` at any frequency where
`sigma_max > 1`: that is structure-preserving (it never invents the
reflection/isolation paths an ideal coupler lacks) AND guarantees `sigma_max <= 1`
exactly. A plain SVD clamp would be the closest passive matrix, but once you keep
only the declared thru/cross keys it can still leave `sigma_max > 1` — the scaling
avoids that. It is a no-op when the matrix is already passive. Still keep
`delta_nom` the small measured residual (not an arbitrary offset) so the scaling
stays a tiny correction, and it is good practice to assert `max singular value
<= 1 + tol` on each corner's reconstructed S as a cross-check before trusting the
cascade. [verified 1.5.0]

Notes verified in practice:
- `__init__` MUST call `super().__init__(**all_kwargs)` — that is what makes the
  model updatable (`model.update(delta_t=...)` re-calls `__init__` with merged
  kwargs).
- `start()` must pass `ports=dict(component.ports)` to `pf.SMatrix`.
- Add a domain guard that raises (strict) or warns when (dt, dw, wl) fall outside
  the training box — extrapolation is where surrogates lie.
- Store fits as plain JSON (kind + kwargs) so they reload without the training
  data, and keep the nominal FDTD channels in the kwargs so serialization is
  self-contained.

## Rings: the parameter-fit route (no anchored-S needed)

For a ring/racetrack, don't fit its S-matrix - fit the few PHYSICAL parameters of
`pf.RingModel` and re-instantiate it per sample. Passive/unitary by construction,
gauge/branch-free (the fitted quantities are magnitudes + index-like scalars),
and extrapolates best. Extract `kappa1`, `kappa2`, `n_eff`, `n_group`, `loss` from
each corner run (or a coupler + waveguide sub-fit), surface-fit each scalar vs
(dt, dw) with `fit_surface`, then:

```python
# per Monte-Carlo sample, at this instance's (dt, dw):
k1  = eval_fit(coeffs["kappa1"],  wl, dt, dw, include_const=True)[i0]  # scalar per corner
neff= eval_fit(coeffs["n_eff"],   wl, dt, dw, include_const=True)      # dispersive, complex OK
loss= float(eval_fit(coeffs["loss"], wl, dt, dw, include_const=True)[i0])
ring_model = pf.RingModel(kappa1=complex(k1), kappa2=complex(k2), n_eff=neff,
                          length=L, propagation_loss=loss, n_group=ng,
                          reference_frequency=f_ref)
# attach as the ring instance's model, or inject via model_updates in the s_matrix call
```

Keep `n_group` (dispersion) and a consistent `reference_frequency` across a WDM
cascade (same pitfalls as the circuit sim). Cross-check the fitted `RingModel`
against the anchored-S route where both apply.

## Surrogates as first-class PCell models

Attach the surrogate as a NAMED model slot beside the ground-truth model, so a
variation-aware PCell is just a component you can serialize:

```python
coupler.add_model(SurrogateCoupler4Port(...), "Surrogate")   # keep "Tidy3D" too
coupler.activate_model("Surrogate")                           # NOT set_active_model
# pf.write_phf(path, filter_component) / pf.load_phf(path) round-trips
# the surrogate, its coefficients, and the active slot.
```

## Positional assignment (per-reference updates)

One virtual chip = one circuit evaluation with each instance carrying ITS OWN
(dt, dw), read at that instance's wafer position. A single blanket update with
one shared index (`("ARMS.*", -1, ...)` + one `n_fit`) collapses every arm to the
same corner and erases the intra-chip differential, which is exactly what shifts
an unbalanced-MZI passband. Assign per instance: [verified 1.5.0]

```python
import re                                                # for re.escape() below

updates = {}
# each ARM reference: its own (dt, dw) from its own wafer position ->
# inject the fitted dispersive index (no mode solve in the loop)
for name, occ, dt_i, dw_i in arm_assignments:          # one row per arm reference
    n_fit = eval_fit(arm_coeffs, wl, dt_i, dw_i, include_const=True)[np.newaxis, :]
    updates[(re.escape(name), occ, None)] = {"model_updates": {"n_complex": n_fit}}
# each coupler reference: its own corner
for name, occ, dt_i, dw_i in coupler_assignments:
    updates[(re.escape(name), occ)] = {"model_updates": {"delta_t": dt_i, "delta_w": dw_i}}
s = circuit.s_matrix(freqs, model_kwargs={"updates": updates})
```

Key forms (verified 1.5.0): `(name, occ)` targets one occurrence of a leaf
component's own model; `(name, occ, None)` descends into an arm that is itself a
sub-circuit and updates the waveguide models inside. `occ = -1` targets ALL
occurrences of a name, acceptable ONLY for a deliberate common-mode estimate or
when every instance of that name sits within one correlation length (so they
truly share a corner); otherwise it silently drops the positional differential.
Never use a blanket `(name, -1, None)` when surrogate models are among the
children whose kwargs differ from a plain waveguide's (the blanket update will
clobber them). `WaveguideModel(n_complex=<2D array (modes, N_freq)>)` skips the
mode solve entirely; match the frequency order to the `s_matrix` call, and
`re.escape()` the hash-suffixed parametric names.

## Hierarchical wafer/lot generator

```python
from scipy.interpolate import RegularGridInterpolator
from scipy.ndimage import gaussian_filter

CONFIG = {  # calibrate every number from the foundry DRM when available
    "wafer_radius_mm": 100.0, "edge_exclusion_mm": 15.0, "chip_pitch_mm": 6.0, "grid_n": 257,
    "thickness": {"sigma_lot": 2.0, "sigma_wafer": 2.0, "radial_bow": -3.0, "gp_sigma": 1.5, "gp_corr_mm": 25.0},
    "cd":        {"sigma_lot": 2.5, "sigma_wafer": 2.5, "tilt":       2.0, "gp_sigma": 3.0, "gp_corr_mm":  5.0},
}

def _gp_field(rng, n, extent_mm, sigma, corr_mm):
    dx = extent_mm / (n - 1)
    field = gaussian_filter(rng.standard_normal((n, n)), sigma=corr_mm/(2*dx), mode="wrap")
    return field * (sigma / field.std())

def sample_lot_offsets(rng, cfg=CONFIG):
    return (rng.normal(0, cfg["thickness"]["sigma_lot"]), rng.normal(0, cfg["cd"]["sigma_lot"]))

def sample_wafer(rng, lot_offsets, cfg=CONFIG):
    R, n = cfg["wafer_radius_mm"], cfg["grid_n"]
    ax = np.linspace(-R, R, n); X, Y = np.meshgrid(ax, ax, indexing="ij")
    r2 = (X**2 + Y**2) / R**2
    ct, cw = cfg["thickness"], cfg["cd"]
    t = lot_offsets[0] + rng.normal(0, ct["sigma_wafer"]) + ct["radial_bow"]*(r2-0.5) + _gp_field(rng, n, 2*R, ct["gp_sigma"], ct["gp_corr_mm"])
    w = lot_offsets[1] + rng.normal(0, cw["sigma_wafer"]) + cw["tilt"]*(X/R)          + _gp_field(rng, n, 2*R, cw["gp_sigma"], cw["gp_corr_mm"])
    # fill_value=np.nan (NOT None): an off-grid query returns NaN instead of
    # silently EXTRAPOLATING a wafer map beyond its edge.
    return (RegularGridInterpolator((ax, ax), t, bounds_error=False, fill_value=np.nan),
            RegularGridInterpolator((ax, ax), w, bounds_error=False, fill_value=np.nan))

def chip_sites(n_chips, cfg=CONFIG, seed=1234):
    """Fixed measurement sample plan: the same sites on every wafer."""
    R = cfg["wafer_radius_mm"] - cfg["edge_exclusion_mm"]; pitch = cfg["chip_pitch_mm"]
    ax = np.arange(-cfg["wafer_radius_mm"], cfg["wafer_radius_mm"]+pitch, pitch)
    XX, YY = np.meshgrid(ax, ax); ok = XX**2 + YY**2 < R**2
    cand = np.stack([XX[ok], YY[ok]], axis=1)
    idx = np.random.default_rng(seed).choice(len(cand), size=min(n_chips, len(cand)), replace=False)
    return cand[np.sort(idx)]

def instance_dt_dw(t_itp, w_itp, chip_xy_mm, instance_origin_um, cfg=CONFIG):
    """(dt, dw) at one instance. Chip/interpolator coords are mm; PF instance
    origins are um -> x1e-3. Reject out-of-wafer coords (do NOT extrapolate).
    [verified 1.5.0]"""
    x = chip_xy_mm[0] + instance_origin_um[0] * 1e-3      # um -> mm
    y = chip_xy_mm[1] + instance_origin_um[1] * 1e-3
    if x*x + y*y > cfg["wafer_radius_mm"]**2:
        raise ValueError(f"instance at ({x:.2f},{y:.2f}) mm is off-wafer")
    pt = [[x, y]]
    return float(t_itp(pt)[0]), float(w_itp(pt)[0])
```

Query at the absolute wafer position of every component instance: chip site (mm)
plus the instance origin CONVERTED from um to mm (x1e-3, as in `instance_dt_dw`).
Adding raw um reads a 100 um offset as 100 mm and lands off the wafer. Do this
per instance (not once per chip) so intra-chip gradients are captured. Report
per-wafer box plots grouped by lot, a histogram + yield vs spec, and a
lot/wafer/chip variance decomposition. Filter NaN metrics before plotting
(matplotlib hides a whole box on a single NaN) and report the unmeasurable count.
Save results to an npz so plots regenerate without re-running the campaign.
