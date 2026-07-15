# PhotonForge Project Versioning + Cloud GUI

Use this when writing code that versions PhotonForge projects, shares them, or
connects the browser GUI to the user's own Python via `photonforge-server`.
Verify uncertain APIs against the installed `photonforge` version — this layer is
simplified often across releases.

## Contents

- What this layer is
- Connecting (it is automatic)
- Environment: production by default
- `photonforge-server`: the local backend (the important part)
- Making the user's component code importable
- Browsing, loading, and creating projects
- Working with a loaded project (add / update / version / tag)
- Naming components for the GUI library
- Backing a GUI schematic with a component
- Seeding PDK libraries
- Common pitfalls
- Quick checklist

## What This Layer Is

The project layer (internally `photonforge.pda`, "Photonic Design Automation")
sits on top of the regular `photonforge` API and adds a version-controlled,
team-shareable cloud workspace. It lets the user:

- organize designs into named **projects**,
- import **PDK libraries** by name + version,
- **snapshot** immutable versions and move named **tags**,
- **share** with teammates (private / organization / public), and
- open and edit projects in the **browser GUI**, optionally running the user's
  own Python behind it.

The payoff is traceability and collaboration: long after tapeout you can recover
exactly which component, at which parameters, against which PDK version, was
fabricated, because the server stored it.

## Connecting (It Is Automatic)

```python
import photonforge.pda as pda

# The first PDA call connects automatically. Just disconnect when done:
uid, org = pda.user_info()
# ... work ...
pda.stop()
```

For scripts, disconnect in a `finally`:

```python
import photonforge.pda as pda
try:
    projects = pda.list_projects()
    ...
finally:
    pda.stop()
```

`pda.init()` still exists and is idempotent (re-calling it closes the prior
connection first). You rarely need it — reach for it only to connect eagerly or
to force a fresh reconnect. [verified on 1.5.0: `user_info()` auto-connects with
no `init()`; a second `init()` cleanly replaces the first.]

## Environment: Production By Default

Once the user's API key is set up (PhotonForge Getting Started), every PDA call
and `photonforge-server` launch talks to **production** automatically. A normal
user never changes this.

Only if someone manages **multiple accounts** do profiles matter: PDA uses
Tidy3D's config manager, and the active profile carries the apikey. Switch with
`from tidy3d.config import get_manager; get_manager().switch_profile(<name>)`
in-process, or set `TIDY3D_PROFILE=<name>` for a separate process such as the
server. Do not surface this to a single-account user.

## photonforge-server: The Local Backend (The Important Part)

`photonforge-server` is a local process the browser GUI talks to so it can run
**the user's own Python** — recomputing their parametric components at new
parameters and submitting their simulations. Pure scripting (create/version/
share from Python) does not need it; "open the project in the GUI and Run it"
does.

```
photonforge-server [--host HOST] [--port PORT]
                   [--log-level DEBUG|INFO|WARNING|ERROR|CRITICAL]
                   [--example | --no-example]
```

There is no `--profile` flag; the server uses the active credentials (production
by default). Multi-account users select a profile with `TIDY3D_PROFILE`.

**Standard setup:**

```bash
# 1) launch from the same env / API key as your design code
photonforge-server --log-level INFO
```

Then open `https://photonforge.simulation.cloud/projects`; the GUI discovers the
local server and shows "Connected to local server".

**Confirm the whole loop** with the built-in example (creates an "Example"
project with an MZI, then exits), then open and Run it in the GUI:

```bash
photonforge-server --example
```

GOTCHA (verified 1.5.0): `--example` needs the "Abstract Components" library
version that matches your PhotonForge release, published in your environment. If
it is not there you get `Library 'Abstract Components' version X.Y.Z not found`.
In that case skip `--example` and seed a project via the SDK instead (or ask an
admin to publish the matching library).

## Making The User's Component Code Importable

**Plain language: what this is and why it matters.** A saved component stores its
geometry, but NOT the Python code that generated it. The managed module is how
you save your `components.py` (the factory code) *inside the project* too, so
anyone who opens it later — you in six months, a teammate, or the browser GUI's
Run button — can re-run your factory at new parameters instead of being stuck
with a frozen snapshot. `save_module()` uploads that code to the project;
`import_module()` loads it back. Skip it and the geometry survives but the
"recipe" is lost: no parameter changes, no GUI recompute.

Mechanically: components saved with `@pf.parametric_component` remember the
Python function that built them (e.g. `<module>.components.vwg`). On GUI recompute
the server does `import <module>`; if it is not importable you get
`No module named '<module>'`.

**The project's own managed module (recommended, portable).** Each project owns a
Python module whose name is FIXED and derived from the project name (lowercased,
spaces become underscores, other punctuation is stripped), so **read it from
`project.module_name`** rather than predicting it - e.g. `"My Demo"` becomes
`my_demo`. It lives at `project.module_path / project.module_name`.
`create_project(..., create_template=True)` (the default) scaffolds it with an
`__init__.py`, a `component.py` template, and a README. Put your PCell code THERE,
load it with `import_module`, then build from it so the parametric function
registers under the project module and is backend-importable: [verified on 1.5.0]

```python
import importlib
project = pda.create_project(name="My Demo", description="...",
                             module_path="/path/to/workdir")   # create_template=True by default
mod = project.module_name                       # the REAL name (e.g. "my_demo"); never hardcode it
# -> scaffolds  {project.module_path}/{mod}/  with __init__.py + component.py

# write your PCell into that dir, e.g.  {project.module_path}/{mod}/components.py
#   with  @pf.parametric_component def vwg(...)

project.import_module(globals())                # imports the project module (+ attached libraries)
components = importlib.import_module(f"{mod}.components")
comp = components.vwg()
print(comp.parametric_function)                 # "<mod>.components.vwg"  <- backend-importable
project.add(comp, tag="draft")
project.save_module()                           # packs module_path/module_name to the cloud
```

TRAP (verified 1.5.0): if the parametric function comes from some OTHER package
instead of the project's own module, `add()` warns *"the parametric function ...
does not come from a library within this project. Updating ... will not be
possible without the original source"*. The project no longer carries the source,
so anyone who loads it later (or a server that does not have that package on its
`sys.path`) cannot recompute or update the cell. You can still make recompute work
on YOUR server by putting the package on `sys.path` (the PYTHONPATH alternative
below), but the project itself is no longer self-contained. Build from the
project's own module (above) when the project should be portable.

Verify persistence after `save_module()` with a functional check (no private attrs):

```python
project.save_module()
pda.stop(); pda.init()                          # force a fresh reload
p2 = pda.load_project(name=project.name, module_path="/path/to/workdir")  # module_path defaults
p2.import_module(globals())                      # to ./pflibs; pass your dir to avoid scattering copies
assert importlib.import_module(f"{p2.module_name}.components")   # importable -> module persisted
assert p2.load("vwg_component_name", tag="draft") is not None
```

**Alternative — `PYTHONPATH` for an external package.** The server can also import
a package you keep outside the project by putting it on `sys.path`:

```bash
PYTHONPATH=/path/to/your/code photonforge-server --log-level INFO
# verify in the SAME env/sys.path as the server:
PYTHONPATH=/path/to/your/code python -c "import mypkg; print(mypkg.__file__)"
```

This lets the server recompute at runtime, but the project does not carry the
source (not portable, and you get the "not from a library" warning). Prefer the
managed module when the project should be self-contained and shareable.
`module_path` passed to `create_project(...)` is only where modules are unpacked;
`module_name` is fixed by the project name.

## Browsing, Loading, And Creating Projects

```python
pda.list_libraries()                       # libraries you can access
pda.list_libraries('SiEPIC EBeam')         # by name
pda.list_projects()                        # your projects + ones shared with you
pda.list_projects(visibility='private', role='owner')
```

Load an existing project (latest editable head, or an immutable snapshot):

```python
project = pda.load_project(name='Example')
project = pda.load_project(project_id='<id>')
project = pda.load_project(name='Example', version='1.0.0')   # immutable
project = pda.load_project(name='Example', tag='balanced')
print(project.name, project.id)
print([lib['name'] for lib in project.get_library_info()])
print(list(project.components(origin='self')))
```

Create a new project:

```python
project = pda.create_project(
    name='tutorial-mzi',
    description='MZI demo',
    module_path='/path/to/code',           # where the parametric source lives
    visibility='private',                  # private | organization | public
)
```

## Working With A Loaded Project

```python
import photonforge as pf

# import a published PDK library and activate its technology.
# GOTCHA (verified 1.5.0): add_library(name=...) raises "N projects matching" if
# your account has duplicate library names (e.g. two 'SiEPIC EBeam' lineages).
# Disambiguate by looking the library up and passing its id:
# list_libraries defaults to latest=True; pass latest=False to see older versions too
hits = [l for l in pda.list_libraries('SiEPIC EBeam', latest=False) if l.get('version') == '1.2.1']
if len(hits) != 1:                                      # never silently take hits[0]
    raise RuntimeError(
        f"expected exactly one 'SiEPIC EBeam' 1.2.1, found {len(hits)}: "
        f"{[h['id'] for h in hits]}"                    # inspect + pick the intended id
    )
project.add_library(library_id=hits[0]['id'])          # unambiguous
# (when the name is unique in your account, add_library(name='SiEPIC EBeam') is fine)
tech = project.technologies(name='SiEPIC EBeam Si', origin='SiEPIC EBeam')
pf.config.default_technology = tech

# save your own component, then snapshot an immutable version
project.add(my_component, tag='draft')
project.add_version('1.0.0', target=my_component.name)     # one component
loaded = project.load(my_component.name, version='1.0.0')

# revise: PDA matches by NAME, so rebuild/edit with the SAME name, then update
updated = my_factory(arm_length=50)                        # same component name
project.update(updated, tag='unbalanced')
project.add_version('2.0.0', target=updated.name)

# a whole-project snapshot
project.add_version('1.0.0')
# return an immutable snapshot to the editable head
project.load_latest()
```

Do not set private attributes to force identity; rely on the name match.
Inspectors: `project.get_info()`, `project.get_library_info()`,
`project.list_permissions()`, `project.check_access()`. Cleanup:
`project.retire(['ComponentName'])`, `pda.retire_project(project_id=project.id)`
(verified 1.5.0: `add_version` does NOT block this — a versioned project retires
cleanly; a project *published as a shared library* for others may still be
protected).

## Naming Components For The GUI Library

By default `@pf.parametric_component` appends an argument-hash suffix to the name,
which is unreadable in the GUI browser. Set a non-empty name inside the function
to skip the hash:

```python
@pf.parametric_component(name_prefix="MRM")
def micro_ring_modulator(*, radius=12, ...):
    c = pf.Component("micro_ring_modulator")   # explicit name -> no hash suffix
    ...
    return c
```

The decorator caches by argument values and returns the cached object only while
unmodified. To rename or attach a model without surprising other call sites that
share the cache, work on a copy:

```python
comp = micro_ring_modulator().copy()
comp.name = "micro_ring_modulator_with_model"
comp.add_model(ring_model, "circuit")
```

## Backing A GUI Schematic With A Component

To let a teammate open a project link and click Run on a schematic, five things
must hold:

1. The component's parametric function is importable on `photonforge-server`
   under the same qualified name it was registered with (`PYTHONPATH` or the
   managed module above).
2. The top-level component has **reference ports** (promoted from a
   sub-`Reference`), not ports added directly to itself.
3. The wrapper is itself a `@pf.parametric_component` (hand-built
   `pf.Component(...)` parents lose their attached model on round-trip).
4. The wrapper has an **activated** model. `pf.CircuitModel()` auto-activates on
   `add_model(...)`; other models need `activate_model(...)`.
5. A recent enough PhotonForge for `save_module()` to persist the module.

An augmented component (copy + attach model + add a drive port) must detach the
inherited parametric function, or the server re-evaluates the base layout and
loses the model:

```python
def build_mrm_with_model():
    comp = micro_ring_modulator().copy()
    comp.name = "micro_ring_modulator_with_model"
    comp.parametric_function = None        # freeze the augmented data
    comp.add_model(ring_model, "circuit")
    comp.activate_model("circuit", "optical")
    return comp
```

Wrap a component that adds its own ports so every port/terminal becomes a
reference port:

```python
import photonforge as pf
from .models import build_mrm_with_model

@pf.parametric_component(name_prefix="WRAP")
def my_app_canvas() -> pf.Component:
    inner = build_mrm_with_model()
    c = pf.Component()
    ref = pf.Reference(inner)
    c.add(ref)
    for pname in list(inner.ports):
        c.add_port(ref[pname], pname)
    for tname in list(inner.terminals):
        c.add_terminal(ref[tname], tname)
    c.add_model(pf.CircuitModel())         # auto-activates; composes inner models
    return c
```

Stage the wrapper alongside the inner component, `save_module()`, and back the
Application with the wrapper. If a model is added but not activated, the worker
crashes with `AttributeError: 'NoneType' object has no attribute 'items'` —
activate explicitly for models that do not auto-activate:

```python
c.add_model(my_model, "circuit")
c.activate_model("circuit", "optical")
c.activate_model("circuit", "electrical")  # required for time-domain
```

Verify after upload:

```python
mrm = project.load("micro_ring_modulator_with_model", tag="draft")
assert mrm.active_model is not None
assert mrm.parametric_function is None
```

If you change which component backs an existing Application, the idempotent
create flow does not repoint it; recreate or repoint it from the GUI.

## Seeding PDK Libraries

PDK packages publish to PyPI and differ in API shape:

| Package | Library name | Tech factory | Component access |
|---|---|---|---|
| `siepic-forge` | SiEPIC EBeam | `technology.ebeam()` | dispatcher: `pkg.component(name, technology=...)` |
| `siepic-sin-forge` | SiEPIC EBeam SiN | `technology.ebeam()` | dispatcher |
| `luxtelligence-lnoi400-forge` | Luxtelligence LNOI400 | `technology.lnoi400()` | per-cell: `pkg.component.<name>(technology=...)` |
| `luxtelligence-ltoi300-forge` | Luxtelligence LTOI300 | `technology.ltoi300()` | per-cell |

Branch on `callable(pkg.component)`:

```python
import photonforge as pf
import photonforge.pda as pda

try:
    tech = pkg.technology.<factory_name>()
    pf.config.default_technology = tech
    project = pda.create_project(name=LIBRARY_NAME, description=DESCRIPTION,
                                 visibility='organization')
    for cell_name in sorted(pkg.component_names):
        if callable(pkg.component):
            comp = pkg.component(cell_name, technology=tech)
        else:
            comp = getattr(pkg.component, cell_name)(technology=tech)
        project.add(comp, update_existing_dependencies=False, update_config=False)
    project.add_version(pkg.__version__)
finally:
    pda.stop()
```

## Common Pitfalls

- GUI `No module named '<module>'` on recompute: the server lacks the source on
  `sys.path`. Set `PYTHONPATH` or use the managed module + `save_module()`, and
  verify the import at the CLI in the server's environment.
- GUI `Component '<x>' has no active model`: an augmented component still carries
  `parametric_function` pointing at the base layout. Set it to `None` before
  `project.add(...)`.
- GUI `only reference ports can be added` then `has no ports`: the schematic is
  backed by a component whose ports were added directly. Wrap it so every port
  and terminal is a promoted reference port.
- GUI `AttributeError: 'NoneType' object has no attribute 'items'`: a model was
  added but not activated. `pf.CircuitModel()` auto-activates; otherwise call
  `activate_model(...)`.
- `project.update(...)` hit the wrong component: PDA matches by NAME; keep the
  name stable.
- `Document not found in repository after N.Ns`: a find-timeout on a cold
  connection. Fix connectivity and retry `pda.init()` / the load; a transient
  cold-start usually clears on a second attempt.
- `add_library(name=...)` raises `N projects matching search parameters found`:
  your account has more than one library with that name. Pass `library_id=` (from
  `list_libraries()`, each entry's `id`) instead. [verified 1.5.0]
- Retire: `add_version` does NOT block `retire_project` in 1.5.0 (verified — a
  versioned project retires cleanly). A `409` still means the target is protected
  another way (e.g. published as a shared library); remove that or use admin
  tooling.
- Auth failure / nothing visible: the API key is not configured (Getting
  Started). Only for multi-account users is it a profile/apikey mismatch.
- `TypeError: 'module' object is not callable` iterating a PDK: you assumed the
  dispatcher shape on a per-cell PDK. Branch on `callable(pkg.component)`.

## Quick Checklist Before Running

1. API key configured (production by default; a profile only matters for
   multiple accounts).
2. For the GUI + local-Python workflow: `photonforge-server` running in the same
   environment, and the user's module importable (verify at the CLI).
3. For pure scripting (create / version / share): the server is not required.
4. Disconnect scripts cleanly with `pda.stop()` in a `finally`.
