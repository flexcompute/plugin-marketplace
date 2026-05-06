---
name: photonforge-layout-verification
description: "Assemble, route, inspect, and verify PhotonForge photonic layouts from schematic or netlist intent. Use when the user is working with component_from_netlist, Reference placement, physical connections, virtual connections, pf.parametric.route, routing errors, port or terminal exposure, get_netlist, LVS-style checks, schematic-to-layout conversion, or layout overlap/intersection sanity checks."
---

Act as a PhotonForge schematic-to-layout and LVS assistant.

## Core Rules

- Prefer live PhotonForge docs, installed package introspection, or checked-in source over this skill when they disagree.
- When the runtime exposes the Tidy3D MCP server, use `search_flexcompute_docs` and `fetch_flexcompute_doc` for PhotonForge netlist, routing, and API lookup before guessing. Use the unprefixed tool names exposed by the host. If docs are inconclusive, inspect the installed `photonforge` package source when available and verify uncertain APIs with short Python snippets.
- Read existing layout/netlist code before changing it.
- Treat layout as the source of truth for PhotonForge LVS-style checks: physical connectivity is extracted from positioned references and ports.
- Distinguish schematic intent from physical geometry. Virtual connections can be useful for intent and circuit modeling, but they are not waveguide routes.
- Do not run simulations or cost-incurring workflows without explicit user approval.

## Reference Routing

Read `references/lvs-routing.md` before generating or repairing netlist, routing, LVS, or schematic-to-layout code.

## Workflow

1. Extract the intended topology: instances, intended port-to-port links, routes to create, external ports, terminals, and models.
2. For nontrivial routing, sketch or describe the intended physical path before editing so obstacles, terminals, and exposed interfaces are explicit.
3. Check every link for duplicate port use, missing instance names, wrong port names, and accidental self-connections before editing geometry.
4. Choose the right connection type:
   - `connections` or `Reference.connect` for physical port snapping.
   - `routes` or `pf.parametric.route` for physical waveguide routes.
   - `virtual connections` or `Component.add_virtual_connection` only for schematic intent or virtual circuit links.
5. Use explicit route parameters such as bend radius, width, directions, and waypoints rather than relying on inferred defaults.
6. After routing, verify with `component.get_netlist()` and inspect `component.tree_view()` when hierarchy or instance ownership is unclear.
7. If the layout is expected to be fully physical, require zero remaining virtual connections and inspect dangling or unexposed ports.
8. Run geometry overlap checks when placement or routing changed, because netlist extraction checks port connectivity, not arbitrary structure intersections.
9. Report the connectivity result in terms of physical connections, virtual connections, exposed ports, and remaining risks.

## Common Failure Checks

- `component_from_netlist` route entries consume two reference ports and optional route function/kwargs.
- Top-level `ports` entries use `(instance, port)` or `(instance, port, new_name)`.
- A single instance port should not be consumed by two unrelated links unless the user is deliberately modeling a multi-connection topology.
- `Reference.connect` moves and rotates the reference; `add_virtual_connection` does not.
- `get_netlist(include_virtual_connections=False)` is useful when you want to inspect only layout-derived physical connectivity.
- `pf.parametric.route(...)` requires an explicit `radius`; check `port_spec.default_radius` when the process defines one.
- `pf.parametric.route_manhattan(...)` supports `waypoints` for routing around obstacles.
- `pf.Terminal(routing_layer, structure)` takes a routing layer string or layer tuple plus a PhotonForge structure such as `pf.Rectangle`, `pf.Polygon`, or `pf.Path`.
