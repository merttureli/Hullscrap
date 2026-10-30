extends RefCounted
## Hull mounts (docs/CONTENT.md 4f): a weapon or engine is two linked halves through a wall of any
## thickness. The OUTSIDE half sits in space against the outer wall face, the INSIDE half on the floor
## against the inner face, and between them is the LINK: a straight run of full wall cells across the
## mount's width, at least one cell deep. At rotation 0 outward is UP (the outside half above the
## wall); rotation r turns it r quarter turns clockwise. Static geometry and placement rules, no state
## (components.gd keeps the placed mounts).
##
## The player points at the outside half's top-left cell; plan() walks inward from there through the
## wall and puts the inside half on the first floor rows behind it. from_inside() runs the same rule
## the other way for a part saved before mounts existed (it only knows the inside half).

const Art = preload("res://scripts/view/art.gd")

const NONE := Vector2i(-1, -1)  ## "no outside half"
const OUTWARD: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]  ## by rotation
const MAX_DEPTH := 32  ## how many wall layers the walk looks through
const SRC_CELL := 16.0  ## art source px per grid cell
const DEFAULT_REACH := 1.5  ## cells from the barrel pivot to its muzzle when there is no art


static func is_mount(def: Dictionary) -> bool:
	return def.get("mount") is Dictionary


## The outward direction (a unit cell step) of a mount turned `rot` quarter turns.
static func outward(rot: int) -> Vector2i:
	return OUTWARD[posmod(rot, 4)]


## `size` (w, h as at rotation 0) turned `rot` quarter turns: odd turns swap width and height.
static func turned(size: Array, rot: int) -> Vector2i:
	return Vector2i(int(size[1]), int(size[0])) if posmod(rot, 2) == 1 else Vector2i(int(size[0]), int(size[1]))


static func rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in r.size.y:
		for x in r.size.x:
			out.append(r.position + Vector2i(x, y))
	return out


## The cells of wall layer `k` (0 is against the outside half) of a mount whose outside half is `outside`.
static func layer(outside: Rect2i, rot: int, k: int) -> Array[Vector2i]:
	match outward(rot):
		Vector2i.UP:
			return rect_cells(Rect2i(outside.position.x, outside.end.y + k, outside.size.x, 1))
		Vector2i.DOWN:
			return rect_cells(Rect2i(outside.position.x, outside.position.y - 1 - k, outside.size.x, 1))
		Vector2i.RIGHT:
			return rect_cells(Rect2i(outside.position.x - 1 - k, outside.position.y, 1, outside.size.y))
	return rect_cells(Rect2i(outside.end.x + k, outside.position.y, 1, outside.size.y))


## Where the two halves of a mount of `def` turned `rot` are, with the outside half's top-left on
## `out` and a wall `depth` layers thick between them: {inside: Rect2i, outside: Rect2i, link: cells}.
## The halves share their extent along the wall.
static func layout(def: Dictionary, out: Vector2i, rot: int, depth: int) -> Dictionary:
	var osz := turned(def["mount"]["outside"], rot)
	var isz := turned(def["size"], rot)
	var outside := Rect2i(out, osz)
	var link: Array[Vector2i] = []
	for k in depth:
		link.append_array(layer(outside, rot, k))
	var at := out
	match outward(rot):
		Vector2i.UP:
			at = Vector2i(out.x, out.y + osz.y + depth)
		Vector2i.DOWN:
			at = Vector2i(out.x, out.y - depth - isz.y)
		Vector2i.RIGHT:
			at = Vector2i(out.x - depth - isz.x, out.y)
		_:
			at = Vector2i(out.x + osz.x + depth, out.y)
	return {"inside": Rect2i(at, isz), "outside": outside, "link": link}


## The wall depth between a saved outside top-left `out` and inside top-left `anchor`, or 0 when the
## two do not line up as one mount (not on the same axis, or not on opposite sides of a wall).
static func depth_of(def: Dictionary, anchor: Vector2i, rot: int, out: Vector2i) -> int:
	for depth in range(1, MAX_DEPTH + 1):
		if layout(def, out, rot, depth)["inside"].position == anchor:
			return depth
	return 0


## Why a mount `def` turned `rot` cannot have its outside half's top-left on `out`, or "" (`why`).
## On success the result also has: anchor (the inside half's top-left), depth, cells (inside),
## out_cells, link. `comps`: the placed components (components.gd), `grid`: the ship grid.
static func plan(grid, comps, def: Dictionary, out: Vector2i, rot: int) -> Dictionary:
	var res := {"why": "", "anchor": NONE, "depth": 0, "cells": [], "out_cells": [], "link": []}
	var outside := Rect2i(out, turned(def["mount"]["outside"], rot))
	for c in rect_cells(outside):
		if not grid.in_bounds(c) or grid.get_tile(c) != "" or comps.any_at(c) >= 0:
			res["why"] = "the barrel must stick out into space"
			return res
	var depth := 0
	while depth < MAX_DEPTH and layer(outside, rot, depth).all(func(c): return flat_wall(grid, c)):
		depth += 1
	if depth == 0:
		res["why"] = "needs a flat wall to mount through"
		return res
	var lay := layout(def, out, rot, depth)
	var inside := rect_cells(lay["inside"])
	if not inside.all(func(c): return comps.free_floor(grid, c)):
		res["why"] = "the breech needs %dx%d free floor behind the wall" % [lay["inside"].size.x, lay["inside"].size.y]
		return res
	res.merge({"anchor": lay["inside"].position, "depth": depth, "cells": inside, "out_cells": rect_cells(lay["outside"]), "link": lay["link"]}, true)
	return res


## The same rule the other way: a part whose inside half is at `anchor` (rotation `rot`) mounted
## through the wall on its outward side. `why` is "" and the plan() entries are there when it can be
## (the part's own cells count as free floor); `out` is where the outside half would have been.
static func from_inside(grid, comps, def: Dictionary, anchor: Vector2i, rot: int) -> Dictionary:
	var isz := turned(def["size"], rot)
	var osz := turned(def["mount"]["outside"], rot)
	var inside := Rect2i(anchor, isz)
	var depth := 0
	while depth < MAX_DEPTH and _beyond(inside, rot, depth).all(func(c): return flat_wall(grid, c)):
		depth += 1
	var out := anchor
	match outward(rot):
		Vector2i.UP:
			out = Vector2i(anchor.x, anchor.y - depth - osz.y)
		Vector2i.DOWN:
			out = Vector2i(anchor.x, anchor.y + isz.y + depth)
		Vector2i.RIGHT:
			out = Vector2i(anchor.x + isz.x + depth, anchor.y)
		_:
			out = Vector2i(anchor.x - depth - osz.x, anchor.y)
	if depth == 0:
		return {"why": "needs a flat wall to mount through", "out": out}
	var own := {}
	for c in rect_cells(inside):
		own[c] = true
	var p := plan(grid, _Placed.new(comps, own), def, out, rot)
	p["out"] = out
	return p


## The cells `k` layers beyond the outward edge of the inside half `inside`.
static func _beyond(inside: Rect2i, rot: int, k: int) -> Array[Vector2i]:
	match outward(rot):
		Vector2i.UP:
			return rect_cells(Rect2i(inside.position.x, inside.position.y - 1 - k, inside.size.x, 1))
		Vector2i.DOWN:
			return rect_cells(Rect2i(inside.position.x, inside.end.y + k, inside.size.x, 1))
		Vector2i.RIGHT:
			return rect_cells(Rect2i(inside.end.x + k, inside.position.y, 1, inside.size.y))
	return rect_cells(Rect2i(inside.position.x - 1 - k, inside.position.y, 1, inside.size.y))


## The link and outside cells of a mount saved with its outside top-left `out`: the plan() entries
## (no `why`), or {} when the two halves do not line up. Reads no grid.
static func cells_of(def: Dictionary, anchor: Vector2i, rot: int, out: Vector2i) -> Dictionary:
	var depth := depth_of(def, anchor, rot, out)
	if depth == 0:
		return {}
	var lay := layout(def, out, rot, depth)
	return {"anchor": anchor, "depth": depth, "cells": rect_cells(lay["inside"]), "out_cells": rect_cells(lay["outside"]), "link": lay["link"]}


## A full, flat, plain wall cell: a solid tile with no door, no shape and no breach.
static func flat_wall(grid, c: Vector2i) -> bool:
	var id: String = grid.get_tile(c)
	return id != "" and grid.tile_flag(id, "solid") and not grid.tile_flag(id, "door") and grid.shape_of(c).is_empty()


## Where a shot leaves a mount: {pivot: the barrel's turning point (ship-local cell coordinates),
## reach: cells from the pivot to the muzzle}, read from the art's anchors (art/components/<id>_out.json
## has the pivot on the outside half, the barrel's own JSON the pivot and muzzle on the barrel). The
## art is drawn at rotation 0 (outward up), so the pivot turns about the middle of the outside half
## with the part. Without that art: the middle of the outside half and DEFAULT_REACH.
static func barrel(def: Dictionary, out: Vector2i, rot: int) -> Dictionary:
	var id := str(def.get("id", ""))
	var raw: Array = def["mount"]["outside"]
	var half := Vector2(float(raw[0]), float(raw[1])) * SRC_CELL / 2.0
	var pivot_px := half
	var reach := DEFAULT_REACH
	var meta := Art.read_json("%s/components/%s_out.json" % [Art.root, id])
	var b = meta.get("barrel")
	if b is Dictionary:
		if b.get("pivot_on_base") is Array and b["pivot_on_base"].size() == 2:
			pivot_px = Vector2(float(b["pivot_on_base"][0]), float(b["pivot_on_base"][1]))
		var on = b.get("pivot_on_barrel")
		var mz = b.get("muzzle")
		if on is Array and mz is Array and on.size() == 2 and mz.size() == 2:
			reach = absf(float(on[1]) - float(mz[1])) / SRC_CELL
	var osz := turned(raw, rot)
	return {"pivot": Vector2(out) + Vector2(osz) / 2.0 + (pivot_px - half).rotated(posmod(rot, 4) * PI / 2.0) / SRC_CELL, "reach": reach}


## Stand-in for the placed components while migrating a part: `own` cells count as free floor.
class _Placed extends RefCounted:
	var _comps
	var _own: Dictionary

	func _init(comps, own: Dictionary) -> void:
		_comps = comps
		_own = own

	func any_at(c: Vector2i) -> int:
		return _comps.any_at(c)

	func free_floor(grid, c: Vector2i) -> bool:
		return _own.has(c) or _comps.free_floor(grid, c)
