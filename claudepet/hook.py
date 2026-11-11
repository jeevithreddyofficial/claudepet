#!/usr/bin/env python3
"""Claude Code hook entrypoint.

Claude Code pipes a JSON payload on stdin for every hook event. We map the event
to a pet state and write it to ~/.claudepet/sessions/<session_id>.json.
The pet window polls that directory. This script never prints and always exits 0,
so it can never block or alter Claude's behaviour.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from claudepet import paths  # noqa: E402

WORK_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "BashOutput",
              "KillShell", "KillBash"}
ASK_TOOLS = {"AskUserQuestion", "ExitPlanMode"}


def _short(tool, tool_input):
    tool_input = tool_input or {}
    target = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if target:
        return "%s %s" % (tool, os.path.basename(target))
    if tool == "Bash" and tool_input.get("command"):
        return "$ " + tool_input["command"].split()[0]
    return tool


def classify(event, data):
    """Return (state, detail), ("end", "") to drop the session, or None for no change."""
    tool = data.get("tool_name", "")
    if event == "SessionStart":
        return "idle", ""
    if event == "UserPromptSubmit":
        return "thinking", ""
    if event in ("PostToolUse", "PostToolUseFailure", "PreCompact"):
        return "thinking", ""   # only applied to sessions that already exist (see main)
    if event == "SubagentStop":
        return None             # background helpers fire this under phantom sessions; ignore
    if event == "PreToolUse":
        if tool in ASK_TOOLS:
            return "permission", "has a question"
        if tool in WORK_TOOLS or tool.startswith("mcp__"):
            return "working", _short(tool, data.get("tool_input"))
        return "thinking", tool
    if event == "PermissionRequest":
        return "permission", "approve " + tool if tool else "needs approval"
    if event == "Notification":
        ntype = data.get("notification_type", "")
        msg = (data.get("message") or "").lower()
        # The 60s "Claude is waiting for your input" nudge after a finished turn
        # shouldn't make the pet wave forever; ignore it.
        if ntype == "idle_prompt" or "waiting for your input" in msg:
            return None
        return "permission", "needs you"
    if event == "Stop":
        return "done", ""
    if event == "SessionEnd":
        return "end", ""
    return None


def _autostart():
    if paths.pet_pid() or not paths.MAC_BIN.exists():
        return
    with open(str(paths.LOGFILE), "a") as log:
        subprocess.Popen([str(paths.MAC_BIN)], stdin=subprocess.DEVNULL, stdout=log,
                         stderr=log, start_new_session=True)


def main():
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        data = {}
    event = data.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else "")
    sid = data.get("session_id") or "default"
    result = classify(event, data)
    if result is None:
        return
    state, detail = result
    if state == "end":
        paths.remove_session(sid)
        return
    # Only a real conversation (SessionStart / a prompt) may create a session entry;
    # follow-up events just update it. Stops phantom "Thinking" from background helpers.
    if event not in ("SessionStart", "UserPromptSubmit") and not paths.session_exists(sid):
        return
    paths.write_session(sid, state, detail, data.get("cwd", ""), event)
    if event in ("SessionStart", "UserPromptSubmit") and paths.load_config().get("autostart"):
        _autostart()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never break Claude Code
        try:
            with open(str(paths.LOGFILE), "a") as f:
                f.write("hook error: %r\n" % (exc,))
        except Exception:
            pass
    sys.exit(0)
