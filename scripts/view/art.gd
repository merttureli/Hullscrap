extends RefCounted
## The art loader. Everything under res://art (format: art/README.md) is read once, with
## Image.load_from_file + ImageTexture, so it works without an editor import (headless runs, tests),
## and cached. Each lookup gives a parsed SpriteSheet or null: null means "no art, draw the
## placeholder". Static: `Art.component("laser_mk1")`.

const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const DEFAULT_ROOT := "res://art"
const CREW_LAYERS := ["legs", "torso", "arms", "head"]

## Where the art lives; tests point it at a fixture folder.
static var root := DEFAULT_ROOT
## A part with no art of its own (engine_mk2) borrows the next lower tier's (engine_mk1) until its own lands.
static var tier_fallback := true
static var _cache := {}  # "<root>/<kind>/<name>" -> SpriteSheet, or null when there is none


static func clear_cache() -> void:
	_cache.clear()


## The sheet of system `id` (art/components/<id>.png), or null.
static func component(id: String) -> RefCounted:
	var s = _sheet("components", id)
	if s != null or not tier_fallback:
		return s
	var key := "%s/components-tier/%s" % [root, id]  # the lower-tier answer is kept too, null included
	if not _cache.has(key):
		_cache[key] = _lower_tier(id)
	return _cache[key]


## The art of the highest lower tier of `id` ("engine_mk2" -> "engine_mk1"), or null.
static func _lower_tier(id: String) -> RefCounted:
	var m := RegEx.create_from_string("^(.+)_mk(\\d+)$").search(id)
	if m == null:
		return null
	for tier in range(int(m.get_string(2)) - 1, 0, -1):
		var s = _sheet("components", "%s_mk%d" % [m.get_string(1), tier])
		if s != null:
			return s
	return null


## A hand-held item: art/items/<id>.png.
static func item(id: String) -> RefCounted:
	return _sheet("items", id)


## An ending's illustration: art/endings/<ending id>.png (320x180 frames; a strip is its ambient animation, <id>_glow.png its light).
static func ending(id: String) -> RefCounted:
	return _sheet("endings", id)


## A tile sheet: art/tiles/<name>.png (floor, walls, door, breach, cable).
static func tiles(name: String) -> RefCounted:
	return _sheet("tiles", name)


## An effect: art/fx/<name>.png (fire, smoke, sparks, explosion, muzzle, shield_ripple).
static func fx(name: String) -> RefCounted:
	return _sheet("fx", name)


## A projectile: art/projectiles/<kind>.png (laser, bolt, flak, missile, beam).
static func projectile(kind: String) -> RefCounted:
	return _sheet("projectiles", kind)


## The projectile art of weapon `id` (art/projectiles/<id><suffix>.png) when it has its own, else its kind's (art/projectiles/<kind><suffix>.png), or null.
## `suffix` is "" for the shot itself and "_impact" for what it looks like where it lands.
static func projectile_of(id: String, kind: String, suffix := "") -> RefCounted:
	if id != "":
		var own = projectile(id + suffix)
		if own != null:
			return own
	return projectile(kind + suffix)


## A crew species (art/crew/<species>/): the torso sheet, with `layers` {"legs", "arms", "head"}
## and `poses` (see _poses). Null unless the torso and the legs both exist. crew.json holds the
## shared "frame" and "pivot", the rig "kind" (normal, large, small or floating: PersonDrawer.RIGS) and a "layers" table
## (image, color_mask, anims, frames, anchors each).
static func crew(species: String) -> RefCounted:
	var key := "%s/crew/%s" % [root, species]
	if _cache.has(key):
		return _cache[key]
	var dir := "%s/crew/%s" % [root, species]
	var d := read_json(dir + "/crew.json")
	var table: Dictionary = d.get("layers", d)
	var common := {"frame": d.get("frame"), "pivot": d.get("pivot"), "anchors_origin": d.get("anchors_origin", "topleft"), "kind": d.get("kind", "normal")}
	var parts := {}
	var raw_arms := {}
	for layer in CREW_LAYERS:
		var ld := common.duplicate()
		var own = table.get(layer)
		if own is Dictionary:
			ld.merge(own, true)
		if layer == "arms":
			raw_arms = ld
		var img := load_image("%s/%s" % [dir, str(ld.get("image", layer + ".png"))])
		if img != null:
			var mask := load_image("%s/%s" % [dir, str(ld.get("color_mask", layer + "_color.png"))])
			parts[layer] = SpriteSheet.from_dict(ld, img, mask)
	var out = null
	if parts.has("torso") and parts.has("legs"):
		out = parts["torso"]
		for layer in ["legs", "arms", "head"]:
			if parts.has(layer):
				out.layers[layer] = parts[layer]
		out.poses = _poses(raw_arms, parts.get("arms"))
	_cache[key] = out
	return out


## The art folder to draw a crew member with: `rig` (art/crew/<rig>/) when its art is there, else "human".
static func crew_rig(rig: String) -> String:
	return rig if crew(rig) != null else "human"


## The arm poses from the arms layer table `ld`: {name: {"frame": int, "mount": Vector2 or null}}, the
## mount in source px from the frame's top-left. Either "frames" {pose: index} with "anchors"
## {pose: {"mount": [x, y]}}, or "poses" {pose: {"frame", "mount"}}. "unarmed" always exists.
static func _poses(ld: Dictionary, arms) -> Dictionary:
	var out := {"unarmed": {"frame": 0, "mount": null}}
	var frames: Dictionary = ld.get("frames", {}) if ld.get("frames") is Dictionary else {}
	var detail: Dictionary = ld.get("poses", {}) if ld.get("poses") is Dictionary else {}
	var anchors: Dictionary = ld.get("anchors", {}) if ld.get("anchors") is Dictionary else {}
	var names := {}
	for n in frames:
		names[n] = true
	for n in detail:
		names[n] = true
	for name in names:
		var p: Dictionary = detail[name] if detail.get(name) is Dictionary else {}
		var mount = p.get("mount", anchors[name].get("mount") if anchors.get(name) is Dictionary else null)
		var v = null
		if mount is Array and mount.size() == 2:
			v = Vector2(float(mount[0]), float(mount[1]))
			if str(ld.get("anchors_origin", "topleft")) in ["centre", "center"] and arms != null:
				v += arms.pivot
		out[str(name)] = {"frame": int(p.get("frame", frames.get(name, 0))), "mount": v}
	return out


static func _sheet(kind: String, name: String) -> RefCounted:
	var key := "%s/%s/%s" % [root, kind, name]
	if not _cache.has(key):
		_cache[key] = load_sheet("%s/%s/%s" % [root, kind, name])
	return _cache[key]


## The sheet at `base` (a path without extension: base.png, base.json, the mask and glow named in
## the JSON or defaulting to <base>_color.png and <base>_glow.png). Null when there is no PNG.
static func load_sheet(base: String) -> RefCounted:
	var img := load_image(base + ".png")
	if img == null:
		return null
	var d := read_json(base + ".json")
	var dir := base.get_base_dir()
	var stem := base.get_file()
	var mask := load_image("%s/%s" % [dir, str(d.get("color_mask", stem + "_color.png"))])
	var s = SpriteSheet.from_dict(d, img, mask)
	var g = d.get("glow")
	if g is Dictionary:
		var gimg := load_image("%s/%s" % [dir, str(g.get("image", stem + "_glow.png"))])
		if gimg != null:
			s.glow = SpriteSheet.from_dict(g, gimg)
	return s


## An RGBA8 image from `path` (res://, user:// or absolute), or null. Reads the PNG bytes itself,
## which needs no editor import; only when there is no such file (an exported build keeps just the
## imported copy) does it ask the resource loader.
static func load_image(path: String) -> Image:
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			img = Image.load_from_file(path)  # not a PNG: let the engine's loaders try
	elif ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		img = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## The JSON object in `path`, or {} when the file is missing or is not an object.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return data
	push_warning("art: %s is not a JSON object" % path)
	return {}
