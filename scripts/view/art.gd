extends RefCounted
## The art loader. Everything under res://art (format: art/README.md) is read once, with
## Image.load_from_file + ImageTexture, so it works without an editor import (headless runs, tests),
## and cached. Each lookup gives a parsed SpriteSheet or null: null means "no art, draw the
## placeholder". Static: `Art.component("laser_mk1")`.

const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const DEFAULT_ROOT := "res://art"
const CREW_LAYERS := ["legs", "torso", "arms"]

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
	var m := RegEx.create_from_string("^(.+)_mk(\\d+)$").search(id)
	if m == null:
		return null
	for tier in range(int(m.get_string(2)) - 1, 0, -1):
		s = _sheet("components", "%s_mk%d" % [m.get_string(1), tier])
		if s != null:
			return s
	return null


## A hand-held item: art/items/<id>.png.
static func item(id: String) -> RefCounted:
	return _sheet("items", id)


## A tile sheet: art/tiles/<name>.png (floor, walls, door, breach, cable).
static func tiles(name: String) -> RefCounted:
	return _sheet("tiles", name)


## An effect: art/fx/<name>.png (fire, smoke, sparks, explosion, muzzle, shield_ripple).
static func fx(name: String) -> RefCounted:
	return _sheet("fx", name)


## A projectile: art/projectiles/<kind>.png (laser, bolt, flak, missile, beam).
static func projectile(kind: String) -> RefCounted:
	return _sheet("projectiles", kind)


## A crew species (art/crew/<species>/): the torso sheet, with `layers` {"legs", "arms"}, `poses`
## and the body anchors. Null unless the torso and the legs both exist.
static func crew(species: String) -> RefCounted:
	var key := "%s/crew/%s" % [root, species]
	if _cache.has(key):
		return _cache[key]
	var dir := "%s/crew/%s" % [root, species]
	var d := read_json(dir + "/crew.json")
	var common := {"frame": d.get("frame"), "anchors_origin": d.get("anchors_origin", "centre")}
	var parts := {}
	for layer in CREW_LAYERS:
		var ld := common.duplicate()
		var own = d.get(layer)
		if own is Dictionary:
			ld.merge(own, true)
		if layer == "torso" and not ld.has("anchors") and d.get("anchors") is Dictionary:
			ld["anchors"] = d["anchors"]  # the body anchors sit at the top of crew.json
		var img := load_image("%s/%s" % [dir, str(ld.get("image", layer + ".png"))])
		if img != null:
			var mask := load_image("%s/%s" % [dir, str(ld.get("color_mask", layer + "_color.png"))])
			parts[layer] = SpriteSheet.from_dict(ld, img, mask, true)
	var out = null
	if parts.has("torso") and parts.has("legs"):
		out = parts["torso"]
		out.layers = {"legs": parts["legs"]}
		if parts.has("arms"):
			out.layers["arms"] = parts["arms"]
		out.poses = _poses(d, out)
	_cache[key] = out
	return out


## The arm poses of crew.json (arms.poses), as {name: {"frame": int, "mount": Vector2 or null}} with
## the mount counted from the centre pixel. "unarmed" always exists.
static func _poses(d: Dictionary, torso) -> Dictionary:
	var out := {"unarmed": {"frame": 0, "mount": null}}
	var arms = d.get("arms")
	var raw = arms.get("poses") if arms is Dictionary else null
	if raw is Dictionary:
		var topleft := str(d.get("anchors_origin", "centre")) == "topleft"
		for name in raw:
			var p = raw[name]
			if p is Dictionary:
				var mount = p.get("mount")
				var v = null
				if mount is Array and mount.size() == 2:
					v = Vector2(float(mount[0]), float(mount[1]))
					if topleft:
						v -= torso.centre()
				out[str(name)] = {"frame": int(p.get("frame", 0)), "mount": v}
	return out


static func _sheet(kind: String, name: String) -> RefCounted:
	var key := "%s/%s/%s" % [root, kind, name]
	if not _cache.has(key):
		_cache[key] = load_sheet("%s/%s/%s" % [root, kind, name], kind == "items")
	return _cache[key]


## The sheet at `base` (a path without extension: base.png, base.json, the mask and glow named in
## the JSON or defaulting to <base>_color.png and <base>_glow.png). Null when there is no PNG.
static func load_sheet(base: String, centre_anchors := false) -> RefCounted:
	var img := load_image(base + ".png")
	if img == null:
		return null
	var d := read_json(base + ".json")
	var dir := base.get_base_dir()
	var stem := base.get_file()
	var mask := load_image("%s/%s" % [dir, str(d.get("color_mask", stem + "_color.png"))])
	var s = SpriteSheet.from_dict(d, img, mask, centre_anchors)
	var g = d.get("glow")
	if g is Dictionary:
		var gimg := load_image("%s/%s" % [dir, str(g.get("image", stem + "_glow.png"))])
		if gimg != null:
			s.glow = SpriteSheet.from_dict(g, gimg)
	return s


## An RGBA8 image from `path` (res://, user:// or absolute), or null. Reads the file itself, and
## only when there is none (an exported build keeps just the imported copy) asks the resource loader.
static func load_image(path: String) -> Image:
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.load_from_file(path)
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
