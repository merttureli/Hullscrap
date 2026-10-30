# Hullscrap: content and core rules (lead design, v1)

This is how systems, weapons and combat work, plus the first content set. Everything here is **data** (`data/*.json`), read by generic code. Numbers are starting points for tuning. Visuals are swappable: every item draws through `scripts/view/visuals.gd` by id, as a placeholder now and real art later.

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

## 4. Combat core (`scripts/sim/combat.gd`): FTL-like, room-targeted
- **Hull**: each ship has `hull_hp` = 20 + armour (from `armor_plate` components). At 0 the ship is wrecked: it becomes a derelict you can salvage. Ships are never deleted.
- **Weapons** are charged by power over `charge_time`. When charged and aimed at a **target room** on an enemy ship, they fire. Weapon stats:
  - `shots`, `damage` (to hull), `sys_damage` (to components in the hit room);
  - `ion` (shield layers removed and system ion-lock seconds), `fire_chance`, `breach_chance`;
  - `pierce` (shield layers ignored), `kind` (`bolt`, `missile`, `beam`, `flak`, `ion`, `drone`), `ammo` (an item consumed per volley, or none);
  - `accuracy_bonus`.
- **Shields**: `layers` from powered shield components. Each projectile (except missiles and pierce) hits a layer instead, and a layer recharges after `recharge` seconds. Beams lose damage per layer.
- **Hit and miss**:
  - **Evasion** = the target's (powered engine thrust / mass) × k, plus a bonus for a manned helm, capped at 60%.
  - The shot hits if roll ≥ evasion − accuracy_bonus.
- **On a hit**:
  - hull −= damage;
  - each component in the room takes `sys_damage`;
  - crew in the room take damage;
  - roll `fire_chance` (start a fire on a random floor cell of the room);
  - roll `breach_chance` (a random wall cell of the room becomes **breached**: the room vents until repaired).
- **Fires** (`scripts/sim/fire.gd`):
  - burn on cells, spread to neighbouring floor cells (10%/s);
  - consume room O2, damage components (0.5/s) and crew;
  - die out below 20% O2.
  - Crew put them out.
- **Repairs**: crew with a job fix disabled components (hp back up), breaches and fires. Speed comes from skill and the line's repair multiplier.
- **Determinism**: all combat rolls use the battle's seeded RNG.

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
2. Abilities, with the Afterburner end to end (an HUD button and its side effects).
3. Combat logic: weapons charge and fire at rooms, shields, evasion, damage, fires and breaches, all headless and tested ship against ship.
4. Combat in the game: a target ship spawns (a simple pirate), the tactical view, the weapon bar, target selection.
5. Crew jobs: repair, firefighting, manning stations (manned bonuses).
