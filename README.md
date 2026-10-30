# Hullscrap

A top-down 2D spaceship game. Start with a ready-made ship (or an empty hull), build walls, rooms and systems on a grid, run power to them, crew the ship, fly it, dock and fight. The plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Play the current build
1. Install **Godot 4.6.3** (standard build, not .NET) from https://godotengine.org/download/archive/4.6.3-stable/.
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to play. The game opens on **Choose your ship** (see [Starter ships](#starter-ships)): press **1**, **2** or **3**, then **B** for play mode and **K** to fight the test pirate.

## Controls
**B** switches between build mode (the default) and play mode. In play mode there is no ghost and the mouse buttons do nothing yet.

| Input | Action |
|---|---|
| B | Build mode / play mode (the HUD shows which) |
| N (play mode) | Pick another starter ship: asks "Discard current ship?" (Y / N), then shows the picker |
| K (play mode) | Fight the test pirate (see Combat) |
| W A S D | Walk (your soldier) |
| Middle mouse | Send Ada there (bodies are 2x2 cells, so she stands where one fits) |
| E over a door | Open / close the whole door piece (both cells; free, not an undo step; both modes). Crew also walk through closed doors, which open while any body overlaps them |
| O | Oxygen overlay: each room cell from red (empty) to blue (full), breached rooms outlined |
| P | Power overlay: cables shown, each network tinted, with its supply / demand over its first cable |
| Mouse wheel | Zoom (0.2 to 3; the game starts at 0.5) |
| Ctrl+S / Ctrl+L | Save / load the whole ship: tiles, doors, systems, cables, cargo, oxygen (`user://ship.json`; older saves still load, but one from before the 2x scale keeps its small layout and 1-cell doors, and its systems now take their doubled size, so rebuild it) |

Build mode only:

| Input | Action |
|---|---|
| Tab | Next palette: Tiles, Systems, Cables |
| 1 / 2 / 3 | Tiles: Floor / Wall / Door |
| 1 - 9 | Systems: pick a system you hold in cargo (the list shows how many) |
| R | Systems: rotate the system by a quarter turn. Door: flip the piece across the way it fits |
| Left mouse (drag to paint) | Place; the whole stroke is one undo step. Green ghost = it will apply, red = not (reason in the HUD). A system is placed with its top-left cell on the mouse, on release; a door piece likewise (2x1 or 1x2, turned along the wall by itself), as one undo step |
| Shift + left mouse drag | Straight line, locked to the horizontal or vertical axis |
| Ctrl + left mouse drag | Rectangle. Floor and cables fill it, a wall makes a room (walls round the edge, floor inside); doors and systems one at a time |
| Right mouse (+ Shift / Ctrl) | Tiles and cables: the same three modes, but removing (100% refund). Systems: removes the one under the mouse and returns it to the cargo |
| Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) | Undo / redo (tiles, systems, cables and cargo) |
| Esc | Cancel a drag |

## Starter ships
The game opens on a centred panel, **Choose your ship**, with a card per design: name, one-line character, a mini schematic (the combat schematic), power supply / demand, mass, hull, shield layers and weapon names. **1 / 2 / 3** or a click loads the design into your ship; **Esc** closes the panel and keeps the current ship (the empty hull at first). The ship is fully editable afterwards, and everything in the table above works as usual. The camera zooms to fit it, and the soldier and Ada start in its middle.

| Key | Ship | Line | Character |
|---|---|---|---|
| 1 | Rustbucket (30x24 cells) | scrap | A brick: scrap-plate skin all round (most hull), 3 reactors (2 Rustbucket and a Mk2), 2 Kickjets, Bubble Rig shield, Shrapnel Cannon + Rattle Burst + Bolt Thrower (it eats scrap), a big hold with 900 scrap, 300 credits. Slow, and its scrap parts quit now and then. |
| 2 | Courier (24x19) | standard | Reliable standard parts: Reactor Mk2 + Mk1, 2 Engine Mk1, Shield Mk1, 2 Laser Mk1 + Pulse Mk1, a titanium front row, 500 credits. |
| 3 | Prism (22x18) | neon | A glass cannon: Prism Core (it runs hot: 2 radiators in its room, a third by the guns), Ion Drive, Neon Lattice shield (2 layers, 4 sectors), Heat Lance + Siren Ion, a thin reflective coat on the nose, the lightest and most agile, 400 credits. |

Every starter is a working ship: closed rooms joined by 2-wide doors, every part on a cable with supply above demand, a helm and engines that fly, an oxygen generator, a fabricator alone in its workshop, crew beds, guns on the front edge, spare parts and some credits in the cargo (`"credits": N`; credits are just a cargo count for now). The hull is the ship's bounding box plus 2 cells, in the middle of the 63x63 grid.

The designs are `data/ships/starter_*.json`: the saved-ship format (Ctrl+S) plus a `blurb` line the picker shows. `Ship.from_design(path)` loads one and `ShipSim.choose_ship(path)` puts it in the player's slot. `tests/tool_make_starters.gd` builds them from room rectangles, doors, parts and plating through `BuildSession`, wires them and exports them (`godot --headless --path . --script res://tests/tool_make_starters.gd`, it prints a map and the stats of each); `tests/test_starter_ships.gd` checks them.

## Combat
In play mode (**B**) press **K** to meet the test pirate (`data/ships/pirate_raider.json`, 1200 px ahead). The camera zooms out to frame both ships, the interior is put away and the walking crew stop. Power, heat, oxygen and malfunctions keep running on both ships.

| Input | Action |
|---|---|
| W / S | Throttle forward / reverse |
| A / D | Turn left / right |
| Mouse | Aim. A line runs from each weapon that can fire, with its arc as a faint wedge; a weapon whose arc misses the aim point is drawn grey |
| Left mouse (hold) | Fire group 1: lasers, bolts, beams |
| Right mouse (hold) | Fire group 2: missiles, flak |
| 1 - 9 | Fire that weapon (the slot numbers on the weapon bar) |
| Space | Overcharge the shield: one extra layer for 6 s, then 15 s of rest |
| Esc | Leave, once the pirate is wrecked or more than 4000 px away |
| R | After your ship is wrecked: back to build mode with the empty starter hull reloaded (B, then N, picks a ship again) |

The panels at the top are the schematics (yours left, the enemy's right): rooms, walls, breaches in red, systems coloured by state (green ok, yellow damaged, red disabled, orange overheated, purple jammed, grey unpowered), a hull bar and the shield pips. **Firing opens your own shield**: the sector of the bubble the shot leaves through drops for 0.3 s (laser), 0.4 s (bolt), 0.6 s (flak) or the whole beam, while shots pass it and use no layer; the schematic shows "OPEN" and the sector ring goes dark. Missiles never drop it. Open doors let shots through; closed doors block them. The weapon bar shows each weapon's key, group, cooldown ring and state (ready, cooling, no power, jammed, no ammo, out of arc).

Characters are big: a crew body is 2x2 cells (drawn about 3x3), so doors are a piece of exactly 2 cells in a row with a wall cell at each end (wall, door, door, wall), and a corridor needs 2 cells. Walls stay 1 cell thick. A door costs per cell; removing or replacing either cell takes the whole piece, and a wall holding a door can't be removed. Systems are items from the cargo: placing one uses an item up, removing it gives the item back. A system needs floor under every cell, and that floor can't be removed or built over while it stands there. Cables cost copper per cell (`data/build.json`) and may run under anything. A system only works when a cable connects it to a reactor; an unpowered one is drawn dimmed with a red mark.

## Tests
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
CI runs these on every push and PR. Rules for AI coders are in [`AGENTS.md`](AGENTS.md).
