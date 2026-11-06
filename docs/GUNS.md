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
- **Fire groups** (owner: "configure and drag weapons to sub categories ... left, right and Q"): four groups, and any gun can go in any of them.
  - **LMB** (amber, a dot), **RMB** (cyan, a ring), **Q** (hot pink `#ff6fb5`, a diamond; lighter than the blue and different in shape, so it holds up without colour) and **AUTO** (soft blue, an arc over a dot).
  - A group fires while its button is held. A turret or swivel in LMB, RMB or Q tracks and fires only then; it holds fire the rest of the time.
  - An **AUTO** gun fires by itself. A turret does as before. A fixed gun in AUTO points its barrel at the foe and fires when the shot bears: the aim is inside its gimbal cone, or the barrel at the edge of the cone still lines up on the foe's hull, and the foe is in range (the enemy pilot's rule, `pilot_ai.gd` `on_hull`). **T** holds every AUTO gun.
  - Defaults with no choice: fixed guns by kind (lasers, bolts, beams LMB; missiles, flak RMB); turrets, swivels and point defence AUTO.
  - **Setting a group:** drag a weapon bar slot (fight) or a dock chip (build mode) to another section; or right-click the slot, the dock chip or the chip on the ship to cycle LMB, RMB, Q, AUTO. The bar always shows the four sections, each with its header; an empty one is a slim drop zone.
  - **Saved** per mount as `group` (1, 2, 3 or 0 for AUTO; absent means the default), components version 8; older saves load with their choice (version 7 held 1 or 2) or the defaults.
  - **E** is the utility ability now (Q was).

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
