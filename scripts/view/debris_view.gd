extends Node2D
## Draws the debris of drift_debris.gd under the ship (this node comes before BuildMode in the scene, so the ship
## draws on top) and steps it, in play mode only: not in build mode and not in a fight. Each piece is art/debris/<art>.png
## (a strip of tumble frames, art/README.md) when that art exists, else a small rotated polygon in its material colour
## with a dark outline. A "+3 scrap" pop floats up from the mouth that took a piece, an intake plays its `pulling` animation
## while a piece is drawn in (a child node over the ship does both), the HUD gets one line, and the starfield drifts
## the way the current runs. frame(dt) does one tick without the scene tree, so tests can drive it.
## In sector space (the Sector node, sector_view.gd, is flying) the debris is the sector's (DriftDebris.for_sector: its
## current, density and theme), lives in sector px round the flying ship (its frame and velocity each tick), keeps
## drifting through a fight in the sector, and the sky is the sector view's.

const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const Visuals = preload("res://scripts/view/visuals.gd")
const GlowLayer = preload("res://scripts/view/glow_layer.gd")
const POP_LIFE := 1.0  ## seconds a "+N material" pop floats and fades
const POP_RISE := 48.0  ## world px it rises in that time
const STAR_PARALLAX := 0.6  ## the nearest stars drift this fraction of the debris' screen speed
const OUTLINE := Color(0.05, 0.06, 0.09)

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
var _ship: RefCounted
var _sector_of = null  # the sector (sector.gd) the debris was made for, null on the build screen's own
var _clock := 0.0
var _sheets := {}  # art id -> SpriteSheet, or null when there is no art yet
var _top: Node2D  # over the ship: the pulling mouths and the pops
var _glow: Node2D  # additive glow of the pieces that have it (a fuel canister), under the ship
var _top_glow: Node2D  # additive glow of the pulling mouths, over the ship
var _layer: CanvasLayer
var _label: Label
var _star_drift := Vector2.ZERO  # the starfield's own drift, put back when play mode ends


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
	_layer = CanvasLayer.new()
	_layer.layer = 2
	_label = Label.new()
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 14.0
	_label.offset_top = -68.0
	_label.offset_right = 1500.0
	_label.offset_bottom = -42.0
	_label.add_theme_color_override("font_color", Color("#ffd24a"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_label)
	add_child(_layer)


func _process(dt: float) -> void:
	view_size = get_viewport_rect().size
	if cam != null:
		view_zoom = cam.zoom
		view_centre = cam.get_screen_center_position()
	frame(minf(dt, 0.25))


## Debris runs while the player is in play mode on their ship: not in build mode, not in a fight (unless the fight is
## in the sector).
func active() -> bool:
	return build != null and sim != null and sim.player_ship() != null and not build.build_on and (not build.combat or _flying())


func _flying() -> bool:
	return sector != null and sector.flying()


## One tick of `dt` seconds: step the debris when active, collect the pops, point the starfield.
func frame(dt: float) -> void:
	var on := active()
	visible = on
	if _layer != null:
		_layer.visible = on
	if starfield != null and not on:
		starfield.drift = _star_drift
	if not on:
		return
	var ship = sim.player_ship()
	var here = sector.current() if _flying() else null
	if debris == null or ship != _ship or here != _sector_of:
		_ship = ship
		_sector_of = here
		debris = DriftDebris.for_sector(here, ship.rng_seed) if here != null else DriftDebris.new(ship.rng_seed)
		pops.clear()
		_place(ship)
		debris.prewarm(ship)
	_clock += dt
	_place(ship)
	debris.step(ship, dt)
	for e in debris.take_events():
		pops.append({"pos": e["pos"], "text": e["text"], "age": 0.0})
	for p in pops:
		p["age"] += dt
	pops = pops.filter(func(p): return p["age"] < POP_LIFE)
	if starfield != null:
		starfield.drift = debris.current_vel() * view_zoom.x * STAR_PARALLAX if here == null else Vector2.ZERO
	if _label != null:
		_label.text = debris.hud_line()
	queue_redraw()
	if _top != null:
		_top.queue_redraw()


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
	if _glow != null:
		_glow.show_quads(quads)


func _sheet(art_id: String) -> RefCounted:
	if not _sheets.has(art_id):
		_sheets[art_id] = Art.load_sheet("%s/debris/%s" % [Art.root, art_id])
	return _sheets[art_id]


## A piece from its art: a strip of tumble frames plays by itself; a one-frame sheet is turned with the piece.
func _draw_art(sheet, p: Dictionary, quads: Array) -> void:
	var k := DriftDebris.CELL / SpriteSheet.SRC_CELL
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


## No art yet: a lopsided polygon in the material colour (a crate and a canister are squarer), 1 screen px outline.
func _draw_placeholder(p: Dictionary, t: Dictionary, px: float) -> void:
	var col := Color(str(t["color"]))
	var r: float = p["r"]
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
			Visuals.draw_mount_out(_top, def, inst, _cells_rect(inst["out_cells"]), Vector2.ZERO, DriftDebris.CELL, Vector2.ZERO, opts)
		var in_sheet = Art.component(str(inst["id"]))
		if in_sheet != null and in_sheet.has_anim("pulling"):
			Visuals.draw_component(_top, _cells_rect(inst["cells"]), def, inst, DriftDebris.CELL, opts)
	_top.draw_set_transform_matrix(Transform2D.IDENTITY)
	_top_glow.show_quads(quads)
	var font := ThemeDB.fallback_font
	var size := roundi(18.0 / maxf(view_zoom.x, 0.05))
	for p in pops:
		var f: float = p["age"] / POP_LIFE
		var at: Vector2 = p["pos"] + Vector2(0.0, -DriftDebris.CELL * 1.2 - POP_RISE * f)
		_top.draw_string_outline(font, at, p["text"], HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, maxi(2, size / 6), Color(0, 0, 0, 1.0 - f))
		_top.draw_string(font, at, p["text"], HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, Color(1.0, 0.92, 0.55, 1.0 - f))


## The world rectangle of `cells` (ship grid cells).
func _cells_rect(cells: Array) -> Rect2:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2(DriftDebris._origin(_ship) + Vector2(lo) * DriftDebris.CELL, Vector2(hi - lo + Vector2i.ONE) * DriftDebris.CELL)
