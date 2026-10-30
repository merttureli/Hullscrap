extends RefCounted
## Draws one crew member as a top-down person. draw() uses the layered pixel sprite of
## art/crew/<species>/ (legs turned to the way they walk; torso, arms and the held item turned to
## where they aim; the outfit tinted by their palette's "suit" colour through the colour masks; a
## 1 px shadow) and falls back to the placeholder, drawn in code about 3 cells across, when that art
## is missing. Static: draw(canvas, ...) draws onto any CanvasItem inside its _draw().
## Placeholder local frame: +x is where the person faces, +y their right-hand side, in cells;
## everything is turned by `facing` and scaled by `cell_px`.

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const SEGMENTS := 20  ## points on a drawn ellipse
const SCALE := 1.15  ## the figure below is drawn in units of this many cells: arms and legs reach about 3 cells across
const STRIDE := PI  ## walk phase (radians) per cell walked: one full leg cycle every 2 cells
const IDLE_SPEED := 2.2  ## radians per second of the breathing bob
const TURN_RATE := 14.0  ## how fast the drawn legs follow the direction of movement
const AIM_RATE := 18.0  ## how fast the drawn torso follows the aim
const SHADOW := Color(0, 0, 0, 0.32)
const DOWN_TINT := Color(0.5, 0.5, 0.55)
const HAND_FRESH := 0.4  ## seconds a hand job (the player holding E) counts as going on after its last tick
const JAB := 1.5  ## source px a tool jabs forward while working
## The held item by the job; anything else with a job holds nothing, no job holds a pistol for the player.
const JOB_ITEMS := {"extinguish": "extinguisher", "repair_breach": "wrench", "repair_component": "wrench"}


## Update the drawing state `a` of crew member `m` by `dt` seconds. `a`: {last, phase, angle (the
## way they move), aim (the way the torso points), moving}. `aim`: the wanted aim angle (radians).
## The walk phase grows with the distance walked (with time when standing, for the breathing bob).
static func animate(a: Dictionary, m, dt: float, aim: float) -> void:
	var moved: float = (m.pos - a["last"]).length()
	a["moving"] = moved > 0.0005
	a["phase"] += (moved * STRIDE) if a["moving"] else (dt * IDLE_SPEED)
	a["angle"] = lerp_angle(a["angle"], m.facing.angle(), 1.0 - exp(-TURN_RATE * dt))
	a["aim"] = lerp_angle(a["aim"], aim, 1.0 - exp(-AIM_RATE * dt))
	a["last"] = m.pos


## A fresh drawing state for `m`.
static func new_state(m) -> Dictionary:
	return {"last": m.pos, "phase": 0.0, "angle": m.facing.angle(), "aim": m.facing.angle(), "moving": false}


## The point in cell units that the job of `m` is about (the fire or breach cell, the middle of a
## part or station), or null when they have no such job.
static func job_target(m) -> Variant:
	var job: Dictionary = m.job
	if job.is_empty() or job.get("type", "") == "rest":
		return null
	if job.get("cells") is Array and not job["cells"].is_empty():
		var sum := Vector2.ZERO
		for c in job["cells"]:
			sum += Vector2(c) + Vector2(0.5, 0.5)
		return sum / job["cells"].size()
	if job.get("cell") is Vector2i:
		return Vector2(job["cell"]) + Vector2(0.5, 0.5)
	return null


## The angle (radians, 0 = right) a crew member who is not steered by a mouse aims at: what their job
## is about once they have arrived, else the way they walk.
static func job_aim(m) -> float:
	var target: Variant = job_target(m)
	if target != null and m.path.is_empty():
		var d: Vector2 = target - m.pos
		if d.length() > 0.05:
			return d.angle()
	return m.facing.angle()


## The id of the item `m` holds: by the job (see JOB_ITEMS), a pistol for the player with no job, else "".
## `clock`: the ship's clock, to tell a hand job still going on from a stale one.
static func item_for(m, clock: float) -> String:
	if m.is_down():
		return ""
	var job: Dictionary = m.job
	var type := str(job.get("type", ""))
	if job.get("hand", false) and clock - float(job.get("t", -1.0e9)) > HAND_FRESH:
		type = ""  # E let go: the job record is stale
	if type != "":
		return str(JOB_ITEMS.get(type, ""))
	return "pistol" if m.is_player else ""


## True while `m` is at a job that uses a tool (arms jab): they have arrived, or the player is holding E.
static func is_working(m, clock: float) -> bool:
	if m.is_down() or not JOB_ITEMS.has(str(m.job.get("type", ""))):
		return false
	if m.job.get("hand", false):
		return clock - float(m.job.get("t", -1.0e9)) <= HAND_FRESH
	return m.path.is_empty()


## Draw a person centred on `centre_px`. `pose`: {species ("human"), move (angle they walk, radians,
## 0 = right), aim (angle the torso points), phase (walk phase, radians), moving, item (id or ""),
## down, work (the tool jabs), t (seconds)}. `palette`: "suit" colour tints the outfit.
static func draw(canvas: CanvasItem, centre_px: Vector2, pose: Dictionary, palette: Dictionary, cell_px: float) -> void:
	var sheet = Art.crew(str(pose.get("species", "human")))
	if sheet == null:
		var facing := float(pose.get("aim", pose.get("move", 0.0)))
		draw_person(canvas, centre_px, facing, float(pose.get("phase", 0.0)), bool(pose.get("moving", false)), palette, cell_px)
		return
	var k := cell_px / SpriteSheet.SRC_CELL
	var layers := plan(sheet, pose)
	var base := Color(DOWN_TINT if pose.get("down", false) else Color.WHITE)
	for l in layers:  # the shadow first: the same silhouettes, one source px down and right
		_blit(canvas, l, l["sheet"].texture, centre_px + Vector2(k, k), k, SHADOW)
	var suit := Color(palette.get("suit", "#33c6d6"))
	for l in layers:
		_blit(canvas, l, l["sheet"].tinted(suit) if l["tint"] else l["sheet"].texture, centre_px, k, base)


## The layers to draw, back to front: [{layer, sheet, frame, angle (radians, to rotate by), off
## (source px from the body centre), tint (colour mask applies)}]. Legs turn to `move`, everything
## else to `aim`; the walk frame follows `phase` (the stand frame when not moving or down).
static func plan(sheet, pose: Dictionary) -> Array:
	var down: bool = pose.get("down", false)
	var move := float(pose.get("move", pose.get("aim", 0.0)))
	var aim := float(pose.get("aim", move))
	var out := []
	var legs = sheet.layers["legs"]
	var frame: int = legs.start_of("stand")
	if pose.get("moving", false) and not down and legs.has_anim("walk"):
		var n: int = legs.anims["walk"]["count"]
		frame = legs.start_of("walk") + int(fposmod(float(pose.get("phase", 0.0)), TAU) / TAU * n) % n
	out.append({"layer": "legs", "sheet": legs, "frame": frame, "angle": move + PI / 2.0, "off": Vector2.ZERO, "tint": true})
	out.append({"layer": "torso", "sheet": sheet, "frame": 0, "angle": aim + PI / 2.0, "off": Vector2.ZERO, "tint": true})
	var arms = sheet.layers.get("arms")
	if arms == null:
		return out
	var held := held_item(pose)
	var cls: String = held["sheet"].pose if not held.is_empty() and held["sheet"].pose != "" else "tool"
	if held.is_empty() or not sheet.poses.has(cls) or sheet.poses[cls]["mount"] == null:
		cls = "unarmed"
		held = {}
	var jab := Vector2(0.0, -absf(sin(float(pose.get("t", 0.0)) * 9.0)) * JAB) if pose.get("work", false) and not down else Vector2.ZERO
	out.append({"layer": "arms", "sheet": arms, "frame": sheet.poses[cls]["frame"], "angle": aim + PI / 2.0, "off": jab, "tint": true})
	if not held.is_empty():
		var it = held["sheet"]
		out.append({"layer": "item", "sheet": it, "frame": 0, "angle": aim + PI / 2.0,
			"off": sheet.poses[cls]["mount"] - it.anchor_c("grip") + jab, "tint": false, "id": held["id"]})
	return out


## {id, sheet} of the item the pose asks for; the wrench stands in for an extinguisher with no art;
## empty when there is none (no item, a missing sheet, or a person who is down).
static func held_item(pose: Dictionary) -> Dictionary:
	var id := str(pose.get("item", ""))
	if id == "" or pose.get("down", false):
		return {}
	var it = Art.item(id)
	if it == null and id == "extinguisher":
		id = "wrench"
		it = Art.item(id)
	return {} if it == null else {"id": id, "sheet": it}


## One layer: frame `l["frame"]` of `tex` (laid out like l["sheet"]), turned by l["angle"] about the
## body centre `at` and offset by l["off"], at `k` px per source px.
static func _blit(canvas: CanvasItem, l: Dictionary, tex: Texture2D, at: Vector2, k: float, mod: Color) -> void:
	var sh = l["sheet"]
	canvas.draw_set_transform(at, l["angle"], Vector2(k, k))
	var top_left: Vector2 = l["off"] - sh.centre() - Vector2(0.5, 0.5)
	canvas.draw_texture_rect_region(tex, Rect2(top_left, Vector2(sh.frame)), sh.region(l["frame"]), mod)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)




## Draw a person centred on `centre_px` (pixels, in the canvas' own coordinates).
## `facing`: radians, 0 = right, like Vector2.angle(). `walk_phase`: radians; advance it with the
## distance walked while `moving`, and with time while standing (it drives the breathing bob).
## `palette`: "suit", "hair" and "tool" colours (Color or "#rrggbb"), optional "skin".
static func draw_person(canvas: CanvasItem, centre_px: Vector2, facing: float, walk_phase: float,
		moving: bool, palette: Dictionary, cell_px: float) -> void:
	var suit := Color(palette.get("suit", "#33c6d6"))
	var hair := Color(palette.get("hair", "#2a2320"))
	var tool := Color(palette.get("tool", "#d7dce4"))
	var skin := Color(palette.get("skin", "#e9c29c"))
	var trim := suit.darkened(0.45)
	var boot := Color("#2b2f3b")
	var u := cell_px * SCALE
	var xf := Transform2D(facing, centre_px)
	var stride := sin(walk_phase) if moving else 0.0  # -1..1: right leg forward at +1
	var breath := 0.0 if moving else sin(walk_phase)
	var twist := Transform2D(stride * 0.10, Vector2.ZERO)  # shoulders turn against the legs
	var body := xf * twist

	# Shadow: not turned, the light stays put.
	_ellipse(canvas, Transform2D(0.0, centre_px + Vector2(0.10, 0.14) * u), Vector2.ZERO, Vector2(1.15, 0.98) * u, Color(0, 0, 0, 0.22))

	# Legs: capsules from the hips to the boots, swinging against each other. Standing, the toes
	# just peek out in front of the chest; walking, the forward boot comes well out.
	for s in [-1.0, 1.0]:
		var hip := Vector2(-0.10, s * 0.30) * u
		var foot := Vector2(0.46 + s * stride * 0.75, s * 0.40) * u
		_capsule(canvas, xf, hip, foot, 0.21 * u, suit.darkened(0.3), true)
		canvas.draw_circle(xf * foot, 0.25 * u, Color(0, 0, 0, 0.45), true, -1.0, true)
		canvas.draw_circle(xf * foot, 0.22 * u, boot, true, -1.0, true)
		canvas.draw_circle(xf * (foot + Vector2(0.06, 0.0) * u), 0.11 * u, boot.lightened(0.22), true, -1.0, true)  # toe cap

	# Backpack: a life-support pack behind the shoulders, the cue for which way is back.
	var pack := Rect2(Vector2(-0.82, -0.30) * u, Vector2(0.44, 0.60) * u)
	_ellipse(canvas, body, pack.get_center(), pack.size / 2.0 * 1.1, Color(0, 0, 0, 0.4))
	_ellipse(canvas, body, pack.get_center(), pack.size / 2.0, suit.darkened(0.38))
	canvas.draw_circle(body * (Vector2(-0.64, 0.0) * u), 0.07 * u, Color("#7dff9b"), true, -1.0, true)

	# Torso: rounded shoulders in the suit colour, a darker trim round the edge, a lighter chest.
	var rx := 0.44 + breath * 0.02
	var ry := 0.80 + breath * 0.03
	_ellipse(canvas, body, Vector2.ZERO, Vector2(rx, ry) * u, suit)
	_ellipse(canvas, body, Vector2(0.07, 0.0) * u, Vector2(rx * 0.55, ry * 0.62) * u, suit.lightened(0.16))
	_outline(canvas, body, Vector2.ZERO, Vector2(rx, ry) * u, trim, 0.07 * u)
	# Belt across the back of the waist, with a buckle.
	canvas.draw_line(body * (Vector2(-0.22, -0.66) * u), body * (Vector2(-0.22, 0.66) * u), Color("#3a2d25"), 0.15 * u)
	canvas.draw_circle(body * (Vector2(-0.22, 0.0) * u), 0.09 * u, Color("#cdb87c"), true, -1.0, true)

	# Arms swing against the legs. The right hand carries the tool out in front.
	var hands := {}
	for s in [-1.0, 1.0]:
		var shoulder := Vector2(0.02, s * 0.80) * u
		var hand := Vector2(0.60 - stride * 0.30, 0.74) * u if s > 0.0 else Vector2(0.22 + stride * 0.50, -0.98) * u
		hands[s] = hand
		_capsule(canvas, body, shoulder, hand, 0.17 * u, suit.darkened(0.08), true)
		_capsule(canvas, body, shoulder.lerp(hand, 0.72), hand, 0.175 * u, trim)  # cuff
	for s in [-1.0, 1.0]:
		canvas.draw_circle(body * (Vector2(0.02, s * 0.80) * u), 0.27 * u, suit.lightened(0.05), true, -1.0, true)  # shoulder pad
		canvas.draw_arc(body * (Vector2(0.02, s * 0.80) * u), 0.27 * u, 0.0, TAU, 16, trim, 0.06 * u, true)

	# Head: hair (or a helmet) over the head with the face showing at the front.
	var head := Vector2(0.06 + breath * 0.015, 0.0) * u
	canvas.draw_circle(body * head, 0.43 * u, Color(0, 0, 0, 0.45), true, -1.0, true)  # edge
	canvas.draw_circle(body * head, 0.405 * u, hair.lightened(0.4), true, -1.0, true)  # rim light, so dark hair shows on a dark floor
	canvas.draw_circle(body * head, 0.37 * u, hair, true, -1.0, true)
	canvas.draw_arc(body * head, 0.24 * u, body.get_rotation() + PI * 0.65, body.get_rotation() + PI * 1.35, 8, hair.lightened(0.3), 0.07 * u, true)
	_ellipse(canvas, body, head + Vector2(0.23, 0.0) * u, Vector2(0.17, 0.27) * u, skin)
	for s in [-1.0, 1.0]:  # eyes, the face direction mark
		canvas.draw_circle(body * (head + Vector2(0.31, s * 0.10) * u), 0.036 * u, Color("#1b1f2a"), true, -1.0, true)

	# Hands, and the wrench in the right one.
	var grip: Vector2 = hands[1.0]
	var aim := -0.10 - stride * 0.12  # radians off straight ahead
	var tip := grip + Vector2.from_angle(aim) * 0.92 * u
	canvas.draw_line(body * grip, body * tip, tool, 0.12 * u, true)
	canvas.draw_arc(body * tip, 0.17 * u, body.get_rotation() + aim + 0.75, body.get_rotation() + aim + TAU - 0.75, 12, tool, 0.10 * u, true)
	for s in [-1.0, 1.0]:
		canvas.draw_circle(body * hands[s], 0.15 * u, skin, true, -1.0, true)


## A filled ellipse with radii `r` (pixels) centred on `c` (pixels) in the frame `xf`.
static func _ellipse(canvas: CanvasItem, xf: Transform2D, c: Vector2, r: Vector2, col: Color) -> void:
	canvas.draw_colored_polygon(_ring(xf, c, r, false), col)


static func _outline(canvas: CanvasItem, xf: Transform2D, c: Vector2, r: Vector2, col: Color, width: float) -> void:
	canvas.draw_polyline(_ring(xf, c, r, true), col, width, true)


static func _ring(xf: Transform2D, c: Vector2, r: Vector2, closed: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in SEGMENTS + (1 if closed else 0):
		var a := TAU * i / SEGMENTS
		pts.append(xf * (c + Vector2(cos(a) * r.x, sin(a) * r.y)))
	return pts


## A thick line with round ends from `a` to `b` (pixels in the frame `xf`), `r` pixels thick each
## side; `edged` puts a soft dark edge round it so it stands out from the floor.
static func _capsule(canvas: CanvasItem, xf: Transform2D, a: Vector2, b: Vector2, r: float, col: Color, edged := false) -> void:
	if edged:
		_capsule(canvas, xf, a, b, r * 1.22, Color(0, 0, 0, 0.4))
	canvas.draw_line(xf * a, xf * b, col, r * 2.0, true)
	canvas.draw_circle(xf * a, r, col, true, -1.0, true)
	canvas.draw_circle(xf * b, r, col, true, -1.0, true)
