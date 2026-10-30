extends "res://tests/base_test.gd"
## The art registry (scripts/view/visuals.gd): art when a file exists, the placeholder when not,
## which animation the art shows in which state, and the state overlay. Drawing goes to a recording
## stand-in for a canvas. The art comes from tests/fixtures/art (a part "probe" with every state).

const Visuals = preload("res://scripts/view/visuals.gd")
const Art = preload("res://scripts/view/art.gd")
const Components = preload("res://scripts/ship/components.gd")
const FIXTURES := "res://tests/fixtures/art"
const EMPTY := "res://tests/fixtures/no_such_folder"
const PROBE := {"id": "probe", "size": [1, 1], "power": -1, "hp": 4}  ## a consumer: 4 hp, frames below
## The frames of the probe sheet: on 0-1 (4 fps), off 2, charge 3-5, fire 6, damaged 7-8, disabled 9, malfunction 10, overheated 11.


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

	func draw_texture_rect_region(tex, rect, src, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
		calls.append({"op": "texture", "tex": tex, "rect": rect, "src": src, "modulate": modulate})

	func draw_set_transform_matrix(xf) -> void:
		calls.append({"op": "matrix", "xf": xf})

	func count(op: String) -> int:
		return calls.filter(func(c): return c["op"] == op).size()

	func texts() -> Array:
		return calls.filter(func(c): return c["op"] == "text").map(func(c): return c["text"])


func _def(id: String) -> Dictionary:
	var c := Components.new()
	c.load_defs("res://data/components.json")
	return c.def(id)


## Draw `def` with no art anywhere: the placeholder and the overlay.
func _draw(def: Dictionary, inst := {}, opts := {}) -> FakeCanvas:
	_use(EMPTY)
	var canvas := FakeCanvas.new()
	Visuals.draw_component(canvas, Rect2(100, 100, 128, 64), def, inst, 32.0, opts)
	_done()
	return canvas


func _use(root: String) -> void:
	Art.root = root
	Art.tier_fallback = true
	Art.clear_cache()


func _done() -> void:
	_use(Art.DEFAULT_ROOT)


## Draw `def` with art from `root`.
func _art_draw(root: String, def: Dictionary, inst := {}, opts := {}, rect := Rect2(100, 100, 32, 32)) -> FakeCanvas:
	_use(root)
	var canvas := FakeCanvas.new()
	Visuals.draw_component(canvas, rect, def, inst, 32.0, opts)
	_done()
	return canvas


func test_without_art_the_placeholder_is_drawn() -> void:
	_use(EMPTY)
	check(Art.component("engine_mk1") == null, "no art file for engine_mk1")
	var canvas := _draw(_def("engine_mk1"))
	eq(canvas.count("texture"), 0, "no texture")
	check(canvas.count("rect") >= 2, "a filled body and an outline")
	check("C1" in canvas.texts(), "labelled C1 (Concord Thruster Mk1): %s" % [canvas.texts()])
	var first: Dictionary = canvas.calls[0]
	eq(first["rect"], Rect2(102, 102, 124, 60), "the body is the footprint less 2 px")
	eq(first["color"], Color(_def("engine_mk1")["color"]), "in the part's colour")
	_done()


func test_art_is_drawn_rotated_when_the_file_exists() -> void:
	_use(FIXTURES)
	var def := {"id": "bare", "size": [4, 2], "power": 0}  # a PNG with no JSON: stretched to the footprint
	var canvas := FakeCanvas.new()
	Visuals.draw_component(canvas, Rect2(100, 100, 128, 64), def, {"rot": 0}, 32.0)
	eq(canvas.count("texture"), 1, "texture drawn")
	eq(canvas.texts(), [], "and no placeholder label")
	var t: Dictionary = canvas.calls.filter(func(c): return c["op"] == "texture")[0]
	eq(t["rect"], Rect2(-64, -32, 128, 64), "centred on the origin at footprint size (4x2 cells of 32)")
	eq(t["src"], Rect2(0, 0, 8, 4), "the whole image")
	eq(canvas.calls[0]["xf"].get_rotation(), 0.0, "facing up at rot 0")
	eq(canvas.calls[0]["xf"].origin, Vector2(164, 132), "about the centre of the rect")
	var turned := FakeCanvas.new()
	Visuals.draw_component(turned, Rect2(100, 100, 64, 128), def, {"rot": 1}, 32.0)
	check(is_equal_approx(turned.calls[0]["xf"].get_rotation(), PI / 2.0), "a quarter turn clockwise at rot 1")
	eq(turned.calls.filter(func(c): return c["op"] == "matrix").back()["xf"], Transform2D.IDENTITY, "the transform is reset afterwards")
	check(Art.component("reactor_mk1") == null, "other parts still have none")
	_done()


func test_a_json_sheet_is_drawn_at_16_source_px_per_cell() -> void:
	var canvas := _art_draw(FIXTURES, {"id": "plain", "size": [2, 1], "power": 0}, {}, {}, Rect2(0, 0, 64, 32))
	var t: Dictionary = canvas.calls.filter(func(c): return c["op"] == "texture")[0]
	eq(t["rect"], Rect2(-32, -16, 4, 4), "the 2x2 source frame at 2 px per source px, at the footprint's top-left")


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


# --- which animation the art shows -------------------------------------------------------------

func _state(def: Dictionary, inst: Dictionary, opts := {}, sheet_id := "probe") -> Dictionary:
	_use(FIXTURES)
	var out := Visuals.anim_state(Art.component(sheet_id), def, inst, opts)
	_done()
	return out


func test_on_loops_with_time_and_off_when_a_consumer_has_no_power() -> void:
	var s := _state(PROBE, {"hp": 4}, {"time": 0.0, "charge": 0.0})
	eq(s["anim"], "charge", "a powered weapon part shows its charge bar")
	var plain := {"id": "plain", "size": [1, 1], "power": -1, "hp": 4}
	eq([_state(plain, {}, {"time": 0.0}, "plain")["frame"], _state(plain, {}, {"time": 5.0}, "plain")["frame"]], [0, 0], "plain: on is one frame")
	var off := _state(plain, {}, {"powered": false}, "plain")
	eq([off["anim"], off["frame"], off["glow"]], ["off", 1, ""], "no power: the off frame, no glow")
	var producer := {"id": "plain", "size": [1, 1], "power": 4, "hp": 4}
	eq(_state(producer, {}, {"powered": false}, "plain")["anim"], "on", "a producer is never off")


func test_a_weapon_shows_charge_by_fraction_and_fire_for_a_moment() -> void:
	for pair in [[0.0, 3], [0.5, 4], [1.0, 5]]:
		eq(_state(PROBE, {"hp": 4}, {"charge": pair[0]})["frame"], pair[1], "charge %s" % pair[0])
	eq(_state(PROBE, {"hp": 4}, {})["frame"], 5, "ready when the arena says nothing")
	var fired := _state(PROBE, {"hp": 4}, {"charge": 0.1, "fired_ago": 0.10})
	eq([fired["anim"], fired["frame"]], ["fire", 6], "fire inside the window")
	eq(_state(PROBE, {"hp": 4}, {"charge": 0.1, "fired_ago": Visuals.FIRE_WINDOW + 0.01})["anim"], "charge", "back to charging after it")


func test_damage_states_use_the_art_or_the_generic_overlays() -> void:
	var plain := {"id": "plain", "size": [1, 1], "power": -1, "hp": 4}
	var hurt := _state(plain, {"hp": 1}, {}, "plain")
	check(hurt["sparks"] and not hurt["smoke"], "under half hp with no damaged animation: sparks")
	check(not _state(plain, {"hp": 2}, {}, "plain")["sparks"], "exactly half hp is not damaged")
	var probe_hurt := _state(PROBE, {"hp": 1}, {"time": 0.3}, "probe")
	eq(probe_hurt["anim"], "charge", "a weapon keeps its charge bar")
	check(probe_hurt["sparks"], "and gets the sparks overlay")
	var non_weapon := {"id": "probe", "size": [1, 1], "power": -1, "hp": 4}
	# the probe is a weapon sheet, so use a sheet without a charge animation but with damaged: build one in memory
	var sheet := _memory_sheet({"on": [0, 1, 0], "off": [1, 1, 0], "damaged": [2, 2, 4], "disabled": [4, 1, 0]})
	var d := Visuals.anim_state(sheet, non_weapon, {"hp": 1}, {"time": 0.3})
	eq([d["anim"], d["frame"], d["sparks"]], ["damaged", 3, false], "the damaged animation replaces the sparks")
	var dis := Visuals.anim_state(sheet, non_weapon, {"hp": 0, "status": "disabled"}, {})
	eq([dis["anim"], dis["frame"], dis["dim"], dis["smoke"], dis["glow"]], ["disabled", 4, false, false, ""], "disabled animation")
	var dis_plain := _state(plain, {"hp": 0, "status": "disabled"}, {}, "plain")
	eq([dis_plain["anim"], dis_plain["dim"], dis_plain["smoke"]], ["off", true, true], "no disabled animation: dim, off frame and smoke")


func test_malfunction_and_overheating() -> void:
	var plain := {"id": "plain", "size": [1, 1], "power": -1, "hp": 4}
	var on_frames := 0
	var off_frames := 0
	for i in 100:
		var s := _state(plain, {"hp": 4, "status": "malfunction"}, {"time": i * 0.05}, "plain")
		if s["anim"] == "on":
			on_frames += 1
		elif s["anim"] == "off":
			off_frames += 1
	check(on_frames > 20 and off_frames > 20, "it flickers between on and off (%d / %d)" % [on_frames, off_frames])
	eq(_state(PROBE, {"hp": 4, "status": "malfunction"}, {})["anim"], "malfunction", "its own malfunction animation wins")
	var hot := _state(plain, {"hp": 4, "status": "overheated"}, {}, "plain")
	eq([hot["anim"], hot["heat"]], ["on", true], "no overheated animation: the heat pulse over the normal frame")
	var own := _state(PROBE, {"hp": 4, "status": "overheated"}, {})
	eq([own["anim"], own["heat"], own["frame"]], ["overheated", false, 11], "the art's own overheated animation")
	var cool := _state(plain, {"hp": 4}, {}, "plain")
	check(not cool["heat"] and not cool["sparks"] and not cool["smoke"], "a healthy part has no overlays")


func test_glow_follows_the_animation_and_goes_to_the_glow_layer() -> void:
	var s := _state(PROBE, {"hp": 4}, {"charge": 0.5, "time": 0.0})
	eq([s["glow"], s["glow_frame"]], ["charge", 3], "glow frame by the same charge fraction (glow charge starts at 2)")
	var fired := _state(PROBE, {"hp": 4}, {"fired_ago": 0.0})
	eq([fired["glow"], fired["glow_frame"]], ["fire", 5], "glow fire frame")
	eq(_state(PROBE, {"hp": 4}, {"powered": false})["glow"], "", "no glow without power")
	eq(_state(PROBE, {"hp": 0, "status": "disabled"}, {})["glow"], "", "none when disabled")
	var quads := []
	var canvas := _art_draw(FIXTURES, PROBE, {"hp": 4}, {"glow_out": quads})
	eq(quads.size(), 1, "the glow quad goes to the additive layer")
	eq(canvas.count("texture"), 1, "so only the sprite is drawn in place")
	check(quads[0]["xf"] is Transform2D and quads[0]["rect"] is Rect2, "with its transform and rect")
	var inline := _art_draw(FIXTURES, PROBE, {"hp": 4})
	eq(inline.count("texture"), 2, "with no layer the glow is drawn over the sprite")


func test_the_part_turns_by_its_rotation_plus_the_art_orientation() -> void:
	var c0 := _art_draw(FIXTURES, PROBE, {"rot": 0, "hp": 4})
	check(is_equal_approx(c0.calls[0]["xf"].get_rotation(), -PI / 2.0), "orientation_rot 3 on a part at rot 0: three quarter turns")
	var c1 := _art_draw(FIXTURES, PROBE, {"rot": 1, "hp": 4})
	check(is_zero_approx(c1.calls[0]["xf"].get_rotation()), "rot 1 + 3 is a full turn")


func test_a_ghost_with_no_state_draws_the_normal_frame() -> void:
	var s := _state(PROBE, {}, {"alpha": 0.5})
	eq(s["anim"], "charge", "ghost: healthy, powered")
	check(not s["sparks"] and not s["dim"], "no damage overlays")
	var canvas := _art_draw(FIXTURES, PROBE, {}, {"alpha": 0.5})
	eq(canvas.calls.filter(func(c): return c["op"] == "texture")[0]["modulate"].a, 0.5, "see-through")


func test_sparks_and_smoke_are_drawn_in_code_without_fx_art() -> void:
	var plain := {"id": "plain", "size": [1, 1], "power": -1, "hp": 4}
	var sparks := _art_draw(FIXTURES, plain, {"hp": 1, "uid": 3}, {"time": 1.0})
	check(sparks.count("rect") >= 3, "specks for the sparks (%d rects)" % sparks.count("rect"))
	var smoke := _art_draw(FIXTURES, plain, {"hp": 0, "status": "disabled", "uid": 3}, {"time": 1.0})
	eq(smoke.count("circle"), 3, "three puffs of smoke")
	_use(FIXTURES)
	var with_art := FakeCanvas.new()
	Visuals.draw_sparks(with_art, Rect2(0, 0, 32, 32), 0.5, 1, 32.0)
	eq(with_art.count("texture"), 3, "fx/sparks art is used when it exists")
	_done()


## A sheet with the given animations, built in memory (frames of 1 px).
func _memory_sheet(anims: Dictionary) -> RefCounted:
	var img := Image.create(8, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return Art.SpriteSheet.from_dict({"frame": [1, 1], "cells": [1, 1], "anims": anims}, img)
