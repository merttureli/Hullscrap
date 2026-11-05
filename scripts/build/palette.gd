extends RefCounted
## The build palette's catalogue (docs/waves/content_loop_1.md, priority 0.3): what each category tab lists, what
## its cards say and what the selection card says about one of them. Read-only views of the ship's data: no
## nodes and no drawing (scripts/ui/hud_palette.gd and hud_card.gd draw them, build_mode.gd picks from them).
## A card (an entry) is a Dictionary:
##   key       the tool it picks: "tile:<id>", "piece:<piece>:<tile>", "cable", "belt" or "part:<id>"
##   kind      tile, piece, cable, belt or part; id: the tile or component id ("cable", "belt"); piece: the shape of a piece
##   name, line (scrap, standard, neon or unique: the card's border), tier (0 for structure)
##   size      Vector2i (a door is 2x1, a piece its footprint, a mount its inside half); out_size: a mount's outside half, else ZERO
##   power     line-adjusted (+ makes, - draws; 0 for structure)
##   cost      what one placement takes from the cargo (structure; {} for a part); count: how many parts are held
##   ok, why   it can be placed now (affordable, or held), else why not (entries() lists only the ones that can be)
## The Cargo tab also lists what else is held and not on the top bar (BAR_IDS) as "item" cards, which pick nothing.

const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Describe = preload("res://scripts/ui/describe.gd")
const Crafting = preload("res://scripts/craft/crafting.gd")
const Content = preload("res://scripts/data/content.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Belts = preload("res://scripts/sim/belts.gd")

enum Tab { STRUCTURE, SHAPES, SYSTEMS, WEAPONS, ENGINES, UTILITY, CARGO }
const TAB_NAMES: Array[String] = ["Structure", "Shapes", "Systems", "Weapons", "Engines", "Utility", "Cargo"]
const TAB_ICONS: Array[String] = ["structure", "shapes", "systems", "weapons", "engines", "utility", "cargo"]
## The families on the Utility tab. Weapons and engines have their own tabs; every other family is a System.
const UTILITY_FAMILIES: Array[String] = ["intake", "radar", "tractor", "shield", "oxygen", "bed", "workshop", "fabricator", "smelter", "utility", "ammo_rack", "belt_drive", "drone_bay"]
## The cargo the top bar shows (scripts/ui/hud_top_bar.gd), in its order; the Cargo tab lists everything else held.
const BAR_IDS: Array[String] = ["scrap", "copper", "polymer", "titanium", "silicon", "crystal", "credits", "fuel"]
const LINE_ORDER: Array[String] = ["standard", "scrap", "neon"]
const LINE_NAMES := {"scrap": "Scrap", "standard": "Standard", "neon": "Neon", "unique": "Unique"}


## What a tab says when nothing on it can be placed now: one line, what to do about it.
const EMPTY_TEXT := ["No structure you can afford: gather scrap", "No shapes you can afford: gather scrap", "No systems in the hold: craft one (C)",
	"No guns in the hold: craft one (C)", "No engines in the hold: craft one (C)", "No utility parts in the hold: craft one (C)", "Nothing in the hold"]


## The tab a component def belongs on.
static func component_tab(def: Dictionary) -> int:
	match str(def.get("family", "")):
		"weapon":
			return Tab.WEAPONS
		"engine":
			return Tab.ENGINES
	return Tab.UTILITY if str(def.get("family", "")) in UTILITY_FAMILIES else Tab.SYSTEMS


## The cards of tab `tab` for `ship` (`cable_cost`: BuildSession.cable_cost): only what can be placed now. Structure: the tiles, the
## cable and the belt that can be paid for; Shapes: the pieces of every wall material that can be paid for; Cargo: the parts held, then
## the other cargo off the top bar; the others: the parts of their families that are held (what is only known to be craftable lives in
## the crafting panel).
static func entries(tab: int, ship, cable_cost: Dictionary) -> Array:
	var out := []
	var g = ship.grid
	match tab:
		Tab.STRUCTURE:
			for id in g.defs.ids():
				out.append(tile_entry(ship, id))
			out.append(cable_entry(ship, cable_cost))
			if Ammo.belts_unlocked(ship):  # the belt needs its blueprint: no card before it
				out.append(belt_entry(ship))
			out = out.filter(func(e): return e["ok"])
		Tab.SHAPES:
			for id in g.defs.ids():
				if g.tile_flag(id, "solid") and not g.tile_flag(id, "door"):
					for p in Shapes.piece_ids():
						if p != Shapes.FULL:
							var e := piece_entry(ship, p, id)
							if e["ok"]:
								out.append(e)
		Tab.CARGO:
			for id in _sorted_parts(ship):
				if ship.inventory.count(id) > 0:
					out.append(part_entry(ship, id))
			var rest: Array = ship.inventory.counts.keys().filter(func(id): return not ship.components.has(id) and not id in BAR_IDS)
			rest.sort()
			for id in rest:
				out.append(item_entry(ship, id))
		_:
			for id in _sorted_parts(ship):
				if component_tab(ship.components.def(id)) == tab and shown(ship, id):
					out.append(part_entry(ship, id))
	return out


## Does the build palette list part `id`: one is held? A part only known (its blueprint) lives in the crafting panel.
static func shown(ship, id: String) -> bool:
	return ship.inventory.count(id) > 0


## Every component id, grouped by family (in the order the families first appear), then by line, then as listed.
static func _sorted_parts(ship) -> Array:
	var ids: Array = ship.components.ids().duplicate()
	var fam := {}
	for id in ids:
		var f := str(ship.components.def(id).get("family", ""))
		if not fam.has(f):
			fam[f] = fam.size()
	var at := {}
	for i in ids.size():
		var d: Dictionary = ship.components.def(ids[i])
		at[ids[i]] = [fam[str(d.get("family", ""))], maxi(LINE_ORDER.find(str(d.get("line", "standard"))), 0), i]
	ids.sort_custom(func(a, b): return at[a] < at[b])
	return ids


static func tile_entry(ship, id: String) -> Dictionary:
	var def: Dictionary = ship.grid.defs.get_def(id)
	var door: bool = ship.grid.tile_flag(id, "door")
	var cost: Dictionary = ship.grid.cost_of(id)
	if door:
		cost = _times(cost, 2)  # a door is a piece of two cells
	return _priced({"key": "tile:" + id, "kind": "tile", "id": id, "piece": Shapes.FULL, "name": str(def.get("name", id)),
		"line": str(def.get("line", "standard")), "tier": 0, "size": Vector2i(2, 1) if door else Vector2i.ONE, "out_size": Vector2i.ZERO,
		"power": 0, "cost": cost, "count": 0}, ship)


## A shaped piece of wall material `tile`: each cell costs by its solid area (rounded up per cell).
static func piece_entry(ship, piece: String, tile: String) -> Dictionary:
	var def: Dictionary = ship.grid.defs.get_def(tile)
	return _priced({"key": "piece:%s:%s" % [piece, tile], "kind": "piece", "id": tile, "piece": piece,
		"name": "%s %s" % [def.get("name", tile), piece], "line": str(def.get("line", "standard")), "tier": 0,
		"size": Shapes.piece_size(piece, 0), "out_size": Vector2i.ZERO, "power": 0, "cost": piece_cost(ship.grid, piece, tile), "count": 0}, ship)


static func cable_entry(ship, cable_cost: Dictionary) -> Dictionary:
	return _priced({"key": "cable", "kind": "cable", "id": "cable", "piece": Shapes.FULL, "name": "Cable", "line": "standard", "tier": 0,
		"size": Vector2i.ONE, "out_size": Vector2i.ZERO, "power": 0, "cost": cable_cost.duplicate(), "count": 0}, ship)


## The conveyor belt (docs/CONTENT.md 4f): locked (not ok) until the belt blueprint is known, which the first belt drive brings.
static func belt_entry(ship) -> Dictionary:
	var e := _priced({"key": "belt", "kind": "belt", "id": "belt", "piece": Shapes.FULL, "name": "Belt", "line": "standard", "tier": 0,
		"size": Vector2i.ONE, "out_size": Vector2i.ZERO, "power": 0, "cost": Belts.cost(), "count": 0}, ship)
	if not Ammo.belts_unlocked(ship):
		e["ok"] = false
		e["why"] = "Needs a belt drive first"
	return e


static func part_entry(ship, id: String) -> Dictionary:
	var def: Dictionary = ship.components.def(id)
	var n: int = ship.inventory.count(id)
	var mount := Mounts.is_mount(def)
	return {"key": "part:" + id, "kind": "part", "id": id, "piece": "", "name": str(def.get("name", id)), "line": line_of(def),
		"tier": int(def.get("tier", 0)), "size": Vector2i(int(def["size"][0]), int(def["size"][1])),
		"out_size": Vector2i(int(def["mount"]["outside"][0]), int(def["mount"]["outside"][1])) if mount else Vector2i.ZERO,
		"power": ship.effective(id)["power"], "cost": {}, "count": n, "ok": n > 0, "why": "" if n > 0 else _not_held(ship, id)}


## Why a part that is not held cannot be placed: where to craft it, or that it has no blueprint here.
static func _not_held(ship, id: String) -> String:
	if ship.crafting.is_known(id):
		return "Craft at %s (C)" % str(Crafting.STATIONS.get(ship.crafting.station_of(id), "Fabricator"))
	return "Blueprint not known"



## Held cargo that is not a part (a rare material, ammo, gear): shown, never placed.
static func item_entry(ship, id: String) -> Dictionary:
	return {"key": "item:" + id, "kind": "item", "id": id, "piece": "", "name": ship.crafting.name_of(id, ship.components), "line": "standard",
		"tier": 0, "size": Vector2i.ONE, "out_size": Vector2i.ZERO, "power": 0, "cost": {}, "count": ship.inventory.count(id), "ok": true, "why": ""}


## The border line of a part: "unique" for a found-or-traded part, else its line.
static func line_of(def: Dictionary) -> String:
	return "unique" if def.get("unique", false) else str(def.get("line", "standard"))


## What piece `piece` of `tile` costs: each cell by its solid area, rounded up per cell.
static func piece_cost(grid, piece: String, tile: String) -> Dictionary:
	var sum := {}
	for pc in Shapes.piece_cells(piece, Vector2i.ZERO):
		var cost: Dictionary = grid.cost_of(tile, Shapes.area_of(pc))
		for m in cost:
			sum[m] = int(sum.get(m, 0)) + int(cost[m])
	return sum


static func _priced(e: Dictionary, ship) -> Dictionary:
	var short: Dictionary = ship.inventory.missing(e["cost"])
	e["ok"] = short.is_empty()
	e["why"] = "" if e["ok"] else "short of " + cost_text(short)
	return e


static func _times(cost: Dictionary, k: int) -> Dictionary:
	var out := {}
	for m in cost:
		out[m] = int(cost[m]) * k
	return out


# --- words ------------------------------------------------------------------------------------------------------

## "2 scrap + 1 copper", or "free".
static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for m in cost:
		parts.append("%d %s" % [int(cost[m]), m])
	return " + ".join(parts) if not parts.is_empty() else "free"


## A number: whole ones plain, others with one decimal (5.4).
static func num(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Power with its sign: "+8", "-2", "0".
static func power_text(v: float) -> String:
	return ("+" if v > 0.0 else "") + num(v)


## The one line a tab shows when it has no card.
static func empty_text(tab: int) -> String:
	return EMPTY_TEXT[clampi(tab, 0, EMPTY_TEXT.size() - 1)]


## The figures on the picture of card `e`: [{icon, text, what}] and a gun's aim class (describe.gd glance()); a tile or piece shows its
## hp and mass.
static func glance(e: Dictionary, ship) -> Dictionary:
	if e["kind"] == "part":
		return Describe.glance(e["id"], ship)
	var out := {"stats": [], "aim": ""}
	if e["kind"] in ["tile", "piece"]:
		for r in info(e, ship)["stats"]:
			if r[0] == "HP":
				out["stats"].append({"icon": "st_hp", "text": str(r[1]), "what": "HP"})
			elif r[0] == "Mass":
				out["stats"].append({"icon": "st_mass", "text": str(r[1]), "what": "Mass"})
	return out


static func size_text(s: Vector2i) -> String:
	return "%dx%d" % [s.x, s.y]


## What the selection card says about card `e` on `ship`: {title, line (its name), tier, what (one short line), stats ([label,
## value]), keywords (describe.gd keyword(): label, colour, hover), lore (one sentence), cost ({id: n}), per ("a cell" for
## cable and belt), level (the fabricator level it needs), note (red: why it can't be placed, else "")}. `rot`: the quarter turns
## the tool has now (an engine's push); `angle`: the degrees of the sloped face it is over, -1 for none.
static func info(e: Dictionary, ship, rot := 0, angle := -1.0) -> Dictionary:
	var out := {"title": e["name"], "line": LINE_NAMES.get(e["line"], str(e["line"]).capitalize()), "tier": e["tier"], "what": "",
		"stats": [], "keywords": [], "lore": "", "cost": {}, "per": "", "level": 0, "note": ""}
	var words: Dictionary = Describe.data()["tiles"]
	match e["kind"]:
		"part":
			var d := Describe.of(e["id"], ship, rot, angle)
			for k in ["what", "stats", "keywords", "lore", "cost", "level"]:
				out[k] = d[k]
			out["note"] = "" if e["ok"] else str(e["why"])
		"item":
			var d := Describe.of(e["id"], ship)
			for k in ["what", "lore", "cost", "level"]:
				out[k] = d[k]
			var it: Dictionary = Content.entry("items", e["id"])
			if it.is_empty():
				it = Content.entry("materials", e["id"])
			out["line"] = str(it.get("kind", it.get("rarity", "cargo"))).replace("_", " ").capitalize()
		"cable", "belt":
			out["what"] = words[e["kind"]]
			out["stats"] = [["Size", "1\u00d71"]]
			out["cost"] = e["cost"]
			out["per"] = "a cell"
			out["note"] = "" if e["kind"] == "cable" or Ammo.belts_unlocked(ship) else str(e["why"])
		_:
			_tile_info(out, e, ship, words)
	return out


static func _tile_info(out: Dictionary, e: Dictionary, ship, words: Dictionary) -> void:
	var g = ship.grid
	var def: Dictionary = g.defs.get_def(e["id"])
	var area := 1.0
	if e["kind"] == "piece":
		area = 0.0
		for pc in Shapes.piece_cells(e["piece"], Vector2i.ZERO):
			area += Shapes.area_of(pc)
	var rows := [["Size", "%d\u00d7%d" % [e["size"].x, e["size"].y]]]
	if def.has("hp"):
		rows.append(["HP", num(float(def["hp"]) * area)])
	if def.has("mass"):
		rows.append(["Mass", num(float(def["mass"]) * area)])
	for k in ["resist", "deflect"]:
		var d = def.get(k, {})
		if d is Dictionary and not d.is_empty():
			var parts := []
			for t in d:
				parts.append("%s x%s" % [t, num(float(d[t]))] if k == "resist" else "%s %d%%" % [t, roundi(float(d[t]) * 100.0)])
			rows.append(["Resists" if k == "resist" else "Deflects", ", ".join(parts)])
	out["stats"] = rows
	out["cost"] = e["cost"]
	var q := str(def.get("quirk", ""))
	if Describe.data()["keywords"].has(q):
		out["keywords"].append(Describe.keyword(q, {"deal": float(def.get("ram_deal", 1.0)), "take": float(def.get("ram_take", 1.0))}))
	out["what"] = words["piece"] if e["kind"] == "piece" else (words["door"] if def.get("door", false) else (words["wall"] if def.get("solid", false) else words["floor"]))
