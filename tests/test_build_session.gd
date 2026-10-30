extends "res://tests/base_test.gd"

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const MID := Vector2i(5, 5)


func _session(scrap := 100, copper := 10) -> BuildSession:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(15, 15), defs)
	g.fill_circle_hull(7.0)
	var inv := Inventory.new()
	inv.load_dict({"scrap": scrap, "copper": copper})
	return BuildSession.new(g, inv)


func _put(id: String, cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append({"cell": c, "to": id})
	return out


func _row(x0: int, x1: int, y: int) -> Array:
	var out := []
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y))
	return out


# --- Inventory ---

func test_inventory_spend_is_all_or_nothing() -> void:
	var inv := Inventory.new()
	inv.add("scrap", 5)
	inv.add("copper", 1)
	check(inv.can_afford({"scrap": 5, "copper": 1}), "exact amount is affordable")
	check(not inv.spend({"scrap": 3, "copper": 2}), "short on copper")
	eq(inv.to_dict(), {"scrap": 5, "copper": 1}, "a failed spend takes nothing")
	check(inv.spend({"scrap": 3, "copper": 1}), "affordable spend")
	eq(inv.count("scrap"), 2, "scrap spent")
	eq(inv.count("copper"), 0, "copper spent")
	check(not inv.counts.has("copper"), "zero counts are not stored")
	check(inv.spend({}), "free costs always pass")


func test_inventory_refund_and_missing() -> void:
	var inv := Inventory.new()
	inv.add("scrap", 2)
	eq(inv.missing({"scrap": 5, "copper": 1}), {"scrap": 3, "copper": 1}, "how many short of each")
	eq(inv.missing({"scrap": 2}), {}, "nothing missing when affordable")
	inv.refund({"scrap": 3, "copper": 1})
	eq(inv.to_dict(), {"scrap": 5, "copper": 1}, "refund adds back")
	inv.add("scrap", -99)
	eq(inv.count("scrap"), 0, "a count never goes below zero")
	eq(inv.count("unobtainium"), 0, "unknown ids count as zero")


func test_inventory_dict_round_trip() -> void:
	var inv := Inventory.new()
	eq(inv.load_dict({"scrap": 400.0, "copper": 30, "gone": 0}), "", "floats from JSON load")
	eq(inv.to_dict(), {"scrap": 400, "copper": 30}, "ints, zeros dropped")
	check(inv.load_dict({"scrap": -1}) != "", "negative counts refused")
	check(inv.load_dict({"scrap": "lots"}) != "", "non-numbers refused")
	eq(inv.to_dict(), {"scrap": 400, "copper": 30}, "failed loads change nothing")


func test_start_data_loads() -> void:
	var inv := Inventory.new()
	eq(inv.load_dict(BuildSession.start_cargo()), "", "start.json cargo is valid")
	check(inv.count("scrap") > 0, "starts with scrap")


# --- Cell helpers ---

func test_line_locks_to_the_larger_axis() -> void:
	eq(BuildSession.line_cells(Vector2i(2, 2), Vector2i(6, 4)), _row(2, 6, 2), "horizontal wins")
	eq(BuildSession.line_cells(Vector2i(2, 2), Vector2i(3, 6)).size(), 5, "vertical wins")
	eq(BuildSession.line_cells(Vector2i(2, 2), Vector2i(3, 6))[4], Vector2i(2, 6), "stays on the start column")
	eq(BuildSession.line_cells(Vector2i(6, 2), Vector2i(3, 2)), [Vector2i(6, 2), Vector2i(5, 2), Vector2i(4, 2), Vector2i(3, 2)],
		"runs backwards from the start")
	eq(BuildSession.line_cells(Vector2i(2, 2), Vector2i(4, 4)), _row(2, 4, 2), "a tie goes horizontal")
	eq(BuildSession.line_cells(MID, MID), [MID], "a click is one cell")


func test_rect_cells_and_outline() -> void:
	eq(BuildSession.rect_cells(Vector2i(2, 2), Vector2i(4, 3)).size(), 6, "3x2 filled")
	eq(BuildSession.rect_cells(Vector2i(4, 3), Vector2i(2, 2)).size(), 6, "corner order does not matter")
	eq(BuildSession.rect_cells(Vector2i(2, 2), Vector2i(4, 4), true).size(), 8, "3x3 outline has 8 cells")
	check(not BuildSession.rect_cells(Vector2i(2, 2), Vector2i(4, 4), true).has(Vector2i(3, 3)), "no centre in the outline")
	eq(BuildSession.rect_cells(Vector2i(2, 2), Vector2i(5, 3), true).size(), 8, "a 2-high rect is all outline")


func test_trace_cells_has_no_gaps() -> void:
	var cells := BuildSession.trace_cells(Vector2i(0, 0), Vector2i(6, 2))
	eq(cells[0], Vector2i(0, 0), "starts at a")
	eq(cells[-1], Vector2i(6, 2), "ends at b")
	for i in range(1, cells.size()):
		check(absi(cells[i].x - cells[i - 1].x) <= 1 and absi(cells[i].y - cells[i - 1].y) <= 1, "step %d is adjacent" % i)
	eq(BuildSession.trace_cells(MID, MID), [MID], "same cell")


# --- Apply, undo, redo ---

func test_a_stroke_is_one_undo_step() -> void:
	var s := _session()
	var r := s.apply(_put("floor", _row(3, 7, 5)))
	eq(r, {"applied": 5, "skipped": 0, "reason": ""}, "all five placed")
	eq(s.undo_stack.size(), 1, "one step for the whole stroke")
	check(s.undo(), "undo")
	eq(s.grid.tiles.size(), 0, "the whole stroke is gone")
	check(not s.undo(), "nothing left to undo")


func test_undo_restores_tiles_and_cargo_and_redo_reapplies() -> void:
	var s := _session()
	s.apply(_put("floor", _row(3, 7, 5)))
	var tiles := s.grid.tiles.duplicate()
	var cargo := s.inventory.to_dict()
	eq(cargo, {"scrap": 95, "copper": 10}, "five floors cost five scrap")
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	eq(s.inventory.count("scrap"), 95 + 2 - 4, "walls replace floors: refund 1 each, pay 2 each")
	check(s.undo(), "undo the walls")
	eq(s.grid.tiles, tiles, "floors are back")
	eq(s.inventory.to_dict(), cargo, "cargo is back exactly")
	check(s.undo(), "undo the floors")
	eq(s.inventory.to_dict(), {"scrap": 100, "copper": 10}, "all the scrap is back")
	check(s.redo(), "redo the floors")
	eq(s.grid.tiles, tiles, "floors re-applied")
	eq(s.inventory.to_dict(), cargo, "and paid for again")
	check(s.redo(), "redo the walls")
	eq(s.grid.get_tile(Vector2i(4, 5)), "wall", "wall is back")
	eq(s.inventory.count("scrap"), 93, "cargo matches the first run")
	check(not s.redo(), "nothing more to redo")


func test_a_new_apply_clears_redo() -> void:
	var s := _session()
	s.apply(_put("floor", [MID]))
	s.undo()
	eq(s.redo_stack.size(), 1, "one step to redo")
	s.apply(_put("floor", [Vector2i(6, 5)]))
	eq(s.redo_stack.size(), 0, "redo cleared by a new action")
	check(not s.redo(), "cannot redo")
	s.undo()
	s.apply(_put("floor", [Vector2i(6, 5)]))
	s.undo()
	s.apply(_put("wall", [Vector2i(0, 0)]))  # skipped: outside the hull, so not an action
	eq(s.redo_stack.size(), 1, "an action that changes nothing keeps redo")


func test_history_is_capped() -> void:
	var s := _session(1000)
	for i in 205:
		s.apply(_put("floor" if i % 2 == 0 else "wall", [MID]))
	eq(s.undo_stack.size(), BuildSession.MAX_HISTORY, "oldest steps dropped")
	var n := 0
	while s.undo():
		n += 1
	eq(n, BuildSession.MAX_HISTORY, "exactly that many undos")


func test_undo_bypasses_placement_rules() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	s.apply(_put("door", [MID]))
	s.apply([{"cell": MID, "to": ""}])
	s.apply([{"cell": Vector2i(4, 5), "to": ""}])
	check(s.undo(), "undo wall removal")
	check(s.undo(), "undo door removal")
	eq(s.grid.get_tile(MID), "door", "door restored")
	check(s.undo(), "undo door placement")
	check(s.undo(), "undo walls")
	eq(s.grid.tiles.size(), 0, "empty again")
	eq(s.inventory.to_dict(), {"scrap": 100, "copper": 10}, "cargo back to the start")


func test_undo_brings_back_an_open_door_open() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	s.apply(_put("door", [MID]))
	s.grid.set_door_open(MID, true)
	s.apply([{"cell": MID, "to": ""}])
	check(not s.grid.is_door_open(MID), "removed door has no state")
	s.undo()
	check(s.grid.is_door_open(MID), "undo restores it open")
	s.redo()
	s.undo()
	s.undo()
	s.redo()
	check(not s.grid.is_door_open(MID), "a door placed again starts closed")


func test_removing_refunds_everything() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	s.apply(_put("door", [MID]))
	eq(s.inventory.to_dict(), {"scrap": 100 - 4 - 3, "copper": 9}, "paid in materials")
	var r := s.apply([{"cell": MID, "to": ""}])
	eq(r["applied"], 1, "door removed")
	eq(s.inventory.to_dict(), {"scrap": 100 - 4, "copper": 10}, "door refunded 100%")
	r = s.apply([{"cell": MID, "to": ""}])
	eq(r, {"applied": 0, "skipped": 1, "reason": "nothing to remove"}, "empty cell")
	eq(s.undo_stack.size(), 3, "a skipped action leaves no step")


func test_unaffordable_placement_is_skipped() -> void:
	var s := _session(2, 0)
	var r := s.apply(_put("floor", _row(3, 6, 5)))
	eq(r, {"applied": 2, "skipped": 2, "reason": "not enough scrap"}, "two floors fit, two do not")
	eq(s.grid.tiles.size(), 2, "only the paid ones are built")
	eq(s.inventory.count("scrap"), 0, "all scrap spent")
	eq(s.undo_stack.size(), 1, "one step for what was applied")


func test_door_needs_copper_too() -> void:
	var s := _session(50, 0)
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	var r := s.apply(_put("door", [MID]))
	eq(r["reason"], "not enough copper", "copper is the missing material")
	eq(s.inventory.count("scrap"), 46, "nothing was charged")
	eq(s.grid.get_tile(MID), "", "no door built")


func test_replacing_refunds_the_old_tile() -> void:
	var s := _session(3, 0)
	s.apply(_put("wall", [MID]))
	eq(s.inventory.count("scrap"), 1, "wall paid")
	var r := s.apply(_put("floor", [MID]))
	eq(r["applied"], 1, "floor replaces the wall")
	eq(s.inventory.count("scrap"), 2, "wall refunded (2), floor paid (1)")
	s.apply(_put("wall", [MID]))
	eq(s.inventory.count("scrap"), 1, "and back to a wall")
	# only affordable because the old tile is refunded first
	var t := _session(0, 0)
	t.grid.force_tile(MID, "wall")
	r = t.apply(_put("floor", [MID]))
	eq(r["applied"], 1, "a refund can pay for the replacement")
	eq(t.inventory.count("scrap"), 1, "net +1")
	r = t.apply(_put("wall", [MID]))
	eq(r["applied"], 1, "1 in hand plus the floor's 1 refund pays for a wall")
	eq(t.inventory.count("scrap"), 0, "all spent")


func test_replace_that_cannot_be_paid_changes_nothing() -> void:
	var s := _session(0, 0)
	s.grid.force_tile(MID, "floor")
	var r := s.apply(_put("door", [MID]))
	check(r["applied"] == 0, "door refused")
	eq(s.grid.get_tile(MID), "floor", "floor still there")
	eq(s.inventory.to_dict(), {}, "cargo untouched")


# --- Planning a drag ---

func test_room_has_walls_on_the_border_and_floor_inside() -> void:
	var s := _session()
	var pl := s.plan(BuildSession.Mode.RECT, "wall", false, Vector2i(3, 3), Vector2i(7, 6))
	eq(pl["error"], "", "no error")
	var r := s.apply(pl["changes"])
	eq(r["applied"], 20, "5x4 room")
	for c in BuildSession.rect_cells(Vector2i(3, 3), Vector2i(7, 6), true):
		eq(s.grid.get_tile(c), "wall", "wall on the border at %s" % str(c))
	for y in range(4, 6):
		for x in range(4, 7):
			eq(s.grid.get_tile(Vector2i(x, y)), "floor", "floor inside at %d,%d" % [x, y])
	eq(s.grid.tiles.size(), 20, "nothing else built")
	eq(s.inventory.count("scrap"), 100 - 14 * 2 - 6, "14 walls and 6 floors")
	check(s.undo(), "undo")
	eq(s.grid.tiles.size(), 0, "the whole room is one undo step")


func test_rect_of_floor_fills_and_doors_are_refused() -> void:
	var s := _session()
	var pl := s.plan(BuildSession.Mode.RECT, "floor", false, Vector2i(3, 3), Vector2i(5, 4))
	eq(pl["changes"].size(), 6, "floor fills the rectangle")
	pl = s.plan(BuildSession.Mode.RECT, "door", false, Vector2i(3, 3), Vector2i(5, 4))
	eq(pl["error"], "drag doors one at a time", "doors refused in a rectangle")
	eq(pl["changes"], [], "and nothing is planned")
	pl = s.plan(BuildSession.Mode.LINE, "door", false, Vector2i(3, 3), Vector2i(5, 3))
	eq(pl["error"], "", "a line of doors is left to the placement rules")


func test_line_plan_locks_to_its_axis() -> void:
	var s := _session()
	var pl := s.plan(BuildSession.Mode.LINE, "wall", false, Vector2i(3, 5), Vector2i(8, 6))
	eq(pl["changes"].size(), 6, "six cells along the row")
	for ch in pl["changes"]:
		eq(ch["cell"].y, 5, "stays on the start row")
	pl = s.plan(BuildSession.Mode.LINE, "wall", false, Vector2i(5, 3), Vector2i(6, 8))
	for ch in pl["changes"]:
		eq(ch["cell"].x, 5, "stays on the start column")


func test_paint_plan_drops_repeats_and_outside_cells() -> void:
	var s := _session()
	var path := [Vector2i(3, 5), Vector2i(4, 5), Vector2i(3, 5), Vector2i(-4, 5)]
	var pl := s.plan(BuildSession.Mode.PAINT, "floor", false, path[0], path[-1], path)
	eq(pl["changes"].size(), 2, "each in-grid cell once")
	pl = s.plan(BuildSession.Mode.PAINT, "floor", false, Vector2i(-4, 5), Vector2i(-4, 5), [Vector2i(-4, 5)])
	eq(pl["error"], "outside the hull", "a click off the grid says why")


func test_removing_a_rectangle_takes_doors_before_their_walls() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	s.apply(_put("door", [MID]))
	var pl := s.plan(BuildSession.Mode.RECT, "", true, Vector2i(3, 4), Vector2i(7, 6))
	var r := s.apply(pl["changes"])
	eq(r, {"applied": 3, "skipped": 12, "reason": "nothing to remove"}, "wall, door, wall all go")
	eq(s.grid.tiles.size(), 0, "empty")


func test_preview_changes_nothing() -> void:
	var s := _session(2, 0)
	var before := s.grid.to_dict()
	var out := s.preview(_put("floor", _row(3, 6, 5)))
	eq(out.size(), 4, "one entry per change")
	eq(out[0]["reason"], "", "first fits")
	eq(out[1]["reason"], "", "second fits")
	eq(out[2]["reason"], "not enough scrap", "third is too dear")
	eq(s.grid.to_dict(), before, "grid untouched")
	eq(s.inventory.to_dict(), {"scrap": 2}, "cargo untouched")
	eq(s.undo_stack.size(), 0, "no history")


# --- Save and load ---

func test_save_load_round_trip_with_doors_and_cargo() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5), Vector2i(6, 5)]))
	s.apply(_put("door", [MID]))
	s.apply(_put("floor", [Vector2i(5, 6)]))
	s.grid.set_door_open(MID, true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	eq(d["version"], 2, "saved as version 2")
	var t := _session(1, 1)
	t.apply(_put("floor", [MID]))
	eq(t.load_dict(d), "", "loads")
	eq(t.grid.tiles, s.grid.tiles, "same tiles")
	check(t.grid.is_door_open(MID), "door is still open")
	eq(t.inventory.to_dict(), s.inventory.to_dict(), "same cargo")
	eq(t.undo_stack.size(), 0, "history cleared")
	check(not t.undo(), "nothing to undo after a load")


func test_version_1_save_loads_with_starting_cargo() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5)]))
	var old: Dictionary = s.grid.to_dict()
	old["version"] = 1
	old.erase("doors_open")
	var t := _session(1, 1)
	eq(t.load_dict(JSON.parse_string(JSON.stringify(old))), "", "version 1 loads")
	eq(t.grid.tiles, s.grid.tiles, "tiles loaded")
	var start := Inventory.new()
	start.load_dict(BuildSession.start_cargo())
	eq(t.inventory.to_dict(), start.to_dict(), "cargo comes from start.json")


func test_bad_saves_change_nothing() -> void:
	var s := _session()
	s.apply(_put("wall", [Vector2i(4, 5)]))
	var tiles := s.grid.tiles.duplicate()
	var cargo := s.inventory.to_dict()
	eq(s.load_dict({"version": 99}), "unsupported ship version", "future version refused")
	check(s.load_dict({"version": 2, "size": [3, 3], "hull": [], "tiles": []}) != "", "version 2 needs cargo")
	var bad := s.to_dict()
	bad["cargo"] = {"scrap": -5}
	check(s.load_dict(bad) != "", "bad cargo refused")
	bad = s.to_dict()
	bad["tiles"] = [[1, 1, "teleporter"]]
	check(s.load_dict(bad) != "", "bad tiles refused")
	eq(s.grid.tiles, tiles, "tiles untouched")
	eq(s.inventory.to_dict(), cargo, "cargo untouched")
	eq(s.undo_stack.size(), 1, "history untouched")
