---
name: photonforge-gui-automation
description: "Drive and verify the PhotonForge cloud GUI (photonforge.simulation.cloud) from an AI coding session. Make the edits programmatically with the PhotonForge PDA SDK - create and update projects, components, and versions - then drive a real web browser with the Playwright MCP server to open, screenshot, and confirm what the user actually sees in the GUI (the project list, a schematic, port placement, wire routing). The established pattern is 'PDA SDK controls, Playwright verifies': treat the GUI as a verification surface, not a control surface. Use when the user wants to build, edit, or visually verify schematics and applications on the cloud GUI, position a circuit correctly in a schematic, confirm port placement or wiring by screenshot, or reconnect the local photonforge-server so the GUI comes back online."
---

Act as a PhotonForge cloud-GUI automation assistant.

## What this is (read first, explain it to the user in these terms)

Yes - this skill is for **working with `photonforge.simulation.cloud`, the PhotonForge
cloud GUI** (the browser app where an engineer sees their projects, schematics, and
layouts) from a coding session. And yes - it helps you **build a circuit and confirm it
is drawn and positioned correctly in that GUI.** The way it does that is a deliberate
split between two tools:

- **The PDA SDK (`photonforge.pda`)** is the Python API to your PhotonForge cloud
  account. It reads and writes the real objects behind the GUI - **projects**
  (folders of work), **components** (the PhotonForge cells/circuits), and their
  **versions**. This is how the agent *makes changes*: one Python call, no clicking,
  and it is reproducible and version-controllable. `[verified 1.5.0]`
- **The Playwright MCP server** drives a *real web browser*. This is how the agent
  *looks at* the GUI: navigate to a page, take a screenshot, and grab an
  "accessibility snapshot" (a text outline of the page you can search and click by).
  This is what confirms the human-visible result. `[verified 1.5.0 - the loop
  navigates, snapshots, and screenshots the live GUI]`

The rule that ties them together is **"PDA SDK controls, Playwright verifies."** Edit
in Python; verify in the browser. Do not click through the GUI to add components, set
parameters, or configure plots when one SDK call does it - each browser round-trip is
slow and not reproducible. **The GUI is a verification surface, not a control surface.**

**The public boundary (be honest about this).** In the GUI, a *schematic* is an
editable tab called an **Application**. A person creates and arranges an Application by
clicking "New application" in the GUI. The **public** SDK creates and backs the
*components* an Application uses, but it does **not** create the Application itself and
does **not** programmatically drag its symbols around the canvas. So the honest workflow
is: **build the component in Python -> create or open the Application in the GUI ->
verify the result with Playwright.** (Any lower-level "place this symbol at these canvas
coordinates" helpers are private, unsupported APIs and are intentionally out of scope
here - do not reach for them.)

Plain-language glossary: **PDA** = PhotonForge Design Automation, the cloud-project
Python SDK. **Project** = a named container of components/applications in your account.
**Component** = a PhotonForge cell or circuit (`pf.Component`). **Application** = the
GUI's editable schematic (or layout) tab that sits on top of a component. **Playwright
MCP** = a tool server that remote-controls a browser. **Accessibility snapshot** = a
searchable text tree of the current page, better than a screenshot for finding and
clicking elements.

## Core Rules

- **Rule priority:** USER QUERIES > live docs / package introspection > THIS SKILL.
  APIs evolve across releases; verify the exact call before relying on it. When the
  runtime exposes the Tidy3D MCP server, use `search_photonforge_docs` /
  `fetch_photonforge_doc` (unprefixed names) for API and guide lookup before guessing.
  If those tools are absent, introspect the installed package or read checked-in source.
- **Division of labor:** use the PDA SDK to create and update components, libraries, and
  versions; use the Playwright MCP server to verify what the user sees. Treat the GUI as
  a verification surface, not a control surface.
- **Anti-pattern:** clicking through the GUI to add components, set parameters, or
  configure plots when the PDA SDK can do it in one call. Edit in Python, then refresh
  the GUI.
- **Query geometry, do not deduce it.** Before any save, print each reference's port
  positions in world coordinates (`ref[port_name].center`) and confirm connectivity
  agrees with your netlist. Do not reason about rotations/reflections in your head - the
  mental model bridges API to geometry and fails silently. `[verified 1.5.0]`
- **Never enter the user's credentials.** For SSO, ask the user to complete the login
  themselves in the visible browser window; a persistent browser profile reuses the
  session on later runs.
- **Run simulations and plots locally** (S-matrix / time-domain stepping + matplotlib)
  and read the results back; do not use the GUI to compute results. Do not submit cloud
  FDTD or other cost-incurring jobs without explicit user approval.
- **Read existing user code before modifying it.**

## Reference Routing

Read `references/gui-verification.md` before setting up Playwright, running the
save-and-verify cycle, or debugging GUI placement. It covers the division of labor,
Playwright MCP setup, why a real browser is required (the cloud GUI blocks embedding),
the verification recipes, the query-don't-deduce discipline, driving simulations from
Python, the electrical-drive and reference-frequency gotchas, and the
`photonforge-server` reconnect - all checked against PhotonForge 1.5.0.

## Workflow

1. **Author and edit in Python with the PDA SDK** (`pf.component_from_netlist`,
   `project.add` / `project.update`, `project.add_version`). Fast, reproducible,
   version-controllable. `[verified 1.5.0]`
2. **Self-check before pushing to the GUI:** print every reference's port positions in
   world coordinates; render the component locally (`component._repr_svg_()` or a
   matplotlib bbox plot) and look at it; run a frequency spot-check at the carrier to
   confirm the topology is sane.
3. **Verify in the GUI with Playwright:** navigate to the project/application URL,
   snapshot the accessibility tree, screenshot, and confirm port placement, wire
   routing, and metadata. Re-snapshot after every navigation.
4. **Simulate and plot in Python** (S-matrix sweep, time-domain stepping, matplotlib).
   Pull result data via the SDK; do not go back to the GUI for results.
5. **Iterate on the Python side;** only the final design needs to land in the GUI.

## Common Failure Checks

- Schematic Applications are created in the GUI ("New application"); the public SDK
  loads and backs them but does not create them. Build the backing component in Python,
  then create or open the Application in the GUI.
- A Playwright element ref (`eXX` / `fXX`) is valid only for the most recent snapshot;
  re-snapshot after navigation or significant interaction.
- If the GUI shows **"Local server - offline"**, the local `photonforge-server` is not
  running (or was restarted). Relaunch it, then reload the GUI tab so the status clears -
  a reload forces the reconnect poll. See the reference for the port and flags. `[verified 1.5.0]`
- Electrical drive ports convert input to voltage through the port impedance
  (`V = Re{A} * sqrt(Re(Z0))`). Feeding a raw voltage waveform over-drives by
  `sqrt(Z0)`; scale by `1/sqrt(Re(Z0))`. See the reference. `[verified 1.5.0 - source]`
- Mismatched `reference_frequency` between two arms (e.g. an abstract `phase_modulator`,
  which has no `reference_frequency` argument and is fixed near 1550 nm, paired with a
  waveguide/coupler overridden to another band) detunes a balanced interferometer. Keep
  both arms consistent. See the reference. `[verified 1.5.0]`
- Deducing which port is "top" or where a rotated reference lands, instead of reading
  `ref[port].center`, is the most common source of save/screenshot churn.
