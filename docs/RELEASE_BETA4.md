# Hullscrap Beta 4.1

Beta 4.1 is a fights, balance and content update on top of Beta 4, from a content audit and a mechanics audit. What it changes comes first; the Beta 4 notes follow. Download it from **GitHub → Actions → beta builds → the latest green run → Artifacts** (Windows, Linux, macOS). The main menu's corner says **Beta 4.1**.

## New in Beta 4.1
### Enemies you can read
- **Race ships and gang liveries.** In a race's home region you meet that race's own ships (about 60% of pirate fights), crewed by that race with its signature parts; the eight factions keep their own livery. Every ship carries an emblem on its hull, a colour for its plating, floor and engines, and dressing outside the hull (mandibles, crystal shards, cargo pods, welded scrap, tarps, fins, lattice spars).
- **Roles.** Gunboats, brawlers, escorts, snipers and haulers: the name line says which ("Kett gunboat"). A poor ship looks patched; a rich one looks fine.
- **Six new ways enemies fight**, each with its own pilot, gear and hull shape. Every faction keeps some of its old roles and flies two of the new ones.
  - **Skirmisher:** a fast, slim dart with swept fins. It hits from the edge of its reach, turns and runs when you close, then comes round again.
  - **Carrier** (from stage 2): a wide deck with a tower to one side. It stays just out of your guns' reach and launches combat drones.
  - **Boarder** (from stage 2): a blunt bow with clamps. It closes fast, throws boarder pods and holds close while its robots are aboard.
  - **Flanker:** a crescent with horns. It goes for your stern quarter and aims at your engines and guns first.
  - **Siege boat:** a long spine lined with racks. It fires long guns and missiles in volleys, then pulls back to reload.
  - **Bulwark** (from stage 2): a slow, stepped fortress with heavy guns. It turns its strongest shield toward you and breaks late.
  - The fight panel's skulls now count a ship's drones and boarder pods.
- **Fewer repeat events.** Once an event has shown this run, it comes up far less often. Three survivor and hermit encounters can now happen on stations too, and a capital's recruiter always has something to say (once you've taken on crew in that region, without offering one).
- **No more skulls before a fight.** Event fight choices, radar markers and exit wardens show the enemy ship itself next to yours, her emblem and her name line; the Ledger warns in words only. The fight panel keeps its skull dots.

### Volley, piercing rounds and shield HP
- **Shields have hit points.** A shield layer is worth shield HP set by its tier (tier 1: 4 HP, tier 2: 7, tier 3: 12). A hit takes its damage off the sector it enters; what is left over goes through to the hull, so a heavy shot bleeds through a weak shield. After a hit a sector waits before it regens (3 s at tier 1, 2 s at tier 3), and a sector knocked to 0 stays down longer (5 s at tier 1, 3 s at tier 3). Ion takes double and locks the regen. The shield diagram and the schematic show each sector's HP.
- **Volley or Ripple, per fire group.** Click a group's header on the weapon bar (or in the build-mode fire dock) to switch it. Ripple is as before: each gun fires when ready. Volley makes the group wait until all its guns are ready (3 s at most) and fire together, so your shield opens once, not once per gun. A ship that relies on its shield wants Volley; a ship with a weak shield does better to spam. Enemy ships volley with their heavier guns.
- **Piercing rounds** for the fast kinetic guns (the Rattle Burst): Alt+click the gun to load them. They pass shields, deal 60% damage, armour blunts them, and they cost a round a shot (10 rounds from scrap and titanium at the fabricator; known from the start; sold in stores). A few late enemies carry them. Point defence never opens your shield.

### Boarding and stations
- **Board the ship you just beat** as she is: her rooms, holes, parts, bodies and survivors. Kill her crew by draining her air and she stays airless.
- **Air on foot**: an airless room needs a sealed suit (EVA suit, exosuit, heat suit). Without one, "Board her" is shut when her airlock is airless, and you loot what's sealed or scrap her.
- **Choose who goes**: the airlock picks the party, or you go alone. A beaten foe leaves a body to loot: rounds, credits, now and then its weapon, rarely a mod or gear.
- **L leaves** a site with one click when nothing is hunting you. A site remembers what you opened.
- **The Hollow tide's clock stops while you're aboard** another vessel.
- **Stations are built from 31 modules**: hubs, spokes, glass tubes, rings, hydroponics, mess halls, labs, a chapel, a brig, hangars, gantries over a gap, breached sections. Every room is furnished for what it is.
- **States**: abandoned, half-active (some sections dark; find the generator and hold E to bring the power back) or operational (lit, people at their posts, friendly guards).
- **Windows to space**: a planet, a gas giant with moons, a nebula, an asteroid field or a distant station.
- **Race-built stations**: one race or a mix, with that race's colours and loot. A Basalt section can run with no air, and an Emberkin section is hot on foot. A race's stations take the colours of its ships.
- **Every race has its own rooms** (40 in all, two for each of the ten main races): a magma hall, a fighting pit, a nectar ward with healing beds, a jury generator to restore, an airless optic cradle, a grand galley round a glowing cauldron, and more.
- **Every homeland has its capital**: a large, operational station of its race alone, with all its race rooms, a race trader (half the shelf is the race's own line, at 0.9x) and a race recruiter. The ten major homelands also hold a **wonder** in space (the Dead Queen-Ship, the Star Forge, the Singing Crystal, the Carved Face, the Scrap Cathedral...), with an event and a race blueprint or gear piece once a run; four of them can be walked.
- **The healing arm** (Medbay Mk2, and the neon Halo Arm Mk3): a medical robot arm that reaches out and heals crew where they stand, 6 or 9 steps away through doors (not walls), so the hurt keep working. It heals the lowest share of health first, the soldier on a tie. Blueprints in stores, boarding loot and two new wreck events.
- **See which button fires which gun**: every gun on your ship wears a chip with its number key, amber with a dot for the left mouse button, cyan with a ring for the right, blue for turrets and swivels that fire by themselves. Holding a button outlines the guns it fires (dim, with the reason, when one cannot); a gun's chip and its weapon bar slot flash together when it fires. The weapon bar shows each gun's picture, grouped by button; hover a slot to light up its gun and arc. Right-click a slot (or a chip in build mode) to move a gun to the other button.
- **Four fire buttons, set by dragging**: LMB (amber), RMB (cyan), **Q** (pink) and AUTO (blue). Drag a gun's slot on the weapon bar, or its chip in the fire-group dock in build mode, to another section; right-click cycles them. Any gun can go in any group: a turret in LMB, RMB or Q fires only on its button, and a fixed gun in AUTO fires by itself when its shot bears. The utility ability moved from Q to **E**. Old saves keep their choices.
- **Guns have shapes**: point and dome turrets (round, all-round), swivel sponsons (one side), casemates, long barrels for rails and lances, broadside batteries for the side walls, heavy cannons, spinal mounts and flat missile pods. Every gun is redrawn in its shape (race guns keep their colours and marks). Placing a gun shows its firing arc (red fixed, yellow swivel, blue turret). Enemy pilots with stronger side guns turn their flank to you; point defence also shoots down slow shells; enemy ships carry their guns by shape. A saved ship keeps its guns (one that no longer fits goes to the hold).
- **Drones**: a **drone bay** (Mk I-III, a 3x3 hangar behind a low 3x1 hatch on any wall) launches one drone at a time that circles the foe, always moving, and fires its family's shot at about half a gun's rate. Pulse, laser, ion, beam and flak drones (tier 1-3, 3 / 5 / 8 hp) and two defence drones that guard your own ship against missiles, slow shells and enemy drones. A launch spends **drone parts** (1, 2 or 3 by tier; sold at stations, cheaper in Kett and Gauntling space, kept in wrecks and boarding loot); the drone is yours for good, the part is not. Point defence, flak and turrets shoot drones down, and so does a shot that crosses one. Choose the loaded kit in build mode (hover a bay and press K, or Alt+click it); the bay is a slot on the weapon bar with its key. About one enemy in four, from stage 2, flies a bay of its own (Kett swarms, Fenn ion drones, Human defence drones). **Limpets and boarders:** fire, poison and heat limpets and boarder pods are thrown by hand (hold the bay's key to see the path your throw will curve along, release to throw): the target's magnet pulls them in, so a shot aimed wide curls round to the side or back rooms. They pass shields and have 2-6 hp, so point defence and flak stop them. A limpet clamps to the hull and burns, poisons or overheats the room behind the wall until it runs out, its wall is shot away, or a crew member scrapes it off from inside; a pod cuts a breach and drops a boarding robot (drill, shock or a heavy pair) that fights your crew or wrecks your systems, and your crew and soldier fight it in turn. Sporelings throw poison, Emberkin fire, Basalt heat, Gauntlings boarders.
- **Picture cards in the build palette and the crafting screen**: each item is its picture and its key numbers (cost, how many held, fixed/swivel/turret on a gun), with the name and description when you hover. The palette lists only what you can place now; the fabricator and smelter list only the blueprints you know (the Blueprints tab counts how many are found).
- **From the playtest notes**: debris pick-ups make a short dry clink that no longer clashes with the music; on-foot guns spread left and right (pistol and rifle about 3 degrees, more while moving, a rifle burst opens up); about half as many guns from bodies and crates; about 3 stores in every 5 sectors, and fewer beacon traders.
- **Fixes from the playtest**: a station's decor no longer shows on the build screen after you leave it; the stars stay up round a ship you board; the build camera centres on your ship (Home too); nobody starts a run standing on a part (the helm included); crawlers drop nothing.
- **Race flagships**: each of the ten major homelands holds one great ship from mid-run on, with its own captain and a trick of its race (a ram bow, a swarm crew, a refracting lattice...). It shows as a beacon with a red ring on the radar and a FLAGSHIP contact card. Beat it or take its surrender for a one-of-a-kind trophy part; staying clear leaves it there. Flagships never flee, and each yields on its own terms.
- **Away-team expeditions**: planets, asteroid bases, ice ruins and gas-giant platforms in sector space. Fly close, press E, pick 1-4 crew (or go alone) and play two or three scenes. The team's race, traits and gear open options; crew can be hurt, captured or lost, with everything they carried.
- **Any crew can join a boarding party**, posted or not; they are back at their posts when you return.
- **Squad orders**: right-click a room on foot to send your followers there (the selected ones, else both; click a card or press 1 / 2 to select, Shift adds). They fight what is in the room, loot every container into the hold (never a locked door, never an airless room without a suit), then hold the room; B calls them back, and at 25% health they fall back on their own. Followers on Follow now close in on a foe they see beyond their pistol's reach instead of standing by.
- **Auto reload on foot**: a magazine that runs dry reloads by itself while the hold has rounds.
- **On-foot fights last longer**: about three foes to a health bar (it was five or more). Scavengers hit harder (9), aim better and call others from further off, so they come two or three at once; armour matters more.
- **Foes on foot are real races.** The crew of a ship you beat are the same race when you board her; a race's section is mostly held by that race; elsewhere foes come from the region. Bodies lie as their race, and a foe's name reads "Kett pirate". Their numbers are the same as before.
- **Enemy ships keep their corridors clear.** A generated ship's parts no longer fill a room wall to wall: every room keeps a walk between its doors that a crew body can use (doors slide along the wall, big parts turn or hug a side, the middle decks are two rows taller). Boarding an enemy, her crew and yours no longer squeeze through parts.
- **Medbays** have working and broken beds, and a room's loot fits the room (the odds of rare items are unchanged).
- **About 30% fewer events** in a sector: each extra contact beyond the sector's own place, its fixed ones, its stores, stations, quests, exits and flagships is dropped about seven times in ten, never below three contacts. The stores and the story beats all stay.
- **Emptier free space**: the contacts that turn up out past a sector's own square, in open space, are about 30% fewer too. The ones that stay keep their place, so a save finds them where they were.
- **Walls that close a loop fill with floor**: place walls (a line, a drag or one more segment) so they enclose empty cells and the inside is floored at once, at the usual floor price. If you cannot pay for the whole floor, nothing is filled and the message says how much scrap it needs. One Ctrl+Z takes the walls and the floor together.

### Starting out
- **Blank Frame** (hangar tab "Your own", the first tab): a pod with a helm, and a hold of parts and hull materials worth the same as the Courier. The run opens in build mode with the tide clock held; you can't launch until the helm and an engine have power and every room is sealed.

### Crew kit and gear
- **I opens the crew kit screen** in flight and in build mode: every crew member's weapons, body and mods, moved around by hand.
- **Gear shows on the crew**: armour and suits are drawn on every race. There are 14 new items, some with a worn trait and three with an active on G (Dash, Brace, Patch).
- **A Blueprints tab** in the crafting panel (C) lists every blueprint you know. With no smelter aboard, the Smelter tab says how to get one (craft a Slag Pot). Hovering a recipe shows what it does, and a click no longer queues it (Enter or a double-click does). The middle mouse button pans the build view.
- **A run starts with 10 fuel** (was 22).
- **The Slag Pot and the other smelters can be crafted from the start** (a starter's saved blueprint list hid every pack's starting blueprints).
- **Rare drift** gives itself away only by its glint: no radar diamond, no toast.

### Fights
- **Fights start 1800 px apart** (was 1200), beyond the longest gun, so there is time to manoeuvre before the first shot.
- **The Rustbucket** carries a Bubble Rig shield in place of its Rattle Burst, and its Bolt Thrower sits in a notch one cell behind the prow, so it is no longer the first thing shot off.
- **Every starter has a spare Reactor Mk1** in its hold.
- **The scrap guns hit harder**: the Rattle Burst does 2 a shot (was 1); the Shrapnel Cannon fires 6 pellets of 2 out to 600 (was 5 of 1.5 out to 500).
- **An ion hit keeps shields down for 5 s** (was 3).
- **A spared ship hands over one part**: taking a surrender opens a short salvage page with one pick and the Scan row, and no strip row. The surrender offer itself no longer includes a part.
- **Fewer enemies run**: Concord ships now surrender as often as they flee, and other pirates surrender more often.
- **The skulls** no longer overrate ships armed with light kinetic guns.
- **Fights end**: an enemy with no working gun surrenders or runs instead of fighting on, one whose jump drive you hold for 10 s surrenders, the Lattice wardens stand aside or withdraw to the gate when beaten, and an enemy volley no longer waits on a gun that cannot bear.
- **Guns last**: every gun is plated and takes 0.4 of a hit, so guns stay in the fight 2.5 times as long on both sides; pilots now wait at most 0.5 s for a safer shield sector, and hold where their turrets reach too.
- **K in play mode is a test-fight page**: pick your ship (a copy of the one you fly, or one of six test ships from "scraped by" to "lucky run") and any enemy (a faction or race x role x stage with a seed, a race flagship, the test pirate or the rammer, or Random), fight it with the real rules, and read the session's results list. The run is never changed.

### Crew and repairs
- **Crew keep their breath**: they take a job in an airless room only if they can finish it and walk out with air to spare. Send someone in yourself (middle click) and they go, with a warning.
- **Lost compartments**: in a fight, a room with 3 or more holes to space (or a fifth of its walls open) is LOST. The crew leave it, and you fix it after the fight or in build mode. Your soldier can still work there.
- **Repairs under fire**: a wall or part hit in the last 5 s repairs at about a third of the speed, on both ships, so an enemy crew no longer mends as fast as one gun hurts.
- **Orders for several crew**: Shift+click or drag a box to select several (Shift+click on the crew bar works too). Middle click a room to split its jobs among them, and **X** spreads them over the damaged rooms.
- **Tab slows a ship fight to a quarter speed** until you press it again: time to give orders. There's no limit on it.
- **Orders stick**: a crew member you send somewhere by hand stays there (the medbay, a repair, a room) and does local work; they no longer walk back to their post on their own. The **Back to posts** button on top of the station bar (left) recalls everyone, and Shift+click a station recalls just its crew member; held crew wear an H pin. Crew now go and revive a downed crewmate first (held ones too), unless the room is airless without a suit, on fire, has a hostile in it, or they are being hurt. Tab also eases the camera in to your ship (your hull fills 70% of the height, 0.3 s) so you can click your crew, and back out when it ends.
- **Save layout and Rebuild**: in build mode (bottom right), **Save layout** remembers the ship as it is. After a fight, **Rebuild** Hull, Parts or Both puts back what is missing at the normal cost: hull before parts, cheap before dear, cargo parts first (else made on the spot from a known blueprint), all as one undo step. It says what it rebuilt and what it was short of. A part made on the spot needs a working fabricator of the recipe's level and tools (else it is listed under Not built); conveyor belts are saved and rebuilt with Parts once unlocked. Save layout says how many cells and parts it kept, Rebuild says "Nothing missing" when there is nothing to do, and the Rebuild buttons are dimmed until a layout is saved.

### Content
- **Boarding**: 10 new discoveries, 2 new hermits and 2 new traders aboard derelicts, and 4 new logs. More derelicts have someone aboard, and suits turn up in engineering and command lockers.
- **Events**:
  - 3 first-week events and 6 new quest fillers;
  - 26 events now wait for stage 4 or later, so the late game has more you haven't seen;
  - regional events come up far more often (about 1 event in 6, was about 1 in 45);
  - a story event you skip comes up less often each time;
  - a new Hollow event deep in the run;
  - fewer people do things "politely".
- **More mods**: in lockers and cabinets, in shops, and dropped by some boarding foes.
- **A plasma rifle in your hold** now arms your boarding soldier (as the Gatekeeper's Lance).
- **A fuel stop in the Boneyard**: Dredgers' Rest.
- **Gun versions**: 39 new guns (light, burst, chain, heavy, long, lance and charge versions of the lasers, pulses, ion, flak, missiles and beams; the new slug and point defence families; broadside batteries, gun strips and spinal mounts). A chain gun fires faster the longer it keeps firing; a charge gun stores volleys while idle and releases them together. Slug Gun and Point Defence Mk I are known from the start; the rest are blueprints found in scans, events, boarding loot and shops, and carried by enemies by tier.
- **The fabricator upgrades in place**: no more building robot arms for level 2. In build mode click the fabricator (or hover it and press U) for a card with the next level, what it opens and its price, then click again to pay. Levels 1 to 4, no blueprints; a ship carries one fabricator, and it is never wrecked, only disabled. Arms and rigs in its room now make crafting 25% faster each (up to +50%); the laser cutter and nanoforge stay tools. Older saves keep the level their modules gave them.
- **One crafting screen, with the upgrade in it**: the Fabricator and Blueprints tabs are one Fabricator tab, grouped by family; a blueprint you know but can't make yet stays in the list, dimmed, and says why. The Upgrade button is in the fabricator's box (cost in icons, red when short). The build-mode click on the fabricator now works on every palette tab (it did nothing on the default Tiles tab). Guns, gear and tools show their own pictures on the cards.
- **Batches**: Queue now takes a count (1, 5, 10, 20, 40, Repeat, or the wheel for 1 to 99) on the fabricator and the smelter. A batch pays one unit at a time and waits, saying what it lacks, while the cargo is short; cancelling gives back the unit in progress. The queue row reads "Titanium 7/20".
- **Smelter upgrade in the Smelter tab**: an Upgrade button swaps in the next smelter (Slag Pot, Mk1, Mk2, Mk3) in place, paying its recipe; it says why when it can't (blueprint, fabricator level, materials, or one more free column of floor).

### Fixed
- **Two Kickjets show one Sputter Boost box** with "x2" (likewise any parts that share an ability key); the starter's lone Bolt Thrower now fires on left-click (a ship whose defaults leave LMB empty puts its guns there; saved choices never move); the fight's top hint line wraps between the two schematics instead of running into the enemy panel's title.
- **Small fixes**: two healing arms no longer stack on one patient when another hurt crew member is in reach; an arm draws no beam through walls (the glow and the turn stay); guns whose shots point defence can stop (missiles, slow shells, mortars, torpedoes) carry a PD CAN STOP tag; a merged "x2" ability box shows READY if any part is ready, else the shortest cooldown.
- **The Slag Pot, Smelter Mk1 and seven more parts have their own art** (they drew as flat blocks): the Slag Pot is a cauldron on legs with slag crusting over it, Smelter Mk1-Mk3 pour one, two and three crucibles into a casting line, the Plasma Forge spins a magenta arc in a bottle, and the Afterburner (a shock-diamond plume), Inertial Dampener, Battering Bow and Ma's Kettle are drawn too. They melt, pour, spin or boil while they have power.
- The debug keys no longer work in the download builds, and F1 lists them only in a debug build.
- The Ledger's first goals and the first-fight tip say where things come from.
- The reactor warning says what it means: "One reactor and no spare. If it's wrecked, you're adrift."
- The Baron's duel no longer unlocks a ship that isn't in the game yet.

Beta 4 saves load in Beta 4.1.

# Beta 4

Boarding, a rebuilt hull, the Ledger, and a balance pass measured by a playtest bot.

## Boarding
- **Board a derelict, an abandoned station, a pirate nest or the wreck of a ship you just beat.** Their events offer "Board her". The soldier goes aboard on foot, in the dark, with a flashlight (F) and a motion tracker.
- **Every site is generated** from real ship parts: quarters, storage, medbays, command, engineering, cargo. Each room's purpose decides what's in it.
- **Loot**: E opens crates, lockers and terminals (a short hold). Keycards open locked doors, or hold E to hack them. Stations are the best place for blueprints.
- **Combat on foot**: LMB fires, R reloads, Q swaps weapons. You meet scavengers, pirates, sentries (hack one from behind to turn it), the Hollow-touched and the crawler. Take up to 2 crew along as followers. A downed crewmate gets back up if you hold E by them for 4 s.
- **Not everyone shoots.** Survivors, hermits, traders and captives stand in some rooms. E talks. There are 32 boarding events tied to the story.
- **Light bolts**: lasers fly as glowing bolts that light the walls they pass. A flare burns for 6 s and lights the room for both sides. An enemy who fires in the dark gives their position away.
- **The fight HUD**: party cards bottom left (hp, weapon, gear, mods); the weapon bar bottom right (ammo, reload, Q).
- **Loadouts**: the airlock is now a loadout screen. Each person gets two weapons, body armour and two mod slots. Kits stay on between boardings. Someone lost aboard loses their kit, and the leave screen warns you first.
- **Mods** (like FTL augments, worn in a kit slot; Mk I–III):
  - **Spotter Cam** shows the rooms next door through the site's cameras.
  - **Salvage Rig** adds +25% / +50% / +100% to every resource stack you open. Mk III also has a chance of an extra rare material. It's very strong, and very rare.
  - **Overcharge Coil** makes shots hit harder. Mk III shots pass through the first body.
- **Leaving**: walk back to the airlock and press E. A site remembers what you opened.

## The hull
- **No hull bar any more.** Every block has its own hp. A fight is decided when enough of a ship's structure is broken.
- **Wrecked parts stay wrecked** until a station repairs them, or your crew, drone and soldier mend the walls.
- **Enemies break sooner**: at a twentieth of their structure lost (it was a tenth), then surrender, flee or fight on as their crew's nature says. Most fights at stages 3–5 now end in one to two minutes, not three.
- **Hollow ghosts fade.** When a ghost ship breaks it doesn't surrender or fight on: it thins back into the Hollow over 6 s (knock out its engines or helm to hold it). A faded ghost counts as a won fight, with nothing to loot. The Hollow's beacon warden still fights to the end.
- **Air** comes from oxygen generators and flows from room to room through blast-valve doors.
- **Doors are easier to walk through.** Their size is the same, but the frame no longer snags you, and you slide into line with the door.

## The Ledger
- **Ma Gantry Loans' guidance program** sits in a small card under the top bar. It shows your next goal for the stage: when to add intakes and guns, when to upgrade the fabricator, when to look for better parts. Click it for the stage checklist, and press L to fold it.
- **First-time tips**, each shown once: building, fights, breaches, stations, blueprints, wardens, boarding, mods and more. **J → Tab** re-reads them.
- **Warnings in amber**: outgunned at a beacon, the stage 3 cliff, a toll you can't pay, low fuel, unspent scrap.
- **Settings → Ledger**: Full, Warnings only or Off. After your first finished run it asks once whether to keep it on.

### Story: the Hollow tide
- **The debt is gone.** No creditor, no payments, no repo crews. The pressure is the Hollow tide that comes out of the gates; the tow (Y) now costs the tide 2 steps.
- **A new opening.** The tide reaches Gantry Rusthold on the first night: take two survivors as crew, help load Ma Gantry's barge, or grab what you can. On your first jump Rusthold goes Hollow.
- **Ma's barge** is a station in every region, toward the exit, with fuel, repairs and the scrap market. Ma calls at each new stage with who fell and where the harbour is.
- **Endings:** Halcyon names who came with you; Retire is now Hold the Line, at Meridian from stage 3. The Ledger is the Rusthold dock office's guidance program. Old saves still load.

## Economy and balance
- **Longer fights, room to flank.** Every ship gun reaches 1.4x as far and its shots fly 1.2x as fast (point defence 1.15x). A pilot holds the range that most of its firepower reaches, not that of its shortest gun, so a wide many-gun ship no longer creeps in for one flak turret. Hulls over 1000 mass turn slower (a 2000-mass ship takes about three times as long to turn 90 degrees), so a quick ship can work round a big one. Flagships yield later (fights of 110 to 150 s).
- **Fuel**: you start with 22. It costs 14 credits, at 24 of 33 stations (6–10 units a visit). Canisters drift by now and then.
- **Small shops** in traders and stores sell rare items, mods and blueprints, among them Laser Mk2, Shield Mk2 and the Assembly Rig.
- **About ten events** can teach a blueprint, at a price.
- **The Scan row** after a fight now offers the blueprint you can actually build next, not the grandest one on the wreck. Boarding blueprints use the same pick.
- **Laser Cutter and Titanium are known from the start**, so the fabricator ladder opens earlier.
- **Rare drift**: crystal, titanium and silicon turn up in the debris now and then. A slow, heavy ship still collects.
- Wardens get stronger from stage 3. If the Ledger says you're outgunned, it means it.

## Sound
- **Adaptive music v2**: explore and battle layers play in sync, so a fight crossfades without restarting. Pieces change by region and faction (Black Box, Concord, the Clans, the Lumen), with "Ledger II" in build mode. Music is muffled while you're aboard another ship.
- **Less hiss**: the static is gone from the music.
- **A bigger sound library**: weapon lines and ten signature guns, region ambience, hazard loops, room tone, machines, footsteps, and boarding sounds (laser shots, impact sizzle, flares, arcs). There's a new **Ambience** volume slider.

## Fixed
- **Breach keys**: R and V answer the breach card even when an event, station, map or other window is open. The window keeps its other keys.
- **Beds and medbays in vacuum**: neither heals someone suffocating in an airless room, so they leave at 40% like anyone else.
- **Sloped walls** draw in their material, cut to the slope, not as flat dark triangles.
- **Far events** are titled with the place's own name (Wreck, Trader...), not the region node's.
- **Slowdown far out**: flight speed doesn't change with distance. The dip QA saw matches an engine out of action (a malfunction or overheating), which the ship's status shows.
- **The Ledger**:
  - an urgent warning (outgunned) is no longer pushed off the card by a lesser one a second later;
  - the toll line comes as soon as you have scrap to sell;
  - the guns goal says guns count once cabled and powered.
- **Layout**:
  - hint toasts no longer cover the sector's place and helm lines;
  - the Ambience label fits the menu;
  - body gear lines fit the loadout;
  - the loadout's mod list shows every mod you hold.
- **F1** lists the Ledger's L key.

## Known issues
- **Starter ships against three-skull pirates at stage 1** come through about 70% of the time in the Rustbucket, 75% in the Courier and 95% in the Prism, measured by a bot; the rest are stalemates.
- **Small overlaps**:
  - the Ledger card hides marker labels near the map's left edge;
  - a tip can cover the start of the fight banner;
  - the craft hint covers the Smelter tab and its "?";
  - the map hint sits over the journal;
  - the Hollow tide clock overlaps the fabricator's corner.
- **Evacuation**: your soldier is player-controlled, so evacuating a room doesn't walk them out.
- Balance is measured by a bot. Tell us where it hurts.

## Saves
Older saves load: crew without a kit get an empty one, and Ledger settings start at Full.
