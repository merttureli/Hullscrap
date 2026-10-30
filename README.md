# Hullscrap

A top-down 2D spaceship game. Start with an empty hull, build walls, rooms and systems on a grid, run power to them, crew the ship, fly it, dock and fight. The plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Play the current build
1. Install **Godot 4.6.3** (standard build, not .NET) from https://godotengine.org/download/archive/4.6.3-stable/.
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to play.

## Controls (build mode)
| Input | Action |
|---|---|
| 1 / 2 / 3 | Floor / Wall / Door |
| Left mouse (hold to paint) | Place: green ghost = allowed, red = not, with the reason at the top |
| Right mouse (hold to erase) | Remove |
| Mouse wheel | Zoom |
| Ctrl+S / Ctrl+L | Save / load the ship (`user://ship.json`) |

A door needs walls on two opposite sides, and a wall holding a door can't be removed.

## Tests
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
CI runs these on every push and PR. Rules for AI coders are in [`AGENTS.md`](AGENTS.md).
