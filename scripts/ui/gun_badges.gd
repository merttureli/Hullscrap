extends RefCounted
## Which gun is which, by picture (docs/GUNS.md 7, the owner's "see which guns we are firing and which button fires which gun").
## Every gun of the player's ship carries a CHIP on its outside half: its number key (1-9), its fire group's colour and a shape mark
## (LMB a filled dot, RMB a ring, a gun that fires by itself a small arc, so it reads without colour). While LMB or RMB is held, the
## guns of that group get a bright outline round their mount (dim, with a small icon for the reason, when the gun cannot bear); a gun
## that fires flashes; hovering a weapon bar slot (or a gun on the ship) lights the pair and draws the gun's firing arc. The colours
## and marks are data (data/combat_ui.json, "gun_badges"). weapon_bar.gd shares one of these with combat_view.gd; build_mode.gd
## draws the same chips on placed guns (draw_chip) and right-click cycles a fixed gun's group (cycle).

const PATH := "res://data/combat_ui.json"
const ARC_COLORS := {"fixed": Color("#ff7a5a"), "swivel": Color("#ffc966"), "turret": Color("#6cc4ff")}  ## the firing arc by aim class (as the build ghost)
const GREY := Color("#6b7686")
const BAD := Color("#e0453a")
const BG := Color(0.04, 0.07, 0.11, 0.9)
const TEXT := Color("#eaf3ff")
const OKAY := ["ready"]
## Why a gun cannot bear -> the icon drawn beside its chip.
const REASON_ICON := {"out of arc": "arc", "cooling down": "clock", "feeding": "clock", "unpowered": "bolt", "no target": "arc", "malfunction": "cross",
	"overheated": "bang", "disabled": "cross", "offline": "cross", "wrecked": "cross", "no ammo": "slash", "no ammo rack in reach": "slash",
	"rack empty": "slash", "belt stopped": "slash"}

static var _cfg := {}

var held := {1: false, 2: false}  ## fire group -> its button (or hold override) is down (combat_view.gd sets it every frame)
var bar_hover := -1  ## uid of the gun whose weapon bar slot the mouse is on
var world_hover := -1  ## uid of the gun under the mouse on the ship
var auto_on := true  ## do the swivels and turrets fire by themselves (T)
var _fired := {}  ## uid -> Time.get_ticks_msec() of its last shot


## The "gun_badges" block of data/combat_ui.json, read once.
static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary and d.get("gun_badges") is Dictionary:
				_cfg = d["gun_badges"]
	return _cfg


## How weapon `w` (a CombatSession.weapons() entry: aim, group, pd) is marked: {key ("1", "2", "auto" or "pd"), label, color, mark}.
static func style(w: Dictionary) -> Dictionary:
	var key := "drones" if w.get("drones", false) else "pd" if w.get("pd", false) else ("auto" if str(w.get("aim", "fixed")) != "fixed" else str(int(w.get("group", 1))))
	var g: Dictionary = cfg().get("groups", {}).get(key, {"label": "?", "color": "#ffffff", "mark": "dot"})
	return {"key": key, "label": str(g["label"]), "color": Color(str(g["color"])), "mark": str(g["mark"])}


## The group a gun sits in on the weapon bar: 1 (LMB), 2 (RMB) or 3 (fires by itself).
static func bar_group(w: Dictionary) -> int:
	return 3 if str(w.get("aim", "fixed")) != "fixed" else int(w.get("group", 1))


## The number key of the gun in 0-based slot `i`, 0 when it has none (the keys stop at 9).
static func key_of(i: int) -> int:
	return i + 1 if i < 9 else 0


## Gun `uid` fired now: its chip and its bar slot flash.
func on_fire(uid: int) -> void:
	_fired[uid] = Time.get_ticks_msec()


## 1 at the shot, fading to 0 over flash_s.
func flash_of(uid: int) -> float:
	if not _fired.has(uid):
		return 0.0
	return clampf(1.0 - (Time.get_ticks_msec() - int(_fired[uid])) / 1000.0 / float(cfg().get("flash_s", 0.35)), 0.0, 1.0)


## The gun that is lit by the mouse: the bar slot's, else the one on the ship.
func hover_uid() -> int:
	return bar_hover if bar_hover >= 0 else world_hover


## Is gun `w` outlined now: it is not an auto gun, and its group's button is down.
func outlined(w: Dictionary) -> bool:
	return str(w.get("aim", "fixed")) == "fixed" and bool(held.get(int(w["group"]), false))


## Next group of fixed gun `uid` of `components` after a right-click: 1 -> 2 -> 1. Stored as the mount's own choice (0 when it is the
## kind's default). Returns the new effective group, 0 when the gun fires by itself (swivels and turrets stay auto).
static func cycle(components, weapons, uid: int) -> int:
	if not components.instances.has(uid):
		return 0
	var id: String = components.instances[uid]["id"]
	if not weapons.has(id) or weapons.def(id)["turret"]:
		return 0
	var now: int = weapons.group_of(id, components.group_choice(uid))
	var next := 2 if now == 1 else 1
	components.set_group_choice(uid, 0 if next == weapons.group_of(id) else next)
	return next


# --- where a gun is on the ship ---------------------------------------------------------------------

## The local cell rect of mount `m` (uid `uid`) of ship `co`: its outside half; a virtual mount a cell about its pivot.
static func out_rect(co, uid: int, m: Dictionary) -> Rect2:
	if not m["virtual"] and co.ship.components.instances.has(uid):
		var cells: Array = co.ship.components.instances[uid]["out_cells"]
		if not cells.is_empty():
			var r := Rect2(Vector2(cells[0]), Vector2.ONE)
			for c in cells:
				r = r.expand(Vector2(c)).expand(Vector2(c) + Vector2.ONE)
			return r
	return Rect2(Vector2(m["pos"]) - Vector2(0.5, 0.5), Vector2.ONE)


## The chip's centre in the world, and the outline's corners.
static func chip_world(arena, idx: int, uid: int, m: Dictionary) -> Vector2:
	return arena.local_to_world(idx, out_rect(arena.ships[idx], uid, m).get_center())


static func outline_world(arena, idx: int, uid: int, m: Dictionary) -> PackedVector2Array:
	var r := out_rect(arena.ships[idx], uid, m).grow(0.12)
	var pts := PackedVector2Array()
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		pts.append(arena.local_to_world(idx, p))
	return pts


## Chip height in world units for a camera that scales by `zoom`: kept between chip_min and chip_max px on screen.
static func chip_height(zoom: float) -> float:
	var s := clampf(zoom * 44.0, float(cfg().get("chip_min", 14)), float(cfg().get("chip_max", 22)))
	return s / maxf(zoom, 0.01)


## The gun under world point `p` (its chip or its outline), -1 when none. `zoom`: the camera's.
func gun_at(session, p: Vector2, zoom: float) -> int:
	var arena = session.arena
	var co = arena.ships[session.PLAYER]
	var h := chip_height(zoom)
	for w in session.weapons():
		var m: Dictionary = co.mounts[w["uid"]]
		if p.distance_to(chip_world(arena, session.PLAYER, w["uid"], m)) <= h * 0.9 or Geometry2D.is_point_in_polygon(p, outline_world(arena, session.PLAYER, w["uid"], m)):
			return w["uid"]
	return -1


# --- drawing -----------------------------------------------------------------------------------------

## The player's guns over the ship in a fight: chips, held-group outlines, flashes, and the hovered gun's arc. `c` is the world
## node; `zoom` the camera's; `aim` the world point the mouse aims at.
func draw_ship(c: CanvasItem, session, zoom: float, aim: Vector2) -> void:
	var arena = session.arena
	var P: int = session.PLAYER
	var co = arena.ships[P]
	var px := 1.0 / maxf(zoom, 0.01)
	var h := chip_height(zoom)
	var hov := hover_uid()
	var list: Array = session.weapons()
	if hov >= 0 and co.mounts.has(hov):
		_draw_arc(c, arena, P, hov, px)
	for i in list.size():
		var w: Dictionary = list[i]
		var uid: int = w["uid"]
		var m: Dictionary = co.mounts[uid]
		var st: Dictionary = session.slot_state(uid, aim)
		var sty := style(w)
		var auto: bool = str(w["aim"]) != "fixed"
		var bears: bool = st["status"] in OKAY
		var fl := flash_of(uid)
		var lit := outlined(w)
		var col: Color = sty["color"]
		if lit or uid == hov or fl > 0.0:
			var a := 1.0 if bears else 0.38
			var pts := outline_world(arena, P, uid, m)
			pts.append(pts[0])
			c.draw_polyline(pts, Color(col, a), (3.0 if lit else 2.0) * px)
			if lit and bears:
				c.draw_polyline(pts, Color(1, 1, 1, 0.35), 1.0 * px)
		var at := chip_world(arena, P, uid, m)
		var dim := auto and not auto_on
		draw_chip(c, at, h, sty, key_of(i), 0.45 if dim else 1.0, fl, uid == hov)
		if (lit or uid == hov) and not bears:
			draw_reason(c, at + Vector2(h * 1.35, -h * 0.55), h * 0.34, str(st["status"]), BAD if str(st["status"]) in ["malfunction", "unpowered", "wrecked", "disabled", "offline"] else GREY.lightened(0.3))


## The firing arc of gun `uid` as a wedge on the ship (red fixed, yellow swivel, blue turret).
func _draw_arc(c: CanvasItem, arena, idx: int, uid: int, px: float) -> void:
	var m: Dictionary = arena.ships[idx].mounts[uid]
	var d: Dictionary = arena.weapons.def(m["id"])
	var a: Dictionary = arena.weapons.aim_of(d)
	var col: Color = ARC_COLORS.get(a["class"], ARC_COLORS["fixed"])
	var half := minf(deg_to_rad(float(a["arc"]) * 0.5), PI)
	var radius := clampf(float(d["range"]) * 0.35, 140.0, 420.0)
	var pivot: Vector2 = arena.local_to_world(idx, m["pos"])
	var dir: float = Vector2(m["dir"]).rotated(arena.ships[idx].flight.angle).angle()
	var rim := PackedVector2Array()
	var steps := maxi(2, ceili(half * 2.0 / deg_to_rad(6.0)))
	for i in steps + 1:
		rim.append(pivot + Vector2.from_angle(dir - half + 2.0 * half * i / steps) * radius)
	if half < PI - 0.01:
		var fan := PackedVector2Array([pivot])
		fan.append_array(rim)
		c.draw_colored_polygon(fan, Color(col, 0.2))
		c.draw_polyline(PackedVector2Array([rim[0], pivot, rim[rim.size() - 1]]), Color(col, 0.7), 1.5 * px)
	else:
		c.draw_colored_polygon(rim, Color(col, 0.16))
	c.draw_polyline(rim, Color(col, 0.8), 1.5 * px)


## One chip centred on `at`, `h` tall: the number key, then the group's mark; edged in the group colour. `alpha` dims it, `flash`
## (0..1) lights it, `hot` thickens the edge.
static func draw_chip(c: CanvasItem, at: Vector2, h: float, sty: Dictionary, key: int, alpha := 1.0, flash := 0.0, hot := false) -> Rect2:
	var col: Color = sty["color"]
	var w := h * (1.85 if key > 0 else 1.0)
	var r := Rect2(at - Vector2(w, h) / 2.0, Vector2(w, h))
	c.draw_rect(r, Color(BG, BG.a * alpha))
	if flash > 0.0:
		c.draw_rect(r.grow(h * 0.18 * flash), Color(col, 0.55 * flash * alpha))
		c.draw_rect(r, Color(col, 0.6 * flash * alpha))
	c.draw_rect(r, Color(col, alpha), false, maxf(1.0, h * (0.14 if hot else 0.09)))
	var mx := r.end.x - h * 0.5
	if key > 0:
		var fs := maxi(4, roundi(h * 0.72))
		c.draw_string(ThemeDB.fallback_font, Vector2(r.position.x + h * 0.2, r.end.y - h * 0.22), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(TEXT, alpha))
	else:
		mx = at.x
	draw_mark(c, Vector2(mx, at.y), h * 0.27, str(sty["mark"]), Color(col, alpha))
	return r


## A group's mark: dot (LMB), ring (RMB), arc over a dot (fires by itself) - three shapes that differ without colour.
static func draw_mark(c: CanvasItem, at: Vector2, r: float, mark: String, col: Color) -> void:
	var wd := maxf(1.0, r * 0.45)
	match mark:
		"ring":
			c.draw_arc(at, r * 0.85, 0.0, TAU, 20, col, wd)
		"arc":
			c.draw_arc(at + Vector2(0.0, r * 0.35), r * 1.05, deg_to_rad(205.0), deg_to_rad(335.0), 12, col, wd)
			c.draw_circle(at + Vector2(0.0, r * 0.45), r * 0.3, col)
		_:
			c.draw_circle(at, r, col)


## A small icon for why a gun cannot bear (see REASON_ICON), `r` big, centred on `at`.
static func draw_reason(c: CanvasItem, at: Vector2, r: float, status: String, col: Color) -> void:
	var wd := maxf(1.0, r * 0.3)
	c.draw_circle(at, r * 1.35, Color(BG, 0.9))
	match REASON_ICON.get(status, "bang"):
		"arc":  # a wedge with the target outside it
			c.draw_polyline(PackedVector2Array([at + Vector2(-r * 0.8, r * 0.7), at + Vector2(0.0, -r * 0.7), at + Vector2(r * 0.8, r * 0.7)]), col, wd)
		"clock":
			c.draw_arc(at, r, 0.0, TAU, 14, col, wd)
			c.draw_polyline(PackedVector2Array([at + Vector2(0.0, -r * 0.6), at, at + Vector2(r * 0.45, r * 0.2)]), col, wd)
		"bolt":
			c.draw_polyline(PackedVector2Array([at + Vector2(r * 0.3, -r), at + Vector2(-r * 0.4, r * 0.1), at + Vector2(r * 0.4, r * 0.1), at + Vector2(-r * 0.3, r)]), col, wd)
		"cross":
			c.draw_line(at + Vector2(-r * 0.7, -r * 0.7), at + Vector2(r * 0.7, r * 0.7), col, wd)
			c.draw_line(at + Vector2(r * 0.7, -r * 0.7), at + Vector2(-r * 0.7, r * 0.7), col, wd)
		"slash":
			c.draw_arc(at, r * 0.85, 0.0, TAU, 14, col, wd)
			c.draw_line(at + Vector2(-r * 0.7, r * 0.7), at + Vector2(r * 0.7, -r * 0.7), col, wd)
		_:
			c.draw_line(at + Vector2(0.0, -r), at + Vector2(0.0, r * 0.25), col, wd)
			c.draw_circle(at + Vector2(0.0, r * 0.75), wd * 0.8, col)


## The mouse icon of a group header: a small mouse with the fired button filled (1 left, 2 right); 3 (auto) a mouse with none.
static func draw_mouse(c: CanvasItem, r: Rect2, group: int, col: Color) -> void:
	c.draw_rect(r, Color(0.1, 0.13, 0.18), true)
	c.draw_rect(r, Color(col, 0.9), false, 1.5)
	var mid := r.position.x + r.size.x / 2.0
	var top := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45))
	if group == 1:
		c.draw_rect(Rect2(top.position, Vector2(top.size.x / 2.0, top.size.y)), col)
	elif group == 2:
		c.draw_rect(Rect2(Vector2(mid, top.position.y), Vector2(top.size.x / 2.0, top.size.y)), col)
	c.draw_line(Vector2(mid, r.position.y), Vector2(mid, top.end.y), Color(col, 0.9), 1.0)
	c.draw_line(Vector2(r.position.x, top.end.y), Vector2(r.end.x, top.end.y), Color(col, 0.9), 1.0)
