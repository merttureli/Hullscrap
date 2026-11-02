extends RefCounted
## Site themes by region (docs/BOARDING.md, stage B3; data/boarding.json `themes`): what a boarding site looks like and holds by whose space it is in.
## A Boneyard scrapyard (rust, scrap, scavengers), a Concord checkpoint (clean, terminals, sentries, documents), a Lumen glass shrine (crystal, quiet, few
## foes, a Hollow tilt), a Clan hall (crates, drink, pirates, trophies) and the Hollow's own places. Pure logic: site.gd (names, props), loot.gd (tilt),
## foes.gd (the mix) and people.gd (who is there) ask it; board_view.gd asks for the colours. A theme never changes the layout of a site.

const SITE := "res://scripts/board/site.gd"  # (loaded when asked, not preloaded: site.gd preloads this script)


static func _config() -> Dictionary:
	return load(SITE).config()


## Every theme: id -> its data (ids sorted).
static func all() -> Dictionary:
	var out := {}
	var themes: Dictionary = _config().get("themes", {})
	var ids: Array = themes.keys().filter(func(k): return not str(k).begins_with("_"))
	ids.sort()
	for id in ids:
		out[id] = themes[id]
	return out


static func ids() -> Array:
	return all().keys()


## The data of theme `id`, {} for "" or one that does not exist (the plain site).
static func def(id: String) -> Dictionary:
	return all().get(id, {})


## The theme of a visit in region `region` (campaign.region_data: id, events, faction): the first whose `regions` name the region by id or events tag, else the
## first whose `factions` name its faction. `hollow` (the place is the Hollow's) is always the Hollow theme. "" when none fits.
static func for_region(region: Dictionary, hollow := false) -> String:
	if hollow:
		return "hollow"
	var rid := str(region.get("id", ""))
	var tag := str(region.get("events", ""))
	var faction := str(region.get("faction", ""))
	var themes := all()
	for id in themes:
		var regions: Array = themes[id].get("regions", [])
		if (rid != "" and regions.has(rid)) or (tag != "" and regions.has(tag)):
			return id
	if faction != "":
		for id in themes:
			if themes[id].get("factions", []).has(faction):
				return id
	return ""


## A name for a site of `kind` in theme `id`, picked with `rng`; "" when the theme has no names for it.
static func site_name(id: String, kind: String, rng: RandomNumberGenerator) -> String:
	var names: Array = def(id).get("names", {}).get(kind, [])
	if names.is_empty():
		return ""
	var pick := str(names[rng.randi() % names.size()])
	return pick.replace("{n}", str(rng.randi_range(1, 19)))


## The weights `mix` of foe kinds as the theme tilts them: x its `foes.mix`, plus its `foes.add` (each a share of the whole base mix).
static func foe_mix(id: String, mix: Dictionary) -> Dictionary:
	var f: Dictionary = def(id).get("foes", {})
	if f.is_empty():
		return mix
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var out := {}
	var mult: Dictionary = f.get("mix", {})
	for k in mix:
		var w := float(mix[k]) * float(mult.get(k, 1.0))
		if w > 0.0:
			out[k] = w
	var add: Dictionary = f.get("add", {})
	for k in add:
		out[k] = float(out.get(k, 0.0)) + float(add[k]) * total
	return out


## How many foes: `n` x the theme's `foes.count`.
static func foe_count(id: String, n: int) -> int:
	return roundi(float(n) * float(def(id).get("foes", {}).get("count", 1.0)))


## The weight of loot outcome `item` x the theme's tilt.
static func tilt(id: String, item: String) -> float:
	return float(def(id).get("loot", {}).get("tilt", {}).get(item, 1.0))


## The [fill, edge] colours prop `prop` is drawn with in theme `id`; `fallback` when it has none.
static func colors(id: String, prop: String, fallback: Array) -> Array:
	var c: Array = def(id).get("colors", {}).get(prop, [])
	return [Color(str(c[0])), Color(str(c[1]))] if c.size() >= 2 else [Color(str(fallback[0])), Color(str(fallback[1]))]


## The tint a room of purpose `purpose` is drawn with in theme `id`: `tint` pulled toward the theme's wash.
static func wash(id: String, tint: Color) -> Color:
	var d := def(id)
	if d.is_empty():
		return tint
	return tint.lerp(Color(str(d.get("wash", "#ffffff"))), float(d.get("wash_mix", 0.5)))
