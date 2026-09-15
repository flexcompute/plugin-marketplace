---
name: editor-integration
description: "Use for Tidy3D editor-integrated work when advertised tools can validate saved simulations, open or control setup and results viewers, capture or annotate views, use artifact receipts, or edit and render Quarto reports. Use alongside the sibling flexagent skill for simulation physics, code, local plots, result analysis, and every cloud action."
---

# Tidy3D Editor Integration

Use the editor capabilities that are actually advertised in the current session. This skill owns the editor boundary; it does not own simulation physics or cloud execution.

## Scope Boundary

- Use the sibling `flexagent` skill for Tidy3D API verification, simulation construction, physics validation, local geometry inspection, result analysis, and cloud estimate / consent / execution.
- Use this skill for saved-source validation, setup and results viewer identity, editor controls, captures, annotations, artifact receipts, and Quarto report editing or rendering.
- Editor validation and captures complement the FlexAgent workflow. They do not prove that a geometry or result is physically correct and do not replace FlexAgent's local plots and inspection.
- An editor capability never authorizes a cloud run, overwrite, or other risky action. Return to FlexAgent's applicable gate whenever the requested editor workflow could execute one.

## Standard Workflows

Use these handoffs only when this skill is invocable and the named capabilities are advertised.

| Situation | Editor handoff |
|---|---|
| Source was built or changed | After FlexAgent's local physics audit, validate the saved source and open the exact setup artifact receipt returned for the intended simulation. |
| A visible setup is being debugged | Capture the applicable setup viewer before diagnosis; use its explicit viewer ID when known. |
| A saved result is being inspected | Open the exact result, list its reported datasets, and select only the monitor and dataset relevant to the question. |
| A durable report is requested or materially useful | Edit the `.qmd`, render it, and open the rendered artifact by following the report protocol. Routine plots stay in FlexAgent. |

Setup and results viewers are separate surfaces with separate viewer IDs and tool families. Reports are changed by editing their `.qmd` source and rendering again: `render_report` executes cells and writes the output. `viewer_annotation` is a user-completed action on a frozen setup-viewer frame, not a report-editing operation.

## Required Protocol

Read `references/protocols/ide-integration.md` before any editor validation, viewer, capture, annotation, or receipt-backed action.

Also read `references/protocols/report.md` when the task creates, edits, opens, renders, or navigates a Quarto report.

## Advertised Capabilities

Treat every listed tool as an independent capability. Use only tools present in the current session; one tool never implies another.

| Area | Tools |
|---|---|
| Environment and source | `detect_python`, `list_simulations`, `validate_simulation` |
| Setup open and capture | `open_simulation`, `rotate_viewer`, `capture_viewer`, `viewer_annotation`, `set_structure_visibility` |
| Setup controls | `viewer_cross_section`, `viewer_set_view`, `viewer_zoom`, `viewer_pan`, `viewer_visibility`, `viewer_layer`, `viewer_display`, `viewer_measure` |
| Results | `viewer_results_open`, `viewer_results_list`, `viewer_results_select`, `viewer_results_view`, `viewer_results_coordinate` |
| Provider-dependent results | `viewer_results_colormap`, `viewer_results_animate` |
| Reports | `render_report`, `open_report`, `get_report`, `set_report_step` |

The tool list is authoritative even if another document describes a broader surface.

## Non-Negotiables

- Do not install, launch, authenticate, bootstrap, or reconfigure an editor or extension to make a missing tool appear.
- Keep setup viewers and results viewers separate. Carry the exact viewer ID returned by the matching open operation.
- Treat artifact IDs and artifact paths as session-scoped receipts. Use only an exact receipt returned for the current task and expected artifact kind.
- Leave editor-owned pickers, dropdowns, annotation dialogs, and confirmations to the user. Do not choose on their behalf or claim completion before the tool returns it.
- A successful generic setup control confirms best-effort delivery, not visual application. Capture afterward when the visible outcome matters.
- If a listed tool fails, preserve and diagnose that failure. Do not silently act as though the tool was absent.
- If a tool is absent, use the documented local fallback only when it satisfies the request. Otherwise state which editor-only outcome is unavailable.

## Completion

Report the exact saved source or artifact, the setup or results viewer ID when one was opened, and what was validated or visibly inspected. For reports, include the `.qmd` path, rendered output when available, and whether all executable cells completed.
