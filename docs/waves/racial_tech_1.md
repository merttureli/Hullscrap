# Racial tech 1: arsenals for the first 10 races (lead, 2026-10-30)
Spec for track 12 (`docs/CONTENT.md` section 17). Each race has 3 ship weapons, 3 components and 2 hand weapons (Human, Basalt, Emberkin and Fenn already have 3 hand weapons each, so they get no new ones).

**The rule**: each part has a big pro (+30–50% over its tier band) and a real con, and that **race's own traits cancel the con**.
- Numbers start from the tier band (`data/balance.json` for engines; take weapons, shields and reactors from the existing Mk1/Mk2 parts of the same family). Then apply the modifiers listed here.
- Every part has a `quirk` line and a blurb in its culture's voice.
- New effects are marked **[effect]**: they come from the track 12 effects code (acid, spores, shard, sonic, magnetic, frost, corrode) or from existing side effects.
- Each part is a pack `data/packs/tech_<race>/` with components, weapons, recipes (`fab_level` 2, plus key materials for tier 3) and stock in its homeland region.
- Art: hull-mount halves for weapons and engines, plus on-theme projectile and impact art (`art/projectiles/<id>`).

## Human (Concord and Clans: generalists, no trait; their "con" is just cost)
- **Ship weapons**:
  - **Volley Rack** (missile, tier 2): 3 small missiles per salvo. Uses ammo ×1.5.
  - **Concord Railgun** (fixed, tier 3): kinetic pierce 2 at high speed. Charge 1.5×.
  - **Flak Screen** (turret, tier 2): **shoots down enemy missiles** within 300 px; weak against hulls.
- **Components**:
  - **Standard Reactor Plus** (+1 power, +20% cost);
  - **Concord Comms Array** (utility: +10% prices at Concord, radar identify);
  - **Crew Quarters Deluxe** (bed: heals 2×, +5% crew work while rested).

## Basalt (no_breath, tough, slow)
- **Ship weapons**:
  - **Magma Spitter** (fixed, tier 2): **[acid]** damage over time. Its breech room loses 30% air per shot (Basalt don't breathe).
  - **Quarry Driver** (fixed, tier 3): a huge kinetic slug that pierces 3. Its room vents on fire.
  - **Pumice Flak** (turret, tier 2): splash. It needs a crew member manning it **in vacuum** to aim well (×0.5 accuracy if the room has air; Basalt run it airless).
- **Components**:
  - **Vacuum Forge** (reactor): +3 power, and it vents its room.
  - **Stonehide Plating Bay** (utility): the walls of its room get +50% hp, but the room has no O2 supply.
  - **Gravity Anchor** (engine utility): turn rate ×1.5 and ram resistance, but it pulls air from adjacent rooms.

## Emberkin (heat_resistant)
- **Ship weapons**:
  - **Pyre Lance** (beam, tier 2): **sets fires** where it sweeps, and its room runs +40 heat.
  - **Cinder Mortar** (fixed, tier 2): incendiary splash. 15% fire chance in its own room per shot.
  - **Flare Turret** (turret, tier 1): blinding flares (**[sonic]** stun on the enemy crew in the room hit). It overheats fast.
- **Components**:
  - **Pyre Drive** (engine): thrust ×1.5, room +40 heat.
  - **Furnace Core** (reactor): +2 power, room +30 heat.
  - **Hearth Shield** (shield): +1 layer while its room is above 60 heat; it heats the room itself.

## Fenn (fast_repair, fragile, quick)
- **Ship weapons**:
  - **Twitch Cannon** (fixed, tier 2): 40% faster cooldown; malfunction 20% per minute.
  - **Spark Lattice** (turret, tier 2): **[shard]** splinters. Self-damage 0.2 hp/s while firing.
  - **Market Missile** (missile, tier 2): cheap ammo (scrap); 25% duds.
- **Components**:
  - **Haggle Engine** (engine): thrust ×1.3; it breaks on every 3rd overheat.
  - **Jury Reactor** (reactor): +2 power; malfunction 15% per minute.
  - **Quickfix Bay** (utility): repairs ×2 in its room; it draws 2 power.

## Kett (swarm)
- **Ship weapons**:
  - **Hive Swarm Launcher** (missile, tier 2): many tiny drones. Full rate only with 3 crew in its room (×0.4 alone).
  - **Chitin Thrower** (fixed, tier 1): **[shard]** cone. Needs 2 operators.
  - **Drone Picket** (turret, tier 2): intercepts boarders and missiles. Needs 2 crew nearby.
- **Components**:
  - **Hive Battery** (shield): full layers only with 3 operators.
  - **Nest Reactor** (reactor): +1 power per Kett in its room (max +3).
  - **Brood Hold** (utility): Kett heal and work ×1.2 here; others ×0.8.

## Mire (extinguish ×2, fire ×0.5, dries out)
- **Ship weapons**:
  - **Steam Lance** (fixed, tier 2): heavy damage, a 10% fire chance in its room per shot.
  - **Bog Mortar** (fixed, tier 2): **[corrode]** splash.
  - **Mist Projector** (turret, tier 1): **[frost]**. Its room gets wet: −30 heat, and non-Mire crew work ×0.8 in it.
- **Components**:
  - **Rain Shield** (shield): +1 layer, and the ship's fire spread ×1.5 (the steam vents).
  - **Wetwell Reactor** (reactor): +2 power, with fire risk 0.02/s in its room.
  - **Spray Deck** (utility): extinguishes its room instantly every 30 s, but floods it (O2 −20%).

## Sporeling (aura o2 and heal, fire ×1.5)
- **Ship weapons**:
  - **Spore Cannon** (fixed, tier 2): **[spores]** O2 drain in the room hit. It eats O2 in its own room too.
  - **Rot Pod** (missile, tier 2): **[acid]** spreads to neighbouring cells; it needs O2 to grow.
  - **Pollen Turret** (turret, tier 1): **[sonic]**-like sleep on the enemy crew. Its room O2 −20%.
- **Components**:
  - **Bloom Reactor** (reactor): +3 power, cheap, eats its room's O2.
  - **Mycelium Shield** (shield): regrows layers ×1.5, but each layer costs room O2.
  - **Garden Bay** (O2): produces ×2 O2, catches fire easily.

## Gauntling (mechanical, ion_stun, repair ×0.8)
- **Ship weapons**:
  - **Arc Hammer** (fixed, tier 2): an ion-plus-kinetic hybrid. It shocks organic crew in its room (2 hp/s while firing).
  - **Scrap Shotgun** (fixed, tier 1): cheap scrap ammo, **[shard]** cone, 15% jams.
  - **Tesla Picket** (turret, tier 2): ion chains between enemy systems. Its room is shock-hazardous for organics.
- **Components**:
  - **Arc Core** (reactor): +3 power, and it shocks organic crew in its room.
  - **Overclock Engine** (engine): thrust ×1.5 while manned by a mechanical crew member (×1.0 otherwise), and it shocks organics.
  - **Graft Bay** (utility): repairs mechanical crew ×2; organics take 1 hp/s in it.

## Prismatic (power_bonus +1 when manning, ion ×2)
- **Ship weapons**:
  - **Prism Lens** (beam, tier 2): full power only when a Prismatic mans it (×0.5 otherwise).
  - **Refractor** (fixed, tier 2): **[shard]**; its shots split on shields (1 → 3). Ion-weak.
  - **Glimmer Turret** (turret, tier 2): high accuracy; needs a crystal-born operator.
- **Components**:
  - **Lattice Shield** (shield): +2 layers, but ion strips 2 per hit.
  - **Song Reactor** (reactor): +2 power, +1 more per Prismatic in its room; ion shuts it down 2× longer.
  - **Resonance Helm** (helm): evasion +0.1 when a Prismatic is at the helm.

## Grundl (restock ×2, melee ×2, slow, big)
- **Ship weapons**:
  - **Slug Mortar** (fixed, tier 3): huge kinetic hits; empties racks fast (ammo ×3).
  - **Grapple Harpoon** (fixed, tier 2): **[magnetic]** pulls the enemy close. Needs a heavy loader (it reloads ×0.3 unless a Grundl restocks).
  - **Barge Flak** (turret, tier 2): big ammo appetite (ammo ×2).
- **Components**:
  - **Hauler Thrusters** (engine): thrust ×1.6 with heavy mass; needs restocking fuel cells (a Grundl job).
  - **Freight Shield** (shield): +2 layers, recharges only when crew restock its cells.
  - **Cargo Deck** (utility): +50 hold and ammo racks ×2; slow to load without Grundl.

## Hand weapons for the 6 new races (2 each)
- **Kett**: Sting Pistol (pistol), Hive Prod (melee).
- **Mire**: Bubble Rifle (rifle, foam), Hook Gaff (melee).
- **Sporeling**: Spore Puffer (tool, sleep), Thorn Lash (melee).
- **Gauntling**: Rivet Fist (heavy), Arc Welder (tool).
- **Prismatic**: Lens Pistol (pistol), Shard Lance (heavy).
- **Grundl**: Freight Hammer (melee), Chain Gun (heavy).

## Projectile and impact art per race
- **Basalt**: glowing slag, rock shards.
- **Emberkin**: fire plumes, embers.
- **Fenn**: quick sparks, tiny bolts.
- **Kett**: drone swarms, chitin needles.
- **Mire**: steam jets, water bursts.
- **Sporeling**: spore clouds, rot pods.
- **Gauntling**: electric arcs, scrap pellets.
- **Prismatic**: refracted beams, split shards.
- **Grundl**: heavy slugs, harpoon chains.
- **Human**: clean tracers, Concord rail flashes.

Each set uses the family colours, plus the race's own accent.
