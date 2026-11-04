extends "res://tests/base_test.gd"
## Body gear drawn from its art (art/gear/, data/boarding.json `looks` `art`): the layers it adds to a human, the
## exosuit's own legs and arms, the flat look kept for rigs the art does not fit, and every item in every pose.

const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Art = preload("res://scripts/view/art.gd")
const Site = preload("res://scripts/board/site.gd")

## item -> the art id its look names (pinned: the data mapping).
const ART_OF := {"basic_armor": "combat_vest", "eva_suit": "eva_suit", "exosuit": "exosuit", "salamander_suit": "salamander_suit", "heat_suit": "heat_suit",
	"rigger_harness": "rigger_harness", "firefighter_coat": "firefighter_coat", "medic_sash": "medic_sash", "jump_pack": "jump_pack", "chitin_plate": "chitin_plate",
	"spore_mantle": "spore_mantle", "prism_cloak": "prism_cloak", "ballast_rig": "ballast_rig", "tank_harness": "tank_harness", "forge_apron": "forge_apron",
	"traders_coat": "traders_coat", "stone_plates": "stone_plates", "scrap_gauntlets": "scrap_gauntlets", "marine_plate": "marine_plate"}
const HAS_HEAD := ["eva_suit", "exosuit", "salamander_suit", "heat_suit", "firefighter_coat", "chitin_plate", "spore_mantle", "prism_cloak", "tank_harness", "marine_plate"]
const HAND := ["basic_armor", "eva_suit", "exosuit", "salamander_suit", "heat_suit"]  ## the hand-made art of the human rig (the rest is generated for every rig: art/_src/sp_wardrobe.py)


## Counts what is drawn.
class Canvas extends RefCounted:
	var textures := 0
	var flat := 0

	func draw_set_transform(_p, _r, _s) -> void:
		pass

	func draw_texture_rect_region(_t, _r, _s, _m := Color.WHITE, _tr := false, _c := true) -> void:
		textures += 1

	func draw_circle(_c, _r, _col, _f := true, _w := -1.0, _a := false) -> void:
		flat += 1

	func draw_arc(_c, _r, _a0, _a1, _n, _col, _w := -1.0, _aa := false) -> void:
		flat += 1

	func draw_rect(_r, _col, _f := true, _w := -1.0) -> void:
		flat += 1

	func draw_colored_polygon(_p, _c, _uv := PackedVector2Array(), _t = null) -> void:
		flat += 1

	func draw_line(_a, _b, _c, _w := -1.0, _aa := false) -> void:
		pass

	func draw_polyline(_p, _c, _w := -1.0, _aa := false) -> void:
		pass


func _real() -> void:
	Art.root = Art.DEFAULT_ROOT
	Art.tier_fallback = true
	Art.clear_cache()


func _names(plan: Array) -> Array:
	return plan.map(func(l): return l["layer"])


func test_the_looks_name_their_art() -> void:
	var looks: Dictionary = Site.config()["looks"]
	for item in ART_OF:
		eq(str(looks[item].get("art", "")), ART_OF[item], "%s wears the %s art" % [item, ART_OF[item]])
	for item in Site.config()["kit"]["bodies"]:
		check(ART_OF.has(str(item)), "%s is covered by the mapping" % item)


func test_every_body_item_resolves_to_art_layers_on_a_human() -> void:
	_real()
	var human = Art.crew("human")
	for item in ART_OF:
		var ge = PersonDrawer.gear_art(human, item)
		check(ge != null and ge.has("body"), "%s has body art" % item)
		var plan := PersonDrawer.plan(human, {"body": item, "aim": 0.0})
		var names := _names(plan)
		check("gear_body" in names, "%s draws its body layer" % item)
		check(names.find("gear_body") > names.find("torso") and names.find("gear_body") < names.find("arms"), "%s sits after the torso, before the arms" % item)
		eq("gear_head" in names, item in HAS_HEAD, "%s: a head layer only when it has one" % item)
		if item in HAS_HEAD:
			eq(names.find("gear_head"), names.find("head") + 1, "%s: its head goes right after the head" % item)
		if item in HAND:
			check(plan.filter(func(l): return l["layer"] == "gear_body")[0]["sheet"].has_mask(), "%s has a colour mask" % item)
	_real()


func test_the_exosuit_wears_its_own_legs_and_arms() -> void:
	_real()
	var human = Art.crew("human")
	var ge = Art.gear("exosuit")
	var walk := PersonDrawer.plan(human, {"body": "exosuit", "moving": true, "phase": 1.0, "item": "rifle"})
	var legs: Dictionary = walk.filter(func(l): return l["layer"] == "legs")[0]
	var arms: Dictionary = walk.filter(func(l): return l["layer"] == "arms")[0]
	check(legs["sheet"] == ge["legs"], "the exosuit's legs replace the legs")
	check(arms["sheet"] == ge["arms"], "and its arms replace the arms")
	eq(arms["frame"], 2, "in the rifle pose")
	var bare := PersonDrawer.plan(human, {"moving": true, "phase": 1.0, "item": "rifle"})
	eq(legs["frame"], bare.filter(func(l): return l["layer"] == "legs")[0]["frame"], "the walk frame is the rig's own")
	var vest := PersonDrawer.plan(human, {"body": "basic_armor", "item": "rifle"})
	check(vest.filter(func(l): return l["layer"] == "arms")[0]["sheet"] == human.layers["arms"], "a vest keeps the human arms")
	_real()


func test_glow_is_a_separate_additive_layer_and_goes_out_when_down() -> void:
	_real()
	var human = Art.crew("human")
	var up := PersonDrawer.plan(human, {"body": "exosuit"})
	check(up.any(func(l): return l.has("glow")), "an exosuit glows")
	check(not PersonDrawer.plan(human, {"body": "exosuit", "down": true}).any(func(l): return l.has("glow")), "not while down")
	check(not PersonDrawer.plan(human, {"body": "basic_armor", "down": false}).any(func(l): return l.has("glow") and l["glow"].frame != Vector2i(33, 33)), "glow frames are cut to the spec's size")
	_real()


func test_the_heat_suit_art_exists_and_loads() -> void:
	_real()
	for f in ["", "_color", "_glow"]:
		check(FileAccess.file_exists("res://art/gear/heat_suit%s.png" % f), "heat_suit%s.png exists" % f)
	check(FileAccess.file_exists("res://art/gear/heat_suit.json"), "and its spec")
	var ge = Art.gear("heat_suit")
	check(ge != null and ge.has("body") and ge.has("head"), "a body and a head layer")
	eq(ge["body"].frame, Vector2i(33, 33), "in the crew frame")
	check(ge["body"].has_mask() and ge["head"].has_mask(), "both with a colour mask")
	check(ge["body"].glow != null and ge["head"].glow != null, "and a glow")
	eq(ge["head"].meta["frame"], 1, "the head is the second frame")
	_real()


func test_gear_fits_the_rigs_with_the_humans_anchors() -> void:
	_real()
	check(Art.gear_fits(Art.crew("human")), "human")
	check(Art.gear_fits(Art.crew("gauntling")), "gauntling has the same anchors")
	for rig in ["basalt", "emberkin", "fenn", "rattler", "brine", "lantern"]:
		check(not Art.gear_fits(Art.crew(rig)), "%s does not fit the hand-made art" % rig)
	check(not Art.gear_fits(null), "no art, no fit")


func test_every_rig_wears_the_gear_drawn_from_its_own_sprites() -> void:
	_real()
	var basalt = Art.crew("basalt")
	for item in ART_OF:
		check(PersonDrawer.gear_art(basalt, item) != null, "%s has art on basalt" % item)
		check(_names(PersonDrawer.plan(basalt, {"body": item})).has("gear_body"), "and draws a gear body layer there")
	var bare := Canvas.new()
	PersonDrawer.draw(bare, Vector2.ZERO, {"species": "basalt"}, {}, 40.0)
	var worn := Canvas.new()
	PersonDrawer.draw(worn, Vector2.ZERO, {"species": "basalt", "body": "exosuit"}, {}, 40.0)
	eq(worn.flat, 0, "no flat shapes: the sprite is drawn")
	check(worn.textures > bare.textures, "more sprites than the bare rig")
	check(PersonDrawer.gear_art(Art.crew("human"), "exosuit") == Art.gear("exosuit"), "the human keeps the hand-made exosuit")


func test_every_item_in_every_pose_draws() -> void:
	_real()
	var poses := [{}, {"moving": true, "phase": 2.0}, {"item": "pistol"}, {"item": "rifle", "moving": true, "phase": 4.0}, {"item": "wrench", "work": true, "t": 0.3},
		{"item": "extinguisher"}, {"item": "quarry_hammer"}, {"down": true}, {"down": true, "item": "pistol"}, {"helmet": true}, {"head": "helmet"}, {"aim": 2.0, "move": -1.0, "moving": true}]
	var n := 0
	for rig in ["human", "gauntling", "basalt", "emberkin", "fenn", "rattler", "brine", "lantern", "wisp"]:
		for item in [""] + ART_OF.keys() + ["not_gear"]:
			for p in poses:
				var pose: Dictionary = p.duplicate()
				pose["species"] = rig
				pose["body"] = item
				var c := Canvas.new()
				PersonDrawer.draw(c, Vector2(50, 50), pose, {"suit": "#33c6d6"}, 40.0)
				n += 1
				check(c.textures > 0 or c.flat > 0, "%s %s %s drew something" % [rig, item, str(p)])
	check(n > 1500, "%d combinations" % n)
	_real()
