# ClaudePet

A small floating pill for macOS that shows what Claude Code is doing:

| Pill | Meaning |
|---|---|
| 🐶 **Idle** (grey) | nothing running |
| 🐶 **Thinking** (blue) | working out what to do: reading, searching, reasoning |
| 🐶 **Working** (orange) | editing files or running commands |
| 🐶 **Needs you** (red) | waiting for your approval or an answer |
| 🐶 **Done** (green) | just finished; goes back to Idle after a few seconds |

It floats above other windows, including full-screen apps, on every desktop. It follows light and dark mode
and doesn't appear in the Dock or Cmd-Tab. Drag it to move it (it remembers the spot). Right-click to switch between a dog and a cat, pick a size
(Small, Medium, Big), choose how it's shown (**Show as → Pet / Pill / Menu bar**), or quit; your choices are remembered.
**Pill** hides the animal and keeps just the status pill; **Menu bar** puts the animated pet and its status in the
macOS menu bar (click it for the same menu).
If several Claude Code sessions are open, it shows the most urgent one.

**Unofficial fan project, not affiliated with Anthropic.**

## How it works

```
Claude Code ──hook event──▶ claudepet/hook.py ──writes──▶ ~/.claudepet/sessions/<session>.json
                                                                   │
                         mac/ClaudePetMac.swift (the pill) ◀─reads─┘ every 0.4 s
```

Claude Code runs `hook.py` on events such as "you sent a prompt", "about to edit a file", "needs permission" and
"finished". The script writes one small state file per session, never prints anything, always exits successfully,
and takes about 25 ms. The pill reads those files.

## Files

```
bin/claudepet              # the command you run
claudepet/hook.py          # called by Claude Code; turns events into states
claudepet/paths.py         # state + config files
claudepet/cli.py           # start / stop / status / install / uninstall …
mac/ClaudePetMac.swift     # the floating pill (compiled on first start)
examples/settings.hooks.json
```

## Use

Requires macOS with the Xcode Command Line Tools (`xcode-select --install`).

```sh
bin/claudepet install        # add the hooks to ~/.claude/settings.json (backs it up first), then restart Claude Code
bin/claudepet start          # show the pill (builds it the first time, ~20 s)
bin/claudepet stop           # hide it
bin/claudepet status         # what it's showing, and whether hooks are installed
bin/claudepet demo           # cycle through every state
bin/claudepet autostart on   # show the pill automatically when a Claude Code session starts
```

## Remove completely

```sh
bin/claudepet stop && bin/claudepet uninstall && rm -rf ~/.claudepet
```

`uninstall` removes only ClaudePet's hooks; your other settings stay as they were. Restart Claude Code afterwards.
Your original settings file is also kept at `~/.claude/settings.json.claudepet.bak`.
