extends "res://tests/base_test.gd"
## The art registry (scripts/view/visuals.gd): art when a file exists, the placeholder when not,
## and the state overlay. Drawing goes to a recording stand-in for a canvas.

const Visuals = preload("res://scripts/view/visuals.gd")
const Components = preload("res://scripts/ship/components.gd")
const ART_TEST_DIR := "user://art_test"


## Records the draw calls Visuals makes.
class FakeCanvas extends RefCounted:
	var calls: Array = []

	func draw_rect(rect, color, filled := true, width := -1.0) -> void:
		calls.append({"op": "rect", "rect": rect, "color": color, "filled": filled})

	func draw_colored_polygon(points, color) -> void:
		calls.append({"op": "polygon", "color": color})

	func draw_line(from, to, color, width := -1.0) -> void:
		calls.append({"op": "line", "color": color})

	func draw_circle(pos, radius, color) -> void:
		calls.append({"op": "circle", "color": color})

	func draw_string(font, pos, text, align := 0, width := -1.0, size := 16, color := Color.WHITE) -> void:
		calls.append({"op": "text", "text": text, "color": color})

	func draw_string_outline(font, pos, text, align := 0, width := -1.0, size := 16, outline := 1, color := Color.WHITE) -> void:
		calls.append({"op": "outline"})

	func draw_set_transform(pos, rot, scale) -> void:
		calls.append({"op": "transform", "pos": pos, "rot": rot})

	func draw_texture_rect(tex, rect, tile, modulate := Color.WHITE) -> void:
		calls.append({"op": "texture", "rect": rect, "modulate": modulate})

	func count(op: String) -> int:
		return calls.filter(func(c): return c["op"] == op).size()

	func texts() -> Array:
		return calls.filter(func(c): return c["op"] == "text").map(func(c): return c["text"])


func _def(id: String) -> Dictionary:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c.def(id)


func _draw(def: Dictionary, inst := {}, opts := {}) -> FakeCanvas:
	var canvas := FakeCanvas.new()
	Visuals.draw_component(canvas, Rect2(100, 100, 128, 64), def, inst, 32.0, opts)
	return canvas


func test_without_art_the_placeholder_is_drawn() -> void:
	Visuals.clear_cache()
	eq(Visuals.art_dir, "res://art/components", "art lives in res://art/components")
	check(Visuals.texture_for("engine_mk1") == null, "no art file for engine_mk1")
	var canvas := _draw(_def("engine_mk1"))
	eq(canvas.count("texture"), 0, "no texture")
	check(canvas.count("rect") >= 2, "a filled body and an outline")
	check("E1" in canvas.texts(), "labelled E1: %s" % [canvas.texts()])
	var first: Dictionary = canvas.calls[0]
	eq(first["rect"], Rect2(102, 102, 124, 60), "the body is the footprint less 2 px")
	eq(first["color"], Color(_def("engine_mk1")["color"]), "in the part's colour")


func test_art_is_drawn_rotated_when_the_file_exists() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_TEST_DIR))
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	eq(img.save_png(ART_TEST_DIR + "/engine_mk1.png"), OK, "test art written")
	var saved_dir := Visuals.art_dir
	Visuals.art_dir = ART_TEST_DIR
	Visuals.clear_cache()
	var tex := Visuals.texture_for("engine_mk1")
	check(tex != null, "the art is found")
	if tex != null:
		eq(tex.get_size(), Vector2(128, 64), "at its own size")
	check(Visuals.texture_for("reactor_mk1") == null, "other parts still have none")
	var canvas := _draw(_def("engine_mk1"), {"rot": 0})
	eq(canvas.count("texture"), 1, "texture drawn")
	eq(canvas.texts(), [], "and no placeholder label")
	var t: Dictionary = canvas.calls[1]
	eq(t["rect"], Rect2(-64, -32, 128, 64), "centred on the origin at footprint size (4x2 cells of 32)")
	eq(canvas.calls[0]["rot"], 0.0, "facing up at rot 0")
	eq(canvas.calls[0]["pos"], Vector2(164, 132), "about the centre of the rect")
	var turned := _draw(_def("engine_mk1"), {"rot": 1})
	eq(turned.calls[0]["rot"], PI / 2.0, "a quarter turn clockwise at rot 1")
	var last: Dictionary = turned.calls.filter(func(c): return c["op"] == "transform").back()
	eq(last["rot"], 0.0, "the transform is reset afterwards")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_TEST_DIR + "/engine_mk1.png"))
	Visuals.art_dir = saved_dir
	Visuals.clear_cache()
	check(Visuals.texture_for("engine_mk1") == null, "back to the placeholder")


func test_marks_follow_the_state() -> void:
	var def := _def("engine_mk1")  # hp 6, limit 100
	var m := Visuals.marks(def, {})
	eq([m["status"], m["show_heat"], m["show_hp"]], ["ok", false, false], "a ghost shows nothing")
	m = Visuals.marks(def, {"heat": 30.0, "hp": 6, "status": "ok"})
	check(not m["show_heat"], "30% is not above 30%")
	m = Visuals.marks(def, {"heat": 31.0, "hp": 5, "status": "malfunction"})
	check(m["show_heat"] and m["show_hp"], "31% heat and 5 of 6 hp show")
	eq([m["status"], m["hp"], m["max_hp"]], ["malfunction", 5, 6], "status and hp")
	m = Visuals.marks(def, {"heat": 250.0})
	eq(m["heat"], 1.0, "heat is clamped to 1")


func test_the_overlay_adds_marks() -> void:
	var def := _def("engine_mk1")
	var plain := _draw(def, {"hp": 6, "heat": 0.0, "status": "ok"})
	var hot := _draw(def, {"hp": 6, "heat": 60.0, "status": "ok"})
	eq(hot.count("rect"), plain.count("rect") + 2, "a heat bar: its back and its fill")
	var hurt := _draw(def, {"hp": 4, "heat": 0.0, "status": "ok"})
	eq(hurt.count("rect"), plain.count("rect") + 6, "six hp pips")
	var over := _draw(def, {"hp": 6, "heat": 100.0, "status": "overheated"})
	check("!" in over.texts(), "an overheated part gets a !")
	var mal := _draw(def, {"hp": 6, "heat": 0.0, "status": "malfunction"})
	check("⚙" in mal.texts() or "M" in mal.texts(), "a malfunctioning part gets a gear or M")
	var off := _draw(def, {"hp": 0, "heat": 0.0, "status": "disabled"})
	eq(off.calls[0]["color"], Visuals.GREY, "a disabled part is grey")
	check(not ("!" in off.texts()), "and has no marks of its own")


func test_each_line_has_its_accent() -> void:
	var scrap := _draw(_def("engine_scrap_mk1"))
	var std := _draw(_def("engine_mk1"))
	var neon := _draw(_def("engine_neon_mk1"))
	eq(scrap.count("polygon"), 1, "scrap: a hazard-stripe corner")
	eq(scrap.count("line"), 2, "with its stripes")
	eq(std.count("polygon") + neon.count("polygon"), 0, "no corner for the others")
	var bright := neon.calls.filter(func(c): return c["op"] == "rect" and not c["filled"] and c["color"] == Visuals.NEON_ACCENT)
	eq(bright.size(), 1, "neon: a bright outline")
	eq(std.calls.filter(func(c): return c["op"] == "rect" and c["color"] == Visuals.NEON_ACCENT).size(), 0, "standard has none")


func test_unpowered_consumers_are_marked_and_ghosts_fade() -> void:
	var def := _def("engine_mk1")
	var off := _draw(def, {"status": "ok"}, {"powered": false})
	check(off.count("circle") == 1 or "⚡" in off.texts(), "a no-power mark")
	eq(_draw(_def("reactor_mk1"), {}, {"powered": false}).count("circle"), 0, "a producer is never marked")
	var ghost := _draw(def, {}, {"alpha": 0.5})
	eq(ghost.calls[0]["color"].a, 0.5, "the ghost is see-through")


func test_labels() -> void:
	eq(Visuals.label_of({"name": "Reactor Mk1"}), "R1", "Mk names")
	eq(Visuals.label_of({"name": "Oxygen Generator"}), "OG", "two words")
	eq(Visuals.label_of({"name": "Kickjet"}), "Ki", "one word")
	eq(Visuals.label_of({}), "?", "no name")
