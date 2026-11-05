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
  - **you may take up to 2 crew**, posted or not, who follow and help; a posted crew member is back at the post when you return;
  - the drone stays on the ship.
- **Leaving**: walk back to the **airlock** (always marked) and press E.
- **Time**: the sector doesn't tick while you're aboard, so no passing ships come, and the Hollow tide's linger clock is held too: time on foot doesn't count against the tide.

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

### B2 as built
Code: `scripts/board/arms.gd` (hand weapons, guns, the hitscan), `foes.gd` (spawning, senses, AI, sentries, the crawler), `party.gd` (followers), `boarding.gd` (the session ties them together, `tick`), `board_view.gd` / `board_hud.gd` (input, drawing, sounds). All numbers are in `data/boarding.json` (`combat`, `enemies`, `spawn`); the tests are `tests/test_boarding_combat.gd`.
- **Keys**: LMB fires, R reloads, Q swaps to the second weapon (a `pistol` or `rifle` item in the hold, found in loot), F is the flashlight. Hold E by a downed crew member (4 s) or behind a sentry (3 s). Rounds are the `hand_ammo` cargo item (the ship starts with 40); what is loaded goes back to the hold on leaving.
- **Shots** are rays: walls and shut doors stop them, a prop in the way stops them half the time, the first body on the line is hit. A foe's aim has an error (`inacc`, x1.3 against a target that is moving), so its hit chance falls with distance on its own.
- **Foes see** in a cone: 4.5 cells in the dark, 8 in a room with an emergency light, 13 when the soldier's beam is on them. A shot or a swing calls every foe within 12 (5) cells. A hunter paths with the crew pathfinder; a hurt scavenger runs for the room farthest from him; a hit pirate goes beside a prop that stands between it and him (and then shows less of itself); sentries sweep, track and can be hacked from behind; the crawler waits in a vent, comes out when he is 7 to 16 cells off in the dark, freezes while his beam is on it, lunges from 4.5 cells, bites twice and goes back to a vent.
- **Down**: the soldier wakes at the airlock with 15% health and the site is closed (its POI is done); loot taken stays. Crew who are down when he leaves are lost (a confirm first; the **Leave** button, L, asks "Leave <name> behind?" with Enter/Esc, and works only when no foe has hunted the party for `leave_quiet_s`, 8 s; it fades 1.5 s and leaves by the same `leave()`, so the site is remembered); the ones standing come home with the health they had.
- **The Hollow** falling while he is aboard: lights flicker, "Visitors: noted.", 2 or 3 hollow-touched appear on the airlock side already hunting him, and the HUD says "The Hollow is here. Get out."

## People (stage B3)
- **Not everyone shoots.** Survivors, hermits, traders and the odd strange one stand in some rooms. E talks: the event panel opens with an event of type `boarding_npc`.
- **What they can do**:
  - trade;
  - tell you where something is;
  - ask for help;
  - join you (rare, and it counts toward the region's crew offer);
  - turn on you.
- **Site themes by region** (a Boneyard scrapyard, a Concord checkpoint, Lumen glass, Clan halls), and boarding-specific events.

### B3 as built
Code: `scripts/board/people.gd` (placing them, the talk, the six effects, the shop, the marks), `themes.gd` (site themes by region), `site.gd` (the theme's props and names, and the discovery marks), `boarding.gd` (the session carries the ops out), `board_view.gd` / `board_hud.gd` (a person to talk to, the goods list, the marks on the HUD), `scripts/ui/event_panel.gd` and `map_view.gd` (the panel opens over the dark and the world stands still until it is done). The writing is the pack `data/packs/boarding_1` (24 `boarding_npc` events, 8 `boarding_site`, 5 logs). Tests: `test_boarding_people.gd`, `test_boarding_events.gd`.
- **Who and how many** (`data/boarding.json` `people`): a station holds someone half the time (a second person one time in eight), a derelict one in five, a wreck nobody (its survivors fight), a nest a captive one time in three. Roles by site: survivor, hermit, trader, scavenger who talks first and the Hollow-touched who talk in stations and derelicts; captives in nests. In a place the Hollow holds the Hollow-touched are five times as likely. They stand six cells or more from the airlock and apart from each other and the foes; the same seed places the same people. A person is a crew species of the region (the theme's list), drawn in a muted palette, and turns to face him within 7 cells.
- **E talks** within 2.4 cells (a person comes before a crate, a door or the hatch, a downed friend before a person). The map opens the event panel on top of the dark, titled "Name, role", and the world stands still. The event is picked once for the person (the campaign's pick by site, role, theme, region and stage; the recruit events keep the region's one free offer and the species gate) and kept, so a second talk is the same page. An outcome that does something spends the person (a closing line from then on), a talk that was only left does not; a trader's goods stay open (1-3 buys, Esc closes).
- **The effects**: `npc_trade` rolls three different things from the tables of the room they stand in (credits never), priced at 1.1 x the cargo value of the stack. `npc_reveal` marks an unopened container (a blueprint's, a keycard's, any, weighted to locked rooms) or a locked door with a pulsing diamond that stays on the HUD, off screen as an arrow, until it is opened. `npc_join` adds a crew member of their species and name. `npc_hostile` puts a foe at their feet, already hunting. `npc_follow` makes them a follower with a sidearm of their own, who stays when he leaves and is no loss if they fall. `npc_leave` sends them to the farthest room. `site_fight` brings foes 5 to 11 cells off, hunting. A shot or a blow at a person turns them (a captive is not a target).
- **Discoveries** (`marks`): a station has 1 to 3 marked spots, a derelict 0 to 2, a nest 0 or 1, a wreck none: a terminal, a body or a strange room. The first step into its room (no foe on the hunt) opens one `boarding_site` event; a faint note shows on a marked terminal or body until then.
- **Themes** (`themes`): the first theme whose region (id or events tag) names the region, else whose faction does: Boneyard scrapyard (`boneyard`, `gauntling_scrapyards`: rust, scrap heaps, scrap tilted up, more scavengers), Concord checkpoint (faction concord: clean, filing racks and terminals, credits and silicon, sentries, an extra log), Lumen glass shrine (faction lumen: crystal clusters, crystal and plasma tilted up, few foes, a Hollow tilt), Clan hall (faction clans: cask racks and trophy cases, rounds and rifles, pirates) and the Hollow's own places. Each has a prop palette, a colour wash, a loot tilt, a foe mix, person names and site names ("Concord Customs Post 7", "Tusk's Hall"). A region of none (the neutral ones) has the plain site. The theme is kept in the sector's memory, so a place stays what it was. A theme never changes the layout.
- **Rounds**: `hand_ammo` is a fabricator recipe, 10 for 4 scrap and 2 copper, known at the start.
- **Music**: the music is muffled aboard (a low-pass on the Music bus); the fight layer comes up through the usual combat mood while a foe is on the hunt (`Audio.mood_inputs` asks the Board view's `fight_music()`), and the muffle stays on.
- **Revisits**: foes left alive come back as they were, the dead stay dead; a person who turned on him is still against him, a person who left, joined or followed is gone, one who was talked to has said their piece, the goods and the marks are as they were.

## Light bolts, the fight HUD, loadouts and mods (stage B4)
- **Shots are light.** The logic is still hitscan (`arms.gd` is unchanged); the view flies a bolt from the muzzle to the hit point at the bolt's speed (35-60 cells a second) and shows the hit when it gets there. Each bolt carries a small light that the walls' occluders shadow, so it lights the walls, the floor and the bodies it passes; a foe's bolt in the dark gives its place away.
- **Heavy weapons** shake the screen a little.
- **Impacts**: a flash and sparks; on a wall a scorch mark that fades in about 20 s; on a body a flash in the bolt's colour.
- **Looks are data** (`data/boarding.json` `bolts`): built in layers, default, the weapon's class, its culture, then its own id. Concord: blue-white lasers. Clans: orange tracers; the flare gun's flare sticks where it lands and burns 6 s. Lumen: the lance is a pale violet beam held 0.15 s. Fenn: the spark pistol is a jittering blue arc. Emberkin: the torchgun is a short flickering flame. Basalt: the slugthrower fires a heavy amber tracer. Melee: a swing arc, no light. Foes: scavengers dirty orange, pirates red, sentries green (the colour of the soldier's weapon once hacked).
- **The flare is logic, not looks** (`boarding.json` `flare`): a flare of the soldier's or his crew's flare gun burns 6 s and lights 4 cells round it; for what a foe sees (`foes.gd`) it counts as an emergency light, so it lights a room for both sides. A wall keeps it in its room. At most 12 burn at once; a scavenger's flare gun is just a gun.
- **Budget**: the lights are pooled, at most 12 bolt, flash or flare lights at once (the oldest drops); only 4 of them cast shadows (the burning flares first, then the newest bolts), because a shadow costs far more than the light (`bolts.shadow_lights`).
- **Sounds** (`audio/_src/sfx/sounds_board.py`): the laser pistol and rifle (Concord and the lance), a bolt biting a wall, the flare's pop and its burn loop, the spark pistol's crackle. The slug weapons keep theirs.
- **The fight HUD** (`board_cards.gd`, `board_loadout.gd`, drawn by `board_hud.gd`): party cards bottom left, the soldier first (head, name, hp bar and number, the weapon, the body gear and the mods, each with a hover line; "DOWN, hold E" with the revive progress), the motion tracker above them; the weapon bar bottom right (the two slots with the item art and the name, the active one lit with the magazine and the reserve, a reload as a progress ring, the Q hint).
- **Loadouts** (`kit.gd`): the airlock's crew picker is the loadout screen ("Boarding party"). It opens first on every boarding, of every kind, even with nobody to take: it lists the crew who can come with their hp, species, gear and the rounds they would carry (a "no suit" tag once the rules mark sealed suits), "N of 2" shows the limit, the number keys toggle crew, **Go alone** (A, Esc) and **Go aboard** (Enter) leave. Pick up to 2 followers, then set for each person two weapons (their species' sidearm or a hand weapon of the hold), one body gear (`basic_armor`, `eva_suit`, `exosuit`, `salamander_suit`, `heat_suit`) and two mods. The same screen is the crew kit screen in flight (I, `crew_kit.gd`, `crew_kit_panel.gd`). What is worn has left the hold and goes back when taken off; the kit is saved on the crew member (`kit` in the crew save; older saves load with none) and stays between boardings. A crew member lost aboard takes the kit with them, and the leave confirm says so. A follower fights with the first weapon of their kit, from rounds of their own: a COPY of the soldier's spare rounds when they go aboard (never fewer than `combat.follower_ammo_min`, 10), nothing taken from the hold; they reload from them, are OUT at none (the card says so, a toast once; a melee follower swings) and what is left is gone when the visit ends. Body gear is drawn on the person (`looks` in `boarding.json`, `PersonDrawer.draw_gear`). A person with `no_suit` is refused body gear, with the reason.
- **Body gear aboard** (`boarding.json` `armor`, the share of the damage taken): `basic_armor` 0.8, `exosuit` 0.65, `salamander_suit` 0.9; the EVA suit and the heat suit 1.0 ("no use aboard"). The wardrobe track (Beta 5) added 14 more (`rigger_harness`, `firefighter_coat`, `medic_sash`, `jump_pack` for everyone; `chitin_plate`, `spore_mantle`, `prism_cloak`, `ballast_rig`, `tank_harness`, `forge_apron`, `traders_coat`, `stone_plates`, `scrap_gauntlets`, `marine_plate` one per tech race). Each has a `gear.<item>` entry: `sealed`, `grants` (trait ids of data/traits.json, merged into the wearer's traits while it is worn, on the ship and on foot: `CrewMember.traits()` reads the kit), `sub` (the short line of its loadout slot) and `line` (the hover), and the numbers read on foot: `hack`, `revive` (speed factors), `mag` (magazine size), `deflect` (the share of energy bolts a wearer throws back: `wear.energy_foes`), `ally_heal` and `ally_r` (hp a second and cells of a spore mantle), and `active` (`actives`: Dash, Brace, Patch, on **G**, with a cooldown the soldier's card shows; `gear_active.gd`). The trait keys added for them: `walk_mult`, `no_knock`, `heat_proof`, `sell_bonus`, `scrap_mult` (data/traits.json `_doc`). Race gear is found in its region's lockers (`regional`: x weight in every table of a site in that region) and sold in that region's station stock; the general four are in the tables, the small shops (`drift.json` `shops.gear`) and a few stations.
- **Who wears what** (`boarding.json` `wear`, `wear.gd`): foes, the people met aboard and the crew of a beaten ship wear body gear (`kit.body`), drawn on them from the art of their own rig (`art/gear/<art id>/<rig>.png`), with its armour and traits. A beaten foe's body holds what it wore (`wear.drop`, 25%; its own roll after the older ones so those do not shift). An enemy's crew in a fight is dressed from the species alone (`Jobs.spawn_enemy_crew`).
- **Mods** (`data/mods.json`, `mods.gd`): each tier is its own cargo item `<mod>_mk1..3` (kind `mod`, slot `kit`), carried by the hold, loot and shops like anything else. A placeholder icon is drawn in code (one colour a mod, 1-3 pips). Ship mods are left to a later stage: the format has room, no ship slot exists.
  - **Spotter Cam** (party; the best one in the party counts): the rooms joined by a door to yours (`site.rooms_near(room, depth)`) show dimly lit as a camera feed, a cool grey-green with scan lines and a CAM mark: their layout, props and whoever stands there. Mk I depth 1, dim. Mk II depth 1, brighter, and a foe standing still in those rooms still pings the tracker. Mk III depth 2. It is a feed, not light: foes do not see you better.
  - **Salvage Rig** (party): every container you open gives more of each stack of materials, rounds and credits: +25%, +50%, +100% (Mk III also a 1 in 3 chance per container of one extra rare material). Fractions are rolled from a stream of the site's seed and the container, so a container gives the same every time. Blueprints, parts and weapons are never multiplied. The loot list shows the bonus as "+3 scrap" in the mod's colour.
  - **Overcharge Coil** (self): the wearer's shots, and swings, do +15%, +30%, +45%; their bolts are wider and brighter; Mk III goes through the first body to the next.
- **Where mods come from**: the `mod` outcome of the command and engineering tables and of the nest's stashes (about one mod per 2 early stations; Mk III is stations only, from stage 4, about one run in three finds one if it boards a station at each of stages 4-8); a trader aboard may carry one (the room's table); the small shops' unique pool has a `mod` kind (weight 1, priced by tier in `drift.json` `shops.mods`).
- **Describe**: `mod` is a coloured keyword (MOD) and an item kind; a mod's hover shows what it does, the numbers of its tier and who they work for. Debug: M in the crafting panel (C) puts the nine mods in the hold (the help panel has no room for a row of it).
- **Tests**: `tests/test_boarding_kit.gd`, plus `test_content` (every mod item validates) and the existing boarding tests.

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
4. **B4, light and kit**: light bolts, the fight HUD, loadouts, mods (Spotter Cam, Salvage Rig, Overcharge Coil).

## Boarding the ship you beat, and air on foot (Beta 4.1)
- **The wreck of a ship you beat is that ship** (`wreck_site.gd`): her grid, doors and rooms, her parts as props, holes where walls were shot away, her dead as bodies, and after a win her crew still on their feet as foes. A captured ship has none. She is stored with the wreck in the sector save (campaign save 13); an older save's wreck is a generated site.
- **Rooms have a pressure** (a beaten ship's is what the fight left). A person without a sealed suit cannot go into an airless room: the door stays shut ("No air past this door. You need a sealed suit."), followers wait at it. The airlock prefers a room with air. When it has none, "Board her" needs a sealed suit (worn or in the hold) and "Go aboard" is refused until it is worn. Suits are found, never given.
- **A beaten foe leaves a body** you open with E: hand ammo, credits, its weapon now and then, rarely a mod or body gear (`foe_loot`).

## Stations built from modules, beds, loot that fits the room (stations step 1)
- **Module stations** (`station_gen.gd`, `data/station_modules.json`; switch `station_gen`: `modules` or `classic`). A station grows from its docking collar, module by module on open connectors (2-wide doors, or 4-wide halls: two doors and a pillar), by weight for its type (outpost, waystation, habitat: the size budget) and by rules: a spoke or a glass tube must lead to a module, the command deck sits behind a security checkpoint (a card door), an observation deck faces open space. Connectors that meet join (loops), the rest close as wall or glass. The same seed gives the same station; one that cannot be built after a few tries is built classic. A station visited before the switch existed stays classic (its memory has no `gen`).
- **States**: abandoned (dark, red emergency lights, breached airless sections, dead doors to hack, scavengers), half (some sections powered: lit or flickering; the rest dark; more dead doors; a few people) and operational (lit and aired throughout; friendly with traders and survivors, or hostile with pirates and sentries). The state and the type are remembered with the visit.
- **Windows** look out on space: the sector's own sky stays up behind the station, and a planet or a gas giant hangs past the observation deck (`station_backdrop.gd`). Light falls in through the glass, so a window is a calm spot in the dark.
- **Glass tubes** are crossings between sections: some lost their air (a sealed suit, or go round), some are watched by a sentry at the far end.
- **Beds** (`beds.gd`, `data/boarding.json` beds): in station medbays (more beds on bigger stations) and in every generated medbay. Hold E by a working bed to heal (5 hp/s); hold E by a hurt follower near a free one and they lie down and heal. Never under fire. Broken beds are dim and spark; most beds on abandoned sites and derelicts are broken.
- **Loot fits the room** (`loot_theme`): the first roll of a container is today's, so every tier (common, rare, part, gear, weapon, ammo, credits, mod) keeps its share; within the tier, items whose tags meet the room's are 3 times as likely (a reactor room: power parts and power blueprints; a medbay: medical; the checkpoint: weapons). On every kind of site.
- **Station interiors** (step 2; `station_fixtures.gd`, `station_races.gd`, `heat_foot.gd`; data `station_fixtures.json`, `station_races.json`, `station_modules.json`): the catalogue is 31 modules (ring segment and corner, hydroponics, mess hall, cargo bay, storage, maintenance crawlway, comms array, laboratory, chapel, brig, water reclamation, hangar, exterior gantry, breached section, generator room, and four race rooms) besides the first eleven. **Fixtures** are the big things in a room (a reactor core, market stalls, bunks, a holo-table): multi-cell, blocking like a prop or walked through, placed by data rules per module, room and room purpose (`wall`, `corner`, `centre`, `free`, `row`; counts scale with room area) from a stream of the seed of their own. A fixture is not a prop, so container ids, slots and loot do not move. After each blocking fixture every door of its room must still reach every other by a 2x2 body and every container and bed must still be reachable, else another place is tried. **State dressing**: dead screens and lamps (`dead`) and toppled furniture (`wreck`) by state. **Power**: a half-active or abandoned station has a generator room; hold E at the generator (`station_modules.json` `power.repair_s`) and its section (every unpowered, unbreached module within `power.reach` modules) is lit and its dead doors open; the visit remembers it. **Guards**: friendly operational stations keep 1 to 2 `guard` people (armed, friendly, they turn on you only when shot). **Backdrops**: planet, gas giant, gas giant with moons, nebula, asteroid field, distant station. **Races**: each station has builder races (`station_races.json`: a home race builds most of its own region's outposts, habitats are mostly mixed, away from home always mixed) and each module is a section of one race. A race changes the skin (tints, lamp colour, glyph, fixture art variants), the people and foes aboard, the loot within the tier (`race_<id>` tags, like a room's tags) and what its body lets a section be: a race that needs no air has operational, lit, airless sections; a power race keeps more of a half-active station lit; a hot race, a reactor and a forge are hot rooms. **Heat on foot** (`heat_foot.gd`): a room's static `heat` (`site.heat_of`, like its air) hurts a `dries_out` person, slows a `heat_speed` one unless `heat_proof` (a Forge Apron), with the ship's numbers; the card shows HOT.
- **Tests**: `tests/test_stations.gd`, `tests/test_beds.gd`, `tests/test_loot_theme.gd`. The map of 8 stations: `tests/tool_station_gallery.gd` (run with a window).
