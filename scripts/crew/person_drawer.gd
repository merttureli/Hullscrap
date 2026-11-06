extends RefCounted
## Draws one crew member as a top-down person. draw() uses the layered pixel sprite of
## art/crew/<species>/ (legs turned to the way they walk; torso, arms and the held item turned to
## where they aim; the outfit tinted by their palette's "suit" colour through the colour masks; a
## 1 px shadow) and falls back to the placeholder, drawn in code about 3 cells across, when that art
## is missing. Static: draw(canvas, ...) draws onto any CanvasItem inside its _draw().
## Placeholder local frame: +x is where the person faces, +y their right-hand side, in cells;
## everything is turned by `facing` and scaled by `cell_px`.
## Rig kinds (art/README.md, crew.json `kind`; RIGS has the frames): normal, large (grundl), small (art fits one cell:
## the 1x1 body of the trait `body` 1) and floating, which has no walk cycle: its `legs` layer is a trailing tail
## (the `float` animation, played by time, else the stand frame) and the whole body bobs over its shadow.

const Art = preload("res://scripts/view/art.gd")
const SpriteSheet = preload("res://scripts/view/sprite_sheet.gd")
const Power = preload("res://scripts/sim/power.gd")
const Site = preload("res://scripts/board/site.gd")
static var _glows := {}  # canvas instance id -> its GearGlow
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
const BOB := 1.5  ## source px a floating body rises and sinks about its middle
const BOB_RATE := 2.4  ## radians a second of that bob
const HOVER := 1.0  ## source px further than usual that the shadow of a floating body sits
## The frame and pivot of each rig kind in source px (art/README.md): every rig is a square frame turned about its middle.
const GEAR_K := 0.1  ## the placeholder person draws gear this many person-units (SCALE cells) per source px of boarding.json `looks`
const RIGS := {"normal": [33, 16], "large": [49, 24], "small": [25, 12], "floating": [49, 24]}
const JOB_ITEMS := {"extinguish": "extinguisher", "repair_breach": "wrench", "repair_component": "wrench", "repair_block": "wrench"}


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


## The kind of rig a crew sheet is (its crew.json `kind`; "normal" when it says none).
static func rig_kind(sheet) -> String:
	return str(sheet.meta.get("kind", "normal"))


## How far up (negative: down) a floating body is lifted at the pose's time `t`, in source px; 0 for one lying down.
static func bob(pose: Dictionary) -> float:
	return 0.0 if pose.get("down", false) else sin(float(pose.get("t", 0.0)) * BOB_RATE) * BOB


## The id of the item `m` holds: by the job (see JOB_ITEMS), a pistol for the player with no job, the
## species' sidearm (CrewMember.sidearm) for anyone else idle in a fight (`in_combat`), else "".
## `clock`: the ship's clock, to tell a hand job still going on from a stale one.
static func item_for(m, clock: float, in_combat := false) -> String:
	if m.is_down():
		return ""
	var job: Dictionary = m.job
	var type := str(job.get("type", ""))
	if job.get("hand", false) and clock - float(job.get("t", -1.0e9)) > HAND_FRESH:
		type = ""  # E let go: the job record is stale
	if type != "":
		return str(JOB_ITEMS.get(type, ""))
	if m.is_player:
		return "pistol"
	return m.sidearm() if in_combat and job.is_empty() else ""


## True while `m` is at a job that uses a tool (arms jab): they have arrived, or the player is holding E.
static func is_working(m, clock: float) -> bool:
	if m.is_down() or not JOB_ITEMS.has(str(m.job.get("type", ""))):
		return false
	if m.job.get("hand", false):
		return clock - float(m.job.get("t", -1.0e9)) <= HAND_FRESH
	return m.path.is_empty()


## Draw a person centred on `centre_px`. `pose`: {species ("human"), move (angle they walk, radians,
## 0 = right), aim (angle the torso points), phase (walk phase, radians), moving, item (id or ""),
## down, work (the tool jabs), helmet, head (the name of a head frame to wear), t (seconds), drone (a repair
## drone: draw_drone, with `off` for no power)}. `palette`: "suit" colour tints the outfit.
static func draw(canvas, centre_px: Vector2, pose: Dictionary, palette: Dictionary, cell_px: float) -> void:
	if pose.get("drone", false):
		draw_drone(canvas, centre_px, pose, cell_px)
		return
	var sheet = art_of(pose)
	if sheet == null:
		var facing := float(pose.get("aim", pose.get("move", 0.0)))
		draw_person(canvas, centre_px, facing, float(pose.get("phase", 0.0)), bool(pose.get("moving", false)), palette, cell_px, str(pose.get("body", "")))
		return
	var k := cell_px / SpriteSheet.SRC_CELL
	var layers := plan(sheet, pose)
	var base := Color(DOWN_TINT if pose.get("down", false) else Color.WHITE)
	var floating := rig_kind(sheet) == "floating"
	var lift := Vector2(0.0, -bob(pose) * k) if floating else Vector2.ZERO  # a floating body rides over its shadow
	for l in layers:  # the shadow first: the same silhouettes, one source px down and right (a floating body: one more)
		if l.has("glow"):
			continue
		_blit(canvas, l, l["sheet"].texture, centre_px + Vector2(k, k) * (1.0 + HOVER if floating else 1.0), k, SHADOW)
	var suit := Color(palette.get("suit", "#33c6d6"))
	var gear := str(pose.get("body", ""))
	var aim := float(pose.get("aim", pose.get("move", 0.0)))
	var flat := gear != "" and gear_art(sheet, gear) == null  # a rig the gear art does not fit: the flat look
	var worn := false
	var glow := []
	for l in layers:
		if l.has("glow"):  # glow is additive: collected, drawn over everything
			glow.append(l)
			continue
		if flat and not worn and l["layer"] in ["arms", "head"]:  # worn over the torso, under the arms and the head
			draw_gear(canvas, centre_px + lift, aim, k, gear, false, base)
			worn = true
		_blit(canvas, l, l["sheet"].tinted(suit) if l["tint"] else l["sheet"].texture, centre_px + lift, k, base)
	if flat:
		draw_gear(canvas, centre_px + lift, aim, k, gear, true, base)
	if not glow.is_empty() and canvas is CanvasItem:
		_glow_of(canvas).add(glow, centre_px + lift, k)


## The body gear art (Art.gear) of `item` on crew art `sheet`: the `art` id of its look (boarding.json `looks`) when the rig fits it, else null.
static func gear_art(sheet, item: String) -> Variant:
	var id := str(gear_look(item).get("art", ""))
	if id == "":
		return null
	var own = Art.gear_rig(id, str(sheet.meta.get("species", "")))  # made from this rig's own sprites
	if own != null:
		return own
	return Art.gear(id) if Art.gear_fits(sheet) else null


## The additive layer that shows the glow of gear drawn on `canvas`: a child node, made on first use.
static func _glow_of(canvas: CanvasItem) -> Node2D:
	var id := canvas.get_instance_id()
	var g = _glows.get(id)
	if g == null or not is_instance_valid(g) or g.get_parent() != canvas:
		g = GearGlow.new()
		_glows[id] = g
		canvas.add_child.call_deferred(g)
	return g


## Additive glow quads of the gear drawn on one canvas this frame (GlowLayer, which fades them when nobody asks any more).
class GearGlow extends "res://scripts/view/glow_layer.gd":
	var stamp := -1

	## Add the glow layers `ls` (plan() entries) of one person drawn at `at`, `k` px per source px.
	func add(ls: Array, at: Vector2, k: float) -> void:
		var now := Engine.get_frames_drawn()
		if stamp != now:
			quads = []
			stamp = now
		for l in ls:
			var g = l["glow"]
			quads.append({"tex": g.texture, "rect": Rect2(l["pos"], Vector2(g.frame)), "src": g.region(l["glow_frame"]), "xf": Transform2D(l["angle"], Vector2(k, k), 0.0, at), "mod": Color.WHITE})
		queue_redraw()

	## Nobody drew glow here this frame: clear it.
	func _process(_dt: float) -> void:
		if not quads.is_empty() and stamp < Engine.get_frames_drawn() - 1:
			quads = []
			queue_redraw()


## The look of body gear `item` (boarding.json `looks`), {} for none or for an item with no look.
static func gear_look(item: String) -> Dictionary:
	var looks = Site.config().get("looks", {})
	var d = looks.get(item, {}) if item != "" else {}
	return d if d is Dictionary else {}


## The body gear `m` wears ("" for none): the `body` of their kit.
static func gear_of(m) -> String:
	return str(m.kit.get("body", "")) if m != null and not m.kit.is_empty() else ""


## The colour of `tone` ("main", "dark", "light" or a #hex) in the gear look `d`.
static func _tone(d: Dictionary, tone: String) -> Color:
	var main := Color(str(d.get("color", "#888888")))
	match tone:
		"main":
			return main
		"dark":
			return Color(str(d["dark"])) if d.has("dark") else main.darkened(0.45)
		"light":
			return Color(str(d["light"])) if d.has("light") else main.lightened(0.3)
	return Color(tone)


## Draw body gear `item` on a person at `centre_px`, turned to `angle` (radians, 0 = facing right), `k` px per source px: the pieces of its
## look (data/boarding.json `looks`) that go under the head (`over_head` false) or over it. `mod` tints it (a person who is down).
static func draw_gear(canvas, centre_px: Vector2, angle: float, k: float, item: String, over_head: bool, mod := Color.WHITE) -> void:
	var d := gear_look(item)
	if d.is_empty():
		return
	canvas.draw_set_transform(centre_px, angle + PI / 2.0, Vector2(k, k))
	for p in d.get("pieces", []):
		if bool(p.get("over_head", false)) != over_head:
			continue
		var col := _tone(d, str(p.get("tone", "main")))
		col.a *= float(p.get("alpha", 1.0))
		col *= mod
		var at := Vector2(float(p["at"][0]), float(p["at"][1]))
		var edge := _tone(d, "dark") * mod
		match str(p.get("shape", "rect")):
			"circle":
				canvas.draw_circle(at, float(p["r"]), col)
				if p.get("edge", false):
					canvas.draw_arc(at, float(p["r"]), 0.0, TAU, 16, edge, 1.0, true)
			"ring":
				canvas.draw_arc(at, float(p["r"]), 0.0, TAU, 20, col, 1.2, true)
			_:
				var r := Rect2(at, Vector2(float(p["size"][0]), float(p["size"][1])))
				canvas.draw_rect(r, col)
				if p.get("edge", false):
					canvas.draw_rect(r, edge, false, 1.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The crew art the pose asks for (art/crew/<species>/), or null: then the placeholder is drawn.
static func art_of(pose: Dictionary) -> RefCounted:
	return Art.crew(str(pose.get("species", "human")))


## The layers to draw, back to front: [{layer, sheet, frame, angle (radians, to rotate by), pos
## (where the frame's top-left goes, in source px from the pivot's middle), tint (colour mask applies)}].
## Legs turn to `move`, everything else to `aim`; the walk frame follows `phase` (the stand frame
## when not moving or down; a floating rig has no walk: its tail plays `float` by `t`). The item sits with its grip on the arm pose's mount; the head is a
## hair frame, or the helmet when the pose says "helmet".
static func plan(sheet, pose: Dictionary) -> Array:
	var down: bool = pose.get("down", false)
	var move := float(pose.get("move", pose.get("aim", 0.0)))
	var aim := float(pose.get("aim", move))
	var out := []
	var ge = gear_art(sheet, str(pose.get("body", "")))  # the worn gear's art layers, or null
	var legs = ge["legs"] if ge != null and ge.has("legs") else sheet.layers["legs"]
	var frame: int = legs.start_of("stand")
	if rig_kind(sheet) == "floating":
		if not down and legs.has_anim("float"):
			frame = legs.frame_at("float", float(pose.get("t", 0.0)))
	elif pose.get("moving", false) and not down and legs.has_anim("walk"):
		var n: int = legs.anims["walk"]["count"]
		frame = legs.start_of("walk") + int(fposmod(float(pose.get("phase", 0.0)), TAU) / TAU * n) % n
	out.append({"layer": "legs", "sheet": legs, "frame": frame, "angle": move + PI / 2.0, "pos": legs.origin_of_frame(), "tint": true})
	if ge != null and ge.has("legs_over"):  # generated gear: an overlay on the same legs frame
		var lo = ge["legs_over"]
		out.append({"layer": "gear_legs", "sheet": lo, "frame": mini(frame, lo.count - 1), "angle": move + PI / 2.0, "pos": lo.origin_of_frame(), "tint": false})
	out.append({"layer": "torso", "sheet": sheet, "frame": 0, "angle": aim + PI / 2.0, "pos": sheet.origin_of_frame(), "tint": true})
	if ge != null and ge.has("body"):
		_add_gear(out, "gear_body", ge["body"], aim, down)  # after the torso, before the arms
	var arms = sheet.layers.get("arms")
	if arms != null:
		var held := held_item(pose)
		var cls: String = held["sheet"].pose if not held.is_empty() and held["sheet"].pose != "" else "tool"
		if held.is_empty() or not sheet.poses.has(cls) or sheet.poses[cls]["mount"] == null:
			cls = "unarmed"
			held = {}
		var ap := str(pose.get("arm_pose", ""))  # a rig's own arm pose by name (a boarding robot's strike frames)
		if ap != "" and sheet.poses.has(ap):
			cls = ap
			held = {}
		var jab := Vector2(0.0, -absf(sin(float(pose.get("t", 0.0)) * 9.0)) * JAB) if pose.get("work", false) and not down else Vector2.ZERO
		var pose_frame: int = sheet.poses[cls]["frame"] if sheet.poses.has(cls) else 0
		var arm_art = ge["arms"] if ge != null and ge.has("arms") else null  # an exosuit's own arms, in the same pose
		out.append({"layer": "arms", "sheet": arms if arm_art == null else arm_art, "frame": pose_frame if arm_art == null else arm_art.named_frames.get(cls, pose_frame),
			"angle": aim + PI / 2.0, "pos": arms.origin_of_frame() + jab, "tint": true})
		if ge != null and ge.has("sleeves"):  # generated gear: sleeves or gauntlets over the arms in the same pose
			var sl = ge["sleeves"]
			out.append({"layer": "gear_sleeves", "sheet": sl, "frame": mini(pose_frame, sl.count - 1), "angle": aim + PI / 2.0, "pos": arms.origin_of_frame() + jab, "tint": false})
		if not held.is_empty():
			var it = held["sheet"]
			out.append({"layer": "item", "sheet": it, "frame": 0, "angle": aim + PI / 2.0, "tint": false, "id": held["id"],
				"pos": sheet.poses[cls]["mount"] - it.anchors.get("grip", Vector2.ZERO) + arms.origin_of_frame() + jab})
	var head = sheet.layers.get("head")
	var hf_gen := 0
	if head != null:
		var hf: int = head.named_frames.get("helmet" if pose.get("helmet", false) else "hair", 0)
		hf = head.named_frames.get(str(pose.get("head", "")), hf)  # a character's own head frame (CrewMember.head)
		hf_gen = hf
		out.append({"layer": "head", "sheet": head, "frame": hf, "angle": aim + PI / 2.0, "pos": head.origin_of_frame(), "tint": true})
	if ge != null and ge.has("head"):
		_add_gear(out, "gear_head", ge["head"], aim, down, hf_gen if ge.has("_gen") else -1)  # after the head
	return out


## Append gear art layer `s` (a body or head layer of Art.gear) to the plan `out`, with its glow (lit while the wearer is up).
static func _add_gear(out: Array, name: String, s, aim: float, down: bool, frame := -1) -> void:
	var at: Vector2 = s.origin_of_frame()
	var l := {"layer": name, "sheet": s, "frame": (0 if s.meta.get("frame") is Array else int(s.meta.get("frame", 0))) if frame < 0 else mini(frame, s.count - 1), "angle": aim + PI / 2.0, "pos": at, "tint": true}
	out.append(l)
	if s.glow != null and not down:
		out.append({"layer": name + "_glow", "sheet": s, "frame": l["frame"], "angle": l["angle"], "pos": at, "tint": false, "glow": s.glow, "glow_frame": int(s.meta["glow"].get("frame", 0))})


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


## One layer: frame l["frame"] of `tex` (laid out like l["sheet"]), turned by l["angle"] about the
## body centre `at` and placed at l["pos"], `k` px per source px.
static func _blit(canvas, l: Dictionary, tex: Texture2D, at: Vector2, k: float, mod: Color) -> void:
	var sh = l["sheet"]
	canvas.draw_set_transform(at, l["angle"], Vector2(k, k))
	canvas.draw_texture_rect_region(tex, Rect2(l["pos"], Vector2(sh.frame)), sh.region(l["frame"]), mod)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## What a crew view adds to the pose of `m` when it is a repair drone (merge it into the pose; {} for anyone else): `drone`, `off`
## (no power) and `work` (it has a job and stands at it). `ship`: the one it is aboard.
static func drone_extras(m, ship) -> Dictionary:
	if not m.is_drone():
		return {}
	var busy: bool = not m.job.is_empty() and m.path.is_empty() and str(m.job.get("type", "")) != "rest"
	return {"drone": true, "off": not m.is_down() and not Power.drone_fed(ship.power_state, m.name), "work": busy and not m.is_down()}


## A repair drone, drawn in code (there is no art/crew/drone): a small hovering robot about one cell across, a round body with one lens
## and a tool arm in front, turned to `pose.aim`. `pose`: aim (radians, 0 = right), t (seconds, for the hover), work (the arm jabs
## and sparks), off (no power: a dark lens, no hover), down (broken: dark, low, no light). `cell_px` pixels a cell.
static func draw_drone(canvas: CanvasItem, centre_px: Vector2, pose: Dictionary, cell_px: float) -> void:
	var u := cell_px
	var t := float(pose.get("t", 0.0))
	var down: bool = pose.get("down", false)
	var live: bool = not down and not pose.get("off", false)
	var working: bool = live and pose.get("work", false)
	var hover := (0.12 + sin(t * 3.0) * 0.04) * u if live else 0.0  # it rides above its shadow
	var hull := Color("#a3b0c2") if live else Color("#6c7686")
	var trim := hull.darkened(0.5)
	var aim := float(pose.get("aim", pose.get("move", 0.0)))
	_ellipse(canvas, Transform2D(0.0, centre_px + Vector2(0.05, 0.12) * u), Vector2.ZERO, Vector2(0.46 + hover / u * 0.3, 0.38) * u, SHADOW)
	var at := centre_px - Vector2(0.0, hover)
	var xf := Transform2D(aim, at)
	for s in [-1.0, 1.0]:  # two thruster pods at the sides
		_capsule(canvas, xf, Vector2(0.0, s * 0.42) * u, Vector2(-0.26, s * 0.42) * u, 0.085 * u, trim, true)
		if live:
			canvas.draw_circle(xf * (Vector2(-0.32, s * 0.42) * u), (0.05 + 0.02 * sin(t * 15.0 + s)) * u, Color("#7fd6ff", 0.85), true, -1.0, true)
	var reach := 0.62 + (absf(sin(t * 9.0)) * 0.10 if working else 0.0)  # the arm: two joints and a claw, it jabs while it works
	var elbow := Vector2(0.36, 0.20) * u
	var tip := Vector2(reach, 0.06) * u
	_capsule(canvas, xf, Vector2(0.22, 0.12) * u, elbow, 0.055 * u, trim, true)
	_capsule(canvas, xf, elbow, tip, 0.05 * u, hull.darkened(0.2), true)
	canvas.draw_arc(xf * tip, 0.075 * u, aim + 0.9, aim + TAU - 0.9, 8, hull.lightened(0.2), 0.04 * u, true)
	canvas.draw_circle(at, 0.44 * u, Color(0, 0, 0, 0.4), true, -1.0, true)  # the round body: an edge, a rim, the plate and a glint
	canvas.draw_circle(at, 0.40 * u, trim, true, -1.0, true)
	canvas.draw_circle(at, 0.34 * u, hull, true, -1.0, true)
	canvas.draw_circle(at + Vector2(-0.08, -0.09) * u, 0.15 * u, hull.lightened(0.18), true, -1.0, true)
	canvas.draw_line(xf * (Vector2(-0.30, -0.10) * u), xf * (Vector2(-0.30, 0.10) * u), trim, 0.05 * u, true)  # a vent at the back
	var lens := xf * (Vector2(0.14, 0.0) * u)  # the one lens, where it looks
	canvas.draw_circle(lens, 0.15 * u, Color(0, 0, 0, 0.65), true, -1.0, true)
	canvas.draw_circle(lens, 0.115 * u, Color("#46e4ff") if live else (Color("#3a2828") if down else Color("#26303c")), true, -1.0, true)
	if live:
		canvas.draw_circle(lens + Vector2(-0.03, -0.03) * u, 0.035 * u, Color(1, 1, 1, 0.85), true, -1.0, true)
	if working:  # sparks at the claw
		for i in 3:
			var a := t * 21.0 + i * 2.1
			if fposmod(a, 2.0) < 1.2:
				canvas.draw_line(xf * tip, xf * (tip + Vector2(cos(a * 3.0), sin(a * 3.0)) * 0.16 * u), Color("#ffd24a"), maxf(1.0, 0.04 * u), true)
	if down:  # a thread of smoke
		for i in 3:
			var rise := fposmod(t * 0.7 + i * 0.33, 1.0)
			canvas.draw_circle(at + Vector2(sin(t + i) * 0.06, -0.15 - rise * 0.5) * u, (0.05 + rise * 0.06) * u, Color(0.7, 0.7, 0.72, 0.4 * (1.0 - rise)), true, -1.0, true)


## A short label (a drone's "no power" or "broken") just above a body at `centre_px`, white on a dark plate so it reads on any floor.
## It stays upright on the screen when the canvas is turned with the ship.
static func draw_status(canvas: CanvasItem, centre_px: Vector2, text: String, cell_px: float) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var size := maxi(10, roundi(cell_px * 0.42))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(-w / 2.0, -cell_px * 0.78)
	canvas.draw_set_transform(centre_px, -canvas.global_rotation if canvas is Node2D else 0.0, Vector2.ONE)
	canvas.draw_rect(Rect2(at + Vector2(-3.0, -size), Vector2(w + 6.0, size + 4.0)), Color(0.04, 0.07, 0.11, 0.8))
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("#ffb347"))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draw a person centred on `centre_px` (pixels, in the canvas' own coordinates).
## `facing`: radians, 0 = right, like Vector2.angle(). `walk_phase`: radians; advance it with the
## distance walked while `moving`, and with time while standing (it drives the breathing bob).
## `palette`: "suit", "hair" and "tool" colours (Color or "#rrggbb"), optional "skin".
static func draw_person(canvas: CanvasItem, centre_px: Vector2, facing: float, walk_phase: float,
		moving: bool, palette: Dictionary, cell_px: float, gear := "") -> void:
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

	if gear != "":
		draw_gear(canvas, centre_px, body.get_rotation(), cell_px * SCALE * GEAR_K, gear, false)
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
	if gear != "":
		draw_gear(canvas, centre_px, body.get_rotation(), cell_px * SCALE * GEAR_K, gear, true)


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
