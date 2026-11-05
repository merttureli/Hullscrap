extends RefCounted
## Healing arms on screen (docs/DRONES.md section 10): where each arm points, the soft beam to its patient and the glow on the patient.
## The arm's own sprite is drawn by Visuals.draw_component (opts arm_angle, arm_heal); the patient comes from Jobs (the ship's meta
## "arm_patients", uid -> crew name). The angles are kept in the ship's meta "arm_angles" (uid -> radians clockwise from up), turned
## every frame by whichever view is up (the interior or the fight). Drawing only, no game logic.

const Visuals = preload("res://scripts/view/visuals.gd")
const TURN := 5.0  ## radians a second an arm turns toward its patient
const GREEN := Color("#78f096")
const CYAN := Color("#5bf5ff")


## The crew member healing arm `uid` now, or null.
static func patient(ship, uid: int):
	var who: String = str(ship.get_meta("arm_patients", {}).get(uid, ""))
	if who == "":
		return null
	for m in ship.crew:
		if m.name == who:
			return m
	return null


## The middle of arm `uid`'s base, in cell units.
static func centre(ship, uid: int) -> Vector2:
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for c in ship.components.instances[uid]["cells"]:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c))
	return (lo + hi) / 2.0 + Vector2(0.5, 0.5)


## Turn each healing arm of `ship` toward its patient by up to TURN x `dt` radians (it stays where it was with none).
static func turn(ship, dt: float) -> void:
	var angles: Dictionary = ship.get_meta("arm_angles", {})
	for uid in ship.components.instances:
		if not Visuals.is_arm(ship.components.def(ship.components.instances[uid]["id"])):
			continue
		var at: float = angles.get(uid, 0.0)
		var m = patient(ship, uid)
		if m != null:
			var want := Vector2.UP.angle_to(m.pos - centre(ship, uid))
			at += clampf(angle_difference(at, want), -TURN * dt, TURN * dt)
		angles[uid] = at
	ship.set_meta("arm_angles", angles)


## The draw options of arm `uid` (merge into Visuals.draw_component's): where it points and whether it is healing.
static func opts(ship, uid: int) -> Dictionary:
	return {"arm_angle": float(ship.get_meta("arm_angles", {}).get(uid, 0.0)), "arm_heal": patient(ship, uid) != null}


## The beam from each working arm's head to its patient, and a glow ring on the patient. `to_px`: Callable(cell units) -> canvas px.
static func draw_beams(canvas, ship, to_px: Callable, cell_px: float, clock: float) -> void:
	var angles: Dictionary = ship.get_meta("arm_angles", {})
	for uid in angles:
		var m = patient(ship, uid) if ship.components.instances.has(uid) else null
		if m == null:
			continue
		var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
		var col := CYAN if str(def.get("line", "")) == "neon" else GREEN
		var tip: Vector2 = to_px.call(centre(ship, uid) + Vector2.UP.rotated(angles[uid]) * Visuals.arm_len(def))
		var to: Vector2 = to_px.call(m.pos)
		var pulse := 0.8 + 0.2 * sin(clock * 6.0)
		if tip.distance_to(to) > cell_px * 0.3:
			canvas.draw_line(tip, to, Color(col, 0.14 * pulse), 12.0, true)
			canvas.draw_line(tip, to, Color(col, 0.30 * pulse), 6.0, true)
			canvas.draw_line(tip, to, Color(col, 0.75), 2.0, true)
		canvas.draw_circle(to, cell_px * 1.05 * pulse, Color(col, 0.10))
		canvas.draw_circle(to, cell_px * 0.75 * pulse, Color(col, 0.16))
		canvas.draw_arc(to, cell_px * 0.9, 0.0, TAU, 32, Color(col, 0.5 * pulse), 2.0, true)
