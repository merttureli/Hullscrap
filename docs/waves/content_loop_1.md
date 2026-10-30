# Content loop 1: starts at 10 pm US Central (owner, 2026-10-30)
> "At 10 pm exactly, start the content loop with a fresh tank: more parallel agents adding lore, enemies and enemy designs, procedural generation to the max, and content updates in general: endings, ending ship screens, ending art, etc."

**Rules for every track**:
- Content goes in its own pack under `data/packs/<wave>/` (`docs/CONTENT_PLAN.md` section 7). Art goes by id under `art/`.
- Every track passes `tests/test_content.gd` and the soak test, and shows the owner screenshots or preview sheets before it merges.
- The lead merges as tracks land and keeps `main` playable after every merge.
- Specs come from `docs/CONTENT.md` (sections 8, 11, 13, 14), `docs/CONTENT_PLAN.md`, `docs/LORE.md` and `docs/ART_STYLE.md`.

## Tracks (parallel)
1. **Procedural enemy ships** (code): `scripts/space/shipgen.gd` builds an enemy ship from (faction, size class, seed, budget).
   - **The hull**: a silhouette from faction grammar rules, made of shaped pieces (no rectangles: the 4c rule).
     - Rustfang: jagged, ram bows.
     - Concord: symmetric and clean.
     - Lumen/Warden: faceted.
     - Hollow: wrong-looking.
   - **The inside**: rooms, doors, power and cables.
   - **The loadout**: mounts placed through the real mount rules and bought from the CONTENT 14 budget (`data/enemy_tables.json`).
   - Deterministic, and every result passes the ship tests (power, rooms, paths, mounts) in a 500-seed sweep.
   - The campaign's `fight: "tier"` uses it, with a threat rating against the player.
2. **The balance harness** (code): CONTENT 14. AI-vs-AI fights of the reference builds against generated enemies at jumps 5/15/25/35 produce `docs/BALANCE_REPORT.md`. It feeds track 1's tables.
3. **Procedural derelicts and POIs** (code): wrecks are generated ships with damage, breaches, fires, dead crew and loot (feeding salvage, and later boarding). POI flavour variants per region. These go into the sector generator once step 1 of the sector core lands.
4. **Region event packs** (writers, 2–3 in parallel): 40 events per region (Clan space, Concord space, Lumen space, the Boneyard, the Gate approaches), with blue options for all 10 species, plus 20 derelict logs per region. Each region is its own pack.
5. **Endings and landmarks** (writer plus code):
   - **Writing**: the full Haven chain (8–10 events across regions, with lures), the Way Out per faction, the Hollow chain, Retire, and 6 landmark events (CONTENT 13).
   - **Code**: the `unlock` effect, `data/unlocks.json`, the profile unlocks, **the ending screen** (the ending art, your ship's silhouette in the "hall of ships", the run log, score and unlocks), and new-run options for unlocked starters.
6. **Ending art and ship screens** (art): one pixel illustration per ending (Halcyon's gardens, a restarted gate per faction, the Hollow, retirement at Rusthold), plus hall-of-ships frames and score panel art, in the approved style.
7. **Content waves**: data plus art pairs:
   - **weapons wave 2**: ~20 more across lines and cultures, with a quarter of them turrets;
   - **race wave 2**: Vellum, Oorth, Drakkin, Wisp, Hullkin, Lantern, with the small and floating rigs;
   - **engines wave 2**: CONTENT_PLAN 4 B, C and D, including uniques with quests;
   - **processing** (smelters, steel and alloy) from CONTENT 12.
9. **The race loop to 30** (owner: "loop the races until we reach 30 unique ones"): waves 2, 3 and 4 from `docs/waves/races_2_4.md`.
   - Each wave is a hooks code agent plus an art agent plus a data and writing agent.
   - Run them back to back, with the next wave's art starting while the previous wave's data lands, until 30 species are on main.
10. **Regions** (CONTENT 15): the region graph code (8 stages, 2–3 choices at each exit, region data), then region packs: each race wave ships its homeland region with it.
11. **Unique characters** (CONTENT 16): the crew active-ability code (G, the vocabulary, cooldowns, crew cards), then character packs of about 16 at a time (writer plus art) until 64.
12. **Racial tech** (CONTENT 17): the new damage effects in combat, then per race 3 ship weapons, 3 components and 2 hand weapons (data plus art plus projectile and impact effects). It folds into the race loop: every race wave ships its arsenal, and waves 0–1 (the existing 10 races) get theirs first.
13. **Rare factions** (CONTENT 18): one pack per faction (region, enemy table, events and quests, crew, relics), from uncommon to legendary.
14. **The hangar** (CONTENT 19): the hangar screen and unlock code (with track 5's unlocks). Then 1–3 starter ships per race, shipped with each race wave (existing races first), plus the event starters as their landmarks, endings and rare factions land. The target is about 80.
8. **Sector space steps 2 and 3**: the view, autopilot, fights in place, then its content (intakes Mk2/Mk3, radars, tractor), when step 1 lands.

## Order of starting
- At 10 pm, start tracks 1, 4 (two writers), 5 (writer and code), 6, 7 (weapons wave 2: art plus data) and **9 (race wave 2: hooks, art and data; wave 3 art too)** at once.
- Tracks 2 and 3 start when track 1 has a first merge, and track 8 when step 1 of the sector core merges.
- The lead keeps about 6–8 agents running and merges continuously.

## The 14-hour window and Beta 2 (owner, 2026-10-30)
> "At 10 pm, keep the reasonable models: Sonnet for builds, Opus when it's needed. Spawn many in parallel. You have roughly 14 hours before we send another version in, with all the features implemented on the core gameplay loop and all the initial 10 races complete with their guns and game mechanics. One Opus agent must also be spawned to guide the game's mechanics forward: no unnecessary additions, but cleverly thought-out ones, so the challenge is worth the time and fun to play. Other games in this style are a good place to look. It develops them with its own crew of 3 Sonnet agents, and presents them to me at the end of the 14 hours."

- **The window** runs from 10 pm Central (03:00 UTC, Oct 31) to about noon Central (17:00 UTC, Oct 31). At the end comes **Beta 2**: a green build, tagged, with a presentation for the owner.
- **Models**: builders are **Sonnet**. **Opus** is used for the mechanics director and for any brief that needs design judgment or a hard, cross-cutting refactor (the region graph, the sector view integration).
- **What Beta 2 must have** (in priority order):
  1. **The core loop, complete**:
     - regions (an 8-stage run with region choice);
     - sector space with the Raft loop: open space, debris, intakes, radar, autopilot, light-speed jumps, fights in place;
     - procedural enemies with threat ratings;
     - endings, landmarks and unlocks;
     - the hangar.
  2. **All 10 existing races complete**: each has its homeland region, racial tech (3 ship weapons, 3 components, 2 hand weapons with on-theme effects), 1–3 starter ships, at least 2 unique characters with active abilities, and its events.
  3. Everything else in this loop (race waves 2–4, rare factions, more characters) as time allows, **never at the cost of 1 and 2**.
- **The mechanics director** (Opus, plus a crew of 3 Sonnet builders):
  - **Mission**: make the game deeper, more challenging and more fun, with **few, clever, well-tested mechanics**, never bloat. Each idea must make choices harder and more interesting, not just add numbers.
  - **Research**: games in this style (FTL and Multiverse, Cosmoteer, Space Haven, Raft, Barotrauma, Into the Breach, Slay the Spire's run structure, Subnautica). Write down what makes their loops work.
  - **Workflow**:
    1. Write `docs/MECHANICS_REVIEW.md`: what's weak in the current loop, then 5–8 proposed mechanics, each with the problem it solves, how it plays, its cost to build, and the risk of bloat.
    2. Pick the best 3–5, write precise briefs, and have its 3 Sonnet builders implement them on their own branches, with tests and screenshots.
    3. Playtest them through the soak test and the balance harness.
    4. At the end of the window, present the results to the owner: the doc plus merged features with screenshots.
  - **It coordinates with the lead** before touching shared systems (combat, campaign, ship), so its work merges cleanly.
- **It loops** (owner, 2026-10-30): research → propose → build → playtest → refine, round after round, **until it is satisfied with the mechanics, or until the owner's usage reaches 25% of the weekly limit**, whichever comes first, and at the latest at the Beta 2 freeze. The lead can't read the usage meter: the owner tells the lead when it hits 25%, and the lead then stops the director's loop. Each round ends with a short progress line to the lead.
- **Sector space step 2 notes (from step 1)**: out of combat the ship flies at a **cruise multiplier of ×3** on its flight numbers, so an 8,000 px trip takes about 25–30 s. In combat the flight numbers stay real. A Radar Mk3 stat `see_hidden` will be added with the radar content (step 3).
- **The lead's cadence**: keep 6–10 builders running, merge continuously, keep `main` green and the beta builds green, and screenshot every big merge to the owner.
  - At about 16:00 UTC, **freeze features**: only fixes and balance from then on.
  - At about 17:00 UTC, **ship Beta 2**: a green build, a release note, and the presentation page.
