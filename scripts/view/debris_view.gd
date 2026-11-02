extends Node2D
## Draws the debris of drift_debris.gd under the ship (this node comes before BuildMode in the scene, so the ship
## draws on top) and steps it, in play mode only: not in build mode and not in a fight. Each piece is art/debris/<art>.png
## (a strip of tumble frames, art/README.md) when that art exists, else a small rotated polygon in its material colour
## with a dark outline. A "+3 scrap" pop floats up from the mouth that took a piece, an intake plays its `pulling` animation
## while a piece is drawn in (a child node over the ship does both), the HUD's log shows debris.hud_line(), and the starfield drifts
## the way the current runs. frame(dt) does one tick without the scene tree, so tests can drive it.
## Q held in play mode (not in a fight, where Q is the utility ability) turns the tractor beams on (tractor.gd): they haul the
## debris near them toward the nearest intake, and a beam of art/projectiles/tractor_beam is drawn from each emitter to the
## pieces it holds.
## In sector space (the Sector node, sector_view.gd, is flying) the debris is the sector's (DriftDebris.for_sector: its
## current, density and theme), lives in sector px round the flying ship (its frame and velocity each tick), keeps
## drifting through a fight in the sector, and the sky is the sector view's.

const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const Audio = preload("res://scripts/audio/audio.gd")
const POP_LIFE := 1.0  ## seconds a "+N material" pop floats and fades
const POP_RISE := 48.0  ## world px it rises in that time
const STAR_PARALLAX := 0.6  ## the nearest stars drift this fraction of the debris' screen speed
const OUTLINE := Color(0.05, 0.06, 0.09)
const PRESSURE_STEP := 0.02  ## how far the tide's pressure must move before the spawner takes its numbers again
const GLINT_RATE := 2.1  ## rad/s of a rare piece's sparkle (a swell about every 3 s)
const MIN_PX := 6.0  ## screen px a piece is drawn at the least, so debris still shows zoomed far out

var sim: Node  ## the ShipSim, for the player's ship
var build: Node  ## the BuildMode: play mode is build_on == false, a fight sets combat
var cam: Camera2D
var starfield: Node  ## Space/Starfield: its drift follows the current in play mode
var sector: Node  ## the Sector node (sector_view.gd), if the scene has one
var debris: DriftDebris  ## made when the ship first shows, again when the player's ship is replaced
var view_size := Vector2(1600.0, 900.0)  ## the viewport, screen px (set every frame in the tree)
var view_zoom := Vector2(0.5, 0.5)
var view_centre := Vector2.ZERO  ## the world point at the middle of the screen
var pops: Array = []  ## {pos, text, age}
var q_held := false  ## Q is down; _process reads the key, a test sets it
var _ship: RefCounted
var _sector_of = null  # the sector (sector.gd) the debris was made for, null on the build screen's own
var _hollow := false  # whether that sector was Hollow when the spawner took its numbers
var _pressure := 0.0  # and the tide's pressure on it then
var _clock := 0.0
var _sheets := {}  # art id -> SpriteSheet, or null when there is no art yet
var _top: Node2D  # over the ship: the pulling mouths and the pops
var _glow: Node2D  # additive glow of the pieces that have it (a fuel canister), under the ship
var _top_glow: Node2D  # additive glow of the pulling mouths, over the ship
var _star_drift := Vector2.ZERO  # the starfield's own drift, put back when play mode ends
var _pulling := {}  # the intakes that were pulling at the last tick (a new one is heard)


func _ready() -> void:
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	cam = get_node_or_null("../Camera2D")
	starfield = get_node_or_null("../Space/Starfield")
	sector = get_node_or_null("../Sector")
	if starfield != null:
		_star_drift = starfield.drift
	_glow = GlowLayer.new()
	add_child(_glow)
	_top = Node2D.new()
	_top.z_index = 1
	_top.draw.connect(_draw_top)
	add_child(_top)
	_top_glow = GlowLayer.new()
	_top.add_child(_top_glow)


func _process(dt: float) -> void:
	view_size = get_viewport_rect().size
	if cam != null:
		view_zoom = cam.zoom
		view_centre = cam.get_screen_center_position()
	q_held = Input.is_key_pressed(KEY_Q) and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META)
	frame(minf(dt, 0.25))


## Debris runs while the player is in play mode on their ship: not in build mode, not in a fight (unless the fight is
## in the sector).
func active() -> bool:
	return build != null and sim != null and sim.player_ship() != null and not build.build_on and (not build.combat or _flying()) and not (sector != null and bool(sector.get("boarding")))


func _flying() -> bool:
	return sector != null and sector.flying()


## Do the tractor beams run now: Q is held in play mode, not in a fight (Q is the utility ability there) and not under the map or an event?
func tractor_ok() -> bool:
	var map = build.get("drift") if build != null else null
	return q_held and active() and not build.combat and not (map != null and map.visible)


## One tick of `dt` seconds: step the debris when active, collect the pops, point the starfield.
func frame(dt: float) -> void:
	var on := active()
	visible = on
	if starfield != null and not on:
		starfield.drift = _star_drift
	if not on:
		_set_fx({})
		if debris != null:
			debris.tractor_on = false
		return
	var ship = sim.player_ship()
	var here = sector.current() if _flying() else null
	if debris == null or ship != _ship or here != _sector_of:
		_ship = ship
		_sector_of = here
		debris = DriftDebris.for_sector(here, ship.rng_seed) if here != null else DriftDebris.new(ship.rng_seed)
		_hollow = here != null and here.hollow
		_pressure = here.pressure if here != null else 0.0
		pops.clear()
		_place(ship)
		debris.prewarm(ship)
	elif here != null and (here.hollow != _hollow or absf(here.pressure - _pressure) >= PRESSURE_STEP):  # the tide took this place with the ship in it, or came nearer: the current thins, the pieces adrift stay
		_hollow = here.hollow
		_pressure = here.pressure
		debris.rescale(here)
	_clock += dt
	_place(ship)
	debris.tractor_on = tractor_ok()
	debris.step(ship, dt)
	_set_fx(debris.beam_aims() if debris.tractor_on else {}, debris.beams_on)
	for e in debris.take_events():
		if e["kind"] == "rare":  # a rare piece came into view: a toast, no pop
			_toast(str(e["text"]))
			continue
		pops.append({"pos": e["pos"], "text": e["text"], "age": 0.0})
		Audio.fx(self, "collect", e["pos"])  # (the catch is at the mouth on the player's ship)
	for uid in debris.pulling:
		if not _pulling.has(uid):
			Audio.fx(self, "intake_pull")  # a mouth starts drawing a piece in
	_pulling = debris.pulling.duplicate()
	Audio.fx_loop(self, "tractor", "tractor_loop", debris.tractor_on and not debris.beams_on.is_empty(), 1.0)
	for p in pops:
		p["age"] += dt
	pops = pops.filter(func(p): return p["age"] < POP_LIFE)
	if starfield != null:
		starfield.drift = debris.current_vel() * view_zoom.x * STAR_PARALLAX if here == null else Vector2.ZERO
	queue_redraw()
	if _top != null:
		_top.queue_redraw()


## A hint toast at the top of the screen (the front door's), when the scene has one.
func _toast(text: String) -> void:
	var door = get_node_or_null("../FrontDoor")
	var t = door.get("toast") if door != null else null
	if t != null:
		t.push(text)


## Light the emitters of the beams that are on (BuildMode.mount_fx): `aims` is uid -> the way a beam that hauls points.
func _set_fx(aims: Dictionary, on: Array = []) -> void:
	if build == null or not "mount_fx" in build:
		return
	var fx := {}
	for uid in on:
		fx[uid] = {"aim": aims.get(uid, Vector2.ZERO)}
	if fx != build.mount_fx:
		build.mount_fx = fx


## Tell the debris where the view is and, in a sector, where the ship flies.
func _place(ship) -> void:
	debris.view_centre = view_centre
	debris.view_half = view_size / view_zoom / 2.0
	if _sector_of != null:
		debris.frame = sector.ship_frame()
		debris.frame_vel = sector.ship_velocity()
		if not is_inside_tree():
			debris.view_centre = debris.frame * (Vector2.ZERO if ship == null else ship.world_pos)


# --- drawing -------------------------------------------------------------------------------------------

func _draw() -> void:
	if debris == null or not visible:
		return
	var px := 1.0 / maxf(view_zoom.x, 0.05)  # one screen pixel in world px, for the outlines
	var quads := []
	for p in debris.pieces:
		var t := debris.type_of(p)
		var sheet = _sheet(str(t["art"]))
		if sheet != null:
			_draw_art(sheet, p, quads)
		else:
			_draw_placeholder(p, t, px)
		if bool(t.get("rare", false)):
			_draw_glint(p, px)
	if _glow != null:
		_glow.show_quads(quads)


func _sheet(art_id: String) -> RefCounted:
	if not _sheets.has(art_id):
		_sheets[art_id] = Art.load_sheet("%s/debris/%s" % [Art.root, art_id])
	return _sheets[art_id]


## A piece from its art: a strip of tumble frames plays by itself; a one-frame sheet is turned with the piece.
func _draw_art(sheet, p: Dictionary, quads: Array) -> void:
	var k := DriftDebris.CELL / SpriteSheet.SRC_CELL
	k *= maxf(1.0, MIN_PX / maxf(float(sheet.frame.x) * k * view_zoom.x, 0.01))
	var size := Vector2(sheet.frame) * k
	var t := float(p["age"]) + float(p["phase"])
	var angle: float = p["angle"] if sheet.count <= 1 else 0.0
	draw_set_transform(p["pos"], angle, Vector2.ONE)
	draw_texture_rect_region(sheet.texture, Rect2(-size / 2.0, size), sheet.region(sheet.loop_frame(t)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var g = sheet.glow
	if g != null:
		quads.append({"tex": g.texture, "rect": Rect2(-size / 2.0 + g.offset * k, Vector2(g.frame) * k), "src": g.region(g.loop_frame(t)),
			"xf": Transform2D(angle, p["pos"]), "mod": Color(1, 1, 1, 1)})


## A rare piece's slow sparkle: a four-point star that swells and fades about every 3 s, a little off the piece's middle.
func _draw_glint(p: Dictionary, px: float) -> void:
	var f := pow(maxf(sin((float(p["age"]) + float(p["phase"])) * GLINT_RATE), 0.0), 3.0)
	if f <= 0.01:
		return
	var at: Vector2 = p["pos"] + Vector2(p["r"] * 0.35, -p["r"] * 0.35)
	var len: float = (float(p["r"]) * 1.1 + 6.0 * px) * f
	var col := Color(1.0, 1.0, 0.92, f)
	draw_line(at - Vector2(len, 0.0), at + Vector2(len, 0.0), col, 1.5 * px)
	draw_line(at - Vector2(0.0, len), at + Vector2(0.0, len), col, 1.5 * px)
	draw_circle(at, 2.0 * px * f, col)


## No art yet: a lopsided polygon in the material colour (a crate and a canister are squarer), 1 screen px outline.
func _draw_placeholder(p: Dictionary, t: Dictionary, px: float) -> void:
	var col := Color(str(t["color"]))
	var r: float = maxf(p["r"], MIN_PX * 0.5 * px)
	var n := 4 if t["id"] in ["sealed_crate", "fuel_canister"] else 7
	var pts := PackedVector2Array()
	for i in n:
		var jag := 1.0 if n == 4 else 0.78 + 0.22 * float(posmod(int(p["uid"]) * 7 + i * 13, 5)) / 4.0
		pts.append(p["pos"] + Vector2.from_angle(float(p["angle"]) + (float(i) + (0.5 if n == 4 else 0.0)) * TAU / float(n)) * r * jag * (1.3 if n == 4 else 1.0))
	draw_colored_polygon(pts, col)
	if t["id"] == "fuel_canister" or t["id"] == "sealed_crate":  # a lighter lid so they read apart from rocks
		draw_line(pts[0], pts[1], col.lightened(0.45), 3.0 * px)
	pts.append(pts[0])
	draw_polyline(pts, OUTLINE, px)


## Over the ship: the pulling frames of the mouths drawing a piece in (both halves, the glow added), then the pops.
func _draw_top() -> void:
	if debris == null or not visible or _ship == null:
		return
	var quads := []
	_top.draw_set_transform_matrix(debris.frame)  # the mouths are drawn in the ship's frame
	_top_glow.transform = debris.frame
	for uid in debris.pulling:
		var inst: Dictionary = _ship.components.instances.get(uid, {})
		if inst.is_empty() or inst["out_cells"].is_empty():
			continue
		var def: Dictionary = _ship.components.def(inst["id"])
		var opts := {"pulling": true, "time": _clock, "glow_out": quads}
		var out_sheet = Art.component(str(inst["id"]) + "_out")
		if out_sheet != null and out_sheet.has_anim("pulling"):
			var out_rect := Visuals.slope_rect(def, inst, Vector2.ZERO, DriftDebris.CELL) if Mounts.is_angled(inst) else _cells_rect(inst["out_cells"])
			Visuals.draw_mount_out(_top, def, inst, out_rect, Vector2.ZERO, DriftDebris.CELL, Vector2.ZERO, opts)
		var in_sheet = Art.component(str(inst["id"]))
		if in_sheet != null and in_sheet.has_anim("pulling"):
			Visuals.draw_component(_top, _cells_rect(inst["cells"]), def, inst, DriftDebris.CELL, opts)
	_top.draw_set_transform_matrix(Transform2D.IDENTITY)
	for l in debris.beam_lines:
		_draw_beam(l["from"], l["to"], quads)
	_top_glow.show_quads(quads)
	var font := ThemeDB.fallback_font
	var size := roundi(18.0 / maxf(view_zoom.x, 0.05))
	for p in pops:
		var f: float = p["age"] / POP_LIFE
		var at: Vector2 = p["pos"] + Vector2(0.0, -DriftDebris.CELL * 1.2 - POP_RISE * f)
		_top.draw_string_outline(font, at, p["text"], HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, maxi(2, size / 6), Color(0, 0, 0, 1.0 - f))
		_top.draw_string(font, at, p["text"], HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, Color(1.0, 0.92, 0.55, 1.0 - f))


## A tractor beam from its emitter `a` to the piece `b` it holds (world px): art/projectiles/tractor_beam laid along the line from
## whole tiles and a cut last one (its head end), the wave crawling toward the emitter; a plain mint line without the art. The
## glow goes in `quads`, which `_top_glow` draws in the ship's frame.
func _draw_beam(a: Vector2, b: Vector2, quads: Array) -> void:
	var art = Art.projectile("tractor_beam")
	if art == null:
		_top.draw_line(a, b, Color(0.55, 1.0, 0.8, 0.7), 3.0 / maxf(view_zoom.x, 0.05))
		return
	var k := DriftDebris.CELL / SpriteSheet.SRC_CELL
	var xf := Transform2D((b - a).angle() + PI / 2.0, a)
	var frame: int = art.loop_frame(_clock)
	var w := float(art.frame.x) * k
	var g = art.glow
	_top.draw_set_transform_matrix(xf)
	for p in beam_pieces(a.distance_to(b), float(art.frame.y) * k):
		var rows: float = p["len"] / k  # source rows of this piece, from the head end of the frame
		var at := Vector2(-w / 2.0, -(p["from"] + p["len"]))
		_top.draw_texture_rect_region(art.texture, Rect2(at, Vector2(w, p["len"])), Rect2(art.region(frame).position, Vector2(art.frame.x, rows)))
		if g != null:
			quads.append({"tex": g.texture, "rect": Rect2(at + Vector2(g.offset.x * k, 0.0), Vector2(float(g.frame.x) * k, p["len"])),
				"src": Rect2(g.region(clampi(frame, 0, g.count - 1)).position, Vector2(g.frame.x, rows)), "xf": debris.frame.affine_inverse() * xf, "mod": Color(1, 1, 1, 1)})
	_top.draw_set_transform_matrix(Transform2D.IDENTITY)


## The pieces a beam `length` px long is tiled from when one tile is `tile` px: [{"from": distance from the start, "len": px}],
## all full tiles but the last (the same cut as combat_view.gd beam_pieces).
static func beam_pieces(length: float, tile: float) -> Array:
	var out := []
	var done := 0.0
	while done < length - 0.001 and tile > 0.0:
		var h := minf(tile, length - done)
		out.append({"from": done, "len": h})
		done += h
	return out


## The world rectangle of `cells` (ship grid cells).
func _cells_rect(cells: Array) -> Rect2:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2(DriftDebris._origin(_ship) + Vector2(lo) * DriftDebris.CELL, Vector2(hi - lo + Vector2i.ONE) * DriftDebris.CELL)
