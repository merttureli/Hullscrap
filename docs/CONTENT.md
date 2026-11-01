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
- Every part explains itself on the build card and in the crafting panel (`scripts/ui/describe.gd`): what its family does, its stats (read from the part's `stats`, `data/weapons.json`, `data/flight.json` and the shield timing, never copied), what its weapon kind, damage type, traits and effects mean, then its `blurb` as the lore. The words live in `data/describe.json`: a new family, weapon kind, damage type, effect key or `stats` key needs a line there (`tests/test_describe.gd` fails without it). A part needs a `blurb` in the same dry voice (`docs/LORE.md`).
- The build palette lists a part only when one is held or its blueprint is known; the crafting panel lists every recipe (unknown ones dimmed), except those of a `unique` or `relic` part and racial tech (`tech_*` packs) until the blueprint is learned.

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
- **Ion vulnerability is real** (`Abilities.ion_lock`, `Shields.absorb`): an ion hit on a part shuts it down (no power made or used, crew cannot repair it, it wears off) for 3 s times its line's `ion_vulnerability`, and an ion hit on the shield bubble strips that many layers (1 times the layers-weighted mean `ion_vulnerability` of the powered shield parts) and locks the bubble 3 s times it. A neon part therefore stays down 6 s and a neon shield loses 2 layers per ion hit and is locked for 6 s. The Prismatic Lattice Shield ("ion strips 2") and Song Reactor ("ion shuts it down twice as long") are this rule, with no key of their own.

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
  - **W/S** thrust and reverse. **A/D strafe** sideways, using engines mounted on the side walls (thrust × the sideways component of their push) plus `side_share` (data/flight.json, 30%) of every engine's thrust, so rear engines alone strafe weakly and side engines stay much better.
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
  - **Rapid guns** (`"rapid": true`, Beta 3 pacing): the only guns that fire a shot or more a second (`shots` / `cooldown` >= 1; a flak volley's pellets count as one shot). They are all turrets with 1 damage a shot and a 0.4 to 0.8 s cooldown: Rattle Burst and the Concord Point Turret (tier 1), Twitch Cannon, Drone Picket and Glimmer Turret (tier 2), Sovereign Turret (tier 3, the best tracking and accuracy). 10 to 15% of the player's guns are rapid (tests/test_weapons.gd); every other gun is slower and heavier (lasers, bolts and flak: cooldown x1.75, damage x1.5; beams: cooldown x1.75, damage x1.5; missiles: cooldown x1.4, damage x1.25). Each shot uses up a whole shield layer, so a rapid turret strips shields while missiles (which pass them) are aimed by hand.
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
  - **Layers are per sector**: a hit spends a layer of the sector it hits, and each sector recharges its own, one layer at a time (7 s a layer for a Mk1, `shields.recharge` in data/weapons.json; the next layer's timer starts when the one before it is back), and a sector whose last whole layer was used waits 3 s more (`shields.break_delay`).
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
- **Start with very little (owner, 2026-10-30, Beta 1 feedback)**: starters are **big frames with only the essentials built** (reactor, helm, 1–2 engines, 1–2 guns, O2, one bed, fabricator). Half or more of the frame is empty, to build in. The starting cargo carries materials and a few parts. Creativity is the point: the player builds the ship they want.
  - **Lean loadout (playtest 2, P3)**: then exactly one of a **shield** (about half the starters, which have one gun), a **medbay** (about half, one or two guns) or **neither** (at most four, which have two guns, the second a turret on a flank). No spare shield or medbay in the hold, 250 scrap. Where a racial reactor could not power that, the standard Reactor Mk2 is built and the racial one waits in the hold.
  - **Bigger frames (P4)**: each starter's frame was grown by about 15% of its area; the built core is the same, so the extra is empty hull. `tests/tool_make_starters.gd` (`FRAME_GROWTH`) does it and checks power, reach and the loadout; `tests/tool_make_starters2.gd` builds the pack's ships from the same rules.
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
    - **Three Dead Gates** sit on the far edges (`gate` nodes; "the gate is dark" everywhere but in the ending region, where their shells can be approached: section 13).
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
  - `requires` on an event: `jumps_min`, `jumps_max`, `flag`, `not_flag`, `rep_min`/`rep_max` per faction, `node` (a node type), `crew_min`/`crew_max`.
  - `requires` on a choice: any of those, plus `species`, `trait`, `items` (you must hold them; they're paid only if `pay` is set), `component` (installed), and `credits`.
    - **`crew_min` / `crew_max`** (event or choice) count the crew aboard **besides the soldier** (drones will not count). `crew_max: 0` is the alone version of a text, `crew_min: 1` the one that sends someone. Write the body text so it works alone ("you", "the ship"), and put the crew-only lines in crew-gated choices.
    - **`species` and `component` take an id or a list: any one of them is enough.** `species_any` and `component_any` mean the same (a list is read the same way) and can sit beside the plain key, which must then hold too. A blue choice shows the parts it found aboard in its brackets (`[Shield Mk1]`), so write `[Shield]` yourself when a list would be long. Any shield is `component_any` of the `shield_*` family ids (`shield_mk1`, `shield_mk2`, `shield_scrap_mk1`, `shield_neon_mk1`...), any radar `radar_mk1`/`radar_mk2`/`radar_mk3`; parts of the packs (strafe jets) are known to the validator too.
  - **One free crew offer a region**: `data/drift.json` `crew.offers_per_region` (1) limits the events that add crew (a recruit effect) that fire in a region (`Campaign.crew_offers`, saved from save version 9, zero again on `enter_region`). Once it is spent those events are out of the pool until the next region. Free of the limit: Ada's pod and the packs in `crew.offers_exempt_packs` (the story's: `story_1`, `endings_1`, `start_alone`).
    - A choice whose `requires` names a species, trait or component is a **blue option**: shown in cyan, with its reason in brackets.
    - A choice whose requirements aren't met is hidden. One that only lacks items or credits shows greyed out, with what it needs.
  - **Effects**:
    - `items` (+/−, including `credits`, `fuel`, materials and components), `rep` {clans, concord, lumen}, `crew_hp` (everyone, +/−), `hull` (integrity +/−), `flag` / `clear_flag`;
    - `recruit` {name?, species}, `lose_crew` (a random non-player), `blueprint` (an id);
    - `fight` (a ship design id, `"tier"` to roll from the node's table, or `"gen:<faction>"` to meet a faction of the enemy tables, e.g. a rare one: `Campaign.foe_of` rolls it once per node and keeps it), `goto` (another event id: a follow-up page), `reveal` (a node or station id), `debt` (+/−).
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
| kett | 80 | 1.0 | `swarm` (work +25% per other Kett in the room, at most +50%) | pack `races_1`; rivet gun |
| mire | 100 | 1.0 | `firefighter` (extinguish ×2, fire damage ×0.5), `dries_out` (−2 hp/s in a room whose hottest part is above 60) | pack `races_1`; service pistol |
| sporeling | 100 | 0.8 | `aura_spores` (their room gains 0.5 air/s each, about a room's worth of what a Bloom Reactor and a Spore Cannon eat: see section 17, and heals everyone 1 hp/s), `flammable` (fire damage ×1.5) | pack `races_1`; flare gun |
| gauntling | 100 | 1.0 | `mechanical` (beds do not heal; a crewmate's `repair_crew` job does), `half_lungs` (air ×0.5), `ion_prone` (stunned 3 s by ion), `tinkerer` (repair time ×0.8) | pack `races_1`; multi-tool |
| prismatic | 100 | 1.0 | `crystal_conduit` (+1 power to the system they man), `crystal_body` (ion damage ×2, melee ×0.5) | pack `races_1`; Gatekeeper's lance |
| grundl | 180 | 0.7 | `hauler` (restock ×2, melee ×2), `clumsy` (repair time ×1.3) | pack `races_1`; quarry hammer; the large rig over the normal 2×2 body |
| vellum | 50 | 1.2 | `folded` (`body` 1: walks 1-wide crawlspaces), `paper_skin` (fire damage ×2) | pack `races_2`; spark pistol; the small rig (art fits 1 cell); homeland `vellum_stacks` |
| oorth | 100 | 1.0 | `third_eye` (`reveal_enemy`: the enemy schematic shows its crew while one is aboard and up), `gentle_hands` (melee ×0.5) | pack `races_2`; service pistol; homeland `oorth_quietude` |
| drakkin | 120 | 1.0 | `pit_fighter` (melee ×1.75), `cold_blooded` (`heat_speed`: ×0.7 in a room whose heat is under 20, ×1.2 over 50) | pack `races_2`; quarry hammer; the large rig over the normal 2×2 body; homeland `drakkin_pits` |
| wisp | 100 | 1.0 | `living_current` (`vacuum_walk`, `o2_use` 0), `handless` (`no_tools`: no repair or extinguish jobs), `console_ghost` (manned bonuses ×1.5), `ion_kin` (ion damage ×2) | pack `races_2`; no sidearm; the floating rig; homeland `wisp_stormfield` |
| hullkin | 100 | 0.5 | `hull_mender` (`hull_mend`: idle, repairs the walls beside them 1 hp/s and seals a breach in 12 s), `shell_breather` (`o2_use` 0.5) | pack `races_2`; multi-tool; homeland `hullkin_reefs` |
| lantern | 80 | 1.3 | `born_pilot` (+0.05 evasion while they man the helm) | pack `races_2`; carbine; the floating rig when gliding; homeland `lantern_lanes` |
| revenant | 110 | 1.0 | `returned` (`o2_use` 0, `revive_once`: the first downing, back up after a while), `stitched` (bed heal x0, medbay x0.5) | pack `races_3`; rivet gun; homeland `revenant_cairns` (stages 5-8, rare); joins through events |
| choir | 100 | 1.0 | `choral_voice` (`aura` work x1.15 for the others in their room), `hollow_body` (melee x0.3) | pack `races_3`; no sidearm; homeland `choir_chantry`; recruited at the Prism |
| rattler | 60 | 1.0 | `gremlin` (`body` 1), `scrap_sense` (`line_affinity` scrap: work x2) | pack `races_3`; multi-tool; the small rig; homeland `rattler_walls`; recruited at Rusthold |
| tessellate | 100 | 1.0 | `many_bodies` (`o2_use` 0, `split_on_death`: two small 1x1 bodies that reform), `circuit_kin` (ion damage x2) | pack `races_3`; spark pistol; homeland `tessellate_mend`; art also has the `tessellate_half` rig; joins through events |
| sable | 90 | 1.0 | `cutter_torches` (breach work x2), `boarders_eye` (ranged x1.25) | pack `races_3`; carbine; homeland `sable_moorings`; joins through events |
| quillback | 110 | 1.0 | `quill_coat` (`counter_melee` 10), `proud_back` (`no_suit`) | pack `races_3`; ember knife; homeland `quillback_lists`; recruited at Rusthold |
| kite | 90 | 1.0 | `drift_born` (suffocate damage x0.5), `tail_grip` (`vacuum_speed` x1.5 in a room under 30% air) | pack `races_3`; flare gun; homeland `kite_slack`; joins through events |
| warden_frame | 100 | 1.0 | `rebuilt_drone` (`mechanical`, `o2_use` 0), `gatekeeper_optics` (ranged x1.5, ion damage x3) | pack `races_4`; Gatekeeper's lance; no homeland: joins only through the quest chain `warden_dark_lens` > `warden_cold_start` > `warden_first_light` (stage 4+, a landmark) |
| murrow | 120 | 0.9 | `digger` (`mining_mult` 1.5) | pack `races_4`; quarry hammer; the large rig over the normal 2x2 body; homeland `murrow_diggings` (stages 3-7); joins at asteroid fields |
| siltborn | 100 | 1.0 | `gas_floater` (`o2_use` 0.5, fire damage x2), `thin_air_bloom` (`low_pressure_heal` 1 hp/s in a room under 50% air) | pack `races_4`; no sidearm; the floating rig; homeland `siltborn_rings` (stages 4-8); joins at anomalies |
| corvin | 100 | 1.0 | `glint_eye` (`haggler` 0.1: station prices -10%), `pocketed` (`loot_bonus` 1: one more roll on wreck, salvage and loot tables) | pack `races_4`; service pistol; homeland `corvin_roost` (stages 2-7); joins at trader nodes |
| brine | 100 | 0.85 | `carapace` (melee and ranged damage taken x0.7), `dock_hauler` (restock x1.5), `shell_back` (`no_suit`) | pack `races_4`; rivet gun; the large rig over the normal 2x2 body; homeland `brine_yards` (stages 2-6); recruited at Meridian |
| echo | 100 | 1.0 | `mirror_skin` (`mimic`: copies the best non-body trait of another crew member in the room, while there) | pack `races_4`; spark pistol; homeland `echo_glassways` (stages 5-8, rare); joins at anomalies |
| ferro | 100 | 1.0 | `ferrofluid` (ion damage x0, `hull_mend` 0.5), `magnet_hands` (`station.pull_bonus` 1: the salvage intake they man pulls 1 cell further) | pack `races_4`; multi-tool; homeland `ferro_lodes` (stages 4-8); joins at wreck fields |
- **Traits are a library** (`data/traits.json`, plus the `traits.json` of every pack): each is a bag of generic keys that `scripts/crew/traits.gd` (`TraitSet.of(member)`) merges into numbers, and every rule a key changes reads them there, so a new race is data only. The keys and what they do are in `data/traits.json` `_doc`; a species entry may also carry keys inline (Basalt's `work_mult.heal_others`).
  - Work speeds are factors on speed (2 = twice as fast); a race spec's repair "×0.8" is a time factor (as Fenn's ×0.6), so its work speed is 1 / 0.8.
  - Room heat is the heat of the hottest part in the room (`Heat.room_heat`).
  - An ion hit costs each crew member in the room it lands in `ion_hp` (`data/crew.json`) per point of damage, times their `damage_taken.ion`, and stuns them for `ion_stun` seconds.
- Traits from species merge with personal traits (`crew.json` `traits`) and with gear (`suit` from an EVA suit). The existing `abilities.meets()` sees all of them.
- **Hand weapons** live in `data/hand_weapons.json`: id, name, culture (concord, clans, lumen, basalt, emberkin, fenn), class (pistol, rifle, heavy, melee, tool), damage, rate, range, and the art id.
  - They're used for on-foot fights later. For now crew carry their culture's sidearm: drawn when idle in combat, holstered at work.
- **Starting crews** (in each starter design's `crew` list): **the Soldier alone** (playtest 2, A1), on every starter, the packs' too; the soldier's species comes from the hangar choice.
  - **Ada** is the likely first crewmate: the `ada_pod` distress event (`data/packs/start_alone`) in stages 1-2, once per run, free, no bed needed. Her name and colours are `data/crew.json` `ada`. About 70% of runs meet her by the end of stage 2 (`tests/tool_crew_rate.gd` measures it).
  - **Crew are rare (A2)**: `data/drift.json` `crew` gates the events that add crew (`species_event`, `station_event`, `unique_event`: the chance an eligible one is in the pool at all), hiring costs 450 credits (`prices.recruit`) and a station has anyone to hire only `prices.recruit_chance` of its visits. The aim: about one more crewmate per 2-3 regions, 2-4 besides Ada by stage 8.
  - The pirate raider's crew: 2 humans and 1 basalt.
- **The repair drone** (playtest 2, R1; species `drone`, `drone: true`): a small hovering robot that is not crew and that the player never controls. Every run starts with one (`RunStart.add_drone`, from the hangar's `apply_ship`: not in the starter files), and the fabricator recipe `repair_drone` (scrap 60, copper 20, polymer 10; the blueprint is not known at the start) or a station that stocks it (`meridian`) adds more, at once, beside the fabricator (`Jobs.launch_drones`). The blueprint comes from a wreck's salvage: `drift.json` `loot.drone_scan` is the chance of a "Scan the service drone bay" row (`Salvage.drone_scan`).
  - 60 hp, a 1x1 body, `mechanical`, needs no air, fire x0.25, no bed or medbay; its work speed is 0.6 (repair, breach, extinguish, restock). It is drawn in code (`PersonDrawer.draw_drone`): there is no `art/crew/drone`.
  - **Jobs**: only `crew.json` `drone_jobs` (extinguish, repair_breach, repair_component, repair_belt, restock, clear_wreck), checked in `Jobs._pick`. Never a station, a revive, the mending of a crewmate, an order (middle click, F) or an ability; it cannot be selected.
  - **Power**: each working drone draws `crew.json` `drone.power` (1) from the ship's surplus, with no cable (`Power.feed_drones`, called by `Ship.refresh` after the solve): the parts on the cables are fed first and the drones take what is left, in name order. A drone the surplus does not cover stands still, takes no job and says "no power" (crew bar, label). The top bar's demand includes every working drone. A ship needs 1 power to spare per drone.
  - **Broken, not dead**: at 0 hp it lies where it fell, does nothing and never bleeds out (`Mortality`); it gets the `repair_crew` job (a crewmate, or the soldier holding E, mends it) and works again above 0 hp. The crew save keeps it, broken included.
  - **Not crew**: it is left out of beds and the crew bonuses of parts (`PartEffects`, `Effects.crew_in_room`), `Campaign.lose_crew`, the end screen's crew, the run's crew count and the hall-of-ships design (`CrewMember.is_drone()`). Enemies never have one.

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
  | Net Mouth | scrap | 2×2 out / 2×2 in | 2 cells | no power; jams sometimes (reliability) |
  | Salvage Intake Mk1–Mk3 | standard | 4×2 out / 4×2 in | 3 / 4 / 5 cells | power −1 / −1 / −2 |
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

**Step 3 notes (the Raft content, `claude/sector3`)**:
- Salvage Intake Mk2/Mk3, Radar Mk1-Mk3 and Tractor Beam Mk1-Mk2 are in `data/components.json` (recipes in `data/recipes.json`: blueprints, not known at the start; Meridian sells them at the tier price rule). Radar stats: `radar_range`, `identify` (Mk2+: names what it sees and rates a fighter's threat in skulls), `see_hidden` (Mk3). Tractor stats: `tractor_range` (300 / 450 px) and `tractor_pull` (px/s); **Q held** in play mode only (Q is the utility key in a fight). Power numbers (radar -1/-2/-3, tractor -2/-3) are the builder's, not in the tables above.
- The income target is measured, not assumed (`tests/test_sector3.gd`): `data/debris.json` spawns one piece every 1.4 s and scatters 80% of them over the whole view (the old 0.6 s and 35% made an idle Mk1 earn about 70 a minute), which gives about 15-25 scrap a minute idle with a Mk1 and about double with a Mk3 and a chase.
- `quest` POIs are only made in a region with a quest event (`Sector.has_quest`: `requires.region`, or the flag `in_<id>` the homeland tech quests use); the node tables carry a `quest` weight of 3-4, about a third to a half of a homeland's sectors have one.
- Not built (art exists): Listening Horn (scrap radar), Lumen Eye (neon radar), Lumen Siphon (neon intake, small debris only). They need a design call on their numbers.

## 12. Processing: smelters and the material ladder (owner, 2026-10-30)
> "Put smelters in the ship to smelt bad materials into better ones: smelt scrap (an early-game material with no late-game use) into forged steel armour or something."

- **Scrap never becomes useless**: it's the feedstock of **steel**, and steel is what mid and late parts and armour are made of.
- **Processing parts** (inside components, crew-operated; manned works 30% faster):
  - **Smelter** (a Scrap "Slag Pot", Standard Mk1–Mk3, a Neon "Plasma Forge"). It runs hot (heat_per_s 8 and up), so Emberkin love working it, and give it a radiator.
  - **Refinery** (section 10): ore into materials.
  - Later, a **Fuel Cracker**: ice plus a plasma cell into fuel, slowly. Fuel stays scarce, so it is slow and expensive.
- **The ladder** (`data/processing.json`, recipe-like: inputs → output, seconds, the minimum processing level):

  | output | inputs | time | level | used for |
  |---|---|---|---|---|
  | `steel` | scrap ×4 | 6 s | Smelter Mk1 | Forged Steel Plate (a wall material: hp 8, kinetic resist 0.3); every Mk3+ recipe uses steel where Mk1 and Mk2 used raw scrap |
  | `alloy` | steel ×2, titanium ×1 | 10 s | Smelter Mk2 | Alloy Armour (hp 10, all-round resist 0.2); Mk4+ hulls and housings |
  | `conductor` | copper ×3, silicon ×1 | 8 s | Smelter Mk2 | Mk3+ power, shields and weapon capacitors |
  | `glass_lattice` | silicon ×2, crystal ×1 | 12 s | Plasma Forge | Neon parts Mk2+, reflective coatings |
  | `fuel` | ice ×10, plasma_cell ×1 | 60 s | Fuel Cracker | emergency fuel |
- Processing **queues like the fabricator** (`crafting.gd`'s queue model) and pulls from cargo. A conveyor network (4f) can feed it, and a smelter can sit next to an ore hold.
- **The early-to-late shape**:
  - early, you drift and collect scrap and build with raw scrap;
  - mid-game, you smelt steel and build the Mk3 parts and Forged Steel armour;
  - late, you need alloy and conductor plus the key materials of section 11 (fights, special mining, quests) for Mk4 and Mk5.
- Engine wave 1's Mk3+ recipes switch their scrap to steel (scrap 40 → steel 10) when processing lands.

**Built (`claude/smelters`, the pack `data/packs/processing_1`, `tests/test_processing.gd`)**:
- **Where it lives**: the ladder is not a `data/processing.json` but ordinary recipes with `"station": "smelter"` (default `"fabricator"`), so packs, the content validators and blueprints work unchanged; `fab_level` and `tools` are then the smelter's level and tools (a Plasma Forge gives the tool `plasma`). `Crafting` keeps one queue per station (`queue` is the fabricator's, `queue_of("smelter")` the smelter's; saved as the optional `queues`); `Processing.best(ship)` (`scripts/craft/processing.gd`) is to the smelter what `Workshop.best` is to the fabricator.
- **Parts**: Slag Pot (Scrap, level 1, x0.9), Smelter Mk1-3 (levels 1-3, speeds x1 / x1.3 / x1.6), Plasma Forge (Neon, level 2, x1.3, tool plasma). Stats: `smelt_level`, `smelt_speed` (the line's output multiplies it), `plasma`, `work_heat`. Heat is 8 / 8 / 10 / 12 / 8 (x1.5 for Neon) and only accrues while the smelter works (`heat.gd`); cooling 3, so one radiator (+6) holds a Mk1. The numbers (speeds, powers -3 to -5, part recipes, prices 280 / 500 / 380) are the builder's; the spec gives only the ladder.
- **Crew**: the family `smelter` is a manned station (`data/crew.json`): its post is on the job board only while the lead smelter has a queue, at priority 50 (out of a fight the other posts drop to 45); manned, the lead works `1 + manned.process_speed (0.3) x manned factor` as fast.
- **Armour**: Forged Steel Plate hp 8 / mass 3 / kinetic x0.7 and Alloy Armour hp 10 / mass 2.5 / kinetic, energy, explosive x0.8: the spec's "resist 0.3" and "all-round resist 0.2" are read as damage reduced by 30% and 20%.
- **Engine wave 1** is re-costed by `override` entries in the pack (every one raw-material neutral): Mk3+ scrap becomes steel (40 -> 10), Mk4+ steel + titanium becomes alloy, Neon Mk2+ silicon + crystal becomes glass lattice. Conductor has no consumer yet except the Smelter Mk3 (power, shield and weapon parts of Mk3+ do not exist yet); Reflective Coating still costs silicon + crystal.
- **Not built**: the Refinery (needs ore from section 10), the Fuel Cracker and the `fuel` rung (ice is not a cargo material), belts feeding a smelter, and art (the parts and the four materials are drawn by code placeholders).

## 13. The end: endings, and why to start again (owner, 2026-10-30)
> "We need an end goal so the game can end and give you a reason to restart with a new build: depending on the lore, finding an established civilisation that survived and is thriving (like I Am Legend), or multiple endings you can run into."

- **A run is 4–8 hours.** It has an ending, a score, and **unlocks** that change how the next run starts. The 200 hours come from replaying with different ships, crews and paths (FTL / Multiverse-style).
- **Pacing in acts and pressure clocks**:
  - **Act 1, Clan space**: Ma's debt clock (section 8) is the early pressure.
  - **Act 2, the Boneyard and Concord space**: the money is good, and the first fragments of **the Haven broadcast** turn up.
  - **Act 3, the Gate approaches**: **the Hollow tide** is the late pressure. From about jump 30, the Hollow spreads from the Dead Gates one node every few jumps. Hollow nodes have ghost ships, no stores and dead beacons, so you can't stall forever.
- **The endings** (each is a quest chain of events, flags and special POIs, and you can run into more than one in a run; the first one you **complete** ends the run):
  1. **The Haven** (the owner's idea, *I Am Legend*): a looping broadcast, "If you can hear this, we're alive. Come to the Lantern Reach", is heard in fragments (logs, radar ghosts, distress beacons).
     - Triangulate it with the radar across regions. Most fragments are real, and some are **Hollow lures**.
     - At the end of the trail is **Halcyon**, a generation ship that was mid-jump at the Snap. For forty years it has quietly **thrived** in a hidden pocket of the Drift: gardens, children, working gates of its own design.
     - You choose:
       - **settle** (the peace ending);
       - **lead others there** (bring Ma, the Concord or the Lumen, which needs reputation; the best Haven ending);
       - or find that they are not what they seem (a dark variant, if you followed a lure).
  2. **The Way Out**: restart a Dead Gate. That needs `gate_alloy`, a gate core from the Dead Gate dungeon, and a faction's backing. The faction decides the ending's tone:
     - **Concord** (the Lattice returns, with paperwork);
     - **Clans** (a free gate: chaos and freedom);
     - **Lumen** (the gate opens somewhere new).
  3. **The Hollow**: follow the hidden Hollow thread (the derelict logs) into the Scrapper Gate and learn what came out at the Snap. It is the hardest ending, the true-lore one, and changes the next run's map (Hollow nodes from the start, plus a Hollow-touched starter).
  4. **Retire** (the short ending): pay off Ma, then buy a berth at Gantry Rusthold (5,000 credits) and hang up your helmet. It has a low score but it counts, and it's good for short sessions.
- **Landmark events don't end the run (owner, 2026-10-30)**. Only endings end a run. Big story moments along the way are **landmarks**: one-off events (`"landmark": true`) that pay out **in the run** (a unique part, a named recruit, a blueprint, a key material, a reputation jump) **and unlock something for future runs**. Then you keep going.
  - Examples:
    - catching the first clean Haven fragment;
    - meeting Ma Gantry in person;
    - boarding the Concord flagship *CS-001 Patience*;
    - standing inside a Dead Gate's shell;
    - the Lumen showing you the first gate study;
    - surviving a Hollow tide node.
  - A new effect, **`unlock`** (an unlock id from `data/unlocks.json`), is recorded in the profile, not the run, and shown as "Unlocked: ..." on the event and the ending screen.
  - Unlocks from landmarks and endings share one list: starter ships, starting species, starting blueprints, map variants, and cosmetic hull skins.
- **Score**: endings are worth base points, plus credits, crew alive, POIs done, parts built, and jumps saved.
- **Unlocks for the next run** (they widen choice, never raw power):
  - **new starter ships**: the Concord frigate after the Concord Way Out, a Lumen skiff after the Lumen one, the Halcyon tender after the Haven;
  - **new starting species** (Haven: any species you recruited this run);
  - **starting blueprints** (one per ending, chosen from what you built this run);
  - **map variants** (the Hollow ending).
- **A run log** (a chronicle you can read on the ending screen) and a **hall of ships** (each finished ship's design is saved, and can be exported as a premade).
- **As built, where the endings are placed** (pack `endings_1`; events carry `requires.region` and `stage_min` / `stage_max`, the ending region is stage 9; `tests/test_endings_route.gd` walks every ending on a route of regions):
  - **The Haven**: the trail is stages 2 to 7. The first fragment is 2 to 5, each link opens a stage after the one before and stays open to stage 6 or 7, the bearings across the chart are 6 to 8 and the Lantern Reach (true or wrong) is on offer from stage 6, in the ending region too. A lure is the same carrier type as the real link it replaces.
  - **The Way Out**: backed at a faction's station, finished at its Dead Gate. The Concord's Restoration Desk is at Meridian (Concord space, stages 3 to 6), the Clan Moot at the station of any Clans-faction homeland (the Basalt Quarries, the Gauntling Scrapyards, the Kett Hives; stages 3 to 7) and the Lumen's consent at the Prism (Lumen space, stages 4 to 8). The cores and the restarts are at the Dead Gates of **the ending region** (stage 9): a gate is dark everywhere else, and in the ending region its shell can be approached (`campaign.gd gate_dark`); the Hollow tide never takes a gate.
  - **The Hollow**: the green ship from stage 3, Hallett's roll call from 4, the listening post and the Knucklehead from 5, the Basalt camp from 6 (these last can happen in the ending region), then the approach and the table at the Scrapper Gate (stage 9).
  - **Retire** and Ma's dinner are at Rusthold, which is Clan space (stage 1) only.

## 14. Difficulty and balance: FTL-hard, on purpose (owner, 2026-10-30)
> "Enemy scaling should be like FTL. It's a very hard game: a good player survives most of the time, but a win isn't guaranteed. You might choose the wrong quest, meet a full-shield enemy you're not prepared for, and die. So game balance is important."

- **Runs are permadeath**: the game saves on quit and at every jump, and death ends the run (with the ending screen and score). There's no reload of a lost fight.
- **Targets** (Normal difficulty; checked by the balance harness below):
  - a **prepared** ship against an enemy of its tier wins **85–95%** of fights, losing 20–40% hull;
  - an **under-prepared** ship against an enemy that counters it (full shields with no ion or missiles; heavy armour with only lasers) wins **30–50%**;
  - a skilled player finishes **40–60%** of runs, and a new player under 10%.
- **Enemy scaling, the FTL way**: an enemy is a **hull** (a premade design per faction and size class: small, medium, large) plus a **loadout bought from a budget**.
  - **Budget** = tier base × (1 + 0.04 × jumps) × the region's danger (Clan 1.0, Concord 1.1, the Boneyard 1.15, Lumen 1.2, the Gate approaches 1.4, the Hollow 1.6) × the difficulty (Easy 0.8, Normal 1.0, Hard 1.2). **Early stages (Beta 3)**: a run's stages 1 to 3 fight with 70% of it (`budget.stage_mult` in `data/enemy_tables.json`), and an enemy of those stages carries a shield at most 25%, 40% and 55% of the time (`budget.shield_cap`, rolled from the ship's seed; the rare factions ignore it). The stage rides in the spec as `:s<stage>` (`gen:rustfangs:medium:123:2400:s1[:ram]`); stage 4 and later, and a spec without it, are unchanged.
  - The budget buys from the faction's table (`data/enemy_tables.json`): weapon tiers, shield layers and sectors, armour layers on the outer walls, crew count and skill, the AI's `aim_skill`, and systems.
    - Rustfangs buy armour, rams and flak.
    - The Concord buys shields and missiles.
    - Wardens buy neon guns and ion.
    - The Hollow buys strange uniques.
  - **Every faction has counters you must plan for**:
    - a Concord shield wall needs ion, missiles or beams;
    - a Rustfang rammer needs dampeners, range or speed;
    - a Warden swarm needs flak or turrets;
    - a Hollow ship needs something you only learn by meeting one.
- **Danger is readable; ignoring it is your choice**:
  - Radar Mk2+ shows an enemy's **threat rating** (1–5 skulls, against your own ship's strength) and, when scanned closer, its loadout.
  - Events hint at danger in their text ("the hull bristles with guns", "her shield hums like a hive").
  - The risky choice is often the lucrative one. **Choosing wrong can kill you, and that's intended.**
- **Escape exists, but it costs**: jumping away needs the 8 s spool and no hostile within 2,000 px. Running from a fight means breaking contact first (speed, terrain, a smoke or decoy utility), as FTL players charge the FTL drive.
- **Difficulty settings**: Easy (enemy budget ×0.8, debris +30%, prices −10%), Normal, and Hard (budget ×1.2, debris −20%, fewer stores).
- **The balance harness** (a code brief; it runs in CI as a report, not a gate):
  - **Headless AI-vs-AI fights** in the real arena: **reference player builds** per stage (early, mid, late; one per line and archetype: gunboat, shield brick, rammer, missile boat) against each faction's enemies at budgets for jumps 5, 15, 25 and 35.
  - 50 seeded fights per pairing. It records win rate, time to kill, and hull and crew lost.
  - It writes `docs/BALANCE_REPORT.md`, flagging pairings outside the targets above. The lead tunes the numbers from it, and every content wave re-runs it.

- **Procedural enemy ships (built: `scripts/space/shipgen.gd`, tables in `data/enemy_tables.json`)**:
  - `Shipgen.build(faction, size, seed, budget)` gives a valid ship (power, sealed rooms, crew paths, mounts through the real rules, flies, no rectangle); the same arguments always give the same ship. A spec string `gen:<faction>:<size>:<seed>:<budget x 100>[:ram]` names one, and `Session.load_ship` loads it like a design file.
  - **Loadout**: the free base ship (helm, life support, the faction's cheapest reactor, two engines, one gun) plus purchases drawn from the faction's weights, each priced in `enemy_tables.json` and each needing the hull's room and the power its reactors give. Armour layers are real wall layers (2 hull integrity a cell, `arena.gd`).
  - **Hull**: `scripts/space/hullgen.gd` draws the faction's silhouette round the decks (gun deck, decks between, engine room) from the faction's `hull` grammar: wedge, chamfer, spikes, round2 arcs. A hull that comes out a box is narrowed at both ends, then gives up bow guns and engines, until it is under 85% of its bounding box.
  - **Campaign**: `fight: "tier"` rolls the `gen:` entry of `data/drift.json` `enemies`; the faction is the region's `enemies`, the budget is tier base x (1 + 0.04 x jumps) x the region's `danger` x the difficulty x the stage's `stage_mult` (stages 1 to 3: 0.7).
  - **Threat**: `Shipgen.threat(enemy, player)` / `Shipgen.threat_of(design, player)` give 1-5 skulls from sqrt(damage per second x effective hp) x a speed factor, enemy over player (`scripts/space/threat.gd`, cuts in the table); `Threat.label(n)` is the text for the radar and HUD.

## 15. Regions: every race has a home you can jump to (owner, 2026-10-30)
> "Every race should have their own region we can jump to."

- **The run is a journey through regions**, FTL/Multiverse-style:
  - A run crosses **8 stages**. Each stage is one **region**: a Drift-style node map of 16–20 places (section 8, each place a sector of section 11).
  - Stage 1 is always **Clan space** (Gantry Rusthold, Ma's debt).
  - At a region's **exit beacon**, a region map offers **2–3 next regions** to choose from. It shows each one's theme, danger and (once scanned) its rarity.
- **The region roster**:
  - **30 race homelands**, one per species: their stations sell their tech, recruit their people and run their events. Their enemies, hazards and debris fit their world.
  - **5 faction regions**: Clan space, Concord space, Lumen space, the Boneyard, the Gate approaches.
  - **The Hollow tide** regions (late).
  - **The rare faction regions** (section 18).
  - So a run sees 8 of 40+, and every run differs.
- **A region's data** (`data/regions/<id>.json`, one per pack): home race, faction, palette and backdrop tint, the debris table (section 11), the POI mix, stores, recruit table, the enemy table (section 14), hazards (ion storms, gas clouds, debris surges, radiation, a star's heat) and its event pool. Stage bands keep the difficulty curve: a region lists which stages it may appear in.
- **Code**: the current single Drift map becomes **one region's map**. A region graph picks the stages and choices from the run seed. The debt, reputation and saves carry across regions.
- **As built** (`scripts/space/regions.gd`, `campaign.gd`, `region_choice.gd`; the rules are `run` in `data/drift.json`):
  - **A region file** is one object: `id` (the file name), `name`, `home_species` ("" for none), `faction` ("" for none), `stages` [first, last], `weight`, `rarity` (common, uncommon, rare, very_rare, legendary), `danger` (the section 14 budget factor, shown as 1–5 skulls), `palette` {tint, nebula (an `art/space/nebula_<id>.png`)}, `map` (any `data/drift.json` map key, e.g. `nodes` or `clan_trader`), `node_weights` (replace the default), `places` (fixed nodes; `beacon: true` keeps one on the map, as a homeland's race station), `debris` and `pois` (multipliers over the node theme and mix), `ambient` (passing ships: trader, patrol, pirate), `stock` and `recruit` (the region's station menu; laid over a `data/drift.json` station's own), `enemies` (an enemy table id: a faction id), `hazards` (the ids a node may roll, README "Hazards", `data/hazards.json`), `events` (its event tag) and `blurb`. A homeland must have its station. The validator is `Regions.problems()`.
  - **The graph**: stage 1 is `run.start` (Clan space). Each exit offers 2–3 regions valid for the next stage, rolled by weight × the rarity factor, never one already visited; the same seed and the same choices give the same offers. Every stage must have enough regions that a run can always be offered two (the validator checks it). The last stage's exit leads to `run.ending` (for now the Gate approaches), the ending region, which has no exit.
  - **A region's map** is 16–20 places: its own places, an **Arrival point** at the left edge (unless a place is the start, as Rusthold) and the **exit beacon** on the far side, always on the map. Arriving there asks to confirm, then shows the cards (name, home race, faction, danger, rarity once scanned with an identifying radar or known through the flag `known_<region id>`, blurb). Crossing costs no fuel and no jump.
  - **Events**: `requires.region` (a region id or its `events` tag, or a list) and `stage_min` / `stage_max`, on an event or a choice. The flag `in_<region id>` is also set while in a region.
  - **Ma's debt clock** runs in stages 1–2 only: from stage 3 no payment falls due, no debt event comes and no rammer is sent (the debt can still be paid). Ma's tow takes you to the current region's start.
  - **Saves** are version 4 (stage, region, route, region seed); older saves load as stage 1 in Clan space.
  - **Exit wardens** (`scripts/space/wardens.gd`, `data/wardens.json`): every region's exit beacon is held by a strong generated ship that the region card names ("Exit warden: Concord Bulwark (Threat 4/5)" and a hint at what beats it). At the beacon you pay its toll (credits x the stage), are waved through when your standing with its faction is high enough, or break through (a win, a capture, a surrender or an escape clears the lane); the region choice stays shut until then. The ending region has no warden. Saves gained `warden` (version 6).

## 16. Unique characters: 60+ named crew with special abilities (owner, 2026-10-30)
> "60+ unique characters that do or sometimes do not belong to a race, but have special abilities, just like FTL."

- **`data/characters.json`** (per pack). Each character has: id, name, species (one of the 30, or a **one-of-a-kind** species of their own), portrait and rig variant (`_color` tints, a unique head or accessory layer), a passive trait bag (section 9 keys), **one active ability**, how you get them, and a lore line.
  - Ways to get one: a quest, a landmark, a rare store, a rare event, beating a rare faction, or a starting crew unlock.
- **Active crew abilities, a new mechanic**: select a crew member and press **G** (or click their ability on their crew card). Each has a cooldown. The vocabulary, built once and used by every character:
  - `power_system` (the system they stand by gets +N power for T s, no reactor needed);
  - `overclock` (the manned system ×1.5 for 10 s, then off 5 s);
  - `heal_burst` (heal everyone in the room for N hp);
  - `rally` (others in the room work ×1.5 for 15 s);
  - `repair_burst` (instantly repair N hp of a system);
  - `extinguish` (put out the room);
  - `seal_breach` (seal it instantly);
  - `shield_layer` (+1 layer for 10 s);
  - `scan` (reveal the enemy for 20 s);
  - `hack` (disable one enemy system for 5 s, from the helm);
  - `berserk` (melee ×2 for 10 s);
  - `phase` (walk through one wall to the next room).
- **How it is built** (`scripts/crew/crew_abilities.gd`, `crew_fx.gd`, `characters.gd`, `ui/crew_bar.gd`; vocabulary in `data/crew_abilities.json`, whose `_doc` says what each ability does exactly):
  - A crew member carries `ability: {id, cooldown?, params?}`: from their species entry (`data/species.json`) or from their character. `cooldown` and `params` override the vocabulary's defaults key by key.
  - **Left click** a crew member in play mode (or their card on the crew bar, bottom right) selects them (a gold ring); **G** uses the ability, in a fight too, or click the icon on the card. The cooldown ring on the card is green when ready, fills while it cools, and is gold while the effect runs. A refused use (no fire in the room ...) costs no cooldown. Cooldowns and effects tick in `ShipSim` with everything else, so they stand still when the world is paused (build mode).
  - Timed effects live in `ship.ability_state["fx"]` (not saved) and reach the game through small hooks: power by hand (`Power.solve` mods `hand`: it also runs a part that is on no cable), overclock and shield layers (`Abilities.running`), offline parts (`Ship.disabled_uids`: a hack, or an overclock's burn-out), rally (`TraitSet.work_rate`), scan (`Radar.contacts`: hidden contacts within radar range, all named), berserk (`CrewAbilities.melee_mult`, read by the on-foot fights later).
  - **`data/characters.json`** (and every pack's `characters.json`, Content kind `characters`): `id`, `name`, exactly one of `species` or `unique_species` (a species entry of its own: name, hp, speed, traits, rig, sidearm, trait keys inline; its species id is `unique:<id>`), `rig` (`{tint, head}`: an outfit colour and the name of a head frame of the rig's `art/crew/<rig>/crew.json`), `traits` (a list of trait ids, or an object of trait keys, merged with the species'), `ability`, `obtained`, `lore`. `CrewAbilities.problems()` checks all of it (it is part of `tests/test_content.gd`'s rules); `tests/fixtures/packs/crew/` has examples.
  - A character joins through the campaign's recruit effect: `{"recruit": {"character": "<id>"}}` (once per run; the event validator knows the ids).
- **The roster target is 64 characters**: 30 tied to the races (one per race at least, two for the big cultures), 20 cross-race oddballs, and 14 one-of-a-kind beings.
  - Examples: **Socket**, a Basalt who powers an adjacent system by hand; **Old Hob**, Ma Gantry's mechanic, who repairs Scrap parts instantly; **the Lamplighter**, an AI in a lantern; **Sister Vell**, a Choir who fights fires with a song.
- **Wave 1, as built** (`data/packs/chars_1`: 24 characters, 28 events; the tests are `tests/test_chars_1.gd`):
  - Two per race for the ten homelands (one combat or helm, one ship-craft or crew) and four wanderers found in any region (a firefighting drone, Halfway who walks through walls, a turned Warden, a slow Basalt racer). The three one-of-a-kind ones use a `unique_species`.
  - The schema has no title key, so a character's one-line title opens their `lore` ("The Vacuum Mason. Skerry has ..."), and the bio follows.
  - Each is recruited by an event with `recruit: {character}`, placed with `requires.region` (the homeland) and a stage band; every event has a free way out and most a blue choice. Eight are hard to get: a fight (the win pays through `after_win`), a high price, or a chain of two events joined by a flag (the second needs only the flag, so it finds you in any region).
  - Abilities used: all of the vocabulary but `berserk`, which nothing reads until there are on-foot fights. A strong one has a longer cooldown and better params than the vocabulary's; a weak or constant one has a short cooldown.
- **Wave 2, as built** (`data/packs/chars_2`: 24 characters, 26 events; the tests are `tests/test_chars_2.gd`):
  - One for each of the twenty newer races (waves 2 to 4), found in their homeland, and four wanderers found anywhere from stage 2 (Tilley, a lane-lamp AI with a `unique_species`; Pettifer, a customs clerk; Tinder, a fire-eater; Cadence, a drum-major). That makes 48 characters. The Warden-frame, Quoin, has no homeland: his event asks for the flag `warden_lit` that the Warden reboot quest sets (stage 5+, any region).
  - Eight are hard to get: three fights (Kharra, Tamsin, Pyracantha; the win pays through `after_win`), two high prices (Rushlight 320, Filigree 360 credits; Kharra can also be bought off for 340) and three chains joined by a flag (Obliged and Tilley across two events, Quoin across the quest). Every event has a free way out and a blue choice (a species, a trait, a part, or good Concord standing).
  - Abilities: all of the vocabulary but `berserk` (still unread). Names are fresh across every name pool (a test checks); the Rattler is Hobnail ("Old Hob") because Hob is a human crew name.

## 17. Racial tech: arsenals and components with trade-offs only their race erases (owner, 2026-10-30)
> "Every race should have their own set of weapons and ship weapons with on-theme animations, effects or damage, and their own versions of components with different pros and cons. The cons should be averted by the race's own pros: an engine draining oxygen, but the race doesn't need it. A trade-off for a mixed crew, but not at all for a dedicated crew. Just like FTL."

- **Per race**: **3 ship weapons, 3 components** (engine, reactor, shield, O2 or utility, whichever fits) and **2 hand weapons**, sold in their homeland and found in their wrecks.
- **The rule**: each racial part has a **strong pro** and a **real con**, and **the con is something that race's own traits cancel**. A dedicated crew runs it free; a mixed crew pays.
  - Basalt **Vacuum Forge** (reactor): +3 power, but it vents its room's air. Basalt don't breathe.
  - Emberkin **Pyre Drive** (engine): thrust ×1.5, but its room runs at +40 heat. Emberkin shrug it off.
  - Fenn **Twitch Cannon** (weapon): fires 40% faster, but malfunctions 20% per minute. Fenn fix it in no time.
  - Kett **Hive Battery** (shield): it reaches full layers only with 3 operators. Kett swarm it.
  - Mire **Steam Lance** (weapon): heavy damage, but a 10% fire chance in its own room per shot. Mire put fires out twice as fast.
  - Sporeling **Bloom Reactor**: cheap, big power, but it eats the room's O2. Sporelings make O2.
  - Gauntling **Arc Core** (reactor): it shocks organic crew in its room. Gauntlings are mechanical.
  - Prismatic **Prism Lens** (weapon): full power only with a Prismatic manning it (50% otherwise). Prismatics also add power.
  - Grundl **Slug Mortar** (weapon): huge hits, but it empties racks fast. Grundl restock twice as fast.
  - New races follow the same rule (Wisp parts need no tools to run but can't be repaired by hand: Wisps can't repair anyway, they're built for crews of Wisps and Ferro...).
- **On-theme effects and damage**: racial weapons bring their own projectile and impact art, and new damage effects built once in the combat vocabulary:
  - `acid` (damage over time to a cell);
  - `spores` (starts a slow O2 drain in the room hit);
  - `shard` (pierce plus splinters);
  - `sonic` (stuns crew in the room hit);
  - `magnetic` (pulls the target ship, or drags debris);
  - `frost` (slows the target system's charge);
  - `corrode` (lowers the hit wall material's resist for 10 s).
- **Data format** (built in `scripts/combat/effects.gd`, tested in `tests/test_fx_effects.gd`): a weapon entry's `"effects": {...}` holds the keys below; every number is checked by `Effects.problems` (the old list of tags, `["lock_doors"]`, stays valid). Shots a shield stops carry no effect. Acid, spores, sonic, frost and corrode renew instead of stacking.
  - On the target, where the shot first meets cells: `acid {dps, seconds, type?, spread?}` (the hit cell, a hit every 0.25 s; it never wrecks a part that is already out; `spread`, a chance from 0 to 1 per tick, lets the cloud creep to one more neighbouring wall, door or part each time it comes up, a part once, up to 12 cells at once, and a shot on a cell the cloud already eats renews the cloud: Magma Spitter 0.15, Rot Pod 0.3); `spores {o2_drain, seconds}` (the room hit loses that fraction of full air a second); `shard {splinters, dmg}` (that many solid neighbours take `dmg`, a part once); `sonic {stun_s}` (crew in the room hit stunned, jobs paused); `magnetic {pull}` (the target gains `pull` px/s at mass 1000 toward the shooter, lighter ships more; debris within 320 px is dragged too); `frost {slow, seconds}` (the part hit, or the parts of the room behind a wall hit: weapon cooldown, shield recharge and ability cooldowns run at 1 - slow); `corrode {resist_mult, seconds}` (the wall or door hit takes 1 / resist_mult times the damage); `split_on_shield {count, damage_mult}` (when a shield stops the shot, `count` fragments of `damage_mult` times its damage fan out 25 degrees either side from just outside the bubble and meet it again: each uses a layer, or reaches the hull where the sector is down; they keep the other effects, scaled, and never split again; bolts, flak and missiles only. Refractor: 3 at 0.35).
  - On the shooter, per shot: `self_room {o2_drain (fraction of the room's full air), heat, fire_chance, shock_dps (organic crew only, while it fires), scorch_dps (hp/s to crew without `heat_resistant` in the breech room for the weapon's cooldown after each shot, the mirror of shock_dps: Pyre Lance 1.5, Flare Turret 0.8)}`; `needs_operator {species (id or list), else_mult, stat: "damage" (default) | "rate"}`; `needs_crew_in_room {count, else_mult, stat: "rate" (default) | "damage"}`; `ammo_mult` (also accepted at the top level of the entry, next to `ammo`; 1.5 spends 1, 2, 1, 2). `intercept {range}` (turrets only: point defence. The turret turns on the nearest enemy missile within `range` px **before any ship**, and each shot rolls its `accuracy` (a missile does not dodge) to destroy it outright; the shot is instant, shows a tracer, never opens the shooter's own shield and logs an `intercept` effect event. Flak Screen and Drone Picket: 300 px).
  - Art: a weapon's shot, its beam and its impact use `art/projectiles/<weapon id>.png` and `<weapon id>_impact.png` when they exist, else the kind's (`bolt`, `laser`, ...). Without art the effects draw as coloured placeholders (`scripts/combat/effect_fx.gd`). `tests/tool_fx_range.gd` (xvfb) shoots each effect at a hull and saves the pictures.
- **Component mechanics** (built in `scripts/sim/abilities.gd` and `scripts/sim/part_effects.gd`, tested in `tests/test_part_effects.gd`; the validator is `PartEffects.problems`, run over every component, packs included, by `tests/test_components.gd`). A racial part is a component with a **passive ability** whose `effects` and `side_effects` use the keys below; the data never needs code. "Room" is the room of the part's anchor; "up" crew are neither downed nor stunned; `who` is a species id (`"kett"`), a trait id of the library, or a flag of the resolved traits (`"mechanical"`); `"a|b"` means either.
  - `effects.crew_bonus {who, stat, per, max}`: each up crew member in the room matching `who` adds `per` to `stat`, `max` in all. `stat`: `power` (added to the part's output, after its factors), `thrust` (added to the engine's thrust), `shield_layer` (layers of a shield part, rounded down). Nest Reactor, Song Reactor.
  - `effects.crew_needed {count, stat, else_mult, who?}`: unless `count` up crew (matching `who`, if given) stand in the room, `stat` is multiplied by `else_mult`. `stat`: `power`, `thrust`, `shield_layer` (rounded down), `recharge` (the speed the shield's used layers come back at: 0.5 takes twice as long, 0 never), `evasion` (the ability's own `evasion_add`: a Resonance Helm is `evasion_add` 0.1 with `crew_needed` `{count 1, stat evasion, else_mult 0, who prismatic}`). Hive Battery; Overclock Engine (`count` 1, `who` `mechanical`); the Prism parts (`who` `prismatic`). `crew_bonus` and `crew_needed` may be a list of entries.
  - `effects.turn_mult`: a factor on the ship's turn rate while the part works (`Abilities.turn_mult`, the product over the parts that work; the arena hands it to the flight body, which scales the turn acceleration and so the steering). Gravity Anchor x1.5. An ion hit or a disabled part turns it off.
  - `effects.room_wall_hp_mult`: a factor on the hp of the wall cells round the room (solid tiles, not doors), set when a fight starts like armour; the strongest factor on a cell counts, they do not stack. Stonehide Plating Bay.
  - `effects.heat_above {heat, shield_layer}`: that many extra layers while the room's hottest part is above `heat`. Hearth Shield.
  - `effects.room_work_mult {mult, who?, else_mult?}`: a factor on the work speed (repair, extinguish, breach, revive) of the crew in the room: `mult` for those matching `who` (everybody without one), `else_mult` (default 1) for the others. Brood Hold, Quickfix Bay, Graft Bay, Cargo Deck.
  - `side_effects` `shock_organic` (`rate` = hp a second): every crew member in the room who is not `mechanical` takes it while the part runs. Arc Core, Graft Bay.
  - `side_effects` `scorch` (`rate` = hp a second): every crew member in the room without the `heat_resistant` trait takes it while the part runs, the mirror of `shock_organic`. It does not touch the part's own heat (`heat` does), so an Emberkin crew runs a Pyre Drive, Furnace Core or Hearth Shield free and a mixed crew pays. Combine it with `heat` on the same ability.
  - `side_effects` `wet` (`rate` = work factor, e.g. 0.8): crew in the room work at that factor unless their `work_mult.extinguish` is above 1 (Mire); every part in the room also loses 30 heat at the start of each second.
  - `stats.recharge` on a shield part (seconds a used layer takes to come back, 7.0 is normal: the `shields.recharge` block of data/weapons.json) is real: the shield's recharge runs at 7.0 / `stats.recharge` times the normal speed, so the Neon Lattice's 4 is 1.75 times as fast and a Mycelium Shield that regrows x1.5 has 3.7. Used layers come back one at a time, and a sector whose last whole layer is used waits `shields.break_delay` (3 s) more. Pack shields follow `shields.tier_recharge` (tier 1: 7, tier 2: 5.5, tier 3: 4.5; x0.6 on the neon line). With several shield parts the layers-weighted mean counts. `crew_needed` `recharge` multiplies that.
  - `stats.malfunction_per_min` on a component (a chance per minute, 0 to 1) replaces its line's malfunction rate. Jury Reactor, Twitch Cannon.
  - `side_effects` `self_repair` (`rate` = hp a second): a living part mends itself and the outside half of its mount, powered or not, and a disabled one is ok again once it has hp (`Abilities._self_repair`). Starwhale Fin.
  - `shield_layer` and `recharge` effects only work on a shield part (the validator refuses them elsewhere). The older keys (`stat_mult`, `shield_layer`, `charge_mult`, `evasion_add`; `drain_o2`, `heat`, `power_spike`, `fire_risk`, `self_damage`) keep working next to them.
  - **Cons cancelled by the race's traits need no key.** `drain_o2`: a crew member with `o2_use` 0 (Basalt) cannot suffocate. `fire_risk`: a Mire puts the fire out twice as fast and takes half the burn. `self_damage` and `malfunction_per_min`: a Fenn repairs 1.67 times as fast. `heat` (the part's own heat) is cancelled by nobody: it trips the part at its heat limit for every crew, and an Emberkin only takes a quarter of the fire damage when that starts one; the Emberkin parts therefore pair it with `scorch`, which only crew without `heat_resistant` pay.
- **Numbers**: racial parts sit on their tier's band (section 3 of CONTENT_PLAN) but trade a +30–50% pro for a con that costs the same on a mixed crew. They carry a `quirk` explaining it, and the validator checks they have both.

## 18. Rare factions: from uncommon to legendary (owner, 2026-10-30)
> "Add factions that are rare to come by, from OK rarity to super rare, where some rare ones are really powerful ships, races or weapons, like the relic people in Multiverse. Getting them might be too strong and kill your run, but if you manage to complete the quests or beat them, getting their guns or tech might be super strong for you."

| rarity | faction | what they are | meeting them | their prize |
|---|---|---|---|---|
| uncommon | **Salvage Barons** | rich pirate lords in heavy, gaudy ships | appear in Clan space and the Boneyard (5% of fights) | gilded weapons, credits, Baron crew |
| uncommon | **Lattice Pilgrims** | gate monks walking the dead lanes | Gate approaches, Lumen space (event chains) | blessings (permanent small buffs), pilgrim crew |
| rare | **Halcyon Wardens** | the Haven's defence fleet | after Haven fragments, as tests | Halcyon shields and gate-shunt drives |
| rare | **Leviathans** | living ships from the deep Drift | their own rare region, or a 1% roaming encounter | living parts that self-repair (Starwhale Fin), bone armour |
| very rare | **The Architects** | the gate builders' automated fleets, still working | their region appears in stages 5–8 at 3%; a landmark | **relic tech**: phase weapons that ignore shields, Architect cores |
| legendary | **The First Lattice** | a ghost fleet from before the Snap, bending space | a 0.5% region in stages 6–8, or a 6-step quest chain | legendary relics that break the rules (time-slow, jump anywhere, a crew member who is a living gate) |

- **Danger is the price**:
  - Rare factions use budgets far above the stage (×1.5 to ×3) and tech the player can't match early. **Meeting one unprepared can end your run**; their encounters are telegraphed with a threat of 5 skulls and a choice to flee.
  - Beating them, or finishing their quest chains, gives tech above the bands: legendary uniques that can carry the rest of a run.
- **Data**: each rare faction is a pack with its region (if any), enemy table, events and quests, crew, and relic components marked `"relic": true`. Relics may ignore the bands, and the validator only requires a `quirk` or a cost.
- **As built (packs `faction_barons` and `faction_leviathans`)**:
  - **The faction table lives in the pack**: a pack's `enemy_tables.json` (`{"factions": {...}}`) adds shipgen factions (`Shipgen.tables`); its `factions.json` lists them as hostile. A rare faction's table has three extra keys: `min_size` (heavy hulls: never smaller), `budget_floor` (the least stage budget it is built for, times the difficulty, so it is dangerous at the first jumps too) and `budget_mult` [least, most] (rolled over the stage budget; `Campaign.gen_spec`). Against the three starters the Barons rate 4-5 skulls (budget 300-400) and the Leviathans 5 (300-450): `tests/test_factions_1.gd` holds both to it.
  - **Events name them** (`fight: "gen:barons"`), so the choice shows its threat tag, and every event with a fight has a choice with no price and no effects. The Barons are six events in Clan space and the Boneyard (`requires.region`), weighted to about 5% of the pirate encounters there; the Leviathans' region `leviathan_deep` (stages 4-8, rare, weight 3, no pirates or patrols; its exit warden is a Leviathan, `data/wardens.json`) has six events, and one roaming event (`leviathan_surfaces`, stage 4 up, ~1% of the empty-space events).
  - **Prizes** come from salvage (a Baron carries the gilded weapons and the Aegis; a Leviathan's engines are all Starwhale Fins and its plating Bone Armour) or from the events (the Leviathan quest: free the calf, then the mother gives a Fin).
  - **Relics**: `relic: true` on a component is checked by `Balance.check` (status `relic`): never held to the bands, but it must have a `quirk` or a `cost` (a text or a non-empty object), or the test fails. Barons: Sovereign Aegis (shield). Leviathans: Starwhale Fin (engine), Bone Armour (tile, costs Leviathan Bone).

## 19. The hangar: unlockable starter ships (owner, 2026-10-30)
> "Every large event and race could give us 1–3 unique starter ships."

- **Every race unlocks 1–3 starter ships**, as the A, B and C layouts of its own ship type (FTL's hangar):
  - **A** is the race's signature: its racial tech plus a crew of that race.
  - **B** is a different strategy: missiles, rams, a shield brick, a boarder, or a miner.
  - **C** is the odd one: a mixed crew, a quirky unique, or a hard mode.
- **Large events give starters too**: landmarks (13), endings (13), rare factions beaten or befriended (18), and big quest chains. Examples:
  - the **Halcyon Tender** (the Haven ending);
  - **CS-001 Patience**'s little sister (a Concord landmark);
  - a **Baron's Yacht** (the Salvage Barons);
  - an **Architect Seed** (relic hull; very rare);
  - **Ma's Kettle-class tug** (Retire ending).
- **The target is about 80 starters**: 30 races × 2 on average, plus about 20 from events. Each one is real:
  - a silhouette in its race's or faction's style (4c, never a rectangle);
  - working power, rooms and crew paths;
  - a starting cargo and a one-line pitch;
  - a fair stage-1 strength (the balance harness checks every starter against stage-1 enemies at the 85–95% target).
- **How they unlock**: each has an `unlock` condition (`data/unlocks.json`):
  - reach its race's homeland;
  - recruit 3 of that race in one run;
  - finish its race's quest;
  - complete a landmark or ending;
  - beat a rare faction.

  The run-start screen shows the hangar: ships grouped by race and faction, with the A/B/C tabs, the unlock hint on locked ones, and stats and crew for the selected ship.
- **Building them**: hand-tuned designs written by generator tools, like `tests/tool_make_starters.gd`. Each race wave ships its starters. The procedural ship generator (track 1) can propose hulls that a designer agent then tunes.
- **Built so far (pack `starters_2`, `tests/tool_make_starters2.gd`)**: the 7 event starters (Halcyon Tender, Ma's Kettle-class Tug, Concord Frigate Resolve, Door Prize, Lumen Skiff Afterimage, Hollow-Touched, CS-002 Forbearance) and layouts A and B for the 10 races of waves 0 and 1 (27 ships, 30 with the first three).
  - Each design file carries its own `hangar` field `{group, layout, unlock}` (a pack has no hangar.json); the group is the race's name (`Human`, `Kett`, ...), the faction's for the event starters (`Clans`, `Concord`, `Lumen`) or `Haven` and `Hollow`.
  - The tool draws every ship as a list of rooms inside a silhouette (every other cell is wall) and uses a part of the race's tech pack where it is loaded, else its standard stand-in, so run it again after a tech pack changes. `tests/test_starter_ships.gd` holds every hangar ship to the starter rules.
  - Earning them: layout A of a race in its homeland's dock event, layout B in its homeland's tech quest (the outcomes that win the tech), both through an `unlock` effect in `data/packs/regions_1/events/`.
- **What the other unlocks do at a new run** (`scripts/space/run_start.gd`; the payloads are documented in `data/unlocks.json`): the hangar has a **new-run row** under the ship (S, V and K or a click move its choices, Shift or a right click go back; it shows only what the profile has earned, and the profile remembers the choice):
  - **`species_start`**: the soldier of the ship's crew list is that species (and named `name`, when the payload has one). Crew entries marked `player` keep the soldier's place under a new name.
  - **`blueprint`**: known in the fabricator at the start of every new run once earned; it is not a choice.
  - **`map_variant`**: an opt-in harder map. The payload's `tide_steps` is how far ahead the Hollow tide of every region starts (`hollow_tide`: 2); the run carries the flag `variant_<id>`.
  - **`skin`**: tints the exterior hull plating of the ship in a fight (`tint`, a multiply colour over the line's own) and colours its lamps (`lamp`). The ship keeps it (`Ship.skin`, saved).
