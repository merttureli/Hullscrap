extends "res://tests/base_test.gd"
## Crew drawn from the layered art (scripts/crew/person_drawer.gd): legs follow the movement, the
## torso, arms, item and head follow the aim, the item follows the job, and a missing species falls
## back to the placeholder. Art from tests/fixtures/art (5x5 frames, pivot 2,2).

const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Art = preload("res://scripts/view/art.gd")
const FIXTURES := "res://tests/fixtures/art"


## Records the draw calls.
class FakeCanvas extends RefCounted:
	var calls: Array = []

	func draw_set_transform(pos, rot, scale) -> void:
		calls.append({"op": "transform", "pos": pos, "rot": rot, "scale": scale})

	func draw_texture_rect_region(tex, rect, src, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
		calls.append({"op": "texture", "tex": tex, "rect": rect, "src": src, "modulate": modulate})

	func draw_colored_polygon(points, color, uv := PackedVector2Array(), texture = null) -> void:
		calls.append({"op": "polygon"})

	func draw_circle(pos, radius, color, filled := true, width := -1.0, antialiased := false) -> void:
		calls.append({"op": "circle"})

	func draw_line(from, to, color, width := -1.0, antialiased := false) -> void:
		calls.append({"op": "line"})

	func draw_polyline(points, color, width := -1.0, antialiased := false) -> void:
		calls.append({"op": "polyline"})

	func draw_arc(center, radius, a0, a1, points, color, width := -1.0, antialiased := false) -> void:
		calls.append({"op": "arc"})

	func count(op: String) -> int:
		return calls.filter(func(c): return c["op"] == op).size()


func _use(root: String) -> void:
	Art.root = root
	Art.tier_fallback = true
	Art.clear_cache()


func _done() -> void:
	_use(Art.DEFAULT_ROOT)


func _layer(plan: Array, name: String) -> Dictionary:
	for l in plan:
		if l["layer"] == name:
			return l
	return {}


func _crew(job := {}, player := false) -> CrewMember:
	var m := CrewMember.new("Test", Vector2(5, 5))
	m.job = job
	m.is_player = player
	return m


func test_the_legs_follow_the_movement_and_the_rest_follows_the_aim() -> void:
	_use(FIXTURES)
	var sheet = Art.crew("human")
	var plan := PersonDrawer.plan(sheet, {"move": 0.0, "aim": PI, "moving": true, "phase": 0.0})
	eq(_layer(plan, "legs")["angle"], PI / 2.0, "legs: facing right is a quarter turn from up")
	for name in ["torso", "arms", "head"]:
		eq(_layer(plan, name)["angle"], PI + PI / 2.0, "%s: aimed left" % name)
	eq(plan.map(func(l): return l["layer"]), ["legs", "torso", "arms", "head"], "back to front, no item")
	_done()


func test_the_walk_cycle_follows_the_distance_and_stands_when_idle() -> void:
	_use(FIXTURES)
	var sheet = Art.crew("human")
	var frames := []
	for i in 6:
		frames.append(_layer(PersonDrawer.plan(sheet, {"moving": true, "phase": TAU * (i + 0.5) / 6.0}), "legs")["frame"])
	eq(frames, [0, 1, 2, 3, 4, 5], "six walk frames over one cycle")
	eq(_layer(PersonDrawer.plan(sheet, {"moving": true, "phase": TAU * 3.0 + 0.1}), "legs")["frame"], 0, "the phase wraps")
	eq(_layer(PersonDrawer.plan(sheet, {"moving": false, "phase": 1.0}), "legs")["frame"], 6, "the stand frame when idle")
	eq(_layer(PersonDrawer.plan(sheet, {"moving": true, "down": true, "phase": 1.0}), "legs")["frame"], 6, "and when down")
	_done()


func test_the_item_follows_the_job() -> void:
	var fire := _crew({"type": "extinguish", "cell": Vector2i(3, 3)})
	eq(PersonDrawer.item_for(fire, 0.0), "extinguisher", "extinguishing")
	eq(PersonDrawer.item_for(_crew({"type": "repair_component", "cells": [Vector2i(3, 3)]}), 0.0), "wrench", "repairing a part")
	eq(PersonDrawer.item_for(_crew({"type": "repair_breach", "cell": Vector2i(3, 3)}), 0.0), "wrench", "sealing a breach")
	eq(PersonDrawer.item_for(_crew({"type": "man_station", "cells": [Vector2i(3, 3)]}), 0.0), "", "manning a station: empty hands")
	eq(PersonDrawer.item_for(_crew(), 0.0), "", "idle: nothing")
	eq(PersonDrawer.item_for(_crew({}, true), 0.0), "pistol", "the player with no job: a pistol")
	eq(PersonDrawer.item_for(_crew({"type": "extinguish", "cell": Vector2i(3, 3)}, true), 0.0), "extinguisher", "the player at a fire")
	var hand := {"type": "repair_component", "hand": true, "t": 10.0}
	eq(PersonDrawer.item_for(_crew(hand, true), 10.2), "wrench", "the player holding E")
	eq(PersonDrawer.item_for(_crew(hand, true), 11.0), "pistol", "a stale hand job is let go")
	var down := _crew({"type": "extinguish", "cell": Vector2i(3, 3)})
	down.hurt(1000.0)
	eq(PersonDrawer.item_for(down, 0.0), "", "nobody holds anything while down")


func test_working_means_arrived_at_a_tool_job() -> void:
	var m := _crew({"type": "repair_component", "cells": [Vector2i(3, 3)]})
	check(PersonDrawer.is_working(m, 0.0), "at the job")
	m.path = [Vector2i(1, 1)]
	check(not PersonDrawer.is_working(m, 0.0), "still walking to it")
	check(not PersonDrawer.is_working(_crew({"type": "man_station"}), 0.0), "a station is not tool work")
	check(PersonDrawer.is_working(_crew({"type": "extinguish", "hand": true, "t": 5.0}, true), 5.1), "the player holding E")
	check(not PersonDrawer.is_working(_crew({"type": "extinguish", "hand": true, "t": 5.0}, true), 6.0), "not after letting go")


func test_the_arm_pose_and_the_item_placement_follow_the_item_class() -> void:
	_use(FIXTURES)
	var sheet = Art.crew("human")
	var pistol := PersonDrawer.plan(sheet, {"item": "pistol", "aim": 0.0})
	eq(_layer(pistol, "arms")["frame"], 1, "pistol arms")
	var it := _layer(pistol, "item")
	eq(it["id"], "pistol", "the item is drawn")
	# pistol mount (2,0), grip (1,3): the item's top-left is at mount - grip = (1,-3) in the body frame, which is -2.5 from the pivot's middle
	eq(it["pos"], Vector2(1, -3) + Vector2(-2.5, -2.5), "grip on the mount")
	eq(pistol.map(func(l): return l["layer"]), ["legs", "torso", "arms", "item", "head"], "the item is between the arms and the head")
	var tool := PersonDrawer.plan(sheet, {"item": "wrench"})
	eq(_layer(tool, "arms")["frame"], 3, "tool arms for a wrench")
	var spray := PersonDrawer.plan(sheet, {"item": "extinguisher"})
	eq(_layer(spray, "item")["id"], "wrench", "no extinguisher art: the wrench stands in")
	eq(_layer(spray, "arms")["frame"], 3, "with the tool arms")
	var none := PersonDrawer.plan(sheet, {"item": "ray_gun"})
	eq(_layer(none, "arms")["frame"], 0, "an item with no art: unarmed")
	check(_layer(none, "item").is_empty(), "and nothing in the hands")
	check(_layer(PersonDrawer.plan(sheet, {"item": "pistol", "down": true}), "item").is_empty(), "nothing while down")
	var jab := PersonDrawer.plan(sheet, {"item": "wrench", "work": true, "t": 0.17})
	check(_layer(jab, "arms")["pos"].y < _layer(tool, "arms")["pos"].y, "the arms jab forward while working")
	eq(_layer(jab, "legs")["pos"], _layer(tool, "legs")["pos"], "the legs stay put")
	_done()


func test_the_head_is_hair_or_a_helmet() -> void:
	_use(FIXTURES)
	var sheet = Art.crew("human")
	eq(_layer(PersonDrawer.plan(sheet, {}), "head")["frame"], 0, "hair")
	eq(_layer(PersonDrawer.plan(sheet, {"helmet": true}), "head")["frame"], 1, "helmet")
	_done()


func test_drawing_shadows_every_layer_and_tints_the_outfit() -> void:
	_use(FIXTURES)
	var canvas := FakeCanvas.new()
	PersonDrawer.draw(canvas, Vector2(100, 100), {"item": "pistol", "aim": 0.0}, {"suit": "#ff0000"}, 32.0)
	eq(canvas.count("texture"), 10, "five layers, each once as shadow and once for real")
	var quads: Array = canvas.calls.filter(func(c): return c["op"] == "texture")
	eq(quads[0]["modulate"], PersonDrawer.SHADOW, "shadows first")
	eq(quads[5]["modulate"], Color.WHITE, "then the layers untinted by modulate")
	var sheet = Art.crew("human")
	check(quads[5]["tex"] == sheet.layers["legs"].tinted(Color("#ff0000")), "legs: the outfit-tinted copy")
	check(quads[0]["tex"] == sheet.layers["legs"].texture, "the shadow: the plain silhouette")
	eq(quads[8]["tex"], Art.item("pistol").texture, "the item is not tinted")
	var shadow_at: Dictionary = canvas.calls.filter(func(c): return c["op"] == "transform")[0]
	eq(shadow_at["pos"], Vector2(102, 102), "the shadow is one source px (2 px) down and right")
	eq(shadow_at["scale"], Vector2(2, 2), "2 px per source px at 32 px cells")
	var down := FakeCanvas.new()
	PersonDrawer.draw(down, Vector2.ZERO, {"down": true}, {}, 32.0)
	eq(down.calls.filter(func(c): return c["op"] == "texture")[-1]["modulate"], PersonDrawer.DOWN_TINT, "darker while down")
	_done()


func test_without_art_the_placeholder_person_is_drawn() -> void:
	_use("res://tests/fixtures/no_such_folder")
	check(PersonDrawer.art_of({"species": "human"}) == null, "no crew art: draw() falls back to the code-drawn person")
	_use(FIXTURES)
	check(PersonDrawer.art_of({"species": "human"}) != null, "with the art it draws the sprite")
	check(PersonDrawer.art_of({"species": "lizard"}) == null, "a species with no art uses the placeholder")
	_done()


func test_job_target_and_aim() -> void:
	var m := _crew({"type": "repair_component", "cells": [Vector2i(8, 4), Vector2i(9, 4)]})
	eq(PersonDrawer.job_target(m), Vector2(9, 4.5), "the middle of the part")
	eq(PersonDrawer.job_target(_crew({"type": "extinguish", "cell": Vector2i(2, 3)})), Vector2(2.5, 3.5), "the burning cell")
	eq(PersonDrawer.job_target(_crew({"type": "rest", "cells": [Vector2i(1, 1)]})), null, "resting aims at nothing")
	eq(PersonDrawer.job_target(_crew()), null, "no job, no target")
	m.pos = Vector2(5, 4.5)
	check(is_zero_approx(PersonDrawer.job_aim(m)), "arrived: look at the part (to the right)")
	m.path = [Vector2i(1, 1)]
	m.facing = Vector2.UP
	check(is_equal_approx(PersonDrawer.job_aim(m), -PI / 2.0), "walking: look the way they go")
	eq(PersonDrawer.job_aim(_crew()), Vector2.DOWN.angle(), "idle: the way they face")


func test_animate_tracks_distance_and_turns_smoothly() -> void:
	var m := _crew()
	var a := PersonDrawer.new_state(m)
	m.pos += Vector2(1, 0)
	m.facing = Vector2.RIGHT
	PersonDrawer.animate(a, m, 0.1, 0.0)
	check(a["moving"], "moved")
	check(absf(a["phase"] - PersonDrawer.STRIDE) < 1e-6, "pi of walk phase per cell")
	check(a["angle"] > 0.0 and a["angle"] < Vector2.DOWN.angle(), "the legs turn toward the movement, not all at once")
	PersonDrawer.animate(a, m, 0.1, 1.0)
	check(not a["moving"], "then standing")
	check(a["aim"] > 0.0 and a["aim"] < 1.0, "the torso turns toward the aim")
