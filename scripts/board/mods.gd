extends RefCounted
## Mods (docs/BOARDING.md, B4; data/mods.json): small devices worn in a kit slot, like FTL's augments. Each tier of a mod is its own cargo item
## (`<mod>_mk1..3`, kind `mod` in data/items.json), so the hold, loot and shops carry them. Pure logic, plus the flat icon every mod is drawn with.
## - scope `party`: the best tier worn by anyone in the boarding party counts (party_tier), mods do not stack. scope `self`: the wearer's own (self_tier).
## - Spotter Cam: rooms_shown (the doors it sees through), Salvage Rig: salvage (the bonus of an opened container), Overcharge Coil: damage_mult, pierce.
## - roll_drop() is how loot picks a mod and its tier (the `mod` outcome of the boarding tables).

const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/mods.json"

static var _cfg := {}


## data/mods.json (read once).
static func config() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = d if d is Dictionary else {}
	return _cfg


static func ids() -> Array:
	return config()["mods"].map(func(m): return str(m["id"]))


## The mod `id`'s entry, {} for an unknown id.
static func def(id: String) -> Dictionary:
	for m in config()["mods"]:
		if str(m["id"]) == id:
			return m
	return {}


## The cargo item of tier `tier` (1 to 3) of mod `id`.
static func item_id(id: String, tier: int) -> String:
	return "%s_mk%d" % [id, tier]


## {mod, tier} of a mod item ("overcharge_coil_mk2"), {} when `item` is not one.
static func parse(item: String) -> Dictionary:
	var at := item.rfind("_mk")
	if at < 0:
		return {}
	var t := item.substr(at + 3)
	if not t.is_valid_int() or int(t) < 1 or int(t) > 3:
		return {}
	var id := item.substr(0, at)
	return {"mod": id, "tier": int(t)} if not def(id).is_empty() else {}


static func is_item(item: String) -> bool:
	return not parse(item).is_empty()


## The numbers of tier `tier` of mod `id`.
static func numbers(id: String, tier: int) -> Dictionary:
	var d := def(id)
	return d["tiers"][clampi(tier, 1, 3) - 1] if not d.is_empty() else {}


static func color(id: String) -> Color:
	return Color(str(def(id).get("color", "#ffffff")))


## "Spotter Cam Mk II".
static func label(item: String) -> String:
	var p := parse(item)
	if p.is_empty():
		return item
	return "%s %s" % [def(p["mod"])["name"], config()["tier_names"][int(p["tier"]) - 1]]


## The lines a hover shows: what it does, then what this tier does and who it works for.
static func hover(item: String) -> Array:
	var p := parse(item)
	if p.is_empty():
		return []
	var d := def(p["mod"])
	return [str(d["does"]), "%s: %s" % [config()["tier_names"][int(p["tier"]) - 1], numbers(p["mod"], int(p["tier"]))["text"]],
		"Works for the whole party. The best one counts." if d["scope"] == "party" else "Works for the one who wears it."]


# --- who wears what --------------------------------------------------------------------------------------------------

## The best tier of mod `id` that person `m` (a CrewMember) wears, 0 for none.
static func self_tier(m, id: String) -> int:
	var best := 0
	for item in m.kit.get("mods", []):
		var p := parse(str(item))
		if not p.is_empty() and p["mod"] == id:
			best = maxi(best, int(p["tier"]))
	return best


## The best tier of mod `id` worn in the boarding party of session `s` (the soldier and the crew who came along; a person met aboard wears nothing).
static func party_tier(s, id: String) -> int:
	var best := self_tier(s.soldier, id) if s.soldier != null else 0
	for p in s.party:
		if not bool(p.get("temp", false)):
			best = maxi(best, self_tier(p["m"], id))
	return best


## The damage factor of the Overcharge Coil `m` wears (1.0 for none).
static func damage_mult(m) -> float:
	var t := self_tier(m, "overcharge_coil")
	return 1.0 + float(numbers("overcharge_coil", t)["damage"]) if t > 0 else 1.0


## How many bodies a shot of `m` goes on through after the first.
static func pierce(m) -> int:
	var t := self_tier(m, "overcharge_coil")
	return int(numbers("overcharge_coil", t)["pierce"]) if t > 0 else 0


## The factor on the width and light of `m`'s bolts.
static func bolt_size(m) -> float:
	var t := self_tier(m, "overcharge_coil")
	return float(numbers("overcharge_coil", t)["size"]) if t > 0 else 1.0


# --- the Salvage Rig -------------------------------------------------------------------------------------------------

## Does the Salvage Rig multiply stacks of `item` (a material, rounds or credits; never a part, a weapon, gear or a blueprint)?
static func is_resource(item: String) -> bool:
	return Content.has("materials", item) or config()["resources"]["extra"].has(item)


## The bonus tier `tier` of the Salvage Rig adds to `items` ({item: n}): {item: extra}. A fraction is rolled with `rng`; at Mk III a container may add one rare material.
static func salvage(items: Dictionary, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	if tier <= 0:
		return out
	var t := numbers("salvage_rig", tier)
	var keys: Array = items.keys()
	keys.sort()
	for item in keys:
		if not is_resource(str(item)):
			continue
		var extra := float(items[item]) * float(t["bonus"])
		var n := floori(extra) + (1 if rng.randf() < extra - floorf(extra) else 0)
		if n > 0:
			out[item] = n
	if float(t["rare_chance"]) > 0.0 and rng.randf() < float(t["rare_chance"]):
		var rare: Array = def("salvage_rig")["rare"]
		var pick := str(rare[rng.randi() % rare.size()])
		out[pick] = int(out.get(pick, 0)) + 1
	return out


# --- drops -------------------------------------------------------------------------------------------------------------

## The weights of Mk I to III in site kind `kind` at stage `stage` of the run.
static func tier_weights(kind: String, stage: int) -> Array:
	var w: Array = [1.0, 0.0, 0.0]
	for s in config()["drops"]["stages"]:
		if stage >= int(s["from"]):
			w = s["w"].duplicate()
	if not config()["drops"]["tier3_kinds"].has(kind):
		w[2] = 0.0
	return w


## A mod item for loot: the mod by its weight, the tier by the weights of the stage (not above `max_tier`). "" when no tier can be rolled.
static func roll_drop(kind: String, stage: int, rng: RandomNumberGenerator, max_tier := 3) -> String:
	var mods: Array = config()["mods"]
	var total := 0.0
	for m in mods:
		total += float(m["weight"])
	var x := rng.randf() * total
	var pick: Dictionary = mods[-1]
	for m in mods:
		x -= float(m["weight"])
		if x < 0.0:
			pick = m
			break
	var w := tier_weights(kind, stage)
	for i in range(max_tier, 3):
		w[i] = 0.0
	var tw: float = w[0] + w[1] + w[2]
	if tw <= 0.0:
		return ""
	var y := rng.randf() * tw
	var tier := 3
	for i in 3:
		y -= float(w[i])
		if y < 0.0:
			tier = i + 1
			break
	return item_id(str(pick["id"]), tier)


# --- the icon ----------------------------------------------------------------------------------------------------------

## The placeholder icon of mod item `item` in rect `r` of canvas item `cv`: a flat square in the mod's colour, its glyph, and 1 to 3 pips for the tier.
static func draw_icon(cv: CanvasItem, item: String, r: Rect2, dim := false) -> void:
	var p := parse(item)
	if p.is_empty():
		return
	var col := color(p["mod"])
	var a := 0.55 if dim else 1.0
	cv.draw_rect(r, Color(col.darkened(0.72), a))
	cv.draw_rect(r, Color(col, a), false, maxf(1.0, r.size.x / 18.0))
	var u := r.size.x / 16.0
	var o := r.position
	var c := Color(col.lightened(0.15), a)
	match str(def(p["mod"]).get("icon", "")):
		"cam":  # a lens in a housing
			cv.draw_rect(Rect2(o + Vector2(3, 4) * u, Vector2(10, 6) * u), c)
			cv.draw_circle(o + Vector2(8, 7) * u, 2.2 * u, Color(0.05, 0.1, 0.1, a))
			cv.draw_circle(o + Vector2(8, 7) * u, 1.0 * u, Color(col.lightened(0.5), a))
			cv.draw_rect(Rect2(o + Vector2(10.5, 2.5) * u, Vector2(2, 1.5) * u), c)
		"rig":  # a hook over a crate
			cv.draw_rect(Rect2(o + Vector2(3.5, 7) * u, Vector2(9, 5) * u), c)
			cv.draw_line(o + Vector2(8, 2) * u, o + Vector2(8, 6) * u, c, maxf(1.0, 1.4 * u))
			cv.draw_arc(o + Vector2(8, 3.2) * u, 1.8 * u, 0.0, PI, 8, c, maxf(1.0, 1.2 * u))
		"coil":  # a bolt through a ring
			cv.draw_arc(o + Vector2(8, 7) * u, 4.2 * u, 0.0, TAU, 14, c, maxf(1.0, 1.3 * u))
			cv.draw_polyline(PackedVector2Array([o + Vector2(9.5, 2.5) * u, o + Vector2(6.5, 7.5) * u, o + Vector2(9.2, 7.5) * u, o + Vector2(6.5, 12) * u]), Color(col.lightened(0.6), a), maxf(1.0, 1.2 * u))
	for i in int(p["tier"]):  # the pips
		cv.draw_rect(Rect2(o + Vector2(3.0 + 3.6 * float(i), 13.2) * u, Vector2(2.4, 1.8) * u), Color(col.lightened(0.5), a))
