# Hullscrap

A top-down 2D spaceship game. Start with an empty hull, build walls, rooms and systems on a grid, run power to them, crew the ship, fly it, dock and fight. The plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Play the current build
1. Install **Godot 4.6.3** (standard build, not .NET) from https://godotengine.org/download/archive/4.6.3-stable/.
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to play.

## Controls
**B** switches between build mode (the default) and play mode. In play mode there is no ghost and the mouse buttons do nothing yet.

| Input | Action |
|---|---|
| B | Build mode / play mode (the HUD shows which) |
| W A S D | Walk (your soldier) |
| Middle mouse | Send Ada to that cell |
| E over a door | Open / close it (free, not an undo step; both modes). Crew also walk through closed doors, which open while they stand in them |
| O | Oxygen overlay: each room cell from red (empty) to blue (full), breached rooms outlined |
| P | Power overlay: cables shown, each network tinted, with its supply / demand over its first cable |
| Mouse wheel | Zoom |
| Ctrl+S / Ctrl+L | Save / load the whole ship: tiles, doors, systems, cables, cargo, oxygen (`user://ship.json`; older saves still load) |

Build mode only:

| Input | Action |
|---|---|
| Tab | Next palette: Tiles, Systems, Cables |
| 1 / 2 / 3 | Tiles: Floor / Wall / Door |
| 1 - 9 | Systems: pick a system you hold in cargo (the list shows how many) |
| R | Systems: rotate the system by a quarter turn |
| Left mouse (drag to paint) | Place; the whole stroke is one undo step. Green ghost = it will apply, red = not (reason in the HUD). A system is placed with its top-left cell on the mouse, on release |
| Shift + left mouse drag | Straight line, locked to the horizontal or vertical axis |
| Ctrl + left mouse drag | Rectangle. Floor and cables fill it, a wall makes a room (walls round the edge, floor inside); doors and systems one at a time |
| Right mouse (+ Shift / Ctrl) | Tiles and cables: the same three modes, but removing (100% refund). Systems: removes the one under the mouse and returns it to the cargo |
| Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) | Undo / redo (tiles, systems, cables and cargo) |
| Esc | Cancel a drag |

A door needs walls on two opposite sides, and a wall holding a door can't be removed. Systems are items from the cargo: placing one uses an item up, removing it gives the item back. A system needs floor under every cell, and that floor can't be removed or built over while it stands there. Cables cost copper per cell (`data/build.json`) and may run under anything. A system only works when a cable connects it to a reactor; an unpowered one is drawn dimmed with a red mark.

## Tests
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
CI runs these on every push and PR. Rules for AI coders are in [`AGENTS.md`](AGENTS.md).
