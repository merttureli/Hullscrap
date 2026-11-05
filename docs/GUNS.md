# Hullscrap guns: shapes, aim, versions and look (lead design v1, 2026-11-05)

Owner: "Guns are one of the biggest features of the game, so good effort into design is a must, both visual and mechanics."
This is the design for the gun rework: the shapes, how they aim, the gun families and their versions (the way FTL: Multiverse grows its arsenal, with our own names), the new mechanics, the visual language, and the plan.
The mount rules (two halves through the wall, CONTENT.md 4f) and the art bible (ART_STYLE.md) still hold. This adds to them.

> **G1a landed (rules as built, where they differ from the first draft).** Centring: the breech starts `floor((W - bw) / 2)` cells from the outside half's left edge at rotation 0, and turns with the part (a wider breech pokes out equally); the link is as wide as the outside half. Outside hp = `round(hp x cells / 4)`. A one-cell-deep outside half (flush pod, gun strip) is **low**: rams pass over it. The data key `aim` is fixed, swivel or turret, `aim_share` holds the shares, `shapes` the shape table (`data/weapons.json`). Point defence shoots missiles, any shot at or below `pd_speed` (500 px/s) and shots marked `interceptable`. Rattle Burst's arc went 240 to 270 to sit in the turret band, and the two broadsides' gimbal 3 to 20.

## 1. Pillars
1. **A gun reads at a glance.** Its silhouette says how it aims (fixed, swivel, turret), its size says how hard it hits, and its colour says its family. The firing arc shows while you place it.
2. **Shapes are a placement puzzle.** A long barrel fits a thin prow, a broadside wants a long flank wall, a spinal mount wants the keel, and a point turret fits a corner. Where a gun can go matters as much as its numbers.
3. **Every version has a reason to exist.** A version changes how you fight (burst, chain, charge, long), not just "+10%". Each has a counter.
4. **Firing feels physical.** Recoil, a muzzle flash in the family's colour, spin-up, charge glow and heat. The hit lands where the shot does.

## 2. Aim classes
| class | arc | tracks | damage share | silhouette |
|---|---|---|---|---|
| **Fixed** | gimbal 2-8 deg (broadside 20) | no: you aim the ship (or strafe, A/D) | 1.0 | a rectangular casemate, the barrel braced in a sleeve |
| **Swivel** (NEW) | 120-180 deg | yes, 90 deg/s | 0.8 | a half-round sponson on a yoke, with a rail track on the hull face |
| **Turret** | 270-360 deg | yes, 120 deg/s | 0.6 (today's `turret_damage`) | a full ring base, a compact head and a sensor eye |

`damage` in the data stays the fixed equivalent. The share comes from the class (`aim` key: fixed, swivel or turret; `turret: true` reads as turret).

## 3. Shapes
Outside half W x H at rotation 0, where H is how far it sticks out into space; the breech is the inside half. Every shape rotates to any wall (R) and mounts on slopes. Outside hp scales with the cells it covers.

| shape | outside | breech | aim | made for | trade-off |
|---|---|---|---|---|---|
| Point turret | 2x2 | 2x2 | turret | light, rapid, point defence | small target, light hits |
| Dome turret | 3x3 | 2x2 | turret | medium all-round turrets | a big round target that sticks out |
| Sponson | 3x2 | 2x2 | swivel | covers one side | the middle ground |
| Casemate | 4x2 | 2x2 | fixed | the standard gun (today's) | you aim the ship |
| Long barrel | 2x4 | 2x2 | fixed | snipers, rails, lances | narrow, but sticks out far: rams hit it first |
| Broadside battery | 6x2 | 4x2 | fixed, gimbal 20 | burst and volley guns, 2-3 barrels | needs a long side wall |
| Gun strip | 8x1 | 4x2 | fixed, gimbal 20 | a row of 4-6 small barrels | very low and hard to hit, but long |
| Heavy cannon | 4x3 | 4x2 | fixed | heavy versions | slow; big hits |
| Spinal mount | 2x6 | 2x4 | fixed, gimbal 2 | tier 3 lances and rails along the keel | the breech runs deep inside, and the ship must face the target |
| Flush pod | 4x1 | 2x2 | fixed (missiles home) | missile and mine pods | low: hard to hit, and rams pass over it |

**Guns meant for the side (owner):** the broadside battery and the gun strip are built for flank walls. A fixed gun on a side wall fires out of the side, and the 20 deg gimbal lets a passing run land. The build ghost says "best on a side wall". There are no locks.

## 4. Families
Each family keeps its kind and its colour (the light pixels, the glow, the flash and the shot), across every line and version.

| family | kind | damage | identity | countered by | colour |
|---|---|---|---|---|---|
| Laser | laser (hitscan) | energy | reliable, instant | shields | red |
| Pulse | bolt | kinetic | solid shots that can be dodged | armour, evasion | orange |
| Ion | laser or bolt | ion | strips shields, shuts systems down | ion-hardened lines (standard) | teal |
| Flak | flak | kinetic | a spread of pellets; good up close and on small ships | range, shields | amber |
| Missile | missile | explosive | slow, homing, passes shields | point defence, evasion | white and red |
| Beam | beam | energy | a held line that sweeps across rooms | shields (a beam can't open a layer) | crimson |
| Slug | bolt (slow shell) | kinetic | heavy, pierces, punches through armour | point defence (a slow shell), evasion | steel and yellow |
| Point defence | bolt (intercept) | kinetic | shoots down missiles and slow movers | heavy fire, beams | green |

## 5. Versions (templates)
A version is a template on a base family at a tier. The numbers are against the base at the same tier; G2 tunes them with the bench (section 9).

| version | shape | damage | cooldown | other | how it plays |
|---|---|---|---|---|---|
| **Mk I-III** | the family's | tier steps | tier steps | | the line you climb |
| **Light** | point or sponson | x0.55 | x0.6 | range x0.85, power -1 | cheap, fits anywhere, tracks |
| **Heavy** | heavy cannon | x1.9 | x1.6 | pierce +1, shot speed x0.85 | big slow hits that break armour |
| **Burst** | broadside or gun strip | x0.45 a shot | x1.25 | 3 shots, spread 6 deg | overwhelms shield layers and PD |
| **Chain** (NEW) | casemate or sponson | x1.0 | x1.3 at first | each volley inside the window cuts the cooldown 20%, up to 3 steps (x0.66 floor); it winds down after 3 s idle; more heat | rewards staying on target |
| **Charge** (NEW) | sponson or spinal | x1.0 | x1.1 | stores up to 3 volleys while idle (or while you hold fire), then fires them 0.15 s apart | breaks layered shields in one go |
| **Long** | long barrel | x1.0 | x1.2 | range x1.4, shot speed x1.4, accuracy +10, gimbal x0.5 | out-ranges, needs aim |
| **Lance** | spinal | x3 | x2.2 | pierce +2, range x1.5, gimbal 2 | the finisher; the ship must face the target |
| **Point defence** | point turret | low | | intercept (section 6) | protection, not offence |

**Race and faction versions:** the race guns of the tech packs are the race's versions. Each keeps its quirk and gets the shape that fits it (section 8). G2 can add one more per major race on these templates, for example a Kett burst swarm, Basalt heavy, Fenn chain, Prismatic charge, Grundl broadside, or a Human long rail and PD.
**Relics:** a few unique found guns that break a template rule. These come later.

## 6. New mechanics
- **Swivel aim class:** turret tracking inside a 120-180 deg arc at the 0.8 share. Same AI and code path as turrets.
- **Chain:** each volley inside the window (the cooldown plus 1.5 s) adds a step, up to 3. Each step cuts the cooldown 20%. Steps fall away one a second after 3 s idle.
  - The weapon bar shows the steps as pips.
  - The art spins faster with each step, and the barrel glows with heat.
- **Charge:**
  - The gun stores a volley each cooldown while it isn't firing, up to 3.
  - The fire key releases all stored volleys (0.15 s apart); the AI releases at 3, or when the target's shield is down.
  - The weapon bar shows the stored charges; the art lights one capacitor ring per charge.
- **Point defence by tier** (owner): builds on today's `intercept` effect, which only shoots missiles.
  - It shoots the nearest incoming threat in range: missiles, and any projectile at or below `pd_speed` (mortars, harpoons, pods, spores, slow shells) or marked `interceptable`.
  - It shoots ships only when nothing incoming is in range, at low damage.
  - Hit chance and rate by tier: Mk I about 60% and 1.2 s, Mk II about 70% and 0.8 s, Mk III about 80% and 0.5 s. Short range, 350-450 px.
  - A hit destroys the shot, with a small burst.
- **Broadside passes** (pilot AI): when a ship's side guns outweigh its bow guns, its pilot turns its side to the target and strafes along, rather than pointing its nose. The player does the same with A/D.
- **The firing arc while placing:** the build ghost of any gun draws its arc as a wedge (the sketch's colours: red fixed, yellow swivel, blue turret). The hover card names the aim class and the arc.

## 7. Visual language (adds to ART_STYLE.md)
- **The silhouette is the aim class:**
  - fixed is rectangular, with a sleeve and bracing;
  - swivel is a half-round bulge on a yoke, with a painted rail track on the hull face;
  - a turret is a full ring (an octagon at 16 px per cell), a compact head and a sensor eye;
  - point defence is a small dome with twin short barrels and a radar eye.
- **Size is weight:** a heavier version has a thicker sleeve and more bracing, in the same silhouette family. Tiers grow by adding parts (rule 9 of the art bible).
- **Version add-ons**, so a version reads at a glance:
  - light: smaller, with one short barrel;
  - heavy: a doubled sleeve, side braces and a muzzle brake;
  - burst: 2-3 barrels side by side, with staggered recoil;
  - chain: a rotary cluster of 3-4 barrels, with a spin animation tied to the steps;
  - charge: 3 capacitor rings on the barrel, lit one by one;
  - long: an extended barrel with a cooling fin row;
  - lance: an armoured spinal sleeve with rings of the family colour;
  - pod: hatch lids over tubes that open as it fires.
- **Lines:** as the art bible: scrap, standard and neon. Race versions take the race's ship palette (the livery) on their accents.
- **Modules, not one-offs:** the art is composed from hand-drawn modules in `art/_src`.
  - **Bases:** a ring base in 2 and 3 cells, a sponson, casemate housings at 2, 4 and 6 cells wide, a strip housing, a heavy housing, a spinal sleeve and a pod plate.
  - **Barrels:** single, twin, triple, rotary, capacitor, long, lance and PD twin.
  - Lines and families recolour the modules, and a gun is a recipe of modules. The quality stays even and the new guns are cheap to add.
- **States:** on, off, damaged and disabled, as the art bible (outside halves are scorched and dented, never shattered). Plus firing:
  - recoil (the barrel slides back 2 px);
  - the family muzzle flash on the glow layer;
  - chain spin, charge rings, PD tracking.
- **Shots and impacts** per family, as today (`art/projectiles/<kind>`). Versions scale and recolour: heavy is a bigger bolt, burst is smaller pellets, a lance is a thick beam.
- **Review gate:** a labelled 3x preview sheet of one gun per shape class in each line, mounted through a wall in context, goes to the lead and then the owner before the rest are drawn.

## 8. The existing guns, reshaped
Each keeps its **breech** size (so ship interiors do not move) and its numbers, except the aim class where it says. Only the outside half changes.
- **Point turret** (2x2): Concord Point Turret, Rattle Burst, Sovereign Turret, Twitch Cannon, Drone Picket (PD), Glimmer Turret, Flak Screen (PD).
- **Dome turret** (3x3): Leech Laser, Siren Ion, Flare Turret, Spark Lattice, Tesla Picket, Barge Flak, Mist Projector, Pollen Turret.
- **Sponson** (3x2, swivel 180, share 0.8 with damage scaled so the dealt damage stays as today): Pumice Flak.
- **Long barrel** (2x4): Concord Railgun, Gilded Lance, Heat Lance, Prism Lens, Pyre Lance, Steam Lance, Breach Harpoon, Grapple Harpoon.
- **Heavy cannon** (4x3): Shrapnel Cannon (already), Quarry Driver, Slug Mortar, Tithe Gun.
- **Flush pod** (4x1): Volley Rack, Hive Swarm Launcher, Rot Pod, Market Missile.
- **Broadside battery** (6x2): Scrap Shotgun, Chitin Thrower.
- **Casemate** (4x2, unchanged): Laser Mk1-2, Pulse Mk1-2, Ion Blast, Artemis, Bolt Thrower, Magma Spitter, Cinder Mortar, Arc Hammer, Bog Mortar, Spore Cannon, Refractor.
- **Saves:** a saved mount is re-planned from its inside half (Mounts.from_inside). If the new outside half doesn't fit, the gun goes back to cargo with a log line ("The Railgun no longer fits there: it is in the hold"). Bump the save version.
- **Designs:** shipgen places by shape, and the hand-made designs (starters, flagships, data/ships, packs) are re-planned and checked by a test.

## 9. Balance
- **Value of a gun** = effective dps (damage x share x shots / cooldown, x hit chance) x a range factor x the aim factor. Its budget is tier x shape cost.
- **The bench** (`tests/tool_standoff.gd` and the Threat rating): every new gun against its base at the same tier, in fights against the stage's enemy mix. A version lands within ±15% of its tier's value, unless the design says otherwise (lance, relics).
- **No dominant pick:**
  - for each tier, the best gun on the bench wins at most 60% against the median gun of that tier;
  - every version has a counter that the bench shows (PD against missiles and slugs, shields against beams and lasers, armour against flak and pulse).
- **Enemies use them:**
  - **By shape:** shipgen places broadsides on the flanks, spinals on the keel, and PD near the middle of each side.
  - **By style:** each ship style weights families and versions (Kett burst and swarm, Basalt heavy, Grundl broadside, Prismatic charge, Fenn chain, Human long and PD). Enemy tables pick by tier.

## 10. Where guns come from
- **Mk I bases** are known from the start, as today.
- **Versions are blueprints:**
  - found in scans, events and boarding loot, and sold by shops (more often in their family's regions);
  - race versions are at the race's traders and in its homeland;
  - relics are found only.
- **The crafting screen** shows them as picture cards (the craft-screen work).

## 11. Plan
- **G0, design and art samples** (this doc, plus the review sheet of section 7): lead, then the owner.
- **G1a, shapes and aim in code:**
  - any outside size end to end: placement, slopes, hits, rams, the build ghost and arc, the hover card;
  - the swivel class;
  - reshape the existing guns (section 8) and the save migration;
  - shipgen by shape, the hand designs re-planned;
  - broadside passes in the pilot AI;
  - PD by tier on today's intercept.
- **G1b, art:** the modules and all existing guns in their new shapes, after the review gate. Only `art/_src` and `art/components`.
- **G2, versions:** chain and charge, about 39 new guns in a pack with recipes, sources, enemy use and art from the G1b modules, and the bench. After G1a and G1b.
  - The first list:
    - Laser: Light, Mk3, Burst, Chain, Heavy, Long, Lance.
    - Pulse: Light, Mk3, Broadside, Chain, Heavy.
    - Ion: Needle (long), Mk2, Heavy, Charge.
    - Flak: Turret (dome), Mk2, Heavy, Broadside.
    - Missile: Pod, Artemis Mk2, Swarm Pod, Torpedo (heavy).
    - Beam: Light (sponson), Mk2, Long, Spinal.
    - Slug: Slug Gun, Mortar, Rail (long), Chain Slug, Spinal Rail.
    - Point defence: Mk I-III.
    - Broadside: Gun Strip, Battery, Heavy Battery.

## 12. G2 as built (the 39 guns, the bench)

### Chain and charge
- **Chain** (`chain {steps, cut, decay_s}`, weapons.gd): a volley fired within the last cooldown plus 1.5 s adds a step (up to `steps`), and each step cuts the cooldown by `cut`, one after the other (3 steps at 20%: x0.512). Steps fall away one a second once the gun has been idle `decay_s`. The data cooldown is the first volley's (the template's x1.3); a gun that stays on target averages 0.62 of it.
- **Charge** (`charge {max, gap_s}`): a gun that is ready and not firing stores a volley each cooldown, up to `max`. A fire order (the player's key, or a turret's or swivel's autofire) fires the volley in the barrel and releases every stored one `gap_s` apart; the cooldown starts after the last. So a full Charge Ion fires 1 + 3 volleys. The pilot AI and the autofire only give the order when the gun holds `max` volleys or the target's shield is down (`Weapons.holds_charge`).
- **State for the UI and the art:** `chain_steps(arena, ship_idx, uid)`, `chain_max(def)`, `charges(arena, ship_idx, uid)`, `charge_max(def)`. The barrel's `spin` animation turns 1.5 turns a second per step (the `spin` art has 4 frames); the `charge` frame shows the stored count. The weapon bar draws the pips from the same accessors.

### The value model and the bases
Value = fixed-equivalent damage x shots (x a beam's seconds) / cooldown (a chain gun's mean over a fight, x0.62; a charge gun x0.97) x (range / 900)^0.35 x (1 + 0.06 pierce) x (1 + 0.04 splash) x 1.1 for a gun that passes shields (tests/gun_value.gd). It is read against the base of the gun's family at its tier. The class share is not in the model: a swivel (0.8) and a turret (0.6) pay it in the fight, and the bench shows what that costs.

| family | tier 1 | tier 2 | tier 3 |
|---|---|---|---|
| laser | laser_mk1 | laser_mk2 | laser_mk3 (new: 6.75 / 1.55 s, range 1100) |
| pulse | pulse_mk1 | pulse_mk2 | pulse_mk3 (new: 6.75 / 2.0 s, range 1000) |
| ion | ion_blast_mk1 | ion_mk2 (new: 2.4 / 4.65 s) | notional: 3.9 / 4.5 s, range 1000 |
| flak | shrapnel_cannon_scrap | flak_mk2 (new: 2.5 x 6 / 3.1 s) | notional: 3.8 x 6 / 2.7 s |
| missile | artemis_mk1 | artemis_mk2 (new: 5.8 / 6.0 s) | notional: 9 / 5.5 s |
| beam | heat_lance_neon | beam_mk2 (new: 6 /s for 1.8 s / 9.3 s) | notional: 8.5 /s for 2 s / 8.7 s |
| **slug** (new family) | **slug_gun: 4 / 3.0 s, range 850, pierce 1, 650 px/s** | notional: 6.5 / 2.7 s | notional: 10.5 / 2.58 s |
| **point defence** (new) | pd_mk1: 60%, 1.2 s, intercept 350 px | pd_mk2: 70%, 0.8 s, 400 px | pd_mk3: 80%, 0.5 s, 450 px |

The notional tiers step the laser's way (x1.8, then x3.05). Point defence has no offence value: its numbers are the tier (the intercept rate is 0.5, 0.9 and 1.6 shots a second) and its damage to ships is 0.5 to 1 (a rapid turret, so 0.4 to 0.8 s cooldown for Mk II and III).

### The final numbers
`damage` is the fixed equivalent (the entry); a swivel deals 0.8 of it and a turret 0.6. `model` is the value model against the base, `bench` the fight value (below) against the same base.

| id | damage | x | every s | range | aim, arc/gimbal | power | tier | model | bench |
|---|---|---|---|---|---|---|---|---|---|
| laser_light | 2 | 1 | 1.3 | 900 | turret 270 deg | -1 | 1 | 1.08 | 0.80 |
| laser_mk3 | 6.75 | 1 | 1.55 | 1100 | fixed +-5 deg | -4 | 3 | 1.00 | 1.00 (base) |
| laser_burst | 1.95 | 3 | 2.2 | 1000 | fixed +-20 deg | -3 | 2 | 1.03 | 0.99 |
| laser_chain | 3.6 | 1 | 2.275 | 1000 | fixed +-5 deg chain 3 | -3 | 2 | 0.99 | 1.02 |
| laser_heavy | 7.7 | 1 | 2.9 | 1000 | fixed +-4 deg | -4 | 2 | 1.09 | 0.96 |
| laser_long | 4.5 | 1 | 2.1 | 1400 | fixed +-3 deg | -3 | 2 | 0.94 | 1.03 |
| laser_lance | 11 | 1 | 3.5 | 1650 | fixed +-2 deg | -5 | 3 | 0.93 | 1.18 |
| pulse_light | 1 | 1 | 0.8 | 700 | turret 270 deg | -1 | 1 | 1.05 | 0.85 |
| pulse_mk3 | 6.75 | 1 | 2 | 1000 | fixed +-5 deg | -4 | 3 | 1.00 | 1.00 (base) |
| pulse_battery | 1.95 | 3 | 2.9 | 900 | fixed +-20 deg | -3 | 2 | 1.03 | 1.12 |
| pulse_chain | 4.2 | 1 | 3 | 900 | swivel 150 deg chain 3 | -3 | 2 | 1.15 | 0.94 |
| pulse_heavy | 11.5 | 1 | 3.3 | 1000 | fixed +-4 deg | -5 | 3 | 1.09 | 0.94 |
| ion_needle | 2.6 | 1 | 5.6 | 1330 | fixed +-3 deg | -3 | 2 | 1.01 | 1.04 |
| ion_mk2 | 2.4 | 1 | 4.65 | 950 | fixed +-5 deg | -3 | 2 | 1.00 | 1.00 (base) |
| ion_heavy | 6.4 | 1 | 7.3 | 1000 | fixed +-4 deg | -5 | 3 | 1.07 | n/a |
| ion_charge | 3 | 1 | 5.1 | 950 | swivel 150 deg charge 3 | -3 | 2 | 1.17 | 0.82 |
| flak_turret | 1.2 | 6 | 2.64 | 510 | turret 270 deg | -1 | 1 | 0.94 | 0.80 |
| flak_mk2 | 2.5 | 6 | 3.1 | 620 | fixed +-5 deg | -3 | 2 | 1.00 | 1.00 (base) |
| flak_heavy | 6.2 | 6 | 4.4 | 650 | fixed +-4 deg | -5 | 3 | 1.06 | n/a |
| flak_battery | 1.85 | 12 | 3.9 | 540 | fixed +-20 deg | -3 | 2 | 1.12 | 0.88 |
| missile_pod | 2.8 | 1 | 4.4 | 1020 | fixed +-5 deg | -1 | 1 | 1.12 | 0.70 |
| artemis_mk2 | 5.8 | 1 | 6 | 1250 | fixed +-5 deg | -3 | 2 | 1.00 | 1.00 (base) |
| swarm_pod | 2.8 | 6 | 7 | 1100 | fixed +-5 deg | -3 | 2 | 2.28 | 0.69 |
| torpedo | 14.5 | 1 | 8.8 | 1300 | fixed +-4 deg | -5 | 3 | 1.08 | n/a |
| beam_light | 3.2 | 1 | 6.3 | 595 | swivel 150 deg | -2 | 1 | 1.12 | 0.77 |
| beam_mk2 | 6 | 1 | 9.3 | 800 | fixed +-5 deg | -4 | 2 | 1.00 | 1.00 (base) |
| beam_long | 5.3 | 1 | 11.2 | 1120 | fixed +-3 deg | -4 | 2 | 0.83 | 0.98 |
| beam_spinal | 13 | 1 | 15 | 1350 | fixed +-2 deg | -6 | 3 | 1.14 | n/a |
| slug_gun | 4 | 1 | 3 | 850 | fixed +-5 deg | -2 | 1 | 1.00 | 1.00 (base) |
| slug_mortar | 3.6 | 1 | 3.2 | 750 | fixed +-5 deg | -2 | 1 | 0.79 | 1.24 |
| slug_rail | 7 | 1 | 3.25 | 1330 | fixed +-3 deg | -4 | 2 | 1.01 | n/a |
| slug_chain | 5.2 | 1 | 3.5 | 950 | swivel 150 deg chain 3 | -3 | 2 | 1.00 | n/a |
| slug_spinal | 21 | 1 | 5.8 | 1575 | fixed +-2 deg charge 2 | -6 | 3 | 1.18 | n/a |
| pd_mk1 | 0.5 | 1 | 1.2 | 600 | turret 300 deg | -2 | 1 | - | n/a |
| pd_mk2 | 1 | 1 | 0.8 | 640 | turret 300 deg | -3 | 2 | - | n/a |
| pd_mk3 | 1 | 1 | 0.5 | 680 | turret 300 deg | -4 | 3 | - | n/a |
| gun_strip | 0.5 | 5 | 3.3 | 750 | fixed +-20 deg | -2 | 1 | 0.65 | 1.12 |
| laser_strip | 1.15 | 5 | 2.2 | 1000 | fixed +-20 deg | -3 | 2 | 1.02 | 1.05 |
| heavy_battery | 7.5 | 3 | 5.2 | 950 | fixed +-20 deg | -5 | 3 | 1.08 | n/a |


"n/a" in the bench column: the base is notional (no gun to fight with), so the gun is held to the model. The guns the model misreads are held to their bench value instead (tests/gun_value.gd, BENCH): the lights (0.7 to 1.0 by design), the swarm pod (six small blasts deal far less than the model says), the mortar (explosive splash does well against scrap plate), the gun strip, the Pulse Chain, the Charge Ion and the Long Beam.

### The bench (tests/tool_gun_bench.gd)
- **solo:** each gun (3 copies) fires for 60 s at stationary generated enemies of its tier, 6 plain and 6 shielded, from 0.65 x its range, the shooter sweeping its aim across the hull; the damage dealt to hull and parts is compared with its family base's. Ion does no hull damage, so its value is the share of the target's shield layers it keeps down. 60 s is long enough to strip the facing hull, so the figure saturates for strong guns: read it as a coarse check (about +-10%), not a dps.
- **pairs:** each version against its family base on identical hulls, 3 copies each, 60 s, the hull with more structure left wins (a margin under 5% is a draw). A deterministic race exaggerates small edges (a gun 5% better wins nearly always).
- **counters:** 3 point-defence guns of the tier on the target hull, shielded hulls against plain, and the plating table.

| tier | gun | against | win rate (a margin under 5% of the hull is a draw) |
|---|---|---|---|
| 1 | beam_light | heat_lance_neon | 4% |
| 1 | flak_turret | shrapnel_cannon_scrap | 0% |
| 1 | gun_strip | pulse_mk1 | 46% |
| 1 | laser_light | laser_mk1 | 50% |
| 1 | missile_pod | artemis_mk1 | 0% |
| 1 | pulse_light | pulse_mk1 | 0% |
| 1 | slug_mortar | slug_gun | 8% |
| 2 | beam_long | beam_mk2 | 79% |
| 2 | flak_battery | flak_mk2 | 0% |
| 2 | laser_burst | laser_mk2 | 50% |
| 2 | laser_chain | laser_mk2 | 50% |
| 2 | laser_heavy | laser_mk2 | 42% |
| 2 | laser_long | laser_mk2 | 100% |
| 2 | laser_strip | laser_mk2 | 50% |
| 2 | pulse_battery | pulse_mk2 | 54% |
| 2 | pulse_chain | pulse_mk2 | 50% |
| 2 | swarm_pod | artemis_mk2 | 8% |
| 3 | laser_lance | laser_mk3 | 62% |
| 3 | pulse_heavy | pulse_mk3 | 50% |

**Dominance.** Within a family no version is a dominant pick: the fight values lie between 0.7 and 1.25 of the base (the lances at 1.18), and head to head the versions win between 0% and 62% (a draw band of 5%), except Laser Long and Long Beam, which win their duels (their range does not show in a duel at one distance but their pierce and fire chance do; in solo they are at 1.03 and 0.98). Across families the existing guns decide: at every tier the Laser (laser_mk1/2/3) deals the most (about 135, 216 and 425 hp in 60 s against 70 to 105 for the other families at tier 1, 115 to 167 at tier 2 and 220 to 360 at tier 3), so "the best gun wins at most 60% against the median gun" does not hold across families and cannot be tuned here without changing existing guns. The new guns are tuned to their own families.

**Counters** (damage with 3 point-defence guns of the tier on the target, and on shielded hulls, as a share of the undefended plain hull):

| gun | family | no counter (hp) | with 3 PD Mk of its tier | share left | on shielded hulls vs plain |
|---|---|---|---|---|---|
| artemis_mk1 | missile | 97.5 | 52.2 | 54% | 89% |
| beam_light | beam | 59.5 | 59.5 | 100% | 66% |
| flak_turret | flak | 68.9 | 68.9 | 100% | 55% |
| gun_strip | pulse | 106.4 | 106.4 | 100% | 73% |
| heat_lance_neon | beam | 81.8 | 81.8 | 100% | 57% |
| ion_blast_mk1 | ion | 0.0 | 0.0 | 0% | 0% |
| laser_light | laser | 120.4 | 120.4 | 100% | 80% |
| laser_mk1 | laser | 142.7 | 142.7 | 100% | 90% |
| missile_pod | missile | 70.2 | 52.5 | 75% | 83% |
| pulse_light | pulse | 82.6 | 82.6 | 100% | 68% |
| pulse_mk1 | pulse | 99.3 | 99.3 | 100% | 65% |
| shrapnel_cannon_scrap | flak | 86.4 | 86.4 | 100% | 54% |
| slug_gun | slug | 100.6 | 100.6 | 100% | 76% |
| slug_mortar | slug | 132.0 | 88.2 | 67% | 68% |
| artemis_mk2 | missile | 149.6 | 2.9 | 2% | 100% |
| beam_long | beam | 155.3 | 155.3 | 100% | 92% |
| beam_mk2 | beam | 146.7 | 146.7 | 100% | 87% |
| flak_battery | flak | 104.9 | 104.9 | 100% | 93% |
| flak_mk2 | flak | 118.9 | 118.9 | 100% | 94% |
| ion_charge | ion | 0.0 | 0.0 | 0% | 0% |
| ion_mk2 | ion | 0.0 | 0.0 | 0% | 0% |
| ion_needle | ion | 0.0 | 0.0 | 0% | 0% |
| laser_burst | laser | 211.8 | 211.8 | 100% | 103% |
| laser_chain | laser | 220.5 | 220.5 | 100% | 99% |
| laser_heavy | laser | 211.2 | 211.2 | 100% | 97% |
| laser_long | laser | 237.0 | 237.0 | 100% | 89% |
| laser_mk2 | laser | 218.3 | 218.3 | 100% | 98% |
| laser_strip | laser | 222.8 | 222.8 | 100% | 104% |
| pulse_battery | pulse | 189.2 | 189.2 | 100% | 97% |
| pulse_chain | pulse | 165.1 | 165.1 | 100% | 89% |
| pulse_mk2 | pulse | 171.8 | 171.8 | 100% | 94% |
| slug_chain | slug | 163.2 | 163.2 | 100% | 92% |
| slug_rail | slug | 174.8 | 174.8 | 100% | 88% |
| swarm_pod | missile | 97.9 | 99.4 | 101% | 96% |
| beam_spinal | beam | 312.0 | 312.0 | 100% | 85% |
| flak_heavy | flak | 427.3 | 427.3 | 100% | 68% |
| heavy_battery | slug | 344.3 | 193.9 | 56% | 72% |
| ion_heavy | ion | 0.0 | 0.0 | 0% | 0% |
| laser_lance | laser | 567.1 | 567.1 | 100% | 77% |
| laser_mk3 | laser | 479.3 | 479.3 | 100% | 77% |
| pulse_heavy | pulse | 248.2 | 248.2 | 100% | 69% |
| pulse_mk3 | pulse | 259.3 | 259.3 | 100% | 72% |
| slug_spinal | slug | 137.6 | 137.6 | 100% | 60% |
| torpedo | missile | 332.4 | 0.0 | 0% | 80% |

- **Point defence** takes the missiles: Artemis Mk II 0%, Torpedo about 30%, Artemis Mk I about 50% of their damage get through at tiers 1 to 3, the slow shells less (Mortar 73%, Heavy Battery 55%), and a fast bolt or laser not at all. The Swarm Pod keeps its damage (98%): six missiles outrun a point defence that has to pick them one at a time.
- **Shields** take the beams and lasers at tier 1 (beam 46 to 66%, laser 59 to 67%) and the heavy lasers, pulses and slugs at tier 3 (60 to 76%); missiles pass them (80 to 100%).
- **Armour** (data/tiles.json): heavy armour lets 60% of kinetic through (flak, slug, harpoons), titanium 80%, ram plating 40%; ablative plating 50% of energy (laser, pulse, beam); scrap plate takes 1.5x explosive.

### Where the guns come from
- Known from the start: `slug_gun` and `pd_mk1` (the pack recipes' `start_known`).
- Blueprints: scans and boarding loot offer the recipe of a part an enemy carries (they rank with the core weapons; tier 3 asks fab level 3, so they come late); sold at the stations of the family's regions (Concord: human_core, grundl_barges, mire_fens; the Clans: kett_hives, gauntling_scrapyards, basalt_quarries, fenn_bazaar; Lumen: emberkin_forges, prismatic_choir, sporeling_groves; the Boneyard: missiles), as `bp:` in the small shops (tier 2 at 360, tier 3 at 640), and in twelve events (`guns_2/events/guns.json`, weight 4 for tier 3 at stage 5 or later).

### Enemy use (200 generated ships per stage, tests/tool_gun_census.gd)
The share of ships that carry each gun. Ships of the race styles weight the versions: Kett burst and swarm (gun strip, flak battery, swarm pod, missile pod), Basalt heavy (mortar, heavy laser, heavy pulse, heavy flak, torpedo), Grundl broadside (flak battery, pulse battery, laser burst, heavy battery), Prismatic charge (charge ion, needle, long beam, spinal rail), Fenn chain (chain laser, pulse and slug), Human long and point defence.

| gun | stage 1 | stage 2 | stage 3 | stage 4 | stage 5 | stage 6 |
|---|---|---|---|---|---|---|
| artemis_mk2 | 0.0% | 0.0% | 1.0% | 2.0% | 1.0% | 1.5% |
| beam_light | 3.5% | 3.0% | 8.0% | 9.0% | 12.5% | 13.0% |
| beam_long | 0.0% | 0.0% | 1.0% | 2.0% | 1.0% | 1.0% |
| beam_mk2 | 0.0% | 0.0% | 1.0% | 0.5% | 0.0% | 1.0% |
| beam_spinal | 0.0% | 0.0% | 0.5% | 0.0% | 0.5% | 0.5% |
| flak_battery | 0.0% | 1.0% | 4.0% | 10.0% | 5.5% | 10.0% |
| flak_heavy | 0.0% | 0.0% | 1.0% | 3.5% | 3.5% | 6.0% |
| flak_mk2 | 0.0% | 0.0% | 2.5% | 3.0% | 2.5% | 3.0% |
| flak_turret | 0.0% | 5.0% | 7.5% | 8.5% | 14.5% | 14.0% |
| gun_strip | 0.0% | 1.0% | 2.5% | 8.5% | 11.0% | 10.5% |
| heavy_battery | 0.0% | 0.0% | 1.5% | 1.5% | 3.0% | 4.0% |
| ion_charge | 0.0% | 3.5% | 8.5% | 12.5% | 14.5% | 16.5% |
| ion_heavy | 0.0% | 0.0% | 0.0% | 0.5% | 0.0% | 1.0% |
| ion_mk2 | 0.0% | 0.0% | 0.0% | 1.0% | 1.0% | 0.5% |
| ion_needle | 0.0% | 1.5% | 7.5% | 8.0% | 11.0% | 7.5% |
| laser_burst | 0.0% | 0.0% | 1.5% | 3.5% | 4.0% | 7.5% |
| laser_chain | 0.0% | 0.0% | 0.5% | 2.0% | 3.0% | 0.5% |
| laser_heavy | 0.0% | 0.0% | 0.0% | 1.5% | 1.5% | 1.0% |
| laser_lance | 0.0% | 0.0% | 2.0% | 2.0% | 2.0% | 1.0% |
| laser_light | 0.0% | 0.5% | 3.5% | 6.0% | 8.0% | 4.5% |
| laser_long | 0.0% | 0.0% | 0.5% | 0.5% | 1.0% | 2.0% |
| laser_mk3 | 0.0% | 0.0% | 1.0% | 1.5% | 1.0% | 1.0% |
| laser_strip | 0.0% | 0.0% | 0.0% | 0.0% | 2.0% | 0.5% |
| missile_pod | 0.0% | 1.5% | 6.0% | 5.0% | 10.0% | 7.0% |
| pd_mk1 | 0.0% | 1.5% | 5.5% | 7.0% | 8.0% | 8.5% |
| pd_mk2 | 0.0% | 0.0% | 3.0% | 5.0% | 7.0% | 7.5% |
| pd_mk3 | 0.0% | 0.0% | 1.0% | 3.5% | 1.5% | 4.5% |
| pulse_battery | 0.0% | 0.0% | 0.5% | 1.5% | 2.0% | 1.0% |
| pulse_chain | 0.0% | 0.0% | 0.0% | 1.5% | 1.5% | 2.0% |
| pulse_heavy | 0.0% | 0.0% | 0.0% | 1.0% | 1.5% | 1.0% |
| pulse_light | 0.0% | 7.5% | 4.0% | 5.0% | 9.0% | 10.0% |
| pulse_mk3 | 0.0% | 0.0% | 0.0% | 0.5% | 0.0% | 0.0% |
| slug_chain | 0.0% | 0.0% | 6.5% | 4.5% | 7.0% | 12.5% |
| slug_gun | 0.0% | 1.0% | 6.0% | 8.0% | 10.5% | 6.0% |
| slug_mortar | 0.0% | 1.0% | 2.5% | 7.0% | 5.5% | 3.5% |
| slug_rail | 0.0% | 0.0% | 2.5% | 1.0% | 2.0% | 2.0% |
| slug_spinal | 0.0% | 0.0% | 0.5% | 1.0% | 1.0% | 0.5% |
| swarm_pod | 0.0% | 0.0% | 1.0% | 1.5% | 2.5% | 2.5% |
| torpedo | 0.0% | 0.0% | 1.0% | 0.0% | 0.0% | 0.5% |
| ships with any new gun | 4% | 28% | 68% | 76% | 85% | 84% |
