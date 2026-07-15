# PhotonForge LiveViewer

Use this reference when rendering PhotonForge components/circuits in a browser
during interactive layout work, or when driving/inspecting the viewer
programmatically (tests, headless capture, AI agents). The LiveViewer runs a
small local web server: it serves an interactive 2D layout page and streams the
SVG of whatever you push to it. Verify exact names/signatures against the
installed `photonforge` before relying on them; everything below was checked
against PF 1.5.0.

## Contents

- Lifecycle
- Port hygiene
- Displaying and updating
- Showcase: several components at once
- Fit-to-view for large devices
- Driving and inspecting the viewer as an agent (`window.lvApi`)
- Server inspection endpoints (SVG, layer stack, cross-section)
- Gotchas

## Lifecycle

```python
import photonforge as pf           # LiveViewer is reachable as pf.live_viewer.LiveViewer
                                    # (no separate import needed; the explicit
                                    #  `from photonforge.live_viewer import LiveViewer` also works)

viewer = pf.live_viewer.LiveViewer(port=8765)  # starts automatically; open http://localhost:8765
viewer(component)                   # render an item (anything with _repr_svg_)
...                                 # edit the design
viewer(component)                   # push an update to the same tab
viewer.stop()                       # release the port when finished
```

- `LiveViewer(port=0, start=True)`: `port=0` (the default) lets the OS assign a
  free port (read it back from `viewer.port`); `start=True` (default) starts the
  server on construction. On start it prints
  `LiveViewer started at http://localhost:<port>`. [verified 1.5.0]
- `viewer(item)` and `viewer.display(item)` are equivalent; both render the item
  and return it, so you can wrap an expression: `comp = viewer(build_component())`.
  Each call re-points the viewer at the new item and the browser redraws.
  [verified 1.5.0]
- `viewer.start()` (re)starts the server and returns the viewer; `viewer.stop()`
  stops it and prints `LiveViewer stopped.` (and frees the port). [verified 1.5.0]

Pin a fixed port for a session so the user opens one URL once and just refreshes
it across updates.

## Port Hygiene

The most common failure is relaunching a viewer script while a previous server
still holds the port. Release it cleanly in-process:

```python
viewer.stop()                       # frees the port from the current process
```

For a standalone script that may have left a server from a prior run, prefer
calling `viewer.stop()` in that process. If a stale server still holds the port,
inspect what owns it and only kill a process you recognize as your own leftover
viewer - do not blindly SIGKILL whatever holds the port (it may be an unrelated
user process):

```bash
lsof -i:8765            # inspect ownership FIRST (macOS/Linux); Windows: netstat -ano | findstr :8765
# then, only if it is your own stale viewer:  kill <pid>   (Windows: taskkill /PID <pid> /F)
```

Prefer a single fixed port per session so there is exactly one server and one
browser tab to manage. The server thread is non-daemon, so it can outlive a
crashed main script and keep holding the port - another reason to `stop()` it
explicitly before relaunching.

## Displaying And Updating

Each `viewer(item)` call pushes the item's current SVG to the browser, which
redraws live. Make visual feedback part of the loop: after each meaningful
geometry change, push again rather than rebuilding the viewer. The server thread
is non-daemon, so a standalone script stays alive on its own after the last push;
the loop below just blocks until Ctrl-C so you can `stop()` cleanly (omitting
`stop()` can otherwise leave the process hanging at exit):

```python
import time
from photonforge.live_viewer import LiveViewer

def show(component, port=8765):
    viewer = LiveViewer(port=port)
    viewer(component)
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        viewer.stop()
```

In a notebook the viewer thread persists with the kernel, so no sleep loop is
needed.

## Showcase: Several Components At Once

To view several components together, arrange them with the built-in layout
helpers `pf.grid_layout` or `pf.pack_layout` instead of shifting references by
hand. Both accept Components, References, or 2D structures. `include_ports=True`
only means each item's ports count toward its bounds (so edge port-stubs are not
clipped) - the assembled board does NOT re-expose child ports as its own, so
child port labels are not shown on the board. To keep a child's port labels in a
showcase, re-expose them on the parent (`board.add_port(ref[name], name)`).
[verified 1.5.0]

```python
import photonforge as pf

# Regular grid (returns a single Component). gap and shape are optional.
board = pf.grid_layout([bend_comp, mzi_comp, ring_comp], gap=50)
viewer(board)

# Bin-packing when sizes vary widely (returns a LIST of Components, one per bin).
packed = pf.pack_layout([c1, c2, c3, c4], gap=20)
viewer(packed[0])
```

`grid_layout(objects, gap=0, shape=None, align_x='center', align_y='center',
direction='lr-bt', include_ports=True, ...)` lays items out in a grid;
`pack_layout(objects, gap=0, max_size=(0, 0), ...)` packs them and returns one
result Component per bin. Prefer leaving `max_size` at its default (unbounded):
capping it can force the result into more than one bin, and a component larger
than `max_size` will not fit at all.

## Fit-to-view For Large Devices

The default view is tight; for millimeter-scale devices the initial render or the
reset-view control lands far too zoomed in. After the first render, frame the
whole device: a person scrolls/wheels out on the canvas or clicks the viewer's
reset-view control; an agent calls `window.lvApi.fit()` (see below). Check
`component.bounds()` to know the device extent you are trying to frame.

## Driving And Inspecting The Viewer As An Agent (`window.lvApi`)

The page exposes a small, stable JavaScript object, **`window.lvApi`**, for
driving and inspecting the viewer WITHOUT a mouse - automated tests, headless
screenshot capture, and AI agents. It is part of the shipped viewer bundle
(present in the production build). Every mutator renders **synchronously**, so
the change is on the canvas the instant the call returns (it works even when the
tab is backgrounded and `requestAnimationFrame` is paused). [verified 1.5.0]

**How an agent invokes it.** Run JavaScript on the viewer page with whatever
browser-eval capability is available: the browser devtools console, a headless
browser's `page.evaluate(...)` (Playwright / Puppeteer), or an IDE's
browser-preview eval tool. For example, `page.evaluate("window.lvApi.fit()")`.
Wait until `window.lvApi.getState().ready === true` (a layout has been pushed and
parsed) before driving it.

**Coordinate convention.** All coordinates are layout/world micrometres unless a
method says "screen" (CSS px from the canvas top-left). Zoom is expressed as the
readout does: a ratio of fit (`1.0` = fit-to-view) or `zoomPct` (`100` = fit).
Important: the viewer works in SVG screen space, so world **X matches the layout
but world Y is NEGATED** relative to PhotonForge layout Y (verified: a component
whose Python `bounds()` gives `y:[-13, 39.25]` reports `bounds.minY/maxY =
-39.25 / 13` in `lvApi`). Prefer the `aabb`/`bounds` values `lvApi` reports (they
are internally consistent); negate Y if you translate from `component.bounds()`.

### Read / inspect (no mutation)

- **`lvApi.getState()`** - the one call to reach for. Returns
  `{ready, zoom, zoomPct, center:{x,y}, bounds:{minX,minY,maxX,maxY},
  viewport:{w,h}, entityCount, lodDepth, layerCount,
  layers:[...], hiddenLayers:[key,...], selection, measurements:[...]}`.
  [verified 1.5.0]
- **`lvApi.layers()`** - the layer list:
  `[{key:"layer_2_0", name:"WG_CORE", gds:[2,0], color:"#6db5dd", used:true,
  visible:true}, ...]` (`gds` is `null` for unlabeled geometry). [verified 1.5.0]
- **`lvApi.texts()`** - label / port-name entities:
  `[{text:"in_P0", x, y, fontSize}, ...]`. [verified 1.5.0]
- **`lvApi.componentTree(maxDepth=4)`** - the cell hierarchy from the reference
  graph: `{id, name, instances, children:[...]}`, with identical child cells
  deduped per parent and their instance counts summed. [verified 1.5.0]

The `lvApi` surface varies across releases (a source build can carry methods a
published wheel does not), so an agent should confirm a method with
`Object.keys(window.lvApi)` before relying on it. You can also read the hierarchy
from Python without the viewer: `component.tree_view()` /
`component.get_netlist()`.

### Camera: zoom, pan, fit

- **`lvApi.fit()`** - fit the whole layout to the viewport (synchronous; keeps
  any measurements). Returns the new `getState()`. [verified 1.5.0]
- **`lvApi.setCamera(opts)`** - set zoom and/or recenter; omitted fields are left
  unchanged; returns the new `getState()`. Accepts `{zoomPct: 200}` OR
  `{zoom: 0.5}` (ratio of fit, `1.0` = fit) and `{center: {x, y}}` (world µm).
  [verified 1.5.0]

```js
lvApi.setCamera({ zoomPct: 200, center: { x: 10, y: -10 } });  // zoom in + recenter
lvApi.setCamera({ zoom: 0.5 });                                 // half of fit zoom
lvApi.fit();                                                    // frame everything
```

### Layers: show / hide

- **`lvApi.setLayerVisible(ref, visible=true)`** - toggle one layer (keeps the
  panel checkbox in sync). `ref` resolves flexibly: human name (`"WG_CORE"`),
  labelled `"Name (n,d)"`, `"n,d"`, `"n/d"` (e.g. `"5/0"`), or the raw key
  (`"layer_2_0"`). Returns `{matched:true, layer:{...}}`, or `{matched:false,
  ref}` when nothing matches (no throw). Hidden layers show up in
  `getState().hiddenLayers`. [verified 1.5.0]

```js
lvApi.setLayerVisible("WG_CORE", false);   // hide by name
lvApi.setLayerVisible("5/0", false);       // hide METAL by n/d
lvApi.setLayerVisible("WG_CORE", true);    // show again
```

### Inspect a shape (selection)

- **`lvApi.selectWorld(wx, wy)`** - inspect the topmost shape at a WORLD point
  (µm). Returns `{label, aabb:[x0,y0,x1,y1], metrics:{area, verts}}` or `null`.
  `label` is `"<cell> · <layer> (n,d)"`, e.g. `"C1 · WG_CORE (2,0)"`. This is the
  agent-friendly entry point - no screen math needed. [verified 1.5.0]
- **`lvApi.select(sx, sy)`** - same, but at a SCREEN point (CSS px from the
  canvas top-left). [verified 1.5.0]
- **`lvApi.clearSelection()`** - clear the highlight; returns `true`.
  [verified 1.5.0]

```js
const hit = lvApi.selectWorld(10, 0);
// -> { label: "C1 · WG_CORE (2,0)", aabb: [0,-0.25,20,0.25], metrics: {area:10, verts:4} }
```

### Measure

- **`lvApi.measure(x1, y1, x2, y2)`** - add a measurement between two WORLD
  points and draw it; returns `{dx, dy, dist, angle}` (angle in degrees).
  [verified 1.5.0]
- **`lvApi.clearMeasurements()`** - remove all measurements; returns `true`.
  [verified 1.5.0]
- **`lvApi.renderNow()`** - force a synchronous render (mutators already render
  synchronously, so this is rarely needed). [verified 1.5.0]

## Server inspection endpoints (SVG, layer stack, cross-section)

The viewer server also exposes plain HTTP routes its own panels read from; an
agent can `GET` them directly (base `http://localhost:<port>`). [all returned 200
on the installed 1.5.0: `/layout.svg` image/svg+xml, `/api/stack` +
`/api/xsection` application/json, `/events` text/event-stream]

- **`GET /layout.svg`** - the raw SVG of the current item (the exact geometry the
  page renders), streamed in chunks.
- **`GET /events`** - a Server-Sent-Events stream of small JSON metadata pushed on
  each display: `{name, component_tree, layers, layer_stack, svg_version,
  svg_bytes}`. `component_tree` is the same hierarchy as
  `lvApi.componentTree()`; `layers` maps `layer_<n>_<d>` -> `{name, description}`.
- **`GET /api/stack`** - the technology's vertical extrusion stack, top-down:
  `[{z0, z1, material, color, sidewall, layers:[[n,d],...]}, ...]`.
- **`GET /api/xsection?ax=&ay=&bx=&by=`** - a process cross-section along the cut
  A -> B (layout µm): `{bands:[{poly, color, material, layers}], zmin, zmax, length}`.

These routes and `lvApi` are the supported surfaces; do not call the module's
underscore-prefixed Python helpers directly. For geometry/connectivity without the
viewer, the stable Python API also works (`component.get_structures(...)`,
`component.get_netlist()`, `component.bounds()`, `component.tree_view()`).

## Gotchas

- `component.bounds()` is a method; without parentheses you get the method
  object, not the extents.
- Run scripts with `python -u` so startup and update logs are not buffered away.
- A blank/stale tab usually means nothing was pushed yet, or the design changed
  without a follow-up `viewer(...)` call.
- `pf.Label(text, origin)` has no `layer` keyword; labels are layer-agnostic.
- Only items with an SVG representation (`_repr_svg_`) render; pushing something
  else is a no-op. A bare `pf.Terminal` cannot be added to a component via
  `Component.add()` - add its shape on a routing layer instead (e.g.
  `component.add("METAL", pf.Rectangle(...))`).
- `window.lvApi` world coordinates match the layout in X but NEGATE Y; use the
  `aabb`/`bounds` values `lvApi` reports, or negate Y from `component.bounds()`.
- `window.lvApi` exists only after the page has loaded and a layout has been
  parsed; gate agent driving on `lvApi.getState().ready === true`.
- The server thread is non-daemon and can survive a crashed script, so free the
  OS port before relaunching a standalone viewer.
