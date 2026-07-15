# Driving And Verifying The PhotonForge Cloud GUI

Use this reference when building or verifying schematics/applications on the cloud GUI. The pattern: manipulate state with the PDA SDK, verify what the user sees with a real browser driven by the Playwright MCP server.

## Contents

- Division of labor
- Playwright MCP setup
- Why a real browser
- The save-and-verify cycle
- Query geometry, do not deduce it
- Driving a simulation from Python
- Electrical drive units gotcha
- Reference-frequency gotcha
- Playwright recipes
- Reconnecting photonforge-server

## Division Of Labor

| Job | Tool |
|---|---|
| Create / update components, versions, library imports | PDA SDK |
| Create / arrange a schematic **Application** | GUI only ("New application"); the public SDK backs it with a component but does NOT create it |
| Run optical-circuit sims (analytic components) | `component.s_matrix(freqs)` + time-domain stepping, locally |
| Run FDTD-backed sims | `component.s_matrix(...)` (submits to the Tidy3D web service) |
| Read existing result data | PDA SDK |
| Plot results | matplotlib locally |
| Verify what the user sees in the GUI | Playwright MCP (screenshot + accessibility snapshot) |
| One-off GUI clicks the SDK cannot do | Playwright MCP (last resort) |

Building a plot or setting parameters by clicking through the GUI is slow and not reproducible; do it in Python and refresh the GUI. Treat the GUI as a verification surface.

## Playwright MCP Setup

This workflow needs a browser-automation MCP server. FIRST check whether one is already available in your runtime (look for `browser_navigate` / `browser_snapshot` / `browser_take_screenshot` tools); if not, register the Playwright MCP server (`@playwright/mcp`) with a persistent profile so SSO cookies stick. It ships for Claude Code, Codex, Copilot CLI, and Cursor - use your runtime's MCP-registration command (the args are the same); the Claude Code form is:

```bash
claude mcp add playwright --scope user -- \
  npx -y @playwright/mcp@latest \
  --browser=chrome \
  --user-data-dir="$HOME/.cache/playwright-mcp-profile"
# Codex:  codex mcp add playwright -- npx -y @playwright/mcp@latest --browser=chrome --user-data-dir=...
# (Copilot CLI / Cursor: add the same npx command via that tool's MCP config.)
```

If no browser MCP is available in a given runtime, do the SDK-side work + local self-checks (query ports, render `_repr_svg_`, spot-check the S-matrix) and tell the user to open the GUI URL and confirm visually - the verification step degrades to a human check rather than failing.

- `--browser=chrome` reuses the installed Chrome (better for SSO and matches what the user sees).
- `--user-data-dir=...` is the key flag: a persistent profile means the user logs in once and cookies persist across sessions.
- Default is headed (visible window); keep it so the user can watch. Add `--headless` for background runs, `--isolated` to discard the profile per session.

Playwright tool schemas may be deferred; load them before first use (e.g. `browser_navigate`, `browser_snapshot`, `browser_take_screenshot`, `browser_click`, `browser_wait_for`).

First-time SSO: ask the user to log in themselves in the visible browser window. Never enter the user's credentials. Once the persistent profile holds the session, later runs reach the GUI directly: navigating to a project URL follows the SSO redirect and renders the authenticated page, and the navigate -> snapshot -> screenshot loop then works without any further login. `[verified 1.5.0 - with an already-authenticated profile]`

## Why A Real Browser

A localhost-only or embedded preview cannot reach the cloud GUI: navigation lands on an error page, and the GUI blocks embedding - it serves `X-Frame-Options: DENY` and a Content-Security-Policy with `frame-ancestors 'none'`, so iframing it into locally served HTML fails too. (Its CSP `connect-src` does allow `http://localhost:8001` and `ws://localhost:8001` - that is how the browser app reaches your local `photonforge-server`.) Driving a real browser through the Playwright MCP is the reliable loop. `[verified 1.5.0 - response headers]`

## The Save-and-verify Cycle

1. Build a `pf.Component` (e.g. via `pf.component_from_netlist`).
2. Run sims locally (frequency and/or time) and save plots.
3. `project.add(...)` or `project.update(...)` (see the `photonforge-project-versioning` skill for the update/version gotchas).
4. `project.add_version(...)` to snapshot.
5. Create or open the schematic Application in the GUI (the public SDK loads/backs Applications but does not create them).
6. Use Playwright to navigate to the application URL and screenshot for verification.

## Query Geometry, Do Not Deduce It

Every concrete geometric question (which port is where, where a rotated reference lands, whether a length parameter inflates the bbox) has an exact answer from one attribute access. Use it; do not reason about transforms in your head. The bridge from a mental model to geometry fails silently and costs repeated save/screenshot rounds.

Before any `project.add` / `project.update`, print every reference's port positions in world coordinates and confirm the netlist connectivity agrees. `ref[port].center` returns the world-coordinate center *after* the full transform stack (origin, rotation, reflection), so it is ground truth, not your mental model `[verified 1.5.0]`:

```python
for ref in comp.references:
    for pname in ref.component.ports:
        cx, cy = ref[pname].center
        side = "ABOVE" if cy > 0.1 else ("BELOW" if cy < -0.1 else "MID")
        print(f"  {ref.component.name:<22} {pname}: y={cy:+.2f}  -> {side}")
```

If you are wiring a "top arm" to a specific port of an output combiner, this loop confirms in milliseconds whether that port actually means top after the transform stack you applied. Note that the GUI canvas flips Y relative to layout (layout y positive maps to canvas above); query, do not assume.

## Driving A Simulation From Python

Pull results via Python rather than clicking Run. Frequency domain:

```python
import numpy as np
import photonforge as pf

wl_nm = np.linspace(1260, 1360, 401)
freqs = pf.C_0 / (wl_nm * 1e-3)        # pf.C_0 is in um/s; wl in um
s = comp.s_matrix(freqs)
through = s[("IN@0", "OUT@0")]
```

Time domain - `CircuitTimeStepper.setup` accepts a `frequencies` keyword (the pole-residue fit grid) alongside `carrier_frequency` `[verified 1.5.0]`:

```python
dt = 5e-14
fit_bw = 0.5 / dt
fit_freqs = np.linspace(carrier - fit_bw*0.9, carrier + fit_bw*0.9, 201)

ts = pf.CircuitTimeStepper(verbose=False)
ts.setup(comp, time_step=dt, carrier_frequency=carrier, frequencies=fit_freqs)
V_TO_A = 1.0 / np.sqrt(50.0)                    # electrical port applies V = A*sqrt(Re(Z0))
out = ts.step(
    pf.TimeSeries({"IN@0": np.ones(N, dtype=complex),
                   "DRIVE@0": (v_drive * V_TO_A).astype(complex)},  # volts -> wave amplitude
                  time_step=dt),
    show_progress=False,
)
power = np.abs(np.asarray(out["OUT@0"])) ** 2
```

Save plots with the matplotlib Agg backend and read the image files back to view them inline. See the circuit-simulation skill for the full time-domain pipeline.

## Electrical Drive Units Gotcha

Electrical input is converted to voltage through the port impedance: `V = Re{A} * sqrt(Re(Z0))` (this is the formula in the modulator time-stepper's own docstring, and the implementation multiplies the real part of the input by `sqrt(Re(Z0))`). So a numpy waveform fed to a DRIVE port is field amplitude in sqrt(W), not volts. `[verified 1.5.0 - source]` With `Z0 = 50 ohm`, a unit-amplitude sine applies `sqrt(50) ~ 7.07 V`, roughly 7x more phase shift than intended, and a modulator DC transfer curve oscillates about 7x too fast.

Fix: scale the voltage waveform by `1/sqrt(Re(Z0))` before feeding the DRIVE port.

```python
Z0 = 50.0
V_TO_A = 1.0 / np.sqrt(Z0)
v_drive = (V_PI / 2) + 0.3 * V_PI * np.sin(2 * np.pi * f_rf * t)   # volts
inputs = pf.TimeSeries(
    {"IN@0": np.ones(N, dtype=complex),
     "DRIVE@0": (v_drive * V_TO_A).astype(complex)},
    time_step=dt,
)
```

Components whose sources output in sqrt(W) natively (signal sources) are already self-consistent; the conversion is only needed when hand-feeding a numpy voltage waveform.

## Reference-frequency Gotcha

The abstract `phase_modulator` has **no** `reference_frequency` argument - it is fixed near 1550 nm (193.4 THz). Waveguide-like abstract blocks (`straight`, `bend`, `directional_coupler`) default to that same 193.4 THz but *accept* a `reference_frequency` override. If two arms of a balanced interferometer end up on different reference frequencies (for example the waveguide arm overridden to an O-band carrier while a phase modulator stays fixed), the arms accumulate a wavelength-dependent phase mismatch and the device no longer sits at peak transmission (you see a few dB of loss across the band instead of near 0). Either let both arms default, or pass the same `reference_frequency` to every block that accepts it, and set `n_group` explicitly on both for consistency. `[verified 1.5.0 - phase_modulator has no reference_frequency kwarg; bend/directional_coupler default to 193.4 THz]`

## Playwright Recipes

Open the cloud GUI and screenshot:

```
browser_navigate        url=https://photonforge.simulation.cloud/projects
browser_take_screenshot type=jpeg filename=projects.jpeg
```

Find and click an element (refs are valid only for the latest snapshot):

```
browser_snapshot   depth=8                 # accessibility tree
browser_click      element="<short description>" target=eXX
```

Fit the schematic to view: click the "Fit all components in view" control (search the snapshot for that aria-label) after a refresh, since the GUI sometimes lands fully zoomed out.

## Reconnecting photonforge-server

When the GUI shows **"Local server - offline"**, the local `photonforge-server` is down (a fresh session or a restart does this). Prefer stopping the previous server gracefully (Ctrl-C in its terminal), then relaunch and reload the GUI tab so the status clears:

```bash
photonforge-server --log-level INFO
```

If the port is still held, **first check what owns it** and only kill a process you recognize as a stale `photonforge-server` - do not blindly SIGKILL whatever holds 8001 (it may be an unrelated user process), and confirm before killing anything you did not start:

```bash
lsof -i:8001            # inspect ownership FIRST (macOS/Linux); Windows: netstat -ano | findstr :8001
# then, only if it is a stale photonforge-server you started:  kill <pid>   (Windows: taskkill /PID <pid> /F)
```

`photonforge-server` listens on port **8001** by default and has **no** `--profile` flag. Most users just run `photonforge-server` (production credentials, default profile) — no environment variables needed. Only a development / multi-account setup needs to pick a non-default tidy3d credential profile, via the `TIDY3D_PROFILE` env var (tidy3d also honors `TIDY3D_CONFIG_PROFILE` / `TIDY3D_ENV`); if you are in that situation you already know you need it. `--log-level` accepts `DEBUG|INFO|WARNING|ERROR|CRITICAL`. `[verified 1.5.0]`

Then `browser_navigate` to the same URL again; the "Local server - offline" status clears only on a reconnect poll, which a reload forces.
