# Verified gdstk Code Patterns

These patterns are validated for use with Tidy3D. Use `gdstk.RobustPath` as the preferred approach
for all curved or tapered waveguide geometry.

## Taper (width transition)

```python
import gdstk
import tidy3d as td

cell = gdstk.Cell("taper")
path = gdstk.RobustPath((0, 0), wg_width_in, layer=1)
path.segment((taper_length, 0), width=wg_width_out)
cell.add(path)
polys = cell.get_polygons()
taper = td.Structure(
    geometry=td.PolySlab(vertices=polys[0], axis=2, slab_bounds=(0, height)),
    medium=si,
)
```

## S-bend (lateral offset with sine profile)

```python
import numpy as np

cell = gdstk.Cell("sbend")
path = gdstk.RobustPath((0, 0), wg_width, layer=1)
path.segment(
    (bend_length, bend_offset),
    offset=lambda u: bend_offset * (u - np.sin(2 * np.pi * u) / (2 * np.pi)),
)
cell.add(path)
polys = cell.get_polygons()
```

## Circular arc bend (90°)

```python
cell = gdstk.Cell("bend")
path = gdstk.RobustPath((0, 0), wg_width, layer=1)
path.arc(bend_radius, 0, np.pi / 2)  # 90-degree bend
cell.add(path)
polys = cell.get_polygons()
```

## Boolean L-shape (using ClipOperation)

```python
arm_h = td.Box.from_bounds(rmin=(0, 0, 0), rmax=(3, 0.5, 0.22))
arm_v = td.Box.from_bounds(rmin=(0, 0, 0), rmax=(0.5, 2, 0.22))
l_shape_geo = td.ClipOperation(operation="union", geometry_a=arm_h, geometry_b=arm_v)
l_shape = td.Structure(geometry=l_shape_geo, medium=si)
```

## Polygon quality check

After calling `cell.get_polygons()`, always verify:

```python
polys = cell.get_polygons()
assert len(polys) > 0, "No polygons returned — check path definition"
if len(polys[0]) < 20:
    # Curve has too few vertices — reduce tolerance in RobustPath
    path = gdstk.RobustPath(..., tolerance=1e-4)  # smaller = more vertices
```

Target: ≥ 50 vertices per curved segment for smooth geometry.
