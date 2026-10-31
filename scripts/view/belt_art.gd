extends RefCounted
## Draws a ship's conveyor belts (docs/CONTENT.md 4f; the logic is scripts/sim/belts.gd and ammo.gd): the belt autotile
## (art/tiles/belt.png: 16 masks across, 4 tread-scroll rows down; the treads scroll while a working drive moves the
## network), cut cells (art/tiles/belt_cut.png), and the units riding them as little ammo-coloured chunks. A flat
## placeholder when the art is missing. Drawing only; build_mode.gd and ship_view.gd call draw() once a frame.

const Art = preload("res://scripts/view/art.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Belts = preload("res://scripts/sim/belts.gd")

const SCROLL_FPS := 8.0
const BELT := Color("#6b6350")
const BELT_RIB := Color("#9c9272")
const CUT := Color("#3a2a22")
const SPARK := Color("#ffb347")


## Draw every belt cell of `ship` and the units on them. `origin`: where grid cell (0, 0) starts in the canvas' pixels.
static func draw(canvas, ship, origin: Vector2, cell_px: float, t: float, alpha := 1.0) -> void:
	var b = ship.belts
	if b.cells.is_empty() and b.units.is_empty():
		return
	var plan: Dictionary = b.analyze(ship)
	var moving := {}  # net id -> true when a working drive moves it
	for net in plan["nets"]:
		moving[net["id"]] = Ammo.net_speed(ship, net) > 0.0
	var has := func(c: Vector2i) -> bool: return b.live(ship.grid, c)
	for c in b.cells:
		if ship.grid.get_tile(c) == "":
			continue  # shot open: no floor there
		var rect := Rect2(origin + Vector2(c) * cell_px, Vector2(cell_px, cell_px))
		if b.cut.has(c):
			cut_cell(canvas, rect, b.cells.has(c + Vector2i.LEFT) or b.cells.has(c + Vector2i.RIGHT), t, alpha)
			continue
		var net: int = plan["net_of"].get(c, -1)
		tile(canvas, rect, Belts.mask_of(c, has), t if moving.get(net, false) else -1.0, alpha)
	for u in b.units:
		unit(canvas, origin + Belts.unit_pos(u) * cell_px, cell_px, str(u["item"]), alpha)


## One belt cell with autotile `mask` (N*1 + E*2 + S*4 + W*8). `t` < 0: the treads stand still.
static func tile(canvas, rect: Rect2, mask: int, t: float, alpha := 1.0) -> void:
	var s = Art.tiles("belt")
	if s == null:
		canvas.draw_rect(rect.grow(-1), Color(BELT, alpha))
		var mid := rect.get_center()
		for i in 4:
			if mask & (1 << i):
				canvas.draw_line(mid, mid + Vector2(Belts.SIDES[i]) * rect.size.x * 0.5, Color(BELT_RIB, alpha), 3.0)
		return
	var scroll := 0 if t < 0.0 else int(t * SCROLL_FPS) % 4
	canvas.draw_texture_rect_region(s.texture, rect, s.region(scroll * 16 + mask), Color(1, 1, 1, alpha))


## A cut cell: the torn-tread art (a north-south run, turned for an east-west one), else a dark gap with a spark.
static func cut_cell(canvas, rect: Rect2, horizontal: bool, t: float, alpha := 1.0) -> void:
	var s = Art.tiles("belt_cut")
	if s == null:
		canvas.draw_rect(rect.grow(-1), Color(CUT, alpha))
		canvas.draw_line(rect.position, rect.end, Color(SPARK, alpha * (0.4 + 0.6 * absf(sin(t * 6.0)))), 2.0)
		return
	if horizontal:
		canvas.draw_set_transform_matrix(Transform2D(PI / 2.0, rect.get_center()))
		canvas.draw_texture_rect_region(s.texture, Rect2(-rect.size / 2.0, rect.size), s.region(0), Color(1, 1, 1, alpha))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		canvas.draw_texture_rect_region(s.texture, rect, s.region(0), Color(1, 1, 1, alpha))


## A unit of ammo `item` riding the belt, centred on `at`.
static func unit(canvas, at: Vector2, cell_px: float, item: String, alpha := 1.0) -> void:
	var colors: Dictionary = Ammo.cfg()["unit_colors"]
	var col := Color(str(colors.get(item, colors["default"])), alpha)
	var s := cell_px * 0.34
	canvas.draw_rect(Rect2(at - Vector2(s, s) / 2.0 - Vector2.ONE, Vector2(s, s) + Vector2(2, 2)), Color(0, 0, 0, 0.75 * alpha))
	canvas.draw_rect(Rect2(at - Vector2(s, s) / 2.0, Vector2(s, s)), col)
	canvas.draw_rect(Rect2(at - Vector2(s, s) / 2.0, Vector2(s, 2.0)), Color(col.lightened(0.45), alpha))
