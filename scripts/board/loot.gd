extends RefCounted
## What a container holds (data/boarding.json): rolled when it is opened, from the site's seed and the container's id, so the same
## container always holds the same things however the visit goes. Pure logic.
## A container's table is its prop's own (a terminal's, a body's) or its room's purpose's (a purpose may borrow another's: rooms.<p>.table); the kind adds
## its `bonus` outcomes to every table. Loot fits the room (boarding.json loot_theme): today's roll picks the outcome and so its tier, then a room
## whose purpose has tags picks again within that tier, the items whose tags meet the room's `mult` times as likely; a blueprint the same way.
## Its counts grow with the kind (`loot_mult`) and the campaign's tier; a room only a lock opens gets one more roll.
## A blueprint slot becomes a recipe the ship does not know (the fab_level weights of the tier), else the `fallback` materials. A log
## slot becomes a derelict log not found yet (of the region's faction by preference), else credits. A key slot is a keycard.
## Contents: {items: {id: n}, blueprint: recipe id or "", log: log id or "", key: key id or ""}.

const Site = preload("res://scripts/board/site.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Content = preload("res://scripts/data/content.gd")

const TIER_GROWTH := 0.15  ## more in every count for each tier above the first
const MOD := "mod"  ## the outcome of a table that is "one mod" (data/mods.json drops)
const MOD_LOW := "mod_low"  ## the same, Mk I or II only (a locker's or a cabinet's: Mk III stays a find of engineering and command decks)


## The weighted outcomes container `id` of `site` rolls on (the site's theme tilts the weights of the items it favours).
static func table_of(site, id: int) -> Array:
	var p: Dictionary = site.props[id]
	var table := table_for(site, p["table"] if p["table"] != "" else purpose_table(str(site.rooms[p["room"]]["purpose"])))
	return table + Site.config()["props"][str(p["prop"])].get("bonus", [])  # (what the prop itself may hold besides)


## The table a room of `purpose` rolls on: its own, or the one it borrows (boarding.json rooms.<purpose>.table).
static func purpose_table(purpose: String) -> String:
	return str(Site.config()["rooms"].get(purpose, {}).get("table", purpose))


## The outcomes of table `name` in `site`: the table, the kind's bonus, the theme's tilt.
static func table_for(site, name: String) -> Array:
	var cfg := Site.config()
	var table: Array = cfg["tables"].get(name, []) + cfg["kinds"][site.kind]["bonus"]
	var home: Dictionary = cfg.get("regional", {}).get(site.region, {}) if site.region != "" else {}  # (the race gear of the region)
	if site.theme == "" and home.is_empty():
		return table
	return table.map(func(o): return {"weight": float(o["weight"]) * Themes.tilt(site.theme, str(o["item"])) * float(home.get(str(o["item"]), 1.0)), "item": o["item"], "count": o["count"]})  # (the theme's tilt)


## Roll the contents of container `id`. `ctx`: {tier (1-3), stage (of the run, for mods), unknown (recipe ids the ship has no blueprint for), levels (recipe id -> fab_level),
## logs (log ids not found yet), log_factions (log id -> faction), faction (the region's)}.
static func resolve(site, id: int, ctx := {}) -> Dictionary:
	var cfg := Site.config()
	var p: Dictionary = site.props[id]
	var kcfg: Dictionary = cfg["kinds"][site.kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "loot", id)
	var tier := clampi(int(ctx.get("tier", 1)), 1, 3)
	var mult := float(kcfg["loot_mult"]) * (1.0 + TIER_GROWTH * float(tier - 1))
	var out := {"items": {}, "blueprint": "", "log": "", "key": ""}
	if p.has("foe"):
		_foe_body(site, p, out["items"], rng, mult, int(ctx.get("stage", 1)))
		return out
	var table := table_of(site, id)
	var purpose := str(site.rooms[p["room"]]["purpose"])
	var rolls := rng.randi_range(int(p["rolls"][0]), int(p["rolls"][1])) + (1 if site.rooms[p["room"]]["locked"] and p["loot"] else 0)
	for i in rolls:
		var o := roll(table, purpose, rng)
		if not o.is_empty() and str(o["item"]) in [MOD, MOD_LOW]:  # a mod: which one and which tier come from the site kind and the stage of the run (mods.gd)
			var drop := Mods.roll_drop(site.kind, int(ctx.get("stage", 1)), rng, 2 if str(o["item"]) == MOD_LOW else 3)
			if drop != "":
				_add(out["items"], drop, 1)
		elif not o.is_empty():
			_add(out["items"], str(o["item"]), maxi(1, roundi(float(rng.randi_range(int(o["count"][0]), int(o["count"][1]))) * mult)))
	for item in p["fixed"]:
		_add(out["items"], str(item), int(p["fixed"][item]))
	match p["slot"]:
		"blueprint":
			out["blueprint"] = _blueprint(ctx, tier, rng, purpose)
			if out["blueprint"] == "":
				var fb: Dictionary = cfg["blueprint"]["fallback"]
				for item in fb:
					_add(out["items"], str(item), rng.randi_range(int(fb[item][0]), int(fb[item][1])))
		"log":
			out["log"] = _log(ctx, rng)
			if out["log"] == "":
				var fb: Dictionary = cfg["log_fallback"]
				for item in fb:
					_add(out["items"], str(item), rng.randi_range(int(fb[item][0]), int(fb[item][1])))
		"key":
			out["key"] = p["key"]
	return out


## The data/boarding.json `foe_loot` entry of foe kind `kind`.
static func foe_entry(kind: String) -> Dictionary:
	var fl: Dictionary = Site.config()["foe_loot"]
	return fl["kinds"].get(kind, fl["default"])


## What a beaten foe's body (prop `p`) holds, added to `items`: hand ammo and credits always, its weapon at combat.foe_drop, a mod or a piece of body gear at its `extra`.
## The dice are the container's (seeded from the site and the prop), `mult` grows the counts as the other containers' do.
static func _foe_body(site, p: Dictionary, items: Dictionary, rng: RandomNumberGenerator, mult: float, stage: int) -> void:
	var fl: Dictionary = Site.config()["foe_loot"]
	var kind := str(p["foe"])
	var e := foe_entry(kind)
	_add(items, str(Site.config()["combat"]["ammo_item"]), maxi(1, roundi(float(rng.randi_range(int(e["ammo"][0]), int(e["ammo"][1]))) * mult)))
	_add(items, "credits", maxi(1, roundi(float(rng.randi_range(int(e["credits"][0]), int(e["credits"][1]))) * mult)))
	var weapon := str(Site.config()["enemies"].get(kind, {}).get("weapon", ""))
	var held: Dictionary = Site.config()["combat"]["hand_items"]
	var keys: Array = held.keys()
	keys.sort()
	var drop := rng.randf() < float(Site.config()["combat"].get("foe_drop", 0.0))  # (rolled whatever the foe held, so the dice do not shift)
	for item in keys:
		if drop and weapon != "" and str(held[item]) == weapon:
			_add(items, str(item), 1)
			break
	if rng.randf() < float(e["extra"]):
		if rng.randf() < float(fl["mod_share"]):
			var m := Mods.roll_drop(site.kind, stage, rng, 3 if bool(e.get("elite", false)) else 2)
			if m != "":
				_add(items, m, 1)
		else:
			var gear: Array = fl["gear"]
			var pick := _pick(gear, rng)
			if not pick.is_empty():
				_add(items, str(pick["item"]), 1)
	var worn := str(p.get("worn", ""))
	if worn != "" and rng.randf() < float(Site.config()["wear"]["drop"]):  # (the gear it wore, after every older roll so those do not shift)
		_add(items, worn, 1)


## Is there nothing left in `contents`?
static func empty(contents: Dictionary) -> bool:
	return contents.get("items", {}).is_empty() and contents.get("blueprint", "") == "" and contents.get("log", "") == "" and contents.get("key", "") == ""


static func _add(items: Dictionary, id: String, n: int) -> void:
	items[id] = int(items.get(id, 0)) + n


# --- loot that fits the room ----------------------------------------------------------------------------------------

static func theme_cfg() -> Dictionary:
	return Site.config().get("loot_theme", {})


## The tags of the rooms of `purpose` ([] for a purpose with none).
static func room_tags(purpose: String) -> Array:
	return theme_cfg().get("rooms", {}).get(purpose, [])


## The tags of item `id`: its own (loot_theme.items), and a part's family's (loot_theme.families).
static func item_tags(id: String) -> Array:
	_index()
	if not _tags.has(id):
		var out: Array = theme_cfg().get("items", {}).get(id, []).duplicate()
		out.append_array(theme_cfg().get("families", {}).get(str(_family.get(id, "")), []))
		_tags[id] = out
	return _tags[id]


## The tags of recipe `rid`: those of what it makes.
static func recipe_tags(rid: String) -> Array:
	_index()
	return item_tags(str(_output.get(rid, rid)))


static func _fits(tags: Array, room: Array) -> bool:
	return tags.any(func(t): return room.has(t))


## How much the Scan pick wants recipe `rid` (salvage.gd's order: the same number is the same tier of wanting).
static func _want(ship, rid: String) -> int:
	return Salvage._recipe_class(ship, rid) * 100 - Salvage._recipe_tier(ship, rid)


static var _family := {}  # part id -> its family
static var _output := {}  # recipe id -> the item it makes
static var _rarity := {}  # material id -> rarity
static var _ammo := {}  # item id -> true: kind ammo
static var _tags := {}  # item id -> its tags, worked out once
static var _tier := {}  # item id -> its tier, worked out once


## The parts, recipes, materials and items (with their packs), read once.
static func _index() -> void:
	if not _rarity.is_empty():
		return
	for d in Content.read("res://data/components.json")["components"]:
		_family[str(d["id"])] = str(d.get("family", ""))
	for d in Content.read("res://data/recipes.json")["recipes"]:
		_output[str(d["id"])] = str(d.get("output", {}).get("item", d["id"]))
	for d in Content.read("res://data/materials.json")["materials"]:
		_rarity[str(d["id"])] = str(d.get("rarity", "common"))
	for d in Content.read("res://data/items.json")["items"]:
		if str(d.get("kind", "")) == "ammo":
			_ammo[str(d["id"])] = true


## The tier of outcome item `id` (what the first roll decides): credits, mod, part, weapon, ammo, gear, common, rare or special (loot_theme.tiers first).
static func tier_of(id: String) -> String:
	if not _tier.has(id):
		_tier[id] = _tier_of(id)
	return _tier[id]


static func _tier_of(id: String) -> String:
	_index()
	var t: Dictionary = theme_cfg().get("tiers", {})
	if t.has(id):
		return str(t[id])
	if id == "credits":
		return "credits"
	if id == MOD or id == MOD_LOW:
		return "mod"
	if _family.has(id):
		return "part"
	if Site.config()["combat"]["hand_items"].has(id):
		return "weapon"
	if _ammo.has(id):
		return "ammo"
	if Site.config().get("gear", {}).has(id):
		return "gear"
	if _rarity.has(id):
		return "common" if _rarity[id] == "common" else "rare"
	return "special"


## One outcome of `table` for a container in a room of `purpose`: today's roll, which settles the tier; then, when the room's tags tell some items of that
## tier from the rest, a second pick within the tier with the fitting ones `mult` times as likely. {} when the table is empty.
static func roll(table: Array, purpose: String, rng: RandomNumberGenerator) -> Dictionary:
	var o := _pick(table, rng)
	var room := room_tags(purpose)
	if o.is_empty() or room.is_empty():
		return o
	var tier := tier_of(str(o["item"]))
	var same: Array = table.filter(func(x): return tier_of(str(x["item"])) == tier)
	var fit := same.map(func(x): return _fits(item_tags(str(x["item"])), room))
	if not fit.has(true) or not fit.has(false):
		return o  # (every item of the tier fits the room, or none does: the pick stands)
	var mult := float(theme_cfg().get("mult", 1.0))
	var w := []
	for i in same.size():
		w.append({"weight": float(same[i]["weight"]) * (mult if fit[i] else 1.0), "item": same[i]["item"], "count": same[i]["count"]})
	return _pick(w, rng)


static func _pick(table: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for o in table:
		total += float(o["weight"])
	if total <= 0.0:
		return {}
	var x := rng.randf() * total
	for o in table:
		x -= float(o["weight"])
		if x < 0.0:
			return o
	return table[-1]


## A recipe of `ctx.unknown`: the one the ship (`ctx.ship`) can craft next, the pick of a salvage's Scan row (Salvage.next_recipe); when the room's tags
## (`purpose`) fit an equally wanted one better, that one `mult - 1` times in `mult`. When it can craft none of them, or `ctx` has no ship, one by the
## weights of the tier's levels, those that fit the room `mult` times as likely; "" when there is none.
static func _blueprint(ctx: Dictionary, tier: int, rng: RandomNumberGenerator, purpose := "") -> String:
	var unknown: Array = ctx.get("unknown", []).duplicate()
	unknown.sort()
	var room := room_tags(purpose)
	var mult := float(theme_cfg().get("mult", 1.0))
	if ctx.get("ship") != null:
		var ship = ctx["ship"]
		var next := Salvage.next_recipe(ship, unknown, rng)
		if next != "" and not room.is_empty() and not _fits(recipe_tags(next), room):
			var fit: Array = unknown.filter(func(rid): return _fits(recipe_tags(str(rid)), room))
			var alt := Salvage.next_recipe(ship, fit, rng) if not fit.is_empty() else ""
			if alt != "" and _want(ship, alt) == _want(ship, next) and rng.randf() < 1.0 - 1.0 / maxf(mult, 1.0):
				return alt
		if next != "":
			return next
	var w: Array = Site.config()["blueprint"]["levels"][str(tier)]
	var weights := []
	var total := 0.0
	for rid in unknown:
		var lv := clampi(int(ctx.get("levels", {}).get(rid, 1)), 1, w.size())
		weights.append(float(w[lv - 1]) * (mult if _fits(recipe_tags(str(rid)), room) else 1.0))
		total += weights[-1]
	if total <= 0.0:
		return ""
	var x := rng.randf() * total
	for i in unknown.size():
		x -= weights[i]
		if x < 0.0:
			return str(unknown[i])
	return str(unknown[-1])


## A log of `ctx.logs`, those of the region's faction three times as likely; "" when there is none.
static func _log(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var logs: Array = ctx.get("logs", []).duplicate()
	logs.sort()
	var weights := []
	var total := 0.0
	for id in logs:
		weights.append(3.0 if str(ctx.get("log_factions", {}).get(id, "")) == str(ctx.get("faction", "-")) else 1.0)
		total += weights[-1]
	if total <= 0.0:
		return ""
	var x := rng.randf() * total
	for i in logs.size():
		x -= weights[i]
		if x < 0.0:
			return str(logs[i])
	return str(logs[-1])
