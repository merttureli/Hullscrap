extends RefCounted
## Healing arms on screen (docs/DRONES.md section 10): how each arm moves, the soft beam to its patient and the glow on the patient.
## The arm itself is drawn by Visuals.draw_component as a 2-bone chain (Visuals.arm_pose, from opts arm_angle, arm_ext, arm_dist, arm_heal,
## arm_phase); the patient comes from Jobs (the ship's meta "arm_patients", uid -> crew name). Where each arm points, how far it reaches and
## how far its patient is are kept in the ship's meta ("arm_angles": radians clockwise from up, "arm_ext": 0 folded .. 1 reaching,
## "arm_dists": cells) and eased every frame by whichever view is up (the interior or the fight), so it never snaps. Drawing only, no game logic.

const Visuals = preload("res://scripts/view/visuals.gd")
const TURN := 5.0  ## radians a second an arm turns toward its patient, at most
const EASE := 6.0  ## how quickly (per second) an arm closes the gap to where it wants to point
const REACH := 3.0  ## how quickly (per second) it unfolds toward a patient or folds back
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


## Ease each healing arm of `ship` toward its patient (turn toward them, unfold, follow them as they move) or, with none, fold back where it points.
static func turn(ship, dt: float) -> void:
	var angles: Dictionary = ship.get_meta("arm_angles", {})
	var exts: Dictionary = ship.get_meta("arm_ext", {})
	var dists: Dictionary = ship.get_meta("arm_dists", {})
	var ease := 1.0 - exp(-EASE * dt)
	for uid in ship.components.instances:
		if not Visuals.is_arm(ship.components.def(ship.components.instances[uid]["id"])):
			continue
		var at: float = angles.get(uid, 0.0)
		var m = patient(ship, uid)
		if m != null:
			var to: Vector2 = m.pos - centre(ship, uid)
			at += clampf(angle_difference(at, Vector2.UP.angle_to(to)) * ease, -TURN * dt, TURN * dt)
			dists[uid] = lerpf(float(dists.get(uid, to.length())), to.length(), ease)
		angles[uid] = at
		exts[uid] = lerpf(float(exts.get(uid, 0.0)), 1.0 if m != null else 0.0, 1.0 - exp(-REACH * dt))
	ship.set_meta("arm_angles", angles)
	ship.set_meta("arm_ext", exts)
	ship.set_meta("arm_dists", dists)


## The draw options of arm `uid` (merge into Visuals.draw_component's): where it points, how far it reaches, whether it is healing.
static func opts(ship, uid: int) -> Dictionary:
	return {"arm_angle": float(ship.get_meta("arm_angles", {}).get(uid, 0.0)), "arm_ext": float(ship.get_meta("arm_ext", {}).get(uid, 0.0)),
			"arm_dist": float(ship.get_meta("arm_dists", {}).get(uid, 0.0)), "arm_heal": patient(ship, uid) != null, "arm_phase": float(uid) * 1.7}


## The beam from each working arm's emitter to its patient, and a glow ring on the patient. `to_px`: Callable(cell units) -> canvas px.
static func draw_beams(canvas, ship, to_px: Callable, cell_px: float, clock: float) -> void:
	var angles: Dictionary = ship.get_meta("arm_angles", {})
	for uid in angles:
		var m = patient(ship, uid) if ship.components.instances.has(uid) else null
		if m == null:
			continue
		var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
		var col := CYAN if str(def.get("line", "")) == "neon" else GREEN
		var pose := Visuals.arm_pose(def, opts(ship, uid).merged({"time": clock}), "heal")
		var tip: Vector2 = to_px.call(centre(ship, uid) + pose["emitter"])  # the beam leaves the head's emitter
		var to: Vector2 = to_px.call(m.pos)
		var pulse := 0.8 + 0.2 * sin(clock * 6.0)
		if tip.distance_to(to) > cell_px * 0.3:
			canvas.draw_line(tip, to, Color(col, 0.14 * pulse), 12.0, true)
			canvas.draw_line(tip, to, Color(col, 0.30 * pulse), 6.0, true)
			canvas.draw_line(tip, to, Color(col, 0.75), 2.0, true)
		canvas.draw_circle(to, cell_px * 1.05 * pulse, Color(col, 0.10))
		canvas.draw_circle(to, cell_px * 0.75 * pulse, Color(col, 0.16))
		canvas.draw_arc(to, cell_px * 0.9, 0.0, TAU, 32, Color(col, 0.5 * pulse), 2.0, true)
