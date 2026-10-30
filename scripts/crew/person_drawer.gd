extends RefCounted
## Draws one crew member as a top-down person, about 3 cells across, in code (placeholder until real
## art lands). Static: `draw_person(canvas, ...)` draws onto any CanvasItem inside its _draw().
## Local frame while drawing: +x is where the person faces, +y their right-hand side, in cells;
## everything is turned by `facing` and scaled by `cell_px`.

const SEGMENTS := 20  ## points on a drawn ellipse
const SCALE := 1.15  ## the figure below is drawn in units of this many cells: arms and legs reach about 3 cells across


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
