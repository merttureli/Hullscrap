extends RefCounted
## The Drift campaign (docs/CONTENT.md section 8): the state of a run and the rules that move it. The map
## (drift.gd), the current node, what is visited, flags, reputation, Ma Gantry's debt and its clock, the
## jump counter, the `once` events used, the hull integrity lost, the recruits on offer. Jumping, arriving
## (which event happens), fights (design choice, loot, the result), the station trades, save and load.
## Light speed (start_jump, tick_jump: an 8 s spool, no jump with hostiles near) and the sectors the nodes turn into
## (sector.gd, docs/CONTENT.md section 11) are here too; cfg `instant_jump` keeps the beta's instant jump for now.
## No nodes, no drawing: map_view.gd, event_panel.gd and station_panel.gd are thin views over it.
## All randomness is the one RandomNumberGenerator `rng`, seeded with the campaign seed and saved with it,
## so a run replays exactly. Numbers come from data/drift.json, reputation rules from data/factions.json.
## `ship` below is the player's Ship (ship.gd): fuel and credits are cargo items.

const Drift = preload("res://scripts/space/drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Content = preload("res://scripts/data/content.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Salvage = preload("res://scripts/space/salvage.gd")

## Save format. Bump it when the file changes, and keep loading the old ones or refuse them clearly.
## 2 adds `fuel_part` (the fraction of a fuel already used up, docs/waves/engines_1.md); version 1 loads with 0.
## 3 adds `sectors` (the POI states and the ship's place of each sector visited, sector.gd) and `spool` (the jump
## drive's charge); older saves load with no sector yet, so the ship arrives at the arrival point of its node's sector.
const VERSION := 3
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
const TOW_DEBT := 150  ## what Ma adds to the debt for a tow home (tow)
const TOW_FUEL := 2
const HOSTILE_PATROL := {"id": "patrol_hostile", "type": "patrol", "once": false,
	"text": "The Concord cutter does not hail you. It has your registry on a list, and the list has changed. Every gun on her flank swings round at once.",
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
var spool := {}  ## the jump drive spooling: {to, t (seconds charged), drift (the no-fuel jump), blocked}; {} when idle
var last_jump := {}  ## what the last spooled jump did: the jump() result ({ok, why, node, drift, notes})
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
	drift = Drift.generate(rng, cfg)
	current = drift.start_id()
	visited[current] = true
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


## `base` credits at a station of `faction`, discount included (never below 1).
func price(base: int, faction: String) -> int:
	return maxi(1, ceili(float(base) * (1.0 - discount(faction)) - 0.0001))


# --- the map and the fog ---------------------------------------------------------------------------------

func node(id: String) -> Dictionary:
	return drift.node(id)


## Is the node kept off the map for now (a `hidden_until` flag that is not set)?
func is_hidden(id: String) -> bool:
	var h := str(drift.node(id).get("hidden_until", ""))
	return h != "" and not flags.has(h)


## Does the map show the node's type? Visited nodes, the neighbours of visited nodes and revealed
## nodes do; others show "?". A hidden node shows nothing at all.
func is_known(id: String) -> bool:
	if is_hidden(id):
		return false
	if visited.has(id) or revealed.has(id):
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


## What the map calls a node: its name or type when known, "?" otherwise.
func label(id: String) -> String:
	if not is_known(id):
		return "?"
	var n := drift.node(id)
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
	if drift.node(to)["type"] == "gate":
		return DARK_TEXT
	if drift_jump:
		if not fuel_short(ship):
			return "you still have fuel"
		if hull_left(ship) <= int(cfg["fuel"]["drift_hull"]):
			return "the hull would not survive a drift jump"
		return ""
	return NO_FUEL if fuel_short(ship) else ""


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


## Time passes by `n` jumps: the counter goes up and each payment date crossed is checked.
func _advance(n: int) -> Array:
	var notes := []
	var d: Dictionary = cfg["debt"]
	for i in n:
		jumps += 1
		if debt > 0 and jumps % int(d["every"]) == 0:
			if behind() > 0:
				flags["debt_missed"] = true
				notes.append("%s's collectors have noted a missed payment." % d["creditor"])
			else:
				notes.append("A payment fell due, and you are paid up.")
	return notes


## With no fuel: wait for a passing trader. Time passes (one jump on the counter) and a trader event
## may come along. Returns {ok, why, notes, event}.
func wait(ship) -> Dictionary:
	if ship.inventory.count("fuel") > 0:
		return {"ok": false, "why": "you still have fuel", "notes": [], "event": {}}
	var notes := _advance(1)
	var ev := events.pick(self, {"id": current, "type": "trader", "place": ""}, ship)
	events_seen += int(not ev.is_empty())
	return {"ok": true, "why": "", "notes": notes, "event": ev}


## Stranded with no fuel: call Ma Gantry for a tow back to Gantry Rusthold. It costs TOW_DEBT on the debt and a
## jump's time, and she throws in TOW_FUEL fuel. Always possible with no fuel, so a run can't soft-lock.
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
	notes.append("Ma's tug drags you home: debt +%d, fuel +%d" % [TOW_DEBT, TOW_FUEL])
	return {"ok": true, "why": "", "notes": notes}


## What happens on reaching the current node. Returns {node, refused, event}: `refused` is the text of a
## dock master who turns you away (a faction below the refusal line), `event` the event to show ({} if
## none). A debt event (Ma's call, a reminder, the collectors' talk) interrupts the node's own event. At a
## station you may dock at the flag at_<place> is set (until you jump away), its recruits are rolled, and
## the event is one of its greetings.
func arrive(ship) -> Dictionary:
	var n := drift.node(current)
	var out := {"node": n, "refused": "", "event": {}}
	var st := station_cfg(current)
	if not st.is_empty():
		if refuses(str(st.get("faction", ""))):
			out["refused"] = REFUSED_TEXT
			return out
		if str(n["place"]) != "":
			flags["at_" + str(n["place"])] = true  # docked: the station greetings ask for it
		if st["services"].has("recruit"):
			roll_offers(current, ship)
	if n["type"] != "gate":
		var due := _debt_event(ship)
		if not due.is_empty():
			out["event"] = due
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
		reminded = jumps / int(cfg["debt"]["every"])
	return ev


## Is it the moment for debt event `e`? See _debt_event.
func _debt_timing(e: Dictionary) -> bool:
	var every := int(cfg["debt"]["every"])
	match Events.debt_kind(e):
		"miss":
			return jumps > 1 and (jumps - 1) % every == 0 and behind() > 0
		"reminder":
			return debt > 0 and next_due_in() <= 2 and reminded != jumps / every
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

## The region of node `id`: that of its nearest landmark (a fixed place of the map; the landmark of each region is
## in data/sectors.json): clans (Rusthold), concord (Meridian), lumen (the Prism), else the boneyard. Regions are not on
## the map yet.
func region_of(id: String) -> String:
	return _region_in(drift, id)


static func _region_in(map, id: String) -> String:
	var here: Dictionary = map.node(id)
	var near := ""
	var near_d := INF
	for n in map.nodes:
		if str(n.get("place", "")) == "" or here.is_empty():
			continue
		var d: float = here["pos"].distance_to(n["pos"])
		if d < near_d or (d == near_d and str(n["id"]) < near):
			near = str(n["id"])
			near_d = d
	var regions: Dictionary = Sector.config()["regions"]
	var fallback := "boneyard"
	for r in regions:
		if str(regions[r]["landmark"]) == "":
			fallback = str(r)
		elif near != "" and str(regions[r]["landmark"]) == near:
			return str(r)
	return fallback


## The sector of node `id`: made from the campaign seed and the node the first time it is asked for, the same every
## time. null for a node the map does not have.
func sector_at(id: String):
	if not sectors.has(id):
		if not drift.has(id):
			return null
		sectors[id] = Sector.generate(seed_value, drift.node(id), region_of(id))
	return sectors[id]


## The sector the ship is in.
func current_sector():
	return sector_at(current)


## The ship arrives at node `id` (a jump or a tow): in its sector, at the arrival point, flying with `ship`'s numbers.
func _enter(id: String, ship) -> void:
	var s = sector_at(id)
	if s == null:
		return
	s.enter()
	if ship != null:
		s.set_flight(ship)


# --- the debt -----------------------------------------------------------------------------------------------

## Credits of payments that have fallen due and are not yet covered.
func behind() -> int:
	var d: Dictionary = cfg["debt"]
	return maxi(0, jumps / int(d["every"]) * int(d["payment"]) - paid)


## How many payments in a row are behind (rounded up).
func misses() -> int:
	return ceili(float(behind()) / float(cfg["debt"]["payment"]))


## Jumps until the next payment date.
func next_due_in() -> int:
	var every := int(cfg["debt"]["every"])
	return every - jumps % every


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


## The design file for a `fight` effect: "tier" rolls from the table of the node's kind (a pirate node
## with two payments missed sends the rammer), anything else is a design id in data/ships.
func fight_path(value: String, node_type: String) -> String:
	if value != "tier":
		return value if value.begins_with("res://") else "res://data/ships/%s.json" % value
	var kind := "patrol" if node_type == "patrol" else "pirate"
	if node_type == "pirate" and misses() >= 2:
		kind = "rammer"
	var table: Array = cfg["enemies"][kind][str(tier())]
	return str(table[rng.randi() % table.size()])


## The fight is over. `res` is {state, hull, hull_max, enemy (its Ship)}, plus `offer` ({item: count}) when
## spared; `state` is "won" | "captured" | "spared" | "escaped" | "fled" | "lost". A win pays credits (the caller
## then shows Salvage.event_for); a captured ship pays 1.5x the credits and the strip scrap; a spared one pays its
## offer (its credits times the tier) and gives no salvage; an escaped one pays nothing. Won, captured and spared
## count as wins and run `after_win` ({text, effects}). The hull integrity left in the fight is kept. A loss ends
## the run (the caller starts a new campaign). Returns {state, text, lines, goto, fight}: `goto` and `fight` are
## what the after_win effects asked for next.
func fight_done(res: Dictionary, ship, after_win: Dictionary = {}) -> Dictionary:
	var state := str(res.get("state", "fled"))
	var out := {"state": state, "text": "", "lines": [], "goto": "", "fight": ""}
	if state == "lost":
		out["text"] = "Your ship is wrecked. The Drift keeps what is left of it."
		return out
	if res.has("hull") and res.has("hull_max"):
		hull_loss = clampi(roundi(float(res["hull_max"]) - float(res["hull"])), 0, maxi(roundi(float(res["hull_max"])) - 1, 0))
	if not state in ["won", "captured", "spared"]:
		out["text"] = "They're gone, and whatever they carried went with them." if state == "escaped" else "You break away. The fight is not finished, but you are."
		return out
	fights_won += 1
	out["text"] = "The wreck tumbles away, still venting."
	if state == "spared":
		out["text"] = "They dump the goods out of the airlock and limp away."
		var offer: Dictionary = res["offer"].duplicate() if res.get("offer") is Dictionary else {}
		if offer.has("credits"):
			offer["credits"] = int(offer["credits"]) * tier()
		out["lines"] = events.apply({"items": offer}, self, ship)["lines"]
	else:
		out["lines"] = loot(res.get("enemy"), ship, state == "captured")
	if not after_win.is_empty():
		if str(after_win.get("text", "")) != "":  # replaces the wreck text; a spared ship's goods stay in the story
			out["text"] = (str(out["text"]) + " " if state == "spared" else "") + str(after_win["text"])
		var r: Dictionary = events.apply(after_win.get("effects", {}) if after_win.get("effects") is Dictionary else {}, self, ship, drift.node(current))
		out["lines"].append_array(r["lines"])
		out["goto"] = r["goto"]
		out["fight"] = r["fight"]
	return out


## After a won fight: the credits (times the tier) as lines. No scrap and no part roll: the player picks
## from the wreck instead (salvage.gd). A `captured` ship pays 1.5x the credits and the strip scrap at once.
func loot(enemy, ship, captured := false) -> Array:
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
## Returns the name, "" if there was no room for a body.
func add_crew(ship, who: String, species: String) -> String:
	if who == "":
		who = crew_name(species, ship)
	var near := Vector2(ship.grid.size) / 2.0
	var beds: Array = Jobs._beds(ship)
	if not beds.is_empty():
		near = Pathfinder.centre_of(beds[ship.crew.size() % beds.size()])
	var spot: Vector2i = Jobs._free_spot(ship.grid, near, Jobs._anchors(ship))
	if spot == Pathfinder.NO_CELL:
		return ""
	var looks: Array = CrewMember.config()["looks"]
	var m = Jobs._person(who, looks[ship.crew.size() % looks.size()], Pathfinder.centre_of(spot), species)
	ship.crew.append(m)
	return who


## A random crew member who is not the player leaves for good. Returns their name, "" if there is none.
func lose_crew(ship) -> String:
	var others: Array = ship.crew.filter(func(m): return not m.is_player)
	if others.is_empty():
		return ""
	var gone = others[rng.randi() % others.size()]
	ship.crew.erase(gone)
	return gone.name


# --- stations -------------------------------------------------------------------------------------------------------

## The menu of node `id`: data/drift.json `stations` entry of the place, or the Scrapper trader's. {} when
## there is nothing to dock at.
func station_cfg(id: String) -> Dictionary:
	var n := drift.node(id)
	var st: Dictionary = cfg["stations"]
	if str(n.get("place", "")) != "" and st.has(n["place"]):
		return st[n["place"]]
	if n.get("type", "") == "trader" and bool(n.get("clan", false)):
		return st["clan_trader"]
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
	var each := price(int(cfg["fuel"]["price"]), _station_faction(id))
	return _purchase(ship, "fuel", n, each * n, "Fuel")


## The price of `item` in the stock of station `id`, 0 when it is not sold there.
func stock_price(id: String, item: String) -> int:
	var stock: Dictionary = station_cfg(id).get("stock", {})
	return price(int(stock[item]), _station_faction(id)) if stock.has(item) else 0


func buy(ship, id: String, item: String, n := 1) -> Dictionary:
	var each := stock_price(id, item)
	if each <= 0:
		return {"ok": false, "text": "They don't sell that."}
	return _purchase(ship, item, n, each * n, ship.crafting.name_of(item, ship.components))


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
	var total := price(int(cfg["prices"]["repair"]), _station_faction(id)) * points
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
	if not keys.is_empty():
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
	var cost := price(int(cfg["prices"]["recruit"]), _station_faction(id))
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
		"sectors": _sectors_dict(), "spool": spool.duplicate()}


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
	for k in ["visited", "flags", "used", "revealed", "logs_found"]:
		if not d.get(k) is Array:
			return "bad campaign data"
	if not (d.get("rep") is Dictionary and d.get("offers") is Dictionary and d.has("seed") and d.has("rng_state") and d.has("debt") and d.has("paid") and d.has("jumps") and d.has("hull_loss")):
		return "bad campaign data"
	var made = _read_sectors(d, map)
	if made == null:
		return "bad campaign sectors"
	var charge = _read_spool(d, map)
	if charge == null:
		return "bad campaign jump drive"
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
	offers = d["offers"].duplicate(true)
	sectors = made
	spool = charge
	last_jump = {}
	_hull_key = -1
	return ""


## The sectors of a save (version 3), made again from the seed with their saved states; {} for an older save, null when
## malformed.
static func _read_sectors(d: Dictionary, map):
	var raw = d.get("sectors", {})
	if not raw is Dictionary:
		return null
	var out := {}
	for id in raw:
		if not (raw[id] is Dictionary and map.has(str(id))):
			return null
		var s = Sector.generate(int(d["seed"]), map.node(str(id)), _region_in(map, str(id)))
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
