---
name: photonforge-live-viewer
description: "The PhotonForge LiveViewer is a local, interactive 2D layout viewer for pf.Component and circuits: `from photonforge.live_viewer import LiveViewer`, point it at a component, and it serves a browser view that redraws as you edit the design - the primary visual feedback loop while building layouts. Covers the Python lifecycle (open on a fixed port, push updates, show several components together, fit large devices, release the port) and the browser-side window.lvApi that lets an AI agent drive the viewer headlessly: zoom/pan/fit the camera, toggle layers, inspect the shape at a point, measure distances, and read the layer list, cell hierarchy, and camera state. Use when the user wants to see or iterate on a PhotonForge layout, run a viewer script, drive or inspect the viewer programmatically, or fix a stuck/port-in-use LiveViewer."
---

Act as a PhotonForge LiveViewer assistant.

## What this is (read first, explain it to the user in these terms)

The **LiveViewer** is a small, local, interactive **2D layout viewer** for
PhotonForge. You import it (`from photonforge.live_viewer import LiveViewer`),
point it at a `pf.Component` (a single device, a routed circuit, or a whole
chip), and it starts a tiny web server on your machine. You open ONE browser tab
(`http://localhost:<port>`) and see the layout drawn to scale. Each time you
change the design and push it again, that same tab redraws. Think of it as a
KLayout window that lives next to your Python script and auto-updates - it is the
main visual feedback loop while building a layout.

There are two ways to interact with it:

- **From Python** - open the viewer, push a component to display it, push again
  after each edit, and stop it when done. This is the everyday loop.
- **From the browser** - a person can pan, zoom, measure distances, toggle
  layers on and off, and click a shape to inspect it. An **AI agent** can do all
  of that programmatically through a small JavaScript API, `window.lvApi`,
  exposed on the page: fit/zoom/pan the camera, show/hide layers, inspect the
  shape at a point, add measurements, and read the layer list, the cell hierarchy
  (`lvApi.componentTree()`), and camera state - with no human at the mouse (all
  verified on 1.5.0; the cell hierarchy is also available from Python via
  `component.tree_view()`). This is how an agent "looks at" and drives the layout
  headlessly.

It is **visualization, not simulation**: displaying a layout runs no FDTD, no
mode solve, and costs nothing. Never launch a solver just to draw something.

## Core Rules

- **Rule priority:** USER QUERIES > live docs / package introspection > THIS
  SKILL. The API evolves across releases; verify against the installed
  `photonforge` before relying on a signature. When the runtime exposes the
  Tidy3D MCP server, use `search_photonforge_docs` / `fetch_photonforge_doc`
  (unprefixed names) before guessing.
- Open the viewer with `from photonforge.live_viewer import LiveViewer; viewer =
  LiveViewer(port=8765)`. It starts on construction and prints its URL. Display a
  component with `viewer(component)` (or the alias `viewer.display(component)`);
  calling again pushes an update to the same browser tab.
- Pin a fixed port for a session so the user opens one URL once and just
  refreshes it. `port=0` (the default) lets the OS pick a free port - read it
  back from `viewer.port`.
- Release the port cleanly with `viewer.stop()` when done. Before re-running a
  viewer script, free the port so the new run can bind it.
- To drive or inspect the viewer as an agent (zoom, pan, fit, toggle layers,
  inspect a shape, read layers / cell hierarchy / camera state), use the
  browser-side `window.lvApi` - see the reference. It needs any way to run
  JavaScript on the page (a browser console or a headless "evaluate" capability).
  The full surface is verified on 1.5.0; on older releases confirm a method with
  `Object.keys(window.lvApi)` first. The cell hierarchy is also available from
  Python (`component.tree_view()`) without the viewer.
- This is local visualization, not simulation. Do not run mode solvers,
  `s_matrix`, or other cost-incurring work just to display a layout.
- `component.bounds()` is a method call, not a property. Read existing user code
  before modifying it.

## Reference Routing

Read `references/live-viewer.md` before writing a viewer script, composing a
multi-component showcase, driving or inspecting the viewer with `window.lvApi`,
or debugging a stuck viewer. It covers the Python lifecycle, port hygiene, the
`grid_layout`/`pack_layout` showcase pattern, fit-to-view for large devices, the
verified `window.lvApi` agent surface (camera, layers, selection, cell
hierarchy, measurement, state), the server inspection endpoints (layer stack,
cross-section, raw SVG), reading geometry/hierarchy from Python, and the common
gotchas - all checked against PF 1.5.0.

## Workflow

1. Construct the viewer on a known port: `viewer = LiveViewer(port=8765)` (it
   starts automatically). Tell the user to open `http://localhost:8765`.
2. Display the current design: `viewer(component)`. After each meaningful layout
   change, call `viewer(component)` again to push the update.
3. To show several components at once, arrange them with `pf.grid_layout(...)` or
   `pf.pack_layout(...)` and push the result - do not shift references by hand.
4. For millimeter-scale devices, fit the view after the first render (the default
   zoom is far too tight for anything longer than a few hundred micrometers). A
   person scrolls to zoom out; an agent calls `window.lvApi.fit()`.
5. To inspect or drive the viewer headlessly, call `window.lvApi` methods on the
   page (`getState`, `fit`, `setCamera`, `setLayerVisible`, `selectWorld`,
   `layers`, `componentTree`, `measure`). Every mutator renders synchronously.
   The cell hierarchy is also available from Python (`component.tree_view()`).
6. When finished, `viewer.stop()` to release the port. If re-running a script,
   free the port first and let the new run rebind.

## Common Failure Checks

- Address-already-in-use on relaunch: a previous viewer still holds the port.
  Call `viewer.stop()` in the old process, or free the port at the OS level
  before restarting.
- `component.bounds()` is a method; calling it without parentheses returns the
  method object, not the extents.
- Run viewer scripts with unbuffered output (`python -u ...`) so "LiveViewer
  started" and update logs appear immediately.
- A blank or stale tab usually means nothing was pushed yet
  (`viewer(component)`), or the design changed without a follow-up `viewer(...)`
  call.
- `window.lvApi` coordinates match the layout in X but NEGATE Y (the viewer works
  in screen space, Y-down). Use the `aabb`/`bounds` values `lvApi` itself
  reports, or negate Y when passing coordinates from Python `component.bounds()`.
- `window.lvApi` is ready only after a layout has been pushed and parsed; check
  `lvApi.getState().ready === true` before driving it.
- Keeping a script alive (a sleep loop) is only needed for standalone scripts; in
  a notebook the viewer thread persists with the kernel.
- Only items with an SVG representation (`_repr_svg_`) render; pushing anything
  else is a no-op.
