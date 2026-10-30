# Hullscrap: plan

## The pitch
A top-down 2D spaceship game (FTL / Among Us look, square grid). You start with an empty hull, a circle, and build the inside yourself:
- walls and doors that split it into compartments;
- an engine room, a reactor, a medbay, crew quarters;
- cables that carry power to each system.

You are also a soldier who walks around inside. The ship sits in the centre of the screen and space moves past it, like Raft. You fly it, dock with other ships and stations, trade, recruit crew and fight.

Placement uses square hitboxes on the grid, but placed objects should look natural rather than blocky, the way The Sims handles it.

## Pillars (what makes it ours)
1. **Compartments matter.** Each room has its own oxygen and pressure. Hull breaches vent a room, and closed doors seal it. Fires spread room to room. This is why you build walls.
2. **Power is a real network.** Cables connect reactors to systems. A cut cable powers down everything beyond it, so routing is part of the design.
3. **Disable, don't destroy.** Damaged components go offline and crew repair them. Only the hull can truly be lost.
4. **Crew are people.**
   - You recruit them at stations and pay wages.
   - They have skills that improve with use.
   - They man systems, which run better when manned (FTL), and fight fires, repair and heal on their own.
   - You set priorities, not every step.
5. **Two views.** An interior view with the ship centred and space scrolling past, and a tactical view with a free camera for ship-to-ship fights.
6. **Docking is physical.** Airlocks connect, and you walk aboard another ship to trade or board it.
7. **Salvage and craft (Subnautica-style).**
   - Structure (floors, walls, doors, cables) costs raw materials directly.
   - Systems (engines, reactors, weapons, shields...) are items crafted at a Fabricator from blueprints and materials, then placed from cargo. Removing a system returns the item.
   - Systems come in tiers (Mk1, Mk2, Mk3) with better stats.
   - Blueprints unlock by salvaging and scanning wrecks; materials come from salvage, mining and trade.

## Systems with character (quirks), the core of our content
Every system should be **unique, FTL Multiverse style**: not just "+10% thrust", but a trade-off that changes how you build and crew the ship. Data-driven, so new systems are mostly JSON.
- **Abilities**: each component can have abilities, either `passive` or `active` (with a duration and cooldown, triggered by the player or a crew member manning it).
  - Each ability has **effects** (e.g. thrust +40%) and **side effects** on the component or its room:
    - `drain_o2` (room oxygen per second), `heat` (see below), `power_spike` (extra draw while active);
    - `noise` / `radiation` (hurts crew in the room without protection), `vent` (opens the room to space while active).
  - Example, *Afterburner Engine Mk2*. Active: +40% thrust for 8 s. While active it drains room oxygen fast and adds a lot of heat.
    - So you put it in its own sealed room and crew it with someone in a **suit**, or with a **species that doesn't breathe**.
- **Heat**: components and rooms have heat.
  - Heat rises from abilities and heavy load and falls through `cooling` (radiators, coolant pumps, vacuum around the room).
  - Past the component's limit it **overheats**: disabled until cooled, with a fire risk. This follows our "disable, don't destroy" rule.
- **Manning requirements**: an ability can require the operator to have a trait: `no_breath`, `heat_resistant`, `suit`, `engineer_skill>=3`, ...
  - This is how crew choice matters.

## Crew species and suits
- **Species are data** with traits.
  - Examples: Human (balanced, needs oxygen); a silicon-based species (`no_breath`, slow, bad medics); a heat-loving species (`heat_resistant`, needs warm rooms); an engineering species (faster repairs, fragile).
  - You recruit them at stations.
- **Suits** are crafted items. A crew member wearing one works in low oxygen or vacuum for a limited time (an air supply that refills in pressurised rooms). Suits take a slot from a suit locker.

## Fabricator levels and workshop modules
- Every recipe has a `fab_level` (1 to 4) and optional `tools` (e.g. `laser_cutter`, `robot_arm`, `nanoforge`, `plasma_furnace`).
- The **Fabricator's level** comes from **workshop modules placed in the same room**:
  - base level 1;
  - a Robot Arm makes it level 2;
  - a Laser Cutter adds the `laser_cutter` tool;
  - an Assembly Rig plus two Robot Arms make level 3;
  - a Nanoforge makes level 4.
  - Modules need power, and some need crew.
- So an advanced engine may be **too high-level to craft** until you build out a proper workshop room. That's another reason compartments matter.
- Blueprints still have to be unlocked (salvage and scan). Knowing a blueprint and being able to craft it are separate.

### Data sketch (component entry)
```json
{"id": "afterburner_mk2", "family": "engine", "tier": 2, "size": [2, 1], "power": -3, "priority": 4,
 "stats": {"thrust": 16, "heat_limit": 100, "cooling": 4},
 "abilities": [{"id": "afterburn", "type": "active", "duration": 8, "cooldown": 30,
   "effects": {"thrust_mult": 1.4},
   "side_effects": [{"type": "drain_o2", "rate": 0.15}, {"type": "heat", "rate": 12}],
   "operator_needs": ["no_breath|suit"]}],
 "recipe": {"fab_level": 3, "tools": ["laser_cutter"], "materials": {"scrap": 40, "titanium": 12, "plasma_cell": 2}, "time": 45}}
```

Reference games for ideas, not code: Space Haven (closest), FTL, Cosmoteer, Barotrauma, Raft, Among Us.

## Decisions so far
- **Engine**: Godot 4.6.3, GDScript, desktop builds (Windows and Mac), not browser.
- **Walls are whole cells** (as in RimWorld and Space Haven). Edge walls can be revisited later if needed.
- **Multi-cell components** (a 2×2 reactor) arrive in milestone 3 with footprints and rotation.
- **Content is JSON data** (`data/`). **Logic is headless-testable** (`scripts/ship` and similar).

## Milestones (each one playable)
1. **Setup.** Repo, rules (`AGENTS.md`), tests, CI, and the first build mode. Done in the first commit.
2. **Build mode, complete.**
   - Floors, walls and doors on the circular hull, with a square ghost preview (green or red, with the reason shown).
   - Drag to paint lines and rectangles, undo and redo, a credit cost, save and load.
   - Doors open and close.
3. **Systems.**
   - Components with footprints and rotation: reactor, engine, oxygen generator, shield, weapon mount, bed, medbay, console.
   - Rooms detected by flood fill, with oxygen per room.
   - Cables solve power: which components are powered, and shortfalls.
   - An overlay view for rooms, power and oxygen.
3b. **Crafting.**
   - Materials and cargo; recipes and blueprints from data.
   - A Fabricator component with a crafting queue.
   - Crafted system items are placed from cargo.
   - Structure costs materials.
3c. **Fabricator levels**: workshop modules in the fabricator's room raise its level and add tools; recipes gated by `fab_level` and `tools`.
4. **Crew.**
   - Your soldier moves with WASD.
   - NPC crew pathfind on the grid through doors and pick jobs by priority: man a station, repair, fight fire, heal, rest.
4b. **Species and suits**: species traits from data, suits with an air supply, suit lockers.
5. **Flight + quirks v1.** Abilities (active and passive), heat and overheating, operator requirements. The first quirky engines and reactors.
5a. **Flight.** The ship-centred camera, with thrust and turning from the engines placed versus the ship's mass. The starfield drifts with velocity.
6. **Combat v1.**
   - A tactical view against one AI ship.
   - Weapons fire at targeted rooms. Shields absorb.
   - Hits damage components, start fires and cause breaches. Crew respond.
7. **Stations.** Docking through airlocks, trading, hiring crew, and boarding other ships.
8. **Content and art.**
   - Real tilesets and sprites (CC0 or bought packs, logged in `ASSETS.md`), sound.
   - More components, events, enemy ships and a sector map.

Milestones 2 to 4 together make the first "show your friend" demo: build a ship, power it, walk around it with your crew.

## Ideas backlog (not scheduled)
- Crew traits and morale.
- Ship blueprints you can share.
- Random sector events.
- A choice between pirate, trader and mercenary careers.
