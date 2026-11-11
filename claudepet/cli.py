"""claudepet: a small floating status pill for Claude Code (macOS)."""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from claudepet import paths  # noqa: E402

PKG = Path(__file__).resolve().parent
HOOK = PKG / "hook.py"
MAC_SRC = PKG.parent / "mac" / "ClaudePetMac.swift"
DEFAULT_SETTINGS = Path.home() / ".claude" / "settings.json"
TEST_SID = "_claudepet_test"

# event -> matcher (None = event takes no matcher)
HOOK_EVENTS = {
    "SessionStart": None, "UserPromptSubmit": None, "PreToolUse": "*",
    "PostToolUse": "*", "PermissionRequest": "*", "Notification": None,
    "SubagentStop": None, "PreCompact": None, "Stop": None, "SessionEnd": None,
}


# ---------------------------------------------------------------- settings.json
def hook_command():
    # "|| true": if this folder is ever moved/deleted, python would exit 2, which
    # Claude Code treats as "block the tool". Swallow it so the pet can never block Claude.
    return '"%s" "%s" 2>/dev/null || true' % (sys.executable, HOOK)


def hooks_block():
    out = {}
    for event, matcher in HOOK_EVENTS.items():
        entry = {"hooks": [{"type": "command", "command": hook_command(), "timeout": 5}]}
        if matcher is not None:
            entry = dict(matcher=matcher, **entry)
        out[event] = [entry]
    return out


def _is_ours(entry):
    return any("claudepet" in h.get("command", "") and "hook.py" in h.get("command", "")
               for h in entry.get("hooks", []))


def _strip(settings):
    hooks = settings.get("hooks", {})
    for event in list(hooks):
        hooks[event] = [e for e in hooks[event] if not _is_ours(e)]
        if not hooks[event]:
            del hooks[event]
    if not hooks:
        settings.pop("hooks", None)
    return settings


def _load_settings(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}


def _save_settings(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = path.with_name(path.name + ".claudepet.bak")
    # Keep the very first backup (your pre-ClaudePet settings); never overwrite it.
    if path.exists() and not backup.exists():
        shutil.copy2(str(path), str(backup))
        print("backup: %s" % backup)
    path.write_text(json.dumps(data, indent=2) + "\n")


def _installed(path):
    hooks = _load_settings(path).get("hooks", {})
    return any(_is_ours(e) for entries in hooks.values() for e in entries)


# ---------------------------------------------------------------- the pill
def build():
    """Compile the pill if missing or out of date (uses swiftc from Xcode Command Line Tools)."""
    if paths.MAC_BIN.exists() and paths.MAC_BIN.stat().st_mtime >= MAC_SRC.stat().st_mtime:
        return
    if sys.platform != "darwin" or not shutil.which("swiftc"):
        sys.exit("ClaudePet needs macOS with Xcode Command Line Tools (xcode-select --install).")
    print("building ClaudePet (one-time, ~20s)…")
    paths.HOME.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["swiftc", "-O", str(MAC_SRC), "-o", str(paths.MAC_BIN)],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    if r.returncode != 0:
        sys.exit(r.stdout + "\nbuild failed")


def cmd_start(_a):
    pid = paths.pet_pid()
    if pid:
        print("ClaudePet already running (pid %d)" % pid)
        return
    build()
    with open(str(paths.LOGFILE), "a") as log:
        p = subprocess.Popen([str(paths.MAC_BIN)], stdin=subprocess.DEVNULL,
                             stdout=log, stderr=log, start_new_session=True)
    time.sleep(0.8)
    if p.poll() is not None:
        sys.exit("ClaudePet exited immediately - see %s" % paths.LOGFILE)
    print("ClaudePet started")


def cmd_stop(_a):
    pid = paths.pet_pid()
    if not pid:
        print("ClaudePet is not running")
        return
    os.kill(pid, signal.SIGTERM)
    for _ in range(20):
        time.sleep(0.1)
        if not paths.pet_pid():
            break
    else:
        os.kill(pid, signal.SIGKILL)
        paths.PIDFILE.unlink()
    print("ClaudePet stopped")


def cmd_restart(a):
    cmd_stop(a)
    cmd_start(a)


def cmd_status(_a):
    cfg = paths.load_config()
    pid = paths.pet_pid()
    sessions = paths.read_sessions()
    print("pill:     %s" % ("running (pid %d)" % pid if pid else "stopped"))
    print("state:    %s" % paths.current_state(sessions, cfg))
    print("sessions: %d" % len(sessions))
    for s in sessions:
        print("  - %-10s %4ds ago  %s" % (s.get("state"), time.time() - s.get("ts", 0), s.get("cwd", "")))
    print("hooks:    %s in %s" % ("installed" if _installed(DEFAULT_SETTINGS) else "not installed",
                                  DEFAULT_SETTINGS))


def cmd_test(a):
    if a.state == "clear":
        paths.remove_session(TEST_SID)
        return
    paths.write_session(TEST_SID, a.state, "", os.getcwd(), "test")
    print("showing %r (run `claudepet test clear` to reset)" % a.state)


def cmd_demo(_a):
    for st in ("idle", "thinking", "working", "permission", "thinking", "done"):
        print("-> %s" % st)
        paths.write_session(TEST_SID, st, "", os.getcwd(), "demo")
        time.sleep(3)
    paths.remove_session(TEST_SID)


def cmd_autostart(a):
    cfg = paths.load_config()
    cfg["autostart"] = a.value == "on"
    paths.save_config(cfg)
    print("autostart %s" % a.value)


def cmd_install(a):
    path = Path(a.settings).expanduser()
    settings = _strip(_load_settings(path))
    hooks = settings.setdefault("hooks", {})
    for event, entries in hooks_block().items():
        hooks.setdefault(event, []).extend(entries)
    _save_settings(path, settings)
    print("installed ClaudePet hooks into %s" % path)
    print("restart Claude Code so the new hooks are picked up.")


def cmd_uninstall(a):
    path = Path(a.settings).expanduser()
    if not path.exists():
        print("nothing to do")
        return
    _save_settings(path, _strip(_load_settings(path)))
    print("removed ClaudePet hooks from %s" % path)


def cmd_snippet(_a):
    print(json.dumps({"hooks": hooks_block()}, indent=2))


def main(argv=None):
    ap = argparse.ArgumentParser(prog="claudepet", description=__doc__)
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("start", help="show the status pill").set_defaults(fn=cmd_start)
    sub.add_parser("stop", help="hide the status pill").set_defaults(fn=cmd_stop)
    sub.add_parser("restart", help="stop then start").set_defaults(fn=cmd_restart)
    sub.add_parser("status", help="show pill, sessions and hook status").set_defaults(fn=cmd_status)

    p = sub.add_parser("test", help="force a state for testing")
    p.add_argument("state", choices=list(paths.STATES) + ["clear"])
    p.set_defaults(fn=cmd_test)
    sub.add_parser("demo", help="cycle through every state").set_defaults(fn=cmd_demo)
    p = sub.add_parser("autostart", help="launch the pill automatically when a session starts")
    p.add_argument("value", choices=["on", "off"])
    p.set_defaults(fn=cmd_autostart)

    for name, fn, hlp in (("install", cmd_install, "add hooks to Claude Code settings"),
                          ("uninstall", cmd_uninstall, "remove hooks from Claude Code settings")):
        p = sub.add_parser(name, help=hlp)
        p.add_argument("--settings", default=str(DEFAULT_SETTINGS),
                       help="settings file (default ~/.claude/settings.json)")
        p.set_defaults(fn=fn)
    sub.add_parser("snippet", help="print the hooks JSON to paste manually").set_defaults(fn=cmd_snippet)

    a = ap.parse_args(argv)
    if not getattr(a, "fn", None):
        ap.print_help()
        return
    a.fn(a)


if __name__ == "__main__":
    main()
