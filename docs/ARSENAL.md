# Hullscrap arsenal: weapons and parts by culture and species (lead, v1)

Content is **data** (`components.json`, `weapons.json`, new `hand_weapons.json`, `items.json`). Lore and voice come from `LORE.md`.
- Every entry has one **quirk** that changes how you build, crew or fight. No plain "+10%".
- Where you get it:
  - **C** = craftable (with a blueprint);
  - **B** = bought from that people's traders (reputation-gated);
  - **F** = found only (salvage, quests);
  - **★** = unique.

## Hand-held weapons (on-foot combat; layered sprites: `art/items/`)
`hand_weapons.json` fields:
- `class` (arm pose: `pistol`, `rifle`, `heavy`, `melee`, `tool`), `damage`, `damage_type`, `fire_rate`, `range`, `spread`, `ammo`, `mag`, `reload`;
- `special`: `sets_fire`, `stun`, `breach` (damages walls and doors), `knockback`, `pierce`, `repairs`, `ricochet_bonus`.

| People | Weapon | Class | Quirk | Source |
|---|---|---|---|---|
| Human | Service Pistol | pistol | The reliable baseline | C |
| Human | Carbine | rifle | 3-round burst, accurate | C |
| Human | Doorbuster | rifle | Shotgun; close range, **breaks doors** in 2 hits | C |
| Human (Scrapper) | Rivet Gun | tool | Weak gun that **also repairs** walls at half speed | C |
| Human (Scrapper) | Flare Gun | pistol | **Sets fires** where it lands; lights dark derelicts | C |
| Basalt | Quarry Hammer | melee | Huge melee damage, **breaches walls** (boarding tool), slow swing | B |
| Basalt | Slugthrower | heavy | Kinetic, **pierce 2**, never ricochets; heavy, slows the carrier | B |
| Emberkin | Torchgun | heavy | Short flame cone, **sets fires**; Emberkin users don't burn | B |
| Emberkin | Ember Knife | melee | Fast; ignites on hit | B |
| Fenn | Spark Pistol | pistol | **Stuns** (ion), great against Wardens and drones | B |
| Fenn | Multi-tool | tool | Repairs at **2× speed**; a weak cutter in a pinch | B |
| ★ | Gatekeeper's Lance | heavy | A neon beam rifle from a dead gate: **its shots bounce** off walls up to 3 times | F |

**Gear** (outfit and utility slots):
- EVA Suit (C; air supply).
- Combat Vest (C; −25% damage, slower).
- Mag Boots (C; immune to knockback; walk on outer hull during EVA).
- Coolant Pack (B Emberkin; non-Emberkin survive hot rooms).
- ★ Salamander Suit (F; immune to fire, slow).
- ★ Exosuit (F; heavy armour, carries a `heavy` weapon one-handed).

## Ship parts by people (on top of the Scrap, Standard and Neon lines)

### Basalt (gate-builder labour caste: heavy, patient, no air)
- **Mass Driver** (weapon, 4×2, B): a kinetic slug that **pierces 2** and **ignores ricochet**. Slow cooldown. Its recoil pushes your ship backwards (a flight impulse).
- **Grav Anchor** (utility, 2×2, B): an active ability that **stops your ship dead** for 3 s, then pins it in place (ignores knockback). Its operator needs `no_breath` because the room vents while it runs.
- **Stone Plating** (wall material, B): heavy, hp 8, **+20% ricochet chance on slopes**, immune to fire. Ugly and beloved.

### Emberkin (heat-lovers, Lumen workers)
- **Furnace Reactor** (reactor, 4×4, B): **power output scales with its room's heat** (radiators in the room *lower* it). It runs best hot and **sets fires** if crew aren't heat-resistant.
- **Flame Projector** (weapon, 4×2, B): a short-range beam cone that **ignites every room it sweeps**. Useless against shields, devastating once they're down.
- **Heat Sink Plating** (wall material, B): absorbs energy hits as **heat into the adjacent room** instead of hp loss, until the room overheats.

### Fenn (fast, clever, fragile traders)
- **Repair Drone Bay** (utility, 2×2, B): launches 2 tiny drones that **fix breaches from the outside**, even in combat. They can be shot down.
- **Gyro Turret** (weapon, **2×2**, B): **360° arc**, low damage, very high fire rate. Shoots down missiles if set to point defence.
- **Haggler's Scanner** (utility, 2×2, B): shows enemy cargo and **raises salvage yield by 25%**. The Fenn swear it's legal.

### Culture specials
- **Scrapper: Junk Cannon** (weapon, 4×4, C): fires a random item from cargo. Its **damage type depends on what it grabbed** (scrap is kinetic, a plasma cell is energy, a missile is explosive). Hilarious, occasionally devastating.
- **Scrapper: Scrap Recycler** (utility, 4×2, C): turns salvaged wreck parts into scrap and copper onboard.
- **Concord: Point Defence** (weapon, 2×2, C): automatic, shoots down missiles and drones in range. Never fires at ships.
- **Concord: Blast Doors** (door upgrade, C): doors with 3× hp that seal automatically on a breach and resist boarding.
- **Lumen: Prism Splitter** (weapon, 4×2, B): a laser that **splits into 3** when it passes through your own reflective or crystal plating. Build your armour as a lens.
- **Lumen: Phase Coil** (utility, 2×4, F): an active 0.5 s **phase**. Shots pass through the ship. Heavy heat, and ion-locks your own systems for 3 s afterwards.

### The Hollow (late game, found only)
**Echo Engine**, **Null Lattice** and **Hollow Lance**. Systems that run with **no crew and no power**, but slowly drain your crew's health. Designed later.

## Where each people's goods come from
- **Gantry Rusthold** (Clans): Scrapper gear, Human and Basalt recruits.
- **Meridian** (Concord): Mk parts, hull frames, Human recruits.
- **The Prism** (Lumen): Neon parts, Emberkin recruits.
- **Fenn traders** at every market: Fenn gear.
- Reputation unlocks better items at each.
