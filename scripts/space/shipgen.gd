extends RefCounted
## Procedural enemy ships (docs/CONTENT.md sections 4c, 14 and 18; the tables are data/enemy_tables.json).
## Shipgen.build(faction, size, seed, budget) gives a Ship that is valid by construction and checked (validate()):
##   1. the LOADOUT is bought from the budget out of the faction's menu (weapons, shield layers and sectors, engine tiers,
##      armour layers, crew, the pilot's aim_skill, systems), with the reactors the power needs;
##   2. the DECKS are planned from it (a gun deck, the decks between with the bridge, quarters, reactor and shield rooms and
##      the flank turrets, and the engine room), and hullgen.gd draws the faction's silhouette round them;
##   3. the hull is built (armour layers on the outer walls, rooms carved from the floor, doors, parts, mounts placed
##      through the real mount rules, cables) and checked; a failed attempt is retried with a new roll, then a plainer hull.
## Everything random goes through one RandomNumberGenerator seeded from (seed, faction, size), so the same arguments
## always give the same ship. A ship has meta "ai" ({aim_skill, style}, read by the pilot) and "shipgen" (what it was).
## A spec is the same arguments as a string, "gen:<faction>:<size>:<seed>:<budget x 100>[:s<stage>][:ram][:warden]", so a design path can name
## a generated ship (combat_session.gd load_ship). threat() rates an enemy against the player's ship (threat.gd).

const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Content = preload("res://scripts/data/content.gd")
const Hullgen = preload("res://scripts/space/hullgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const HullOutline = preload("res://scripts/ship/hull_outline.gd")
const Morale = preload("res://scripts/combat/morale.gd")

const PREFIX := "gen:"
const TABLES_PATH := "res://data/enemy_tables.json"
const STYLES_PATH := "res://data/ship_styles.json"
const RACE_SHARE := 0.6  ## the share of a home region's pirate fights that meet the region's own race (a region's `race_share` says otherwise)
const MAX_ATTEMPTS := 10
const MARGIN := 4  ## free cells round the hull in the grid (a mount's outside half is up to 3 deep)
const HULL_MARGIN := 2  ## the buildable hull is everything built plus this
const MAX_FILL := 0.84  ## the solid area of a hull over its bounding box, at most (the tests say 0.85)
const MID_H := 4  ## floor rows of a deck between the gun deck and the engine room
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const AMMO_STOCK := 40  ## units of ammo a weapon that uses some starts with
const ESSENTIAL := 1  ## rooms of this priority or better (the helm room, the reactors) are never dropped for lack of floor

static var _tables := {}
static var _tables_for := ["", ""]  # Content.root and packs_root the tables were read for
static var _defs: Components = null
static var _lines := {}
static var _weapons: Weapons = null
static var _powers := {}  # part id -> its line-adjusted power
static var _turrets := {}  # weapon id -> is it a turret
static var last_failed: Array = []  ## why the attempts of the last build() failed (all of them when it returned null)


# --- data ----------------------------------------------------------------------------------------

## data/enemy_tables.json, read once, with the `factions` of every pack's enemy_tables.json added (a pack may not replace a faction
## that is already there). Read again when the content loader is pointed elsewhere.
static func tables() -> Dictionary:
	if _tables.is_empty() or _tables_for[0] != Content.root or _tables_for[1] != Content.packs_root:
		var data = JSON.parse_string(FileAccess.get_file_as_string(TABLES_PATH))
		assert(data is Dictionary and data.get("factions") is Dictionary, "bad enemy tables: " + TABLES_PATH)
		for p in Content.packs():
			var more = JSON.parse_string(FileAccess.get_file_as_string(p["dir"] + "/enemy_tables.json")) if FileAccess.file_exists(p["dir"] + "/enemy_tables.json") else null
			if more is Dictionary and more.get("factions") is Dictionary:
				for id in more["factions"]:
					if not data["factions"].has(id):
						data["factions"][id] = more["factions"][id]
		_add_races(data)
		_tables = data
		_tables_for = [Content.root, Content.packs_root]
	return _tables


## The race styles of data/ship_styles.json and of every pack's ship_styles.json (a race already there is kept) become factions of
## `data`: the table of the style's `base` faction with the style laid over it (see the file's _doc). The race's own id is the faction id.
static func _add_races(data: Dictionary) -> void:
	var races := {}
	var files: Array = [STYLES_PATH]
	for p in Content.packs():
		files.append(p["dir"] + "/ship_styles.json")
	for path in files:
		var more = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if more is Dictionary and more.get("races") is Dictionary:
			for id in more["races"]:
				if not races.has(id):
					races[id] = more["races"][id]
	var names = Content.names()
	var crews = names.get("crew", {}) if names is Dictionary else {}
	for id in races:
		var st: Dictionary = races[id]
		if data["factions"].has(id) or not data["factions"].has(str(st.get("base", ""))):
			continue
		var f: Dictionary = data["factions"][str(st["base"])].duplicate(true)
		f["race"] = id
		f["lines_as"] = str(st["base"])  # the faction whose voice lines (data/morale.json) it says
		f["name_pool"] = ""
		f["ship_names"] = st.get("ship_names", [])
		f["crew"] = st.get("crew", f["crew"]).duplicate(true)
		if crews is Dictionary and crews.get(str(f["crew"]["species"][0])) is Array:
			f["crew"]["names"] = crews[str(f["crew"]["species"][0])]
		for k in ["ai", "weights", "hull"]:
			if st.get(k) is Dictionary:
				f[k].merge(st[k].duplicate(true), true)
		if st.get("parts") is Dictionary:
			for cat in st["parts"]:
				if cat == "base":
					f["parts"]["base"].merge(st["parts"]["base"], true)
				else:
					f["parts"][cat] = st["parts"][cat].duplicate(true)
		if st.get("armour") is Dictionary:
			f["armour"]["tiles"] = st["armour"]["tiles"].duplicate()
			f["armour"]["factor"].merge(st["armour"].get("factor", {}), true)
		if st.has("cost_mult"):  # the tuning knob of a style's weapon prices (never its budget): dearer guns, fewer of them
			for m in f["parts"]["weapons"]:
				m["cost"] = snappedf(float(m["cost"]) * float(st["cost_mult"]), 0.1)
		if st.get("prefer") is Dictionary:  # a race with no pack of its own leans on some parts of the base menu: those weights x the factor
			for cat in st["prefer"]:
				for m in f["parts"].get(cat, []):
					if st["prefer"][cat].has(m["id"]):
						m["weight"] = float(m.get("weight", 1)) * float(st["prefer"][cat][m["id"]])
		f["style"] = st["style"].duplicate(true)
		data["factions"][id] = f


static func _comps() -> Components:
	if _defs == null:
		_defs = Components.new()
		_defs.load_defs(Ship.COMPONENTS_PATH)
		_lines = Stats.load_lines()
		_weapons = Weapons.new()
	return _defs


static func _def(id: String) -> Dictionary:
	return _comps().def(id)


static func _power(id: String) -> float:
	if not _powers.has(id):
		_powers[id] = float(Stats.effective(_def(id), _lines)["power"])
	return _powers[id]


static func _is_turret(id: String) -> bool:
	if not _turrets.has(id):
		_comps()
		_turrets[id] = bool(_weapons.def(id)["turret"])
	return _turrets[id]


static func factions() -> Array:
	var out: Array = tables()["factions"].keys()
	out.sort()
	return out


# --- budget, size, faction, spec -----------------------------------------------------------------

## The budget of a fight (docs/CONTENT.md 14): tier base x (1 + 0.04 x jumps) x the region's danger x the difficulty x the run
## stage's `stage_mult` (stages 1 to 3 fight with 70% of it; `stage` 0 or a later one: 1).
static func budget_for(tier: int, jumps: int, danger: float, difficulty := "normal", stage := 0) -> float:
	var b: Dictionary = tables()["budget"]
	return float(b["tier_base"][str(clampi(tier, 1, 3))]) * (1.0 + float(b["per_jump"]) * jumps) * danger * float(b["difficulty"].get(difficulty, 1.0)) * float(b.get("stage_mult", {}).get(str(stage), 1.0))


## The most likely an enemy of run stage `stage` (1 to 8; 0 = unknown) is to carry a shield: `shield_cap` of the budget table, 1 for the later stages.
static func shield_cap(stage: int) -> float:
	return float(tables()["budget"].get("shield_cap", {}).get(str(stage), 1.0))


## The danger of a region (`region` is its data, data/regions/*.json: the `danger` field; 1.0 for {}).
static func danger_of(region: Dictionary) -> float:
	return float(region.get("danger", 1.0))


## The size class a budget buys: medium and large from the thresholds of the table, blurred by the seed.
static func pick_size(budget: float, rng: RandomNumberGenerator) -> String:
	var b: Dictionary = tables()["budget"]
	var j := float(b["size_jitter"])
	var medium := float(b["size_from"]["medium"]) * (1.0 + rng.randf_range(-j, j))
	var large := float(b["size_from"]["large"]) * (1.0 + rng.randf_range(-j, j))
	return "large" if budget >= large else ("medium" if budget >= medium else "small")


## The faction met in `region` (its data) in a fight of `kind` ("pirate" or "patrol"): the pirates are the region's `enemies`
## faction; a patrol is the Concord's, unless the region is held by the Wardens or the Hollow, whose guards patrol it.
static func faction_for(region: Dictionary, kind: String) -> String:
	var enemies := str(region.get("enemies", "rustfangs"))
	if kind == "patrol" and enemies != "wardens" and enemies != "hollow":
		return "concord"
	return enemies if tables()["factions"].has(enemies) else "rustfangs"


## The least stage budget a rare faction is built for (CONTENT 18: `budget_floor` in its table, times the difficulty), so it is
## dangerous at the first jumps too; 0 for the others.
static func budget_floor(faction: String, difficulty := "normal") -> float:
	return float(tables()["factions"].get(faction, {}).get("budget_floor", 0.0)) * float(tables()["budget"]["difficulty"].get(difficulty, 1.0))


## The budget factor a rare faction fights at over the stage's budget (CONTENT 18: `budget_mult` [least, most] in its table), rolled
## with `rng`; 1.0 for a faction with none (and no roll is made, so the others' ships do not move).
static func budget_mult(faction: String, rng: RandomNumberGenerator) -> float:
	var m = tables()["factions"].get(faction, {}).get("budget_mult")
	return rng.randf_range(float(m[0]), float(m[1])) if m is Array and m.size() == 2 else 1.0


## `size` or, for a faction with a `min_size` (heavy hulls only), the bigger of the two.
static func at_least(faction: String, size: String) -> String:
	var order: Array = ["small", "medium", "large"]
	var want := str(tables()["factions"].get(faction, {}).get("min_size", "small"))
	return size if order.find(size) >= order.find(want) else want


## `warden`: the ship holds a beacon (Wardens.for_region), ":warden": it never fades (see build).
static func spec(faction: String, size: String, seed_value: int, budget: float, ram := false, stage := 0, warden := false) -> String:
	return "%s%s:%s:%d:%d%s%s%s" % [PREFIX, faction, size, seed_value, roundi(budget * 100.0), ":s%d" % stage if shield_cap(stage) < 1.0 else "", ":ram" if ram else "", ":warden" if warden else ""]


static func is_spec(path: String) -> bool:
	return path.begins_with(PREFIX)


## The ship a spec names, or null when it is malformed.
static func from_spec(text: String) -> Ship:
	var p := text.trim_prefix(PREFIX).split(":")
	if p.size() < 4 or not tables()["factions"].has(p[0]) or not tables()["sizes"].has(p[1]):
		return null
	var stage := 0  # an early stage's enemies carry a shield less often (shield_cap): ":s<stage>"
	for x in p.slice(4):
		if x.length() > 1 and x.begins_with("s") and x.substr(1).is_valid_int():
			stage = int(x.substr(1))
	var opts := {"ram": p.slice(4).has("ram"), "stage": stage, "warden": p.slice(4).has("warden")}
	var at := p.slice(4).find("role")  # ":role:<id>" pins the role (the tools measure each role); a spec without it rolls the role from its seed
	if at >= 0 and at + 1 < p.slice(4).size() and tables().get("roles", {}).get("list", {}).has(p.slice(4)[at + 1]):
		opts["role"] = p.slice(4)[at + 1]
	return build(p[0], p[1], int(p[2]), float(p[3]) / 100.0, opts)


# --- building ------------------------------------------------------------------------------------

## The enemy ship for (faction, size class, seed, budget). `opts`: ram (true: a Rustfang rammer, a ram plated V bow and the
## rammer style; false: never; left out: a faction whose pilots ram does so by the seed), stage (the run stage: in an early one
## the ship has a shield only with the chance of shield_cap(stage), rolled from the seed; the rare factions ignore it), warden (it
## holds a beacon: a style that fades, the Hollow's ghosts, becomes `hollow`, so the Hollow's warden stays a fight to the end). Always a valid ship (see
## validate()); meta "shipgen".attempts says how many tries it took.
static func build(faction: String, size: String, seed_value: int, budget: float, opts := {}) -> Ship:
	var f: Dictionary = tables()["factions"][faction]
	var ram := bool(opts["ram"]) if opts.has("ram") else false
	if not opts.has("ram"):
		var roll := RandomNumberGenerator.new()
		roll.seed = _mix(seed_value, faction, size, 99)
		ram = roll.randf() < float(f["ai"]["rammer"]) and size != "small"
	var role := str(opts["role"]) if opts.has("role") else pick_role(faction, size, seed_value)
	if role != "" and not opts.has("ram") and bool(tables()["roles"]["list"][role].get("ram", false)) and float(f["ai"]["rammer"]) > 0.0 and size != "small":
		ram = true  # a brawler of a faction whose pilots ram rams
	var shields := true
	var cap := shield_cap(int(opts.get("stage", 0)))
	if cap < 1.0 and not f.has("budget_mult"):
		var sroll := RandomNumberGenerator.new()
		sroll.seed = _mix(seed_value, faction, size, 98)
		shields = sroll.randf() < cap
	var failed: Array = []
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = _mix(seed_value, faction, size, attempt)
		var r := _attempt(faction, size, rng, budget, ram, attempt, shields, role)
		if r["ship"] != null:
			var ship: Ship = r["ship"]
			ship.get_meta("shipgen")["attempts"] = attempt + 1
			ship.get_meta("shipgen")["failed"] = failed
			ship.get_meta("shipgen")["seed"] = seed_value
			if bool(opts.get("warden", false)) and Morale.fades_style(str(ship.get_meta("ai").get("morale", ""))):
				ship.get_meta("ai")["morale"] = "hollow"
			return ship
		failed.append(r["why"])
	last_failed = failed
	return null


## Why `ship` (a generated one or any) is not a valid enemy: [] when it is fine. Power covers the demand and every part is
## on it, every room holds air, every floor cell can be reached by a crew body from the helm, every mount is placed by the
## mount rules, it can fly, it has a gun, and it is no rectangle.
static func validate(ship: Ship, max_fill := 0.85) -> Array:
	var bad: Array = []
	ship.refresh()
	for n in ship.power_state["networks"]:
		if float(n["supply"]) + 0.0001 < float(n["demand"]):
			bad.append("network %d: supply %s under demand %s" % [n["id"], str(n["supply"]), str(n["demand"])])
	for uid in ship.components.instances:
		if not ship.power_state["powered"].get(uid, false):
			bad.append("%s is not powered" % ship.components.instances[uid]["id"])
	for r in ship.atmosphere.rooms:
		if not r["sealed"]:
			bad.append("room %d is not sealed" % r["id"])
	var pockets := HullOutline.pockets(ship)
	if not pockets.is_empty():
		bad.append("%d floor cells no crew body reaches" % pockets.size())
	var guns := 0
	var comps: Components = ship.components
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var d: Dictionary = comps.def(inst["id"])
		if Mounts.is_mount(d):
			if not comps.has_outside(uid) or not comps.link_intact(ship.grid, uid):
				bad.append("%s has no whole mount" % inst["id"])
			if str(d["family"]) == "weapon":
				guns += 1
	if guns == 0:
		bad.append("no weapon")
	var f := Flight.new()
	if f.can_fly(comps, ship.power_state["powered"]) != "":
		bad.append("cannot fly: " + f.can_fly(comps, ship.power_state["powered"]))
	var area := 0.0
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in ship.grid.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
		area += ship.grid.area_at(c)
	if area >= max_fill * (hi.x - lo.x + 1) * (hi.y - lo.y + 1):
		bad.append("a rectangle (%.0f%% of its box)" % (100.0 * area / ((hi.x - lo.x + 1) * (hi.y - lo.y + 1))))
	return bad


## 1-5 skulls for `enemy` against `player`: Threat.rate()'s {skulls, ratio, enemy, player}.
static func threat(enemy: Ship, player: Ship) -> Dictionary:
	return Threat.rate(enemy, player)


## The threat rating of a design (a generated spec or a design file) against the player's ship, Threat.rate()'s dictionary;
## {} when the design does not load. For the radar and the HUD: a contact's design path in, its skulls out.
static func threat_of(design: String, player: Ship) -> Dictionary:
	var enemy: Ship = from_spec(design) if is_spec(design) else Ship.from_design(design)
	return {} if enemy == null else Threat.rate(enemy, player)


# --- roles ---------------------------------------------------------------------------------------------------

## The roles a faction flies (data/enemy_tables.json "roles"): the `per_faction` whose favoured category its weights rate highest (ties by the table's order).
static func roles_of(faction: String) -> Array:
	var cfg: Dictionary = tables()["roles"]
	var w: Dictionary = tables()["factions"][faction]["weights"]
	var keyed: Array = []
	var i := 0
	for id in cfg["list"]:
		keyed.append([-float(w.get(cfg["list"][id]["favours"], 1)), i, id])
		i += 1
	keyed.sort()
	var ids: Array = keyed.map(func(k): return k[2])
	return ids.slice(0, int(cfg["per_faction"]))


## The role of the ship of (faction, size, seed), rolled from the seed and weighted by the faction's own weights; "" for a faction with no roles.
static func pick_role(faction: String, size: String, seed_value: int) -> String:
	var cfg: Dictionary = tables()["roles"]
	var w: Dictionary = tables()["factions"][faction]["weights"]
	var order: Array = ["small", "medium", "large"]
	var pool: Array = []
	var total := 0.0
	for id in roles_of(faction):
		var r: Dictionary = cfg["list"][id]
		if order.find(size) < order.find(str(r.get("min_size", "small"))):
			continue
		pool.append(id)
		total += float(w.get(r["favours"], 1))
	if pool.is_empty():
		return ""
	var roll := RandomNumberGenerator.new()
	roll.seed = _mix(seed_value, faction, size, 97)
	var x := roll.randf() * total
	for id in pool:
		x -= float(w.get(cfg["list"][id]["favours"], 1))
		if x < 0.0:
			return str(id)
	return str(pool[pool.size() - 1])


## `f` with a role laid over it: its weights times the role's, the weight of a long-range gun times the sniper's bias. A copy; the tables stay as they are.
static func _with_role(f: Dictionary, role: String) -> Dictionary:
	if role == "":
		return f
	var r: Dictionary = tables()["roles"]["list"][role]
	var out := f.duplicate(true)
	for k in r["weights"]:
		out["weights"][k] = float(out["weights"].get(k, 1)) * float(r["weights"][k])
	if r.has("range_from"):
		_comps()
		for m in out["parts"]["weapons"]:
			if _weapons.has(str(m["id"])) and float(_weapons.def(str(m["id"]))["range"]) >= float(r["range_from"]):
				m["weight"] = float(m.get("weight", 1)) * float(r["range_bias"])
	return out


static func _mix(seed_value: int, faction: String, size: String, attempt: int) -> int:
	var h := posmod(seed_value, 2147483647) * 31 + attempt * 40503 + 7
	for ch in (faction + "/" + size).to_utf8_buffer():
		h = (h * 131 + ch) % 2147483647
	return h + 1


## One try at a ship: {ship (null when it failed), why}.
static func _attempt(faction: String, size: String, rng: RandomNumberGenerator, budget: float, ram: bool, attempt: int, shields := true, role := "") -> Dictionary:
	var f: Dictionary = _with_role(tables()["factions"][faction], role)
	var sz: Dictionary = tables()["sizes"][size]
	var level := 2 if attempt < 4 else (1 if attempt < 7 else 0)
	var lo := _buy(f, size, budget, rng, ram, shields)
	var t: int = int(lo["armour"]) + 1
	var prow := rng.randi_range(int(f["hull"]["prow"][0]), int(f["hull"]["prow"][1]))
	var tail := rng.randi_range(int(f["hull"]["tail"][0]), int(f["hull"]["tail"][1]))
	if size == "small":
		prow = mini(prow, 2)
		tail = mini(tail, 1)
	if ram:
		prow = maxi(prow, 5)  # a V bow needs rows to widen over
	var bands: Array = []
	var ras := {}
	var why_not := "a rectangle"
	for boost in 4:  # a hull too much of a box is reshaped harder
		bands = _plan(lo, sz, f, boost, prow, tail)
		var y := t
		var avoid: Array = []  # rows whose flanks carry a turret stay flat
		for b in bands:
			b["y0"] = y
			b["y1"] = y + int(b["h"]) - 1
			y = int(b["y1"]) + 2
			if b["rooms"].any(func(r): return r["kind"] == "turret"):
				avoid.append([b["y0"], b["y1"]])
		var rows: int = y - 1 + t
		Hullgen.extents(f, bands, int(sz["max_interior"]), rng, boost, t)
		var hull := Hullgen.make(f, bands, t, rows, rng, {"level": level, "ram": ram, "avoid": avoid, "boost": boost})
		var r := Hullgen.raster(hull["outline"])
		if not r["errors"].is_empty():
			why_not = "outline: " + str(r["errors"][0])
		elif Hullgen.fill_ratio(r["cells"]) < float(f["hull"].get("max_fill", MAX_FILL)):
			ras = r
			break
		else:
			why_not = "a rectangle (%.2f, t %d, boost %d)" % [Hullgen.fill_ratio(r["cells"]), t, boost]
	if ras.is_empty():
		return {"ship": null, "why": why_not}
	var made := _construct(f, faction, lo, bands, ras["cells"], t, ram, rng)
	if made["ship"] == null:
		return made
	var ship: Ship = made["ship"]
	var why := validate(ship, float(f["hull"].get("max_fill", MAX_FILL)) + 0.01)
	if not why.is_empty():
		return {"ship": null, "why": str(why[0])}
	var parts := {"weapon": [], "engine": [], "shield": [], "reactor": []}  # what stands in the hull, not what was bought
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var id := str(ship.components.instances[uid]["id"])
		var family := str(ship.components.def(id).get("family", ""))
		if parts.has(family):
			parts[family].append(id)
	ship.set_meta("shipgen", {"faction": faction, "size": size, "budget": budget, "spent": lo["spent"], "ram": ram, "level": level,
		"weapons": parts["weapon"], "engines": parts["engine"], "shields": parts["shield"], "reactors": parts["reactor"],
		"armour": lo["armour"], "crew": lo["crew"], "skill": lo["skill"], "role": role})
	var look := style_of(faction, size, role, budget)
	if not look.is_empty():
		ship.set_meta("style", look)
	return {"ship": ship, "why": ""}


# --- the loadout ---------------------------------------------------------------------------------

## What the budget buys: {weapons, engines, shields, reactors, systems, armour, crew, skill, beds, spent}.
## The base ship (helm, life support, the faction's cheapest reactor, two engines, one gun) is free; every purchase
## after it is drawn from the faction's weights and has to fit the hull's limits and the power its reactors give.
static func _buy(f: Dictionary, size: String, budget: float, rng: RandomNumberGenerator, ram: bool, shields := true) -> Dictionary:
	var T := tables()
	_comps()
	var mx: Dictionary = T["sizes"][size]["max"].duplicate()
	if ram:
		mx["bow"] = 1
	if not shields:  # the stage's roll said no shield: none of the shield room is for sale
		mx["shield"] = 0
	var parts: Dictionary = f["parts"]
	var base: Dictionary = parts["base"]
	var ai: Dictionary = f["ai"]
	var engines: Array = _menu(parts["engines"], budget)
	var lo := {"weapons": [str(base["weapon"])], "engines": [], "shields": [], "systems": [], "reactors": [], "armour": 0,
		"crew": 2, "skill": float(ai["aim_skill"][0]), "beds": 0, "spent": 0.0, "helm": str(base["helm"]), "o2": str(base["o2"])}
	for _i in 2:
		lo["engines"].append(str(engines[0]["id"]))
	var cfg: Dictionary = T["budget"]
	var ctx := _power_ctx(f, mx, budget)
	var spent := _rplan(ctx, _demand(f, lo))  # the reactor the base ship needs, above the free one
	if spent < 0.0:  # not even the best reactors carry two engines: fly on one
		lo["engines"].pop_back()
		spent = maxf(_rplan(ctx, _demand(f, lo)), 0.0)
	for _step in 80:
		var options: Array = _options(f, size, lo, mx, budget, budget - spent, cfg, ctx)
		if options.is_empty():
			break
		var total := 0.0
		for o in options:
			total += float(o["weight"])
		var roll := rng.randf() * total
		var pick: Dictionary = options[options.size() - 1]
		for o in options:
			roll -= float(o["weight"])
			if roll < 0.0:
				pick = o
				break
		_apply(lo, pick)
		spent += float(pick["cost"])
	lo["reactors"] = _reactors(f, lo, mx, budget)["ids"]
	lo["spent"] = spent
	lo["beds"] = mini(int(mx["beds"]), (int(lo["crew"]) + 1) / 2)
	return lo


## The menu items of a category for sale at this budget, cheapest first.
static func _menu(items: Array, budget: float) -> Array:
	var out: Array = items.filter(func(m): return float(m.get("from", 0)) <= budget)
	out.sort_custom(func(a, b): return float(a["cost"]) < float(b["cost"]))
	return out


static func _item(f: Dictionary, cat: String, id: String) -> Dictionary:
	for m in f["parts"].get(cat, []):
		if m["id"] == id:
			return m
	return {}


## The power the loadout draws (a positive number), reactors left out; radiators included.
static func _demand(f: Dictionary, lo: Dictionary) -> float:
	var d := 0.0
	var ids: Array = [lo["helm"], lo["o2"]] + lo["weapons"] + lo["engines"] + lo["shields"] + lo["systems"]
	for id in ids:
		d -= minf(_power(str(id)), 0.0)
	var rad := 0
	for id in lo["weapons"]:
		rad += int(_item(f, "weapons", id).get("needs", {}).get("radiator", 0))
	return d + rad * absf(_power("radiator"))


## The cheapest reactors (at most `mx.reactor` of them) that cover `lo`'s demand: {ids, cost (above the free base reactor), net}
## ({} ids when the hull cannot hold enough). A reactor that comes with radiators gives that much less.
static func _reactors(f: Dictionary, lo: Dictionary, mx: Dictionary, budget: float) -> Dictionary:
	var plan := _reactor_plan(f, lo, mx, _menu(f["parts"]["reactors"], budget))
	if plan["ids"].is_empty():  # nothing for sale at this budget carries the base ship: the best reactor is on it anyway
		plan = _reactor_plan(f, lo, mx, _menu(f["parts"]["reactors"], 1e9))
	return plan


static func _reactor_plan(f: Dictionary, lo: Dictionary, mx: Dictionary, menu: Array) -> Dictionary:
	var need := _demand(f, lo)
	var base_cost := 0.0
	for m in f["parts"]["reactors"]:
		if m["id"] == f["parts"]["base"]["reactor"]:
			base_cost = float(m["cost"])
	var best := {"ids": [], "cost": 1e9, "net": 0.0}
	var rad := absf(_power("radiator"))
	for count in range(1, int(mx["reactor"]) + 1):
		for combo in _multisets(menu.size(), count):
			var supply := 0.0
			var cost := 0.0
			var ids: Array = []
			for k in combo:
				var m: Dictionary = menu[k]
				supply += _power(str(m["id"])) - rad * int(m.get("needs", {}).get("radiator", 0))
				cost += float(m["cost"])
				ids.append(str(m["id"]))
			if supply + 0.0001 >= need * 1.02 and cost < float(best["cost"]) - 1e-9:
				best = {"ids": ids, "cost": cost, "net": supply}
	if best["ids"].is_empty():
		return {"ids": [], "cost": 0.0, "net": 0.0}
	best["cost"] = maxf(0.0, float(best["cost"]) - base_cost)
	return best


## Every multiset of `count` indices below `n`, as sorted lists.
static func _multisets(n: int, count: int) -> Array:
	var out: Array = []
	var cur: Array = []
	_multi(n, count, 0, cur, out)
	return out


static func _multi(n: int, count: int, from: int, cur: Array, out: Array) -> void:
	if cur.size() == count:
		out.append(cur.duplicate())
		return
	for k in range(from, n):
		cur.append(k)
		_multi(n, count, k, cur, out)
		cur.pop_back()


## The numbers of the reactor choice for one buy: the menu on sale, the whole menu (for a base ship nothing on sale carries),
## the most reactors the hull holds, the cost of the free base reactor, and a cache of plans by demand.
static func _power_ctx(f: Dictionary, mx: Dictionary, budget: float) -> Dictionary:
	var rad := absf(_power("radiator"))
	var on_sale: Array = []
	var every: Array = []
	for m in _menu(f["parts"]["reactors"], 1e9):
		var e := {"cost": float(m["cost"]), "net": _power(str(m["id"])) - rad * int(m.get("needs", {}).get("radiator", 0))}
		every.append(e)
		if float(m.get("from", 0)) <= budget:
			on_sale.append(e)
	var base_cost := 0.0
	for m in f["parts"]["reactors"]:
		if m["id"] == f["parts"]["base"]["reactor"]:
			base_cost = float(m["cost"])
	return {"sale": on_sale, "all": every, "cap": int(mx["reactor"]), "base": base_cost, "cache": {}}


## The cost, above the free base reactor, of the cheapest reactors that carry `need` power; -1 when the hull holds none that do.
static func _rplan(ctx: Dictionary, need: float) -> float:
	var key := roundi(need * 100.0)
	if ctx["cache"].has(key):
		return ctx["cache"][key]
	var cost := _cheapest_supply(ctx["sale"], int(ctx["cap"]), need)
	if cost < 0.0:
		cost = _cheapest_supply(ctx["all"], int(ctx["cap"]), need)
	if cost >= 0.0:
		cost = maxf(0.0, cost - float(ctx["base"]))
	ctx["cache"][key] = cost
	return cost


static func _cheapest_supply(menu: Array, cap: int, need: float) -> float:
	var best := -1.0
	for count in range(1, cap + 1):
		for combo in _multisets(menu.size(), count):
			var supply := 0.0
			var cost := 0.0
			for k in combo:
				supply += float(menu[k]["net"])
				cost += float(menu[k]["cost"])
			if supply + 0.0001 >= need * 1.02 and (best < 0.0 or cost < best - 1e-9):
				best = cost
	return best


## Every purchase the budget left could make now: [{cat, id, cost (with the reactor it needs), weight}].
static func _options(f: Dictionary, size: String, lo: Dictionary, mx: Dictionary, budget: float, left: float, cfg: Dictionary, ctx: Dictionary) -> Array:
	var parts: Dictionary = f["parts"]
	var w: Dictionary = f["weights"]
	var demand := _demand(f, lo)
	var here := maxf(_rplan(ctx, demand), 0.0)
	var raw: Array = []  # [option, demand it adds]
	for m in _menu(parts["weapons"], budget):
		if _slots_ok(lo["weapons"] + [m["id"]], mx):
			var add := -minf(_power(str(m["id"])), 0.0) + int(m.get("needs", {}).get("radiator", 0)) * absf(_power("radiator"))
			raw.append([{"cat": "weapons", "id": m["id"], "cost": float(m["cost"]), "weight": float(m.get("weight", 1))}, add])
	if int(lo["armour"]) < int(mx["armour"]):
		var tiles: Array = f["armour"]["tiles"]
		var tile := str(tiles[mini(int(lo["armour"]), tiles.size() - 1)])
		raw.append([{"cat": "armour", "id": tile, "cost": float(f["layer_cost"][size]) * float(f["armour"]["factor"].get(tile, 1.0)), "weight": 1.0}, 0.0])
	for m in _menu(parts["shields"], budget):
		var draw := -minf(_power(str(m["id"])), 0.0)
		if lo["shields"].size() < int(mx["shield"]):
			raw.append([{"cat": "shield", "id": m["id"], "cost": float(m["cost"]), "weight": float(m.get("weight", 1)), "mode": "add"}, draw])
		elif not lo["shields"].is_empty():
			var worst := _cheapest(f, "shields", lo["shields"])
			if float(m["cost"]) > float(worst["cost"]):
				raw.append([{"cat": "shield", "id": m["id"], "cost": float(m["cost"]) - 0.5 * float(worst["cost"]), "weight": float(m.get("weight", 1)), "mode": "swap", "old": worst["id"]}, draw + minf(_power(str(worst["id"])), 0.0)])
	var cur := _item(f, "engines", lo["engines"][0])
	var cur_cost := float(cur["cost"])
	var cur_draw := -minf(_power(str(cur["id"])), 0.0)
	if lo["engines"].size() < int(mx["engine"]):
		raw.append([{"cat": "engine", "id": cur["id"], "cost": cur_cost, "weight": 1.0, "mode": "add"}, cur_draw])
	for m in _menu(parts["engines"], budget):
		if float(m["cost"]) > cur_cost:
			var n: int = lo["engines"].size()
			raw.append([{"cat": "engine", "id": m["id"], "cost": n * (float(m["cost"]) - cur_cost), "weight": 1.0, "mode": "tier"}, n * (-minf(_power(str(m["id"])), 0.0) - cur_draw)])
	if int(lo["crew"]) < int(mx["crew"]):
		raw.append([{"cat": "crew", "id": "", "cost": float(cfg["crew_cost"]), "weight": 1.0}, 0.0])
	if float(lo["skill"]) + float(cfg["skill_step"]) <= float(f["ai"]["aim_skill"][1]) + 1e-6:
		raw.append([{"cat": "skill", "id": "", "cost": float(cfg["skill_cost"]), "weight": 1.0}, 0.0])
	for m in _menu(parts["systems"], budget):
		if lo["systems"].count(m["id"]) < (3 if m["id"] == "radiator" else 1):
			raw.append([{"cat": "systems", "id": m["id"], "cost": float(m["cost"]), "weight": float(m.get("weight", 1))}, -minf(_power(str(m["id"])), 0.0)])
	var count := {}
	for r in raw:
		count[r[0]["cat"]] = int(count.get(r[0]["cat"], 0)) + 1
	var out: Array = []
	for r in raw:
		var o: Dictionary = r[0]
		var plan := _rplan(ctx, demand + float(r[1]))
		if plan < 0.0:
			continue
		var extra: float = float(o["cost"]) + plan - here
		if extra > left + 1e-6:
			continue
		o["cost"] = maxf(extra, 0.0)
		o["weight"] = float(w.get(o["cat"], 1)) * float(o["weight"]) / float(count[o["cat"]])
		if o["weight"] > 0.0:
			out.append(o)
	return out


static func _cheapest(f: Dictionary, cat: String, ids: Array) -> Dictionary:
	var best: Dictionary = {}
	for id in ids:
		var m := _item(f, cat, id)
		if best.is_empty() or float(m["cost"]) < float(best["cost"]):
			best = m
	return best


## Do these weapons fit the hull? Fixed guns only go on the bow; turrets fill the flank slots, then what is left of the bow.
static func _slots_ok(ids: Array, mx: Dictionary) -> bool:
	var fixed := 0
	var turrets := 0
	for id in ids:
		if _is_turret(str(id)):
			turrets += 1
		else:
			fixed += 1
	return fixed <= int(mx["bow"]) and turrets <= int(mx["bow"]) - fixed + int(mx["flank"])


static func _apply(lo: Dictionary, o: Dictionary) -> void:
	match str(o["cat"]):
		"weapons":
			lo["weapons"].append(o["id"])
		"armour":
			lo["armour"] = int(lo["armour"]) + 1
		"shield":
			if o.get("mode", "add") == "swap":
				lo["shields"][lo["shields"].find(o["old"])] = o["id"]
			else:
				lo["shields"].append(o["id"])
		"engine":
			if o["mode"] == "add":
				lo["engines"].append(o["id"])
			else:
				for i in lo["engines"].size():
					lo["engines"][i] = o["id"]
		"crew":
			lo["crew"] = int(lo["crew"]) + 1
		"skill":
			lo["skill"] = float(lo["skill"]) + float(tables()["budget"]["skill_step"])
		"systems":
			lo["systems"].append(o["id"])


# --- the decks -----------------------------------------------------------------------------------

## The decks of the ship, bow to stern: [{kind, h, need (floor width), rooms: [{kind, w, flex, pri, pad, parts: [{id, dx, dy}],
## mounts: [{id, rot}]}]}]. The flank turrets sit in the widest decks (core, aux) so the flanks stay flat; the bridge deck
## (quarters, the helm) stays narrow. What does not fit a deck's share of the widest floor is dropped, the lowest priority first.
static func _plan(lo: Dictionary, sz: Dictionary, f: Dictionary, boost := 0, prow := 0, tail := 0) -> Array:
	var maxw := int(sz["max_interior"])
	var share: Dictionary = f["hull"]["band"]
	var mx: Dictionary = sz["max"]
	var bow: Array = []
	var flank: Array = []
	for id in lo["weapons"]:
		if not _is_turret(str(id)):
			bow.append(id)
	for id in lo["weapons"]:
		if _is_turret(str(id)):
			if flank.size() < int(mx["flank"]):
				flank.append(id)
			else:
				bow.append(id)
	if bow.is_empty() and not flank.is_empty():  # a ship with only turrets has the first on the bow, where it is sure to stand
		bow.append(flank.pop_front())
	bow = bow.slice(0, maxi(1, int(mx["bow"]) - maxi(0, boost - 1)))  # a hull still too boxy gives up bow guns and engines
	var bands: Array = []
	var gun := _mount_band("gun", bow, 0, prow)
	var weapon_rads := 0
	for id in lo["weapons"]:
		weapon_rads += int(_item(f, "weapons", id).get("needs", {}).get("radiator", 0))
	if weapon_rads > 0:  # radiators cool the room they stand in: the heat of a beam lance is in the gun room
		var room: Dictionary = gun["rooms"][0]
		room["pad"] = 2 * weapon_rads
		room["w"] = int(room["w"]) + 2 * weapon_rads
		for k in weapon_rads:
			room["parts"].append({"id": "radiator", "dx": -2 * (k + 1), "dy": 0})
		gun["need"] = room["w"]
	bands.append(gun)
	var reactors: Array = []
	for id in lo["reactors"]:
		var w := int(_def(id)["size"][0])
		var r: Array = [{"id": id, "dx": 0, "dy": 0}]
		var need := int(_item(f, "reactors", id).get("needs", {}).get("radiator", 0))
		for k in need:
			r.append({"id": "radiator", "dx": w, "dy": 2 * k})
		reactors.append(_room("reactor", w + (2 if need > 0 else 0), 1, r))
	var shields: Array = []
	for id in lo["shields"]:
		shields.append(_room("shield", int(_def(id)["size"][0]), 2, [{"id": id, "dx": 0, "dy": 0}]))
	var util: Array = []
	var bought := 0
	for id in lo["systems"]:
		if id == "radiator":
			bought += 1
		else:
			util.append(_room("util", int(_def(id)["size"][0]), 4, [{"id": id, "dx": 0, "dy": 0}]))
	var rads: Array = []
	if bought > 0:
		var rr: Array = []
		for k in bought:
			rr.append({"id": "radiator", "dx": 2 * (k / 2), "dy": 2 * (k % 2)})
		rads.append(_room("util", 2 * ((bought + 1) / 2), 4, rr))
	var helm_room := _room("bridge", 4, 0, [{"id": lo["helm"], "dx": 0, "dy": 0}, {"id": lo["o2"], "dx": 2, "dy": 0}])
	helm_room["flex"] = true
	var beds: Array = []
	for k in int(lo["beds"]):
		beds.append({"id": "bed", "dx": 2 * k, "dy": 0})
	var quarters := _room("quarters", 2 * beds.size(), 5, beds)
	quarters["flex"] = true
	var t_left: Array = []
	var t_right: Array = []
	for i in flank.size():
		(t_right if i % 2 == 0 else t_left).append(flank[i])
	var k_mid := int(sz["k_mid"])
	if k_mid == 1:
		var mid: Array = reactors.slice(0, 1) + [helm_room] + shields.slice(0, 1)
		bands.append(_deck("core", mid, maxw, share))
	else:
		var br: Array = []
		if quarters["w"] > 0:
			br.append(quarters)
		br.append(helm_room)
		br.append_array(rads)
		bands.append(_deck("bridge", br, maxw, share))
		var core: Array = reactors.duplicate()
		var aux: Array = []
		if k_mid >= 3:
			aux = shields + util
		else:
			core.append_array(shields + util)
		bands.append(_deck("core", _flanked(core, t_left, t_right, 0), maxw, share))
		if k_mid >= 3:
			var rooms := _flanked(aux, t_left, t_right, 1)
			if rooms.is_empty():
				var cargo := _room("cargo", 6, 9, [])
				cargo["flex"] = true
				rooms.append(cargo)
			bands.append(_deck("aux", rooms, maxw, share))
	bands.append(_mount_band("engine", lo["engines"].slice(0, maxi(2, lo["engines"].size() - maxi(0, boost - 2))), 2, tail))
	return bands


## `rooms` with the flank turret number `k` of each side at its ends (left: rot 3, right: rot 1).
static func _flanked(rooms: Array, t_left: Array, t_right: Array, k: int) -> Array:
	var out: Array = []
	if t_left.size() > k:
		out.append(_turret_room(t_left[k], 3))
	out.append_array(rooms)
	if t_right.size() > k:
		out.append(_turret_room(t_right[k], 1))
	return out


static func _room(kind: String, w: int, pri: int, parts: Array) -> Dictionary:
	return {"kind": kind, "w": w, "flex": false, "pri": pri, "pad": 0, "parts": parts, "mounts": []}


static func _turret_room(id: String, rot: int) -> Dictionary:
	var r := _room("turret", Mounts.turned(_def(id)["size"], rot).x, 3, [])
	r["mounts"] = [{"id": id, "rot": rot}]
	return r


## A deck made of `rooms` in this order; the rooms of the highest `pri` go first when they do not fit `maxw`.
static func _deck(kind: String, rooms: Array, maxw: int, share: Dictionary) -> Dictionary:
	var list := rooms.duplicate()
	var cap := maxi(roundi(float(share.get(kind, 1.0)) * maxw), 4)
	while list.size() > 1 and _width(list) > cap:
		var drop := 0
		for i in list.size():
			if int(list[i]["pri"]) >= int(list[drop]["pri"]):
				drop = i
		list.remove_at(drop)
	return {"kind": kind, "h": MID_H, "need": _width(list), "rooms": list}


static func _width(rooms: Array) -> int:
	var w := 0
	for r in rooms:
		w += int(r["w"]) + 1
	return maxi(w - 1, 0)


## The gun deck (rot 0) or the engine room (rot 2): one room whose mounts stand side by side.
static func _mount_band(kind: String, ids: Array, rot: int, extra := 0) -> Dictionary:
	var w := 0
	var h := 2
	var mounts: Array = []
	for id in ids:
		var sz: Vector2i = Mounts.turned(_def(str(id))["size"], rot)
		w += sz.x + (1 if kind == "engine" and not mounts.is_empty() else 0)
		h = maxi(h, sz.y)
		mounts.append({"id": id, "rot": rot})
	var room := _room(kind, w, 0, [])
	room["mounts"] = mounts
	room["flex"] = true
	return {"kind": kind, "h": h + extra, "need": w, "rooms": [room]}


# --- construction --------------------------------------------------------------------------------

## Build the ship: tiles and armour from the outline's cells, the rooms carved from the floor, doors, parts, mounts, cables.
static func _construct(f: Dictionary, faction: String, lo: Dictionary, bands: Array, raw_cells: Dictionary, t: int, ram: bool, rng: RandomNumberGenerator) -> Dictionary:
	var cells_lo := Vector2i(1 << 20, 1 << 20)
	var cells_hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in raw_cells:
		cells_lo = cells_lo.min(c)
		cells_hi = cells_hi.max(c)
	var off := Vector2i(MARGIN, MARGIN) - cells_lo
	var cells := {}
	for c in raw_cells:
		# float32 noise can leave a whole cell a hair under 1 and the rasterizer calls it the full round2 piece: it is a plain cell
		cells[c + off] = {} if not raw_cells[c].is_empty() and Shapes.area_of(raw_cells[c]) > 0.9999 else raw_cells[c]
	for b in bands:
		b["x0"] = int(b["x0"]) + off.x
		b["x1"] = int(b["x1"]) + off.x
		b["y0"] = int(b["y0"]) + off.y
		b["y1"] = int(b["y1"]) + off.y
	var grid_size := cells_hi - cells_lo + Vector2i.ONE + Vector2i(MARGIN, MARGIN) * 2
	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new("Enemy", ShipGrid.new(grid_size, defs))
	var g: ShipGrid = ship.grid
	for y in grid_size.y:
		for x in grid_size.x:
			g.hull[Vector2i(x, y)] = true
	# tiles: armour layers on the outer walls, steel behind them, the rest floor to be carved into rooms
	var layers := int(lo["armour"])
	var armour: Array = f["armour"]["tiles"]
	var depth := _depths(cells)
	var ram_rows := int(bands[0]["y1"]) + t + 1
	var fset := {}
	for c in cells:
		var d: int = depth[c]
		var tile := "floor"
		if d < layers:
			tile = str(armour[mini(d, armour.size() - 1)])
		elif d == layers:
			tile = "wall"
		if ram and d <= layers and c.y < ram_rows:
			tile = str(f["armour"].get("ram", "ram_plating"))
		if tile == "floor" and cells[c].is_empty():
			fset[c] = true
			tile = "wall"
		g.force_tile(c, tile, cells[c])
	# rooms
	var decks: Array = []
	for b in bands:
		var rect := _rect_of(fset, b)
		if rect.size.x < 2:
			return {"ship": null, "why": "a deck has no floor"}
		var rooms := _lay_rooms(b["rooms"], rect)
		if rooms.is_empty():
			return {"ship": null, "why": "a deck is too narrow for its essential rooms"}
		decks.append({"band": b, "rect": rect, "rooms": rooms})
		for r in rooms:
			for y in range(r["rect"].position.y, r["rect"].end.y):
				for x in range(r["rect"].position.x, r["rect"].end.x):
					g.force_tile(Vector2i(x, y), "floor")
	# doors
	var door_why := _doors(g, decks)
	if door_why != "":
		return {"ship": null, "why": door_why}
	# parts
	var comps: Components = ship.components
	var spine := str(f["hull"].get("spine", ""))
	if spine != "":
		for c in fset:
			if g.get_tile(c) == "wall" and absi(c.x - (decks[0]["rect"].position.x + decks[0]["rect"].size.x / 2)) <= 1:
				g.force_tile(c, spine)
	var placed := {"helm": false, "o2": false, "reactor": false, "engine": false}
	for d in decks:
		for r in d["rooms"]:
			for p in r["room"]["parts"]:
				var dx := int(p["dx"])
				var origin: Vector2i = r["rect"].position if dx >= 0 else Vector2i(r["rect"].end.x, r["rect"].position.y)
				var uid := comps.place(g, str(p["id"]), origin + Vector2i(dx, int(p["dy"])), 0)
				if uid < 0:
					if p["id"] == lo["helm"] or p["id"] == lo["o2"] or _is_reactor(str(p["id"])):
						return {"ship": null, "why": "a vital part did not fit: " + str(p["id"])}
				elif p["id"] == lo["helm"]:
					placed["helm"] = true
		_place_mounts(ship, d, placed)
	if not placed["helm"] or not placed["engine"]:
		return {"ship": null, "why": "no helm or no engine"}
	# the cables, then the finishing touches
	if not _wire(ship):
		return {"ship": null, "why": "no route to a part"}
	_trim(ship)
	_finish(ship, f, faction, lo, rng, ram)
	return {"ship": ship, "why": ""}


static func _is_reactor(id: String) -> bool:
	return str(_def(id).get("family", "")) == "reactor"


## BFS depth from the skin (shaped cells and cells next to space) into the hull.
static func _depths(cells: Dictionary) -> Dictionary:
	var depth := {}
	var queue: Array = []
	for c in cells:
		var skin: bool = not cells[c].is_empty()
		if not skin:
			for d in SIDES:
				if not cells.has(c + d):
					skin = true
					break
		if skin:
			depth[c] = 0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in SIDES:
			var n: Vector2i = c + d
			if cells.has(n) and not depth.has(n):
				depth[n] = int(depth[c]) + 1
				queue.append(n)
	return depth


## The floor rectangle of a deck: its rows, from the widest span every row has round the deck's middle.
static func _rect_of(fset: Dictionary, b: Dictionary) -> Rect2i:
	var mid: int = (int(b["x0"]) + int(b["x1"])) / 2
	var lo_x := -(1 << 20)
	var hi_x := 1 << 20
	for y in range(int(b["y0"]), int(b["y1"]) + 1):
		var x := mid
		if not fset.has(Vector2i(x, y)):
			var found := false
			for dx in range(1, 9):
				if fset.has(Vector2i(mid + dx, y)):
					x = mid + dx
					found = true
					break
				if fset.has(Vector2i(mid - dx, y)):
					x = mid - dx
					found = true
					break
			if not found:
				return Rect2i()
		var a := x
		while fset.has(Vector2i(a - 1, y)):
			a -= 1
		var z := x
		while fset.has(Vector2i(z + 1, y)):
			z += 1
		lo_x = maxi(lo_x, a)
		hi_x = mini(hi_x, z)
	if hi_x - lo_x + 1 < 2:
		return Rect2i()
	return Rect2i(lo_x, int(b["y0"]), hi_x - lo_x + 1, int(b["y1"]) - int(b["y0"]) + 1)


## Cut a deck's rectangle into its rooms with a one cell wall between them; spare width goes to the flexible rooms first.
## Returns [{room (the plan's room), rect}] left to right.
static func _lay_rooms(rooms: Array, rect: Rect2i) -> Array:
	var list: Array = rooms.duplicate()
	while list.size() > 1 and _width(list) > rect.size.x:
		var drop := 0
		for i in list.size():
			if int(list[i]["pri"]) >= int(list[drop]["pri"]):
				drop = i
		if int(list[drop]["pri"]) <= ESSENTIAL:
			return []  # the rooms a ship cannot do without do not fit this deck
		list.remove_at(drop)
	var widths: Array = []
	for r in list:
		widths.append(int(r["w"]))
	var slack := rect.size.x - _width(list)
	if slack < 0:  # one room wider than the floor: it takes the floor
		widths[0] = int(widths[0]) + slack
		slack = 0
	var givers: Array = []
	for i in list.size():
		if list[i]["flex"]:
			givers.append(i)
	if givers.is_empty():
		for i in list.size():
			if list[i]["kind"] != "turret":
				givers.append(i)
	if givers.is_empty():
		givers = [list.size() - 1]
	var k := 0
	while slack > 0:
		widths[givers[k % givers.size()]] += 1
		slack -= 1
		k += 1
	var out: Array = []
	var x := rect.position.x
	for i in list.size():
		out.append({"room": list[i], "rect": Rect2i(x, rect.position.y, widths[i], rect.size.y)})
		x += widths[i] + 1
	return out


## Doors: one between each pair of neighbouring rooms of a deck, and one joining each deck to the next.
static func _doors(g: ShipGrid, decks: Array) -> String:
	for d in decks:
		var rooms: Array = d["rooms"]
		for i in range(rooms.size() - 1):
			var a: Rect2i = rooms[i]["rect"]
			var placed := false
			var mid := a.position.y + (a.size.y - 2) / 2
			for dy in [0, 1, -1, 2, -2]:
				var y: int = mid + dy
				if y >= a.position.y and y + 1 < a.end.y + 0 and g.place_door("door", Vector2i(a.end.x, y), Vector2i.DOWN):
					placed = true
					break
			if not placed:
				return "no door between rooms %d and %d of the %s deck at %s" % [i, i + 1, rooms[i]["room"]["kind"], str(a)]
	for i in range(decks.size() - 1):
		var up: Array = decks[i]["rooms"]
		var down: Array = decks[i + 1]["rooms"]
		var row: int = decks[i]["rect"].end.y
		var best: Array = []
		for u in up:
			for v in down:
				var lo_x := maxi(u["rect"].position.x, v["rect"].position.x)
				var hi_x := mini(u["rect"].end.x, v["rect"].end.x)
				if hi_x - lo_x >= 2 and (best.is_empty() or hi_x - lo_x > best[1] - best[0]):
					best = [lo_x, hi_x]
		if best.is_empty():
			return "no rooms overlap between decks %d and %d: %s / %s" % [i, i + 1, str(up.map(func(r): return [r["room"]["kind"], r["rect"]])), str(down.map(func(r): return [r["room"]["kind"], r["rect"]]))]
		var placed := false
		var centre: int = (best[0] + best[1] - 2) / 2
		for dx in [0, 1, -1, 2, -2, 3, -3]:
			var x: int = centre + dx
			if x >= best[0] and x + 2 <= best[1] and g.place_door("door", Vector2i(x, row), Vector2i.RIGHT):
				placed = true
				break
		if not placed:
			return "no door between decks %d and %d at %s" % [i, i + 1, str(best)]
	return ""


## Place the mounts of a deck through the mount rules: the outside half against a flat stretch of the outer wall.
static func _place_mounts(ship: Ship, d: Dictionary, placed: Dictionary) -> void:
	for r in d["rooms"]:
		var mounts: Array = r["room"]["mounts"]
		if mounts.is_empty():
			continue
		var rect: Rect2i = r["rect"]
		var total := 0
		for m in mounts:
			total += _along(str(m["id"]), int(m["rot"])).x
		var vertical := int(mounts[0]["rot"]) % 2 == 1
		var span: int = (rect.size.y if vertical else rect.size.x) - int(r["room"]["pad"])
		var at: int = (rect.position.y if vertical else rect.position.x) + maxi(0, (span - total) / 2)
		for m in mounts:
			var id := str(m["id"])
			var w: int = _along(id, int(m["rot"])).x
			var lo_c: int = rect.position.y if vertical else rect.position.x
			var hi_c: int = (rect.end.y if vertical else rect.end.x) - w
			for shift in [0, 1, -1, 2, -2, 3, -3]:
				var pos: int = at + shift
				if pos < lo_c or pos > hi_c:
					continue
				var out := _out_anchor(ship.grid, id, int(m["rot"]), pos)
				if out.x < -900:
					continue
				if ship.components.place_mount(ship.grid, id, out, int(m["rot"])) >= 0:
					if str(_def(id)["family"]) == "engine":
						placed["engine"] = true
					break
			at += w + (1 if r["room"]["kind"] == "engine" else 0)


## (extent along the wall, depth) of the OUTSIDE half of mount `id` turned `rot`.
static func _along(id: String, rot: int) -> Vector2i:
	var o: Vector2i = Mounts.turned(_def(id)["mount"]["outside"], rot)
	return Vector2i(o.x, o.y) if rot % 2 == 0 else Vector2i(o.y, o.x)


## Where the outside half of mount `id` (rotation `rot`, `pos` its first column or row along the wall) goes: against the
## outermost wall cell of that stretch, or (-999, -999) when the stretch is not level.
static func _out_anchor(g: ShipGrid, id: String, rot: int, pos: int) -> Vector2i:
	var osz: Vector2i = Mounts.turned(_def(id)["mount"]["outside"], rot)
	var along: int = osz.x if rot % 2 == 0 else osz.y
	var edge := -999
	for k in along:
		var e := _edge(g, rot, pos + k)
		if e == -999 or (edge != -999 and e != edge):
			return Vector2i(-999, -999)
		edge = e
	match rot:
		0:
			return Vector2i(pos, edge - osz.y)
		2:
			return Vector2i(pos, edge + 1)
		1:
			return Vector2i(edge + 1, pos)
	return Vector2i(edge - osz.x, pos)


## The outermost built cell of column / row `line` seen from the side the mount points to (its y for rot 0 and 2, its x
## for rot 1 and 3), or -999 when the line is empty.
static func _edge(g: ShipGrid, rot: int, line: int) -> int:
	match rot:
		0:
			for y in g.size.y:
				if g.get_tile(Vector2i(line, y)) != "":
					return y
		2:
			for y in range(g.size.y - 1, -1, -1):
				if g.get_tile(Vector2i(line, y)) != "":
					return y
		1:
			for x in range(g.size.x - 1, -1, -1):
				if g.get_tile(Vector2i(x, line)) != "":
					return x
		_:
			for x in g.size.x:
				if g.get_tile(Vector2i(x, line)) != "":
					return x
	return -999


# --- the cables ----------------------------------------------------------------------------------

## Join every part to the first reactor with cables: each part, in order, by the cheapest route to the network so far.
static func _wire(ship: Ship) -> bool:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var net := {}
	var rest: Array = []
	for uid in uids:
		if net.is_empty() and _is_reactor(str(ship.components.instances[uid]["id"])):
			var inst: Dictionary = ship.components.instances[uid]
			net[inst["cells"][inst["cells"].size() / 2]] = true
		else:
			rest.append(uid)
	if net.is_empty():
		return false
	ship.cables.place(ship.grid, net.keys()[0])
	for uid in rest:
		var path := _route(ship, ship.components.instances[uid]["cells"], net)
		if path.is_empty() and not _touches(ship.components.instances[uid]["cells"], net):
			return false
		for c in path:
			net[c] = true
			ship.cables.place(ship.grid, c)
	return true


static func _touches(cells: Array, net: Dictionary) -> bool:
	return cells.any(func(c): return net.has(c))


## The cells of the cheapest cable path from a cell of `starts` to the network, not counting the end cell
## (a floor cell costs 1, a part or a door 1, a wall 3, open space 50).
static func _route(ship: Ship, starts: Array, net: Dictionary) -> Array:
	var g: ShipGrid = ship.grid
	var dist := {}
	var prev := {}
	var buckets: Array = []
	for s in starts:
		dist[s] = 0
		_bucket(buckets, 0, s)
	var d := 0
	while d < buckets.size():
		var i := 0
		while i < buckets[d].size():
			var c: Vector2i = buckets[d][i]
			i += 1
			if int(dist[c]) != d:
				continue
			if net.has(c):
				var path: Array = []
				var at := c
				while prev.has(at):
					at = prev[at]
					path.append(at)
				return path.filter(func(p): return not net.has(p))
			for s in SIDES:
				var n: Vector2i = c + s
				if not g.in_bounds(n):
					continue
				var nd := d + _wire_cost(ship, n)
				if not dist.has(n) or nd < int(dist[n]):
					dist[n] = nd
					prev[n] = c
					_bucket(buckets, nd, n)
		d += 1
	return []


static func _bucket(buckets: Array, d: int, c: Vector2i) -> void:
	while buckets.size() <= d:
		buckets.append([])
	buckets[d].append(c)


static func _wire_cost(ship: Ship, c: Vector2i) -> int:
	var g: ShipGrid = ship.grid
	var t := g.get_tile(c)
	if t == "":
		return 50
	if g.tile_flag(t, "solid"):
		return 3
	return 1


# --- the finish ----------------------------------------------------------------------------------

## Take parts off that the power cannot carry (the last gun first) until supply covers the demand.
static func _trim(ship: Ship) -> void:
	for _i in 12:
		ship.refresh()
		var short := false
		for n in ship.power_state["networks"]:
			short = short or float(n["supply"]) + 0.0001 < float(n["demand"])
		for uid in ship.components.instances:
			short = short or not ship.power_state["powered"].get(uid, false)
		if not short:
			return
		var uids: Array = ship.components.instances.keys()
		uids.sort()
		uids.reverse()
		for uid in uids:
			if str(ship.components.def(ship.components.instances[uid]["id"])["family"]) == "weapon" and _weapon_count(ship) > 1:
				ship.components.remove_uid(uid)
				break


static func _weapon_count(ship: Ship) -> int:
	var n := 0
	for uid in ship.components.instances:
		n += int(str(ship.components.def(ship.components.instances[uid]["id"])["family"]) == "weapon")
	return n


## The hull marking, the crew, the pilot, the cargo and the name.
static func _finish(ship: Ship, f: Dictionary, faction: String, lo: Dictionary, rng: RandomNumberGenerator, ram: bool) -> void:
	var g: ShipGrid = ship.grid
	var blo := Vector2i(g.size)
	var bhi := Vector2i.ZERO
	var all: Array = g.tiles.keys() + ship.cables.cells.keys()
	for uid in ship.components.instances:
		all.append_array(ship.components.instances[uid]["cells"])
		all.append_array(ship.components.instances[uid]["out_cells"])
	for c in all:
		blo = blo.min(c)
		bhi = bhi.max(c)
	blo -= Vector2i(HULL_MARGIN, HULL_MARGIN)
	bhi += Vector2i(HULL_MARGIN, HULL_MARGIN)
	g.hull.clear()
	for y in range(maxi(blo.y, 0), mini(bhi.y, g.size.y - 1) + 1):
		for x in range(maxi(blo.x, 0), mini(bhi.x, g.size.x - 1) + 1):
			g.hull[Vector2i(x, y)] = true
	var crew: Dictionary = f["crew"]
	var names: Array = crew["names"]
	var first := rng.randi() % names.size()
	for i in int(lo["crew"]):
		var base_name := str(names[(first + i) % names.size()])
		var lap := i / names.size()  # more crew than names: the second lap is "Vex II"
		ship.crew_plan.append({"name": base_name if lap == 0 else "%s %s" % [base_name, "I".repeat(lap + 1)], "species": str(crew["species"][rng.randi() % crew["species"].size()])})
	var ai: Dictionary = {"aim_skill": snappedf(float(lo["skill"]), 0.01), "morale": str(f["ai"].get("morale", "default")), "faction": str(f.get("lines_as", faction))}  # morale: a style of data/morale.json; faction: whose lines (morale.json) it says
	if ram:
		ai["style"] = "rammer"
		ai["morale"] = "ram"
	ship.set_meta("ai", ai)
	for uid in ship.components.instances:
		var w := str(ship.components.instances[uid]["id"])
		var ammo := str(_weapons.def(w).get("ammo", "")) if _weapons.has(w) else ""
		if ammo != "" and ship.inventory.count(ammo) < AMMO_STOCK:
			ship.inventory.add(ammo, AMMO_STOCK)
	ship.name = _name_of(f, faction, rng)
	ship.rng_seed = rng.randi() % 100000 + 1
	ship.mark_dirty()
	ship.refresh()


## The look of a faction's (or race's) ships: {id, race, label (the adjective), role (by size), line ("Kett lancer"), palette (colours as
## Color, patch an Array of them), emblem (data)}; {} for a faction with no `style`.
static func style_of(faction: String, size: String, role := "", budget := -1.0) -> Dictionary:
	var st = tables()["factions"].get(faction, {}).get("style")
	if not st is Dictionary:
		return {}
	var pal: Dictionary = st["palette"]
	var noun := role if role != "" else str(st["roles"].get(size, ""))
	var cfg: Dictionary = tables()["roles"]
	var grade := "plain"  # a low budget looks patched, a high one fine
	if budget >= 0.0:
		grade = "patched" if budget < float(cfg["patched_below"]) else ("fine" if budget >= float(cfg["fine_from"]) else "plain")
	return {"id": faction, "race": str(tables()["factions"][faction].get("race", "")), "label": str(st["label"]), "role": noun, "grade": grade,
		"line": ("%s %s" % [st["label"], noun]).strip_edges(), "emblem": st["emblem"], "dressing": st.get("dressing", []),
		"palette": {"tint": Color(str(pal["tint"])), "accent": Color(str(pal["accent"])), "mark": Color(str(pal["accent"])) if Color(str(pal["accent"])).get_luminance() > 0.3 else Color(str(pal["tint"])).lightened(0.3), "lamp": Color(str(pal["lamp"])),
			"glow": Color(str(pal["glow"])), "floor": Color(str(pal.get("floor", pal["tint"]))), "wall": Color(str(pal.get("wall", pal["tint"]))), "patch": pal.get("patch", []).map(func(c): return Color(str(c)))}}


static func _name_of(f: Dictionary, faction: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	var pools = Content.names()
	if str(f.get("name_pool", "")) != "" and pools.get(str(f["name_pool"])) is Array:
		pool = pools[str(f["name_pool"])]
	elif f.get("ship_names") is Array:
		pool = f["ship_names"]
	if pool.is_empty():
		return faction.capitalize() + " ship"
	return str(pool[rng.randi() % pool.size()])
