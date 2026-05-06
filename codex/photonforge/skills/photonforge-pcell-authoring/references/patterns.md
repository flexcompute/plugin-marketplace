# PhotonForge PCell, Hierarchy, And Schema Patterns

Use this reference when authoring or repairing PhotonForge component code.

## Contents

- Component authoring checklist
- Technology and ports
- Parametric component pattern
- Geometry construction
- Hierarchy and references
- Interactive visualization
- Schema and GUI integration
- Validation checklist

## Component Authoring Checklist

Start from the contract, not from geometry:

- technology or PDK name
- layers or layer tuples to write
- optical and electrical ports to expose
- intended model, such as analytical, `pf.CircuitModel`, or `pf.Tidy3DModel`
- parameters that should appear in GUI/schema surfaces
- whether the component is a leaf PCell or a hierarchical circuit block

Prefer small, composable PCells. Keep a leaf component responsible for its own geometry and ports. Put placement, routing, and top-level port naming in a parent component.

## Technology And Ports

A PhotonForge `Technology` maps 2D layout layers to a 3D material stack and defines named port specifications. For a custom process, model these pieces explicitly:

- `pf.LayerSpec`: layer/datatype, human label, and 2D layout color/pattern.
- `pf.MaskSpec`: where an extrusion applies. An empty mask applies everywhere in that z range.
- `pf.ExtrusionSpec`: material and z limits for a mask.
- `pf.PortSpec`: width, out-of-plane limits, target mode information, and `path_profiles`.
- `pf.Technology`: the assembled layer stack, port specs, and background medium.

Important ordering rule: broad background or cladding extrusions should appear before patterned layers that override them. Do not represent an everywhere BOX or cladding layer as a huge drawn polygon unless that is explicitly part of the layout data contract.

Port limits should bracket the vertical mode region. A zero-height `PortSpec` limit, or limits that sit away from the waveguide core, can produce invalid mode-solver domains.

Minimal custom technology shape:

```python
import photonforge as pf
import tidy3d as td


@pf.parametric_technology
def demo_technology(*, thickness: float = 0.22) -> pf.Technology:
    layers = {
        "Si": pf.LayerSpec((1, 0), "Silicon", "#d2132e18", "//"),
    }
    si = td.Medium(permittivity=3.48**2)
    oxide = td.Medium(permittivity=1.44**2)
    extrusion_specs = [
        pf.ExtrusionSpec(pf.MaskSpec(), oxide, (-2.0, 2.0)),
        pf.ExtrusionSpec(pf.MaskSpec((1, 0)), si, (0.0, thickness)),
    ]
    ports = {
        "Strip": pf.PortSpec(
            "Single-mode strip",
            1.55,
            (-0.6, thickness + 0.6),
            target_neff=2.4,
            path_profiles=[(0.5, 0.0, (1, 0))],
        )
    }
    return pf.Technology(
        "Demo technology",
        "1.0",
        layers,
        extrusion_specs,
        ports,
        oxide,
    )
```

## Parametric Component Pattern

Use keyword-only arguments so PhotonForge can store and update parameter state clearly.

```python
import photonforge as pf
import photonforge.typing as pft


@pf.parametric_component
def straight_heater(
    *,
    length: pft.Dimension = 50.0,
    port_spec: pf.PortSpec | str = "Strip",
) -> pf.Component:
    length_f = float(length)
    tech = pf.config.default_technology
    spec = tech.ports[port_spec] if isinstance(port_spec, str) else port_spec
    width, offset = spec.path_profile_for("Si")

    component = pf.Component("Straight heater", technology=tech)
    path = pf.Path((0, 0), width=width)
    path.segment((length_f, 0))
    component.add("Si", path)
    component.add_port(pf.Port((0, offset), 0, spec), port_name="P0")
    component.add_port(pf.Port((length_f, offset), 180, spec), port_name="P1")
    return component
```

Use typed parameters for public parameters that should show up cleanly in schema or UI surfaces:

- `pft.Dimension` for lengths in micrometers.
- `pft.Angle` for degrees.
- `pft.PositiveInt` for counts.
- `pft.PositiveFloat` for positive scalar values.
- `pft.Fraction` for 0 to 1 values.
- `pft.Frequency` for frequencies.

Convert typed values before using them in `range`, NumPy array shapes, repeated reference counts, or low-level PhotonForge APIs.

## Geometry Construction

Use PhotonForge structures directly:

```python
component.add("Si", pf.Rectangle(corner1=(-1, -0.25), corner2=(1, 0.25)))

path = pf.Path((0, 0), width=0.5)
path.segment((10, 0))
path.arc(start_angle=0, end_angle=90, radius=5)
component.add("Si", path)

holes = pf.boolean([outer], [inner], "-")
component.add("Si", *holes)
```

Use layer names from the technology when possible. Use raw `(layer, datatype)` tuples only when the code is intentionally independent of a named technology layer.

`pf.Label(text, origin)` is layer-agnostic and does not accept a `layer` keyword. If the layout needs durable layer-marked text in exported mask data, verify the current PhotonForge text/annotation API in live docs instead of assuming labels behave like geometry.

PhotonForge components do not expose a `.plot()` method. In notebooks, components can render through their SVG representation. For layout reviews in scripts, prefer LiveViewer. Use `pf.tidy3d_plot(component, ...)` only when the user actually needs a Tidy3D cross-section or simulation-derived view; it can construct a Tidy3D simulation and can fail or become expensive for very large structure counts.

## Hierarchy And References

Build parent circuits by adding references to child components:

```python
parent = pf.Component("Parent")
left = parent.add_reference(straight_heater(length=20))
right = parent.add_reference(straight_heater(length=20))

right.connect("P0", left["P1"])
parent.add_port(left["P0"], port_name="Input")
parent.add_port(right["P1"], port_name="Output")
```

Rules that prevent common hierarchy bugs:

- Use `parent.add_reference(component)` when you need the returned `Reference`.
- Use `ref["P0"]` to get a transformed port from a reference.
- Avoid adding a parent back into its own dependency tree; PhotonForge rejects cycles.
- Put reusable geometry in child components and route or expose ports in the parent.
- For reference arrays, bracket access may return a list of transformed ports.

## Interactive Visualization

For nontrivial component authoring, make visual feedback part of the workflow:

1. Sketch the intended layout before coding when the design includes multiple ports, electrodes, or routes.
2. Build in small steps and render after meaningful changes.
3. Use the same viewer port during one session so the user can refresh one browser tab.
4. Check `component.bounds()` after changes before using bounds for placement, chip sizing, or edge-coupler alignment.

Minimal LiveViewer pattern:

```python
import time

import photonforge as pf
from photonforge.live_viewer import LiveViewer


def showcase_component(component: pf.Component) -> None:
    viewer = LiveViewer(port=8765)
    viewer(component)
    while True:
        time.sleep(60)
```

To show several components together, add each component as a `pf.Reference` to a parent showcase component, shift each reference by its `bounds()`, and expose reference ports on the showcase so port names remain visible in the viewer.

## Schema And GUI Integration

PhotonForge has more than one schema surface:

- Full export/import preserves PhotonForge objects and design state.
- Node schema is a lightweight UI representation of a component.
- Netlist schema represents instance connectivity for schematic views.
- Parameter schema comes from inspected function signatures and annotations.

When the user asks about frontend, GUI, serialization, or schema behavior, inspect the live code or docs for the current version. Internal helper modules such as `_backend.parametric_schema` and `_backend.netlist` are useful evidence, but public code should avoid depending on private helpers unless the task is explicitly inside the PhotonForge backend.

Good GUI-facing PCells have:

- stable function names
- clear docstrings
- keyword-only typed parameters
- native default values
- explicit component names
- deterministic top-level port names

## Validation Checklist

Before handing back PhotonForge component code:

- Instantiate the component with defaults.
- Check `component.bounds()` and `component.size()` for plausible geometry.
- Confirm expected ports exist and use the correct `PortSpec`.
- If ports are detected automatically, inspect the names and orientations.
- Render in LiveViewer or another local layout preview when available.
- If exporting GDS/OASIS, use PhotonForge layout export APIs and check layer mapping.
- Do not run FDTD or other remote-cost simulations unless the user approved it.
