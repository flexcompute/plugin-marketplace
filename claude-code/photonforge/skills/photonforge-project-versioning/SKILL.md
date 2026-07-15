---
name: photonforge-project-versioning
description: "Version-control PhotonForge projects and use the API that creates and edits projects you can open, edit, and simulate in the browser GUI. Set up photonforge-server so the cloud GUI runs the user's own Python locally (recomputing their parametric components at new parameters and submitting their simulations); create and load projects, snapshot immutable versions and named tags, import PDK libraries, share with a team, and back a GUI schematic with a custom component so a teammate can open a link and click Run. This is the PhotonForge project and collaboration layer, also called PDA (Photonic Design Automation), used through `photonforge.pda` and the `photonforge-server` command. Use when the user runs photonforge-server, connects the cloud GUI to local Python, calls photonforge.pda, versions/tags/shares a project, seeds a PDK library, or hits a GUI recompute error such as 'No module named' or 'has no active model'."
---

Act as a PhotonForge project-versioning and cloud-GUI assistant. This is the
layer that stores PhotonForge designs as version-controlled, shareable cloud
projects and lets the browser GUI drive code running in the user's own Python
environment. Its value is traceability and collaboration: months after tapeout
you can still recover exactly which component, at which parameters, against which
PDK version was fabricated, and a teammate can open a project link and run it.

## Rule Priority

USER QUERIES > live docs / package introspection > THIS SKILL > training data.

This layer is simplified often across releases. If the live PhotonForge docs or
installed-package introspection disagree with this skill, trust them and verify
against the installed `photonforge` version.

## Core Rules

- **Plain language.** Say "your cloud project", "version control", "the browser
  GUI" — not "PDA SDK", "repository", or "CRDT". The user wants to version their
  work and drive the GUI, not learn tool internals.
- **Production by default.** Once the user's API key is configured (PhotonForge
  Getting Started), everything talks to production automatically. Do NOT lead
  with profile or endpoint switching — a normal user never changes it. It only
  matters for someone juggling multiple accounts; keep it out of the way.
- **Connecting is automatic.** The first `photonforge.pda` call connects to the
  server on its own. Just call `pda.stop()` when a script finishes (in a
  `finally`). `pda.init()` still exists and is idempotent (re-calling closes the
  prior connection first) — use it only to connect eagerly or force a reconnect.
- **Tools.** When the runtime exposes the Tidy3D MCP server, use
  `search_photonforge_docs` / `fetch_photonforge_doc` for API and guide lookup
  before guessing; verify APIs against the installed version.
- Do not run cloud simulations or other cost-incurring work without explicit user
  approval. Read existing user code before modifying it.

## Setting up photonforge-server (the important part)

`photonforge-server` is a small local process that lets the **browser GUI run
the user's own Python** — recomputing their parametric components at new
parameters and submitting their simulations. Without it the GUI can only show
stored geometry; with it, "open a project link and click Run" works.

1. **Same environment.** Launch it from the same Python environment and API key
   as the user's design code, so it imports the same packages and hits the same
   account.
2. **Launch it** (uses the active credentials, so it lands on production):
   ```bash
   photonforge-server --log-level INFO
   ```
3. **Open the GUI** at `https://photonforge.simulation.cloud/projects`. It
   auto-discovers the local server and shows "Connected to local server".
4. **Make the user's component code importable**, or GUI recompute fails with
   `No module named ...`. Either point the server at the source
   (`PYTHONPATH=/path/to/code photonforge-server`; verify first with
   `PYTHONPATH=/path/to/code python -c "import <yourmodule>"`), or ship the code
   in the project's own managed module (`project.import_module(globals())` +
   `project.save_module()`) so it travels with the project (reference).
5. **Sanity-check the whole loop** with the built-in example, which creates an
   "Example" project (an MZI) and exits, then open and Run it in the GUI:
   ```bash
   photonforge-server --example
   ```
   If this fails with `Library 'Abstract Components' version <x> not found`, that
   matching library isn't published in your environment - skip `--example` and
   seed a small project via the SDK instead (see reference).

Full server, managed-module, and GUI-schematic-backing detail is in the
reference.

## Reference Routing

Read `references/projects-and-server.md` before configuring `photonforge-server`
for the GUI, making a parametric module importable, backing a GUI schematic with
a component, seeding a PDK library, or debugging a GUI recompute error. It
carries the connection, project-lifecycle, server, module-import, GUI-backing,
and PDK-seeding patterns in full.

## Workflow

1. **Connect.** Just start calling `photonforge.pda` (it connects
   automatically); wrap script work in `try` / `finally` with `pda.stop()`.
   Confirm identity with `pda.user_info()`.
2. **Browse.** `pda.list_projects(...)` (filter by name / visibility / role) and
   `pda.list_libraries(...)`.
3. **Create or load.** `pda.create_project(name, description=...)`, or
   `pda.load_project(name=... | project_id=...)`; load an immutable snapshot with
   `version=...` (or a named `tag=...`).
4. **Work in the project.** Import a PDK with `project.add_library(name,
   version=version)` (`version` is keyword-only; a positional second arg raises
   `TypeError`) and set `pf.config.default_technology`; save a component with
   `project.add(comp, tag="draft")`; revise with `project.update(comp)` (matched
   by component NAME — keep the name stable); snapshot immutably with
   `project.add_version("1.0.0", target=comp.name)` (or whole-project
   `project.add_version("1.0.0")`); reload with `project.load(name,
   version=...)`; return a snapshot to editable head with `load_latest()`.
5. **Set up the GUI** for parametric recompute / simulation: run
   `photonforge-server` with the code importable (above + reference).
6. **Back a GUI schematic** so a teammate opens a link and runs it: wrap the
   component as a `@pf.parametric_component` with promoted reference ports and an
   activated model, make it importable, and `save_module()`. Five conditions must
   hold — see the reference.
7. **Share / clean up.** Publish as a library for others to import; inspect with
   `project.list_permissions()`; `project.retire([...])` /
   `pda.retire_project(project_id=...)` (versioned projects retire cleanly in
   1.5.0; a 409 means the target is protected another way, e.g. published as a
   shared library).

## Common Failure Checks

- GUI `No module named '<module>'` on recompute → the server can't import the
  user's code. Set `PYTHONPATH` or use the managed module + `save_module()`, and
  verify the import at the CLI in the server's environment.
- GUI `Component '<x>' has no active model` → an augmented component (copy +
  attached model) still points at the base layout; set
  `parametric_function = None` before `project.add(...)`.
- GUI `only reference ports can be added` / `has no ports` → the schematic is
  backed by a component whose ports were added directly; wrap it so every port
  and terminal is a promoted reference port.
- GUI `'NoneType' object has no attribute 'items'` in model handling → a model
  was added but not activated; `pf.CircuitModel()` auto-activates, others need
  `activate_model(...)`.
- `project.update(...)` changed the wrong thing → PDA matches by NAME; rebuild or
  edit with the same component name.
- Auth failure or nothing visible → the API key is not configured (run
  PhotonForge Getting Started). Only for a multi-account user is it a profile
  mismatch.
- `add_library(name=...)` errors "N projects matching" → duplicate library names
  in the account; pass `library_id=` from `list_libraries()` instead.
- `pda.retire_project(...)` returns 409 → the target is protected (e.g. published
  as a shared library); `add_version` alone no longer blocks retire in 1.5.0.
