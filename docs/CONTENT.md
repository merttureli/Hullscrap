# Hullscrap: content and core rules (lead design, v1)

This is how systems, weapons and real-time combat work, plus the first content set. Everything here is **data** (`data/*.json`), read by generic code. Numbers are starting points for tuning. Visuals are swappable: every item draws through `scripts/view/visuals.gd` by id, as a placeholder now and real art later.

## 1. Component schema (`data/components.json`)
Each entry has:
- `id`, `name`, `family`, `line` (`scrap` / `standard` / `neon`), `tier` (1-3), `size`, `color`;
- `power` (+ produces, − consumes), `priority`, `manned`;
- `hp` (system health: at 0 it's **disabled**, not destroyed; crew repair it);
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
  - **W/S** thrust and reverse, **A/D** turn.
  - Speed, acceleration and turn rate come from `flight.gd`: powered engines' thrust against the mass of everything you built.
  - The crew stay aboard and repair, fight fires and man stations on their own.
- **Aiming**:
  - **Mouse aims.**
  - **LMB** fires weapon group 1, **RMB** fires group 2. Lasers default to group 1 and missiles to group 2.
  - **1–4** fire a single weapon, **Shift** triggers the engine ability (e.g. Afterburner), **Space** the shield ability, **Q** and **E** utility abilities.
  - Weapons have **cooldowns** (charge times) shown on the weapon bar.
- **Weapon arcs**: a weapon fires from **its own position on your ship**.
  - It aims within a **120° arc** pointing outward, from the ship's centre through the weapon. Some weapons have their own `arc`; turrets get 360°.
  - So guns belong on the hull edge, facing out. Flanking the enemy matters.
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
    - A component at 0 is **disabled**, not destroyed, until crew repair it.
    - If the weapon has `pierce`, leftover damage carries on into the next cells.
  - **Thick outer walls are armour.** A reactor in the middle is protected, and an exposed one is a target. Players will aim for engines and weapons, and flank to reach the soft side.
  - Every hull hit also lowers the ship's **hull integrity** pool: hull_hp = 20 + armour plates. At 0 the ship is **wrecked** and becomes a salvageable derelict.
- **Shields** are a bubble (an ellipse around the hull) with **layers** from powered shield components.
  - A projectile or laser hitting the bubble uses up a layer, and layers recharge over time.
  - Missiles pass through. Ion removes layers and ion-locks systems.
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
