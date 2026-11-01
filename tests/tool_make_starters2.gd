extends "res://tests/tool_make_starters.gd"
## Not a test (the runner only loads test_*.gd). Builds the starter ships of the pack data/packs/starters_2/ships/:
##   godot --headless --path . --script res://tests/tool_make_starters2.gd [-- skin] [-- <ship file> ...]
## (the names after -- pick the ships to rebuild, by file name; none means all of them).
## The seven event starters whose unlocks sit in data/packs/endings_1/unlocks.json (docs/CONTENT.md 19), then two ships
## for each of the ten races (layout A: the race's signature, with its racial tech and a crew of its kind; layout B: a
## different strategy), each with its own silhouette. They are built by tests/tool_make_starters.gd (same rules, same
## router, same output), which this tool extends: every design here is a "rooms" spec, so the floor is the list of
## rooms and every other cell inside the outline is wall; the design file carries its own `hangar` field {group, layout,
## unlock}, which is how the hangar (space/hangar.gd) finds a pack's ships.
## Racial parts: a part of a race's tech pack (data/packs/tech_<race>/) is used when the pack is loaded, else the
## standard part of the race's line stands in, so this tool works before and after the tech packs land (run it again
## when they do). The cargo takes the same rule.
## The core of each ship is drawn in its own local coordinates with the centre line at x = CX; `at` puts it in the frame.
## Like the first three, each is saved with the round build area of tool_make_starters.gd (DISC_R), not with its frame outline.

const Content = preload("res://scripts/data/content.gd")

const PACK_DIR := "res://data/packs/starters_2/ships/"
const CX := 8  ## the centre line of the standard spine (a core's local x)
## The second gun of the three spine ships that start with two and no shield or medbay: [id, x, y, rot], the outside half's top-left cell.
const GUN2_KETTLE := ["rattle_burst_scrap", "flank"]
const GUN2_PRIZE := ["rattle_burst_scrap", "flank"]


func _makers() -> Dictionary:
	var out := {}
	for spec in _specs():
		var s: Dictionary = spec
		out[s["file"]] = func(): return s
	return out


## A part of a race's tech pack when it is loaded, else the stand-in.
func _p(racial: String, standin: String) -> String:
	return racial if Content.has("components", racial) else standin


## The polygon of a symmetric outline about the centre line x = cx: `prof` is [[y, hw], ...] going down the right-hand side,
## from the top edge to the bottom edge: two points with the same y are a step, two with the same hw a straight run,
## the rest are the edges of the hull (45 degrees: hw changes as much as y; 2:1: hw changes half as much, or twice). A
## corner may be a round2 arc ["arc", hw of its centre, y of its centre, from degrees, to degrees] (the right-hand side's
## angles: 270 to 360 the top corner, 0 to 90 the bottom one).
func _sym(cx: int, prof: Array, other := []) -> Array:
	var out := []
	for p in prof:
		out.append(["arc", cx + p[1], p[2], p[3], p[4]] if p[0] is String else [cx + p[1], p[0]])
	var left: Array = other if not other.is_empty() else prof  # the left-hand side is `other` (a profile like the right-hand one) turned over
	for i in range(left.size() - 1, -1, -1):
		var p: Array = left[i]
		out.append(["arc", cx - p[1], p[2], 180 - p[4], 180 - p[3]] if p[0] is String else [cx - p[1], p[0]])
	return out


## A polygon with the same edges as `poly` turned over about the vertical line x = cx.
func _flip(poly: Array, cx: int) -> Array:
	var out := []
	for i in range(poly.size() - 1, -1, -1):
		var p: Array = poly[i]
		out.append(["arc", 2 * cx - p[1], p[2], 180 - p[4], 180 - p[3]] if p[0] is String else [2 * cx - p[0], p[1]])
	return out


# --- the standard spine ------------------------------------------------------------------------------------------
# The stack every starter here is built round (the Courier's fuselage, in rooms): from the bow, two rows of wall that carry
# the gun, the bridge (the gun's breech and the helm), a row of bulkhead, the quarters (a bed, the O2 and the kit: a shield or a medbay) beside the
# workshop (the fabricator alone), a row of bulkhead, and the engine room (the reactor and the engines, whose bells stick
# out of the stern wall). The core is 12 wide (the interior x = CX-5 .. CX+4) and 21 rows tall; `o` may widen the bridge
# (bh, half its interior width, 4), the quarters (lw) and the workshop (rw), the engine room on either side (el, er), make the
# quarters and the workshop taller (mid rows) or stretch the engine room downwards (down rows). Both move the stern wall.

func _spine(o: Dictionary) -> Dictionary:
	var bh: int = o.get("bh", 4)
	var rw: int = o.get("rw", 0)
	var lw: int = o.get("lw", 0)
	var el: int = o.get("el", 0)
	var er: int = o.get("er", 0)
	var down: int = o.get("down", 0)
	var mid: int = o.get("mid", 0)
	var stern: int = 20 + mid + down  # the row of the stern wall
	var engines: Array = o["engines"]
	var parts := [
		[o["gun"], CX - 2, -2], [o.get("helm", "helm"), CX + 2, 3],
		["bed", CX - 5, 6, 1], [o["o2"], CX - 5, 10, o.get("o2_rot", 1)], ["fabricator", CX + 1, 8],
		[o["reactor"], o.get("rx", CX - 2), 13 + mid],
	]
	if o.get("kit", "") != "":  # a shield or a medbay (P3: exactly one of them, or neither) where the second bed was, or at `kit_at` [x, y, rot]
		var at: Array = o.get("kit_at", [CX - 5, 8, 1])
		parts.append([o["kit"], at[0], at[1], at[2]])
	if engines.size() == 1:
		parts.append([engines[0], CX - 2, stern + 1, 2])
	else:
		parts.append([engines[0], CX - 4, stern + 1, 2])
		parts.append([engines[1], CX, stern + 1, 2])
	for x in o.get("extra", []):
		parts.append(x)
	return {
		"rooms": [[CX - bh, 2, CX + bh - 1, 4], [CX - 5 - lw, 6, CX - 1, 11 + mid], [CX + 1, 6, CX + 4 + rw, 11 + mid], [CX - 5 - el, 13 + mid, CX + 4 + er, stern - 1]],
		"doors": [[CX - 3, 5, "h"], [CX + 2, 5, "h"], [CX - 3, 12 + mid, "h"], [CX + 2, 12 + mid, "h"]],
		"parts": parts, "walls": [], "stern": stern,
	}


## The common parts of a spec: the standard skin rules (plate everywhere, two plated rows round the gun) over `spec`, and
## the core's place in the frame unless the spec gives "at": centred across, a little above the middle down the frame.
## `top` (default 2) is how far the core sticks out above its first row: the gun's outside half, or a horn.
func _spec(spec: Dictionary) -> Dictionary:
	var out := {"walls": [], "plated": func(_c): return true, "backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 1}
	out.merge(spec, true)
	out["dir"] = PACK_DIR
	if not out.has("at"):
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for p in out["frame"]:
			var x: int = p[1] if p[0] is String else p[0]
			var y: int = p[2] if p[0] is String else p[1]
			lo = lo.min(Vector2i(x - (2 if p[0] is String else 0), y))
			hi = hi.max(Vector2i(x + (2 if p[0] is String else 0), y))
		var top: int = out.get("top", 2)
		var core_h: int = top + out["stern"] + 3  # from the highest cell above the core to the bells below the stern wall
		out["at"] = [(hi.x + lo.x) / 2 - CX, top + int((hi.y - core_h) * 0.45)]
	return out


func _specs() -> Array:
	return [
		_halcyon_tender(), _kettle_tug(), _concord_frigate(), _door_prize(), _lumen_skiff(), _hollow_touched(), _patience_sister(),
		_human_ring_runner(), _human_formal_complaint(), _basalt_deepcut(), _basalt_long_quiet(), _emberkin_ember_kite(), _emberkin_flashpan(),
		_fenn_sold_twice(), _fenn_closing_sale(), _kett_ninefold_cell(), _kett_picket_nest(), _mire_wet_watch(), _mire_geyser_season(),
		_sporeling_first_bloom(), _sporeling_mycelium_wall(), _gauntling_graft_row(), _gauntling_lamp_post(), _prismatic_tuning_bell(), _prismatic_flat_note(),
		_grundl_second_helping(), _grundl_tow_rope(),
	]


# --- the event starters (the unlocks of data/packs/endings_1/unlocks.json) -------------------------------------------

## Haven A. A garden tender from Halcyon: round all over (round2 corners and two planter pods on the flanks), soft cream
## plating, a Garden Bay for air where the Sporeling tech is loaded, and a medbay in the hold. Peaceful: one pulse gun.
func _halcyon_tender() -> Dictionary:
	var garden := Content.has("components", "sporeling_garden_bay")
	var k := _spine({"gun": "pulse_mk1", "reactor": "reactor_mk2", "o2": "sporeling_garden_bay" if garden else "oxygen_gen", "o2_rot": 0 if garden else 1, "engines": ["engine_mk1", "engine_mk1"], "kit": "medbay"})
	return _spec(k.merged({
		"file": "halcyon_tender", "name": "Halcyon Tender",
		"hangar": {"group": "Haven", "layout": "A", "unlock": "ship_halcyon_tender"},
		"crew": SOLDIER,
		"blurb": "A garden tender from Halcyon: round, soft-plated and unarmoured in spirit. One pulse gun, a medbay, and forty years of seeds' worth of room to grow in.",
		"frame": _sym(24, [["arc", 8, 2, 270, 360], [16, 24], [26, 24], [40, 10], ["arc", 8, 40, 0, 90]]),
		"outline": _sym(CX, [["arc", 4, 2, 270, 360], [6, 6], ["arc", 7, 8, 270, 360], ["arc", 7, 14, 0, 90], [16, 6], ["arc", 4, 19, 0, 90]]),
		"plate": "whipple_spacer",
		"cargo": {"scrap": 250, "copper": 80, "polymer": 80, "silicon": 20, "credits": 300, "fuel": 8},
	}))


## Clans C. Ma's Kettle-class tug: a fat round pot of a hull with a short spout for a bow, scrap plate all over, two scrap guns and Ma's own
## Kettle crated in the hold for when there is a second reactor's room (the Kettle boils over: it thins the air and starts fires in its room).
func _kettle_tug() -> Dictionary:
	var k := _spine({"gun": "bolt_thrower_scrap", "reactor": "reactor_mk2", "o2": "oxygen_scrap_mk1", "engines": ["engine_scrap_mk1", "engine_scrap_mk1"],
		"bh": 5, "lw": 1, "rw": 3, "el": 3, "er": 3, "extra": [GUN2_KETTLE]})
	return _spec(k.merged({
		"file": "kettle_tug", "name": "Ma's Kettle-class Tug",
		"hangar": {"group": "Clans", "layout": "C", "unlock": "ship_kettle_tug"},
		"crew": SOLDIER,
		"blurb": "Ma Gantry's own tug: a round, scrap-plated pot with two scrap-fed guns and her Kettle crated in the hold. Bolt it in beside the reactor for more power than the ship has any right to, and a room that smells of tea and smoke.",
		"frame": _sym(20, [[0, 6], [8, 14], [11, 20], [32, 20], [35, 14], [43, 6]]),
		"outline": _sym(CX, [["arc", 4, 2, 270, 360], [5, 6], ["arc", 7, 7, 270, 360], ["arc", 7, 19, 0, 90]]),
		"plate": "scrap_plate",
		"cargo": {"scrap": 250, "copper": 80, "polymer": 30, "reactor_scrap_kettle": 1, "net_mouth_scrap": 1, "credits": 300, "fuel": 8},
	}))


## Concord B. Concord Frigate Resolve: the long, clean, symmetric hull of a Concord warship, armoured a cell deeper than the
## others (titanium over titanium), with the best Concord gun, a Mk2 shield in the hold and a point turret to follow it.
func _concord_frigate() -> Dictionary:
	var k := _spine({"gun": "laser_mk2", "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1"], "mid": 4, "down": 2, "kit": "shield_mk2"})
	return _spec(k.merged({
		"file": "concord_frigate", "name": "Concord Frigate Resolve",
		"hangar": {"group": "Concord", "layout": "B", "unlock": "ship_concord_frigate"},
		"crew": SOLDIER,
		"blurb": "A restored Concord frigate: long, symmetric and armoured a layer deeper than the rest. A Mk2 laser to aim, a Mk2 shield, a point turret in the hold, and the paperwork in order.",
		"frame": _sym(18, [[0, 6], [8, 6], [14, 12], [20, 12], [26, 18], [44, 18], [50, 12], [54, 12]]),
		"outline": _sym(CX, [[0, 4], [3, 7], [10, 7], [14, 11], [22, 11], [24, 9], [26, 9], [27, 8]]),
		"plate": "titanium_alloy", "backed": func(c): return c.y <= 24, "thick": func(_c): return true,
		"cargo": {"scrap": 250, "copper": 100, "titanium": 80, "polymer": 30, "laser_turret_mk1": 1, "credits": 400, "fuel": 6},
	}))


## Clans B. Door Prize: a battering wedge, ram plating on its barbed bow and scrap plate behind, a scrap-fed bolt gun in the
## tip and a Battering Bow in the hold for the day the Clans want a door opened.
func _door_prize() -> Dictionary:
	var k := _spine({"gun": "bolt_thrower_scrap", "reactor": "reactor_mk2", "o2": "oxygen_scrap_mk1", "engines": ["engine_scrap_mk1", "engine_scrap_mk1"], "extra": [GUN2_PRIZE]})
	return _spec(k.merged({
		"file": "door_prize", "name": "Door Prize",
		"hangar": {"group": "Clans", "layout": "B", "unlock": "ship_door_prize"},
		"crew": SOLDIER,
		"blurb": "What the Clans give the one who opens the Scrapper Gate: a ram. A barbed wedge of ram plating, a scrap-fed bolt gun in its tip, a rattling turret beside it, and a Battering Bow in the hold to latch on with.",
		"frame": _sym(20, [[0, 8], [8, 16], [16, 16], [24, 20], [34, 20], [38, 16], [46, 12]]),
		"outline": _sym(CX, [[0, 3], [5, 8], [9, 8], [11, 6], [20, 6], [21, 5]]),
		"plate": func(c): return "ram_plating" if c.y <= 11 else "scrap_plate", "backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 8,
		"cargo": {"scrap": 250, "copper": 80, "polymer": 30, "battering_bow": 1, "credits": 250, "fuel": 6},
	}))


## Lumen B. Lumen Skiff Afterimage: a faceted neon skiff, light and quick, whose ion Siren locks doors. A Prism Core,
## one Ion Drive and two radiators, so it runs hot.
func _lumen_skiff() -> Dictionary:
	var k := _spine({"gun": "siren_ion_neon", "reactor": "reactor_neon_mk1", "o2": "oxygen_gen", "engines": ["engine_neon_mk1"], "extra": [["radiator", CX - 5, 15], ["radiator", CX + 3, 15]], "kit": "shield_neon_mk1"})
	return _spec(k.merged({
		"file": "lumen_skiff", "name": "Lumen Skiff Afterimage",
		"hangar": {"group": "Lumen", "layout": "B", "unlock": "ship_lumen_skiff"},
		"crew": SOLDIER,
		"blurb": "Built to study a gate and left behind when the gate stopped answering. A faceted skiff always a moment behind its own light: an ion Siren that locks doors shut, a Prism Core that runs hot, a Neon Lattice shield.",
		"frame": _sym(18, [[0, 6], [6, 12], [10, 12], [16, 18], [28, 18], [34, 12], [40, 6]]),
		"outline": _sym(CX, [[0, 3], [3, 6], [8, 6], [12, 10], [14, 10], [16, 8], [20, 8], [21, 6]]),
		"plate": "neon_lattice",
		"cargo": {"scrap": 250, "copper": 60, "polymer": 30, "silicon": 40, "crystal": 12, "plasma_cell": 3, "engine_neon_mk1": 1, "credits": 400, "fuel": 6},
	}))


## Hollow A. Hollow-Touched: Welcome Aboard: a ship that was made welcome by something polite and is now very slightly wrong.
## A lopsided hull (one flank a smooth curve, the other cut in steps), mirror-polished plating, a Mirror Veil in the hold.
func _hollow_touched() -> Dictionary:
	var k := _spine({"gun": "leech_laser", "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "mid": 4, "kit": "mirror_veil", "kit_at": [CX - 5, 12, 0]})
	return _spec(k.merged({
		"file": "hollow_touched", "name": "Hollow-Touched: Welcome Aboard",
		"hangar": {"group": "Hollow", "layout": "A", "unlock": "ship_hollow_touched"},
		"crew": SOLDIER,
		"blurb": "Everything works, and everything is a little too clean. A lopsided hull, plating polished to a mirror, a Leech Laser that takes your power and a Mirror Veil in the quarters. Stay to dinner.",
		"frame": _sym(22, [["arc", 8, 2, 270, 360], [4, 10], [14, 20], [28, 20], [38, 10], [40, 10]], [[0, 8], [8, 16], [14, 16], [14, 22], [26, 22], [26, 16], [34, 16], [40, 10]]),
		"outline": _sym(CX, [["arc", 4, 2, 270, 360], [4, 6], ["arc", 8, 6, 270, 360], ["arc", 8, 21, 0, 90], [23, 6], ["arc", 4, 23, 0, 90]], [[0, 4], [4, 6], [7, 6], [7, 8], [10, 8], [10, 7], [13, 7], [13, 9], [16, 9], [16, 6], [24, 6], [25, 5]]),
		"plate": "reflective_coating",
		"cargo": {"scrap": 250, "copper": 60, "polymer": 40, "silicon": 20, "inertial_dampener": 1, "credits": 250, "fuel": 6},
	}))


## Concord C. CS-002 Forbearance: the little sister of the flagship Patience, in the yard at Meridian and never launched.
## A huge frame and a skeleton built in it: one engine, one pulse gun, a skeleton crew. A hard start with the most room.
func _patience_sister() -> Dictionary:
	var k := _spine({"gun": "pulse_mk1", "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "mid": 2, "kit": "shield_mk1"})
	return _spec(k.merged({
		"file": "patience_sister", "name": "CS-002 Forbearance",
		"hangar": {"group": "Concord", "layout": "C", "unlock": "ship_patience_sister"},
		"crew": SOLDIER,
		"blurb": "The Patience's little sister, never launched: a flagship's bare ribs and a skeleton built in them. One engine, one pulse gun, a shield, a skeleton crew and military circuit boards in the hold. A hard start with room to grow.",
		"frame": _sym(24, [[0, 8], [8, 8], [16, 16], [20, 16], [28, 24], [44, 24], [52, 16], [58, 16]]),
		"outline": _sym(CX, [[0, 4], [4, 6], [7, 6], [7, 9], [9, 9], [9, 6], [13, 6], [13, 9], [15, 9], [15, 6], [19, 6], [19, 9], [21, 9], [21, 6], [22, 6], [23, 5]]),
		"plate": "titanium_alloy",
		"cargo": {"scrap": 250, "copper": 100, "titanium": 60, "polymer": 40, "military_circuit": 4, "engine_mk1": 1, "credits": 300, "fuel": 6},
	}))


# --- the races: a signature ship (A) and a different strategy (B) each ------------------------------------------------

## The base cargo of a race starter (building materials and a little money) over which `extra` goes, and the counts of the
## parts that wait in the hold: `parts` is a list of component ids (a racial one where its pack is loaded, else its stand-in).
func _cargo(extra: Dictionary, parts: Array, scrap := 250) -> Dictionary:
	var out := {"scrap": scrap, "copper": 80, "polymer": 30, "credits": 350, "fuel": 6}
	out.merge(extra, true)
	for id in parts:
		out[id] = int(out.get(id, 0)) + 1
	return out


func _race_ship(file: String, name: String, group: String, layout: String, how_crew: Array, blurb: String, k: Dictionary, outline: Array, frame: Array, plate, cargo: Dictionary, more := {}) -> Dictionary:
	var spec := {
		"file": file, "name": name, "hangar": {"group": group, "layout": layout, "unlock": "ship_" + file},
		"crew": how_crew, "blurb": blurb, "frame": frame, "outline": outline, "plate": plate, "cargo": cargo,
	}
	spec.merge(k)
	spec.merge(more, true)
	return _spec(spec)


## Human A. The balanced ship of the Core: a swept-winged cruiser in Concord titanium, a standard reactor and two good engines,
## Crew Quarters Deluxe for a medbay and a Reactor Plus in the hold.
func _human_ring_runner() -> Dictionary:
	var k := _spine({"gun": "laser_mk1", "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2", "engine_mk2"], "kit": _p("human_crew_quarters_deluxe", "medbay"), "kit_at": [CX - 5, 8, 0]})
	return _race_ship("human_ring_runner", "Ring Runner", "Human", "A", SOLDIER,
		"Raced by a Haldane Ring captain who swore there was nothing to apologise for, and never did. Swept wings, titanium skin, a laser, two good engines, deluxe quarters (a medbay with a view), a spare Reactor Plus in the hold.",
		k, _sym(CX, [[0, 4], [4, 6], [8, 6], [11, 9], [14, 9], [17, 6], [20, 6], [21, 5]]),
		_sym(21, [[0, 5], [16, 21], [30, 21], [30, 10], [46, 10]]), "titanium_alloy",
		_cargo({"titanium": 40}, [_p("human_reactor_plus", "reactor_mk1")]))


## Human B. A missile boat: shoulder pylons forward to carry the Volley Rack, ten missiles, a Flak Screen in the hold to answer theirs.
func _human_formal_complaint() -> Dictionary:
	var k := _spine({"gun": _p("human_volley_rack", "artemis_mk1"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "kit": "shield_mk1"})
	return _race_ship("human_formal_complaint", "Formal Complaint", "Human", "B", SOLDIER,
		"Filed in triplicate and fired in salvos by a Haldane Ring clerk tired of waiting for a reply. A Volley Rack on a pylon-shouldered hull, ten missiles in the rack and a Flak Screen in the hold for the replies.",
		k, _sym(CX, [[0, 3], [2, 5], [5, 5], [5, 9], [9, 9], [12, 6], [20, 6], [21, 5]]),
		_sym(18, [[0, 18], [12, 18], [36, 6], [46, 6]]), "titanium_alloy",
		_cargo({"missile": 10}, [_p("human_flak_screen", "laser_turret_mk1")]))


## Basalt A. A slow quarry block: heavy armour all round, a Vacuum Forge (+3 power, it empties its room) and a Magma Spitter. Basalt do not breathe.
func _basalt_deepcut() -> Dictionary:
	var k := _spine({"gun": _p("basalt_magma_spitter", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "kit": "shield_mk1"})
	return _race_ship("basalt_deepcut", "Deepcut", "Basalt", "A", SOLDIER,
		"A quarry block a Basalt crew cut loose and bolted an engine to. Heavy plating, a Vacuum Forge that runs best with no air, a Magma Spitter that keeps eating. The crew do not mind the vacuum. The Soldier does.",
		k, _sym(CX, [[0, 4], [4, 8], [8, 8], [8, 10], [16, 10], [16, 8], [19, 8], [21, 6]]),
		_sym(22, [[0, 6], [16, 22], [36, 22], [52, 6]]), "heavy_armor",
		_cargo({"titanium": 40, "silicon": 20}, [_p("basalt_vacuum_forge", "reactor_mk1"), _p("basalt_stonehide_bay", "inertial_dampener")]),
		{"backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 3})


## Basalt B. A brick: a ziggurat of heavy armour, a Quarry Driver's huge slow slug, a small engine and a medbay.
func _basalt_long_quiet() -> Dictionary:
	var k := _spine({"gun": _p("basalt_quarry_driver", "laser_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "kit": "medbay"})
	return _race_ship("basalt_long_quiet", "Long Quiet", "Basalt", "B", SOLDIER,
		"The last ship of a gate-builders' crew, parked forty years because nobody wanted to be first to talk. Stepped heavy armour, a Quarry Driver that pierces three walls, a small engine, a medbay and a long silence.",
		k, _sym(CX, [[0, 3], [2, 5], [4, 5], [4, 7], [8, 7], [8, 9], [14, 9], [16, 7], [20, 7], [21, 6]]),
		_sym(20, [[0, 8], [6, 8], [6, 14], [14, 14], [14, 20], [38, 20], [38, 14], [44, 14], [44, 8], [50, 8]]), "heavy_armor",
		_cargo({"titanium": 60}, [_p("basalt_stonehide_bay", "inertial_dampener")]),
		{"backed": func(c): return c.y <= 1 or (c.y >= 5 and c.y <= 19), "thick": func(_c): return true})


## Emberkin A. A hot kite: a Prism Core, a Pyre Lance that sets fires and a Pyre Drive that burns its own room, two radiators. The crew shrug it off.
func _emberkin_ember_kite() -> Dictionary:
	var k := _spine({"gun": _p("emberkin_pyre_lance", "heat_lance_neon"), "reactor": "reactor_neon_mk1", "o2": "oxygen_gen", "engines": [_p("emberkin_pyre_drive", "afterburner")],
		"extra": [["radiator", CX - 5, 15], ["radiator", CX + 3, 15]], "kit": _p("emberkin_hearth_shield", "shield_neon_mk1"), "kit_at": [CX - 5, 17, 1]})  # (the Hearth Shield warms itself: it goes in the engine room, with the radiators)
	return _race_ship("emberkin_ember_kite", "Ember Kite", "Emberkin", "A", SOLDIER,
		"An Emberkin pilot's pride, flown hot until the pilot retired somewhere cold and sulky. A Prism Core, a Pyre Lance that sets fires where it sweeps, an engine that burns its own room, two radiators. The crew call it cosy.",
		k, _sym(CX, [[0, 3], [2, 5], [3, 6], [7, 6], [11, 10], [15, 10], [19, 6], [20, 6], [21, 5]]),
		_sym(22, [[0, 4], [10, 14], [16, 14], [24, 22], [32, 22], [42, 12]]), "ablative_plating",
		_cargo({"silicon": 30, "crystal": 8}, ["afterburner"]))


## Emberkin B. A fire ship: a round-shouldered pan of a hull, a Cinder Mortar that lobs incendiaries, two engines and crew who stand in the flames.
func _emberkin_flashpan() -> Dictionary:
	var k := _spine({"gun": _p("emberkin_cinder_mortar", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1", "engine_mk1"], "kit": "medbay"})
	return _race_ship("emberkin_flashpan", "Flashpan", "Emberkin", "B", SOLDIER,
		"Won in a foundry race by an Emberkin who spent the prize on fuel, and the fuel on a fire. A Cinder Mortar that lobs fire, two engines, a hull that does not mind it. The crew stand in the flames and call for more.",
		k, _sym(CX, [["arc", 4, 2, 270, 360], ["arc", 6, 6, 270, 360], ["arc", 6, 17, 0, 90], ["arc", 4, 19, 0, 90]]),
		_sym(18, [[0, 12], [6, 18], [28, 18], [34, 12], [34, 4], [52, 4]]), "ablative_plating",
		_cargo({"polymer": 50, "heat_suit": 2}, ["radiator"]), {"at": [10, 8]})


## Fenn A. A quick stall on long ears: a Twitch Cannon, a Haggle Engine and a medbay, all fixed by quick hands. Fragile.
func _fenn_sold_twice() -> Dictionary:
	var k := _spine({"gun": _p("fenn_twitch_cannon", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": [_p("fenn_haggle_engine", "engine_mk2")], "kit": "medbay"})
	return _race_ship("fenn_sold_twice", "Sold Twice", "Fenn", "A", SOLDIER,
		"Sold twice before it left the dock, to two Fenn who are still arguing about it. Quick and light: a Twitch Cannon that fires fast and sulks, a Haggle Engine, a Jury Reactor in the hold. The crew mend it faster than it breaks.",
		k, _sym(CX, [[0, 2], [0, 4], [-5, 4], [-6, 5], [-5, 6], [4, 6], [20, 6], [21, 5]]),
		_sym(18, [[0, 4], [8, 12], [14, 12], [20, 18], [30, 18], [40, 8], [46, 8]]), "whipple_spacer",
		_cargo({"silicon": 20}, [_p("fenn_jury_reactor", "reactor_mk1"), _p("fenn_quickfix_bay", "inertial_dampener")]),
		{"top": 8})


## Fenn B. A market stall with missiles: a canopy of a bow, a Market Missile on scrap rounds, a salvage intake in the hold to restock.
func _fenn_closing_sale() -> Dictionary:
	var k := _spine({"gun": _p("fenn_market_missile", "artemis_mk1"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1", "engine_mk1"], "kit": "medbay"})
	return _race_ship("fenn_closing_sale", "Closing Sale", "Fenn", "B", SOLDIER,
		"A Fenn trader's last ship: the stock ran out, the lease ran out, the canopy stayed. A Market Missile that runs on scrap (a quarter are duds), a salvage intake in the hold. Everything must go, preferably at someone else.",
		k, _sym(CX, [[0, 8], [3, 8], [5, 6], [20, 6], [21, 5]]),
		_sym(22, [[0, 14], [6, 14], [10, 18], [20, 18], [24, 22], [34, 22], [42, 14], [46, 14]]), "titanium_alloy",
		_cargo({}, ["intake_mk1", _p("fenn_jury_reactor", "reactor_mk1")]))


## Kett A. A segmented hive cell: a scrap hull in bumps like body rings, a Chitin Thrower that wants two hands, a Brood Hold in the engine room.
func _kett_ninefold_cell() -> Dictionary:
	var k := _spine({"gun": _p("kett_chitin_thrower", "pulse_mk1"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "extra": [[_p("kett_brood_hold", "radiator"), CX - 5, 15]], "kit": "shield_mk1"})
	return _race_ship("kett_ninefold_cell", "Ninefold Cell", "Kett", "A", SOLDIER,
		"One cell of a hive cut off in the Snap that kept building the same ship. Ringed like a body, a Chitin Thrower that wants two Kett on it, a Brood Hold in the engine room where they work together. Alone, a Kett sulks.",
		k, _sym(CX, [[0, 4], [4, 6], [6, 6], [6, 7], [8, 7], [8, 6], [10, 6], [10, 7], [12, 7], [12, 6], [14, 6], [14, 7], [16, 7], [16, 6], [20, 6], [21, 5]]),
		_sym(20, [[0, 6], [6, 12], [10, 12], [14, 16], [18, 16], [22, 20], [30, 20], [34, 16], [38, 16], [42, 12], [46, 12]]), "scrap_plate",
		_cargo({"polymer": 50}, ["engine_mk1"]))


## Kett B. A boarder: a nest with swollen rear sacs, a Hive Swarm Launcher, a Breach Harpoon to latch on and four Kett to go over.
func _kett_picket_nest() -> Dictionary:
	var k := _spine({"gun": _p("kett_hive_swarm_launcher", "artemis_mk1"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "kit": "medbay"})
	return _race_ship("kett_picket_nest", "Picket Nest", "Kett", "B", SOLDIER,
		"A Kett nest that went visiting and never quite went home. A Hive Swarm Launcher, a medbay, a Breach Harpoon in the hold to latch on, and room for the five hands on the rivet guns it will need.",
		k, _sym(CX, [[0, 4], [4, 6], [11, 6], ["arc", 7, 13, 270, 360], ["arc", 7, 18, 0, 90], [20, 6], [21, 5]]),
		_sym(20, [[0, 8], [4, 12], [8, 12], [12, 16], [16, 16], [20, 20], [32, 20], [38, 14], [44, 14]]), "scrap_plate",
		_cargo({"missile": 8}, ["breach_harpoon"]))


## Mire A. A fire tender: a teardrop with a belly of water at the stern, a Steam Lance and a Wetwell Reactor in the hold. Crew who put fires out twice as fast.
func _mire_wet_watch() -> Dictionary:
	var k := _spine({"gun": _p("mire_steam_lance", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1"], "kit": _p("mire_rain_shield", "shield_mk1")})
	return _race_ship("mire_wet_watch", "Wet Watch", "Mire", "A", SOLDIER,
		"The Concord's fire tender, still on watch: a teardrop with a belly of water, a Steam Lance that hits hard and sets its own room smouldering, and Mire crew who put it out twice as fast.",
		k, _sym(CX, [[0, 3], [2, 5], [4, 6], [8, 6], [11, 9], ["arc", 7, 19, 0, 90]]),
		_sym(18, [[0, 4], [8, 12], [12, 12], [18, 18], [34, 18], [40, 12], [44, 12]]), "titanium_alloy",
		_cargo({"polymer": 60}, [_p("mire_wetwell_reactor", "reactor_mk1"), _p("mire_spray_deck", "inertial_dampener")]))


## Mire B. A wet siege: twin boilers on the shoulders, a Bog Mortar that eats walls and a Mist Projector in the hold.
func _mire_geyser_season() -> Dictionary:
	var k := _spine({"gun": _p("mire_bog_mortar", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1", "engine_mk1"], "kit": "medbay"})
	return _race_ship("mire_geyser_season", "Geyser Season", "Mire", "B", SOLDIER,
		"Raised by Mire dockhands tired of other people's fires, who built a siege ship round the boilers. A Bog Mortar whose slurry eats the wall it lands on, a Mist Projector in the hold. Wet, loud and quite safe from fire.",
		k, _sym(CX, [["arc", 4, 2, 270, 360], [4, 6], ["arc", 7, 6, 270, 360], ["arc", 7, 13, 0, 90], [15, 6], [20, 6], [21, 5]]),
		_sym(20, [[0, 6], [10, 16], [14, 16], [18, 20], [30, 20], [34, 16], [38, 16], [48, 6]]), "titanium_alloy",
		_cargo({"polymer": 50}, [_p("mire_mist_projector", "laser_turret_mk1")]))


## Sporeling A. A mushroom: a round cap for the bridge on a narrow stalk, a Bloom Reactor (+3 power, it eats the room's air), a Garden Bay and a Spore Cannon.
func _sporeling_first_bloom() -> Dictionary:
	var garden := Content.has("components", "sporeling_garden_bay")
	var k := _spine({"gun": _p("sporeling_spore_cannon", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "sporeling_garden_bay" if garden else "oxygen_gen", "o2_rot": 0 if garden else 1,
		"engines": ["engine_mk2"], "bh": 6, "kit": "medbay"})
	return _race_ship("sporeling_first_bloom", "First Bloom", "Sporeling", "A", SOLDIER,
		"Grown from a seed in a derelict's hold, given an engine out of politeness. A cap on a stalk, a Garden Bay, a Spore Cannon that thins the enemy's air, a Bloom Reactor in the hold that eats its room's (the crew make more).",
		k, _sym(CX, [["arc", 7, 2, 270, 360], ["arc", 7, 5, 0, 90], [7, 6], [20, 6], [21, 5]]),
		_sym(22, [[0, 10], [12, 22], [16, 22], [22, 16], [32, 16], [38, 22], [44, 22], [50, 16]]), "whipple_spacer",
		_cargo({"polymer": 80}, [_p("sporeling_bloom_reactor", "reactor_mk1"), _p("sporeling_pollen_turret", "laser_turret_mk1")]))


## Sporeling B. A shield wall: a round slab of a hull, a Rot Pod and a Mycelium Shield in the hold that regrows.
func _sporeling_mycelium_wall() -> Dictionary:
	var garden := Content.has("components", "sporeling_garden_bay")
	var k := _spine({"gun": _p("sporeling_rot_pod", "artemis_mk1"), "reactor": "reactor_mk2", "o2": "sporeling_garden_bay" if garden else "oxygen_gen", "o2_rot": 0 if garden else 1, "engines": ["engine_mk2"], "kit": _p("sporeling_mycelium_shield", "shield_mk2")})
	return _race_ship("sporeling_mycelium_wall", "Mycelium Wall", "Sporeling", "B", SOLDIER,
		"A wall that took root across a Sporeling hull, and the hull gave in. A rounded slab, a Rot Pod that spreads along the wall it hits, a Mycelium Shield that regrows its layers. Patient, damp and hard to shift.",
		k, _sym(CX, [["arc", 7, 2, 270, 360], ["arc", 7, 19, 0, 90]]),
		_sym(26, [[0, 10], [16, 26], [26, 26], [40, 12]]), "whipple_spacer",
		_cargo({"polymer": 80, "missile": 6}, [_p("sporeling_garden_bay", "oxygen_gen")]),
		{"backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 3})


## Gauntling A. A patchwork: an asymmetric hull of mismatched plates (scrap, titanium and bare steel), an Arc Core that shocks organic crew, an Arc Hammer and an Overclock Engine for mechanical hands.
func _gauntling_graft_row() -> Dictionary:
	var k := _spine({"gun": _p("gauntling_arc_hammer", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": [_p("gauntling_overclock_engine", "engine_mk2")], "kit": "medbay"})
	return _race_ship("gauntling_graft_row", "Graft Row", "Gauntling", "A", SOLDIER,
		"Proud of every part and every part used to be someone else's: a patchwork hull of mismatched plates, an Arc Hammer, an engine that runs flat out for mechanical hands and an Arc Core in the hold that shocks anyone with a pulse.",
		k, _sym(CX, [[0, 4], [4, 6], [8, 6], [10, 8], [14, 8], [16, 6], [20, 6], [21, 5]], [[0, 3], [3, 6], [11, 6], [11, 7], [15, 7], [15, 6], [20, 6], [21, 5]]),
		_sym(20, [[0, 6], [6, 12], [10, 12], [18, 20], [28, 20], [36, 12], [46, 12]], [[0, 10], [10, 20], [16, 20], [22, 14], [36, 14], [40, 10], [46, 10]]),
		func(c): return "titanium_alloy" if (c.x + c.y * 2) % 5 == 0 else "scrap_plate",
		_cargo({}, [_p("gauntling_arc_core", "reactor_mk1"), _p("gauntling_graft_bay", "robot_arm")]),
		{"plated": func(c): return (c.x * 3 + c.y * 2) % 11 > 0, "backed": func(c): return c.y <= 1 or (c.x >= 15 and c.y >= 9 and c.y <= 17), "thick": func(_c): return true})


## Gauntling B. A scavenger: a mast and a lamp on a lopsided hull, a Scrap Shotgun that jams, a salvage intake and a Net Mouth in the hold.
func _gauntling_lamp_post() -> Dictionary:
	var k := _spine({"gun": _p("gauntling_scrap_shotgun", "pulse_mk1"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "extra": [[_p("gauntling_tesla_picket", "laser_turret_mk1"), "flank"]]})
	return _race_ship("gauntling_lamp_post", "Lamp Post", "Gauntling", "B", SOLDIER,
		"A scavenger's boat with a mast and a work lamp, kept lit through forty years of other people's wrecks. A Scrap Shotgun that jams one volley in seven, a Tesla Picket for the rude, a salvage intake and a Net Mouth in the hold.",
		k, _sym(CX, [[0, 2], [0, 6], [-8, 6], [-8, 8], [4, 8], [4, 6], [20, 6], [21, 5]], [[0, 4], [4, 6], [20, 6], [21, 5]]),
		_sym(20, [[0, 8], [8, 16], [14, 16], [18, 20], [30, 20], [38, 12], [44, 12]]), "scrap_plate",
		_cargo({}, ["intake_mk1", "net_mouth_scrap"]), {"top": 10})


## Prismatic A. A bell of crystal: a pointed bow flaring to the stern, a Prism Lens that wants a Prismatic on it, a Resonance Helm, an Ion Drive Halo.
func _prismatic_tuning_bell() -> Dictionary:
	var k := _spine({"gun": _p("prismatic_prism_lens", "heat_lance_neon"), "reactor": "reactor_neon_mk1", "o2": "oxygen_gen", "helm": _p("prismatic_resonance_helm", "helm"), "engines": ["engine_neon_mk2"],
		"extra": [["radiator", CX - 5, 15], ["radiator", CX + 3, 15]], "kit": _p("prismatic_lattice_shield", "shield_neon_mk1")})
	return _race_ship("prismatic_tuning_bell", "Tuning Bell", "Prismatic", "A", SOLDIER,
		"A bell struck once, forty years ago, and still ringing. Faceted, flaring to the stern: a Prism Lens at full power only with a crystal-born hand on it, a Resonance Helm that evades for a Prismatic, a Song Reactor in the hold.",
		k, _sym(CX, [[0, 3], [3, 6], [10, 6], [14, 10], [20, 10], [21, 9]]),
		_sym(20, [[0, 6], [6, 12], [14, 12], [22, 20], [30, 20], [38, 12], [46, 12]]), "neon_lattice",
		_cargo({"silicon": 30, "crystal": 10}, [_p("prismatic_song_reactor", "reactor_mk1")]))


## Prismatic B. A glass cannon: a lozenge of reflective plating, a Refractor whose shots split on shields and a Lattice Shield in the hold.
func _prismatic_flat_note() -> Dictionary:
	var k := _spine({"gun": _p("prismatic_refractor", "heat_lance_neon"), "reactor": "reactor_neon_mk1", "o2": "oxygen_gen", "engines": ["engine_neon_mk2"], "extra": [["radiator", CX - 5, 15], ["radiator", CX + 3, 15]], "kit": "medbay"})
	return _race_ship("prismatic_flat_note", "Flat Note", "Prismatic", "B", SOLDIER,
		"A Prismatic ship tuned a half-step flat, and nobody has dared tell the hull. A lozenge of reflective plating, a Refractor that splits its shots on a shield, a medbay for the rest. Brilliant, thin-skinned, afraid of ion.",
		k, _sym(CX, [[0, 4], [4, 8], [8, 10], [12, 10], [16, 8], [20, 6], [21, 5]]),
		_sym(20, [[0, 4], [16, 20], [26, 20], [42, 4]]), "reflective_coating",
		_cargo({"silicon": 40, "crystal": 12, "plasma_cell": 3}, ["radiator"]))


## Grundl A. A barge: a wide boxed hull with a notch in the stern, a Slug Mortar that empties its racks fast and Hauler Thrusters that need a Grundl to restock.
func _grundl_second_helping() -> Dictionary:
	var k := _spine({"gun": _p("grundl_slug_mortar", "pulse_mk2"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk2"], "bh": 5, "lw": 1, "rw": 3, "el": 2, "er": 3, "kit": "medbay"})
	return _race_ship("grundl_second_helping", "Second Helping", "Grundl", "A", SOLDIER,
		"A Grundl freight barge refitted for a war nobody declared. The bow of a warship, a Slug Mortar that throws half the cargo, a medbay, a hold you could live in and Hauler Thrusters crated for the way home.",
		k, _sym(CX, [[0, 5], [2, 7], [4, 7], [4, 9], [19, 9], [21, 7]]),
		_sym(24, [[0, 10], [10, 20], [14, 20], [18, 24], [34, 24], [38, 20], [42, 20], [52, 10]]), "heavy_armor",
		_cargo({"titanium": 40}, [_p("grundl_hauler_thrusters", "engine_mk2"), _p("grundl_cargo_deck", "inertial_dampener")]),
		{"backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 3})


## Grundl B. A tug with tongs: two long arms forward, a Grapple Harpoon that drags the enemy close and a Grundl to hit what arrives.
func _grundl_tow_rope() -> Dictionary:
	var k := _spine({"gun": _p("grundl_grapple_harpoon", "breach_harpoon"), "reactor": "reactor_mk2", "o2": "oxygen_gen", "engines": ["engine_mk1", "engine_mk1"], "kit": "medbay"})
	return _race_ship("grundl_tow_rope", "Tow Rope", "Grundl", "B", SOLDIER,
		"A Grundl tug that spent years towing dead ships home and decided the live ones were next. Two long tongs for a bow, a Grapple Harpoon that drags the enemy close, a crew who hit twice as hard in a corridor. Slowly.",
		k, _sym(CX, [[0, 2], [0, 6], [-6, 6], [-8, 8], [-8, 9], [4, 9], [4, 7], [20, 7], [21, 6]]),
		_sym(22, [[0, 10], [6, 16], [10, 16], [16, 22], [34, 22], [40, 16], [46, 10]]), "heavy_armor",
		_cargo({}, [_p("grundl_cargo_deck", "inertial_dampener")]),
		{"top": 10, "backed": func(c): return c.y <= 1, "thick": func(c): return c.y <= 3})
