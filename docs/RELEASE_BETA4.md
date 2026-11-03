# Hullscrap Beta 4

Boarding, a rebuilt hull, the Ledger, and a balance pass measured by a playtest bot. Download it from **GitHub → Actions → beta builds → the latest green run → Artifacts** (Windows, Linux, macOS). The main menu's corner says **Beta 4**.

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
- **Starter ships against three-skull pirates at stage 1**: the Rustbucket now has a Bubble Rig and its Bolt Thrower sits in a notch of the prow, and it comes through about 40 to 60% of them (the Courier about 55 to 65%, the Prism about 90%): the rest are stalemates, mostly against Concord and Lumen pirates whose crews mend as fast as one Bolt Thrower hurts. A person who shoots the pirate's one gun does better than the autopilot the numbers come from.
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
