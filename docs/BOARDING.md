# Boarding (design, lead)
The owner: "We are lacking the gameplay element of boarding and exploring. I want it to be like an Alien game, where you board abandoned stations, fight random people, or talk to people, explore crates and boxes and find blueprints."

Boarding takes the soldier **off the ship and onto another vessel**: a derelict, an abandoned station, a pirate nest, or the wreck of a ship you just beat. It's top-down, on foot, in the dark, with a flashlight and a motion tracker. Quiet, tense and lonely, in Hullscrap's voice.

## Where you can board
- **POIs**: `wreck` (a derelict), `abandoned_station`, `pirate_nest`, and the `wreck` a won fight leaves (`sector.add_wreck`).
- **The trigger**: their events gain a choice **"Board her"**, with the effect `board: {kind}`. A POI you have boarded stays boardable until it is `cleared` (everything opened) or you leave the sector.
- **Kinds**:

| kind | size | inside |
|---|---|---|
| `derelict` | an enemy-ship-sized hull | mostly empty, salvage, now and then one creature |
| `station` | large, 12–20 rooms | scavengers or survivors, terminals, the best chance of blueprints |
| `nest` | medium | hostile pirates and a loot stash |
| `wreck` | your fresh kill | its surviving crew, if any; its parts as loot |

## The site
- **Generated from the POI's seed** with the same tools that make ships: `hullgen.gd` for the outline and `ship_grid.gd` for the grid. Rooms are cut by bulkheads, joined by doors and corridors, so it's a real ship grid.
- **Every room gets a purpose**: quarters, storage, medbay, command, engineering, cargo or airlock. The purpose decides its props and loot.
- **Props** live in a site-only layer: crates, lockers, cabinets, cargo pallets, terminals, bodies, sparking cables, and locked doors (a keycard or a hold-E hack).
- **Darkness**: the site is dark. The soldier carries a **flashlight**, a cone toward the mouse. Some rooms have dim red emergency lights.
- **The motion tracker** (a nod to Alien): a HUD ring that pings anything moving within about 25 cells, with blips by distance and a ping sound. It is the main way you know something is there.

## The soldier aboard
- **Movement**: WASD screen-relative walking, as on the ship.
- **Interacting**: E opens a container (a 1–2 s hold), and a small loot list appears; take all, or pick items.
  - Loot goes straight to the ship's hold.
  - Blueprints are learned at once, with a toast.
  - Logs go to the journal.
- **Crew**:
  - **posted** crew stay aboard;
  - **you may take up to 2 unposted crew**, who follow and help;
  - the drone stays on the ship.
- **Leaving**: walk back to the **airlock** (always marked) and press E.
- **Time**: the sector doesn't tick while you're aboard, so no passing ships come. The Hollow tide's linger clock **does** keep running, so you can't loot forever.

## Combat on foot (stage B2)
- **The player's weapon**: the soldier's sidearm (`data/hand_weapons.json`). Aim with the mouse, LMB fires, R reloads, ammo is limited.
- **Enemies**:
  - scavengers (pistols, flee when hurt);
  - pirates (rifles, push);
  - sentry turrets (stationary);
  - Hollow-touched (slow, polite, melee);
  - **something in the vents**: a fast melee creature that hides, the horror beat, rare.
- **Enemy AI**:
  - idle or patrol, then notice (a sight cone, plus noise when you shoot), then chase, then attack, and flee when hurt;
  - it paths with the crew pathfinder on the site grid.
- **Being downed**:
  - **the soldier** comes to at the airlock, back aboard the ship, hurt. The site is closed. You keep what you took.
  - **crew** who are downed and not revived before you leave are **lost**: crew are precious, and that's the point.

## People (stage B3)
- **Not everyone shoots.** Survivors, hermits, traders and the odd strange one stand in some rooms. E talks: the event panel opens with an event of type `boarding_npc`.
- **What they can do**:
  - trade;
  - tell you where something is;
  - ask for help;
  - join you (rare, and it counts toward the region's crew offer);
  - turn on you.
- **Site themes by region** (a Boneyard scrapyard, a Concord checkpoint, Lumen glass, Clan halls), and boarding-specific events.

## Loot
- **Tables in data**: `data/boarding.json`, by site kind and room purpose.
- **What drops**:
  - materials: scrap, copper, polymer, and now and then titanium, silicon or crystal;
  - parts as cargo items;
  - ammo, credits;
  - fuel (rare);
  - **blueprints**: a station has about one, a nest or derelict now and then;
  - hand weapons and gear (B2);
  - logs, keycards.

## Save
- **You can't save while aboard** ("Can't save aboard another vessel").
- **Quit and Continue** puts you back on your ship at the airlock.
- **The site remembers** what you opened and who you beat, by POI id, in the sector save.

## Stages
1. **B1, the core**:
   - entering and leaving;
   - site generation, props and containers, loot tables;
   - darkness and the flashlight, the motion tracker (empty until B2);
   - exploring, the hold transfer, site memory, the save rules;
   - the `board` effect and the choices on the four POI kinds, the HUD.
2. **B2, combat**: hand weapons, enemies and AI, crew followers, the downed rules, tracker pings, sounds.
3. **B3, people**: NPC talk, boarding events, region themes, balance.
