#!/usr/bin/env python3
"""PreToolUse guard: a Tidy3D MCP tool name typed into Bash is redirected to the real tool.

Smaller models occasionally read a deferred-tool lookup that returns no text as "the tool does not
exist", then run the tool name as a shell command or import a client module that was never shipped.
Exit code 2 blocks the command and hands the model the correction as tool feedback; anything else
passes through untouched.

Deliberately conservative about *where* it matches. Blocking a command the model was allowed to run
is worse than missing one it was not: a mention inside a comment, a grep pattern, an echoed string
or a heredoc body is discussion, not execution, so only an execution or import position counts.

Kept to syntax an old interpreter accepts. The installer guarantees `uv`, not a particular Python,
and a guard that fails to start silently removes the safeguard on every Bash call.
"""
import json
import re
import sys
from typing import Optional

# The tool name as the model would type it, keeping whichever server prefix it used: a
# marketplace-installed plugin exposes `mcp__plugin_tidy3d_tidy3d__*`, and correcting that to
# `mcp__tidy3d__*` would name a tool the session does not have.
QUALIFIED_TOOL = re.compile(r"mcp__(?:plugin_tidy3d_)?tidy3d__[a-z_]+")
# A command position: the start of a line, or straight after a shell separator.
COMMAND_POSITION = re.compile(r"(?:^|[;&|(`]|\$\()\s*(" + QUALIFIED_TOOL.pattern + r")\b")
FAKE_CLIENT_IMPORT = re.compile(
    r"(?:^|[;&|(`]|\$\(|\bimport\s+|\bfrom\s+)\s*tidy3d_mcp_client\b"
)
FAKE_HELPER_CALL = re.compile(r"(?:^|[;&|(`=]|\$\()\s*call_mcp_tool\s*\(")

HEREDOC_START = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
PYTHON_INLINE_CODE = re.compile(
    r"(?:^|[;&|]\s*)(?:python(?:3(?:\.\d+)?)?|py)\s+-c\s+(['\"])(.*?)\1"
)


def executable_text(command: str) -> str:
    """Drop the parts of a command that are quoted prose rather than something to run.

    Removes heredoc bodies, trailing comments, and quoted arguments such as grep patterns. Inline
    Python passed to `python -c` is retained because that quoted text is executed. This is not a
    shell parser -- it only has to stop the guard firing on text the model was reading or writing
    about rather than executing.
    """
    lines = []
    inline_python = []
    pending_terminator = None
    for raw_line in command.splitlines():
        if pending_terminator is not None:
            if raw_line.strip() == pending_terminator:
                pending_terminator = None
            continue
        heredoc = HEREDOC_START.search(raw_line)
        if heredoc:
            pending_terminator = heredoc.group(1)
        inline_python.extend(match.group(2) for match in PYTHON_INLINE_CODE.finditer(raw_line))
        characters = list(raw_line)
        quote = None
        for index, character in enumerate(raw_line):
            if quote:
                characters[index] = " "
                if character == quote:
                    quote = None
            elif character in "'\"":
                quote = character
                characters[index] = " "
            elif character == "#" and (index == 0 or raw_line[index - 1].isspace()):
                characters[index:] = " " * (len(characters) - index)
                break
        lines.append("".join(characters))
    return "\n".join([*lines, *inline_python])


def verdict(command: str) -> Optional[str]:
    """Return the correction for a command that misuses a Tidy3D tool, or None to allow it."""
    text = executable_text(command)
    named = COMMAND_POSITION.search(text)
    if named:
        qualified = named.group(1)
        name = qualified.rsplit("__", 1)[1]
        return (
            "Stop: `{0}` is not a shell command; it is one of your own tools. Call the tool named "
            "{0} directly, passing its arguments as the tool input. If it is not loaded yet, call "
            "ToolSearch with query `select:{0}`; a reply with no text means the tool is now "
            "loaded, so call it on your next step. (The tool is {1} on this install.)"
        ).format(qualified, name)
    if FAKE_CLIENT_IMPORT.search(text) or FAKE_HELPER_CALL.search(text):
        return (
            "Stop: there is no Tidy3D MCP client module or `call_mcp_tool` helper to import; the "
            "Tidy3D capabilities are your own tools. Call the tool directly, passing its arguments "
            "as the tool input. If none are loaded, call ToolSearch with query `tidy3d viewer` and "
            "use the fully qualified name it returns; a reply with no text means the tools are now "
            "loaded, so call one on your next step."
        )
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    command = (payload.get("tool_input") or {}).get("command", "")
    message = verdict(command if isinstance(command, str) else "")
    if message is None:
        return 0
    sys.stderr.write(message + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
