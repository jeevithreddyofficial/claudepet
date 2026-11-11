"""Shared paths, config and per-session state storage (stdlib only)."""
import json
import os
import time
from pathlib import Path

HOME = Path(os.environ.get("CLAUDEPET_HOME", Path.home() / ".claudepet"))
SESSIONS = HOME / "sessions"
CONFIG = HOME / "config.json"
PIDFILE = HOME / "pet.pid"
LOGFILE = HOME / "pet.log"
MAC_BIN = HOME / "ClaudePetMac"   # the floating status pill, built by `claudepet start`

STATES = ("idle", "thinking", "working", "permission", "done")
RANK = {s: i for i, s in enumerate(("idle", "done", "thinking", "working", "permission"))}
STALE = {"thinking": 300, "working": 900, "permission": 1800}

DEFAULTS = {
    "x": None,           # saved drag position (top-left, screen points)
    "y": None,
    "autostart": False,  # hook launches the pill on SessionStart if it isn't running
    "done_secs": 6,      # how long "Done" shows before returning to "Idle"
}


def _atomic_write(path, data):
    SESSIONS.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(".%s.%d.tmp" % (path.name, os.getpid()))
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(str(tmp), str(path))


def load_config():
    cfg = dict(DEFAULTS)
    try:
        cfg.update(json.loads(CONFIG.read_text()))
    except (OSError, ValueError):
        pass
    return cfg


def save_config(cfg):
    _atomic_write(CONFIG, {k: cfg.get(k, v) for k, v in DEFAULTS.items()})


def _session_file(sid):
    safe = "".join(c for c in str(sid) if c.isalnum() or c in "-_")[:80] or "default"
    return SESSIONS / (safe + ".json")


def write_session(sid, state, detail="", cwd="", event=""):
    _atomic_write(_session_file(sid), {
        "session": sid, "state": state, "detail": detail,
        "cwd": cwd, "event": event, "ts": time.time(),
    })


def session_exists(sid):
    return _session_file(sid).exists()


def remove_session(sid):
    try:
        _session_file(sid).unlink()
    except OSError:
        pass


def read_sessions():
    out = []
    if SESSIONS.is_dir():
        for f in SESSIONS.glob("*.json"):
            try:
                out.append(json.loads(f.read_text()))
            except (OSError, ValueError):
                pass
    return out


def current_state(sessions, cfg, now=None):
    """Most urgent state across sessions (same rules as the pill)."""
    now = now or time.time()
    best = "idle"
    for s in sessions:
        st, age = s.get("state", "idle"), now - s.get("ts", 0)
        if (st == "done" and age > cfg["done_secs"]) or age > STALE.get(st, 1e12):
            st = "idle"
        if RANK.get(st, 0) > RANK[best]:
            best = st
    return best


def pet_pid():
    """PID of the running pill, or None."""
    try:
        pid = int(PIDFILE.read_text().strip())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None
