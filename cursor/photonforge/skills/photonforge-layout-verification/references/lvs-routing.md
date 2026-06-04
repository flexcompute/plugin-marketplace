# PhotonForge LVS, Routing, And Schematic-To-Layout Patterns

Use this reference when assembling, routing, or verifying PhotonForge layouts.

## Contents

- Connection vocabulary
- Declarative netlists
- Routing and terminal routes
- Virtual-to-physical routing workflow
- LVS-style verification
- Geometry intersection checks
- Circuit model and S-matrix guardrails

## Connection Vocabulary

PhotonForge layout verification centers on port connectivity.

- Physical connection: two positioned reference ports touch after placement or `Reference.connect`.
- Route: a physical waveguide component inserted between two ports, usually with `pf.parametric.route`.
- Virtual connection: an intent annotation between reference ports. It can participate in circuit modeling, but it does not draw geometry.
- Butt coupling: a physical port contact where profiles differ.
- External port: a child reference port exposed as a top-level component port.

Use virtual connections to capture schematic intent before routing, or to model a deliberate virtual circuit connection. Remove them when the user expects a fully routed physical layout.

## Declarative Netlists

`pf.component_from_netlist` is the most compact way to create a circuit from instances and connectivity.

```python
import photonforge as pf


netlist = {
    "name": "MZI",
    "instances": {
        "dc0": directional_coupler,
        "arm0": phase_shifter,
        "arm1": straight,
        "dc1": {"component": directional_coupler, "origin": (120, 0)},
    },
    "connections": [
        (("dc0", "P2"), ("arm0", "P0")),
        (("dc0", "P3"), ("arm1", "P0")),
    ],
    "routes": [
        (("arm0", "P1"), ("dc1", "P0"), pf.parametric.route, {"radius": 10}),
        (("arm1", "P1"), ("dc1", "P1")),
    ],
    "ports": [
        ("dc0", "P0", "In0"),
        ("dc0", "P1", "In1"),
        ("dc1", "P2", "Out0"),
        ("dc1", "P3", "Out1"),
    ],
    "models": [(pf.CircuitModel(), "Circuit")],
}

component = pf.component_from_netlist(netlist)
```

Netlist rules:

- `instances` can be a dictionary or list. Dictionary keys make errors easier to read.
- Instance values can be components, references, or reference-constructor dictionaries.
- `connections` transform references so ports physically snap together.
- `routes` insert route geometry. If no route function is provided, PhotonForge uses `pf.parametric.route`.
- `virtual connections` mark intent only.
- `ports` and `terminals` expose child interfaces at the top level.
- Optical route entries should pass an explicit bend radius. Check the relevant port spec's `default_radius` if the process defines one.

Before building, scan for repeated endpoint use. A duplicated endpoint such as using `dc1.P1` in two independent links is usually a topology bug.

## Routing And Terminal Routes

Use PhotonForge routing helpers for physical layout work. Do not drop to raw `gdstk` for ordinary waveguide, metal, or terminal routing unless the user explicitly needs low-level file conversion.

For optical waveguides, pass route parameters explicitly:

```python
route = pf.parametric.route(
    port1=left["P1"],
    port2=right["P0"],
    radius=10,
)
component.add(route)
```

When building from a netlist, keep route kwargs near the link they belong to:

```python
"routes": [
    (("splitter", "P1"), ("combiner", "P0"), pf.parametric.route, {"radius": 10}),
]
```

For electrical or terminal routing, use `pf.Terminal` and `pf.parametric.route_manhattan(...)`. A terminal is constructed from a routing layer and a PhotonForge structure:

```python
signal = pf.Terminal(
    "M2",
    pf.Rectangle(corner1=(0, -2), corner2=(20, 2)),
)

route = pf.parametric.route_manhattan(
    port1=signal,
    port2=bondpad_terminal,
    width=4,
    direction1=0,
    direction2=180,
    waypoints=[(40, 20), (80, 20)],
)
component.add("M2", route)
```

Use `waypoints` to route around obstacles such as ring electrodes, signal traces, or keep-out regions. After terminal routing, inspect layer-specific intersections; netlist extraction will not catch arbitrary metal crossings.

## Virtual-To-Physical Routing Workflow

For an LVS-aware flow:

1. Place instances.
2. Add virtual connections for schematic intent.
3. Expose intended external ports.
4. Replace each virtual connection with a physical route.
5. Remove the virtual connection that the route replaced.
6. Recompute the netlist and check the result.

```python
component = pf.Component("Main")
left = component.add_reference(block_a)
right = component.add_reference(block_b)
right.translate((100, 0))

component.add_virtual_connection(left, "P1", right, "P0")
component.add_port(left["P0"], port_name="Input")
component.add_port(right["P1"], port_name="Output")

route = pf.parametric.route(port1=left["P1"], port2=right["P0"], radius=10)
component.add(route)
component.remove_virtual_connection(left, "P1")

netlist = component.get_netlist()
assert len(netlist["virtual connections"]) == 0
```

`Reference.connect("P0", other_ref["P1"])` moves and rotates the reference. `Component.add_virtual_connection(...)` does not move anything.

Use `component.tree_view()` when instance ownership or hierarchy is unclear, and use `component.bounds()` for chip sizing, floorplan checks, and edge alignment. `bounds()` is a method and works on flat or hierarchical components.

## LVS-Style Verification

Use `Component.get_netlist()` to inspect extracted connectivity:

```python
net = component.get_netlist()
physical = net["connections"]
virtual = net["virtual connections"]
ports = net["ports"]
```

Use `component.get_netlist(include_virtual_connections=False)` when the question is "what is physically connected by layout only?"

For a fully routed layout, verify:

- no remaining virtual connections
- all intended top-level ports are present
- no unexpected dangling internal ports are reported by warnings or netlist inspection
- route components are present as references or geometry as expected
- port mode counts and names are compatible across connected ports
- terminal routes expose the expected top-level terminals when electrical access matters

For a schematic or circuit-model-only layout, virtual connections may be acceptable. Say that explicitly so the user knows the layout is not physically routed.

## Geometry Intersection Checks

Netlist extraction checks port connectivity. It does not prove that unrelated waveguide structures do not overlap or run too close. Use boolean intersection checks after placement or routing changes.

```python
def assert_no_reference_intersections(component: pf.Component, layer: str | tuple[int, int]) -> None:
    main_structures = component.get_structures(layer, depth=0)
    references = list(component.references)

    for i, first in enumerate(references):
        first_structures = first.get_structures(layer)
        if main_structures and pf.boolean(main_structures, first_structures, "*"):
            raise RuntimeError(f"Main geometry intersects {first}")

        for second in references[i + 1:]:
            second_structures = second.get_structures(layer)
            if pf.boolean(first_structures, second_structures, "*"):
                raise RuntimeError(f"{first} intersects {second}")
```

Treat this as a sanity check, not a full DRC or parasitic/crosstalk analysis.

## Circuit Model And S-Matrix Guardrails

When layout verification flows into circuit modeling:

- `pf.CircuitModel` uses the component netlist and referenced component models.
- Virtual connections behave like connections for circuit modeling, even though they are not routed geometry.
- `component.s_matrix(...)` returns a PhotonForge `SMatrix`, not a plain dense NumPy array.
- Use `s_matrix.elements` or indexed element access for S-parameter data.
- Element keys use input then output port-mode names, such as `("P0@0", "P1@0")`.
- To reuse existing S-parameter data, look for `pf.DataModel` or the live documented data-model path rather than rerunning an EM model by default.
- A `Tidy3DModel` active model is FDTD-based. Do not claim PhotonForge automatically switches it to EME; use a separate EME model or the live documented EME path when needed.
