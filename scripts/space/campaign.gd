extends RefCounted
## The Drift campaign (docs/CONTENT.md section 8): the state of a run and the rules that move it. The map
## (drift.gd), the current node, what is visited, flags, reputation, Ma Gantry's debt and its clock, the
## jump counter, the `once` events used, the hull integrity lost, the recruits on offer. Jumping, arriving
## (which event happens), fights (design choice, loot, the result), the station trades, save and load.
## Light speed (start_jump, tick_jump: an 8 s spool, no jump with hostiles near) and the sectors the nodes turn into
## (sector.gd, docs/CONTENT.md section 11) are here too; cfg `instant_jump` keeps the beta's instant jump for now.
## The run crosses regions (docs/CONTENT.md section 15, regions.gd): the map is the current region's, `stage` counts them
## (1 = Clan space), `route` lists the regions of the run, and cross() leaves from the exit beacon for one of the regions on
## offer. The debt, reputation, flags, the jump counter and the ship carry across; the map, the sectors, what is visited
## and the recruits on offer are the region's own. Ma Gantry's debt clock runs only for the first run.debt_stages stages.
## No nodes, no drawing: map_view.gd, event_panel.gd, station_panel.gd and region_choice.gd are thin views over it.
## All randomness of play is the one RandomNumberGenerator `rng`, seeded with the campaign seed and saved with it, so a run
## replays exactly; each region's map and sectors come from its own seed (Regions.seed_for: the run seed, the stage and the
## region), and the offers at an exit from the run seed and the stage. Numbers come from data/drift.json, reputation rules from data/factions.json.
## `ship` below is the player's Ship (ship.gd): fuel and credits are cargo items.

const Drift = preload("res://scripts/space/drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Content = preload("res://scripts/data/content.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Tide = preload("res://scripts/space/tide.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Radar = preload("res://scripts/space/radar.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Wardens = preload("res://scripts/space/wardens.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")

## Save format. Bump it when the file changes, and keep loading the old ones or refuse them clearly.
## 2 adds `fuel_part` (the fraction of a fuel already used up, docs/waves/engines_1.md); version 1 loads with 0.
## 3 adds `sectors` (the POI states and the ship's place of each sector visited, sector.gd) and `spool` (the jump
## drive's charge); older saves load with no sector yet, so the ship arrives at the arrival point of its node's sector.
## 4 adds the regions: `stage`, `region`, `route` (the regions so far), `region_seed` and `debt_stop` (the jump count at
## which Ma's clock paused). Older saves load as stage 1 in Clan space; a map with no exit beacon (one from before the
## regions) is made again as Clan space's, with the ship at Gantry Rusthold.
## 5 adds `tide` (the Hollow tide of the region, tide.gd); older saves load with a fresh tide (at their jump count in stage 1).
## 6 adds `warden` (the warden of the exit beacon, wardens.gd); older saves roll it on load. Its flag is in `flags`.
## 7 adds `foes` (the enemies rolled for the fights of the places, foe_for); older saves start with none rolled.
## 8 adds `far` to each saved sector (the far POIs that are done, sector.gd); older saves have none done.
const VERSION := 8
const MIN_VERSION := 1
## A fuel is this many parts: a jump costs the powered engines' thrust-weighted mean `fuel_mult`, in hundredths.
const FUEL_PARTS := 100
const CONFIG_PATH := "res://data/drift.json"
const FACTIONS_PATH := "res://data/factions.json"
const ITEMS_PATH := "res://data/items.json"
const SAVE_PATH := "user://campaign.json"
const REFUSED_TEXT := "The dock master turns you away."
const DARK_TEXT := "The gate is dark."
const NO_FUEL := "no fuel"
const HOSTILES_TEXT := "hostiles too close to jump"
const SPOOL_TEXT := "spool the jump drive first"
const NOT_AT_EXIT := "not at the exit beacon"
const TOW_DEBT := 150  ## what Ma adds to the debt for a tow home (tow)
const TOW_FUEL := 2
const HOSTILE_PATROL := {"id": "patrol_hostile", "type": "patrol", "once": false,
	"text": "The Concord cutter does not hail you. It has your registry on a list, and the list has changed. Every gun on her flank swings round at once.",
	"choices": [{"text": "Raise shields.", "outcomes": [{"weight": 100, "text": "", "effects": {"fight": "tier"}}]}]}
## The event of a Hollow place when no hollow event fits (data/packs/mech_tide has the real ones).
const HOSTILE_HOLLOW := {"id": "hollow_hostile", "type": "hollow", "once": false,
	"text": "The beacon here has been dead a long time, and something is still answering it. Lights come up on the dark hulls around you, one after another, all pointing your way.",
	"choices": [{"text": "Raise shields.", "outcomes": [{"weight": 100, "text": "", "effects": {"fight": "tier"}}]}]}

static var _cfg := {}
static var _fac := {}
static var _kinds := {}

var seed_value := 1
var rng := RandomNumberGenerator.new()  ## every roll of the campaign: the map, events, loot, recruits
var cfg: Dictionary
var events: Events
var drift: Drift
var current := ""  ## node id of the ship
var visited := {}  ## node id -> true
var flags := {}  ## flag -> true
var rep := {}  ## faction id -> -10..10
var debt := 0  ## credits still owed to Ma Gantry
var paid := 0  ## credits repaid so far
var jumps := 0  ## the jump counter: drives the debt clock and the danger tier
var used := {}  ## once-events already seen: id -> true
var revealed := {}  ## node ids shown on the map although far from any visited node
var logs_found := {}  ## derelict log ids found: id -> true
var reminded := -1  ## the payment cycle (jumps / every) Ma's reminder was shown in
var hull_loss := 0  ## hull integrity points lost; repaired at stations
var fuel_part := 0  ## parts (hundredths) of a fuel the jumps have used up and not yet paid; 0..FUEL_PARTS-1, spent as whole fuel when they reach FUEL_PARTS
var events_seen := 0  ## events met at nodes, waits and wrecks (the game over screen counts them)
var fights_won := 0  ## fights of the run that were won
var offers := {}  ## station node id -> [{species, name}] recruits on offer
var sectors := {}  ## node id -> Sector (sector.gd) for every node visited (made on first use from the seed, so only their states are saved)
var foes := {}  ## "region/node/kind" -> the enemy rolled for a fight of that kind there (foe_for): a design path or a gen: spec; saved
var tide: Tide  ## the Hollow tide over the map (tide.gd): jumps, waits, tows and lingering push it
var spool := {}  ## the jump drive spooling: {to, t (seconds charged), drift (the no-fuel jump), blocked}; {} when idle
var last_jump := {}  ## what the last spooled jump did: the jump() result ({ok, why, node, drift, notes})
var stage := 1  ## the stage of the run: 1 (Clan space) to run.stages (8); one more is the ending region
var region_id := ""  ## the region the ship is in (data/regions/<id>.json)
var region_data := {}  ## that region's data (Regions.get_region), not saved
var route: Array = []  ## the regions of the run in order, this one last
var region_seed := 0  ## the seed of this region's map and sectors
var debt_stop := -1  ## the jump count at which Ma's debt clock stopped (from stage run.debt_stages + 1), -1 while it runs
var warden := {}  ## the warden of this region's exit beacon (Wardens.for_region), rolled on entering; {} in the ending region
var profile = null  ## the player's Profile (profile.gd), set by the map: unlocks and landmarks are written to it at once. null in tests
var ending := ""  ## the id of the ending this run reached ("" while it goes on): the run is won (docs/CONTENT.md section 13)
var landmarks: Array = []  ## ids of the landmark events (events.gd) met in this run, in order
var unlocks_earned: Array = []  ## ids of the unlocks this run earned (new to the profile), in order
var chronicle: Array = []  ## the run log, in order: {jumps, kind (landmark, unlock, ending), id, text}; the ending screen reads it
var _hazards := {}  # "<region seed>:<region>:<node>" -> that node's hazard ({} or {id, dir}), rolled once (hazard_at)
var _hull_key := -1
var _hull_max := 0


## data/drift.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		assert(data is Dictionary, "bad drift data: " + CONFIG_PATH)
		_cfg = data
	return _cfg


## data/factions.json, read once.
static func factions_data() -> Dictionary:
	if _fac.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(FACTIONS_PATH))
		assert(data is Dictionary, "bad faction data: " + FACTIONS_PATH)
		_fac = data
	return _fac


func _init(p_seed := 1, p_cfg := {}, p_events = null) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	cfg = p_cfg if not p_cfg.is_empty() else config()
	events = p_events if p_events != null else Events.shared()
	enter_region(str(Regions.run_of(cfg)["start"]))
	debt = int(cfg["debt"]["total"])
	for f in rep_factions():
		rep[f] = 0


# --- factions and reputation ----------------------------------------------------------------------------

## The factions with a reputation bar, in file order.
static func rep_factions() -> Array:
	var out := []
	for f in factions_data()["factions"]:
		if not bool(f.get("hostile", false)):
			out.append(str(f["id"]))
	return out


static func faction_name(id: String) -> String:
	for f in factions_data()["factions"]:
		if f["id"] == id:
			return str(f.get("short", f["name"]))
	return id


static func faction_color(id: String) -> Color:
	for f in factions_data()["factions"]:
		if f["id"] == id:
			return Color(str(f["color"]))
	return Color.WHITE


## Change `faction`'s reputation by `n`, kept within -10..10. Returns the change really made.
func add_rep(faction: String, n: int) -> int:
	if not rep.has(faction):
		return 0
	var r: Dictionary = factions_data()["rep"]
	var before: int = rep[faction]
	rep[faction] = clampi(before + n, int(r["min"]), int(r["max"]))
	return rep[faction] - before


## Does `faction` turn you away (its reputation is below the refusal line)?
func refuses(faction: String) -> bool:
	return faction != "" and int(rep.get(faction, 0)) < int(factions_data()["rep"]["refuse_below"])


## The fraction `faction`'s stations take off their prices (0 below the discount line).
func discount(faction: String) -> float:
	var r: Dictionary = factions_data()["rep"]
	return float(r["discount"]) if faction != "" and int(rep.get(faction, 0)) >= int(r["discount_from"]) else 0.0


## `base` credits at a station of `faction`, discount included (never below 1). With the buyer's `ship`, the best haggler
## aboard takes his fraction off as well (TraitSet.haggle: -10% is 0.1, added to the faction's discount).
func price(base: int, faction: String, ship = null) -> int:
	return maxi(1, ceili(float(base) * (1.0 - discount(faction) - TraitSet.haggle(ship)) - 0.0001))


# --- the map and the fog ---------------------------------------------------------------------------------

func node(id: String) -> Dictionary:
	return drift.node(id)


## Is the node kept off the map for now (a `hidden_until` flag that is not set)?
func is_hidden(id: String) -> bool:
	var h := str(drift.node(id).get("hidden_until", ""))
	return h != "" and not flags.has(h)


## Does the map show the node's type? Visited nodes, the neighbours of visited nodes, revealed nodes, the exit
## beacon and beacon places (a homeland's station) do; others show "?". A hidden node shows nothing at all.
func is_known(id: String) -> bool:
	if is_hidden(id):
		return false
	if visited.has(id) or revealed.has(id) or drift.node(id).get("type", "") == "exit" or bool(drift.node(id).get("beacon", false)):
		return true
	for o in drift.neighbours(id):
		if visited.has(o):
			return true
	return false


## The lanes out of `id` that lead somewhere on the map (hidden nodes are left out).
func neighbours(id: String) -> Array:
	return drift.neighbours(id).filter(func(o): return not is_hidden(o))


static func type_info(type: String) -> Dictionary:
	return config()["types"].get(type, {"label": type, "color": "#ffffff", "glyph": "?"})


## What the map calls a node: its name or type when known ("The Hollow" for an unnamed place the tide has taken), "?" otherwise.
func label(id: String) -> String:
	if not is_known(id):
		return "?"
	var n := drift.node(id)
	if str(n["name"]) == "" and is_hollow(id):
		return "The Hollow"  # ghosts, whatever the place was
	return str(n["name"]) if str(n["name"]) != "" else str(type_info(str(n["type"]))["label"])


## Show a node on the map: `id` is a node or place id, or a node type (the nearest node of that type that
## is not on the map yet). Returns its label, "" when there is none.
func reveal(id: String) -> String:
	if drift.has(id):
		revealed[id] = true
		return label(id)
	if not config()["types"].has(id):
		return ""
	var here: Vector2 = drift.node(current)["pos"]
	var best := ""
	var best_d := INF
	for n in drift.nodes:
		if n["type"] != id or is_hidden(n["id"]) or is_known(n["id"]):
			continue
		var d: float = here.distance_to(n["pos"])
		if d < best_d or (d == best_d and n["id"] < best):
			best = n["id"]
			best_d = d
	if best == "":
		return ""
	revealed[best] = true
	return label(best)


# --- hull integrity ---------------------------------------------------------------------------------------

## The most hull integrity `ship` can have (what a fight would give it).
func hull_max(ship) -> int:
	var key: int = hash([ship.get_instance_id(), ship.grid.tiles.hash()])
	if key != _hull_key:
		var arena := Arena.new(1)
		arena.add_ship(ship)
		_hull_max = roundi(arena.ships[0].hull_max)
		_hull_key = key
	return _hull_max


## The integrity `ship` has left (at least 1: a damaged hull has a lower maximum than the one the loss was
## counted against, and the number must never show as zero or less).
func hull_left(ship) -> int:
	return maxi(hull_max(ship) - hull_loss, 1)


## The hull a fight starts with: the arena's maximum less what the campaign has lost (never below 1), so the
## damage of one fight, of an event or of a drift jump is still there in the next fight until it is repaired.
func fight_hull(arena_hull_max: float) -> float:
	return maxf(1.0, arena_hull_max - float(hull_loss))


## Change the hull integrity by `n` (negative = damage). It never drops below 1 or rises above the
## maximum. Returns the change really made.
func change_hull(ship, n: int) -> int:
	var before := hull_loss
	hull_loss = clampi(hull_loss - n, 0, maxi(hull_max(ship) - 1, 0))
	return before - hull_loss


# --- jumping ----------------------------------------------------------------------------------------------

## "" when the ship may jump to `to`, else why not: no lane, a dark gate, "no fuel". A drift jump (no
## fuel, costs integrity) is only for an empty tank and only if the hull would survive it.
func jump_block(to: String, ship, drift_jump := false) -> String:
	if not drift.has(to) or is_hidden(to) or not drift.linked(current, to):
		return "no lane there"
	if gate_dark(to):
		return DARK_TEXT
	if drift_jump:
		if not fuel_short(ship):
			return "you still have fuel"
		if hull_left(ship) <= int(cfg["fuel"]["drift_hull"]):
			return "the hull would not survive a drift jump"
		return ""
	return NO_FUEL if fuel_short(ship) else ""


## Is node `id` a Dead Gate that cannot be entered? The gates are dark everywhere but in the ending region (the Gate approaches
## past the last stage), where their shells can be approached: the Way Out and the Hollow endings wait there.
func gate_dark(id: String) -> bool:
	return drift.has(id) and drift.node(id)["type"] == "gate" and not is_final()


## Is the old instant jump on (cfg `instant_jump`, true for now)? The map then jumps with jump() at once; with it off
## a jump is start_jump() and tick_jump(), eight seconds of spool.
func instant_jump() -> bool:
	return bool(cfg.get("instant_jump", true))


## Jump along a lane to `to` at once (the beta's map): the fuel of jump_cost() (or 15 integrity for a drift jump), +1 on
## the jump counter, which may bring a payment due. Returns {ok, why, node, drift, notes}; `notes` are lines to tell the
## player. With `instant_jump` off it refuses: the jump spools (start_jump).
func jump(to: String, ship, drift_jump := false) -> Dictionary:
	if not instant_jump():
		return {"ok": false, "why": SPOOL_TEXT, "notes": []}
	return _jump_now(to, ship, drift_jump)


func _jump_now(to: String, ship, drift_jump: bool) -> Dictionary:
	var why := jump_block(to, ship, drift_jump)
	if why != "":
		return {"ok": false, "why": why, "notes": []}
	var notes := []
	if drift_jump:
		var cost := int(cfg["fuel"]["drift_hull"])
		change_hull(ship, -cost)
		notes.append("The drift jump tears at the hull (-%d integrity)." % cost)
	else:
		var parts := fuel_part + jump_cost(ship)
		ship.inventory.add("fuel", -(parts / FUEL_PARTS))
		fuel_part = parts % FUEL_PARTS
	flags.erase("at_" + str(drift.node(current).get("place", "")))  # undocked
	current = to
	visited[to] = true
	_enter(to, ship)
	notes.append_array(_advance(1))
	return {"ok": true, "why": "", "node": to, "drift": drift_jump, "notes": notes}


## What the next jump costs, in parts (hundredths) of a fuel: the thrust-weighted mean `fuel_mult` of the powered
## engines (an offline mount, with its outside half disabled or its link cut, is not powered and does not count; an
## engine without a `fuel_mult` counts as 1.0), rounded to a part. A ship with no powered engine pays a whole fuel.
func jump_cost(ship) -> int:
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var weighted := 0.0
	var thrust := 0.0
	for uid in uids:
		var id := str(ship.components.instances[uid]["id"])
		if not powered.get(uid, false) or str(ship.components.def(id).get("family", "")) != "engine":
			continue
		var t := float(ship.effective(id)["stats"].get("thrust", 0.0))
		weighted += t * float(ship.components.def(id).get("stats", {}).get("fuel_mult", 1.0))
		thrust += t
	if thrust <= 0.0:
		return FUEL_PARTS
	return maxi(1, roundi(weighted / thrust * FUEL_PARTS))


## The whole fuel the next jump takes from the cargo: the remainder plus its cost, in whole fuels.
func jump_fuel(ship) -> int:
	return (fuel_part + jump_cost(ship)) / FUEL_PARTS


## Is the cargo short of the fuel the next jump takes?
func fuel_short(ship) -> bool:
	return ship.inventory.count("fuel") < jump_fuel(ship)


## A cost in parts as text: "1 fuel", "0.5 fuel", "1.25 fuel".
static func fuel_text(parts: int) -> String:
	if parts % FUEL_PARTS == 0:
		return "%d fuel" % (parts / FUEL_PARTS)
	return ("%d.%02d" % [parts / FUEL_PARTS, parts % FUEL_PARTS]).rstrip("0") + " fuel"


## Time passes by `n` jumps: the counter goes up and each payment date crossed is checked (while Ma's clock runs).
func _advance(n: int) -> Array:
	var notes := []
	var d: Dictionary = cfg["debt"]
	for i in n:
		jumps += 1
		if debt > 0 and debt_running() and jumps % int(d["every"]) == 0:
			if behind() > 0:
				flags["debt_missed"] = true
				notes.append("%s's collectors have noted a missed payment." % d["creditor"])
			else:
				notes.append("A payment fell due, and you are paid up.")
	notes.append_array(_tide_notes(tide.advance(n)))
	_mark_hollow(true)
	return notes


## The line for `fell` places the Hollow tide has just taken (none for 0).
func _tide_notes(fell: int) -> Array:
	return ["The Hollow takes %d more place%s." % [fell, "" if fell == 1 else "s"]] if fell > 0 else []


## Has the Hollow tide taken node `id` (tide.gd)? Stations and the exit never fall, nor do the Dead Gates: it comes from them,
## and their own events (the Way Out, the Hollow endings) are what waits there.
func is_hollow(id: String) -> bool:
	return tide.is_hollow(id) and drift.node(id).get("type", "") != "gate"


## How hard the Hollow tide presses on node `id`, 0 to 1 (tide.gd pressure; 1 once it is Hollow, 0 for a Dead Gate, which the tide never takes).
func tide_pressure(id: String) -> float:
	if is_hollow(id):
		return 1.0
	return 0.0 if drift.node(id).get("type", "") == "gate" else tide.pressure(id)


## Tell the current sector whether the tide has taken it (Sector.set_hollow) and how hard it presses (Sector.set_pressure): the one place those are set. `mid_stay`: the
## ship is in the place as it falls (a jump's step, a wait, lingering), so a ghost comes for it at once; an arrival and a load
## are quiet. Called on arrival (_enter), on a load, and wherever the tide steps (_advance, linger); a sector made later is
## marked by sector_at. It never makes a sector (so a save stays the same save).
func _mark_hollow(mid_stay := false) -> void:
	var s = sectors.get(current)
	if s != null:
		s.set_hollow(is_hollow(current), mid_stay)
		s.set_pressure(tide_pressure(current))


## A stretch of `dt` seconds is lived in the same place (play mode, no fight, no map): the tide creeps on. Returns lines for
## the HUD and the chronicle. It never moves the jump counter or the debt.
func linger(dt: float) -> Array:
	var fell := tide.hollow_count()
	var lines := tide.linger(dt)
	if not tide.warns.is_empty() and lines.has("The tide rises in %d s" % int(tide.warns[0])) and tide.jumps_until(current) == 1 and tide_pressure(current) > 0.0:
		lines.append(Tide.NEAR_TEXT)  # the first warning, and it is this place that falls next
	lines.append_array(_tide_notes(tide.hollow_count() - fell))
	_mark_hollow(true)
	return lines


## With no fuel: wait for a passing trader. Time passes (one jump on the counter) and a trader event
## may come along. Returns {ok, why, notes, event}.
func wait(ship) -> Dictionary:
	if ship.inventory.count("fuel") > 0:
		return {"ok": false, "why": "you still have fuel", "notes": [], "event": {}}
	var notes := _advance(1)
	var ev := events.pick(self, {"id": current, "type": "trader", "place": ""}, ship)
	events_seen += int(not ev.is_empty())
	return {"ok": true, "why": "", "notes": notes, "event": ev}


## Stranded with no fuel: call Ma Gantry for a tow back to the region's start (Gantry Rusthold in Clan space). It costs
## TOW_DEBT on the debt and a jump's time, and she throws in TOW_FUEL fuel. Always possible with no fuel, so a run can't
## soft-lock.
func tow(ship) -> Dictionary:
	if ship.inventory.count("fuel") > 0:
		return {"ok": false, "why": "you still have fuel", "notes": []}
	var notes := _advance(1)
	current = drift.start_id()
	visited[current] = true
	spool = {}
	_enter(current, ship)
	notes.append_array(add_debt(ship, TOW_DEBT))
	ship.inventory.add("fuel", TOW_FUEL)
	notes.append("Ma's tug drags you to %s: debt +%d, fuel +%d" % [label(current), TOW_DEBT, TOW_FUEL])
	return {"ok": true, "why": "", "notes": notes}


## What happens on reaching the current node. Returns {node, refused, event, exit}: `refused` is the text of a
## dock master who turns you away (a faction below the refusal line), `event` the event to show ({} if
## none), `exit` true at the region's exit beacon once its warden is dealt with (the region choice comes after any event; while
## the warden holds the lane `event` is its hail and `warden` is true). A debt event (Ma's call,
## a reminder, the collectors' talk; only while her clock runs) interrupts the node's own event. At a
## station you may dock at the flag at_<place> is set (until you jump away), its recruits are rolled, and
## the event is one of its greetings.
func arrive(ship) -> Dictionary:
	var n := drift.node(current)
	var out := {"node": n, "refused": "", "event": {}, "exit": n.get("type", "") == "exit", "warden": false}
	if n.get("type", "") == "exit" and warden_up():  # the warden holds the lane: its hail, and no region choice until it is dealt with
		out["event"] = warden_event(ship)
		out["exit"] = false
		out["warden"] = true
		events_seen += 1
		return out
	var st := station_cfg(current)
	if not st.is_empty():
		if refuses(str(st.get("faction", ""))):
			out["refused"] = REFUSED_TEXT
			return out
		if str(n["place"]) != "":
			flags["at_" + str(n["place"])] = true  # docked: the station greetings ask for it
		if st["services"].has("recruit"):
			roll_offers(current, ship)
	if n["type"] != "gate" and debt_running():
		var due := _debt_event(ship)
		if not due.is_empty():
			out["event"] = due
			events_seen += 1
			return out
	if is_hollow(current):  # the tide has taken this place: ghost ships instead of its own event
		out["event"] = events.pick(self, {"id": current, "type": "hollow", "place": ""}, ship)
		if out["event"].is_empty():
			out["event"] = HOSTILE_HOLLOW
		events_seen += 1
		return out
	if n["type"] == "patrol" and refuses("concord"):
		out["event"] = HOSTILE_PATROL
		events_seen += 1
		return out
	out["event"] = events.pick(self, n, ship)
	events_seen += int(not out["event"].is_empty())
	return out


## The debt event due now, {} if none. The debt events (type debt) say when by their requires: Ma's first
## call (not_flag met_ma) once its jumps_min is reached, a reminder when a payment is due within 2 jumps
## (once per payment cycle) and the collectors' talk (flag debt_missed) on the jump after a payment was missed.
func _debt_event(ship) -> Dictionary:
	var ev := events.pick(self, {"id": current, "type": "debt", "place": ""}, ship, _debt_timing)
	if not ev.is_empty() and Events.debt_kind(ev) == "reminder":
		reminded = debt_jumps() / int(cfg["debt"]["every"])
	return ev


## Is it the moment for debt event `e`? See _debt_event.
func _debt_timing(e: Dictionary) -> bool:
	var every := int(cfg["debt"]["every"])
	match Events.debt_kind(e):
		"miss":
			return jumps > 1 and (jumps - 1) % every == 0 and behind() > 0
		"reminder":
			return debt > 0 and next_due_in() <= 2 and reminded != debt_jumps() / every
	return true


# --- light speed: the jump drive spools (docs/CONTENT.md section 11) ---------------------------------------

## Seconds the jump drive takes to charge (cfg jump.spool, 8).
func spool_time() -> float:
	return float(cfg.get("jump", {}).get("spool", 8.0))


## How close a hostile ship may be before the drive will not spool, in px (cfg jump.hostile_range, 2,000).
func hostile_range() -> float:
	return float(cfg.get("jump", {}).get("hostile_range", 2000.0))


## Begin charging the jump drive for a jump along a lane to `to` (the checks of jump_block; `hostiles_near`: a hostile
## is within hostile_range(), see Sector.hostile_near). Nothing is spent yet. The ship keeps flying while it spools.
## Returns {ok, why}. One spool at a time: cancel_jump() first to change the target.
func start_jump(to: String, ship, hostiles_near := false, drift_jump := false) -> Dictionary:
	if not spool.is_empty():
		return {"ok": false, "why": "the jump drive is already spooling"}
	var why := jump_block(to, ship, drift_jump)
	if why == "" and hostiles_near:
		why = HOSTILES_TEXT
	if why != "":
		return {"ok": false, "why": why}
	spool = {"to": to, "t": 0.0, "drift": drift_jump, "blocked": false}
	return {"ok": true, "why": ""}


## Stop charging (the map's cancel, or the ship was towed). Nothing was spent.
func cancel_jump() -> void:
	spool = {}


## The charge for the HUD: {active, to, t, total, frac (0..1), blocked}.
func jump_status() -> Dictionary:
	if spool.is_empty():
		return {"active": false, "to": "", "t": 0.0, "total": spool_time(), "frac": 0.0, "blocked": false}
	var total := spool_time()
	return {"active": true, "to": spool["to"], "t": spool["t"], "total": total, "frac": clampf(float(spool["t"]) / total, 0.0, 1.0), "blocked": bool(spool.get("blocked", false))}


## The drive charges for `dt` seconds. While `hostiles_near` (a hostile within hostile_range()) the charge holds where
## it is and this returns "blocked" (HOSTILES_TEXT is why). When the charge is full the jump fires: the fuel is spent
## now (jump_block is checked again, the fuel_mult of the engines as they are), the ship arrives in the sector of `to`
## (its arrival point, its POIs as they were left), and this returns "jumped" with the jump() result in `last_jump`.
## Also returns "spooling" (charging), "failed" (the jump was refused when it fired, last_jump.why says why; the spool
## is over) and "" (no spool).
func tick_jump(dt: float, hostiles_near: bool, ship) -> String:
	if spool.is_empty():
		return ""
	spool["blocked"] = hostiles_near
	if hostiles_near:
		return "blocked"
	spool["t"] = float(spool["t"]) + maxf(dt, 0.0)
	if float(spool["t"]) < spool_time():
		return "spooling"
	var to := str(spool["to"])
	var drift_jump := bool(spool.get("drift", false))
	spool = {}
	last_jump = _jump_now(to, ship, drift_jump)
	return "jumped" if last_jump["ok"] else "failed"


# --- sectors ------------------------------------------------------------------------------------------------

## The region of node `id`: every node of the map is in the current region (region_id); "" for a node the map does not have.
func region_of(id: String) -> String:
	return region_id if drift.has(id) else ""


## The sector of node `id`: made from the region seed, the node and the region's data the first time it is asked for, the
## same every time. null for a node the map does not have.
func sector_at(id: String):
	if not sectors.has(id):
		if not drift.has(id):
			return null
		sectors[id] = Sector.generate(region_seed, drift.node(id), region_id, {}, region_data)
		sectors[id].set_hollow(is_hollow(id))
		sectors[id].set_pressure(tide_pressure(id))
	return sectors[id]


## The hazard of node `id` ({} or {id, dir}; hazards.gd): rolled once from the region seed, the node and the region's
## `hazards`, the same every time. {} for a node the map does not have.
func hazard_at(id: String) -> Dictionary:
	var key := "%d:%s:%s" % [region_seed, region_id, id]
	if not _hazards.has(key):
		_hazards[key] = Hazards.roll(region_seed, drift.node(id), region_data.get("hazards", [])) if drift.has(id) else {}
	return _hazards[key]


## The sector the ship is in.
func current_sector():
	return sector_at(current)


## The ship arrives at node `id` (a jump or a tow): in its sector, at the arrival point, flying with `ship`'s numbers.
func _enter(id: String, ship) -> void:
	tide.reset_linger()
	var s = sector_at(id)
	if s == null:
		return
	s.enter()
	_mark_hollow()
	if ship != null:
		s.set_flight(ship)


# --- regions (docs/CONTENT.md section 15) ---------------------------------------------------------------------

## The stages of a run (8).
func stages() -> int:
	return Regions.stages(cfg)


## Is the ship in the ending region (past the last stage)? It has no exit beacon.
func is_final() -> bool:
	return stage > stages()


## The region's name ("The Kett Hives").
func region_name() -> String:
	return str(region_data.get("name", region_id))


## What the map says of where the run is: "Stage 3/8: The Kett Hives", or "Final region: ..." past the last stage.
func stage_text() -> String:
	if is_final():
		return "Final region: " + region_name()
	return "Stage %d/%d: %s" % [stage, stages(), region_name()]


## Is the ship at the region's exit beacon?
func at_exit() -> bool:
	return drift.node(current).get("type", "") == "exit"


## Does the warden still hold this region's exit beacon (wardens.gd)? The ending region has none.
func warden_up() -> bool:
	return not warden.is_empty() and not flags.has(str(warden["flag"]))


## The warden's event at the beacon ({} when it is not up).
func warden_event(ship) -> Dictionary:
	return Wardens.event(warden, self, ship) if warden_up() else {}


## The regions on offer at this region's exit beacon (ids; Regions.offers: the same for the same seed and route).
func region_offers() -> Array:
	return Regions.offers(seed_value, stage, route, cfg)


## Does the player know region `id`'s rarity: scanned (`ship` has a radar that identifies) or known (the flag known_<id>)?
func rarity_known(id: String, ship) -> bool:
	return flags.has("known_" + id) or (ship != null and float(Radar.ranges(ship)["identify_range"]) > 0.0)


## Put the ship at the start of region `id` (the run's first region, a crossing, or a test): its map is rolled from the
## region seed for this stage; what is visited, revealed, the sectors, the recruits on offer and the spool start afresh;
## the flags at_<place> and in_<old region> go and in_<id> is set (for event packs that tag by flag). Flags, the debt,
## reputation, the jump counter and the ship are kept. With a `ship` it arrives in the start's sector.
func enter_region(id: String, ship = null) -> void:
	if drift != null:
		flags.erase("at_" + str(drift.node(current).get("place", "")))
	flags.erase("in_" + region_id)
	region_id = id
	region_data = Regions.get_region(id)
	route.append(id)
	region_seed = Regions.seed_for(seed_value, stage, id)
	drift = Regions.make_map(region_data, cfg, region_seed, is_final())
	current = drift.start_id()
	tide = Tide.make(drift, current, Tide.config(), drift.exit_id(), stage)  # a Hollow tide of the region's own, from its entry
	tide.steps = tide_head()  # a map variant may start it on
	warden = Wardens.for_region(seed_value, stage, region_data, jumps, str(cfg.get("difficulty", "normal")))
	visited = {current: true}
	revealed = {}
	sectors = {}
	offers = {}
	spool = {}
	flags["in_" + id] = true
	if ship != null:
		_enter(current, ship)


## Leave the region from its exit beacon for region `id`, one of region_offers(): the next stage begins at the new
## region's arrival node (the crossing takes no fuel and no jump). Entering stage run.debt_stages + 1 stops Ma's debt
## clock. Returns {ok, why, notes}.
func cross(id: String, ship) -> Dictionary:
	if not at_exit():
		return {"ok": false, "why": NOT_AT_EXIT, "notes": []}
	if not region_offers().has(id):
		return {"ok": false, "why": "that region is not on the beacon's charts", "notes": []}
	var notes := []
	stage += 1
	if stage > int(Regions.run_of(cfg).get("debt_stages", 2)) and debt_stop < 0:
		debt_stop = jumps
		if debt > 0:
			notes.append("Out here %s's collectors can't reach you: the debt clock stops (%d still owed)." % [cfg["debt"]["creditor"], debt])
	enter_region(id, ship)
	notes.append("You jump into %s." % region_name())
	return {"ok": true, "why": "", "notes": notes}


# --- unlocks, landmarks and the end ---------------------------------------------------------------------------

## Earn unlock `id` (data/unlocks.json): kept in the profile at once, and in this run's list when it is new. Returns
## true when the player did not have it yet (the event then says "Unlocked: ...").
func unlock(id: String) -> bool:
	var fresh: bool = profile.unlock(id) if profile != null else not unlocks_earned.has(id)
	if fresh and not unlocks_earned.has(id):
		unlocks_earned.append(id)
		chronicle.append({"jumps": jumps, "kind": "unlock", "id": id, "text": ""})
	return fresh


## A landmark event `id` was met, with its `title`: once in the run log, and once ever in the profile. Returns true when it
## is new to this run.
func note_landmark(id: String, title: String) -> bool:
	if landmarks.has(id):
		return false
	landmarks.append(id)
	chronicle.append({"jumps": jumps, "kind": "landmark", "id": id, "text": title})
	if profile != null:
		profile.record_landmark(id, title)
	return true


## Map variant `id` (the payload `variant` of a map_variant unlock, run_start.gd) is on for this run: the flag variant_<id>, which
## the save keeps, and the Hollow tide of this region and every later one starts its `tide_steps` on (tide_head).
func set_variant(id: String) -> void:
	if id == "":
		return
	flags["variant_" + id] = true
	tide.steps = maxi(tide.steps, tide_head())


## The steps the Hollow tide starts a region with: the greatest `tide_steps` of the map variants on (0 for none).
func tide_head() -> int:
	var n := 0
	for f in flags:
		if str(f).begins_with("variant_"):
			n = maxi(n, Unlocks.tide_steps(str(f).substr(8)))
	return n


## The run is won with ending `id`: the event panel then opens the ending screen.
func finish(id: String) -> void:
	ending = id
	chronicle.append({"jumps": jumps, "kind": "ending", "id": id, "text": ""})


# --- the debt -----------------------------------------------------------------------------------------------

## Does Ma Gantry's debt clock run? Only in the first run.debt_stages stages (2): later regions are too far for the repo
## crew, so from stage 3 no payment falls due, no debt event comes and no rammer is sent (the debt can still be paid).
func debt_running() -> bool:
	return debt_stop < 0


## The jumps the debt clock has counted: the jump counter, held where it stood when the clock stopped.
func debt_jumps() -> int:
	return jumps if debt_stop < 0 else mini(jumps, debt_stop)


## Credits of payments that have fallen due and are not yet covered.
func behind() -> int:
	var d: Dictionary = cfg["debt"]
	return maxi(0, debt_jumps() / int(d["every"]) * int(d["payment"]) - paid)


## How many payments in a row are behind (rounded up).
func misses() -> int:
	return ceili(float(behind()) / float(cfg["debt"]["payment"]))


## Jumps until the next payment date.
func next_due_in() -> int:
	var every := int(cfg["debt"]["every"])
	return every - debt_jumps() % every


## Pay `amount` of the debt (not more than owed). Returns {ok, text}.
func pay_debt(ship, amount: int) -> Dictionary:
	amount = mini(amount, debt)
	if amount <= 0:
		return {"ok": false, "text": "Nothing to pay."}
	if ship.inventory.count("credits") < amount:
		return {"ok": false, "text": "You can't cover %d credits." % amount}
	ship.inventory.add("credits", -amount)
	var lines := _repay(ship, amount)
	return {"ok": true, "text": " ".join(lines)}


## Change the debt by `n` (an event: +50 for a penalty, -100 forgiven). Returns lines saying what happened.
func add_debt(ship, n: int) -> Array:
	if n >= 0:
		debt += n
		return ["Debt %+d" % n] if n != 0 else []
	return _repay(ship, mini(-n, debt))


## `amount` of the debt is paid: a payment on the clock, and the Kettle when it reaches 0.
func _repay(ship, amount: int) -> Array:
	var lines := []
	if amount <= 0:
		return lines
	debt -= amount
	paid += amount
	lines.append("Debt -%d (%d left)" % [amount, debt])
	if behind() == 0:
		flags.erase("debt_missed")
	if debt == 0 and not flags.has("debt_free"):
		flags["debt_free"] = true
		flags.erase("debt_missed")
		var kettle := str(cfg["debt"]["kettle"])
		ship.inventory.add(kettle, 1)
		lines.append("The debt is paid. Ma Gantry sends over %s, with a straight face." % ship.components.def(kettle).get("name", kettle))
	return lines


# --- fights ---------------------------------------------------------------------------------------------------

## The enemy tier from the jump counter: 1, then 2 and 3 at the jumps in data/drift.json.
func tier() -> int:
	var d: Dictionary = cfg["danger"]
	if jumps >= int(d["tier3_from"]):
		return 3
	return 2 if jumps >= int(d["tier2_from"]) else 1


## The design for a `fight` effect: "tier" is the enemy of the current node for the table of its kind (foe_for: a pirate
## node with two payments missed sends the rammer while Ma's clock runs); an entry is a design file or a generated ship
## ("gen:...", gen_spec). Anything else is a design id in data/ships.
func fight_path(value: String, node_type: String) -> String:
	if Shipgen.is_spec(value):  # a generated ship named outright (the exit warden), or a faction to meet ("gen:barons": foe_of)
		return value if value.split(":").size() >= 4 else foe_of(value)
	if value != "tier":
		return value if value.begins_with("res://") else "res://data/ships/%s.json" % value
	var kind := "patrol" if node_type == "patrol" else "pirate"
	if node_type == "hollow" or is_hollow(current):  # a Hollow place sends ghost ships whatever it was
		kind = "hollow"
	elif node_type == "pirate" and misses() >= 2 and debt_running():
		kind = "rammer"
	return foe_for(current, kind)


## The enemy of a fight of `kind` ("pirate", "patrol", "rammer" or "hollow") at node `node_id`: a design path or a generated
## ship's spec. It is rolled the first time it is asked and kept (`foes`, saved), so the event panel can rate it before the fight
## is chosen and the fight is the one that was rated (docs/MECHANICS_REVIEW.md, round 3). The roll has a rng of its own, seeded
## from the run seed, the region seed, the node and the kind, so it never moves the campaign rng; the tier and the budget are
## those of the moment of the first roll.
func foe_for(node_id: String, kind: String) -> String:
	var key := "%s/%s/%s" % [region_id, node_id, kind]
	if not foes.has(key):
		var roll := RandomNumberGenerator.new()
		roll.seed = _foe_seed(node_id, kind)
		var table: Array = cfg["enemies"][kind][str(tier())]
		var pick := str(table[roll.randi() % table.size()])
		foes[key] = gen_spec(pick, kind, roll) if Shipgen.is_spec(pick) else pick
	return foes[key]


## The enemy an event names by its table entry ("gen:barons", "gen:leviathans"): rolled the first time at this node and kept, as
## foe_for does, so the threat the event panel rates is the ship that attacks.
func foe_of(entry: String) -> String:
	var key := "%s/%s/%s" % [region_id, current, entry]
	if not foes.has(key):
		var roll := RandomNumberGenerator.new()
		roll.seed = _foe_seed(current, entry)
		foes[key] = gen_spec(entry, "pirate", roll)
	return foes[key]


func _foe_seed(node_id: String, kind: String) -> int:
	var h := posmod(seed_value, 2147483647) * 31 + posmod(region_seed, 2147483647)
	for ch in ("%s/%s" % [node_id, kind]).to_utf8_buffer():
		h = (h * 131 + ch) % 2147483647
	return h


## A generated enemy (shipgen.gd) for a table entry "gen:<faction>[:ram]"; a bare "gen:" takes the faction the current
## region meets in a fight of `kind` (Shipgen.faction_for). The budget is the tier's, the jumps', the region's danger and the difficulty's
## (docs/CONTENT.md 14), the size class follows from it. Rolls with `roller` (the campaign rng when left out). Returns the
## spec string Session.load_ship() reads.
func gen_spec(entry: String, kind: String, roller: RandomNumberGenerator = null) -> String:
	var r: RandomNumberGenerator = roller if roller != null else rng
	var p := entry.trim_prefix(Shipgen.PREFIX).split(":")
	var faction := p[0] if p[0] != "" else Shipgen.faction_for(region_data, kind)
	var difficulty := str(cfg.get("difficulty", "normal"))
	var budget := maxf(Shipgen.budget_for(tier(), jumps, Shipgen.danger_of(region_data), difficulty, stage), Shipgen.budget_floor(faction, difficulty))
	budget *= Shipgen.budget_mult(faction, r)  # a rare faction (CONTENT 18) fights far above the stage, from the first jump on; the others roll nothing here
	return Shipgen.spec(faction, Shipgen.at_least(faction, Shipgen.pick_size(budget, r)), r.randi(), budget, p.has("ram"), stage)


## The fight is over. `res` is {state, hull, hull_max, enemy (its Ship)}, plus `offer` ({item: count}) when
## spared; `state` is "won" | "captured" | "spared" | "escaped" | "fled" | "lost". A win pays credits (the caller
## then shows Salvage.event_for); a captured ship pays 1.5x the credits and the strip scrap; a spared one pays its
## offer (its credits times the tier) and gives no salvage; an escaped one pays nothing. Won, captured and spared
## count as wins and run `after_win` ({text, effects}). The hull integrity left in the fight is kept. A loss ends
## the run (the caller starts a new campaign). Returns {state, text, lines, goto, fight, ending, threat}: `goto`,
## `fight` and `ending` are what the after_win effects asked for next. `threat` (the skulls of the enemy, 0 when
## the result has none) is handed on for Salvage.event_for.
func fight_done(res: Dictionary, ship, after_win: Dictionary = {}) -> Dictionary:
	var state := str(res.get("state", "fled"))
	var out := {"state": state, "text": "", "lines": [], "goto": "", "fight": "", "ending": "", "threat": int(res.get("threat", 0))}
	if state == "lost":
		out["text"] = "Your ship is wrecked. The Drift keeps what is left of it."
		return out
	if res.has("hull") and res.has("hull_max"):
		hull_loss = clampi(roundi(float(res["hull_max"]) - float(res["hull"])), 0, maxi(roundi(float(res["hull_max"])) - 1, 0))
	if state == "escaped" and after_win.has("clears"):  # the warden left the lane
		flags[str(after_win["clears"])] = true
		out["lines"].append("The lane is clear.")
	if not state in ["won", "captured", "spared"]:
		out["text"] = "They're gone, and whatever they carried went with them." if state == "escaped" else "You break away. The fight is not finished, but you are."
		return out
	fights_won += 1
	out["text"] = "The wreck tumbles away, still venting."
	var ghost := is_hollow(current)  # ghosts pay almost nothing: loot() gives no credits, the strip row is half (salvage.gd)
	if state == "spared" and not ghost:
		out["text"] = "They dump the goods out of the airlock and limp away."
		var offer: Dictionary = res["offer"].duplicate() if res.get("offer") is Dictionary else {}
		if offer.has("credits"):
			offer["credits"] = int(offer["credits"]) * tier()
		out["lines"] = events.apply({"items": offer}, self, ship)["lines"]
	else:
		out["lines"] = loot(res.get("enemy"), ship, state == "captured")
	if ghost:
		out["text"] = "The ghost ship stops firing and drifts off. Nothing it offers is worth taking." if state == "spared" else "The ghost hull goes dark and hangs there, wrong and empty."
	if not after_win.is_empty():
		if str(after_win.get("text", "")) != "":  # replaces the wreck text; a spared ship's goods stay in the story
			out["text"] = (str(out["text"]) + " " if state == "spared" else "") + str(after_win["text"])
		var r: Dictionary = events.apply(after_win.get("effects", {}) if after_win.get("effects") is Dictionary else {}, self, ship, drift.node(current))
		out["lines"].append_array(r["lines"])
		out["goto"] = r["goto"]
		out["fight"] = r["fight"]
		out["ending"] = r["ending"]
	return out


## After a won fight: the credits (times the tier) as lines. No scrap and no part roll: the player picks
## from the wreck instead (salvage.gd). A `captured` ship pays 1.5x the credits and the strip scrap at once. At a Hollow
## place a fight pays almost nothing: no credits and no strip scrap here, and a spared ghost's offer is refused (fight_done).
func loot(enemy, ship, captured := false) -> Array:
	if is_hollow(current):  # a ghost ship pays no credits and no strip scrap here: its plating is a salvage row (salvage.gd)
		return []
	var l: Dictionary = cfg["loot"]
	var credits := rng.randi_range(int(l["credits"][0]), int(l["credits"][1])) * tier()
	if captured:
		credits = roundi(credits * 1.5)
	ship.inventory.add("credits", credits)
	var lines := ["+%d credits" % credits]
	if captured:
		var scrap := Salvage.strip_scrap(enemy, self)
		ship.inventory.add("scrap", scrap)
		lines.append("+%d scrap (stripped)" % scrap)
	return lines


## The salvage event that follows a won fight (a wreck_field one), or {}.
func salvage_event(ship) -> Dictionary:
	var ev := events.pick(self, {"id": current, "type": "wreck_field", "place": ""}, ship)
	events_seen += int(not ev.is_empty())
	return ev


# --- crew --------------------------------------------------------------------------------------------------------

## A name for a new `species` crew member nobody aboard has: from the name pools (crew -> species ->
## names, data/names.json and the packs' names.json through the content loader), else the names of data/crew.json.
func crew_name(species: String, ship) -> String:
	var pool: Array = []
	var crew_pools = Content.names().get("crew")
	if crew_pools is Dictionary and crew_pools.get(species) is Array:
		pool = crew_pools[species]
	if pool.is_empty():
		pool = CrewMember.config().get("names", [])
	var free: Array = pool.filter(func(n): return not ship.crew.any(func(m): return m.name == n))
	if free.is_empty():
		return "Crew %d" % (ship.crew.size() + 1)
	return str(free[rng.randi() % free.size()])


## Put a new crew member of `species` aboard, at the next bed (or near the middle). `who` "" picks a name.
## `character`: the id of a unique character (data/characters.json): they come as themselves (name, species, look and
## ability), and only once. Returns the name, "" if there was no room for a body (or the character is aboard already).
func add_crew(ship, who: String, species: String, character := "") -> String:
	var chr := Characters.entry(character)
	if character != "" and (chr.is_empty() or ship.crew.any(func(m): return m.character == character or m.name == chr["name"])):
		return ""
	if not chr.is_empty():
		who = str(chr["name"])
		species = Characters.species_id(chr)
	elif who == "":
		who = crew_name(species, ship)
	var near := Vector2(ship.grid.size) / 2.0
	var beds: Array = Jobs._beds(ship)
	if not beds.is_empty():
		near = Pathfinder.centre_of(beds[ship.crew.size() % beds.size()])
	var spot: Vector2i = Jobs._free_spot(ship.grid, near, Jobs._anchors(ship))
	if spot == Pathfinder.NO_CELL:
		return ""
	var looks: Array = CrewMember.config()["looks"]
	var ada: Dictionary = CrewMember.config()["ada"]
	var look: Dictionary = ada["look"] if who == str(ada["name"]) else looks[ship.crew.size() % looks.size()]  # Ada comes in her own colours
	var m = Jobs._person(who, look, Pathfinder.centre_of(spot), species)
	if not chr.is_empty():
		Characters.apply(m, character)
	m.backstory()  # their story is fixed the day they join, and saved
	ship.crew.append(m)
	return who


## A random crew member who is not the player leaves for good. Returns their name, "" if there is none.
func lose_crew(ship) -> String:
	var others: Array = ship.crew.filter(func(m): return not m.is_player and not m.is_drone())  # (a drone is no crew)
	if others.is_empty():
		return ""
	var gone = others[rng.randi() % others.size()]
	ship.crew.erase(gone)
	return gone.name


# --- stations -------------------------------------------------------------------------------------------------------

## The menu of node `id`: the station menu of its place (Regions.station: data/drift.json `stations`, or made from its
## region's stock and recruits), or the Scrapper trader's. `id` may also be the place id of a station in any region (its
## menu is the same wherever it is asked for). {} when there is nothing to dock at.
func station_cfg(id: String) -> Dictionary:
	if is_hollow(id):  # no trade in a place the tide has taken
		return {}
	var n := drift.node(id)
	if n.is_empty():
		return Regions.station(id, cfg)
	if str(n.get("place", "")) != "":
		return Regions.station(str(n["place"]), cfg)
	if n.get("type", "") == "trader" and bool(n.get("clan", false)):
		return cfg["stations"]["clan_trader"]
	return {}


## Why the ship cannot dock at `id` ("" if it can).
func dock_block(id: String) -> String:
	var st := station_cfg(id)
	if st.is_empty():
		return "nothing to dock at"
	return REFUSED_TEXT if refuses(str(st.get("faction", ""))) else ""


func _station_faction(id: String) -> String:
	return str(station_cfg(id).get("faction", ""))


## Pay for `n` units of fuel at the station `id`. Returns {ok, text}.
func buy_fuel(ship, id: String, n := 1) -> Dictionary:
	var each := price(int(cfg["fuel"]["price"]), _station_faction(id), ship)
	return _purchase(ship, "fuel", n, each * n, "Fuel")


## The price of `item` in the stock of station `id`, 0 when it is not sold there (`ship`: the buyer's, for a haggler aboard).
func stock_price(id: String, item: String, ship = null) -> int:
	var stock: Dictionary = station_cfg(id).get("stock", {})
	return price(int(stock[item]), _station_faction(id), ship) if stock.has(item) else 0


func buy(ship, id: String, item: String, n := 1) -> Dictionary:
	var each := stock_price(id, item, ship)
	if each <= 0:
		return {"ok": false, "text": "They don't sell that."}
	var r := _purchase(ship, item, n, each * n, ship.crafting.name_of(item, ship.components))
	if r["ok"]:
		Jobs.launch_drones(ship)  # a repair drone bought goes aboard at once
	return r


func _purchase(ship, item: String, n: int, total: int, name: String) -> Dictionary:
	if n <= 0:
		return {"ok": false, "text": "Nothing to buy."}
	if ship.inventory.count("credits") < total:
		return {"ok": false, "text": "%d credits: you have %d." % [total, ship.inventory.count("credits")]}
	ship.inventory.add("credits", -total)
	ship.inventory.add(item, n)
	return {"ok": true, "text": "Bought %d %s for %d credits." % [n, name, total]}


static func _item_kinds() -> Dictionary:
	if _kinds.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
		for i in data["items"]:
			_kinds[str(i["id"])] = str(i.get("kind", ""))
	return _kinds


## What `item` is worth in credits (a sale pays half): by rarity for materials, by tier for parts, a
## fixed figure for unique parts and by kind for other items; fuel and credits at their own price.
func value_of(ship, item: String) -> int:
	var v: Dictionary = cfg["values"]
	if item == "credits":
		return 1
	if item == "fuel":
		return int(cfg["fuel"]["price"])
	if ship.crafting.materials.has(item):
		return int(v["rarity"].get(str(ship.crafting.materials[item].get("rarity", "common")), 1))
	if ship.components.has(item):
		var d: Dictionary = ship.components.def(item)
		return int(v["unique"]) if bool(d.get("unique", false)) else int(v["tier"].get(str(int(d.get("tier", 1))), 40))
	return int(v["kind"].get(str(_item_kinds().get(item, "")), 1))


## Credits one `item` sells for.
func sell_price(ship, item: String) -> int:
	return floori(float(value_of(ship, item)) * float(cfg["prices"]["sell_fraction"]))


## Sell `n` of `item` from the cargo at half its value. Returns {ok, text}.
func sell(ship, item: String, n := 1) -> Dictionary:
	n = mini(n, ship.inventory.count(item))
	var each := sell_price(ship, item)
	if item == "credits" or n <= 0:
		return {"ok": false, "text": "Nothing to sell."}
	if each <= 0:
		return {"ok": false, "text": "They won't pay anything for that."}
	ship.inventory.add(item, -n)
	ship.inventory.add("credits", each * n)
	return {"ok": true, "text": "Sold %d %s for %d credits." % [n, ship.crafting.name_of(item, ship.components), each * n]}


## Repair `points` of hull integrity (the most that is missing) at the repair price per point.
func repair(ship, id: String, points: int) -> Dictionary:
	points = mini(points, hull_loss)
	if points <= 0:
		return {"ok": false, "text": "The hull is sound."}
	var total := price(int(cfg["prices"]["repair"]), _station_faction(id), ship) * points
	if ship.inventory.count("credits") < total:
		return {"ok": false, "text": "%d credits for %d points: you have %d." % [total, points, ship.inventory.count("credits")]}
	ship.inventory.add("credits", -total)
	hull_loss -= points
	return {"ok": true, "text": "Repaired %d points for %d credits." % [points, total]}


## The recruits on offer at station `id`: roll them (species weighted by the station's list, a name each
## that nobody aboard `ship` has).
func roll_offers(id: String, ship) -> Array:
	var weights: Dictionary = station_cfg(id).get("recruit", {})
	var list := []
	var keys: Array = weights.keys()
	keys.sort()
	if not keys.is_empty() and rng.randf() < float(cfg["prices"].get("recruit_chance", 1.0)):  # most stations have nobody to hire
		for i in int(cfg["prices"]["offers"]):
			var total := 0.0
			for k in keys:
				total += float(weights[k])
			var r := rng.randf() * total
			var species := str(keys[-1])
			for k in keys:
				r -= float(weights[k])
				if r < 0.0:
					species = str(k)
					break
			list.append({"species": species, "name": crew_name(species, ship)})
	offers[id] = list
	return list


## Hire offer `index` of station `id` for the recruit price. Returns {ok, text}.
func recruit(ship, id: String, index: int) -> Dictionary:
	var list: Array = offers.get(id, [])
	if index < 0 or index >= list.size():
		return {"ok": false, "text": "Nobody there."}
	var cost := price(int(cfg["prices"]["recruit"]), _station_faction(id), ship)
	if ship.inventory.count("credits") < cost:
		return {"ok": false, "text": "%d credits to hire: you have %d." % [cost, ship.inventory.count("credits")]}
	var who := add_crew(ship, str(list[index].get("name", "")), str(list[index]["species"]))
	if who == "":
		return {"ok": false, "text": "No room aboard for another body."}
	ship.inventory.add("credits", -cost)
	list.remove_at(index)
	return {"ok": true, "text": "%s joins the crew for %d credits." % [who, cost]}


# --- save and load --------------------------------------------------------------------------------------------------------

static func _keys(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


## The whole campaign as plain JSON-friendly data (the rng state is a string: it does not fit a double).
func to_dict() -> Dictionary:
	return {"version": VERSION, "seed": seed_value, "rng_state": str(rng.state), "map": drift.to_dict(), "current": current,
		"visited": _keys(visited), "flags": _keys(flags), "rep": rep.duplicate(), "debt": debt, "paid": paid, "jumps": jumps,
		"used": _keys(used), "revealed": _keys(revealed), "logs_found": _keys(logs_found), "reminded": reminded, "hull_loss": hull_loss,
		"fuel_part": fuel_part, "offers": offers.duplicate(true), "events_seen": events_seen, "fights_won": fights_won,
		"sectors": _sectors_dict(), "spool": spool.duplicate(), "landmarks": landmarks.duplicate(), "unlocks_earned": unlocks_earned.duplicate(),
		"chronicle": chronicle.duplicate(true), "stage": stage, "region": region_id, "route": route.duplicate(), "region_seed": str(region_seed),
		"debt_stop": debt_stop, "tide": tide.to_save(), "warden": warden.duplicate(), "foes": foes.duplicate()}


func _sectors_dict() -> Dictionary:
	var out := {}
	for id in _keys(sectors):
		out[id] = sectors[id].to_save()
	return out


## Replace the state with a saved one. Returns "" on success, else why not (and nothing changes).
func load_dict(d: Dictionary) -> String:
	if int(d.get("version", 0)) < MIN_VERSION or int(d.get("version", 0)) > VERSION:
		return "unsupported campaign version"
	var map = Drift.from_dict(d["map"]) if d.get("map") is Dictionary else null
	if map == null:
		return "bad campaign map"
	var at := str(d.get("current", ""))
	if not map.has(at):
		return "bad campaign position"
	var where = _read_region(d)
	if where == null:
		return "bad campaign region"
	if map.exit_id() == "" and where["stage"] <= Regions.stages(cfg):  # a map from before the regions: Clan space's, made again
		map = Regions.make_map(Regions.get_region(where["region"]), cfg, where["seed"])
		at = map.start_id()
		d = d.duplicate()
		d["visited"] = [at]
		d["revealed"] = []
		d["sectors"] = {}
		d["spool"] = {}
	for k in ["visited", "flags", "used", "revealed", "logs_found"]:
		if not d.get(k) is Array:
			return "bad campaign data"
	if not (d.get("rep") is Dictionary and d.get("offers") is Dictionary and d.has("seed") and d.has("rng_state") and d.has("debt") and d.has("paid") and d.has("jumps") and d.has("hull_loss")):
		return "bad campaign data"
	var made = _read_sectors(d, map, where["seed"], Regions.get_region(where["region"]))
	if made == null:
		return "bad campaign sectors"
	var charge = _read_spool(d, map)
	if charge == null:
		return "bad campaign jump drive"
	var held := Wardens.clean(d.get("warden"), where["region"], where["stage"])  # an older save, or a bad one, rolls its warden again
	if held.is_empty():
		held = Wardens.for_region(int(d["seed"]), where["stage"], Regions.get_region(where["region"]), int(d["jumps"]), str(cfg.get("difficulty", "normal")))
	var rising = Tide.make(map, map.start_id(), Tide.config(), map.exit_id(), where["stage"])
	if d.get("tide") is Dictionary:
		if rising.load_save(d["tide"]) != "":
			return "bad campaign tide"
	elif where["stage"] == 1:
		rising.steps = int(d["jumps"])  # an older save: a fresh tide, at its jump count in the first region
	seed_value = int(d["seed"])
	rng.state = int(str(d["rng_state"]))
	drift = map
	current = at
	visited = _to_set(d["visited"])
	flags = _to_set(d["flags"])
	used = _to_set(d["used"])
	revealed = _to_set(d["revealed"])
	logs_found = _to_set(d["logs_found"])
	reminded = int(d.get("reminded", -1))
	rep = {}
	for f in rep_factions():
		rep[f] = clampi(int(d["rep"].get(f, 0)), -10, 10)
	debt = int(d["debt"])
	paid = int(d["paid"])
	jumps = int(d["jumps"])
	hull_loss = int(d["hull_loss"])
	fuel_part = clampi(int(d.get("fuel_part", 0)), 0, FUEL_PARTS - 1)  # a version 1 save has none
	events_seen = int(d.get("events_seen", 0))  # saves from before the game over screen have none
	fights_won = int(d.get("fights_won", 0))
	landmarks = _texts(d.get("landmarks"))  # saves from before the endings have none of these three
	unlocks_earned = _texts(d.get("unlocks_earned"))
	chronicle = _chronicle(d.get("chronicle"))
	ending = ""
	offers = d["offers"].duplicate(true)
	sectors = made
	spool = charge
	tide = rising
	warden = held
	stage = where["stage"]
	region_id = where["region"]
	region_data = Regions.get_region(region_id)
	route = where["route"]
	region_seed = where["seed"]
	debt_stop = int(d.get("debt_stop", -1)) if d.get("debt_stop") is float or d.get("debt_stop") is int else -1
	foes = {}  # a version 5 save has none rolled: the places roll theirs when asked
	if d.get("foes") is Dictionary:
		for k in d["foes"]:
			if d["foes"][k] is String:
				foes[str(k)] = d["foes"][k]
	last_jump = {}
	_hull_key = -1
	_mark_hollow()  # the flag is not saved: the tide says it
	return ""


## {stage, region, route, seed} of a save; an old one (no `region`) is stage 1 in the run's start region, with the
## region seed a new run of its seed has there. null when malformed.
func _read_region(d: Dictionary):
	if not d.has("region"):
		var start := str(Regions.run_of(cfg)["start"])
		return {"stage": 1, "region": start, "route": [start], "seed": Regions.seed_for(int(d.get("seed", seed_value)), 1, start)}
	var r = d["region"]
	var path = d.get("route")
	var st = d.get("stage")
	if not (r is String and Regions.has(r) and path is Array and not path.is_empty() and path[-1] == r and (st is float or st is int)):
		return null
	if int(st) < 1 or int(st) > Regions.stages(cfg) + 1 or not path.all(func(x): return x is String and Regions.has(x)):
		return null
	if not (d.get("region_seed") is String and str(d["region_seed"]).is_valid_int()):
		return null
	return {"stage": int(st), "region": r, "route": path.map(func(x): return str(x)), "seed": int(str(d["region_seed"]))}


## The sectors of a save (version 3 on), made again from the region seed with their saved states; {} for an older save,
## null when malformed.
static func _read_sectors(d: Dictionary, map, rseed: int, rdata: Dictionary):
	var raw = d.get("sectors", {})
	if not raw is Dictionary:
		return null
	var out := {}
	for id in raw:
		if not (raw[id] is Dictionary and map.has(str(id))):
			return null
		var s = Sector.generate(rseed, map.node(str(id)), str(rdata.get("id", "")), {}, rdata)
		if s.load_save(raw[id]) != "":
			return null
		out[str(id)] = s
	return out


## The jump drive's charge of a save, {} when idle (or an older save), null when malformed.
static func _read_spool(d: Dictionary, map):
	var raw = d.get("spool", {})
	if not raw is Dictionary:
		return null
	if raw.is_empty():
		return {}
	if not (raw.get("to") is String and map.has(raw["to"]) and (raw.get("t") is float or raw.get("t") is int)):
		return null
	return {"to": raw["to"], "t": maxf(float(raw["t"]), 0.0), "drift": bool(raw.get("drift", false)), "blocked": false}


static func _texts(v) -> Array:
	var out := []
	for x in v if v is Array else []:
		out.append(str(x))
	return out


static func _chronicle(v) -> Array:
	var out := []
	for x in v if v is Array else []:
		if x is Dictionary:
			out.append({"jumps": int(x.get("jumps", 0)), "kind": str(x.get("kind", "")), "id": str(x.get("id", "")), "text": str(x.get("text", ""))})
	return out


static func _to_set(list: Array) -> Dictionary:
	var out := {}
	for k in list:
		out[str(k)] = true
	return out


## Write the campaign to `path` (user://campaign.json). Returns "" or why not.
func save(path := SAVE_PATH) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not write " + ProjectSettings.globalize_path(path)
	f.store_string(JSON.stringify(to_dict(), "  "))
	return ""


## Load the campaign at `path`. Returns "" or why not (a missing file included).
func load_file(path := SAVE_PATH) -> String:
	if not FileAccess.file_exists(path):
		return "no saved campaign"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_dict(d) if d is Dictionary else "campaign file is not valid JSON"
