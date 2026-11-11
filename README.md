# 🐶 ClaudePet

**A tiny pixel pet for macOS that shows what Claude Code is doing.**

It floats on your screen (or sits in your menu bar) and reacts as Claude works. It naps when Claude is idle, types
when Claude is editing, and waves at you when Claude needs your OK.

> Unofficial fan project. Not affiliated with Anthropic.

---

## Quick start

Requires **macOS** with the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/jeevithreddyofficial/claudepet.git
cd claudepet
bin/claudepet install   # adds hooks to ~/.claude/settings.json (backs it up first)
bin/claudepet start     # shows the pet (first run builds it, ~20 s)
```

Then restart Claude Code. That's it.

---

## What the pet is telling you

| Status | Color | What the pet does | Meaning |
|---|---|---|---|
| **Idle** | ⚪ grey | breathes, blinks, falls asleep after 2 min | nothing running |
| **Thinking** | 🔵 blue | paces with a thought bubble | reading, searching, reasoning |
| **Working** | 🟠 orange | types on a laptop | editing files or running commands |
| **Needs you** | 🔴 red | waves with a `!` | waiting for your approval or an answer |
| **Done** | 🟢 green | jumps with sparkles | just finished |

If several Claude Code sessions are open, it shows the most urgent one.

---

## Controls

| Action | Result |
|---|---|
| **Click** | pet it (hearts, and it wakes up) |
| **Hover** | see exactly what Claude is doing |
| **Drag** | move it (it remembers the spot) |
| **Right-click** | open the menu below |

**Right-click menu:**

- **Dog / Cat**: pick your pet
- **Size**: Small, Medium or Big
- **Show as**:
  - **Pet**: the floating pet with a status label
  - **Pill**: just a compact floating status pill
  - **Menu bar**: the pet and its status live in your menu bar
- **Move to corner**
- **Quit**

Your choices are remembered. The pet stays above other windows (including full-screen apps), shows up on every
desktop, follows light and dark mode, and stays out of the Dock and Cmd-Tab.

---

## Commands

| Command | What it does |
|---|---|
| `bin/claudepet start` | show the pet |
| `bin/claudepet stop` | hide it |
| `bin/claudepet restart` | stop, then start |
| `bin/claudepet status` | what it's showing, and whether hooks are installed |
| `bin/claudepet demo` | cycle through every state |
| `bin/claudepet autostart on` | start the pet automatically with each Claude Code session (`off` to disable) |
| `bin/claudepet install` / `uninstall` | add or remove the Claude Code hooks |

---

## How it works

```
Claude Code ──hook event──▶ claudepet/hook.py ──writes──▶ ~/.claudepet/sessions/<session>.json
                                                                   │
                                mac/ClaudePetMac.swift ◀──reads────┘  (every 0.2 s)
```

Claude Code runs `hook.py` on events like *prompt sent*, *about to edit a file*, *needs permission* and *finished*.
The script writes one small state file per session in about 25 ms. It never prints anything and always exits
cleanly, so it can't get in Claude's way. The Mac app reads those files and animates the pet.

<details>
<summary>Project layout</summary>

```
bin/claudepet                 the command you run
claudepet/hook.py             called by Claude Code; turns events into states
claudepet/paths.py            state + config files
claudepet/cli.py              start / stop / status / install / uninstall …
mac/ClaudePetMac.swift        the pet itself (compiled on first start)
examples/settings.hooks.json  the hooks, if you'd rather add them by hand
```

</details>

---

## Uninstall

```sh
bin/claudepet stop && bin/claudepet uninstall && rm -rf ~/.claudepet
```

`uninstall` removes only ClaudePet's hooks and leaves your other settings alone. Restart Claude Code afterwards.
A backup of your original settings is kept at `~/.claude/settings.json.claudepet.bak`.

## License

See [LICENSE](LICENSE).
