extends RefCounted
## The helm in sector space (docs/CONTENT.md section 11, "Flying and the helm"): the player's ship as a flight body
## (flight.gd, the arena's model) in sector px, flown by the autopilot to a course while the helm is manned, or by hand
## (E at the helm: the combat flight controls). Pure logic, no nodes: sector_view.gd drives it each frame and the soak
## test flies it at a time scale. Numbers are data/sectors.json `helm`.
## - `flight.pos` is the hull's pivot (the centre of its bounding box, as in arena.gd), `flight.angle` its heading (0 up,
##   clockwise positive). frame() maps the build view's px (ship.world_pos at the grid centre) into the sector, so the
##   interior, the crew and the intakes can be drawn and hit where the ship flies.
## - Out of combat the flight numbers run at `cruise` (x1.8 on acceleration and top speed, data/sectors.json); with a hostile within
##   `real_within` px (2,500) they are the real ones.
## - The autopilot turns toward the way it has to go, thrusts, and brakes with reverse thrust so it stops within
##   `arrive` px (300) of the course; then the course is done. Big drifting rocks near its path push it aside.
## - Unmanned, the ship coasts: the current carries the debris, not the ship (sector.gd fly()).

const Flight = preload("res://scripts/sim/flight.gd")
const Stats = preload("res://scripts/sim/stats.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/sectors.json"
const CELL := 32.0
const STEER_MIN := 48.0  ## px: a cursor nearer the ship than this does not turn it (combat_session.gd)

var cfg: Dictionary  ## data/sectors.json "helm"
var flight: Flight
var pivot := Vector2.ZERO  ## the hull's centre in grid cells: flight.pos sits on it
var radius := 64.0  ## px from the pivot to the farthest corner of what is built
var mass := 1.0
var thrust := 0.0  ## all the powered engines' thrust (it turns the ship)
var thrusts := {"fwd": 0.0, "left": 0.0, "right": 0.0}
var why_not := "no powered helm"  ## "" when the ship can fly, else why not (flight.gd can_fly)
var course := {}  ## {poi: id} follows a POI of the sector, {pos: Vector2} a point; {} is no course
var manual := false  ## the player has the helm (E): hand() flies it
var cruise := 1.0  ## the multiplier on acceleration and top speed in use now
var state := "no course"  ## what the last step did, for the HUD: autopilot, manual, unmanned, no course, grounded
var arrived := ""  ## the name of the course reached on the last step ("" when none)
var _base := Vector2.ZERO  # data/flight.json's thrust_to_accel and max_speed
var _powered = null  # the power solve refresh() last read
var _rev := -1


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else Content.read(PATH)["helm"]
	flight = Flight.new()
	_base = Vector2(flight.thrust_to_accel, flight.max_speed)


## The hull's centre in grid cells (the middle of its bounding box, as arena.gd add_ship).
static func pivot_of(grid) -> Vector2:
	if grid.hull.is_empty():
		return Vector2(grid.size) / 2.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in grid.hull:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
	return (lo + hi) / 2.0


## The transform from the build view's px (where BuildMode draws `ship`, ship.world_pos at the grid centre) to the
## sector, for a hull pivot `p_pivot` (cells) on `pos` turned by `angle`.
static func frame_of(ship, pos: Vector2, angle: float, p_pivot: Vector2) -> Transform2D:
	var origin: Vector2 = ship.world_pos - Vector2(ship.grid.size) * CELL / 2.0
	return Transform2D(angle, pos) * Transform2D(0.0, -(origin + p_pivot * CELL))


func frame(ship) -> Transform2D:
	return frame_of(ship, flight.pos, flight.angle, pivot)


## Read the ship again when its power solve or abilities changed: mass, thrust, whether it can fly and the pivot (a
## rebuilt hull moves the pivot; flight.pos follows it so the ship stays where it was drawn).
func refresh(ship) -> void:
	ship.refresh()
	var powered = ship.power_state.get("powered", {})
	if is_same(powered, _powered) and _rev == Abilities.rev(ship):
		return
	_powered = powered
	_rev = Abilities.rev(ship)
	var view = Stats.view(ship.components, ship.lines)
	var mults := Stats.mass_mults(ship.components, ship.lines)
	mass = flight.mass_of(ship.grid, ship.components, ship.cables, mults)
	thrust = flight.thrust_of(view, powered, Abilities.thrust_boost(ship))
	thrusts = flight.thrusts_of(view, powered, Abilities.thrust_boost(ship))
	why_not = flight.can_fly(ship.components, powered)
	var p := pivot_of(ship.grid)
	if p != pivot:
		flight.pos += ((p - pivot) * CELL).rotated(flight.angle)
		pivot = p
	var half := 0.0
	for c in ship.grid.tiles:  # what is built, not the whole frame
		half = maxf(half, (Vector2(c) + Vector2(0.5, 0.5) - pivot).length())
	radius = (half + 0.75) * CELL


## Put the ship at `pos` (its pivot), moving at `vel`, heading `angle`.
func place(pos: Vector2, vel := Vector2.ZERO, angle := 0.0, ang_vel := 0.0) -> void:
	flight.pos = pos
	flight.vel = vel
	flight.angle = wrapf(angle, -PI, PI)
	flight.ang_vel = ang_vel


func set_course(poi_id: String) -> void:
	course = {"poi": poi_id}


func set_course_to(pos: Vector2) -> void:
	course = {"pos": pos}


func clear_course() -> void:
	course = {}


## Where the course leads in `sector` now (a POI moves with it), or null with no course or a POI that is gone.
func target(sector):
	if course.has("pos"):
		return course["pos"]
	if course.has("poi"):
		var p: Dictionary = sector.find(str(course["poi"]))
		return p["pos"] if not p.is_empty() else null
	return null


## The name the HUD gives the course ("" with none).
func course_name(sector) -> String:
	if course.has("poi"):
		return str(sector.find(str(course["poi"])).get("name", ""))
	return "the marked point" if course.has("pos") else ""


## Acceleration (px/s^2) at full forward thrust with the numbers in use.
func accel() -> float:
	return float(thrusts.get("fwd", 0.0)) * flight.thrust_to_accel / maxf(mass, Flight.MIN_MASS)


## Fly `dt` seconds in `sector` (its ship_pos, ship_vel and ship_angle follow). `manned`: someone is at the helm (a crew
## member or the player, is_manned()). `hand`: the player's controls while `manual`: {throttle, side, cursor (a sector
## point, or null)}. `hostile`: a hostile ship is within `real_within` px, so the numbers are real. `rocks`: [{pos, r}]
## drifting rocks the autopilot steers round.
func step(dt: float, sector, manned: bool, hand := {}, hostile := false, rocks: Array = []) -> void:
	if dt <= 0.0:
		return
	arrived = ""
	cruise = 1.0 if hostile else float(cfg["cruise"])
	flight.thrust_to_accel = _base.x * cruise
	flight.max_speed = _base.y * cruise
	var input := {}
	var to = target(sector)
	if course.has("poi") and to == null:
		course = {}  # the contact left
	if why_not != "":
		state = "grounded"
		manual = false
	elif manual:
		state = "manual"
		input = hand_input(hand)
	elif not manned:
		state = "unmanned"
	elif to == null:
		state = "no course"
	else:
		state = "autopilot"
		if flight.pos.distance_to(to) <= float(cfg["arrive"]) and flight.vel.length() <= float(cfg["arrive_speed"]):
			arrived = course_name(sector)
			course = {}
			state = "no course"
		else:
			input = autopilot(to, rocks)
	flight.step(dt, input, mass, thrust, thrusts)
	var size: float = sector.size
	if flight.pos.x < 0.0 or flight.pos.x > size:
		flight.pos.x = clampf(flight.pos.x, 0.0, size)
		flight.vel.x = 0.0
	if flight.pos.y < 0.0 or flight.pos.y > size:
		flight.pos.y = clampf(flight.pos.y, 0.0, size)
		flight.vel.y = 0.0
	sync_to(sector)


## Write the ship's place into `sector` (radar, triggers and the save read it there).
func sync_to(sector) -> void:
	sector.ship_pos = flight.pos
	sector.ship_vel = flight.vel
	sector.ship_angle = flight.angle


## The helm input that flies to `to`: the wanted velocity points at it (bent round rocks in the way), as fast as reverse
## thrust can still stop in the distance left; the ship faces the way it must speed up (the target while it slows down),
## thrusts forward when it faces the change it wants, reverses when that change is behind it, and strafes the rest.
func autopilot(to: Vector2, rocks: Array = []) -> Dictionary:
	var off := to - flight.pos
	var dist := off.length()
	if dist < 1.0:
		return {}
	var dir := off / dist
	dir = _avoid(dir, dist, rocks)
	var a := maxf(accel(), 1.0)
	var brake := a * Flight.REVERSE * float(cfg["brake"])
	var speed := minf(flight.max_speed * 0.95, sqrt(2.0 * brake * maxf(dist - float(cfg["arrive"]) * 0.5, 0.0)))
	var want := dir * speed - flight.vel
	var fwd := Vector2.UP.rotated(flight.angle)
	var face := want if want.dot(dir) > 0.0 and want.length() > a * 0.05 else dir
	var turn := flight.steer_toward(face.angle() + PI / 2.0, mass, thrust)
	var along := want.dot(fwd)
	var aim := want.normalized().dot(fwd) if want.length() > 0.001 else 0.0
	var throttle := 0.0
	if along > 0.0 and aim > 0.7:
		throttle = clampf(along / (a * 0.3), 0.0, 1.0)
	elif along < 0.0 and aim < -0.7:
		throttle = clampf(along / (a * Flight.REVERSE * 0.3), -1.0, 0.0)
	var right := Vector2.RIGHT.rotated(flight.angle)
	var side := want.dot(right)
	var push := float(thrusts.get("right", 0.0)) if side > 0.0 else float(thrusts.get("left", 0.0))
	var strafe := 0.0
	if push > 0.0:
		strafe = clampf(side / (push * flight.thrust_to_accel / maxf(mass, Flight.MIN_MASS) * 0.3), -1.0, 1.0)
	return {"throttle": throttle, "turn": turn, "strafe": strafe}


## `dir`, or, when a rock ahead (within `avoid.look` px, or `avoid.react` seconds at the speed now) sits closer to the
## line than the ship's radius plus the rock's and `avoid.clear`, the way to a point that far beside the nearest such
## rock, on the side the ship is already on.
func _avoid(dir: Vector2, dist: float, rocks: Array) -> Vector2:
	var look := minf(maxf(float(cfg["avoid"]["look"]), flight.vel.length() * float(cfg["avoid"]["react"])), dist)
	var perp := dir.orthogonal()
	var best := INF
	var out := dir
	for rock in rocks:
		var rel: Vector2 = rock["pos"] - flight.pos
		var ahead := rel.dot(dir)
		var lat := rel.dot(perp)
		var need := radius + float(rock["r"]) + float(cfg["avoid"]["clear"])
		if ahead <= -need * 0.25 or ahead > look or absf(lat) >= need or ahead >= best:
			continue
		best = ahead
		var away := -signf(lat) if absf(lat) > 0.5 else 1.0
		var side: Vector2 = rock["pos"] + perp * away * need * 1.25 - flight.pos
		out = side.normalized() if side.dot(dir) > 0.0 else (dir + perp * away).normalized()
	return out


## The combat flight controls (combat_session.gd helm_input): `hand` {throttle (-1..1), side (-1..1), cursor}. Mouse
## steering turns toward the cursor and `side` strafes; keys steering turns with `side`.
func hand_input(hand: Dictionary) -> Dictionary:
	var throttle := float(hand.get("throttle", 0.0))
	var side := float(hand.get("side", 0.0))
	var cursor = hand.get("cursor")
	if cursor is Vector2 and flight.steer == "mouse":
		var to: Vector2 = cursor - flight.pos
		var turn := 0.0
		if to.length() > STEER_MIN:
			turn = flight.steer_toward(to.angle() + PI / 2.0, mass, thrust)
		return {"throttle": throttle, "turn": turn, "strafe": side}
	return {"throttle": throttle, "turn": side, "strafe": 0.0}


## Where a fight starts (combat_session.gd start()'s `place`): the ship as it flies now, and the enemy at `enemy_pos`
## (else `gap` px ahead), never nearer than `gap` px, inside a sector `size` px across.
func fight_place(enemy_pos, gap: float, size: float) -> Dictionary:
	var e: Vector2 = enemy_pos if enemy_pos is Vector2 else flight.pos + Vector2.UP.rotated(flight.angle) * gap
	if e.distance_to(flight.pos) < gap:
		var away: Vector2 = e - flight.pos
		e = flight.pos + (away.normalized() if away.length() > 1.0 else Vector2.UP.rotated(flight.angle)) * gap
	return {"player_pos": flight.pos, "player_angle": flight.angle, "player_vel": flight.vel, "player_ang_vel": flight.ang_vel,
		"enemy_pos": e.clamp(Vector2.ZERO, Vector2(size, size))}


# --- who is at the helm ------------------------------------------------------------------------------------

## The uids of the working helms of `ship` (status ok), in order.
static func helms(ship) -> Array:
	var out := []
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if str(ship.components.def(inst["id"]).get("family", "")) == "helm" and str(inst.get("status", "ok")) == "ok":
			out.append(uid)
	return out


## The working helm `player` stands next to (or on), -1 when none.
static func helm_near(ship, player) -> int:
	if player == null or player.is_down():
		return -1
	var body: Array = player.body_cells()
	for uid in helms(ship):
		for c in ship.components.instances[uid]["cells"]:
			for b in body:
				if absi(b.x - c.x) + absi(b.y - c.y) <= 1:
					return uid
	return -1


## Is someone at a working helm: a crew member manning it (jobs.gd marks ship.manned) or the player standing by it?
static func is_manned(ship, player = null) -> bool:
	var working := helms(ship)
	for uid in ship.manned:
		if working.has(uid):
			return true
	return helm_near(ship, player) >= 0
