extends RefCounted
## The enemy pilot: flies one ship of the arena against another and shoots. Deterministic: its few
## random choices (aim jitter, which way it strafes) come from its own generator, seeded from the
## arena's seed, and it only reads the arena. Call think(dt) once per arena substep, before stepping.
## - Range: it keeps a gap of RANGE_FRACTION of the range most of its dps reaches (REACH_SHARE of it, so one short gun does not pull a many-gun ship in; at least HULL_MARGIN) between the two hulls,
##   measured along the line between the centres from each hull's reach that way (extent()), since muzzles and the parts
##   it aims at sit on the hull's edge. (It used to hold that between the centres, and later at least both bounding circles
##   apart: a large hull, or a starter's frame round a small core, then kept it out of its own guns' range.)
## - Pointing: it turns the side its fixed guns face to the target, off by
##   an aim error that shrinks with `aim_skill` (the design's `ai.aim_skill`, 0..1, default 0.6): up to
##   (1 - aim_skill) x AIM_ERROR_DEG degrees either way, re-rolled every RETARGET_S. It fires a fixed gun
##   when the gun can bear (its gimbal reaches the aim point, in range), or when its barrel at the edge of the
##   gimbal still lines up on the foe's hull within range (on_hull()). Turrets track and fire by themselves
##   in the arena (Weapons.tick_turrets). It strafes with side engines when it has them.
## - Broadside passes (docs/GUNS.md 6): the fixed guns are grouped by the side of the ship they face (bow, starboard, stern, port) and each
##   group is weighed by its dps (pick_facing()). The pilot presents the heaviest group: the bow when it is at least as heavy as
##   any side, else a flank (of two heavy flanks the one needing the smaller turn, kept while it stays that way). Presenting a flank it
##   holds the foe abeam, cruising along it at its range: the nose leans toward the foe when it is too far and away when too near
##   (ABEAM_LEAN_MAX_DEG at most, about the gimbal of its broadside), and side engines strafe it in or out.
## - Aim (pick_target()): a pilot of SNIPE_SKILL or better aims at the foe's weapons first (the outside half of a
##   mount, the part it can see), a worse one at its hull; once the guns are out, everyone aims at the hull: the
##   facing wall nearest its line to the foe's centre, clear of the guns' outside halves (hull_point()), so the shots
##   meet walls and the hull integrity drops. A foe that flees (`foe_morale`, set for the player's pilot in tests and tools) has
##   its engines aimed at first: they hold its jump drive. A part its guns can reach (within its longest range of
##   the hull's near edge) comes before one that is not. Shots that fly are led by the part's own velocity
##   (hitscan lasers and beams go at the part as it is).
## - With a sectored shield it holds back weapons whose shot would open the sector the player's loaded
##   guns are pointing at, for at most HOLD_MAX seconds.
## - With 2+ shield sectors it shifts the balance toward the side that faces its foe, one step every
##   SHIFT_BASE_S - aim_skill seconds (the design's `ai.aim_skill`, default 0.6).
## - It overcharges its shield when the layers are gone, and does nothing once wrecked.
## - Morale (morale.gd, set by the session): surrendering it holds fire and cuts the throttle; fleeing it turns
##   its stern to the foe and burns at full throttle (the guns still fire when they bear); once captured, spared
##   or gone it does nothing.
## - Style "rammer" (a ship design's `"ai": {"style": "rammer"}`) does not keep a range: it finds its
##   bow (the side with the most ram plating, else forward), points it at where the foe will be and
##   closes at full throttle, uses its engine ability within RAM_ABILITY_RANGE of the foe's hull, and after a collision
##   backs off for RAM_BACKOFF_S seconds before coming round again. Its guns still fire when they can.
## - The fighting styles of the enemy roles (data/enemy_tables.json roles, the role's `ai.style`), each its own small function; the guns
##   fire as above in all of them:
##   - "skirmisher" (_skirmish): hit and run. It holds the gap between the hulls at SKIRMISH_HOLD of its longest reach; when the foe
##     closes inside SKIRMISH_RUN of it, it turns and burns away (as it flees) until it is back out at the hold, then comes round again.
##   - "carrier" (_carry): it keeps the gap at CARRIER_MARGIN of the foe's longest reach, within its drones' reach (Drones.DRONE_REACH),
##     and its bays launch and relaunch (Drones.ai_launch). With no drone left to fly it fights as the others do.
##   - "boarder" (_board): it closes fast (BOARD_CLOSE_MAX px/s) to throwing range and its bays throw their pods (Drones.LIMPET_REACH);
##     while its people are aboard the foe (robots, or pods on the hull or in flight) it holds close (BOARD_GAP) and strafes.
##   - "flanker" (_flank): it steers for the foe's stern quarter (FLANK_DEG off the foe's stern, by the foe's heading, at its hold) and
##     goes round the foe's hull to get there; near that point it fights as the others do and is soon carried on across. Its
##     priority() puts the foe's engines and weapons first.
##   - "siege" (_siege): it holds the gap at SIEGE_HOLD of its longest reach and fires in volleys (the session puts its guns in Volley);
##     once a volley is out it backs off to SIEGE_BACK of its reach for SIEGE_BACK_S at least and while the guns reload, then returns.
##   - "bulwark" (_bulwark): it closes slowly (BULWARK_CLOSE px/s at most) and turns its strongest shield sector (the most HP) toward the
##     foe, the balance shifted that way (_balance); with one sector or none it shows the foe its bow. It breaks late (its ai's break_structure).

const Shields = preload("res://scripts/combat/shields.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const Drones = preload("res://scripts/combat/drones.gd")

const RANGE_FRACTION := 0.7  ## of a gun's range: the gap it keeps for it
const REACH_SHARE := 0.6  ## it holds the longest gap at which guns of this share of its dps (or more) reach
const HULL_MARGIN := 96.0  ## px kept between the two hulls, at least (three cells: an orbit at less clips the foe's hull)
const DEFAULT_RANGE := 840.0
const SNIPE_SKILL := 0.8  ## a pilot of this aim_skill or better aims at the foe's weapons first; a worse one at its hull
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const GUN_CLEARANCE := 2  ## cells: the point of the hull it aims at keeps this far from a weapon's outside half
const DEFAULT_AIM_SKILL := 0.6
const AIM_ERROR_DEG := 8.5  ## (12 before the guns reached 1.4x as far: the same miss in px at the longer hold) aim error either way of a pilot with no skill; a pilot of skill s is off by up to (1 - s) of it
const ABEAM_LEAN_MAX_DEG := 30.0  ## the most the nose leans off the beam to open or close the range while a flank is presented
const ABEAM_LEAN_MIN_DEG := 10.0
const ABEAM_CRUISE := 0.5  ## throttle while a flank is presented (the pass along the foe)
const FACING_STICK_DEG := 30.0  ## a presented flank is kept unless the other flank needs this much less turn
const LATERAL_MAX := 225.0  ## px/s of sideways drift before it turns the other way
const CLOSE_MAX := 390.0  ## px/s it closes at, at most
const BACK_MAX := 180.0  ## px/s it backs off at, at most
const THROTTLE_BAND := 135.0  ## px/s of closing-speed error that asks for full throttle
const HOLD_THROTTLE := 0.5  ## at the preferred range it still pushes this hard
const HOLD_MAX := 1.5  ## seconds a weapon waits for a safer sector
const SHIFT_BASE_S := 1.5  ## a shield balance step comes every this many seconds less the aim skill
const RETARGET_S := 0.5
const HOLD_EVERY_S := 0.25  ## seconds between two workings-out of the distance it holds
const LINE_EVERY := 6  ## substeps an on_hull() answer for a gun is kept
const RAM_BACKOFF_S := 2.0  ## seconds a rammer reverses after a collision
const RAM_ABILITY_RANGE := 600.0  ## px from the foe's hull (its centre less its bounding radius): a rammer presses its engine ability inside this
const RAM_FINAL := 240.0  ## px: inside this a rammer steers straight at the foe
const RAM_CLOSE_SPEED := 480.0  ## px/s a rammer steers to close at
const RAM_MIN_CLOSE := 150.0  ## px/s: the closing speed it assumes when working out the time to contact
const RAM_MAX_LEAD_S := 4.0
const RAM_ALIGNED := 0.45  ## rad: full throttle when the heading is this close to the steering direction
const FLEE_ALIGNED := 0.6  ## rad: a fleeing ship burns once its nose is this close to straight away from the foe
const SKIRMISH_HOLD := 0.9  ## a skirmisher holds the gap between the hulls at this share of its longest reach
const SKIRMISH_RUN := 0.6  ## inside this share it turns and burns away, until it is back out at SKIRMISH_HOLD
const SKIRMISH_RUN_MAX_S := 6.0  ## a run that has not opened the gap in this long ends: it turns and fights
const CARRIER_MARGIN := 1.15  ## a carrier keeps the gap at this many times the foe's longest reach
const CARRIER_DRONE_SHARE := 0.85  ## and its centre within this share of its drones' reach of the foe's
const BOARD_CLOSE_MAX := 560.0  ## px/s a boarder closes at, at most
const BOARD_GAP := 2.0 * HULL_MARGIN  ## px between the hulls a boarder holds while its people are aboard
const FLANK_DEG := 45.0  ## a flanker's goal: this far off the foe's stern, to the side it came from
const FLANK_NEAR := 0.35  ## within this share of its hold of the goal it fights as the others do
const FLANK_SPEED := 330.0  ## px/s it closes on its goal at, at most (on top of the foe's own drift)
const FLANK_ALIGNED := 0.5  ## rad: it burns once its nose is this close to the way it wants to go
const SIEGE_HOLD := 0.9  ## a siege boat holds the gap at this share of its longest reach
const SIEGE_BACK := 1.3  ## and backs off to this share while it reloads
const SIEGE_BACK_S := 2.5  ## seconds it backs off after a volley, at least
const SIEGE_COOLING := 0.5  ## a volley is out when this share of its guns (not rapid, not point defence) cool for more than SIEGE_RELOAD_S
const SIEGE_RELOAD_S := 0.5
const BULWARK_CLOSE := 140.0  ## px/s a bulwark closes at, at most
const BULWARK_SWAP := 1.25  ## it turns another sector to the foe once that holds this many times the HP of the one facing it

var arena
var me: int
var foe: int
var rng := RandomNumberGenerator.new()
var aim_skill := DEFAULT_AIM_SKILL  ## 0..1: how true the pilot's aim is and how quickly it shifts its shield balance (the design's ai.aim_skill)
var side := 1.0  ## +1 or -1: which way it strafes (when it has side engines)
var bias := 0.0  ## radians: its aim error now, re-rolled with each retarget
var target_uid := -1  ## the part of the foe it aims at (-1: its hull, at hull_aim)
var hull_aim := Vector2.ZERO  ## with no part to aim at: the point of the foe's hull it aims at (the foe's cell coordinates, hull_point())
var style := ""  ## "" (keeps its range and strafes), "rammer", or a role's style (skirmisher, carrier, boarder, flanker, siege, bulwark)
var morale = null  ## morale.gd of this fight (the session sets it): pilot_mode() says hold, flee or stop
var foe_morale = null  ## the foe's morale.gd, when the foe is the enemy (the player's pilot in tests and tools): a fleeing foe's engines come first
var facing := 0  ## the side of the ship it presents to the foe: 0 bow, 1 starboard, 2 stern, 3 port (pick_facing())
var _flip := 0.0
var _retarget := 0.0
var _hold := {}  # weapon uid -> seconds held back
var _bow := Vector2.UP  # ship-local direction of a rammer's bow
var _shift_in := 0.0  # seconds until the next shield balance step
var _backoff := 0.0  # seconds a rammer still reverses
var _contact_seen := -1  # the last arena.contact_tick this pilot has reacted to
var _hold_d := -1.0  # the distance it holds (hold_distance()), and seconds until it is worked out again
var _hold_in := 0.0
var _lined := {}  # weapon uid -> [arena tick, on_hull()] of its last check
var _running := -1.0  # a skirmisher's run: seconds it has run (-1: not running)
var _reload := -1.0  # a siege boat's back-off: seconds of it left at least (-1: at range)
var _flank_side := 0.0  # +1 or -1: the side of the foe's stern a flanker goes for (0: not chosen yet)
var _facing_sector := 0  # the shield sector a bulwark shows the foe


## `p_ai`: the `ai` entry of the ship's design ({"style": "rammer"}), if it has one.
func _init(p_arena, p_me: int, p_foe: int, p_ai := {}) -> void:
	arena = p_arena
	me = p_me
	foe = p_foe
	style = str(p_ai.get("style", ""))
	aim_skill = clampf(float(p_ai.get("aim_skill", DEFAULT_AIM_SKILL)), 0.0, 1.0)
	_shift_in = shift_interval()
	_bow = bow_of(arena.ships[me])
	hull_aim = hull_point()
	rng.seed = int(arena.rng.seed) * 7919 + me * 104729 + 17
	side = 1.0 if rng.randf() < 0.5 else -1.0
	_flip = rng.randf_range(2.0, 4.0)


## Decide for `dt` seconds: set the helm and fire what is ready.
func think(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var mode: String = morale.pilot_mode() if morale != null else ""
	if co.wrecked or tgt.wrecked or mode == "stop":
		arena.set_input(me, 0.0, 0.0)
		return
	_retarget -= dt
	if _retarget <= 0.0 or (target_uid >= 0 and not _part_ok(target_uid)):
		_retarget = RETARGET_S
		target_uid = pick_target()
		if target_uid < 0:
			hull_aim = hull_point()
		_bow = bow_of(co)
		var e := deg_to_rad((1.0 - aim_skill) * AIM_ERROR_DEG * Hazards.aim_error_mult(arena))
		bias = rng.randf_range(-e, e)
	if mode == "hold":  # surrendering: no throttle, no fire
		arena.set_input(me, 0.0, 0.0)
		_balance(dt)
		return
	if mode == "flee":
		_flee()
	elif style == "rammer":
		_ram(dt)
	elif style == "skirmisher":
		_skirmish(dt)
	elif style == "carrier":
		_carry(dt)
	elif style == "boarder":
		_board(dt)
	elif style == "flanker":
		_flank(dt)
	elif style == "siege":
		_siege(dt)
	elif style == "bulwark":
		_bulwark(dt)
	else:
		_fly(dt)
	_balance(dt)
	_shoot(dt)
	Drones.ai_launch(arena, me, foe)  # its bays launch when they can (drones.gd)


# --- flying ------------------------------------------------------------------------------------

## The weapons that can shoot now: uid -> mount, in uid order.
func _armed() -> Dictionary:
	var out := {}
	var uids: Array = arena.ships[me].mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = arena.ships[me].mounts[uid]
		if arena.weapons.status_of(arena, me, uid) == "ok" and (m["powered"] if m["virtual"] else arena.ships[me].powered.get(uid, false)):
			out[uid] = m
	return out


## The weapons not shot out or cut off, and powered (a jammed or overheated one will be back): uid -> mount, in uid order.
func _intact() -> Dictionary:
	var out := {}
	var uids: Array = arena.ships[me].mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = arena.ships[me].mounts[uid]
		if not arena.weapons.status_of(arena, me, uid) in ["disabled", "offline"] and (m["powered"] if m["virtual"] else arena.ships[me].powered.get(uid, false)):
			out[uid] = m
	return out


## Keep the range and fight: `hold` (px between the centres) in place of hold_distance() when it is 0 or more; it closes at `close_max` px/s at most.
func _fly(dt: float, hold := -1.0, close_max := CLOSE_MAX) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var armed := _armed()
	# The fixed guns by the side they face, each side weighed by its dps: the heaviest is presented to the foe.
	var groups := fixed_groups(armed)
	var to_foe0: Vector2 = tgt.flight.pos - co.flight.pos
	facing = pick_facing(groups, (to_foe0.rotated(-co.flight.angle)).angle() + PI / 2.0, facing)
	var axis := Vector2.UP
	var lead_mount := {}
	var pivots := Vector2.ZERO  # where the presented guns turn, summed
	var fixed := 0
	if groups.has(facing):
		axis = Vector2(groups[facing]["axis"]).normalized() if Vector2(groups[facing]["axis"]).length_squared() > 1e-6 else Vector2.UP
		pivots = groups[facing]["pivots"]
		fixed = int(groups[facing]["n"])
		lead_mount = groups[facing]["first"]
	var to_foe: Vector2 = tgt.flight.pos - co.flight.pos
	var dist := to_foe.length()
	var u := to_foe / maxf(dist, 1.0)
	_hold_in -= dt
	if _hold_in <= 0.0 or _hold_d < 0.0:  # the hulls' reach changes slowly: worked out a few times a second
		_hold_in = HOLD_EVERY_S
		_hold_d = hold_distance(u, _intact())
	var preferred := _hold_d if hold < 0.0 else hold
	# Flip the strafe now and then, and when the sideways drift gets too big.
	_flip -= dt
	if _flip <= 0.0:
		_flip = rng.randf_range(2.5, 5.0)
		side = -side
	var lateral: float = co.flight.vel.dot(u.rotated(PI / 2.0))
	if absf(lateral) > LATERAL_MAX:
		side = -signf(lateral)
	# Turn so the fixed guns' axis leads the target (a guess off by its aim error).
	var aim: Vector2 = aim_for(lead_mount) if not lead_mount.is_empty() else tgt.flight.pos
	var want: float = (aim - co.flight.pos).angle() - axis.angle()
	if fixed > 0:  # the guns sit off the middle: aim so that they, not the centre, point at it
		for k in 3:
			var at: Vector2 = co.flight.pos + ((pivots / fixed - co.pivot) * arena.CELL).rotated(want)
			want = (aim - at).angle() - axis.angle()
	var closing: float = co.flight.vel.dot(u)
	var abeam := fixed > 0 and (facing == 1 or facing == 3)
	var lean := 0.0  # the nose leans toward the foe when it is too far, away when too near (abeam only)
	if abeam:
		var room := clampf(deg_to_rad(float(arena.weapons.def(lead_mount["id"])["gimbal"])), deg_to_rad(ABEAM_LEAN_MIN_DEG), deg_to_rad(ABEAM_LEAN_MAX_DEG))
		lean = clampf((dist - preferred) / maxf(preferred, 1.0) - 0.5 * closing / CLOSE_MAX, -1.0, 1.0) * room * (1.0 if axis.x > 0.0 else -1.0)
		want += lean
	var turn: float = co.flight.steer_toward(want, co.mass, co.thrust)
	# Close or open the range with the thrust (it pushes along the heading, near the target's direction).
	var brake: float = co.thrust * co.flight.thrust_to_accel / maxf(co.mass, 1.0) * co.flight.REVERSE * 0.6  # px/s^2 it can stop with
	var gap := dist - preferred
	var want_closing := signf(gap) * minf(sqrt(2.0 * brake * absf(gap)), close_max if gap > 0.0 else BACK_MAX)
	var heading := Vector2.UP.rotated(co.flight.angle)
	var throttle := 0.0
	if heading.dot(u) > 0.5:
		throttle = clampf((want_closing - closing) / THROTTLE_BAND, -1.0, 1.0)
		if absf(gap) < preferred * 0.15 and absf(throttle) < HOLD_THROTTLE:
			throttle = HOLD_THROTTLE * (1.0 if gap >= 0.0 else -1.0)  # keep pushing: the hold is a slow orbit
	var strafe := side if float(co.thrusts["left"]) + float(co.thrusts["right"]) > 0.0 else 0.0
	if abeam:  # the pass: cruise along the foe, and slide in or out with the side engines to hold the range
		var tangent: float = absf(co.flight.vel.dot(u.rotated(PI / 2.0)))
		throttle = ABEAM_CRUISE if tangent < CLOSE_MAX * 0.6 else 0.0
		if strafe != 0.0:
			strafe = (1.0 if axis.x > 0.0 else -1.0) * signf(gap) if absf(gap) > preferred * 0.1 else 0.0
	arena.set_input(me, throttle, turn, strafe)


## The armed fixed guns grouped by the side of the ship they face: facing (0 bow, 1 starboard, 2 stern, 3 port) -> {dps, axis (their
## outward directions summed, ship-local), pivots (their pivots summed), n, first (the first one's mount)}.
func fixed_groups(armed: Dictionary) -> Dictionary:
	var out := {}
	for uid in armed:
		var m: Dictionary = armed[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		if w["turret"]:
			continue
		var f := facing_of(m["dir"])
		if not out.has(f):
			out[f] = {"dps": 0.0, "axis": Vector2.ZERO, "pivots": Vector2.ZERO, "n": 0, "first": m}
		var g: Dictionary = out[f]
		g["dps"] += float(w["damage"]) * float(w["shots"]) / maxf(float(w["cooldown"]), 0.1)
		g["axis"] += Vector2(m["dir"])
		g["pivots"] += Vector2(m["pos"])
		g["n"] += 1
	return out


## The side (0 bow, 1 starboard, 2 stern, 3 port) a ship-local direction faces.
static func facing_of(dir: Vector2) -> int:
	if absf(dir.x) > absf(dir.y):
		return 1 if dir.x > 0.0 else 3
	return 2 if dir.y > 0.0 else 0


## The side to present to the foe, from the groups (fixed_groups()): the bow unless a side outweighs it, and of the heaviest sides
## (within 15 percent of the best) the one that needs the smaller turn. `foe_angle`: the foe's bearing from the ship's nose (radians,
## clockwise, ship-local, 0 is dead ahead); `now`: the side presented now, which stays unless another needs FACING_STICK_DEG less turn.
static func pick_facing(groups: Dictionary, foe_angle: float, now := 0) -> int:
	if groups.is_empty():
		return 0
	var bow_dps: float = float(groups[0]["dps"]) if groups.has(0) else 0.0
	var best := 0.0
	for f in groups:
		if f == 0 or float(groups[f]["dps"]) > bow_dps:
			best = maxf(best, float(groups[f]["dps"]))
	var pick := -1
	var pick_turn := INF
	var now_turn := INF
	for f in groups:
		if (f != 0 and float(groups[f]["dps"]) <= bow_dps) or float(groups[f]["dps"]) < best * 0.85:
			continue
		var axis_angle := Vector2(groups[f]["axis"]).angle() + PI / 2.0  # 0 for a bow gun (up)
		var turn := absf(wrapf(foe_angle - axis_angle, -PI, PI))
		if f == now:
			now_turn = turn
		if turn < pick_turn - 1e-6:
			pick = f
			pick_turn = turn
	if now_turn < INF and now_turn <= pick_turn + deg_to_rad(FACING_STICK_DEG):
		return now
	return pick if pick >= 0 else 0


## The distance between the centres it keeps with the foe along the world direction `u` (from it to the foe), with the
## weapons `armed` (_intact(): a jam or a reload does not move it): each hull's extent() that way plus the gap that brings
## every gun within RANGE_FRACTION of its range of the foe's near edge, its place counted (a flank turret far behind the bow needs a closer gap
## than a bow gun); at least HULL_MARGIN. A gun too far to the side to reach the line between the centres is left out.
func hold_distance(u: Vector2, armed: Dictionary) -> float:
	var co = arena.ships[me]
	var ext := extent(me, u)
	# Per gun the gap at which it reaches (a short gun gives a small one); it holds the largest gap at which guns of REACH_SHARE of the dps fire.
	var reach: Array = []  # [gap, dps]
	var total := 0.0
	for uid in armed:
		var m: Dictionary = armed[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		var dps := float(w["damage"]) * float(w["shots"]) / maxf(float(w["cooldown"]), 0.1)
		var r := RANGE_FRACTION * float(w["range"])
		var mo: Vector2 = arena.local_to_world(me, m["pos"]) - co.flight.pos
		var off := absf(mo.cross(u))
		total += dps
		if off < r:
			reach.append([mo.dot(u) + sqrt(r * r - off * off) - ext, dps])
	reach.sort_custom(func(a, b): return a[0] > b[0])
	var gap := INF
	var acc := 0.0
	for e in reach:
		acc += e[1]
		if acc >= REACH_SHARE * total:
			gap = e[0]
			break
	if gap == INF:
		gap = RANGE_FRACTION * DEFAULT_RANGE if reach.is_empty() else reach[-1][0]
	return ext + extent(foe, -u) + maxf(HULL_MARGIN, gap)


## Px from the pivot of ship `idx` to the farthest point of its hull along the world direction `u`: its outer cells' centres
## projected on `u`, plus half a cell's diagonal. How far it reaches toward a ship that lies that way.
func extent(idx: int, u: Vector2) -> float:
	var hc: Dictionary = Collisions.hit_cells(arena, idx)
	var lu: Vector2 = u.rotated(-arena.ships[idx].flight.angle)
	var far := 0.0
	for c in hc["cells"]:
		far = maxf(far, Vector2(hc["info"][c]["ctr"]).dot(lu))
	return far + arena.CELL * 0.71


## The ship's bow, ship-local: the unit vector toward the side (up, down, left, right of its centre)
## holding the most ram plating (a tile with the `ram` quirk); forward (up) when it has none, and on a tie the first of up, down, left, right.
static func bow_of(co) -> Vector2:
	var sides: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var count := [0, 0, 0, 0]
	var grid = co.ship.grid
	for c in grid.tiles:
		if str(grid.defs.get_def(grid.tiles[c]).get("quirk", "")) != "ram":
			continue
		var v: Vector2 = Vector2(c) + Vector2(0.5, 0.5) - co.pivot
		if absf(v.x) > absf(v.y):
			count[3 if v.x > 0.0 else 2] += 1
		else:
			count[1 if v.y > 0.0 else 0] += 1
	var best := 0
	for k in range(1, 4):
		if count[k] > count[best]:
			best = k
	return sides[best]


## Helm turn (-1..1) that brings an angle error `err` (rad, positive is clockwise) to zero, braking in time.
func _turn_for(err: float) -> float:
	var co = arena.ships[me]
	return co.flight.steer_toward(co.flight.angle + err, co.mass, co.thrust)


## A rammer's flying: bow at the foe's future position and full throttle, or reversing after a collision.
func _ram(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	var to_foe: Vector2 = tgt.flight.pos - co.flight.pos
	var dist := to_foe.length()
	var touched: int = int(arena.contact_tick.get(me, -1))
	if touched > _contact_seen:
		_contact_seen = touched
		if _backoff <= 0.0:
			_backoff = RAM_BACKOFF_S
	var u := to_foe / maxf(dist, 1.0)
	if _backoff > 0.0:  # keep the bow on the foe while backing away, ready to come round
		_backoff -= dt
		arena.set_input(me, -1.0, _turn_for(wrapf(u.angle() - _bow.angle() - co.flight.angle, -PI, PI)))
		return
	var rel_v: Vector2 = co.flight.vel - tgt.flight.vel
	var t_hit := clampf(dist / maxf(rel_v.dot(u), RAM_MIN_CLOSE), 0.0, RAM_MAX_LEAD_S)
	var aim: Vector2 = tgt.flight.pos + tgt.flight.vel * t_hit
	var steer: Vector2 = (aim - co.flight.pos).normalized()
	if dist > RAM_FINAL:  # cancel the sideways drift as well as closing in
		steer = (steer * RAM_CLOSE_SPEED - (rel_v - steer * rel_v.dot(steer))).normalized()
	var turn := _turn_for(wrapf(steer.angle() - _bow.angle() - co.flight.angle, -PI, PI))
	var heading := Vector2.UP.rotated(co.flight.angle)
	arena.set_input(me, 1.0 if heading.dot(steer) > cos(RAM_ALIGNED) else 0.0, turn)
	if dist - float(Collisions.hit_cells(arena, foe)["radius"]) < RAM_ABILITY_RANGE:
		arena.use_key(me, "engine")


## Fleeing: nose straight away from the foe (stern to it), full throttle once it points that way.
func _flee() -> void:
	var co = arena.ships[me]
	var away: Vector2 = co.flight.pos - arena.ships[foe].flight.pos
	away = away.normalized() if away.length_squared() > 1.0 else Vector2.UP
	var turn: float = co.flight.steer_toward(away.angle() + PI / 2.0, co.mass, co.thrust)
	arena.set_input(me, 1.0 if Vector2.UP.rotated(co.flight.angle).dot(away) > cos(FLEE_ALIGNED) else 0.0, turn)


# --- the fighting styles of the roles ------------------------------------------------------------

## The distance between the centres at which the gap between the two hulls along the line between them is `gap` px.
func centres_at(gap: float) -> float:
	var u: Vector2 = (arena.ships[foe].flight.pos - arena.ships[me].flight.pos).normalized()
	return extent(me, u) + extent(foe, -u) + gap


## The gap between the two hulls along the line between the centres now (px).
func gap_now() -> float:
	var d: Vector2 = arena.ships[foe].flight.pos - arena.ships[me].flight.pos
	return d.length() - extent(me, d.normalized()) - extent(foe, -d.normalized())


## The longest range of the foe's weapons that are not shot out (DEFAULT_RANGE with none).
func foe_reach() -> float:
	var r := 0.0
	var f = arena.ships[foe]
	for uid in f.mounts:
		if not arena.weapons.status_of(arena, foe, uid) in ["disabled", "offline"]:
			r = maxf(r, float(arena.weapons.def(f.mounts[uid]["id"])["range"]))
	return r if r > 0.0 else DEFAULT_RANGE


## Skirmisher: hit and run (see the top). The run is a flight (_flee) that ends back out at the hold, or after SKIRMISH_RUN_MAX_S.
func _skirmish(dt: float) -> void:
	var r := reach()
	var gap := gap_now()
	if _running >= 0.0:
		_running += dt
		if gap >= SKIRMISH_HOLD * r or _running > SKIRMISH_RUN_MAX_S:
			_running = -1.0
	elif gap < SKIRMISH_RUN * r:
		_running = 0.0
	if _running >= 0.0:
		_flee()
	else:
		_fly(dt, centres_at(SKIRMISH_HOLD * r))


## Does it still have drones to fly: a bay with a drone out, re-arming, or ready to launch?
func has_drones() -> bool:
	for uid in arena.ships[me].bays:
		if Drones.can_launch(arena, me, uid) in ["", "drone out", "re-arming"]:
			return true
	return false


## Carrier: beyond the foe's reach and within its drones' (see the top); the bays launch by themselves (Drones.ai_launch in think()).
func _carry(dt: float) -> void:
	if not has_drones():
		_fly(dt)
		return
	_fly(dt, minf(centres_at(CARRIER_MARGIN * foe_reach()), CARRIER_DRONE_SHARE * Drones.DRONE_REACH))


## Are its people aboard the foe: a robot of the foe's intruders, or one of its own pods stuck on the foe's hull or flying at it?
func boarders_out() -> bool:
	if not arena.ships[foe].ship.intruders.is_empty():
		return true
	return arena.drones.any(func(d): return int(d["owner"]) == me and str(d["role"]) == "boarder")


## Boarder: closes fast, throws, then holds close while its people are aboard (see the top).
func _board(dt: float) -> void:
	if boarders_out():
		_fly(dt, centres_at(BOARD_GAP), BOARD_CLOSE_MAX)
	else:
		_fly(dt, minf(_hold_d, Drones.LIMPET_REACH) if _hold_d > 0.0 else -1.0, BOARD_CLOSE_MAX)


## The flanker's goal (world px): FLANK_DEG off the foe's stern on its side, at the distance it holds.
func flank_goal() -> Vector2:
	var tgt = arena.ships[foe]
	var co = arena.ships[me]
	var stern: Vector2 = -Vector2.UP.rotated(tgt.flight.angle)
	if _flank_side == 0.0:  # the side of the foe it is on now
		_flank_side = 1.0 if stern.cross(co.flight.pos - tgt.flight.pos) >= 0.0 else -1.0
	var hold := _hold_d if _hold_d > 0.0 else hold_distance(stern, _intact())
	return tgt.flight.pos + stern.rotated(deg_to_rad(FLANK_DEG) * _flank_side) * hold


## Flanker: for the foe's stern quarter, round its hull, then the guns (see the top).
func _flank(dt: float) -> void:
	var co = arena.ships[me]
	var tgt = arena.ships[foe]
	if _hold_d < 0.0:
		_hold_d = hold_distance((tgt.flight.pos - co.flight.pos).normalized(), _intact())
	var goal := flank_goal()
	if co.flight.pos.distance_to(goal) <= FLANK_NEAR * _hold_d:
		_fly(dt)
		return
	# Go round the foe: a goal behind the foe's hull is reached by the point beside it, out at the hold.
	var keep: float = 0.8 * _hold_d
	var seg: Vector2 = goal - co.flight.pos
	var t := clampf((tgt.flight.pos - co.flight.pos).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	var near: Vector2 = co.flight.pos + seg * t
	if near.distance_to(tgt.flight.pos) < keep:
		var out: Vector2 = near - tgt.flight.pos
		out = out.normalized() if out.length_squared() > 1.0 else (co.flight.pos - tgt.flight.pos).normalized().rotated(PI / 2.0 * _flank_side)
		goal = tgt.flight.pos + out * _hold_d
	var to_goal: Vector2 = goal - co.flight.pos
	var accel: float = co.thrust * co.flight.thrust_to_accel / maxf(co.mass, 1.0)
	var want_v: Vector2 = tgt.flight.vel + to_goal.normalized() * minf(FLANK_SPEED, sqrt(2.0 * accel * 0.5 * to_goal.length()))
	var err: Vector2 = want_v - co.flight.vel
	var turn := _turn_for(wrapf(err.angle() + PI / 2.0 - co.flight.angle, -PI, PI))
	var aligned := Vector2.UP.rotated(co.flight.angle).dot(err.normalized()) > cos(FLANK_ALIGNED)
	arena.set_input(me, 1.0 if aligned and err.length() > 20.0 else 0.0, turn)


## Is a volley out: SIEGE_COOLING of its armed guns that join volleys (not rapid, not point defence) cool for more than SIEGE_RELOAD_S?
func volley_out() -> bool:
	var armed := _intact()
	var n := 0
	var cooling := 0
	for uid in armed:
		var w: Dictionary = arena.weapons.def(armed[uid]["id"])
		if bool(w.get("rapid", false)) or (w.get("effects") is Dictionary and w["effects"].has("intercept")):
			continue
		n += 1
		cooling += int(arena.cooldown_left(me, uid) > SIEGE_RELOAD_S)
	return n > 0 and float(cooling) >= SIEGE_COOLING * n


## Siege boat: a volley from range, back off while it reloads, come back (see the top).
func _siege(dt: float) -> void:
	var out := volley_out()
	if _reload < 0.0 and out:
		_reload = SIEGE_BACK_S
	elif _reload >= 0.0:
		_reload -= dt
		if _reload < 0.0 and out:
			_reload = 0.0  # still reloading: it stays back
	var r := reach()
	_fly(dt, centres_at((SIEGE_BACK if _reload >= 0.0 else SIEGE_HOLD) * r))


## The world direction sector `s` of ship `co`'s bubble faces (sector 0 the bow, clockwise).
static func sector_dir(co, s: int) -> Vector2:
	return Vector2.UP.rotated(co.flight.angle + TAU * float(s) / float(maxi(co.sectors, 1)))


## Bulwark: slow, its strongest sector to the foe (see the top).
func _bulwark(dt: float) -> void:
	var co = arena.ships[me]
	if co.sectors < 2 or co.layers_cap <= 0 or co.layers <= 0:
		_facing_sector = 0
		_fly(dt, -1.0, BULWARK_CLOSE)
		return
	_facing_sector = clampi(_facing_sector, 0, co.sectors - 1)
	var best := _facing_sector
	for s in co.sectors:
		if Shields.hp_of(co, s) > Shields.hp_of(co, best) + 1e-6:
			best = s
	if Shields.hp_of(co, best) > BULWARK_SWAP * Shields.hp_of(co, _facing_sector) + 1e-6:
		_facing_sector = best
	if _facing_sector == 0:  # the bow: its guns and its best plate both point at the foe
		_fly(dt, -1.0, BULWARK_CLOSE)
		return
	var tgt = arena.ships[foe]
	var to_foe: Vector2 = tgt.flight.pos - co.flight.pos
	var u := to_foe.normalized()
	if _hold_in <= 0.0 or _hold_d < 0.0:
		_hold_in = HOLD_EVERY_S
		_hold_d = hold_distance(u, _intact())
	_hold_in -= dt
	var turn := _turn_for(wrapf(u.angle() + PI / 2.0 - TAU * float(_facing_sector) / float(co.sectors) - co.flight.angle, -PI, PI))  # sector_dir() on the foe
	var gap := to_foe.length() - _hold_d
	var brake: float = co.thrust * co.flight.thrust_to_accel / maxf(co.mass, 1.0) * co.flight.REVERSE * 0.6
	var want_closing := signf(gap) * minf(sqrt(2.0 * brake * absf(gap)), BULWARK_CLOSE if gap > 0.0 else BACK_MAX)
	var along: float = Vector2.UP.rotated(co.flight.angle).dot(u)  # its thrust closes the range this much (the nose may point away)
	var throttle := 0.0
	if absf(along) > 0.4:
		throttle = clampf((want_closing - co.flight.vel.dot(u)) / THROTTLE_BAND, -1.0, 1.0) * signf(along)
	var strafe := 0.0
	var right: float = Vector2.RIGHT.rotated(co.flight.angle).dot(u)  # its side engines close it this much
	if float(co.thrusts["left"]) + float(co.thrusts["right"]) > 0.0 and absf(right) > 0.4:
		strafe = clampf((want_closing - co.flight.vel.dot(u)) / THROTTLE_BAND, -1.0, 1.0) * signf(right)
	arena.set_input(me, throttle, turn, strafe)


## Seconds between two steps of shield balance.
func shift_interval() -> float:
	return SHIFT_BASE_S - aim_skill


## With a sectored shield: a step of weight toward the sector that faces the foe every shift_interval().
func _balance(dt: float) -> void:
	var co = arena.ships[me]
	if co.sectors < 2 or co.layers_cap <= 0:
		return
	_shift_in -= dt
	if _shift_in > 0.0:
		return
	_shift_in = shift_interval()
	Shields.shift_sector(co, Shields.sector_of_world_dir(co, arena.ships[foe].flight.pos - co.flight.pos))


# --- shooting ------------------------------------------------------------------------------------

## The foe's part to aim at: the first family of priority() it has an alive part of, nearest first, a part within reach()
## of the near edge of its own hull before one that is not; -1 when none is (it aims at the foe's centre of mass: the hull).
func pick_target() -> int:
	var tgt = arena.ships[foe]
	var comps = tgt.ship.components
	var uids: Array = comps.instances.keys()
	uids.sort()
	var from: Vector2 = arena.ships[me].flight.pos
	var to_foe: Vector2 = tgt.flight.pos - from
	var limit := extent(me, to_foe.normalized()) + reach()
	for family in priority():
		for near in [true, false]:
			var best := -1
			var best_d := INF
			for uid in uids:
				if not _part_ok(uid) or comps.def(comps.instances[uid]["id"]).get("family", "") != family:
					continue
				var d := from.distance_squared_to(arena.local_to_world(foe, part_centre(foe, uid)))
				if near and d > limit * limit:
					continue
				if d < best_d:
					best_d = d
					best = uid
			if best >= 0:
				return best
	return -1


## The part families it aims at before the hull, in order: the engines of a fleeing foe, then the weapons for a pilot of
## SNIPE_SKILL or better; a flanker goes for the engines and then the weapons whatever its skill.
func priority() -> Array[String]:
	var out: Array[String] = []
	if (foe_morale != null and foe_morale.state == "fleeing") or style == "flanker":
		out.append("engine")
	if aim_skill >= SNIPE_SKILL - 1e-6 or style == "flanker":
		out.append("weapon")
	return out


## The point of the foe's hull it aims at when it aims at no part (the foe's cell coordinates): of the wall and door cells
## that border space on the side facing it and at least GUN_CLEARANCE cells from the outside half of a weapon (shots at the middle of a
## bow meet the bow gun), the one nearest the line from it to the foe's centre of mass; that centre when there is none.
func hull_point() -> Vector2:
	var f = arena.ships[foe]
	var comps = f.ship.components
	var g = f.ship.grid
	var guns: Array = []
	for uid in comps.instances:
		if comps.def(comps.instances[uid]["id"]).get("family", "") == "weapon":
			guns.append_array(comps.instances[uid]["out_cells"])
	var from: Vector2 = arena.world_to_local(foe, arena.ships[me].flight.pos)
	var com: Vector2 = f.com
	var look: Vector2 = (com - from).normalized()
	var best: Vector2 = com
	var best_d := INF
	for c in Collisions.hit_cells(arena, foe)["cells"]:
		var t: String = g.get_tile(c)
		if t == "" or not (g.tile_flag(t, "solid") or g.tile_flag(t, "door")):
			continue
		if not SIDES.any(func(d): return g.get_tile(c + d) == "" and comps.any_at(c + d) < 0):
			continue  # a bulkhead inside (it borders a floor, not space)
		var at := Vector2(c) + Vector2(0.5, 0.5)
		if (at - com).dot(look) > 0.0:
			continue  # the far side
		if guns.any(func(o): return absi(o.x - c.x) <= GUN_CLEARANCE and absi(o.y - c.y) <= GUN_CLEARANCE):
			continue
		var d := absf((at - from).cross(look))
		if d < best_d:
			best_d = d
			best = at
	return best


## The longest range of its weapons that can shoot (DEFAULT_RANGE with none).
func reach() -> float:
	var r := 0.0
	var armed := _armed()
	for uid in armed:
		r = maxf(r, float(arena.weapons.def(armed[uid]["id"])["range"]))
	return r if r > 0.0 else DEFAULT_RANGE


func _part_ok(uid: int) -> bool:
	var ship = arena.ships[foe].ship
	var inst = ship.components.instances.get(uid)
	return inst != null and inst.get("status", "ok") != "disabled" and float(inst.get("hp", 1)) > 0.0 and ship.components.offline_reason(ship.grid, uid) == ""


## The centre of part `uid` of ship `idx`, in its grid cell coordinates: the outside half of a hull
## mount (what the pilot sees), else the part.
func part_centre(idx: int, uid: int) -> Vector2:
	var sum := Vector2.ZERO
	var inst: Dictionary = arena.ships[idx].ship.components.instances[uid]
	var cells: Array = inst["out_cells"] if not inst["out_cells"].is_empty() else inst["cells"]
	for c in cells:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return sum / cells.size()


## Where to aim from `origin` at a point moving with `vel`: the spot a shot of `speed` px/s meets it
## (the smallest positive time), or the point itself for hitscan (`speed` 0) or when no meeting exists.
static func lead_point(origin: Vector2, point: Vector2, vel: Vector2, speed: float) -> Vector2:
	if speed <= 0.0:
		return point
	var r := point - origin
	var qa := vel.dot(vel) - speed * speed
	var qb := 2.0 * r.dot(vel)
	var qc := r.dot(r)
	var t := -1.0
	if absf(qa) < 1e-6:
		if absf(qb) > 1e-9:
			t = -qc / qb
	else:
		var disc := qb * qb - 4.0 * qa * qc
		if disc >= 0.0:
			var s := sqrt(disc)
			var t1 := (-qb - s) / (2.0 * qa)
			var t2 := (-qb + s) / (2.0 * qa)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	return point + vel * t if t > 0.0 else point


## The velocity of the point of ship `idx` at ship-local `local` (its drift plus its spin).
func point_velocity(idx: int, local: Vector2) -> Vector2:
	var co = arena.ships[idx]
	var r: Vector2 = ((local - co.pivot) * arena.CELL).rotated(co.flight.angle)
	return co.flight.vel + r.rotated(PI / 2.0) * co.flight.ang_vel


## The world point to aim mount `m` at: the chosen part (or the centre of the ship), led, and turned off
## by the pilot's aim error `bias` when `jitter`.
func aim_for(m: Dictionary, jitter := true) -> Vector2:
	var local: Vector2 = part_centre(foe, target_uid) if target_uid >= 0 and _part_ok(target_uid) else hull_aim
	var origin: Vector2 = arena.local_to_world(me, m["pos"])
	var w: Dictionary = arena.weapons.def(m["id"])
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var aim := lead_point(origin, arena.local_to_world(foe, local), point_velocity(foe, local), speed)
	if jitter:
		aim = origin + (aim - origin).rotated(bias)
	return aim


func _shoot(dt: float) -> void:
	var co = arena.ships[me]
	if co.layers == 0 and co.layers_cap > 0 and co.overcharge_left <= 0.0 and co.overcharge_cd <= 0.0:
		arena.overcharge(me)
	var danger := _exposed_sectors() if co.sectors > 1 and co.layers > 0 else []
	var uids: Array = co.mounts.keys()
	uids.sort()
	for uid in uids:
		var m: Dictionary = co.mounts[uid]
		var w: Dictionary = arena.weapons.def(m["id"])
		if w["turret"]:
			continue  # it tracks and fires by itself (Weapons.tick_turrets)
		var aim := aim_for(m)
		arena.weapons.point_barrel(arena, me, uid, aim)
		if arena.cooldown_left(me, uid) > 0.0:
			continue
		var origin: Vector2 = arena.weapons.muzzle_of(arena, me, m)
		if arena.weapons.can_fire(arena, me, uid, aim) != "":
			continue
		if origin.distance_to(aim) > float(w["range"]) or not arena.weapons.in_arc(arena, me, m, aim):
			# It cannot bear on the part it aims at: it fires anyway when its barrel, at the edge of its gimbal, still lines up on
			# the foe's hull within range (a row of bow guns cannot all point at one part, but each can hit the ship).
			var seen: Array = _lined.get(uid, [-1000, false])
			if arena.tick - int(seen[0]) >= LINE_EVERY:
				seen = [arena.tick, on_hull(origin, Vector2(m["aim"]).rotated(co.flight.angle), float(w["range"]))]
				_lined[uid] = seen
			if not seen[1]:
				continue
		if not danger.is_empty() and Shields.drop_seconds(w) > 0.0:
			var s := Shields.outgoing_sector(co, m["pos"], (aim - origin).rotated(-co.flight.angle))
			if s in danger and float(_hold.get(uid, 0.0)) < HOLD_MAX:
				_hold[uid] = float(_hold.get(uid, 0.0)) + dt
				continue
		if arena.weapons.holds_charge(arena, me, m, foe):
			continue  # a charge gun waits for its volleys (or the foe's shields to fall)
		_hold.erase(uid)
		arena.fire(me, uid, aim)


## Does a shot from the world point `origin` along the unit vector `dir` meet an outer cell of the foe's hull within `reach_px`?
func on_hull(origin: Vector2, dir: Vector2, reach_px: float) -> bool:
	var f = arena.ships[foe]
	var hc: Dictionary = Collisions.hit_cells(arena, foe)
	var to_c: Vector2 = f.flight.pos - origin
	if absf(to_c.cross(dir)) > float(hc["radius"]) or to_c.dot(dir) < -float(hc["radius"]):
		return false
	for c in hc["cells"]:
		var v: Vector2 = to_c + Vector2(hc["info"][c]["ctr"]).rotated(f.flight.angle)
		var t := v.dot(dir)
		if t > 0.0 and t <= reach_px and absf(v.cross(dir)) <= arena.CELL * 0.5:
			return true
	return false


## The sectors of its own bubble that the foe's loaded guns (ready within 0.4 s, aimed at it) would hit.
func _exposed_sectors() -> Array:
	var co = arena.ships[me]
	var out := []
	var f = arena.ships[foe]
	for uid in f.mounts:
		var m: Dictionary = f.mounts[uid]
		if arena.cooldown_left(foe, uid) > 0.4 or not (m["powered"] if m["virtual"] else f.powered.get(uid, false)):
			continue
		if not arena.weapons.in_arc(arena, foe, m, co.flight.pos):
			continue
		var a: Vector2 = arena.world_to_local(me, arena.local_to_world(foe, m["pos"]))
		var t := Shields.entry_t(co, a, co.pivot)
		var s := Shields.sector_of(co, (a.lerp(co.pivot, t) if t >= 0.0 else a) - co.pivot)
		if not out.has(s):
			out.append(s)
	return out
