extends RefCounted
## The tractor beam (docs/CONTENT.md section 11, the Raft loop): hold Q in play mode and every working tractor beam draws
## the debris within its range toward the nearest working intake. Pure logic, no nodes: drift_debris.gd asks beams() once a
## step and pull() for each piece, debris_view.gd reads the key and draws the beams.
## - A beam is a part of the `tractor` family (a turret hull mount) with stats.tractor_range (px) and stats.tractor_pull
##   (px/s, how fast it hauls a piece). It works when it is not disabled (a shot-off outside half or a cut link included) and,
##   as it draws power, is powered. Its emitter is the turning point of its head, on the outside half.
## - Range is measured from the emitter to the edge of the piece. The piece is hauled toward the middle of the intake mouth
##   nearest to it; it still has to get through the hull's outline to land (a mouth on the far side is a long way round).
## - Q is the combat utility key, so the beam is a play-mode tool: debris_view.gd does not run it in a fight.

const Mounts = preload("res://scripts/ship/mounts.gd")

const FAMILY := "tractor"
const CELL := 32.0  ## ship-frame px per grid cell (build_mode.gd CELL)


## The working beams of `ship`: [{uid, id, at (the emitter, in the ship's px: `origin` is where grid cell (0, 0) starts), range, pull}].
static func beams(ship, origin: Vector2) -> Array:
	var out := []
	var off: Dictionary = ship.disabled_uids()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		if str(def.get("family", "")) != FAMILY or inst["out_cells"].is_empty() or off.has(uid):
			continue
		if int(def.get("power", 0)) < 0 and not powered.get(uid, false):
			continue
		var stats: Dictionary = def.get("stats", {})
		out.append({"uid": uid, "id": inst["id"], "at": origin + Vector2(Mounts.barrel(def, inst["out_anchor"], inst["rot"])["pivot"]) * CELL,
			"range": float(stats.get("tractor_range", 0.0)), "pull": float(stats.get("tractor_pull", 0.0))})
	return out


## How the beams haul a piece of radius `r` at `lp` (the ship's px), toward one of `mouths` (drift_debris.gd intakes()):
## {} when none reaches it or there is no mouth, else {beam (the uid of the nearest beam that reaches it), at (that
## beam's emitter), to (the middle of the nearest mouth), speed (the fastest pull of the beams that reach it)}.
static func pull(beams: Array, mouths: Array, lp: Vector2, r: float) -> Dictionary:
	if mouths.is_empty():
		return {}
	var near := {}
	var near_d := INF
	var speed := 0.0
	for b in beams:
		var d: float = lp.distance_to(b["at"])
		if d - r > float(b["range"]):
			continue
		speed = maxf(speed, float(b["pull"]))
		if d < near_d:
			near = b
			near_d = d
	if near.is_empty():
		return {}
	var to := Vector2.ZERO
	var best := INF
	for m in mouths:
		var rect: Rect2 = m["rect"]
		var d: float = (lp - Vector2(clampf(lp.x, rect.position.x, rect.end.x), clampf(lp.y, rect.position.y, rect.end.y))).length()
		if d < best:
			best = d
			to = rect.get_center()
	return {"beam": near["uid"], "at": near["at"], "to": to, "speed": speed}
