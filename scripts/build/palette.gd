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
##   ok, why   it can be placed now (affordable, or held), else why not
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
const UTILITY_FAMILIES: Array[String] = ["intake", "radar", "tractor", "shield", "oxygen", "bed", "workshop", "fabricator", "smelter", "utility", "ammo_rack", "belt_drive"]
## The cargo the top bar shows (scripts/ui/hud_top_bar.gd), in its order; the Cargo tab lists everything else held.
const BAR_IDS: Array[String] = ["scrap", "copper", "polymer", "titanium", "silicon", "crystal", "credits", "fuel"]
const LINE_ORDER: Array[String] = ["standard", "scrap", "neon"]
const LINE_NAMES := {"scrap": "Scrap", "standard": "Standard", "neon": "Neon", "unique": "Unique"}
const TILE_QUIRKS := {
	"ablative": "Ablative: every energy hit takes 1 from its max hp",
	"lattice_power": "Lattice: part of the energy it absorbs becomes ship power",
	"ram": "Ram plating: deals x%s ram damage in a collision and takes x%s",
}
const DIRS: Array[String] = ["up", "right", "down", "left"]


## The tab a component def belongs on.
static func component_tab(def: Dictionary) -> int:
	match str(def.get("family", "")):
		"weapon":
			return Tab.WEAPONS
		"engine":
			return Tab.ENGINES
	return Tab.UTILITY if str(def.get("family", "")) in UTILITY_FAMILIES else Tab.SYSTEMS


## The cards of tab `tab` for `ship` (`cable_cost`: BuildSession.cable_cost). Structure: every tile and the cable;
## Shapes: every non-full piece of every wall material; Cargo: the parts held, then the other cargo off the top bar;
## the others: the parts of their families that are held or whose blueprint is known (could be crafted), see shown().
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
		Tab.SHAPES:
			for id in g.defs.ids():
				if g.tile_flag(id, "solid") and not g.tile_flag(id, "door"):
					for p in Shapes.piece_ids():
						if p != Shapes.FULL:
							out.append(piece_entry(ship, p, id))
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


## Does the build palette list part `id`: one is held, or its blueprint is known (so it could be crafted)? Anything
## else lives in the crafting panel only.
static func shown(ship, id: String) -> bool:
	return ship.inventory.count(id) > 0 or ship.crafting.is_known(id)


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
		e["why"] = "needs a belt drive"
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
		return "0 held, craft at the %s (C)" % str(Crafting.STATIONS.get(ship.crafting.station_of(id), "fabricator")).to_lower()
	return "none held, and the blueprint is not known"



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


static func size_text(s: Vector2i) -> String:
	return "%dx%d" % [s.x, s.y]


## What the selection card says about card `e` on `ship`: {title, line (its name), tier, does (a part's sentence), rows ([label, value]),
## kinds (what its type means, lines), quirk, abilities (lines), blurb, recipe, place}. `rot`: the quarter turns the tool has now (a mount's facing).
static func info(e: Dictionary, ship, rot := 0) -> Dictionary:
	var out := {"title": e["name"], "line": LINE_NAMES.get(e["line"], str(e["line"]).capitalize()), "tier": e["tier"], "rows": [],
		"does": "", "kinds": [], "quirk": "", "abilities": [], "blurb": "", "recipe": "", "place": ""}
	match e["kind"]:
		"part":
			_part_info(out, e, ship, rot)
		"item":
			var d: Dictionary = Content.entry("items", e["id"])
			if d.is_empty():
				d = Content.entry("materials", e["id"])
			out["line"] = str(d.get("kind", d.get("rarity", "cargo"))).replace("_", " ").capitalize()
			out["rows"] = [["In cargo", str(e["count"])]]
			out["does"] = Describe.of(e["id"], ship)["does"]
			out["blurb"] = str(d.get("blurb", ""))
			out["recipe"] = cost_text(ship.crafting.def(e["id"]).get("materials", {})) if ship.crafting.has(e["id"]) else ""
			out["place"] = "Not placed on the ship: it is spent by weapons, crafting or the crew, or sold at a station."
		"cable":
			out["rows"] = [["Size", "1x1 per cell"], ["Cost", cost_text(e["cost"]) + " a cell"]]
			out["blurb"] = "Carries power from the reactors to the systems. Each joined run of cable is one network."
			out["place"] = "Anywhere in the hull, under floors and systems. Drag to lay a run; every system needs a cable to a reactor."
		"belt":
			out["rows"] = [["Size", "1x1 per cell"], ["Cost", cost_text(e["cost"]) + " a cell"]]
			out["blurb"] = "A conveyor floor. Joined cells are a network; a powered belt drive moves ammo along it from racks to the guns it touches."
			out["place"] = "On floor and doors, never under a system. A rack, gun or drive must have a belt cell against its edge. Drag to lay a run." if Ammo.belts_unlocked(ship) else "Locked: it comes with your first belt drive, a part found or traded for (Rusthold, Meridian and Prism sell them)."
		_:
			_tile_info(out, e, ship)
	return out


static func _tile_info(out: Dictionary, e: Dictionary, ship) -> void:
	var g = ship.grid
	var def: Dictionary = g.defs.get_def(e["id"])
	var area := 1.0
	if e["kind"] == "piece":
		area = 0.0
		for pc in Shapes.piece_cells(e["piece"], Vector2i.ZERO):
			area += Shapes.area_of(pc)
	var rows := [["Size", size_text(e["size"])], ["Cost", cost_text(e["cost"])]]
	if def.has("hp"):
		rows.append(["HP", num(float(def["hp"]) * area) + (" over %d cells" % Shapes.piece_cells(e["piece"], Vector2i.ZERO).size() if e["kind"] == "piece" else "")])
	if def.has("mass"):
		rows.append(["Mass", num(float(def["mass"]) * area)])
	for k in ["resist", "deflect"]:
		var d = def.get(k, {})
		if d is Dictionary and not d.is_empty():
			var parts := []
			for t in d:
				parts.append("%s x%s" % [t, num(float(d[t]))] if k == "resist" else "%s %d%%" % [t, roundi(float(d[t]) * 100.0)])
			rows.append(["Resists" if k == "resist" else "Deflects", ", ".join(parts)])
	out["rows"] = rows
	var q := str(def.get("quirk", ""))
	if TILE_QUIRKS.has(q):
		out["quirk"] = TILE_QUIRKS[q] % [num(float(def.get("ram_deal", 1.0))), num(float(def.get("ram_take", 1.0)))] if q == "ram" else TILE_QUIRKS[q]
	if e["kind"] == "piece":
		out["blurb"] = "A shaped piece of %s: hp, mass and cost scale with its solid area." % def.get("name", e["id"])
		out["place"] = "Top-left cell on the mouse. R turns it, Shift+R mirrors it, T picks the next shape."
	elif def.get("door", false):
		out["blurb"] = "Two cells wide, so a crew member fits through. Opens for the crew and closes behind them."
		out["place"] = "In a straight wall, with wall at both ends. R flips it across. E opens and closes it."
	elif def.get("solid", false):
		out["place"] = "Inside the hull. Ctrl+drag a rectangle to build a room: walls round it, floor inside. T shapes it."
	else:
		out["blurb"] = "Crew walk on it and systems stand on it. Rooms fill with air."
		out["place"] = "Inside the hull. Drag to paint, Shift+drag a line, Ctrl+drag a rectangle."


static func _part_info(out: Dictionary, e: Dictionary, ship, rot: int) -> void:
	var def: Dictionary = ship.components.def(e["id"])
	var d := Describe.of(e["id"], ship, rot)  # what it does, the stats, what its type means, the lore
	out["does"] = d["does"]
	out["rows"] = d["rows"]
	out["kinds"] = d["kinds"]
	out["quirk"] = " ".join(d["notes"])
	out["blurb"] = d["lore"]
	for a in def.get("abilities", []):
		if str(a.get("type", "")) == "passive":
			out["abilities"].append("%s (passive)" % a.get("name", a.get("id", "")))
		else:
			out["abilities"].append("%s: %s key, %s s, rests %s s" % [a.get("name", a.get("id", "")), a.get("key", "?"), num(float(a.get("duration", 0))), num(float(a.get("cooldown", 0)))])
	out["recipe"] = _recipe_text(ship, e["id"], def)
	if Mounts.is_mount(def):
		var o := Mounts.turned(def["mount"]["outside"], rot)
		out["place"] = "Hull mount: outside half %dx%d, pointing %s: put it in space against a flat outer wall. The inside half goes on the floor behind it. R turns it." % [o.x, o.y, DIRS[posmod(rot, 4)]]
	else:
		out["place"] = "On floor inside the hull, clear of other systems. R turns it. Wire it to a reactor with cable."


static func _recipe_text(ship, id: String, def: Dictionary) -> String:
	var r: Dictionary = ship.crafting.def(id)
	if r.is_empty():
		return "No recipe: found, bought or earned" if def.get("unique", false) else "No recipe"
	var t := "%s, %s level %d" % [cost_text(r.get("materials", {})), str(Crafting.STATIONS.get(ship.crafting.station_of(id), "fabricator")).to_lower(), int(r.get("fab_level", 1))]
	if not r.get("tools", []).is_empty():
		t += ", tools: " + ", ".join(r["tools"])
	return t + ("" if ship.crafting.is_known(id) else " (blueprint not known)")
