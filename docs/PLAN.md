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
4. **Crew.**
   - Your soldier moves with WASD.
   - NPC crew pathfind on the grid through doors and pick jobs by priority: man a station, repair, fight fire, heal, rest.
5. **Flight.** The ship-centred camera, with thrust and turning from the engines placed versus the ship's mass. The starfield drifts with velocity.
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
