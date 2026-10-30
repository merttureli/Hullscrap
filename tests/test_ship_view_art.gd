extends "res://tests/base_test.gd"
## What a ship in a fight hands its art: a weapon's charge and fire window read from the arena's
## cooldowns (the arena itself is only read), and every part of the starter ships and the pirate
## drawing with the shipped art (and its Mk1 fallbacks) without a script error.

const Arena = preload("res://scripts/combat/arena.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipView = preload("res://scripts/view/ship_view.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const Art = preload("res://scripts/view/art.gd")
const FIXTURE_SHIP := "res://data/ships/%s.json"


class FakeCanvas extends RefCounted:
	var textures := 0

	func draw_texture_rect_region(tex, rect, src, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
		textures += 1

	func draw_set_transform_matrix(xf) -> void:
		pass

	func draw_rect(rect, color, filled := true, width := -1.0) -> void:
		pass

	func draw_colored_polygon(points, color) -> void:
		pass

	func draw_line(from, to, color, width := -1.0) -> void:
		pass

	func draw_circle(pos, radius, color) -> void:
		pass

	func draw_string(font, pos, text, align := 0, width := -1.0, size := 16, color := Color.WHITE) -> void:
		pass

	func draw_string_outline(font, pos, text, align := 0, width := -1.0, size := 16, outline := 1, color := Color.WHITE) -> void:
		pass


func near(got: float, want: float, msg: String, eps := 0.02) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_the_view_reads_a_weapons_charge_and_shots_from_the_cooldown() -> void:
	var arena := Arena.new(1)
	var i := arena.add_ship(Ship.from_design(FIXTURE_SHIP % "starter_courier"), Vector2.ZERO, 0.0)
	var gun := arena.add_mount(i, "test_bolt", Vector2(20.5, 15.5))  # cooldown 0.5 s
	var view := ShipView.new()
	view.bind(arena, i)
	var o: Dictionary = view._weapon_opts(gun)
	eq(o["charge"], 1.0, "ready: a full bar")
	check(o["fired_ago"] > 1000.0, "and no shot yet")
	check(arena.fire(i, gun, Vector2(1000.0, 0.0)), "fire")
	o = view._weapon_opts(gun)
	near(o["charge"], 0.0, "just fired: an empty bar")
	near(o["fired_ago"], 0.0, "just now")
	arena.step(0.25)
	view._clock += 0.25
	o = view._weapon_opts(gun)
	near(o["charge"], 0.5, "half way through the cooldown")
	near(o["fired_ago"], 0.25, "a quarter second ago", 0.001)
	check(o["fired_ago"] > Visuals.FIRE_WINDOW, "outside the fire window")
	arena.step(0.3)
	view._clock += 0.3
	eq(view._weapon_opts(gun)["charge"], 1.0, "ready again")
	var courier: Ship = arena.ships[i].ship
	var non_weapon := -1
	for uid in courier.components.instances:
		if not arena.ships[i].mounts.has(uid):
			non_weapon = uid
	eq(view._weapon_opts(non_weapon), {}, "a part that is not a weapon asks for nothing")
	view.free()


func test_the_view_without_an_arena_asks_for_nothing() -> void:
	var view := ShipView.new()
	view.show_ship(Ship.from_design(FIXTURE_SHIP % "starter_courier"))
	eq(view._weapon_opts(1), {}, "no arena, no weapon state")
	view.free()


func test_every_part_of_every_starter_draws_with_the_shipped_art() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.tier_fallback = true
	Art.clear_cache()
	var with_art := 0
	var total := 0
	for name in ["starter_courier", "starter_rustbucket", "starter_prism", "pirate_raider"]:
		var ship: Ship = Ship.from_design(FIXTURE_SHIP % name)
		for uid in ship.components.instances:
			var inst: Dictionary = ship.components.instances[uid]
			var canvas := FakeCanvas.new()
			for state in [{}, {"hp": 1}, {"hp": 0, "status": "disabled"}, {"status": "malfunction"}, {"status": "overheated", "heat": 90.0}]:
				var merged: Dictionary = inst.duplicate()
				merged.merge(state, true)
				var quads := []
				Visuals.draw_component(canvas, Rect2(0, 0, 128, 64), ship.components.def(inst["id"]), merged, 32.0,
					{"powered": true, "time": 1.3, "charge": 0.4, "fired_ago": 0.05, "glow_out": quads})
			total += 1
			if canvas.textures > 0:
				with_art += 1
	check(total > 30, "parts drawn: %d" % total)
	check(with_art > 10, "and a good few of them from art: %d of %d" % [with_art, total])
