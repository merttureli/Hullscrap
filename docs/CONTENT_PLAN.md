# Content plan: built for a 200-hour game (owner and lead, 2026-10-30)

**The owner's direction:**
> FTL was a good 20-hour game; FTL: Multiverse made it a 200-hour game with races, guns, quests and story, on the same mechanics. The more content the better. Keep the game playable while agents keep adding content in the background. Very stable, robust mechanics with unlimited content potential.

So the rule from now on is: **mechanics are a fixed vocabulary, and content is data that composes it.**
- A new race, engine, gun or quest should almost never need code.
- When content wants something the vocabulary can't say, the lead adds **one generic hook** (an effect type, a trait key or an event effect), tested once, that every later piece of content can reuse. We never write a one-off `if id == "..."`.

## 1. Content packs (architecture decision)
- **Core data stays in `data/*.json`**. New content goes into **packs**: `data/packs/<pack_id>/`, holding any of `components.json`, `weapons.json`, `recipes.json`, `items.json`, `materials.json`, `species.json`, `traits.json`, `events/*.json`, `ships/*.json`, `names.json`, `logs.json` and `hand_weapons.json`, plus a `pack.json` (`id`, `name`, `version`, `requires`, `notes`).
- **One loader** (`scripts/data/content.gd`) reads core, then every pack in alphabetical order, and merges them by id.
  - A duplicate id is an error, unless the entry says `"override": true` with a `"reason"`.
  - Every system that reads data reads it through this loader.
- So **parallel content agents never edit the same file**: each writes its own pack. Art stays in `art/` by id (ids are globally unique).
- **`tests/test_content.gd` validates everything**: references (recipes → items, weapons → components, events → ids, species → traits, ships → components), art present for every placeable id, trait and effect keys known, ids unique, and **balance bands** (section 3).
- **`docs/CONTENT_INDEX.md` is generated** (`tests/tool_content_index.gd`): counts and lists per family, line, race and faction, so we can watch the game grow.

## 2. The mechanics vocabulary (what content composes)
- **Component stats** per family (`data/components.json` `_doc`), **lines** (`lines.json` multipliers), **heat**, **reliability**, `unique`, and `mount` (inside and outside halves).
- **Abilities** (`abilities[]`), triggered by key or passive, with:
  - `effects`: today `stat_mult`, `shield_layer`, `charge_mult`, `evasion_add`;
  - `side_effects`: today `drain_o2`, `heat`, `power_spike`, `fire_risk`, `self_damage`;
  - `operator_needs`.
- **New generic effects** to add as content needs them (each one implemented once and tested):
  - `blink` (teleport the ship N px forward);
  - `trail` (drop a hazard behind: fire, ion or mines);
  - `tow` (a tether to a wreck or ship);
  - `ram_mult`;
  - `pierce_shields_on_ram`;
  - `self_repair` (hp/s);
  - `crew_scaling` (a stat × per crew member in the room);
  - `no_malfunction`, `no_overheat`;
  - `jump_range` (nodes per jump);
  - `fuel_mult`;
  - `reveal_enemy` (show enemy interior and crew on the schematic).
- **Crew traits**: a **trait library in `data/traits.json`**, resolved in one place (`scripts/crew/traits.gd`, `TraitSet.of(member)`; its `_doc` and the `##` lines say what each key does). Built: `hp_mult`, `speed_mult`, `o2_use`, `suffocate_mult`, `damage_taken`, `work_mult` (as speed factors), `heal_mult`, `mechanical`, `aura` {o2_per_s, heal_per_s, work_mult}, `station` {power_bonus, manned_mult}, `melee_mult` and `ranged_mult` (kept for on-foot fights), `swarm`, `dries_out`, `ion_stun`. Still to come: `body`, `line_affinity`, the other `aura` and `station` keys, `counter_melee` and the Special list. Every trait is a bag of generic keys:
  - **Body**: `hp_mult`, `speed_mult`, `body` (2 = the normal 2×2; 1 = a small body that fits 1-cell crawlspaces).
  - **Air**: `o2_use` (0 = doesn't breathe), `suffocate_mult`.
  - **Damage taken**: `damage_taken` {fire, no_air, melee, ranged, ion}, plus `ion_stun` (seconds stunned by ion).
  - **Work**: `work_mult` {repair, extinguish, breach, man, restock, craft, heal_others}, and `line_affinity` {line: work_mult} (e.g. faster on scrap parts).
  - **Healing**: `heal_mult` {bed, medbay}, `mechanical` (healed by the repair job, not beds).
  - **Room auras**: `aura` {o2_per_s, heal_per_s, work_mult, heat_per_s, fire_suppress}.
  - **Stations**: `station` {manned_mult, power_bonus, evasion_add}.
  - **Fighting**: `melee_mult`, `ranged_mult`, `counter_melee`.
  - **Special**:
    - `vacuum_walk` (no breach or vacuum penalties);
    - `revive_once`;
    - `split_on_death` (into 2 small bodies that reform);
    - `no_tools` (can't repair or extinguish);
    - `no_suit`;
    - `regen_in_power` (heals in powered rooms);
    - `hull_mend` (slowly repairs adjacent walls and breaches when idle);
    - `heat_speed` (speed scales with room heat);
    - `haggler` (prices −10%);
    - `reveal_enemy`.
- **Event effects** (`docs/CONTENT.md` section 8). Add: `start_quest`, `advance_quest`, `give_unique`, `damage_system`, and `board` (boarding comes with on-foot play).

## 3. Balance bands (content agents fill tables; they don't invent numbers)
`data/balance.json` holds the expected stats per **family × tier** for the Standard line. Lines multiply them (`lines.json`).
- The validator flags any non-unique part more than 20% off its band unless it carries a `quirk` (a trade-off ability or side effect) that explains it.
- Uniques may break bands, but must carry a cost (a side effect, operator needs, or a weakness).

**Engines** (thrust per engine; mass and heat scale the same way):

| tier | Mk1 | Mk2 | Mk3 | Mk4 | Mk5 |
|---|---|---|---|---|---|
| thrust | 10 | 18 | 26 | 36 | 48 |
| power | −2 | −3 | −4 | −5 | −6 |
| hp | 6 | 8 | 10 | 12 | 14 |
| fuel_mult | 1.0 | 1.0 | 1.1 | 1.2 | 1.3 |
| outside half | 4×2 | 4×2 | 4×2 | 4×3 | 4×3 |

Bands for weapons, shields, reactors, O2 and the workshop come in the same table format as each family gets its wave.

## 4. Engines: the catalogue (target ~50; the owner: "many many engines, many levels, special found engines")
**A. Tiered line engines (13)**
- Standard **Concord Thruster** Mk1–Mk5.
- Scrap **Kickjet** Mk1–Mk4: cheap, malfunctions, and Mk3+ has Sputter Boost.
- Neon **Ion Drive** Mk1–Mk4: more thrust, hot, ion-weak, Mk3+ spools faster.

**B. Specialty families, Mk1–Mk3 each (18)**
- **Strafe Jets**: small (2×2 + 2×2 outside), side walls, give A/D strafe.
- **Gyro Ring**: inside-only, no nozzle; adds turn rate, no thrust.
- **Retro Burner**: reverse thrust ×2, for brawlers that back off.
- **Long-Burn Drive**: `fuel_mult` 0.5, thrust 60%; the explorer's engine.
- **Hauler Drive**: a 4×3 outside half, thrust ×1.6, heavy, slow to spool (2 s ramp).
- **Tug Engine**: `tow` ability (Shift): tether a wreck or ship and haul it.

**C. Culture and species engines (8)**, sold where that people trade:
- Basalt **Magma Furnace**: huge thrust, heats its room +30/s, `operator_needs: no_breath|heat_resistant`.
- Emberkin **Pyre Drive**: Afterburner-like, with a `trail` of fire behind you that hurts pursuers.
- Fenn **Twitch Jets**: strafe and turn bonus, fragile.
- Kett **Swarm Pods**: 4 tiny 2×2 engines that count as one system; each pod lost costs 25%.
- Mire **Steam Kettle**: no heat at all, but each burn costs O2 from its room.
- Gauntling **Overclock Drive**: thrust ×1.5 while manned by a `mechanical` crew member.
- Prismatic **Lightsail**: no power, low thrust; while sailing (not thrusting), +1 shield layer.
- Rustfang **Screamer**: `ram_mult` 1.5 while burning, very loud (enemy crew knock on ram).

**D. Uniques, found or from quests (★, 10+)**, one striking ability and a cost each:
- **Gate Shard Drive** (Dead Gate debris): `blink` 300 px (Shift, 20 s cooldown). Ion stuns it for twice as long.
- **The Old Mule** (Ma Gantry's late husband's engine; debt questline): `no_malfunction`, `no_overheat`, Mk2 thrust, and ugly.
- **Comet Tail**: a burning plasma `trail` and `fire_risk` in its own room.
- **Siren Wake** (Lumen anomaly): drops 3 ion mines behind you (Shift).
- **Hollow Spindle** (Hollow wrecks): no power, Mk4 thrust; slowly drains O2 from the **whole ship**.
- **Concord Interceptor Core** (a top-tier Concord bounty): afterburner plus evasion +0.1, `operator_needs: suit`.
- **Phase Coil**: `pierce_shields_on_ram`. Rams go through shields.
- **Dead Gate Spindle** (late quest): `jump_range` 2: jump two nodes for 1 fuel.
- **Choir Resonator**: `crew_scaling` thrust +15% per crew member in the engine room.
- **Starwhale Fin** (a living engine): `self_repair` 0.5 hp/s; eats 1 scrap per jump.

Art: every tier and variant follows the art bible (tiers grow by adding parts). Uniques get a gold-trim accent and a signature silhouette.

## 5. Races: the roster (target **30**; the owner: "loop the races until we reach 30 unique ones")
Each race is **data plus art**:
- traits from the library;
- a body rig (the 4 existing rigs plus new ones);
- a culture or faction, and a home (a station or node type);
- recruit odds, a sidearm, 1–2 signature ship parts;
- ship-name and crew-name lists;
- 3+ events with blue options that use their traits.

| # | race | concept | traits (library keys) |
|---|---|---|---|
| 1 | Human | most of the Drift | none |
| 2 | Basalt | silicon labourers, gate builders' caste | o2_use 0, hp ×1.4, speed ×0.75, heal_others ×0.5 |
| 3 | Emberkin | small, absurdly warm | fire damage ×0.25 |
| 4 | Fenn | quick hands, market runners | repair ×0.6, hp ×0.75, speed ×1.15, haggler |
| 5 | Kett | insect hive-workers | work +25% per other Kett in the room (max +50%), hp ×0.8 |
| 6 | Mire | amphibians, shipboard firefighters | extinguish ×2, fire damage ×0.5; lose hp in hot rooms |
| 7 | Sporeling | walking fungus colonies | aura o2 + heal, speed ×0.8, fire damage ×1.5 |
| 8 | Gauntling | salvage cyborgs | mechanical, o2_use 0.5, ion_stun, repair ×0.8 |
| 9 | Prismatic | Lumen crystal-born | station power_bonus +1, ion damage ×2, melee ×0.5 |
| 10 | Vellum | folded paper-folk | body 1 (crawlspaces), hp ×0.5, speed ×1.2, fire damage ×2 |
| 11 | Grundl | huge haulers | hp ×1.8, speed ×0.7, restock ×2, melee ×2, repair ×1.3 |
| 12 | Oorth | quiet telepaths | reveal_enemy, melee ×0.5 |
| 13 | Drakkin | cold-blooded brawlers | melee ×1.75, hp ×1.2, heat_speed |
| 14 | Wisp | living current | vacuum_walk, o2_use 0, no_tools, station manned ×1.5, ion damage ×2 |
| 15 | Hullkin | barnacle-folk who live on hulls | hull_mend, speed ×0.5, o2_use 0.5 |
| 16 | Lantern | moth-folk pilots | speed ×1.3, station evasion +0.05 at the helm, hp ×0.8 |
| 17 | Revenant | Hollow-touched survivors | o2_use 0, revive_once, bed heal ×0, medbay ×0.5 |
| 18 | Choir | crystal singers | aura work ×1.15 for others, melee ×0.3 |
| 19 | Rattler | scrap gremlins | body 1, scrap line work ×0.5, hp ×0.6 |
| 20 | Tessellate | a swarm of tiny bots | split_on_death, o2_use 0, ion damage ×2 |
| 21 | Sable | boarding specialists | breach (cutting) ×2, ranged ×1.25, hp ×0.9 |
| 22 | Quillback | spined and proud | counter_melee 10, hp ×1.1, no_suit |
| 23 | Kite | born in zero-g | suffocation ×0.5, speed ×1.5 in vacuum rooms, hp ×0.9 |
| 24 | Warden-frame | rebuilt Lumen drones (quest only) | mechanical, o2_use 0, ranged ×1.5, ion damage ×3 |

Rows 25–30 (wave 4): Murrow (mole miners), Siltborn (gas-giant floaters), Corvin (crow scavengers), Brine (crab dockworkers), Echo (mimics) and Ferro (living ferrofluid). The full specs for waves 2–4 are in `docs/waves/races_2_4.md`.

New rigs needed: **small** (Vellum, Rattler, Tessellate fragments), **large** (Grundl, Drakkin), **floating** (Wisp, Lantern wings), **mechanical** (Gauntling, Warden-frame). Each rig can be shared by several races through `_color` masks and head and accessory layers.

## 6. Other content families (same pattern, waves later)
- **Weapons**: ~60. Every line × family × Mk1–Mk3, plus culture guns and uniques; a turret share of about 1 in 4.
- **Shields, reactors, O2, utility**: ~15 each.
- **Hand weapons**: ~40. **Gear**: ~25.
- **Ships**: 3 starters per culture (9), then a starter per race; 30+ enemy designs by tier and faction.
- **Events**: hundreds, by node type, faction, race and quest. **Quests**: chains with flags. **Logs**: hundreds.
- **Places**: stations per faction and race, and the Dead Gates.
- **Mining**: ore types, field types (ice fields, crystal fields, gas giants' rings, Hollow-touched rocks), mining gear per line (CONTENT section 10), and mining contracts.

## 7. The content factory (how waves run)
1. **The lead writes the spec list**: ids, names, family, tier, line, stats from the bands, abilities from the vocabulary, and a one-line concept.
2. **A data agent** builds the pack (`data/packs/<wave>/`) and passes `test_content.gd`.
3. **An art agent** draws every id to the art bible and ships a preview sheet.
4. **A writer** adds blurbs, events with blue options, names and logs in the pack.
5. **The lead reviews and merges, and sends the owner screenshots.** `CONTENT_INDEX.md` updates.
6. Any new hook (an effect type or trait key) is its own small code brief with tests, merged **before** the wave that uses it.

The game must stay playable on `main` after every merge. Content only adds; mechanics change rarely and carefully.

### Adding content
**Make a pack** (one per wave or agent, so nobody edits the same file):
1. A folder `data/packs/<pack_id>/` (lowercase and underscores, e.g. `engines_wave1`). Packs load in alphabetical order after the core files.
2. `pack.json` with `id` (the folder name), `name`, `version`, `requires` (a list of pack ids this one needs, `[]` for none) and `notes`. A missing field is an error.
3. Any of these files, each in the shape of its core file in `data/`: `components.json`, `weapons.json` (an object keyed by component id), `recipes.json`, `items.json`, `materials.json`, `tiles.json`, `species.json`, `traits.json`, `hand_weapons.json`, `factions.json`, `names.json` (name pools are joined), plus `events/*.json` and `ships/<name>.json` (one design per file; its file name is its id). A misspelt file or folder name is an error.
4. Ids are unique across the whole game (a component, a material and an item cannot share one; art is found by id). To change something that exists, write the whole entry again with `"override": true` and a `"reason"`; the later pack replaces the earlier entry.
5. Code reads content only through `scripts/data/content.gd` (`Content.list(kind)`, `Content.events()`, `Content.ships()`, `Content.names()`, or `Content.read(path)` for a loader that takes a path).

**What `tests/test_content.gd` checks** (every message names the file and the id): files parse and ids are unique; pack.json is complete and its `requires` exist; recipes name real components, items and materials; every weapon part has a `weapons` entry and the reverse; abilities use only the keys and effect types listed in `scripts/sim/abilities.gd`; ships use real components and tiles; species use defined traits; the Drift's event validator runs when it exists; and **balance bands** (`data/balance.json`): a non-unique part of a family with bands must be within 20% of its band (after its line's multipliers) unless it has a quirk (a non-empty `abilities` or `side_effects`, or `"quirk": "<why>"`). The art check only reports: the ids with no `art/components/<id>.png` are counted in the test output and listed in `CONTENT_INDEX.md`.

**Run it:**
```
godot --headless --path . --script res://tests/run_tests.gd                # the validator is part of the suite
godot --headless --path . --script res://tests/tool_content_index.gd       # rewrites docs/CONTENT_INDEX.md; commit it
```

**Checklist for a new component:**
1. **Data**: an entry in the pack's `components.json` with every field of the core ones (`id`, `name`, `family`, `line`, `tier`, `size`, `power`, `priority`, `hp`, heat fields, `stats`), and a `weapons.json` entry if it is a weapon.
2. **Recipe**: an entry in `recipes.json` (the recipe id is the part's id), unless the part is `unique` (found or earned).
3. **Art id**: the sheet goes to `art/components/<id>.png` (art bible); until then the part is listed as having no art.
4. **Blurb**: one line of flavour in `blurb`.
5. **Band**: take `power`, `hp` and the main stat from the `data/balance.json` row for its family and tier; if the part must be off the table, give it a quirk (a trade-off) and say why.

## 8. Order from here (updated 2026-10-30: the Raft loop and endings)
1. Merge the running work: two-piece mounts, shields v2, the engine, race and sector art.
2. **The ship redesign**: non-rectangular starters, pirate and rammer (CONTENT 4c).
3. **Sector space** (CONTENT 11), in three briefs: the core logic, then the view, then content (intakes, radar, debris, POI events).
4. **Processing** (CONTENT 12): smelters, steel, alloy and conductor, Forged Steel and Alloy armour; Mk3+ recipes switch to steel.
5. **Engine wave 1** data (its art is in progress) and **race wave 1** data plus trait hooks (its art is in progress).
6. **Mining in sector space** (CONTENT 10 inside 11): rocks, cutting, special motherlode POIs.
7. **Enemy scaling and the balance harness** (CONTENT 14): faction enemy tables, budgets, threat ratings, the AI-vs-AI report. Run it after every content wave.
8. **Endings and landmarks** (CONTENT 13): the Haven chain first (the writer plus a small code brief for the ending screen, score and unlocks), then the Retire ending, the Way Out per faction, and the Hollow tide clock.
9. On foot at POIs (docking, abandoned stations, boarding).
