# Quarto Report Protocol

Use this protocol when the user requests a durable simulation report or when a report materially helps communicate completed analysis. Routine plots do not need a report. Use the sibling `flexagent` skill for the simulation and analysis content and for every cloud safeguard.

## Source of Truth

The saved workspace `.qmd` file is the editable report source. Read it before editing and apply the smallest relevant change. Keep simulation inputs, analysis code, and provenance in the report or link them explicitly; do not replace the source with hand-written HTML or a temporary web server.

A useful report normally contains:

1. purpose and simulation configuration;
2. geometry or setup figure;
3. solver settings and cost / run provenance;
4. result plots and quantitative metrics;
5. limitations and the next decision.

Use Python cells for reproducible analysis. Prefer exact saved Tidy3D results and local calculations over code that repeats cloud work.

## Editor Report Tools

Use only report tools advertised in the current session. Each is an independent capability.

- `render_report(path, open_after_render=...)` renders a saved workspace `.qmd`, preserves bounded command / working-directory / environment / output diagnostics, and can open or reload the rendered output.
- `open_report(path)` opens or focuses the rendered output for a saved `.qmd`; arbitrary HTML is unsupported.
- `get_report(path)` reads whether the report is open and returns its current timeline steps and selection.
- `set_report_step(path, step)` selects an actual step value in an open report, not a row index.

For timeline navigation, call `get_report` before `set_report_step` and choose only a value in the returned `steps`. A growing live report can expose a different list on each read.

## Safe Rendering

Rendering executes the report's code cells. Inspect every executable cell before rendering. If a cell can start cloud compute, return to the sibling FlexAgent cloud workflow for its estimate and explicit consent; otherwise freeze or remove that cell so the report renders from saved results.

When `render_report` is advertised:

1. save the `.qmd`;
2. read and inspect every changed executable cell;
3. render the exact saved source;
4. inspect the returned output path and bounded diagnostics;
5. fix a reported failing cell in the `.qmd` and rerender rather than bypassing the source.

If a listed report tool fails, diagnose it. Do not silently substitute another route and claim the editor action succeeded.

## Local Fallback

When editor report tools are absent and Quarto is already installed, render locally:

```bash
quarto render report.qmd --to html -M embed-resources:true
```

If Quarto is unavailable, leave a complete `.qmd` plus the render command. Do not install a new reporting stack or construct HTML to imitate the editor report surface unless the user asks.

## Figures and Data

- Use tables for small scalar summaries.
- Use matplotlib for plots and label axes with units.
- Use Tidy3D plotting helpers when they match the result type.
- Save figures beside the report or embed them through Quarto according to the requested artifact layout.
- Do not claim a theme, stylesheet, or theme opt-out unless the active renderer exposes it.

## Completion

Report the `.qmd` source path, rendered artifact path when available, whether all cells executed successfully, and the selected timeline step when navigation was requested. If rendering was skipped or failed, state the blocker and leave the source usable.
