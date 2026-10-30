# Hullscrap: setting and lore (lead, v1)

Everything here should make the mechanics feel motivated:
- the three equipment lines are three **cultures**;
- species traits come from where those peoples live;
- wrecks are everywhere for a reason;
- every quest giver wants something.

Tone: **working-class space**. Grimy, funny, a little sad, never grimdark. The jokes come from people getting by. Think *Firefly* crossed with a salvage yard.

## The premise: the Snap
Forty years ago the **Lattice** went dark in one night. It was the network of gate stations that let ships jump between star systems.
- Every ship mid-jump came out wherever it happened to be: thousands of hulls strewn across the **Drift**, the region between three dead gates.
- Nobody knows why. The **Concord** says "solar event". Scrappers say "somebody pulled the plug". The Lumen don't say anything, which people find suspicious.
- With no gates, the Drift became an island. Nothing new gets built from scratch out here: **everything flies on salvage**. That's the game's economy, and its name.

## The player
You inherited (won at cards, stole, were "loaned") a barely-working hull and the debts that come with it. You're a **hullscrapper**: you fly out to wrecks, cut them apart, sell what works, and fit the rest to your own ship.

**The long arc**: rumours say the dead gates still have power in their cores, and whoever restarts one owns the way out of the Drift.
- Every faction wants that. You start out wanting rent money.
- The arc is a sequence of gate expeditions: a Concord gate, a Scrapper gate, a Lumen gate. They're the late-game set pieces, each a huge derelict station to board.

## The three cultures (= the three equipment lines)

### The Scrapper Clans: Scrap line
- **Who**: descendants of the crews stranded by the Snap. They live in **Rustholds**: stations welded together from dozens of wrecks, still spinning on borrowed parts.
- **Values**: if it runs, it's fine; if it doesn't, hit it. Clan reputation is measured in how much junk you can keep flying.
- **Gear**: cheap, loud, repairable with a wrench and a prayer. A Rustbucket Reactor works fine until it doesn't.
- **Politics**: a dozen clans that feud constantly and unite instantly against the Concord. The biggest is the **Gantry Clan**, which runs the main Rusthold. The **Rustfangs** are clan exiles turned pirates. *The pirate raider you fight is Rustfang.*
- **They hire you for** salvage runs, cargo smuggling, clan disputes ("bring back our cousin's reactor"), and races.

### The Concord: Standard (Mk) line
- **Who**: the remnant of the government that ran the Lattice. They hold **Concord Station Meridian**, the one place in the Drift with a working shipyard that can make new Mk parts.
- **Values**: order, paperwork, and the firm belief that they'll fix the gates if everyone just files the right forms. Decent people trapped in a bureaucracy that has nothing left to administer.
- **Gear**: reliable, standardised, tiered Mk1–Mk3, and certified. Their shipyard sells **hull frames**: you expand your ship here.
- **Politics**: they want the gates back under Concord control. They post **bounties** on Rustfangs and are quietly losing a cold war with the clans over who owns salvage rights.
- **They hire you for** bounties, escorts, "official" salvage contracts with inspections, and courier work.

### The Lumen: Neon line
- **Who**: a sect of engineers who were researching the Lattice when it died. They live in **the Prism**, a crystalline station that hums.
- **Values**: they think the Snap was a door opening, not closing. They build with **crystal** and **plasma** salvaged from the dead gates themselves, which is why their gear is brilliant, fragile, runs hot, and **hates ion**: it's built from the same physics that broke.
- **Gear**: neon. High output, needs a proper workshop to make (high fabricator level), expensive. They trade it only to people they've decided are "interesting".
- **Politics**: they want to *study* the gates, not restart them. Possibly they're the ones who turned them off. Their quests are strange, and the rewards are blueprints.
- **They hire you for** scanning anomalies, retrieving crystal from gate debris, testing prototypes (a quest that literally hands you a quirky unique), and escorting researchers.

## Species
All are data; traits appear in `data/crew.json` as they're implemented.
- **Humans**: most of the Drift. Balanced, need air, complain about everything.
- **Basalt** (silicon-based): slow, heavy, **don't breathe** (`no_breath`), bad medics because they don't understand soft bodies. Clan engineers love them for vacuum work. Before the Snap they were the gate builders' labour caste, and some remember more than they say.
- **Emberkin**: small, warm-blooded to an absurd degree. **Heat-resistant** (`heat_resistant`), happier in hot rooms, miserable in the cold. The natural crew for neon reactors and afterburner rooms. Many work for the Lumen.
- **Fenn**: quick, clever-handed engineers (`fast_repair`), but fragile (low hp). Long ears, short tempers, an excellent trading culture. They run most station markets.
- Unique recruits are named individuals from quests, each with one odd trait. For example *"Socket"*, a Basalt who can **power one adjacent system by hand**.

## Places (stations are walkable ships; see PLAN "On foot")
- **Gantry Rusthold** (Scrapper hub): a scrap market, clan recruiters, cheap repairs, fights in the cargo bay. The first station you dock at.
- **Meridian** (Concord hub): the shipyard (hull frames, Mk parts), the bounty office, a medical deck, very clean floors.
- **The Prism** (Lumen hub): only after a Lumen quest. Neon blueprints, crystal traders, strange crew.
- **The Boneyard**: a dense wreck field near the first dead gate, the main salvage zone. Derelicts float here with their air, fires and occasionally their crew still aboard.
- **Dead Gates** (late game): three huge derelict stations to board, each a dungeon with its own hazards (vacuum zones, overcharged systems, Lumen watchers, Rustfang squatters).

## Pirates and threats
- **Rustfangs**: Scrapper exiles with scrap-line ships, scrap-plate armour and a liking for flak and Bolt Throwers. They **board** when they can. Early-game enemies.
- **Concord Enforcers**: if your Concord reputation drops (smuggling, attacking Concord ships). Mk-line ships with good shields and missiles.
- **Wardens**: Lumen-built automated drones guarding gate debris. Neon weapons, ion-weak. Mid-game.
- **The Hollow**: rumoured ships that came *out of* the dead gates after the Snap. No crew aboard, but the systems still run. The late-game mystery.

## How lore shows up in play (writing rules)
- **No lore dumps.** Lore comes through NPC dialogue, item blurbs, station signage, derelict logs (short data-pad texts found while salvaging), and quest text.
- **Every item blurb has a voice**, the one of the culture that made it. Scrap blurbs are jokes or warnings, Concord blurbs read like spec sheets with tired asides, Lumen blurbs are cryptic.
- **Reputation**: three bars (Clans, Concord, Lumen). Your choices in quests and fights move them. Prices, recruits and which blueprints you're offered depend on them.
- **Names**:
  - Scrapper ships are named like boats and insults ("Second Mortgage", "Ma's Kettle", "Not Again");
  - Concord ships have registry numbers plus a virtue ("CS-114 Diligence");
  - Lumen ships are named after light phenomena ("Caustic", "Afterimage").

## Data to add as content grows
- `data/factions.json`: id, name, line, colours and reputation thresholds.
- `data/species.json`: traits, hp, speed, oxygen use, heat tolerance.
- `data/dialogue/*.json`: NPC dialogue trees.
- `data/quests/*.json`: quest steps, requirements and rewards.
- `data/logs/*.json`: derelict data-pad texts.
- Ship names per faction: `data/names.json`.
