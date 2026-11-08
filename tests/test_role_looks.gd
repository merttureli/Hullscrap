extends "res://tests/base_test.gd"
## The looks of the fighting roles (data/role_looks.json, scripts/space/hullgen.gd with_look() and the role ops, scripts/view/dressing.gd):
## each role op on a plain stack of decks, the style's ops leaving the corners a role made, the look laid over a style, the old roles'
## ships exactly as before, every role's ship looking like its role, building as well as the old roles, and wearing its dressing.

const Hullgen = preload("res://scripts/space/hullgen.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Dressing = preload("res://scripts/view/dressing.gd")
const Gallery = preload("res://tests/tool_enemy_gallery.gd")

const NEW_ROLES := ["skirmisher", "carrier", "boarder", "flanker", "siege", "bulwark"]
## Ships of the old roles (pinned by `:role:`) before the role looks: the sha256 (first 16 hex) of their dict, name, crew, pilot and meta.
const OLD_SHIPS := {
	"gen:rustfangs:small:40:6000:s3:role:gunboat": "e6c12806740770ab",
	"gen:rustfangs:small:53:9500:s3:role:brawler": "8b59550c5a93b6b1",
	"gen:rustfangs:medium:66:13000:s3:role:escort": "88c7a85869ada890",
	"gen:rustfangs:medium:79:16500:s3:role:sniper": "e4b7184d82eb5ec5",
	"gen:rustfangs:large:92:20000:s3:role:hauler": "16863aa3c2aaf182",
	"gen:rustfangs:large:105:23500:s3:role:gunboat": "faafaee6b4439eeb",
	"gen:concord:small:118:27000:s3:role:brawler": "7e4f798b804fd232",
	"gen:concord:small:131:6000:s3:role:escort": "36e0cf87f7f43045",
	"gen:concord:medium:144:9500:s3:role:sniper": "3f7a76fdece98b4e",
	"gen:concord:medium:157:13000:s3:role:hauler": "bc3d0f6be940be72",
	"gen:concord:large:170:16500:s3:role:gunboat": "caca99ad98f591b0",
	"gen:concord:large:183:20000:s3:role:brawler": "be0656554a8b2a02",
	"gen:lumen:small:196:23500:s3:role:escort": "bb22a09114a81c90",
	"gen:lumen:small:209:27000:s3:role:sniper": "ebef2237e32e7465",
	"gen:lumen:medium:222:6000:s3:role:hauler": "2b70ae14e0fd5142",
	"gen:lumen:medium:235:9500:s3:role:gunboat": "f63964e8d271ec1b",
	"gen:lumen:large:248:13000:s3:role:brawler": "56197fa131fde058",
	"gen:lumen:large:261:16500:s3:role:escort": "d011fa0d1d48c96a",
	"gen:wardens:small:274:20000:s3:role:sniper": "1ef4b9068e655791",
	"gen:wardens:small:287:23500:s3:role:gunboat": "ff1f5f6e830b5a23",
	"gen:wardens:medium:300:27000:s3:role:gunboat": "134a50f89392efcd",
	"gen:wardens:medium:313:6000:s3:role:brawler": "6f1bb767de7dede1",
	"gen:wardens:large:326:9500:s3:role:escort": "76016404ba4a8f1f",
	"gen:wardens:large:339:13000:s3:role:sniper": "07bfe98193b98734",
	"gen:clans:small:352:16500:s3:role:gunboat": "312a47292fdfbf00",
	"gen:clans:small:365:20000:s3:role:gunboat": "84fbdd217d47fb38",
	"gen:clans:medium:378:23500:s3:role:brawler": "274eb2f8d7e73908",
	"gen:clans:medium:391:27000:s3:role:escort": "d7df20519ade9d8f",
	"gen:clans:large:404:6000:s3:role:sniper": "f53f83a12e36d497",
	"gen:clans:large:417:9500:s3:role:hauler": "26e3c7f514375dab",
	"gen:hollow:small:430:13000:s3:role:gunboat": "dddf9fa410dedfce",
	"gen:hollow:small:443:16500:s3:role:brawler": "38a4123edc8b29dd",
	"gen:hollow:medium:456:20000:s3:role:escort": "7173f0eb6e51fc18",
	"gen:hollow:medium:469:23500:s3:role:sniper": "938f8278174b40fc",
	"gen:hollow:large:482:27000:s3:role:hauler": "3561efe731da60cc",
	"gen:hollow:large:495:6000:s3:role:gunboat": "37914105210d1254",
	"gen:kett:small:508:9500:s3:role:brawler": "739f6e298e505177",
	"gen:kett:small:521:13000:s3:role:escort": "d2aca777003d5cef",
	"gen:kett:medium:534:16500:s3:role:sniper": "497584ac953e567d",
	"gen:kett:medium:547:20000:s3:role:hauler": "2279079faaa3e701",
	"gen:kett:large:560:23500:s3:role:gunboat": "ad0c48774e6b88c4",
	"gen:kett:large:573:27000:s3:role:brawler": "e63f3e4f48b8832a",
	"gen:grundl:small:586:6000:s3:role:escort": "c9a9b88994d46207",
	"gen:grundl:small:599:9500:s3:role:sniper": "13263017fee9d785",
	"gen:grundl:medium:612:13000:s3:role:hauler": "585446a10f86e9c3",
	"gen:grundl:medium:625:16500:s3:role:gunboat": "299f00939eabe66e",
	"gen:grundl:large:638:20000:s3:role:brawler": "7db3573e139e3d3a",
	"gen:grundl:large:651:23500:s3:role:escort": "ef074aea6546efb1",
	"gen:sporeling:small:664:27000:s3:role:sniper": "0c55b64bda8609db",
	"gen:sporeling:small:677:6000:s3:role:gunboat": "013345cc2b311a15",
	"gen:sporeling:medium:690:9500:s3:role:gunboat": "b9d9a81f6c4b1c41",
	"gen:sporeling:medium:703:13000:s3:role:brawler": "362aa31b2a058ef7",
	"gen:sporeling:large:716:16500:s3:role:escort": "b0e908b60d9b4b2f",
	"gen:sporeling:large:729:20000:s3:role:sniper": "11041516c893aa9e",
	"gen:prismatic:small:742:23500:s3:role:gunboat": "baa0be069538e9bd",
	"gen:prismatic:small:755:27000:s3:role:gunboat": "5d906c384c1334e6",
	"gen:prismatic:medium:768:6000:s3:role:brawler": "db51ed0a8d862903",
	"gen:prismatic:medium:781:9500:s3:role:escort": "b2b342dc994b4d89",
	"gen:prismatic:large:794:13000:s3:role:sniper": "c3b3663fafac7c19",
	"gen:prismatic:large:807:16500:s3:role:hauler": "bbea8f1993b12946",
}


# --- the role ops on a plain stack of decks -------------------------------------------------------------

## A gun deck (8 wide, or 2 x `gun_half`) needing 2 columns for its gun, a bridge (16), a core (20) and an engine room (12),
## centred on x = -0.5, in a shell 1 cell thick.
func _bands(gun_half := 4) -> Array:
	return [
		{"kind": "gun", "x0": -gun_half, "x1": gun_half - 1, "y0": 1, "y1": 4, "need": 2},
		{"kind": "bridge", "x0": -8, "x1": 7, "y0": 6, "y1": 11},
		{"kind": "core", "x0": -10, "x1": 9, "y0": 13, "y1": 18},
		{"kind": "engine", "x0": -6, "x1": 5, "y0": 20, "y1": 22},
	]


## make() of the decks with `role_ops` and the style's `ops`: {poly, cells, errors}.
func _make(role_ops: Array, ops := [], opts := {}, seed_value := 7, gun_half := 4) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var h := Hullgen.make({"hull": {"ops": ops, "role_ops": role_ops}}, _bands(gun_half), 1, 24, rng, opts)
	var r := Hullgen.raster(h["outline"])
	return {"poly": h["poly"], "cells": r["cells"], "errors": r["errors"]}


## [first x, last x] of the cells of row y (shaped ones too); [] for an empty row.
func _row(cells: Dictionary, y: int) -> Array:
	var xs: Array = []
	for c in cells:
		if c.y == y:
			xs.append(c.x)
	if xs.is_empty():
		return []
	xs.sort()
	return [xs[0], xs[xs.size() - 1]]


## The runs of cells of row y: how many separate pieces the row is.
func _runs(cells: Dictionary, y: int) -> int:
	var xs: Array = []
	for c in cells:
		if c.y == y:
			xs.append(c.x)
	xs.sort()
	var n := 0
	for i in xs.size():
		n += int(i == 0 or xs[i] != xs[i - 1] + 1)
	return n


func _top(cells: Dictionary) -> int:
	var y := 1 << 20
	for c in cells:
		y = mini(y, c.y)
	return y


func _clean(m: Dictionary, what: String) -> void:
	eq(m["errors"], [], what + ": every cell is a shape of shapes.json")
	for c in m["cells"]:
		if not m["cells"][c].is_empty():
			eq(str(m["cells"][c]["shape"]), "tri", "%s: the cell %s is a 45 degree slope" % [what, str(c)])


func test_fins_sweep_out_of_the_stern_corners() -> void:
	var plain := _make([])
	var m := _make([{"op": "fins", "depth": [2, 2]}])
	_clean(m, "fins")
	eq(_row(plain["cells"], 23), [-7, 6], "the plain stern row")
	eq(_row(m["cells"], 23), [-9, 8], "the fins widen the stern row by their depth on each side")
	eq(_row(m["cells"], 21), _row(plain["cells"], 21), "and leave the rows above them")
	check(not m["cells"][Vector2i(8, 23)].is_empty() and not m["cells"][Vector2i(-9, 23)].is_empty(), "their leading edges are slopes")


func test_a_jaw_juts_a_clamp_tooth_forward_of_each_bow_corner() -> void:
	var m := _make([{"op": "jaw", "depth": [2, 2], "w": 1}], [], {}, 7, 7)
	_clean(m, "jaw")
	eq(_top(m["cells"]), -2, "the teeth reach two rows past the bow")
	eq(_runs(m["cells"], -1), 2, "two teeth, apart")
	check(m["cells"].has(Vector2i(-8, -2)) and m["cells"].has(Vector2i(7, -2)), "each on its corner")
	check(not m["cells"].has(Vector2i(0, -1)), "the middle of the bow stays back for the guns")
	eq(_make([{"op": "jaw", "depth": [2, 2], "w": 1}])["cells"].size(), _make([])["cells"].size(), "no jaw over the columns a narrow gun deck's gun and door need")


func test_horns_rise_from_the_shoulders_beside_the_gun_deck() -> void:
	var m := _make([{"op": "horns", "w": [3, 3], "reach": [1, 1], "gap": 1}])
	_clean(m, "horns")
	eq(_top(m["cells"]), -1, "the horns reach a row past the bow")
	eq(_runs(m["cells"], 2), 3, "beside the gun deck a row is three pieces: a horn, the deck, a horn")
	check(m["cells"].has(Vector2i(7, 0)) and m["cells"].has(Vector2i(-8, 0)), "a horn each side")
	check(not m["cells"].has(Vector2i(5, 2)) and not m["cells"].has(Vector2i(-6, 2)), "a notch between each horn and the gun deck")
	eq(_make([{"op": "horns", "w": [3, 3], "reach": [1, 1], "gap": 4}])["cells"].size(), _make([])["cells"].size(), "no horns where a step leaves no room for them")


func test_an_island_stands_on_one_flank_away_from_the_turret_rows() -> void:
	var plain := _make([])
	for side in ["right", "left"]:
		var m := _make([{"op": "island", "w": [2, 2], "len": [4, 4], "side": side}])
		_clean(m, "island")
		var added: Array = m["cells"].keys().filter(func(c): return not plain["cells"].has(c))
		check(added.size() >= 6, "%s: the island adds cells (%d)" % [side, added.size()])
		check(added.all(func(c): return (c.x > 0) == (side == "right")), side + ": all on that flank")
		var kept := _make([{"op": "island", "w": [2, 2], "len": [4, 4], "side": side}], [], {"avoid": [[6, 11]]})
		var moved: Array = kept["cells"].keys().filter(func(c): return not plain["cells"].has(c))
		check(not moved.is_empty() and moved.all(func(c): return c.y <= 4 or c.y >= 13), side + ": it keeps a row clear of the turret rows")


func test_racks_line_both_flanks_at_the_same_rows() -> void:
	var plain := _make([])
	var m := _make([{"op": "racks", "count": [3, 3], "h": 2, "gap": 2, "depth": 1}])
	_clean(m, "racks")
	var added: Array = m["cells"].keys().filter(func(c): return not plain["cells"].has(c))
	eq(added.size(), 3 * 2 * 2, "three teeth two rows tall on each flank")
	check(added.all(func(c): return m["cells"].has(Vector2i(-1 - c.x, c.y))), "each mirrored on the other flank")


func test_steps_make_a_ziggurat_of_the_bow() -> void:
	var m := _make([{"op": "steps", "at": "tip", "n": [2, 2], "a": 1, "b": 2, "bevel": 1}], [], {}, 7, 7)
	_clean(m, "steps")
	var w := func(y): return int(_row(m["cells"], y)[1]) - int(_row(m["cells"], y)[0]) + 1
	check(w.call(0) < w.call(1) and w.call(1) < w.call(2), "each step down the bow is wider (%d, %d, %d)" % [w.call(0), w.call(1), w.call(2)])
	eq([w.call(0), w.call(1), w.call(4)], [8, 12, 16], "two steps two columns each side, the gun deck below them as wide as before")
	var deep := _make([{"op": "steps", "at": "tip", "n": [3, 3], "a": 2, "b": 2, "bevel": 0}], [], {}, 7, 7)
	eq(_row(deep["cells"], 2), _row(_make([], [], {}, 7, 7)["cells"], 2), "a step that would reach the deck behind is left out (the gun deck's flank is 5 rows)")
	eq(_make([{"op": "steps", "at": "tip", "n": [2, 2], "a": 1, "b": 2, "bevel": 0}])["cells"].size(), _make([])["cells"].size(), "no step into the floor a narrow gun deck's gun and door need")
	check(m["cells"].values().any(func(s): return not s.is_empty()), "the steps are bevelled")


func test_the_style_ops_leave_the_corners_a_role_made() -> void:
	var bevel := [{"op": "chamfer", "at": "tip", "kind": ["45"], "n": [3, 3]}, {"op": "wedge", "at": "bow", "slope": ["45"], "chance": 1.0}]
	var style_only := _make([], bevel, {}, 7, 7)
	check(not style_only["cells"].has(Vector2i(-8, 1)), "the style alone bevels the bow corner")
	var m := _make([{"op": "jaw", "depth": [2, 2], "w": 1}], bevel, {}, 7, 7)
	check(m["cells"].has(Vector2i(-8, -2)) and m["cells"].has(Vector2i(7, -2)), "after a jaw the style's tip bevel finds no corner of it")
	var wedge := [{"op": "wedge", "at": "bow", "slope": ["45"], "chance": 1.0}]
	eq(_row(_make([{"op": "keep", "at": "bow"}], wedge)["cells"], 4), _row(_make([])["cells"], 4), "a kept step is not filled by the style's wedge")
	check(_row(_make([], wedge)["cells"], 4) != _row(_make([])["cells"], 4), "(which it fills without the keep)")
	var spiky := [{"op": "spikes", "count": [6, 6], "depth": 1}]
	var horns := _make([{"op": "horns", "w": [3, 3], "reach": [1, 1], "gap": 1}], spiky)
	check(not horns["cells"].has(Vector2i(10, 0)) and not horns["cells"].has(Vector2i(-11, 0)), "no spike on a horn")


func test_role_ops_are_deterministic_and_off_for_a_rammer_and_the_plain_hull() -> void:
	for role in NEW_ROLES:
		var ops: Array = Hullgen.look_of(role)["hull"]["ops"]
		var a := _make(ops, [], {}, 31)
		eq(a["poly"], _make(ops, [], {}, 31)["poly"], role + ": the same seed draws the same hull")
		_clean(a, role)
		eq(_make(ops, [], {"ram": true})["poly"], _make([], [], {"ram": true})["poly"], role + ": a rammer keeps its ram bow")
		eq(_make(ops, [], {"level": 0})["poly"], _make([], [], {"level": 0})["poly"], role + ": the plain fallback keeps its bevels")


# --- the look laid over a style -------------------------------------------------------------------

func test_with_look_lays_the_role_over_the_style_and_leaves_the_tables() -> void:
	var f: Dictionary = Shipgen.tables()["factions"]["kett"]
	var before := JSON.stringify(f)
	check(is_same(Hullgen.with_look(f, "gunboat"), f), "an old role keeps the style's hull: the same table")
	check(is_same(Hullgen.with_look(f, ""), f), "and so does no role")
	check(is_same(Hullgen.with_look(f, "boarder", true), f), "and a rammer: its ram bow is the style's")
	for role in NEW_ROLES:
		var look: Dictionary = Hullgen.look_of(role)["hull"]
		var h: Dictionary = Hullgen.with_look(f, role)["hull"]
		eq(h["prow"], look["prow"], role + ": the role's prow")
		eq(h["tail"], look["tail"], role + ": and tail")
		for k in look["band"]:
			eq(h["width"][k], look["band"][k], "%s: the role's %s width" % [role, k])
		eq(h["band"], f["hull"]["band"], role + ": the style's band still caps the decks")
		check(int(h["jitter_w"][1]) <= int(look["jitter_w"]) and int(h["jitter_c"]) <= int(look["jitter_c"]), role + ": its jitter caps the style's")
		eq(h["role_ops"], look["ops"], role + ": its ops")
		for k in ["ops", "asym"]:
			eq(h[k], f["hull"][k], "%s: the style keeps its %s" % [role, k])
	eq(JSON.stringify(f), before, "the tables stay as they were")
	var concord: Dictionary = Hullgen.with_look(Shipgen.tables()["factions"]["concord"], "skirmisher")["hull"]
	eq([concord["jitter_w"], concord["jitter_c"], concord["asym"]], [[0, 0], 0, false], "a symmetric people stays symmetric")
	var hollow: Dictionary = Hullgen.with_look(Shipgen.tables()["factions"]["hollow"], "flanker")["hull"]
	eq([hollow["jitter_w"], hollow["jitter_c"], hollow["asym"]], [[1, 2], 1, true], "a lopsided one stays lopsided as far as the role allows")


func test_old_roles_build_the_same_ships_as_before() -> void:
	for spec in OLD_SHIPS:
		var ship = Shipgen.from_spec(spec)
		check(ship != null, spec + " builds")
		if ship == null:
			continue
		eq(JSON.stringify([ship.to_dict(), ship.name, ship.crew_plan, ship.get_meta("ai"), ship.get_meta("shipgen")]).sha256_text().substr(0, 16), OLD_SHIPS[spec], spec + ": the same ship")
	eq(OLD_SHIPS.size(), 60, "60 old-role ships")


# --- the ships -------------------------------------------------------------------------------------

## The hull rows of `ship` (its tiles, shaped ones too), top to bottom: [[first x, last x, runs], ...] and the middle x.
func _rows(ship) -> Dictionary:
	var by_y := {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c in ship.grid.tiles:
		if not by_y.has(c.y):
			by_y[c.y] = []
		by_y[c.y].append(c.x)
		lo = lo.min(c)
		hi = hi.max(c)
	var rows: Array = []
	for y in range(lo.y, hi.y + 1):
		var xs: Array = by_y.get(y, [])
		xs.sort()
		var runs := 0
		for i in xs.size():
			runs += int(i == 0 or xs[i] != xs[i - 1] + 1)
		rows.append([xs[0], xs[xs.size() - 1], runs] if not xs.is_empty() else [0, -1, 0])
	return {"rows": rows, "mid": (lo.x + hi.x) / 2.0, "w": hi.x - lo.x + 1}


func _w(r: Array) -> int:
	return int(r[1]) - int(r[0]) + 1


## Does `ship` show the mark of `role`'s silhouette?
func _looks_like(role: String, ship) -> bool:
	var d := _rows(ship)
	var rows: Array = d["rows"]
	var n := rows.size()
	var widest := 0
	for r in rows:
		widest = maxi(widest, _w(r))
	match role:
		"skirmisher":  # a narrow nose, swept fins past the stern: the last row is the two fin tips
			return _w(rows[0]) * 2 <= widest and int(rows[n - 1][2]) == 2
		"boarder":  # two clamp teeth ahead of a blunt bow as wide as the ship
			return int(rows[0][2]) == 2 and rows.slice(0, 6).any(func(r): return int(r[2]) == 1 and _w(r) * 10 >= widest * 6)
		"flanker":  # horns beside the gun deck: rows of three pieces
			return rows.slice(0, n / 2).filter(func(r): return int(r[2]) == 3).size() >= 3
		"carrier":  # a wide deck with an island on one side: nearly as wide as long, the island's rows off the others' middle
			var centres: Array = rows.map(func(r): return float(r[0]) + float(r[1]))
			return float(d["w"]) >= 0.85 * n and centres.max() - centres.min() >= 3.0
		"siege":  # a long narrow neck lined with racks: rows wider than both neighbours
			var teeth := 0
			for i in range(1, n - 1):
				teeth += int(_w(rows[i]) > _w(rows[i - 1]) and _w(rows[i]) > _w(rows[i + 1]))
			var neck := widest
			for i in n / 4:
				neck = mini(neck, _w(rows[i]))
			return teeth >= 2 and neck * 10 <= widest * 7
		"bulwark":  # stepped ends: square steps down the bow and the stern
			var steps := 0
			for i in range(1, mini(8, n)):
				steps += int(_w(rows[i]) >= _w(rows[i - 1]) + 4)
			return steps >= 2
	return false


func test_every_role_ship_looks_like_its_role() -> void:
	var fly := {"skirmisher": ["clans", "kett"], "carrier": ["lumen", "sporeling"], "boarder": ["rustfangs", "kett"], "flanker": ["lumen", "hollow"], "siege": ["concord", "hollow"], "bulwark": ["wardens", "grundl"]}
	for role in fly:
		for faction in fly[role]:
			for size in ["medium", "large"]:
				var good := 0
				for k in 10:
					var ship = Shipgen.build(faction, size, 900 + k * 37, 120.0 + 25.0 * k, {"role": role, "stage": 4})
					good += int(ship != null and _looks_like(role, ship))
				check(good >= 8, "%s %s %s: %d of 10 ships look like one" % [faction, size, role, good])
	var plain := 0
	for role in NEW_ROLES:
		for k in 10:
			plain += int(_looks_like(role, Shipgen.build("concord", "medium", 900 + k * 37, 150.0, {"role": "escort", "stage": 4})))
	check(plain <= 6, "an old role's ship rarely looks like a new one (%d of 60)" % plain)


## Every faction (and race) builds each new role it flies at every size class it fits, 20 seeds each, as well as its old roles
## at the same seeds (tool_enemy_gallery.gd rates()): a ship every time the old roles give one, on the first roll no less
## often over all the factions of a size, and per faction and size never more than 15 points less often (20 seeds a role is
## noisy). The table: tool_enemy_gallery.gd rates=1.
func test_the_new_roles_build_as_well_as_the_old_ones() -> void:
	var pooled := {}
	for size in Gallery.SIZES:
		pooled[size] = {"new": {"n": 0, "first": 0, "made": 0}, "old": {"n": 0, "first": 0, "made": 0}}
	for faction in Shipgen.factions():
		var sp := Gallery.split_roles(faction)  # (a faction with no new role, a rare one, has nothing to compare)
		for size in Gallery.SIZES:
			var a := Gallery.rates(faction, size, sp[0], 20)
			var b := Gallery.rates(faction, size, sp[1], 20)
			for k in ["n", "first", "made"]:
				pooled[size]["new"][k] += a[k]
				pooled[size]["old"][k] += b[k]
			if a["n"] == 0 or b["n"] == 0:
				continue
			check(Gallery._pct(a, "made") >= Gallery._pct(b, "made"), "%s %s: the new roles are built %.0f%% of the time, the old %.0f%%" % [faction, size, Gallery._pct(a, "made"), Gallery._pct(b, "made")])
			check(Gallery._pct(a, "first") >= Gallery._pct(b, "first") - 15.0, "%s %s: the new roles on the first roll %.0f%%, the old %.0f%%" % [faction, size, Gallery._pct(a, "first"), Gallery._pct(b, "first")])
	for size in Gallery.SIZES:
		var a: Dictionary = pooled[size]["new"]
		var b: Dictionary = pooled[size]["old"]
		check(Gallery._pct(a, "first") >= Gallery._pct(b, "first"), "%s, every faction: the new roles on the first roll %.1f%% of %d, the old %.1f%% of %d" % [size, Gallery._pct(a, "first"), a["n"], Gallery._pct(b, "first"), b["n"]])
		check(Gallery._pct(a, "made") >= Gallery._pct(b, "made"), "%s, every faction: the new roles built %.1f%%, the old %.1f%%" % [size, Gallery._pct(a, "made"), Gallery._pct(b, "made")])


## A carrier or a boarder whose hull takes no drone bay flies as a gunboat (shipgen build()): its look's hull loses that no more
## often than the style's own hull (the look switched off) does, 20 seeds of each faction that flies it and size.
func test_a_role_look_costs_no_drone_bay() -> void:
	var kept := {"look": 0, "plain": 0}
	var n := 0
	for pair in [["carrier", "lumen"], ["carrier", "wardens"], ["boarder", "rustfangs"], ["boarder", "clans"]]:
		for size in Gallery.SIZES:
			if not Gallery.fits(pair[0], size):
				continue
			var look := Gallery.rates(pair[1], size, [pair[0]], 20)
			var saved: Dictionary = Hullgen.looks()
			Hullgen._looks = {"roles": {}}
			var plain := Gallery.rates(pair[1], size, [pair[0]], 20)
			Hullgen._looks = saved
			kept["look"] += look["kept"]
			kept["plain"] += plain["kept"]
			n += look["n"]
	check(kept["look"] >= kept["plain"], "the role's look keeps its bay %d of %d times, the style's hull %d" % [kept["look"], n, kept["plain"]])


func test_a_role_ship_is_the_same_for_the_same_seed() -> void:
	for role in NEW_ROLES:
		var a = Shipgen.from_spec("gen:wardens:large:77:20000:s4:role:" + role)
		var b = Shipgen.from_spec("gen:wardens:large:77:20000:s4:role:" + role)
		check(a != null and b != null, role + " builds")
		if a != null and b != null:
			eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), role + ": the same ship")


func test_a_role_ship_wears_its_role_s_dressing() -> void:
	var kinds := {}
	for role in NEW_ROLES:
		for e in Hullgen.look_of(role)["dressing"]:
			kinds[str(e["kind"])] = role
	eq(kinds.size(), 6, "a dressing kind of its own for each role")
	for kind in kinds:
		var role: String = kinds[kind]
		for faction in ["wardens", "kett"]:
			var ship = Shipgen.build(faction, "large", 51, 200.0, {"role": role, "stage": 4})
			var plan: Array = Dressing.plan(ship, ship.get_meta("style")["dressing"])
			var mine: Array = plan.filter(func(p): return p["kind"] == kind)
			check(mine.size() >= 2, "%s %s wears %s (%d)" % [faction, role, kind, mine.size()])
			if Dressing.PAIRED.has(kind):
				var mid := float(_rows(ship)["mid"]) + 0.5
				eq(mine.size(), 2, "%s: one %s each side" % [role, kind])
				check(mine.size() == 2 and (mine[0]["at"].x < mid) != (mine[1]["at"].x < mid), "%s: on both sides" % kind)
			eq(Dressing.plan(ship, ship.get_meta("style")["dressing"]), plan, role + ": the same pieces every time")
	var old = Shipgen.build("kett", "large", 51, 200.0, {"role": "gunboat", "stage": 4})
	var plan_old: Array = Dressing.plan(old, old.get_meta("style")["dressing"])
	check(plan_old.all(func(p): return not kinds.has(p["kind"])), "an old role wears only its livery's dressing")
	old.remove_meta("shipgen")  # a ship from a design file has no role: it plans as before
	eq(Dressing.plan(old, old.get_meta("style")["dressing"]), plan_old, "a ship with no role plans its livery as before")
