# Editor Integration Protocol

Use this protocol only for editor capabilities visible in the current tool list. The sibling `flexagent` skill remains responsible for simulation physics, API correctness, local plotting, result interpretation, and cloud execution safeguards.

## Capability Discovery

Treat every advertised tool as a separate capability. Never infer a complete editor installation from one tool.

- Environment and source: `detect_python`, `list_simulations`, `validate_simulation`
- Setup open and capture: `open_simulation`, `rotate_viewer`, `capture_viewer`, `viewer_annotation`, `set_structure_visibility`
- Generic setup controls: `viewer_cross_section`, `viewer_set_view`, `viewer_zoom`, `viewer_pan`, `viewer_visibility`, `viewer_layer`, `viewer_display`, `viewer_measure`
- Results: `viewer_results_open`, `viewer_results_list`, `viewer_results_select`, `viewer_results_view`, `viewer_results_coordinate`
- Provider-dependent results: `viewer_results_colormap`, `viewer_results_animate`
- Reports: `render_report`, `open_report`, `get_report`, `set_report_step`

Do not search for, install, launch, authenticate, bootstrap, or reconfigure an editor extension merely to discover capabilities. Unsupported protocols, malformed registrations, failed authentication, and unavailable bridges intentionally expose no editor tools.

## Saved Source and Validation

Editor source operations accept saved local `.py` or `.ipynb` paths, not inline or base64 source.

1. Save the simulation in the user's chosen file.
2. For local command execution, follow the canonical saved-source interpreter rule in the sibling `flexagent` skill: when `detect_python` is advertised, call it with the saved source as `resource` and use its exact `pythonExec`. Viewer-only actions do not require detection, and `validate_simulation` already uses the selected editor environment.
3. Use `list_simulations` when the file can contain multiple simulations. Each entry's `variable_name` and zero-based `index` identify a simulation; the response-level `source_revision` identifies the saved source. Pass `variable_name` as the `symbol` argument, or pair an `index` with the response's `source_revision`.
4. Run `validate_simulation`. Omit `symbol` and `index` to validate every simulation unless the user deliberately scoped the task to one. When selecting by `index`, pass the response-level `source_revision`. Relist after the source changes or when a revision is rejected.
5. Inspect every warning and error under FlexAgent's warning-classification rule. Errors and explicit tool refusals block. An aggregate `ok=false` may include warnings, so do not call the simulation clean without classifying them, and do not bypass an explicit refusal.
6. Validation opens no viewer. Preserve the per-simulation `artifact_id` and `output_file_uri` returned for the current task, then use the exact receipt for the simulation the user intends. Do not manufacture, shorten, or reuse receipts from another task.

If validation is absent, return to FlexAgent's narrow local construction and validation path. Do not execute an entire script when it could start cloud work, overwrite files, or cause unrelated side effects.

## Setup Viewer

`open_simulation` is for simulation setup, never completed result data.

1. Pass exactly one source or setup artifact route:
   - a saved `.py` / `.ipynb`, with `symbol` from `variable_name` or `index` from `list_simulations` when selecting one simulation; index addressing also requires the matching `source_revision`;
   - `open_all=True` when the user wants the editor-owned picker to choose and open one simulation; or
   - the exact setup `artifact_id` or HDF5 artifact path returned by validation.
2. Record the returned setup `viewer_id`. The user owns the `open_all=True` picker; do not choose or claim completion before the tool returns the selected simulation.
3. Pass the exact setup viewer ID to later controls whenever it is known or ambiguity is possible. With no ID, the bridge may use an applicable setup viewer remembered for the session or discover a single setup viewer opened by the user. If several setup viewers are available, supply an explicit ID instead of guessing. This implicit route never targets a results viewer.

When `open_simulation` is absent, use FlexAgent's Tidy3D / matplotlib cross-section inspection. State that an interactive editor setup view is unavailable only if that changes the requested outcome.

## Setup Controls and Visual Verification

Use only advertised controls and their documented inputs:

- `rotate_viewer`: align the camera to a named direction.
- `capture_viewer`: return the current setup frame as an image.
- `set_structure_visibility`: pass one boolean per structure in viewer order.
- `viewer_cross_section`: open, move, configure, or close an axis-aligned cut; pass either an absolute position in micrometers or a 0–1 fraction, never both.
- `viewer_set_view`: use a supported named camera preset.
- `viewer_zoom`: zoom in, out, or fit; a factor applies only to in or out.
- `viewer_pan`: pass either a direction or a three-coordinate `[x, y, z]` target in micrometers.
- `viewer_visibility`: show or hide structures, sources, or monitors by supported group and optional item.
- `viewer_layer`: toggle the supported boundary, source, or monitor scene layer.
- `viewer_display`: toggle a supported ruler, beyond-domain, or domain-edge option.
- `viewer_measure`: pass two finite three-coordinate points on the open cut plane, or clear existing measurements.

Generic setup controls confirm best-effort delivery through the bridge; they do not prove that the viewer applied the operation. Call `capture_viewer` afterward whenever visual application matters, then inspect the returned image. A capture failure is evidence to diagnose, not permission to guess the visible state.

## Annotation

`viewer_annotation` opens a frozen-frame editor and waits for the user to save or cancel.

- The user owns drawing and the **Save and copy** action.
- A completed operation returns a session artifact receipt and bounded metadata, never raw image bytes or a data URL.
- A cancelled operation creates no artifact. Do not claim, reconstruct, or reuse one.
- If clipboard access is unavailable, report the returned saved-artifact fallback instead of claiming the image was copied.

## Results Viewer

Results have their own identity and tools. Never send result data to `open_simulation`, use a setup viewer ID for a results operation, or guess among multiple result files.

1. Identify one specific, contained `.hdf5` / `.h5` `SimulationData` path or exact result artifact receipt.
2. Call `viewer_results_open` with exactly one of `path` or `artifact_id` and record its distinct results `viewer_id`.
3. Call `viewer_results_list` before navigating. It is the authority for monitor names, dataset keys, value operations, coordinates, supported views, and current selection.
4. Use only reported values:
   - `viewer_results_select` chooses a reported monitor and dataset, plus a supported complex-value operation when needed;
   - `viewer_results_coordinate` fixes a reported dimension to a reported non-negative index;
   - `viewer_results_view` selects a supported plot mode or line-plot axis.
5. Call `viewer_results_list` again when confirmation of the updated state matters.

`viewer_results_colormap` and `viewer_results_animate` are provider-dependent. Use either only when the tool itself is advertised for the active results viewer. Each operation must read back the requested state; failure is not a successful best-effort request.

If the results viewer is absent, return to FlexAgent's exact saved-result analysis and Tidy3D / matplotlib plot. This fallback is not an interactive editor results view.

## Receipts and Identity

- Setup artifact receipts open only setup artifacts; result receipts open only results.
- Viewer IDs belong to either the setup or results surface that returned them.
- Receipts and implicit current-viewer identities are session-scoped. Do not persist them in reusable code or documentation.
- When identity is ambiguous, reopen the exact saved source or artifact instead of guessing.

## Failure and Ownership

- **Capability absent:** use the documented local FlexAgent path when it meets the outcome; otherwise report the unavailable editor-only action.
- **Capability present but errors:** preserve the failure details, diagnose the contract or source issue, and retry only after addressing it. Do not silently downgrade.
- **User-owned picker or dialog:** wait for the user's choice or the tool's completed / cancelled response.
- **Cloud or destructive effect:** return to FlexAgent's applicable estimate, consent, or overwrite gate before continuing.
