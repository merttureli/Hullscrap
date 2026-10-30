# Hullscrap: content and core rules (lead design, v1)

This is how systems, weapons and real-time combat work, plus the first content set. Everything here is **data** (`data/*.json`), read by generic code. Numbers are starting points for tuning. Visuals are swappable: every item draws through `scripts/view/visuals.gd` by id, as a placeholder now and real art later.

## 1. Component schema (`data/components.json`)
Each entry has:
- `id`, `name`, `family`, `line` (`scrap` / `standard` / `neon`), `tier` (1-3), `size`, `color`;
- `power` (+ produces, − consumes), `priority`, `manned`;
- `hp` (system health: at 0 it's **disabled** and crew repair it. A direct hit on an already-disabled interior component **wrecks** it, see 4f);
- `heat_limit` and `heat_per_s` (heat gained while running at full load), `cooling` (heat lost per second);
- `stats` (family-specific, see below);
- `abilities` (optional, see 5), `unique` (bool; unique items are found or traded only and have no recipe), `blurb` (one line of flavour).

## 2. Lines (`data/lines.json`): multipliers on top of the family and tier base
| | cost | power draw | output | mass | heat | repair time | malfunction / min | ion vulnerability |
|---|---|---|---|---|---|---|---|---|
| scrap | ×0.5 (mostly scrap) | ×1.2 | ×0.9 | ×1.2 | ×1.1 | ×0.5 | **15%** | ×1.0 |
| standard | ×1.0 | ×1.0 | ×1.0 | ×1.0 | ×1.0 | ×1.0 | 1% | ×1.0 |
| neon | ×2.0 (crystal, silicon, plasma) | ×0.9 | ×1.3 | ×0.7 | ×1.5 | ×1.5 | 3% | ×2.0 |

- **Malfunction**: rolled each second while powered, from the ship's seeded RNG (rate per minute ÷ 60).
  - The component is disabled until repaired.
  - **25%** of malfunctions also deal 1 damage to the component and have a 30% chance to **start a fire** in its room.
  - The chronicle says what happened.
- Output means the family's main stat: thrust, power produced, damage, shield recharge, O2 rate.

## 3. Heat (`scripts/sim/heat.gd`)
- Each component has `heat`.
  - While it runs, heat += `heat_per_s` × load × line heat.
  - Every second, heat −= `cooling` + the room's cooling bonus. **Radiator** modules in the same room add cooling.
- At `heat_limit` it **overheats**: disabled until heat drops below 50%, with a 20% chance to start a fire in the room when it trips.
- Room temperature is cosmetic for now. Species traits use it later (heat-loving species work better in hot rooms).

## 4. Combat: real-time 1v1, you fly and aim (owner, 2026-10-30)
Combat is **action, not menus**. When an enemy engages, the camera **zooms out to a 1v1 arena**. You fly your ship and physically aim at the enemy's parts. **How you built your ship decides how it fights.**

- **Flying** (the player is at the helm):
  - **The ship turns toward the mouse cursor** at its turn rate, so you aim nose guns by flying (owner, 2026-10-30). Heavy ships turn slowly, so they aim slowly.
  - **W/S** thrust and reverse. **A/D strafe** sideways, using engines mounted on the side walls (thrust × the sideways component of their push). No side engines means no strafe.
  - A setting `controls.steer` switches to keys (A/D turn as before, with the mouse only aiming gimbals).
  - Speed, acceleration and turn rate come from `flight.gd`: powered engines' thrust against the mass of everything you built.
  - The crew stay aboard and repair, fight fires and man stations on their own.
- **Aiming**:
  - **Fixed guns aim where the ship points** (plus a few degrees of gimbal toward the cursor). Turrets aim themselves (see "Fixed guns and turrets" below).
  - **LMB** fires weapon group 1, **RMB** fires group 2. Lasers default to group 1 and missiles to group 2. **T** toggles turret autofire.
  - **1–4** fire a single weapon, **Shift** triggers the engine ability (e.g. Afterburner), **Space** the shield ability, **Q** and **E** utility abilities.
  - Weapons have **cooldowns** (charge times) shown on the weapon bar.
- **Fixed guns and turrets (owner, 2026-10-30)**: a weapon fires from **its own hull mount** (4f), outward through its wall.
  - **Most weapons are fixed.** The barrel points along the mount's outward direction, so **you aim by pointing the ship**.
    - A small **gimbal** (`gimbal` in degrees; Scrap 3, Standard 5, Neon 8) lets the barrel follow the cursor inside that cone.
    - Nose guns fire forward, and guns on a side wall fire sideways. **Broadside ships** are a real build.
    - A faint boresight line shows where each fixed gun points.
  - **Turrets** (`"turret": true`) rotate within their `arc` (centred on the outward direction) at `track` degrees per second, and **aim themselves** at the enemy with perfect lead, firing when ready.
    - **Reliable but weak**: about 60% of a fixed gun's damage at the same tier, ×1.5 cost, and 1 more power.
    - **Hit chance** = `accuracy` (0.6–0.85) − the target's evasion. Evasion = 0.25 × speed ÷ max speed, +0.05 with a manned helm. The weapon bar shows the hit % against the current target.
    - Each turret shot rolls on the combat RNG. **A hit aims at a random outer cell facing the turret; a miss aims just off the hull.** Then physics takes over: a hard turn can still dodge it, and shields still stop it.
    - So **turrets can't pick your reactor; a good pilot with fixed guns can.** Turrets suit steady chip damage, ion, and builds that can't turn (rams, freighters).
  - **Skill beats spending**: a good pilot with cheap fixed guns puts full damage exactly where they want and dodges turret fire. A bad pilot is better off with turrets.
  - **Targeting Computer** (utility, 2×2, power −1, standard line, C): shows a **lead marker** for fixed guns, and gives turrets +0.1 accuracy.
    - Variants: Scrap "Spotter's Scope" (cheap, and the marker jitters) and Neon "Oracle Lens" (marker, plus the enemy's weapon charge bars).
  - **Pilot AI** turns its nose to lead you with fixed guns. `ai.aim_skill` (0–1) adds aim error: Rustfangs 0.5, Concord 0.85.
  - **Which weapons are turrets**:
    - Turrets: Rattle Burst (scrap), Siren (neon ion), Leech Laser (★), and a new **Concord Point Turret** `laser_turret_mk1` (standard, damage 1, cooldown 4, accuracy 0.8, arc 270, track 120°/s).
    - Everything else is fixed: lasers, pulses, Shrapnel Cannon, Bolt Thrower, Artemis, Ion Blast, Heat Lance (sweep the beam by turning) and Breach Harpoon.
- **Shot types**:
  - **Lasers** are hitscan, an instant beam to the first thing they meet, so you have to track the target.
  - **Pulse, bolt and flak** are projectiles with a travel speed. You have to **lead moving targets**; there's no auto-aim.
  - **Missiles** are slow and lightly homing, pass through shields, and explode with splash damage.
  - **Beams** sweep a line while held.
- **Physical hits on the ship's real grid**:
  - Shots travel in the plane and **collide with the enemy's actual cells**, in ship-local coordinates with its rotation.
  - Every solid cell has **hp**: wall 4, door 3, component = its `hp`. Floor cells are open interior: shots pass over them but can hit crew standing there.
  - A projectile deals `damage` to the first solid cell it meets.
    - A wall at 0 becomes a **breach**: a hole, so the room vents.
    - A component at 0 is **disabled** until crew repair it. A direct hit on one that's already disabled **wrecks** it (4f). Outside mount halves are only ever disabled.
    - If the weapon has `pierce`, leftover damage carries on into the next cells.
  - **Thick outer walls are armour.** A reactor in the middle is protected, and an exposed one is a target. Players will aim for engines and weapons, and flank to reach the soft side.
  - Every hull hit also lowers the ship's **hull integrity** pool: hull_hp = 20 + armour plates. At 0 the ship is **wrecked** and becomes a salvageable derelict.
- **Shields** are a bubble around the hull (its shape is below) with **layers** from powered shield components.
  - A projectile or laser hitting the bubble uses up a layer, and layers recharge over time.
  - Missiles pass through. Ion removes layers and ion-locks systems.
- **Firing opens your own shield (owner, 2026-10-30)**:
  - When you fire anything shields can stop (laser, bolt, flak, beam, ion), **your whole bubble is open** for `drops_shield_s`: laser 0.3 s, bolt 0.4 s, flak 0.6 s, ion 0.3 s, and a beam for its whole duration.
  - Layers aren't spent while it's open, and **missiles never open it**.
  - So you time your volleys, shield-heavy ships favour missiles, and an enemy who just fired is briefly exposed.
- **Shield shape (owner, 2026-10-30: "surround the whole ship, never clip the inside")**:
  - The bubble is the **convex hull of the ship's solid cells** (outside mount halves included), **inflated by 1.5 cells with rounded corners**, rather than an ellipse.
  - So it hugs any silhouette (long, wedge-shaped, lumpy) and never cuts through the hull. Hits test against that shape.
  - It is rebuilt when the hull changes (building, a part lost); breaches don't change it.
- **Sectors and balance, Star Wars: Squadrons-style (owner, 2026-10-30)**:
  - The bubble's **sector count** comes from the best powered generator. Sectors are angle ranges from the ship's centre, starting at the bow.
    - **1 sector** (Mk1, scrap): one piece, nothing to configure.
    - **2 sectors** (Mk2): **bow and stern**.
    - **4 sectors** (Mk3, and Neon from Mk1): bow, starboard, stern, port.
    - **8 sectors** (Mk5, and late uniques): the 4 above plus the diagonals.
  - **Balance**: each sector has a weight `w` in steps of 0.5, from 0 to 2, and the weights always sum to the sector count (even = every w is 1).
    - A sector holds **`total layers × w`** layers.
    - So with 2 layers on bow and stern: even is 2/2, "double the bow" is 4 bow and 0 stern, and 3/1 is in between.
    - Protection is moved, never created.
  - **Layers are per sector**: a hit spends a layer of the sector it hits, and each sector recharges its own.
  - **Shifting takes time**: the losing sector drops at once, and the gaining sector fills at the recharge rate, so you can't swap for free as a volley lands.
  - Firing opens **only the sector the shot leaves through**, for `drops_shield_s`.
  - **In combat**: the arrow keys shift balance one step: ↑ bow, ↓ stern, ← port, → starboard (port and starboard need 4+ sectors). The step is taken from the opposite sector first, then evenly from the others. **End** returns to even.
    - A small shield diagram by the weapon bar shows each sector's layers.
  - **The Shields tab** (**H** in play or build mode): your ship's silhouette with its real bubble and sectors.
    - Click a sector's + and − (the weights stay summed), or pick a preset: Even, Bow, Stern, Port, Starboard, plus 2 custom slots.
    - The chosen balance is saved with the ship and is how every fight starts.
  - The bubble is drawn along its shape: brightness and thickness by each sector's layers, a faint dashed line for a sector at 0, and a shimmer where layers are filling.
  - **Pilot AI** with 2+ sectors shifts toward the side facing its enemy, at a speed set by `ai.aim_skill`.
- **Shield-heavy builds**: layers are the sum of your powered generators, each a big power draw, so lots of energy plus generators is a real alternative to armour.
  - **Space = Shield Overcharge**: +1 temporary layer for 6 s, at +4 power draw while active, with a 20 s cooldown.
- **Fires and breaches** come from hits (`fire_chance`, and walls reaching 0) and use the existing oxygen and fire rules.
- **Two schematics at the top of the screen**: faint close-up maps of **your ship and the enemy's**, FTL-style. They show rooms, systems with hp, disabled, fire and breach states, hull integrity and shield layers. You read the damage there while fighting in the arena.
- **Enemy pilot AI** keeps its preferred range, strafes, **leads its shots at your components** (weapons, then engines, then reactor) and uses its abilities on cooldown. It's deterministic from the battle seed.
- **Determinism**: physics and all rolls step at a fixed rate with the battle's seeded RNG, so a battle with the same inputs replays exactly.

## 4b. Armour materials, layering and damage types (From the Depths, in 2D)
- **Damage types**:
  - `kinetic` (bolts, flak, scrap missiles);
  - `energy` (lasers, beams, pulse);
  - `explosive` (missiles and their splash);
  - `ion` (no structural damage: strips shield layers and ion-locks systems).
  - Every weapon has a `damage_type`.
- **Walls are armour, and layers are cells.** A hull 3 cells thick is 3 layers. Each wall **material** is its own tile in `data/tiles.json`, with:
  - `hp`, `mass` (feeds `flight.gd`, so more and heavier layers make a slower, sluggish ship), `cost`, `line`;
  - `resist` (damage multiplier per type, e.g. `{"energy": 0.5}`);
  - `deflect` (chance per type to bounce a shot away entirely, e.g. `{"energy": 0.4}`);
  - optional quirks.
- **Ricochet**: kinetic shots hitting a wall at a shallow angle (more than 60° from the surface normal) have a 50% chance to glance off. Angled hull shapes matter.
- **Spacing**: an `explosive` hit detonates on the first layer. A **spaced** layer (an empty or floor cell between two wall layers) cuts the splash reaching the next layer to 30%.
- **Materials v1** (tune later):

| Material | Line | hp | mass | Strong against | Weak against | Notes |
|---|---|---|---|---|---|---|
| Scrap Plate | scrap | 3 | 2.0 | n/a | explosive ×1.5 | dirt cheap, easy to patch |
| Steel Wall | standard | 4 | 2.0 | n/a | n/a | the baseline (today's `wall`) |
| Titanium Alloy | standard | 6 | 1.5 | kinetic ×0.8 | n/a | light and strong, costs titanium |
| Heavy Armour | standard | 10 | 5.0 | kinetic ×0.6, explosive ×0.7 | n/a | very heavy, a slow brick |
| Reflective Coating | neon | 2 | 0.5 | **deflects 40% of energy** | kinetic ×1.5 | the outer skin against lasers |
| Ablative Plating | standard | 5 | 2.5 | energy ×0.5 | n/a | loses 1 max hp per energy hit (burns away) |
| Whipple Spacer | standard | 2 | 0.8 | explosive (spacing rule) | n/a | thin sacrificial outer layer against missiles |
| Neon Lattice | neon | 3 | 1.0 | energy ×0.7 | ion ×2 | **quirk**: 20% of the energy damage it absorbs becomes ship power for 5 s |

- **The design question this creates**: reflective outside against lasers, alloy in the middle, a Whipple spacer against missiles, heavy armour only around the reactor. Every layer costs speed and turning. Enemies counter with their weapon mix.
- **Build mode**: every wall material is in the Tiles palette. **Ctrl-drag a room** uses the selected wall material. A new **"Plating" tool** adds one layer around the whole outer hull (it expands outward if there's hull room).
- Breached layers (hp 0) leave a hole. Repairing restores the original material.

## 4c. Premade ships, hull frames and expansion (owner, 2026-10-30)
- **Premade ships** are data: `data/ships/*.json`, in the same format as a saved ship (hull, tiles, components, cables, cargo, crew). They're used for:
  - **starter ships**: choose one at a new game, then modify it freely. v1 has 3:
    - *Rustbucket*: scrap-heavy, cheap, big cargo;
    - *Courier*: small, fast, standard parts;
    - *Prism*: a small neon ship with high power and fragile armour.
  - **enemy and NPC ships**: pirates, traders, derelicts, stations.
  - **test fixtures**.
  - In build mode, Ctrl+E exports the current ship as a design file.
- **The buildable area is the hull frame.** A ship can only build on its **hull cells**, and starter ships come with a small frame.
  - To grow, you **buy Hull Frame** items at shipyards (stations) and place them **adjacent to the existing hull** (4-connected) to physically extend the space you may build on.
- **Expansion gets more expensive with size**: price per frame cell = 20 credits × (1 + hull_cells / 400). So a very big, very good ship is possible, but costly.
- **Size balances itself**: more space means more walls to enclose it, more material cost, more mass (slower, turns worse), more armour, more oxygen to fill and more crew to run it. No artificial size cap beyond the grid limit (128×128).
- **Credits** are the trading currency (buying frames, gear and crew; selling salvage). Materials stay physical cargo. Each starter ship starts with some credits.
- The ship grid is a fixed 128×128 workspace. The hull marks which cells you own.
- **Ship silhouettes (owner, 2026-10-30: "spaceships being rectangles is pretty goofy")**: no premade ship is a rectangle.
  - Every designed ship (starters, enemies, NPCs, stations) uses **slopes and curves** (4d) for a bow, stern and flanks with character.
  - It has a **non-rectangular footprint**: sponsons, wings, an engine block, a tapered nose, a raised bridge pod.
  - **It reads at a glance in combat.** Guns sit on flat hull faces (mounts need a flat wall), and the slopes go everywhere else.
  - The direction per ship:
    - *Rustbucket*: a lumpy, asymmetric patched freighter. A blunt sloped bow, one fat cargo sponson on the port side, a rounded stern with the engines in a wide block, and a scrap-plate patch that sticks out.
    - *Courier*: a sleek arrowhead. A long `slope2` bow taper, swept-back wings carrying the side Strafe Jets, and a narrow waist.
    - *Prism*: a faceted crystal shape. Only 45° facets (a diamond or hexagon outline), a symmetric neon spine, and a pointed bow and stern.
    - *Pirate raider*: a jagged wedge with a notched prow and asymmetric gun sponsons.
    - *Rustfang rammer*: the ram-plated V bow (already shaped), a heavy engine block and short stubby flanks.
  - The **build mode** helps the player do the same: the shape tool (T/R/Shift+R) is in the hint line, and later a "Round Off" tool.

## 4d. Angled and curved parts: slopes, curves and real ricochet (owner, 2026-10-30)
Walls stop being only squares. **Any wall material can take a shape**, for style (ships with real silhouettes, inside and out) and for **physics** (sloped armour deflects).
- **Shapes are data** (`data/shapes.json`): a polygon per cell in cell-local 0..1 coordinates, plus multi-cell **pieces** built from them. Pieces rotate in quarter turns and can be mirrored.
  - v1 pieces:
    - `full` (today's wall);
    - `slope45` (1 cell, half triangle);
    - `slope2` (2×1 cells, a shallow ~27° ramp: a small triangle plus a trapezoid);
    - `round2` (2×2 cells): a convex rounded corner. At rotation 0 the solid region is the **quarter disk centred at the piece's bottom-right corner (2,2) with radius 2**: solid toward the bottom-right, empty (space or floor) at the top-left. The arc is an 8-segment polygon.
    - `tri` at rotation 0 is the **bottom-left half** (the diagonal runs from the top-left corner to the bottom-right). `slope2` at rotation 0 rises from (0,1) to (2,0) across its two cells, solid below the line.
  - A shaped cell stores `shape`, `rot` and `mirror` next to its material tile.
- **Area scaling**: hp, mass and cost scale with the shape's solid area (triangle = 0.5, minimum 1 hp, cost rounded up). Sloped hulls are lighter per cell but take more cells to wrap a room.
- **Rooms and walking**: in v1 a shaped cell is fully **solid** for sealing rooms and for pathfinding. Its open part is drawn as floor (inside) or space (outside) based on its neighbours.
- **Combat physics**:
  - Rays and projectiles test the **real polygon edges**. The hit point and its **surface normal** give the incidence angle θ (0 = straight on).
  - **Sloped armour**: kinetic and explosive damage × `clamp(cos θ, 0.5, 1)`, because a shot at an angle passes through more plate. Energy is unaffected.
  - **Ricochet** (replaces the flat 50%-over-60° rule, for every cell including flat walls): kinetic chance is 0 below 40°, rising linearly to 80% at 75°+.
  - **Reflective coating** deflects energy at its base chance × (1 + 0.5 sin θ).
  - **Bounces are real**: a ricocheted or deflected shot **reflects** off the surface at 50% damage (lasers bounce once, projectiles up to twice) and can hit anything, **including your own ship** or a third party. Angle your plates so bounces go out into space.
- **Building**: in the Tiles palette, **T** cycles the shape (full → slope45 → slope2 → round2), **R** rotates, **Shift+R** mirrors.
  - A **Round Off** tool (later) converts the hull's convex outer corners into slopes automatically.
- **Exterior hull skin**: outer solid cells (next to space) get a hull-skin layer drawn outside (panel lines, rivets, material tint, edges that follow the slopes and curves). In combat at a distance the skin is what you see, as in FTL.

## 4e. Hitboxes and ramming: ships collide physically (owner, 2026-10-30)
Ships are physical bodies made of their cells. **They collide, and both take damage**, so **ram builds** are a real strategy.
- **Hitboxes**:
  - Every solid cell (walls, doors, component cells, and **shaped cells with their real polygons**) is part of the ship's hitbox, in ship-local space, rotated with the ship.
  - Broad phase: bounding circles. Narrow phase: only **outer cells** (solid cells next to non-solid), tested against the other ship's cells. Contacts are pairs of overlapping cells, each with a point, normal and penetration.
- **Response** (fixed 1/60 s substeps, deterministic):
  - Ships are pushed apart along the contact normal, weighted by inverse mass.
  - Impulse `j = (1 + e) · v_rel·n / (1/mA + 1/mB + angular terms)` with restitution `e = 0.2`, applied to both velocities **and spins**. The moment of inertia comes from the ship's cells, so off-centre hits spin you.
  - Mass is the flight mass (heavy armour makes a battering ram, and a slow one).
- **Damage**:
  - Impact energy `E = ½ · μ · (v_rel·n)²` with reduced mass `μ = mA·mB/(mA+mB)`.
  - Below a safe speed (`ram.min_speed`, about 40 px/s relative) there's no damage: a gentle bump, which docking needs.
  - Above it, each ship takes `E × ram.damage_k`, spread over the cells in contact (more to the cells hit hardest), as **kinetic** damage. Material resistance and slope angle apply (a glancing slope contact does less, per the sloped-armour rule).
  - Walls at 0 hp breach, components at 0 are disabled, and the lost hp lowers hull integrity.
  - Crew in rooms touching the impact take a knock (5 hp per 100 px/s of impact).
- **Ram content**:
  - **Ram Plating** (wall material, standard line, C): hp 12, mass 4, kinetic resist 0.4. Quirk `ram`: it **deals 2× ram damage and takes 0.5×**. A bow of it, plus slopes to glance off return fire, is the classic ram build.
  - **Inertial Dampener** (utility component, 2×2, C, power −2): halves ram damage taken by your **non-ram** cells and stops crew knocks. The counter.
  - **Scrapper "Battering Bow"** (★ found): a 4×2 bow component. Ram damage ×3, and it **latches on** (a tether) for 3 s after a hit, a natural boarding opener.
- **Pilot AI**: ship designs may set `"ai": {"style": "rammer"}`. A rammer closes at full thrust with its bow (the side with the most ram plating) aimed at you, uses its engine ability on approach, and backs off after impact to come around again.
- **Wrecks and debris**: wrecked ships stay physical. You can ram them, push them, and later tow them.
- **Tuning** (`data/collision.json`): `restitution`, `min_speed`, `damage_k`, `crew_knock`, `separation_slop`.

## 4f. Hull mounts: two linked halves through a hull of any thickness (owner, 2026-10-30)
Weapons and engines are **two linked halves**, not FTL's all-outside nor a box in a room:
- the **outside half** (turret and barrel, nozzles) sits in space against the hull's outer face, and **takes the hits you can see**;
- the **inside half** (breech, capacitor, ammo feed, engine core) sits on the floor against the hull's inner face. Crew **repair, wire, feed and man it** there.
- **Between them is your wall, as thick as you like**: 1 cell of steel, or 5 layers of composite and ablative plating. The halves are linked straight through it.

- **Data**: `size` is the inside half. `"mount": {"outside": [4, 2], "outside_hp": 30}` adds the outside half.
  - Standard guns and engines are 4×2 + 4×2. Heavy ones have a 4×3 outside half.
  - At rotation 0, **outward is UP**: the outside half sits above the inside half, with the wall in between. Rotate to mount on any wall (rear engines use rotation 2).
- **Placement** (one item, one placement, with a ghost of both halves):
  - The player places the **outside half** against the outer face of the hull.
  - The game walks inward through the wall along the mount axis, and puts the **inside half on the first floor rows behind it**.
  - **The link** is the straight run of cells between the two halves, across the mount's full width. It must be **at least 1 cell deep**, and every cell must be a full wall cell (any material; no doors, floor or shaped pieces).
  - The outside cells must be exterior (no tile, open to space), and the inside cells free floor.
  - Refusal reasons: "the barrel must stick out into space", "needs a flat wall to mount through", "the breech needs 4×2 free floor behind the wall".
  - Thicker walls protect the inside half better and weigh more. That's the trade-off; there's no depth limit.
  - **Saves** store one record per mount: `pos` (inside half), `rot` and `out` (the outside half's top-left). Bump the save version.
- **Damage: outside is built to take it, inside is not**:
  - **Outside half**: its own hp (`outside_hp`). At 0 it's **disabled, never destroyed**: the gun stops firing, or the engine stops pushing.
    - Shots that hit a disabled outside half pass through to the wall behind it.
    - Crew repair it **from the inside half**, while the link is intact.
  - **Inside half**: like every interior component, it's only reachable by a direct hit once the wall in front is breached.
    - At 0 hp it's disabled and repairable, as now.
    - **A direct physical hit (projectile, splash or ram) on an interior component that is already disabled wrecks it** (see below).
    - Wrecking the inside half wrecks the whole mount; the outside half breaks off.
  - **The link cut**: if any link cell breaches, the mount goes offline (no feed, power or control) until crew patch that breach. The room vents as usual.
  - The outside half is part of the hitbox. Turrets stick out, so **rams hit guns first**.
- **Wrecked components (owner, 2026-10-30)**: "disable first, destroy when exposed". This applies to every interior component, not just mounts.
  - A wrecked component is **gone**: removed from the ship, with a wreck decal on its cells.
  - A crew job **`clear_wreck`** (priority 30, 4 s) clears the cells and recovers **half its recipe materials** (rounded down) into cargo. A unique (found) component has no recipe, so wrecking it loses it for good.
  - Fire, heat, ion and malfunctions only ever **disable**. They never wreck.
  - So protect your systems with walls, and repair disabled ones before the next volley lands.
- **Weapon aim**: fixed guns fire along the mount's outward direction (± `gimbal`). Turrets rotate within their `arc`, centred on the outward direction. See "Fixed guns and turrets" in section 4. The shot leaves from the barrel's muzzle.
- **Power and crew**: cables connect only to the inside half, and the station is manned there.
- **Engines**: thrust acts along the **opposite of the nozzle direction**. Forward thrust for W/S is the sum of each engine's thrust × cos(angle between its push and the ship's forward).
  - Rear engines give full thrust, side engines none (lateral thrust and strafing come later).
  - Turning still comes from total thrust, as now.
- **Ammo racks** (logistics, Cosmoteer-style):
  - `ammo_rack` is an inside component, 2×2, holding up to 20 units of one ammo item (missiles, scrap for the Bolt Thrower, ...). It shows its fill level.
  - A weapon with `ammo` draws from racks **in the same room as its inside half**, or from any rack on its **conveyor network** (below). "No ammo rack in reach" and "rack empty" are its refusal reasons.
  - **A crew job `restock`** (priority 40) carries ammo from ship cargo to any rack below 50%: 1 s per 5 units, walking to it.
  - **A wrecked rack holding explosive ammo (missiles) explodes**: 2 damage per unit, as splash in its room. A big central magazine is efficient, and a liability.
- **Conveyor belts (owner, 2026-10-30)**: found upgrades that let racks sit anywhere and feed the guns automatically, so crew restock one magazine instead of running between guns.
  - **The upgrade is a belt drive**, a found or traded component (not a starting blueprint), 2×2, power −1. Line variants:

    | Drive | Line | Speed | Feed | Quirk |
    |---|---|---|---|---|
    | Clan Chain Drive | Scrap | 3 cells/s | 1 unit / 0.8 s | jams on malfunction (line reliability) until a crew member kicks it |
    | Concord Autoloader | Standard | 5 cells/s | 1 unit / 0.5 s | — |
    | Lumen Mag-Rail | Neon | 8 cells/s | 1 unit / 0.3 s | ion stops it for the ion duration |
  - **Belts** are a floor overlay laid cell by cell in build mode (an autotile, like cables), costing 1 scrap per cell. Crew walk over them.
    - Belts run on floor and door cells, never through walls (to feed a gun, lay the belt to its inside half).
    - Building belts needs at least one belt blueprint, which comes with your first drive.
  - **Networks**: orthogonally connected belt cells form a network. A rack, weapon or drive **is on a network if a belt cell touches its edge**.
    - A network moves only with a powered, working drive on it. Several drives add feed rate, and the speed is the best drive's.
    - A weapon pulls its ammo from the nearest rack on its network (shortest belt path). Each unit **rides the belt visibly** and arrives after path length ÷ speed. Reloads wait for it.
  - **Damage**: a belt cell under fire or on a breached cell is cut, splitting the network, until crew repair it (the same job as cables).
  - Later, belts can carry other items: salvage from the airlock to cargo, or scrap to the fabricator.
- **Ships to redesign**: the starters, the pirate raider and the rammer get their guns and engines re-mounted through their walls (the generator tool rebuilds them). Courier gets a thicker bow.

## 5. Abilities and quirks (`scripts/sim/abilities.gd`)
- An ability is `{id, name, type: active|passive, duration, cooldown, effects, side_effects, operator_needs}`.
  - Active abilities are triggered by the player (or by an AI captain) when the component is powered and, if `operator_needs` is set, manned by a qualifying crew member.
- **Effects**: `stat_mult` (e.g. `{"thrust": 1.4}`), `shield_layer` (+1 temporary), `charge_mult`, `evasion_add`, `o2_add`.
- **Side effects** (per second while active, or once on trigger):
  - `drain_o2` (room), `heat` (component), `power_spike` (extra draw);
  - `fire_risk` (chance/s), `vent` (the room opens to space), `self_damage`, `radiation` (crew damage in the room unless suited).

## 6. First content set (v1)
Tiers and lines follow the tables. Unique items (★) have no recipe.

**Reactors** (power):
- Scrap Rustbucket Reactor (6 power, loud, 15% malf);
- Standard Mk1, Mk2 and Mk3 (8, 12, 16 power);
- Neon Prism Core (16 power, heat-hungry, needs radiators).
- ★ *Leaking Fusion Bottle*: 20 power, but radiation in its room unless the crew are suited.

**Engines** (thrust, evasion):
- Scrap Kickjet; Standard Mk1, Mk2 and Mk3; Neon Ion Drive (light, very efficient);
- ★ *Afterburner* (standard Mk2 base). Active: thrust ×1.4 for 8 s, cooldown 30 s. Side effects: drain_o2 0.15/s and heat 12/s. Operator needs `no_breath` or `suit`.

**Shields**:
- Scrap Bubble Rig (1 layer, flickers: 15% malf);
- Standard Mk1, Mk2 and Mk3 (1, 2 and 3 layers);
- Neon Lattice (2 layers, fast recharge, ion-weak).
- ★ *Mirror Veil*: a passive 15% chance to reflect bolt hits.

**Weapons**:
- **Lasers (bolt)**: Scrap Rattle Burst (3 shots, 2 dmg, jams), Standard Burst Mk1–3, Neon Heat Lance (beam; 30% fire chance on every room swept; overheats fast).
- **Ion**: Standard Ion Blast (removes 1 layer, 5 s ion lock); Neon Siren Ion (also locks the target room's doors).
- **Missiles**: Scrap Bolt Thrower (fires **scrap** as ammo, 2 dmg, pierces); Standard Artemis Mk1 (3 dmg, pierce, 1 missile item per shot).
- **Flak**: Scrap Shrapnel Cannon (5 small projectiles, 1 dmg each; great against shields; 10% breach chance).
- ★ *Leech Laser*: each hit drains 1 power from the target's reactor for 10 s and gives it to you.
- ★ *Breach Harpoon*: 1 dmg and a guaranteed breach. It can also pull a derelict in for docking.

**Life support**:
- Scrap Wheezer O2 (cheap, noisy, malfunctions);
- Standard O2 Mk1 and Mk2;
- Neon Bloom Garden (O2 plus slow crew healing in the room; needs light power).

**Utility and structure**:
- `radiator` (cooling bonus in the room);
- `armor_plate` (hull +2 each; heavy);
- `door_lock` (blast doors resist boarding);
- `medbay`, `bed`, `helm`, `fabricator` and the workshop modules (as in PLAN).

## 7. Order of implementation (each step is a Sonnet brief with tests)
1. `lines.json`, the `line`/`hp`/`heat` fields, the stats resolver (base × line × tier → effective), reliability rolls, heat and overheating, and the visual registry.
2. **Combat physics, headless**:
   - an arena with 2 ships (flight bodies, rotated grids);
   - projectiles and hitscan lasers, weapon arcs and cooldowns;
   - cell collision with hp and pierce;
   - **damage types, wall materials (resist, deflect, ricochet, spacing)**;
   - shields, breaches, disables and hull integrity;
   - deterministic tests.
3. **Combat in the game**: the zoomed-out arena, flight controls, mouse aiming, the weapon bar, both schematics at the top, and a pirate ship with pilot AI.
4. Abilities, with the Afterburner end to end.
5. Crew jobs: repair, firefighting, manning stations (manned bonuses).
6. Premade ships: the design file format, 3 starters plus 2 pirates, a start screen to choose one, Hull Frame items and the expansion tool, credits.
7. Physics: shaped cells, ricochet, ship collisions and ramming (4d, 4e).
8. Hull mounts (two halves), fixed guns and turrets, mouse steering, wrecked components, ammo racks and the restock job, conveyor belts (4, 4f).
9. The Drift: map, jumps, events, reputation, the debt and stations (8), with the first event pack.
10. Species in play (9): species data, rigs in the game, starting crews, hand weapons data.

## 8. The Drift: the map, jumps, events and the debt (lead, 2026-10-30)
This is the campaign loop that gives fights, salvage and trade a reason, FTL-style but with a home.
- **The map** (`scripts/space/drift.gd`, logic; `data/drift.json`, tuning):
  - It is generated from the campaign seed: **28 nodes** scattered in a 1600×1000 region with a minimum spacing. Lanes join each node to its 2–4 nearest neighbours, and the graph is always connected.
  - **Fixed places**:
    - **Gantry Rusthold** is the start, at the left edge.
    - **Meridian** is mid-map.
    - **The Prism** exists from the start but stays hidden until the flag `prism_revealed` is set.
    - **Three Dead Gates** sit on the far edges (`gate` nodes, not enterable yet: "the gate is dark").
  - Every other node rolls a type by weight: `pirate` 22, `wreck_field` 18, `distress` 16, `trader` 10, `anomaly` 8 (Lumen), `patrol` 8 (Concord), `empty` 18.
  - **Fog**: you see the types of nodes next to ones you've visited. Others show "?". Stations are always visible once you've heard of them (a flag).
- **Jumping**:
  - Click a node linked to yours. A jump costs **1 `fuel`**, a new item (start with 6, buy at stations for 8 credits).
  - With no fuel, you can only wait for a passing trader (an event that sells fuel at triple price) or drift: a jump that costs 15 hull integrity.
  - Each jump advances the **jump counter**, which drives the debt clock and the danger.
  - **Danger**: pirate and patrol fights scale with the jump counter. Enemy designs pick from tables by tier (tier 1 at jumps 0–9, tier 2 from 10, tier 3 from 25).
- **Arriving**: the node's type runs an **event** picked by weight from `data/events/*.json` (a seeded roll). A pirate node may skip the talk and start a fight.
- **Events (FTL-style text with choices)**, one JSON object per event:
  ```json
  {"id": "distress_hauler_fire", "type": "distress", "weight": 10, "once": false,
   "requires": {"jumps_min": 0, "flag": "", "not_flag": "", "rep_min": {"clans": -10}},
   "text": "A Scrapper hauler is spinning, a fire glowing through its cargo windows...",
   "choices": [
     {"text": "Dock and help fight the fire.", "outcomes": [
        {"weight": 70, "text": "...", "effects": {"items": {"scrap": 40, "credits": 30}, "rep": {"clans": 1}}},
        {"weight": 30, "text": "...", "effects": {"crew_hp": -20, "items": {"scrap": 15}}}]},
     {"text": "[Basalt] Send Rook out on the hull, no suit needed.", "requires": {"species": "basalt"},
      "outcomes": [{"weight": 100, "text": "...", "effects": {"items": {"scrap": 60}, "rep": {"clans": 2}}}]},
     {"text": "Leave them to it.", "outcomes": [{"weight": 100, "text": "...", "effects": {}}]}]}
  ```
  - `requires` on an event: `jumps_min`, `jumps_max`, `flag`, `not_flag`, `rep_min`/`rep_max` per faction, `node` (a node type).
  - `requires` on a choice: any of those, plus `species`, `trait`, `items` (you must hold them; they're paid only if `pay` is set), `component` (installed), and `credits`.
    - A choice whose `requires` names a species, trait or component is a **blue option**: shown in cyan, with its reason in brackets.
    - A choice whose requirements aren't met is hidden. One that only lacks items or credits shows greyed out, with what it needs.
  - **Effects**:
    - `items` (+/−, including `credits`, `fuel`, materials and components), `rep` {clans, concord, lumen}, `crew_hp` (everyone, +/−), `hull` (integrity +/−), `flag` / `clear_flag`;
    - `recruit` {name?, species}, `lose_crew` (a random non-player), `blueprint` (an id);
    - `fight` (a ship design id, or `"tier"` to roll from the node's table), `goto` (another event id: a follow-up page), `reveal` (a node or station id), `debt` (+/−).
  - Outcomes are rolled with the campaign RNG. A `fight` effect starts combat, and after a win the event's `after_win` text and effects (optional) run.
- **Reputation**: three numbers, `clans`, `concord`, `lumen`, from −10 to +10, starting at 0.
  - Below −5, that faction's stations refuse you and its patrols attack.
  - At +5 and above, prices are 20% off and its event options open up.
  - `data/factions.json` holds id, name, line, colours, the ship name style and these thresholds. Rustfangs, Wardens and the Hollow are listed as hostile, with no reputation bar.
- **The debt (the pressure clock)**: you owe **Ma Gantry** of the Gantry Clan for your hull.
  - **1000 credits**, with a payment of **100 due every 8 jumps**, paid at any Scrapper station (Gantry Rusthold, or a `trader` node flagged clan).
  - Miss a payment and a "repo crew" event chain starts: Rustfang collectors (a pirate fight that also demands credits). Two misses in a row and the next pirate fight is a rammer that wants your ship back.
  - Pay it all off and Ma gives you a unique ("Ma's Kettle", a Scrap reactor with a quirk) and the flag `debt_free`. The debt is a cargo-independent number on the campaign.
- **Stations** (for now a menu; walkable stations come with on-foot play):
  - trade (buy fuel, sell items at half value, buy listed items from the station's stock in `data/drift.json`), pay the debt, repair hull integrity (2 credits per point), and recruit (2 recruits on offer, 150 credits each, species weighted by the station).
  - Gantry Rusthold sells Scrap-line parts, Meridian Standard-line parts, and the Prism Neon-line parts.
- **After a won fight**: loot is credits 20–60 × tier, scrap 30–80 × tier, and a 25% chance of one of the enemy's components. Then a `wreck_field`-style salvage event runs (boarding the wreck on foot comes later).
- **Conventions the content uses** (as built):
  - **Event types** are the node types plus `debt` (picked by the debt clock from `requires`: the first call after jump 2, reminders when a payment is due within 2 jumps, repo talk after a miss) and `station` (one weighted greeting per docking, gated by the `at_rusthold` / `at_meridian` / `at_prism` flags that are set while docked).
  - **Follow-up pages** have `weight: 0` and are reached only by `goto`. `after_win` is an event-level `{text, effects}`.
  - **`once` events** are spent only when the chosen outcome has non-empty effects, so walking away doesn't burn a quest step.
  - **Effects**: `log` (hands over a derelict log; kept once in `logs_found`), and `reveal` with a node type (reveals the nearest unrevealed node of that type). `lose_crew` is an int.
  - **Requires**: `fuel_max` (true when fuel ≤ N). `pay` on a choice charges what its `requires` named.
  - **Hull integrity** is a campaign number, repaired at stations. Events and drift jumps never take the last point.
  - **Losing a fight ends the run** (a new campaign starts).
- **Controls**: **M** opens the map from play mode. Click a linked node to jump; the event panel opens on arrival. Esc closes the map.
- **Saves**: the campaign (seed, node positions, lanes and types, the current node, visited nodes, flags, reputation, debt, jump counter, and `once` events used) is saved with the ship. Bump the save version.

## 9. Species in play (lead, 2026-10-30)
`data/species.json`. A crew member's `species` sets their body, their traits and their art rig (`art/crew/<species>/`).

| species | hp | speed | traits | other |
|---|---|---|---|---|
| human | 100 | 1.0 | — | — |
| basalt | 140 | 0.75 | `no_breath` (no damage from no air) | heals others at ×0.5 (bad medics); rig `basalt`, no helmet |
| emberkin | 90 | 1.0 | `heat_resistant` (fire damage ×0.25, can stand in overheated rooms) | — |
| fenn | 75 | 1.15 | `fast_repair` (repair and breach-patch time ×0.6) | — |
- Traits from species merge with personal traits (`crew.json` `traits`) and with gear (`suit` from an EVA suit). The existing `abilities.meets()` sees all of them.
- **Hand weapons** live in `data/hand_weapons.json`: id, name, culture (concord, clans, lumen, basalt, emberkin, fenn), class (pistol, rifle, heavy, melee, tool), damage, rate, range, and the art id.
  - They're used for on-foot fights later. For now crew carry their culture's sidearm: drawn when idle in combat, holstered at work.
- **Starting crews** (in each starter design's `crew` list):
  - Rustbucket: the Soldier, Ada (human), **Rook (basalt, the afterburner operator)**, and Juno (fenn).
  - Courier: the Soldier, Ada, and **Bram (basalt, the afterburner operator)**.
  - Prism: the Soldier, **Tess (emberkin)**, Quill (fenn), and **Wren (basalt, the afterburner operator)**.
  - Every ship carrying an Afterburner has a `no_breath` or suited operator.
  - The pirate raider's crew: 2 humans and 1 basalt.

## 10. Mining and cutting: a reliable way to earn materials (owner, 2026-10-30)
Fights, raids and quests pay well but unreliably. **Mining is the steady job**: if you badly need 10 more scrap, you take a mining run. It's dangerous but straightforward, and **the right equipment and tactics decide the yield**.

- **It's a mini-game in the combat arena.** No new physics: an asteroid is a "ship" made of rock cells, so cutting, hp, debris and collisions reuse the combat and ramming code (4, 4b, 4e).
  - **Rock cells** (`data/tiles.json`, `rock_*`): `rock` (hp 6, nothing inside), and ore veins:
    - `ore_iron` → scrap ×3;
    - `ore_copper` → copper ×2;
    - `ore_titanium` → titanium ×2;
    - `ore_silicate` → silicon ×2;
    - `ore_crystal` (rare, mostly near Dead Gates) → crystal ×1;
    - `ice` → restores O2 (refills every room 10% when collected).
  - **`gas_pocket`**: **explodes when cut** (splash 4, sets fires if the explosion reaches you). This is the main hazard to read and avoid.
  - Asteroids are generated from a seed: a blob of 60–400 cells, with veins as clusters and gas pockets. Bigger rocks spin slowly.
- **Cutting**: a destroyed ore cell drops a **chunk** (a small physical body carrying its yield). Destroyed plain rock drops nothing.
  - When a cut leaves a part of the asteroid disconnected, it **breaks off as its own rock** and drifts away (flood fill over the rock cells).
  - Breaking big rocks apart is how you reach the inner veins. The pieces keep their momentum, so **they can hit you** (ramming damage applies).
- **Collecting**: fly into chunks with a **scoop**, or pull them in with a **tractor beam**. Chunks go into the **ore hold**.
  - The hold's base capacity is 20 units; each `ore_hold` part adds 30. When it's full, extra chunks bounce off.
  - Raw ore isn't a material yet. **Refining** turns it into materials:
    - aboard, with a **refinery** (1 unit per 4 s while powered, then into cargo);
    - or at a station, for a fee (5 credits per unit, the station keeps 20%).
- **Dangers** (straightforward but real):
  - drifting and spinning rocks (collision damage, worst for fast or unarmoured ships);
  - gas pockets;
  - the heat from long cuts (mining lasers run hot);
  - **instability**: every field has a stability timer (3–6 min). After it runs out, rocks start breaking up and accelerating ("the field is shifting"), so leave or risk it;
  - **claim jumpers**: a chance (rising with time spent) that a pirate arrives mid-run.
  - You can leave at any time unless an enemy is near: Esc, the same rule as combat.
- **Equipment** (each line has its own take; normal parts with recipes, using the hull-mount format):

  | part | line | what it does |
  |---|---|---|
  | Mining Laser Mk1–Mk3 | standard | fixed, hitscan, ×4 damage to rock, ×0.25 to ship armour; heat 2× a laser's |
  | Bore Drill | scrap | a bow mount: **ram to mine**, ×5 rock damage on ram contact, no power; a ram build's mining tool |
  | Lumen Cutter | neon | a beam, ×6 to `ore_crystal`, cuts gas pockets without igniting them (×0.5 chance) |
  | Ore Scoop | scrap | a bow outside half: collects chunks you touch; no power |
  | Tractor Beam Mk1–Mk2 | standard | a turret mount: holding Q pulls chunks within 300/450 px to the ship |
  | Ore Hold | any | inside 2×2: +30 ore capacity |
  | Refinery Mk1–Mk2 | standard | inside 4×4, power −2: refines 1 unit per 4 s (Mk2 per 2 s); a workshop module raises it a level |
  | Survey Scanner | standard | utility: shows veins and gas pockets inside rocks (otherwise only exposed cells show) |
  - Ordinary weapons mine too, badly (×1 to rock), so any ship can scrape by. Proper gear makes it fast and safe.
- **The Drift**:
  - **`asteroid_field` nodes** (weight 14) and **mining contracts** at stations ("the Clan needs 40 copper ore by jump 20").
  - Fields roll a richness (poor, rich, motherlode) and a danger tier. Crystal fields sit near Dead Gates and are Warden-guarded.
  - Before the mini-game exists, `asteroid_field` events offer a text version: surface mining (safe, small yield) or deep cracking (risky, bigger yield, hull damage chance).
- **The same mini-game later salvages wrecks** (the "hullscrapper" fantasy): cut a dead ship apart and its components drop as chunks to scoop (`wreck` cells instead of ore). One mechanic, two content streams.

## 11. Sector space: Raft in space (owner, 2026-10-30; this is the core loop)
> "More Raft-like: shoot resources that float around space, build collection chambers to get a steady gain of resources. A radar or beacon shows where the big events are, and you set your course there. When you're done with a place, you light-speed to another. Every place has a few notable areas: mining, quests, unknown ships, a store, an abandoned station, a distress beacon."

**Two scales**:
- **The Drift map** (section 8) is the **macro** layer: places linked by lanes. Moving between them is a **light-speed jump** (fuel, a spool-up).
- Each place is a **sector**: an open, real-time region of space you **fly through**. The ship is centred, space and debris drift past (like Raft), and the crew live and work inside while you travel.
- **Combat, mining, salvage and events all happen in the sector.** The combat arena becomes sector space, with no separate screen.

### The sector
- **Generated from the node's seed and type**: a region about 24,000 × 24,000 px.
  - A **current**: a direction and speed (20–60 px/s) that debris drifts along. The Drift literally drifts.
  - A **debris density**, with the theme set by the node type: wreck fields are dense with salvage, asteroid fields with rock, empty sectors sparse.
  - **2–6 points of interest (POIs)**, placed 3,000–12,000 px from where you arrive.
- **POI types**:
  - station or store, trader, distress beacon, wreck, abandoned station, mining field;
  - unknown ship (could be a trader, a pirate, refugees or a derelict);
  - pirate nest, Concord checkpoint, anomaly, quest site.
  - The node type sets the mix: a `pirate` node has a nest plus a wreck or two; a `trader` node has a store plus a mining field; and so on (`data/sectors.json`).
- **Approaching a POI** (within 800 px) runs **its event** (section 8's event system, unchanged). A `fight` effect spawns the enemy ship physically in the sector, near the POI. A store opens the station menu.
  - POIs remember what's done. **The sector panel lists them, and when you've done what you want, you jump.**
- **Ambient encounters**: while you're in a sector, a roll every ~90 s can spawn a passing ship (trader, patrol, pirate) at the radar's edge, which comes to you or passes by.

### Drifting resources, the Raft loop
- **Debris spawns continuously upstream of the ship**, in a ring 1,500–3,000 px out, drifts along the current, and despawns when far behind.
- **Types** (`data/debris.json`, content):
  - scrap chunk (scrap 2–5), copper coil (copper 1–3), polymer barrel (polymer 2), ice chunk (refills O2 10%);
  - sealed crate (shoot it open: 1–2 random items or materials);
  - an ore rock (shoot it to break it into chunks, the mining rules in section 10);
  - a dead drone (salvage: a chance of a component);
  - a fuel canister (fuel 1, rare).
- **Collecting**: **Salvage Intakes**, the "collection chambers".
  - An intake is a **hull mount** (section 4f) whose outside half is an open mouth with a magnetic net, and whose inside half is a sorting hopper that feeds cargo.
  - Debris that **touches the mouth**, or comes within its **pull radius**, is drawn in and lands in cargo, up to the ore and hold capacity of section 10.
  - Debris that hits plain hull just bounces (a scratch, if fast).
  - So **where you put intakes, and how you fly into the current, decides your income.** Bow intakes catch what you fly into; side intakes catch the current as you drift.

  | part | line | mouth | pull radius | notes |
  |---|---|---|---|---|
  | Net Mouth | scrap | 2×2 out / 2×2 in | 1 cell | no power; jams sometimes (reliability) |
  | Salvage Intake Mk1–Mk3 | standard | 4×2 out / 4×2 in | 2 / 3 / 4 cells | power −1 / −1 / −2 |
  | Lumen Siphon | neon | 4×2 out / 4×2 in | 6 cells | power −3; pulls only small debris |
  | Tractor Beam Mk1–Mk2 | standard | turret | 300 / 450 px | **Q** held: pulls debris toward the nearest intake (section 10) |
- **Shooting debris**: any weapon breaks a crate or rock into chunks. Mining lasers do it well (section 10).
- **The target income**: idle drifting with one Mk1 intake brings ~15–25 scrap a minute plus a bit of copper and polymer. Actively chasing debris and breaking crates doubles that. Big hauls come from POIs (wrecks, mining fields, quests).
  - This is the steady, reliable income the owner asked for. Fights and quests are the jackpots.

### Materials by rarity and region (owner, 2026-10-30)
> "Basic materials can float around, but key upgrade materials or rare ones are only found through fighting, special mining or questing. Different regions have different core materials floating around, and quest items are found too."

- **Common** (they float everywhere; the Raft loop): scrap, copper, polymer, ice.
- **Regional** (they float only in their region's sectors, and are bought dearly elsewhere):
  - **titanium**: Concord space around Meridian, and wreck fields;
  - **silicon**: asteroid regions;
  - **crystal shards**: Lumen space around the Prism, and the Dead Gate approaches (small amounts);
  - **plasma cells**: rare canisters near anomalies.
- **Key materials** (**never float**; Mk4/Mk5 parts and uniques need them):
  - `military_circuit`: from wrecked Concord patrols, Enforcers and pirate captains (fight loot);
  - `gate_alloy`: from Dead Gate POIs and Warden drones;
  - `void_crystal`: only from **motherlode** mining fields (special mining POIs, guarded or unstable);
  - `nanite_paste` (exists): from wreck medbays, abandoned stations and quests.
- **Quest items** (`kind: "quest"` in `items.json`): story objects found at POIs and given by events, such as Ma's ledger, the buoy's recording or Skarn's hat.
  - Events `require` and consume them; they can't be sold, and they show in their own cargo section.
- **Regions of the Drift**: every map node belongs to a region by its nearest landmark:
  - **Clan space** (Rusthold): scrap-rich, Rustfangs;
  - **Concord space** (Meridian): titanium, patrols;
  - **Lumen space** (the Prism): crystal, Wardens;
  - **the Boneyard**: dense wrecks, salvage, scavengers;
  - **Gate approaches** (the Dead Gates): crystal, gate alloy, the Hollow.

  The region sets each sector's debris table (`data/debris.json` per region), the enemy mix and its stores' stock. The map tints regions faintly.
- **Recipes gate tiers this way**: Mk1–Mk3 need common and regional materials; **Mk4 needs a key material, and Mk5 needs two**. So the best parts come from fighting, special mining and questing, never from drifting alone.

### Radar and beacons
- **What you can see**:
  - `beacon` POIs (stations, stores, traders, distress beacons, quest markers) **broadcast**: you always know their bearing, from anywhere in the sector.
  - `signal` POIs (wrecks, abandoned stations, mining fields, unknown ships) need a **radar** within its range.
  - `hidden` ones (ambushes, a ship running dark) show only within visual range (1,500 px) or to a Mk3 radar.
- **Radar** (a hull mount: an inside console plus an outside dish that turns):
  - Mk1: range 6,000 px, shows "contact" and the bearing.
  - Mk2: 10,000 px, and **identifies the type**.
  - Mk3: 16,000 px, sees hidden contacts.
  - Scrap "Listening Horn": 5,000 px, cheap, no power. Neon "Lumen Eye": 14,000 px; identifies; ion-weak.
  - Without a radar you see only beacons and what's in visual range.
- **HUD**:
  - A **compass ring** around the ship and **edge markers** for known contacts: an icon, the distance, and the type once identified.
  - Debris shows on the ring as faint dots within 2,000 px.
  - **Click a marker to set a course.**

### Flying and the helm
- **The ship moves when the helm is manned.** With a course set, a crew member at the helm **steers there on autopilot**: it rotates toward the course, thrusts, slows on arrival, and avoids rocks.
- **The player can take the helm** (E at the helm) and fly by hand with the flight controls of section 4. **E again** hands the helm back to the autopilot.
- With nobody at the helm, the ship drifts with the current (and still collects debris).
- So you can walk around inside, fight fires, man a gun or build while the ship travels, which is Raft's core feeling.
- **Combat while walking**: fixed guns fire only when someone aims them. The pilot at the helm aims the bow guns; a crew member at a weapon station fires at the nearest hostile within the gun's arc (with the AI's aim skill). Turrets fire on their own.

### Light speed (leaving)
- **M** opens the Drift map. Pick a linked place and the jump drive spools for **8 s**: a visible charge, and you can keep flying.
- **It's blocked while a hostile ship is within 2,000 px** ("hostiles too close to jump"). Fuel is spent when it fires, as section 8 says (including `fuel_mult`).
- Arriving puts you at the sector's arrival point. Sectors you've visited remember their POIs.

### What changes in sections 8 and 10
- A Drift **node's type is now its sector's theme**: it sets the POI mix and the debris density. Its events run at the matching POIs, not on arrival.
- The debt clock, reputation, stations, loot and saves stay the same.
- **Mining** happens at mining-field POIs and on the ore rocks drifting by, with the same cutting rules, in the same space.

### Order (each step is a brief)
1. **Sector core** (logic, headless tests):
   - sector generation from a node;
   - the debris spawner and bodies, intakes and collecting, breaking debris;
   - radar visibility rules;
   - the autopilot to a course;
   - the jump spool;
   - POI triggering into events;
   - fights spawned in place.

   It builds on the arena after the mounts and shields v2 merges.
2. **Sector view**: the ship-centred interior while flying, parallax space, debris sprites, the compass ring and edge markers, click to set a course, zooming from interior to flight view, and combat inside the sector.
3. **Content**: intakes, radars and debris data with art (drift pieces, intake mouths, radar dishes), POI types in `data/sectors.json`, and writer passes for POI events.
4. **On foot** at POIs (docking, abandoned stations, boarding), later, as PLAN says.
