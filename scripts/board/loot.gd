extends RefCounted
## What a container holds (data/boarding.json): rolled when it is opened, from the site's seed and the container's id, so the same
## container always holds the same things however the visit goes. Pure logic.
## A container's table is its prop's own (a terminal's, a body's) or its room's purpose's; the kind adds its `bonus` outcomes to every table.
## Its counts grow with the kind (`loot_mult`) and the campaign's tier; a room only a lock opens gets one more roll.
## A blueprint slot becomes a recipe the ship does not know (the fab_level weights of the tier), else the `fallback` materials. A log
## slot becomes a derelict log not found yet (of the region's faction by preference), else credits. A key slot is a keycard.
## Contents: {items: {id: n}, blueprint: recipe id or "", log: log id or "", key: key id or ""}.

const Site = preload("res://scripts/board/site.gd")
const Themes = preload("res://scripts/board/themes.gd")

const TIER_GROWTH := 0.15  ## more in every count for each tier above the first


## The weighted outcomes container `id` of `site` rolls on (the site's theme tilts the weights of the items it favours).
static func table_of(site, id: int) -> Array:
	var p: Dictionary = site.props[id]
	return table_for(site, p["table"] if p["table"] != "" else str(site.rooms[p["room"]]["purpose"]))


## The outcomes of table `name` in `site`: the table, the kind's bonus, the theme's tilt.
static func table_for(site, name: String) -> Array:
	var cfg := Site.config()
	var table: Array = cfg["tables"].get(name, []) + cfg["kinds"][site.kind]["bonus"]
	if site.theme == "":
		return table
	return table.map(func(o): return {"weight": float(o["weight"]) * Themes.tilt(site.theme, str(o["item"])), "item": o["item"], "count": o["count"]})  # (the theme's tilt)


## Roll the contents of container `id`. `ctx`: {tier (1-3), unknown (recipe ids the ship has no blueprint for), levels (recipe id -> fab_level),
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
	var table := table_of(site, id)
	var rolls := rng.randi_range(int(p["rolls"][0]), int(p["rolls"][1])) + (1 if site.rooms[p["room"]]["locked"] and p["loot"] else 0)
	for i in rolls:
		var o := _pick(table, rng)
		if not o.is_empty():
			_add(out["items"], str(o["item"]), maxi(1, roundi(float(rng.randi_range(int(o["count"][0]), int(o["count"][1]))) * mult)))
	for item in p["fixed"]:
		_add(out["items"], str(item), int(p["fixed"][item]))
	match p["slot"]:
		"blueprint":
			out["blueprint"] = _blueprint(ctx, tier, rng)
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


## Is there nothing left in `contents`?
static func empty(contents: Dictionary) -> bool:
	return contents.get("items", {}).is_empty() and contents.get("blueprint", "") == "" and contents.get("log", "") == "" and contents.get("key", "") == ""


static func _add(items: Dictionary, id: String, n: int) -> void:
	items[id] = int(items.get(id, 0)) + n


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


## A recipe of `ctx.unknown` by the weights of the tier's levels; "" when there is none.
static func _blueprint(ctx: Dictionary, tier: int, rng: RandomNumberGenerator) -> String:
	var unknown: Array = ctx.get("unknown", []).duplicate()
	unknown.sort()
	var w: Array = Site.config()["blueprint"]["levels"][str(tier)]
	var weights := []
	var total := 0.0
	for rid in unknown:
		var lv := clampi(int(ctx.get("levels", {}).get(rid, 1)), 1, w.size())
		weights.append(float(w[lv - 1]))
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
