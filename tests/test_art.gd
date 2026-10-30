extends "res://tests/base_test.gd"
## The art loader (scripts/view/art.gd) and the sprite sheet maths (sprite_sheet.gd), on the tiny
## fixtures in tests/fixtures/art and on the art the repo ships in art/.

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const FIXTURES := "res://tests/fixtures/art"


func _use(root: String) -> void:
	Art.root = root
	Art.tier_fallback = true
	Art.clear_cache()


func _done() -> void:
	_use(Art.DEFAULT_ROOT)


func test_a_component_sheet_is_parsed() -> void:
	_use(FIXTURES)
	var s = Art.component("probe")
	check(s != null, "probe loads")
	if s != null:
		eq(s.frame, Vector2i(2, 2), "frame size")
		eq(s.count, 12, "twelve frames in the strip")
		eq(s.cells, Vector2i(1, 1), "cells")
		eq(s.orientation_rot, 3, "orientation_rot")
		eq(s.anims["on"], {"start": 0, "count": 2, "fps": 4.0}, "the on animation")
		eq(s.anims["fire"], {"start": 6, "count": 1, "fps": 0.0}, "the fire animation")
		eq(s.anchors["muzzle"], Vector2(2, 1), "anchor from the frame's top-left")
		check(s.glow != null, "glow layer")
		if s.glow != null:
			eq(s.glow.frame, Vector2i(3, 3), "glow frame")
			eq(s.glow.count, 6, "glow frames")
			eq(s.glow.offset, Vector2(-1, -1), "glow offset")
			eq(s.glow.anims["charge"]["start"], 2, "glow charge animation")
		check(s.texture != null and s.texture.get_size() == Vector2(24, 2), "texture is the whole strip")
	_done()


func test_missing_art_is_null() -> void:
	_use(FIXTURES)
	check(Art.component("nothing_here") == null, "component")
	check(Art.item("nothing_here") == null, "item")
	check(Art.tiles("nothing_here") == null, "tiles")
	check(Art.fx("nothing_here") == null, "fx")
	check(Art.projectile("nothing_here") == null, "projectile")
	check(Art.crew("nobody") == null, "crew")
	_use("res://tests/fixtures/no_such_folder")
	check(Art.component("probe") == null, "an empty root has no art")
	check(Art.crew("human") == null, "and no crew")
	_done()


func test_a_bare_png_is_one_frame_and_the_art_is_cached() -> void:
	_use(FIXTURES)
	var s = Art.component("bare")
	check(s != null, "a PNG with no JSON loads")
	if s != null:
		eq(s.frame, Vector2i(8, 4), "the frame is the whole image")
		eq(s.count, 1, "one frame")
		eq(s.cells, Vector2i.ZERO, "no cells: stretched to the footprint")
		check(s.anims.is_empty() and s.glow == null and not s.has_mask(), "nothing else")
	check(Art.component("bare") == s, "the same sheet the second time")
	Art.clear_cache()
	check(Art.component("bare") != s, "clear_cache forgets it")
	_done()


func test_a_part_without_art_borrows_the_lower_tier() -> void:
	_use(FIXTURES)
	check(Art.component("probe_mk2") == null, "no probe_mk1 here either")
	_use(Art.DEFAULT_ROOT)
	var mk1 = Art.component("engine_mk1")
	check(mk1 != null, "the shipped Engine Mk1 art")
	check(Art.component("engine_mk2") == mk1, "Engine Mk2 uses it until it has its own")
	Art.tier_fallback = false
	Art.clear_cache()
	check(Art.component("engine_mk2") == null, "unless the fallback is off")
	check(Art.component("engine_scrap_mk1") == null, "other lines never borrow")
	_done()


func test_frame_maths() -> void:
	_use(FIXTURES)
	var s = Art.component("probe")
	eq(s.region(0), Rect2(0, 0, 2, 2), "frame 0")
	eq(s.region(5), Rect2(10, 0, 2, 2), "frame 5")
	eq(s.region(99), Rect2(22, 0, 2, 2), "clamped to the last frame")
	eq(s.frame_at("on", 0.0), 0, "on at 0 s")
	eq(s.frame_at("on", 0.3), 1, "on at 0.3 s (4 fps)")
	eq(s.frame_at("on", 0.5), 0, "it loops")
	eq(s.frame_at("off", 9.0), 2, "a one-frame animation holds")
	eq(s.frame_at("nope", 1.0), 0, "an unknown animation is frame 0")
	eq([s.frame_frac("charge", 0.0), s.frame_frac("charge", 0.5), s.frame_frac("charge", 1.0)], [3, 4, 5], "charge by fraction")
	eq(s.frame_frac("charge", 7.0), 5, "fractions clamp")
	eq([s.frame_life("damaged", 0.0), s.frame_life("damaged", 0.49), s.frame_life("damaged", 0.99), s.frame_life("damaged", 1.5)], [7, 7, 8, 8], "played over a life")
	eq([s.frame_once("on", 0.0), s.frame_once("on", 0.3), s.frame_once("on", 5.0)], [0, 1, 1], "played once at its fps, the last frame held")
	eq([s.rot_total(0), s.rot_total(1), s.rot_total(2)], [3, 0, 1], "orientation_rot adds quarter turns")
	_done()


func test_the_colour_mask_tints_only_where_it_is_white() -> void:
	_use(FIXTURES)
	var torso = Art.crew("human")
	check(torso != null and torso.has_mask(), "the torso has a mask")
	var red: Texture2D = torso.tinted(Color(1, 0, 0))
	var img := red.get_image()
	var base: Color = torso.image.get_pixel(0, 0)
	var masked: Color = img.get_pixel(0, 0)
	check(absf(masked.r - base.r) < 0.01 and masked.g < 0.01 and masked.b < 0.01, "masked pixel x red: %s" % masked)
	eq(img.get_pixel(1, 1), torso.image.get_pixel(1, 1), "unmasked pixel unchanged")
	check(torso.tinted(Color(1, 0, 0)) == red, "tinted copies are kept")
	check(torso.tinted(Color(0, 1, 0)) != red, "one per colour")
	var plain = Art.component("plain")
	check(plain.tinted(Color.RED) == plain.texture, "no mask: the plain texture")
	_done()


func test_mask4_index() -> void:
	eq(SpriteSheet.mask4(false, false, false, false), 0, "alone")
	eq(SpriteSheet.mask4(true, false, false, false), 1, "N")
	eq(SpriteSheet.mask4(false, true, false, false), 2, "E")
	eq(SpriteSheet.mask4(false, false, true, false), 4, "S")
	eq(SpriteSheet.mask4(false, false, false, true), 8, "W")
	eq(SpriteSheet.mask4(true, true, true, true), 15, "all four")
	eq(SpriteSheet.mask4(false, true, false, true), 10, "a horizontal run")
	eq(SpriteSheet.mask4(true, false, true, false), 5, "a vertical run")


func test_crew_sheet_layers_poses_and_pivot() -> void:
	_use(FIXTURES)
	var c = Art.crew("human")
	check(c != null, "human loads")
	if c != null:
		eq(c.frame, Vector2i(5, 5), "frame from crew.json")
		eq(c.pivot, Vector2(2, 2), "pivot")
		eq(c.layers.keys(), ["legs", "arms", "head"], "layers next to the torso")
		eq(c.layers["legs"].count, 7, "legs frames")
		eq(c.layers["legs"].anims["walk"], {"start": 0, "count": 6, "fps": 8.0}, "walk")
		eq(c.poses["pistol"], {"frame": 1, "mount": Vector2(2, 0)}, "pistol pose")
		eq(c.poses["tool"]["frame"], 3, "tool pose")
		eq(c.poses["unarmed"]["mount"], null, "unarmed has no mount")
		eq(c.layers["head"].named_frames, {"hair": 0, "helmet": 1}, "head frames")
		eq(c.anchors["head"], Vector2(2, 2), "torso anchor")
		eq(c.origin_of_frame(), Vector2(-2.5, -2.5), "frames are laid out about the pivot's middle")
	var pistol = Art.item("pistol")
	eq(pistol.pose, "pistol", "an item names its arm pose")
	eq(pistol.anchors["grip"], Vector2(1, 3), "its grip")
	_done()


func test_every_shipped_sheet_is_consistent() -> void:
	_use(Art.DEFAULT_ROOT)
	var seen := 0
	for kind in ["components", "items", "tiles", "fx", "projectiles"]:
		var dir := "%s/%s" % [Art.DEFAULT_ROOT, kind]
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var id := f.get_basename()
			if not FileAccess.file_exists("%s/%s.png" % [dir, id]) and not JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, f])).has("frame"):
				continue  # a data file next to the art (tiles/shapes.json holds the shape polygons)
			var s = Art._sheet(kind, id)
			check(s != null, "%s/%s has its PNG" % [kind, id])
			if s == null:
				continue
			seen += 1
			for name in s.anims:
				var a: Dictionary = s.anims[name]
				check(a["start"] + a["count"] <= s.count, "%s/%s: animation %s runs past the %d frames" % [kind, id, name, s.count])
			if s.glow != null:
				for name in s.glow.anims:
					var a: Dictionary = s.glow.anims[name]
					check(a["start"] + a["count"] <= s.glow.count, "%s/%s: glow animation %s runs past its %d frames" % [kind, id, name, s.glow.count])
	check(seen >= 10, "found the shipped art (%d sheets)" % seen)
	var laser = Art.component("laser_mk1")
	check(laser != null and laser.has_anim("charge") and laser.has_anim("fire"), "the laser has charge and fire")
	check(Art.crew("human") != null, "the shipped crew loads")
	for item in ["pistol", "rifle", "wrench", "extinguisher"]:
		check(Art.item(item) != null and Art.item(item).anchors.has("grip"), "item %s with a grip" % item)
	_done()
