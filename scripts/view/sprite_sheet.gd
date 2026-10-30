extends RefCounted
## One parsed art sheet: a texture cut into equal frames (a horizontal strip, wrapping to more rows
## only when the image is wider than the strip says), named animations, an optional glow layer (a
## sheet of its own), an optional `_color` mask for outfit tints, and anchors. Built by art.gd from
## a PNG and its JSON (the format is in art/README.md); from_dict() also builds one from a plain
## dictionary and images, which is how the tests make fixtures. No drawing here, only frame maths.

const SRC_CELL := 16.0  ## source pixels per grid cell

var texture: Texture2D
var image: Image  ## the pixels, kept to build tinted copies
var mask: Image  ## the colour mask (same size as `image`), or null
var frame := Vector2i.ONE  ## source px of one frame
var columns := 1
var count := 1  ## number of frames
var cells := Vector2i.ZERO  ## the footprint in cells at rotation 0; ZERO for a plain PNG with no JSON
var offset := Vector2.ZERO  ## where the frame's top-left sits against the footprint's top-left (source px; overhang is negative)
var orientation_rot := 0  ## quarter turns added to the placed rotation, so the art's facing matches the game's
var autotile := ""  ## "mask4": frame = N*1 + E*2 + S*4 + W*8 over neighbours
var anims := {}  ## name -> {"start", "count", "fps"}
var glow = null  ## another SpriteSheet (its `offset` is against this sheet's frame top-left), or null
var anchors := {}  ## name -> Vector2, source px from the frame's top-left pixel
var layers := {}  ## crew: "legs" / "arms" sheets next to this torso sheet
var poses := {}  ## crew: arm pose name -> {"frame": int, "mount": Vector2 or null}, centre-relative
var pose := ""  ## an item: the arm pose class it is held in ("pistol", "rifle", "tool")
var notes := ""
var _tinted := {}  # "#rrggbb" -> ImageTexture


## A sheet from the JSON dictionary `d` (any key may be missing) and its images. `mask_img` may be
## null. `centre_anchors`: anchors in `d` count from the frame's centre pixel, not its top-left
## (crew and items); "anchors_origin" in `d` overrides.
static func from_dict(d: Dictionary, img: Image, mask_img: Image = null, centre_anchors := false) -> RefCounted:
	var s = new()
	s.image = img
	s.mask = mask_img if mask_img != null and mask_img.get_size() == img.get_size() else null
	s.texture = ImageTexture.create_from_image(img)
	var fr = d.get("frame")
	s.frame = Vector2i(maxi(1, int(fr[0])), maxi(1, int(fr[1]))) if fr is Array and fr.size() == 2 else img.get_size()
	s.columns = maxi(1, img.get_width() / s.frame.x)
	s.count = s.columns * maxi(1, img.get_height() / s.frame.y)
	var ce = d.get("cells")
	if ce is Array and ce.size() == 2:
		s.cells = Vector2i(int(ce[0]), int(ce[1]))
	s.offset = _vec(d.get("offset"))
	s.orientation_rot = posmod(int(d.get("orientation_rot", 0)), 4)
	s.autotile = str(d.get("autotile", ""))
	s.pose = str(d.get("pose", ""))
	s.notes = str(d.get("notes", ""))
	var a = d.get("anims", d.get("animations", {}))
	if a is Dictionary:
		for name in a:
			var v = a[name]
			if v is Array and v.size() >= 2:
				s.anims[str(name)] = {"start": int(v[0]), "count": maxi(1, int(v[1])), "fps": float(v[2]) if v.size() > 2 else 0.0}
	var origin := str(d.get("anchors_origin", "centre" if centre_anchors else "topleft"))
	var at = d.get("anchors")
	if at is Dictionary:
		for name in at:
			var p := _vec(at[name])
			s.anchors[str(name)] = p + s.centre() if origin in ["centre", "center"] else p
	return s


static func _vec(v) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO


## The centre pixel of a frame (what crew and items rotate about): (w / 2, h / 2) by integer division.
func centre() -> Vector2:
	return Vector2(frame.x / 2, frame.y / 2)


## Anchor `name` from the centre pixel (x right, y down), or `fallback` when the sheet has none.
func anchor_c(name: String, fallback := Vector2.ZERO) -> Vector2:
	return anchors[name] - centre() if anchors.has(name) else fallback


func has_anim(name: String) -> bool:
	return anims.has(name)


## First frame of animation `name` (0 when there is none).
func start_of(name: String) -> int:
	return int(anims[name]["start"]) if anims.has(name) else 0


## The frame of looping animation `name` at `t` seconds (its first frame when it has no fps or one frame).
func frame_at(name: String, t: float) -> int:
	if not anims.has(name):
		return 0
	var a: Dictionary = anims[name]
	if a["count"] <= 1 or a["fps"] <= 0.0:
		return a["start"]
	return a["start"] + int(floorf(maxf(t, 0.0) * a["fps"])) % a["count"]


## The frame of `name` for a fraction 0..1 (a charge bar: 0 is the first frame, 1 the last).
func frame_frac(name: String, f: float) -> int:
	if not anims.has(name):
		return 0
	var a: Dictionary = anims[name]
	return a["start"] + clampi(roundi(clampf(f, 0.0, 1.0) * (a["count"] - 1)), 0, a["count"] - 1)


## The frame of `name` played once over `life` (0 = just started, 1 = over): equal slices, the last held.
func frame_life(name: String, f: float) -> int:
	if not anims.has(name):
		return clampi(int(clampf(f, 0.0, 1.0) * count), 0, count - 1)
	var a: Dictionary = anims[name]
	return a["start"] + clampi(int(clampf(f, 0.0, 1.0) * a["count"]), 0, a["count"] - 1)


## The frame of `name` played once at its own fps, `age` seconds in (the last frame is held).
func frame_once(name: String, age: float) -> int:
	if not anims.has(name):
		return 0
	var a: Dictionary = anims[name]
	if a["fps"] <= 0.0:
		return a["start"]
	return a["start"] + clampi(int(maxf(age, 0.0) * a["fps"]), 0, a["count"] - 1)


## The rectangle of frame `i` in the texture, in source px.
func region(i: int) -> Rect2:
	var k := clampi(i, 0, count - 1)
	return Rect2(Vector2((k % columns) * frame.x, (k / columns) * frame.y), Vector2(frame))


## Quarter turns clockwise to draw this art at for a part placed with rotation `rot`.
func rot_total(rot: int) -> int:
	return posmod(rot + orientation_rot, 4)


func has_mask() -> bool:
	return mask != null


## The texture with the outfit (where the mask is) multiplied by `color`; the plain texture when the
## sheet has no mask. Made once per colour and kept.
func tinted(color: Color) -> Texture2D:
	if mask == null or image == null:
		return texture
	var key := color.to_html(false)
	if _tinted.has(key):
		return _tinted[key]
	var out := image.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var m := mask.get_pixel(x, y).a
			if m <= 0.0:
				continue
			var p := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(p.r * lerpf(1.0, color.r, m), p.g * lerpf(1.0, color.g, m), p.b * lerpf(1.0, color.b, m), p.a))
	var tex := ImageTexture.create_from_image(out)
	_tinted[key] = tex
	return tex


## The mask4 autotile frame: N*1 + E*2 + S*4 + W*8 over the neighbours that count as solid (or joined).
static func mask4(n: bool, e: bool, s: bool, w: bool) -> int:
	return int(n) + int(e) * 2 + int(s) * 4 + int(w) * 8
