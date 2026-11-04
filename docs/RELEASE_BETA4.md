# Hullscrap Beta 4.1

Beta 4.1 is a fights, balance and content update on top of Beta 4, from a content audit and a mechanics audit. What it changes comes first; the Beta 4 notes follow. Download it from **GitHub → Actions → beta builds → the latest green run → Artifacts** (Windows, Linux, macOS). The main menu's corner says **Beta 4.1**.

## New in Beta 4.1
### Enemies you can read
- **Race ships and gang liveries.** In a race's home region you meet that race's own ships (about 60% of pirate fights), crewed by that race with its signature parts; the eight factions keep their own livery. Every ship carries an emblem on its hull, a colour for its plating, floor and engines, and dressing outside the hull (mandibles, crystal shards, cargo pods, welded scrap, tarps, fins, lattice spars).
- **Roles.** Gunboats, brawlers, escorts, snipers and haulers: the name line says which ("Kett gunboat"). A poor ship looks patched; a rich one looks fine.
- **No more skulls before a fight.** Event fight choices, radar markers and exit wardens show the enemy ship itself next to yours, her emblem and her name line; the Ledger warns in words only. The fight panel keeps its skull dots.

### Fights
- **The Rustbucket** carries a Bubble Rig shield in place of its Rattle Burst, and its Bolt Thrower sits in a notch one cell behind the prow, so it is no longer the first thing shot off.
- **Every starter has a spare Reactor Mk1** in its hold.
- **The scrap guns hit harder**: the Rattle Burst does 2 a shot (was 1); the Shrapnel Cannon fires 6 pellets of 2 out to 600 (was 5 of 1.5 out to 500).
- **An ion hit keeps shields down for 5 s** (was 3).
- **A spared ship hands over one part**: taking a surrender opens a short salvage page with one pick and the Scan row, and no strip row. The surrender offer itself no longer includes a part.
- **Fewer enemies run**: Concord ships now surrender as often as they flee, and other pirates surrender more often.
- **The skulls** no longer overrate ships armed with light kinetic guns.

### Crew and repairs
- **Crew keep their breath**: they take a job in an airless room only if they can finish it and walk out with air to spare. Send someone in yourself (middle click) and they go, with a warning.
- **Lost compartments**: in a fight, a room with 3 or more holes to space (or a fifth of its walls open) is LOST. The crew leave it, and you fix it after the fight or in build mode. Your soldier can still work there.
- **Repairs under fire**: a wall or part hit in the last 5 s repairs at about a third of the speed, on both ships, so an enemy crew no longer mends as fast as one gun hurts.
- **Orders for several crew**: Shift+click or drag a box to select several (Shift+click on the crew bar works too). Middle click a room to split its jobs among them, and **X** spreads them over the damaged rooms.
- **Tab slows a ship fight to a quarter speed** until you press it again: time to give orders. There's no limit on it.

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

### Fixed
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

## Economy and balance
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
- **Lattice wardens** never break, so beating one takes several minutes.
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
