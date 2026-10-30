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
| W A S D | Walk (your soldier). The legs turn to the way you walk |
| Mouse (play mode) | Your soldier aims at the cursor: the torso and what they hold (a pistol; a wrench or an extinguisher while working) turn to it |
| E (hold) | Work with your own hands: stand next to a fire, a breach, a broken system or a downed crewmate and hold E. It goes at the speed of a crew member's work (see Crew, fire and repairs) |
| Middle mouse | Send Ada there (bodies are 2x2 cells, so she stands where one fits). She leaves the job board alone for 8 s |
| E over a door | Open / close the whole door piece (both cells; free, not an undo step; both modes). Crew also walk through closed doors, which open while any body overlaps them |
| O | Oxygen overlay: each room cell from red (empty) to blue (full), breached rooms outlined |
| P | Power overlay: cables shown, each network tinted, with its supply / demand over its first cable |
| Mouse wheel | Zoom (0.2 to 3; the game starts at 0.5) |
| Ctrl+S / Ctrl+L | Save / load the whole ship: tiles, doors, systems, cables, cargo, oxygen, fires (`user://ship.json`; older saves still load, but one from before the 2x scale keeps its small layout and 1-cell doors, and its systems now take their doubled size, so rebuild it) |

Build mode only:

| Input | Action |
|---|---|
| Tab | Next palette: Tiles, Systems, Cables |
| 1 / 2 / 3 | Tiles: Floor / Wall / Door |
| 1 - 9 | Systems: pick a system you hold in cargo (the list shows how many) |
| R | Systems: rotate the system by a quarter turn (a weapon or engine points up at 0 degrees: rear engines are turned twice). Door: flip the piece across the way it fits. Wall: turn the shape a quarter turn |
| T | Wall: cycle the wall tool through the shapes: full, slope45, slope2, round2 (pieces of `data/shapes.json`) |
| Shift+R | Wall: mirror the shape |
| F (over a system) | Send the nearest crew member to repair it. Unlike the job board, an order also covers a system that works but is damaged |
| Left mouse (drag to paint) | Place; the whole stroke is one undo step. Green ghost = it will apply, red = not (reason in the HUD). A system is placed with its top-left cell on the mouse, on release; a **weapon or engine** is placed by its **outside half**, in space against the outer face of the hull: the game walks inward through the wall (any thickness of full wall cells, never a door, floor or shaped piece) and puts the inside half on the first free floor behind it, and the ghost shows both halves and the wall between (refusals: "the barrel must stick out into space", "needs a flat wall to mount through", "the breech needs 4x2 free floor behind the wall"); a door piece likewise (2x1 or 1x2, turned along the wall by itself), as one undo step. A shaped wall piece (T) is the same: top-left cell on the mouse, on release, one undo step, and its ghost is the real outline of each cell |
| Shift + left mouse drag | Straight line, locked to the horizontal or vertical axis |
| Ctrl + left mouse drag | Rectangle. Floor and cables fill it, a wall makes a room (walls round the edge, floor inside); doors and systems one at a time |
| Right mouse (+ Shift / Ctrl) | Tiles and cables: the same three modes, but removing (100% refund). Systems: removes the one under the mouse (either half of a weapon or engine) and returns it to the cargo |
| Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) | Undo / redo (tiles, systems, cables and cargo) |
| Esc | Cancel a drag |

## Starter ships
The game opens on a centred panel, **Choose your ship**, with a card per design: name, one-line character, a mini schematic (the combat schematic), power supply / demand, mass, hull, shield layers and weapon names. **1 / 2 / 3** or a click loads the design into your ship; **Esc** closes the panel and keeps the current ship (the empty hull at first). The ship is fully editable afterwards, and everything in the table above works as usual. The camera zooms to fit it, and the soldier and Ada start in its middle.

| Key | Ship | Line | Character |
|---|---|---|---|
| 1 | Rustbucket (30x24 cells) | scrap | A brick: scrap-plate skin all round (most hull), 3 reactors (2 Rustbucket and a Mk2), 2 Kickjets, Bubble Rig shield, Shrapnel Cannon + Rattle Burst + Bolt Thrower (it eats scrap), a big hold with 900 scrap, 300 credits. Slow, and its scrap parts quit now and then. |
| 2 | Courier (24x19) | standard | Reliable standard parts: 2 Reactor Mk2, 2 Engine Mk2 on the rear wall and a strafe pair of Engine Mk1 on the side walls, Shield Mk1, 2 Laser Mk1 + Pulse Mk1, a titanium front row, 500 credits. |
| 3 | Prism (22x18) | neon | A glass cannon: Prism Core (it runs hot: 2 radiators in its room, a third by the guns), Ion Drive, Neon Lattice shield (2 layers, 4 sectors), Heat Lance + Siren Ion, a thin reflective coat on the nose, the lightest and most agile, 400 credits. |

Every starter is a working ship: closed rooms joined by 2-wide doors, every part on a cable with supply above demand, a helm and engines that fly (engines on the rear wall, guns through the bow, each in two halves), an oxygen generator, a fabricator alone in its workshop, crew beds, spare parts and some credits in the cargo (`"credits": N`; credits are just a cargo count for now). The hull is the ship's bounding box plus 2 cells, in the middle of the 63x63 grid.

The designs are `data/ships/starter_*.json`: the saved-ship format (Ctrl+S) plus a `blurb` line the picker shows. `Ship.from_design(path)` loads one and `ShipSim.choose_ship(path)` puts it in the player's slot. `tests/tool_make_starters.gd` builds them from room rectangles, doors, parts and plating through `BuildSession`, wires them and exports them (`godot --headless --path . --script res://tests/tool_make_starters.gd`, it prints a map and the stats of each); `tests/test_starter_ships.gd` checks them.

## Crew, fire and repairs
Every starter comes with four people: your soldier, Ada, and two more NPCs (Rook and Juno; names and suit colours come from `data/crew.json`) who start on the beds. The pirate has three enemy crew. Everyone has 100 hp.

**Fire** (`scripts/sim/fire.gd`, `ship.fires`: cell -> intensity 0 to 1, saved with the ship). A fire burns on a floor cell (a cell under a system too; doors and walls are not floor, so a fire stays in its room).
- Each second: while the room's air is above 20% the intensity grows by 0.15, below it the fire decays by 0.3 and goes out at 0; each burning cell has a 10% chance to light a random neighbouring floor cell and uses 0.05 of the room's oxygen; a system on a burning cell loses 0.5 hp (at 0 it is disabled, not destroyed).
- Fires start when a system overheats (20%) or malfunctions (30%), on the system's first cell, and when a hit in a fight ignites (`fire_chance`), on the cell that was hit.
- Drawn from `art/fx/fire` (a flame per burning cell, with its glow), or as flickering orange and red blobs when that art is missing (`ShipView.draw_fire()`), in the interior and on the ships in a fight.

**Health.** Standing in a burning cell costs 10 hp a second, a room below 15% air 5. At 0 hp a crew member is **down**: they don't move, and a crewmate revives them (3 s of work, back with 20 hp) or a powered medbay does (15 hp a second, times the medbay's `stats.heal`). A bed heals 5 hp a second. A small health bar hangs over anyone hurt.

**Jobs** (`scripts/crew/jobs.gd`, numbers in `data/crew.json`). Every second the ship's job board is rebuilt from its state and idle NPCs take the highest-priority job nobody is on (two may fight the same fire), the nearest first by walking distance (only the few nearest get a path search). They keep a job until it is done or one at least 30 points higher shows up. Your soldier is never given a job.

| Priority | Job | Work |
|---|---|---|
| 100 | Extinguish a burning cell | 0.5 intensity per second per crew member; two stack |
| 95 | Revive a downed crew member | 3 s |
| 90 | Repair a breach | 6 s x the repair multiplier of the wall's line; the wall comes back and the room seals |
| 80 (90 for a weapon, engine or shield in a fight) | Repair a malfunctioning or disabled system, or a hull mount's damaged outside half (from the inside, while the wall between the halves is whole; the outside half heals first) | 5 s x the repair multiplier of the system's line (scrap 0.5, standard 1, neon 1.5). An overheated system just needs time |
| 50 | Man a station: the helm, and weapons, shields or engines whose data says `manned: true` | stands next to it |
| 30 | Clear a wreck: the debris of a part that was shot to pieces | 4 s; gives back half its recipe materials, rounded down |
| 10 | Rest, when hurt: a powered medbay, else a bed | heals |

A manned helm adds 5% evasion in a fight (`Jobs.evasion_bonus(ship)`; the turrets' hit roll reads it) and a manned weapon cools down 10% faster (wired into `Arena.fire`). `ship.manned` maps each manned system's uid to the crew member at it.

The HUD (bottom left) has one line, "Crew: Ada repairing Laser Mk1, Rook extinguishing, Juno at helm, ...", and the chronicle logs "Fire in engine room", "Fire out", "Breach sealed", "Kickjet repaired", "Rook is down", "Rook is back on their feet".

## Combat
In play mode (**B**) press **K** to meet the test pirate (`data/ships/pirate_raider.json`, 1200 px ahead). The camera zooms out to frame both ships, the interior is put away and the crew are drawn on the hulls: they keep working (fires, breaches, repairs, stations) on both ships. Power, heat, oxygen, fires and malfunctions keep running on both ships.

| Input | Action |
|---|---|
| W / S | Throttle forward / reverse |
| A / D | Strafe left / right on the engines mounted on the side walls (no side engines, no strafe). With `"controls": {"steer": "keys"}` in `data/flight.json` they turn the ship instead |
| Mouse | Steer: the ship turns toward the cursor at its turn rate, and **fixed guns aim where the ship points** (their barrels follow the cursor inside a few degrees of gimbal). A faint boresight line and cone shows where each fixed gun points; a turret shows its arc as a wedge and a ring, and tracks the enemy by itself |
| T | Turrets autofire on / off (they fire when loaded and on target; the weapon bar shows each turret's hit chance and AUTO or HOLD) |
| Left mouse (hold) | Fire group 1: lasers, bolts, beams |
| Right mouse (hold) | Fire group 2: missiles, flak |
| 1 - 9 | Fire that weapon (the slot numbers on the weapon bar) |
| Shift | Engine ability (a Kickjet's Sputter Boost...) |
| Space | Shield ability: Overcharge gives one extra layer for 6 s, then 15 s of rest |
| Q | Utility ability (the Prism Core's Overdrive...) |
| Esc | Leave, once the pirate is wrecked or more than 4000 px away |
| R | After your ship is wrecked: back to build mode with the empty starter hull reloaded (B, then N, picks a ship again) |

The panels at the top are the schematics (yours left, the enemy's right): rooms, walls, breaches in red, systems coloured by state (green ok, yellow damaged, red disabled, orange overheated, purple jammed, grey unpowered), a hull bar and the shield pips. **Firing opens your own shield**: the sector of the bubble the shot leaves through drops for 0.3 s (laser), 0.4 s (bolt), 0.6 s (flak) or the whole beam, while shots pass it and use no layer; the schematic shows "OPEN" and the sector ring goes dark. Missiles never drop it. Open doors let shots through; closed doors block them. The weapon bar shows each weapon's key, group, cooldown ring and state (ready, cooling, no power, jammed, no ammo, disabled, offline, out of arc for a turret), and under each turret its hit chance against the enemy.

**Hull mounts, fixed guns and turrets** (`docs/CONTENT.md` 4f, `scripts/ship/mounts.gd`). A weapon or engine is two halves joined through a wall of any thickness: the **outside half** (barrel or nozzles) sits in space against the hull and takes the hits you can see, with its own hp (75% of the part's), and is only ever **disabled**, never destroyed: shots and rams then go on into the wall behind it. The **inside half** is on the floor behind the wall, where crew man, wire and repair it. If any wall cell between the halves is breached the mount is **offline** until crew patch it. A direct hit on an interior part that is already disabled **wrecks** it (both halves of a mount): it is gone, with debris on its cells that a crew job (`clear_wreck`, 4 s) clears for half its recipe materials, rounded down (nothing for a unique). Fire, heat, ion and malfunctions never wreck. Most guns are **fixed** and fire along the mount's outward direction (up at rotation 0); **turrets** (Rattle Burst, Siren Ion, Leech Laser, Concord Point Turret) track within their arc and roll a hit (accuracy less the target's evasion, 25% at full speed, 5% more with a manned helm) for 60% of the damage. An engine pushes opposite its nozzle: rear engines (rotation 2) drive the ship, side engines strafe it.

**Ramming and ricochets** (`scripts/combat/impact_fx.gd`). When two ships collide hard enough to hurt, sparks and debris fly from the contact points (`fx/sparks`, `fx/explosion`), the screen shakes by the impact energy, a banner and the chronicle say "Rammed the pirate: 14 hull damage (took 6)", and the walls take their damage as usual. A shot that glances off a hull shows a small spark at the bounce point.

Characters are big: a crew body is 2x2 cells (drawn about 3x3), so doors are a piece of exactly 2 cells in a row with a wall cell at each end (wall, door, door, wall), and a corridor needs 2 cells. Walls stay 1 cell thick. A door costs per cell; removing or replacing either cell takes the whole piece, and a wall holding a door can't be removed. Systems are items from the cargo: placing one uses an item up, removing it gives the item back. A system needs floor under every cell, and that floor can't be removed or built over while it stands there. Cables cost copper per cell (`data/build.json`) and may run under anything. A system only works when a cable connects it to a reactor; an unpowered one is drawn dimmed with a red mark.

## Art
The game draws pixel art from `art/` and falls back to flat code-drawn placeholders for anything missing (`scripts/view/art.gd` loads and caches it; no editor import is needed). What is live:
- **Systems** (`art/components`): the sprite at the part's footprint, turned with it, animated by state (on, off, weapon charge and fire, damaged, disabled, malfunction flicker, overheated pulse) with a glow layer; the heat bar, hp pips and marks stay on top. A part with no art borrows the next lower tier's (Engine Mk2 shows the Mk1 sprite until it has its own).
- **Crew** (`art/crew`): layered top-down sprites, legs to the way they walk, torso, arms, item and head to the aim, the outfit tinted with each crew member's suit colour, a 1 px shadow.
- **Structure and effects** (`art/tiles`, `art/fx`, `art/projectiles`): autotiled walls, floors, doors that open, breaches, powered cables, fire, smoke, sparks, explosions, muzzle flashes, shield ripples, shots and beams.
- **Shaped walls and the hull skin** (`art/tiles/*_shapes`, `hull_skin*`): slopes and curves are drawn from the shaped sheets (a frame per orientation and neighbour mask; a neighbour joins a wall when it covers 60% of the shared edge), ram plating from `walls_ram*` with no tint, and the open part of a shaped wall shows floor when it looks into the ship, space otherwise. A ship in a fight also gets the exterior skin over every wall that faces space (panel variants and a few vents, antennas, hatches and lamps by position, tinted by the line most of those walls belong to; neon adds an edge glow; ram plating keeps its hazard tape). The interior and build views never show it.

The format and how to add art are in [`art/README.md`](art/README.md); every file's source is in [`ASSETS.md`](ASSETS.md). The default texture filter is nearest.

## Tests
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
CI runs these on every push and PR. Rules for AI coders are in [`AGENTS.md`](AGENTS.md).
