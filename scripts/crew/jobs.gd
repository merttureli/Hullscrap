extends RefCounted
## What the crew do on their own (docs/PLAN.md pillar 4). One Jobs object per ship (ShipSim keeps
## them); tick() runs every frame. Utility style, no randomness, so the same ship plays out the same.
##
## The job board is rebuilt from the ship's state every `period` seconds (and at once after a job
## is finished): `extinguish` a burning cell (100), `revive` a downed crew member (95),
## `repair_breach` a shot-open wall (90), `repair_component` a malfunctioning or disabled part (80,
## +10 for a weapon, engine or shield in a fight; also a hull mount whose outside half is damaged and
## whose link is intact, from its inside half), `repair_crew` a hurt `mechanical` crew member (75,
## done by any other crew member: beds do not heal them), `repair_block` a wall or door below its hp and not breached (60; 65 out of a
## fight; work by the hp missing), `man_station` (50, out of a fight 45 but the helm: the helm, and weapons,
## shields and engines flagged manned), `restock` (40: carry ammo from the cargo to an ammo rack below half full,
## 1 s per 5 units at normal speed: scripts/sim/ammo.gd), `clear_wreck` (30: the debris of a part that was shot to pieces,
## which gives back half its recipe), and `repair_belt` (70: mend one conveyor-belt cell that damage cut). A job has `slots` places (two crew stack on a fire) and a place to
## stand next to it. Numbers are in data/crew.json.
## Each hand-out, an idle crew member takes the highest-priority job with a free place, preferring
## jobs nobody works on, then the nearest by walking distance (only the nearest few get a path
## search, see `search` in the data). A crew member keeps their job until it is done or a job at
## least `switch_margin` priority points higher shows up. The player's soldier is never given a
## job; the player works a job by standing next to it and holding E (hand_work). Hurt crew with
## nothing to do rest on a bed (5 hp/s) or in a powered medbay (15 hp/s; a medbay is one bed: it heals one crew member at a time).
## What the crew's traits change (traits.gd, the library in data/traits.json) is asked there: work speed
## (work_rate: repair, extinguish, breach, revive, swarm and aura bonuses), air and fire damage, room heat
## (dries_out, heat_speed), healing (heal_mult, auras), ion hits (ion_hit: damage and stun), vacuum_walk (no suffocation),
## vacuum_speed (the walk in thin air), line_affinity (repairing a part of a line), no_tools (no repair or extinguish jobs) and
## hull_mend (idle crew mend the walls and breaches next to them), low_pressure_heal (hp a second in a room with under half its
## air) and mimic (tick starts with TraitSet.update_mimics, so a mimic's set holds the trait it copies). revive_once, split_on_death: mortality.gd.
## Repairs take `seconds` x the repair multiplier of the part's line (of the wall's line for a
## breach). A crew member at a station marks it in `ship.manned` (uid -> name): a manned helm adds
## evasion in a fight and a manned weapon cools down faster (see evasion_bonus, cooldown_mult), and a manned
## smelter works faster (processing.gd; its post is on the board only while it has a queue).
## A crew member posted to a station (CrewMember.post, posts.gd, K1) mans it for good: the board gives them only their post and what
## Posts.allows (a fire or breach in its room, repairing it, restocking its gun's rack), and unposted crew leave a held post alone.
## An abandoned room (evacuate.gd, K2) has no jobs on the board: they wait in `closed`, where only the player's hand (hand_work) reaches them.
## A crew member who breathes and is hurt (hp under crew.json air.hurt_below) walks out of an airless room and takes no job in one until
## their hp is over air.back_above again (K3; drones, vacuum_walk, o2_use 0 and suits are exempt).
## The breath budget (repairs track, crew.json air.breath_margin): a crew member who breathes and wears no suit takes a finite job in an airless room (or whose walk crosses one) only
## when they have breath_margin times the seconds it needs (walk in, work, walk out: _lasts), and leaves one they can no longer finish before hurt_below; their job stays on the board for the next.
## The player's orders are not held to the budget (order_warning says so), but an ordered crew member still leaves when they cannot get out safely any more.
## In a fight a room whose boundary is shot open in too many places is lost (Evacuate.lost_rooms, ship.lost_rooms): its jobs are closed like an abandoned room's and the crew walk out;
## a wall or part hit in the last under_fire.seconds is mended at under_fire.mult of the speed (_fire_mult).
## A repair drone (CrewMember.is_drone, R1) is handed only the jobs of crew.json `drone_jobs`, and only while Power.feed_drones powers it
## (without power it stands still); at 0 hp it is broken, not dead: a crewmate's repair_crew job (or the player's hand) mends it.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Processing = preload("res://scripts/craft/processing.gd")
const Power = preload("res://scripts/sim/power.gd")
const Posts = preload("res://scripts/crew/posts.gd")
const Evacuate = preload("res://scripts/crew/evacuate.gd")
const QUALIFIED_BONUS := 15  ## a station whose abilities need traits: crew who have them prefer it by this much
const UNQUALIFIED_PENALTY := 20  ## ...and crew who lack them look elsewhere first
## The jobs with a finite work time that the breath budget (crew.json air.breath_margin) holds a crew member to in bad air.
const BREATH_JOBS: Array[String] = ["repair_breach", "repair_component", "repair_block", "repair_belt", "clear_wreck", "revive"]
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const FAULTY: Array[String] = ["malfunction", "disabled"]  ## part statuses a crew member can repair
const NO_FIRE := Vector2i(-1, -1)  ## "no burning cell"
const HAND_SHOWN := 0.6  ## seconds the HUD still says what the player was doing by hand
## The jobs that need tools: a crew member with the trait no_tools takes none of them.
const TOOL_JOBS: Array[String] = ["extinguish", "repair_breach", "repair_component", "repair_crew", "repair_belt", "repair_block"]
## The TraitSet work_mult a job type is done at.
const WORK_KIND := {"extinguish": "extinguish", "repair_breach": "breach", "repair_component": "repair", "repair_crew": "repair", "revive": "heal_others", "restock": "restock", "repair_belt": "repair", "repair_block": "repair"}

var board := {}  ## job key -> job: {key, type, priority, cells, slots, work, label, ...}
var progress := {}  ## job key -> seconds of work done so far (kept while the job stays on the board)
var closed := {}  ## job key -> job: the jobs of abandoned rooms, off the board (nobody is sent), but the player's hand_work still does them
var orders := {}  ## job key -> job: repairs the player ordered (F), kept until done
var patients := {}  ## medbay uid -> the name of the one crew member it is healing (a medbay is one bed)
var opened := {}  ## job key -> ship.clock until which a closed job (a lost or abandoned room's) stays on the board because the player sent crew to it
var restocking := {}  ## rack uid -> true: racks a crew member has started filling (they fill them to the top, not just to half)
var combat := false  ## a fight is on: weapons, engines and shields get repaired first
var paths_used := 0  ## path searches the last hand-out made
var _since := 1.0e9  ## seconds since the board was rebuilt (huge: build it on the first tick)


# --- the frame ----------------------------------------------------------------------------------

## Advance the crew of `ship` by `dt` seconds: rebuild the board and hand out jobs when it is time,
## walk and work, then hurt and heal. `in_combat`: a fight is on.
func tick(ship, dt: float, in_combat := false) -> void:
	combat = in_combat
	TraitSet.update_mimics(ship)
	_since += dt
	if _since >= float(jcfg().get("period", 1.0)):
		_since = 0.0
		build_board(ship)
		assign(ship)
	ship.manned.clear()
	for m in ship.crew:
		m.hold = maxf(m.hold - dt, 0.0)
		var stunned: bool = m.is_stunned()
		m.stun = maxf(m.stun - dt, 0.0)
		if m.is_down() or m.is_player or stunned:
			continue
		if m.is_drone() and not Power.drone_fed(ship.power_state, m.name):
			continue  # no power: the drone stands still
		m.step(dt)
		if not m.job.is_empty():
			_do(ship, m, dt)
		elif m.path.is_empty():
			_mend(ship, m, dt)
	_health(ship, dt)


## The player's hand on a job: `m` works the best job they stand next to (not a station) for `dt`
## seconds, at the same speed as an NPC. Returns its key, "" when there is nothing in reach.
func hand_work(ship, m, dt: float) -> String:
	if m.is_down() or m.is_stunned():
		return ""
	var tools: bool = not TraitSet.of(m)["no_tools"]
	for job in by_priority(board.values() + closed.values()):  # (an abandoned room's jobs too: the soldier may still go in)
		if job["type"] != "man_station" and in_reach(m, job) and not _is_own(job, m) and (tools or not job["type"] in TOOL_JOBS):
			work(ship, m, job, dt)
			m.job = {"key": job["key"], "type": job["type"], "label": job["label"], "hand": true, "t": ship.clock}
			return job["key"]
	return ""


## Do `dt` seconds of the work of `job` as crew member `m` (who must be in reach).
func work(ship, m, job: Dictionary, dt: float) -> void:
	match job["type"]:
		"extinguish":
			var c: Vector2i = job["cell"]
			var foot := _fire_under(ship, m)
			var rate := float(jcfg()["extinguish"]["rate"]) * _work_rate(ship, m, "extinguish") * dt
			if ship.fires.has(c) and foot != NO_FIRE:  # the fire has spread under their feet: that one first
				ship.fires[foot] = float(ship.fires[foot]) - rate
				if ship.fires[foot] <= 0.0:
					Fire.extinguish(ship, foot)
					_erase("fire:%d,%d" % [foot.x, foot.y])
				return
			if ship.fires.has(c):
				ship.fires[c] = float(ship.fires[c]) - rate
			if not ship.fires.has(c) or ship.fires[c] <= 0.0:
				Fire.extinguish(ship, c)
				_erase(job["key"])  # done: everyone on it moves on at the next hand-out
				_since = 1.0e9
		"man_station":
			ship.manned[job["uid"]] = m.name
		"restock":  # carries Ammo rate units a second (times their restock work_mult) from the cargo, until the rack is full
			var rack: int = job["uid"]
			restocking[rack] = true
			var per_s := float(jcfg()["restock"]["rate"])
			progress[job["key"]] = float(progress.get(job["key"], 0.0)) + dt * _work_rate(ship, m, "restock")
			var whole := int(float(progress[job["key"]]) * per_s + 1e-6)
			if whole > 0:
				progress[job["key"]] = float(progress[job["key"]]) - float(Ammo.restock(ship, rack, whole)) / per_s
			if Ammo.restock_done(ship, rack):
				restocking.erase(rack)
				progress.erase(job["key"])
				_erase(job["key"])
				_since = 1.0e9
		"repair_breach", "repair_component", "revive", "clear_wreck", "repair_belt", "repair_block":
			var key: String = job["key"]
			var line: String = TraitSet.part_line(ship, job["uid"]) if job["type"] == "repair_component" else ""  # their line_affinity
			progress[key] = float(progress.get(key, 0.0)) + dt * _work_rate(ship, m, job["type"], line) * _fire_mult(ship, job)
			if progress[key] >= float(job["work"]) - 1e-6:
				_finish(ship, job)
		"repair_crew":  # mends the hurt crewmate (hp a second) until they are whole
			var who = _find(ship, func(x): return x.name == job["who"])
			var open: bool = who != null and (not who.is_down() or who.is_drone())  # a broken drone is mended too: above 0 hp it works again
			if open and who.hp < who.max_hp:
				who.heal(float(jcfg()["repair_crew"]["rate"]) * _work_rate(ship, m, "repair_crew") * dt)
			if not open or who.hp >= who.max_hp:
				_erase(job["key"])
				_since = 1.0e9


## How fast `m` does a job of `type`, 1.0 being normal: the work_mult of their traits for it (fast_repair
## works a repair or a breach 1 / 0.6 times as fast, a Basalt revives at half speed), with the swarm and
## aura bonuses of the crew in their room (TraitSet.work_rate), times what the parts in their room do to the work
## (Abilities.work_mult: room_work_mult, wet). `line`: the equipment line of the part they work on (their line_affinity).
static func _work_rate(ship, m, type: String, line := "") -> float:
	return TraitSet.work_rate(ship, m, WORK_KIND.get(type, "repair"), line) * Abilities.work_mult(ship, m)


## The speed factor of a repair of a wall or part that was hit in the last under_fire.seconds (crew.json): under_fire.mult, else 1.
static func _fire_mult(ship, job: Dictionary) -> float:
	var key = job["uid"] if job["type"] == "repair_component" else job.get("cell")
	if key == null or not ship.hit_at.has(key):
		return 1.0
	var c: Dictionary = CrewMember.config().get("under_fire", {})
	return float(c.get("mult", 1.0)) if ship.clock - float(ship.hit_at[key]) < float(c.get("seconds", 0.0)) else 1.0


## Is `job` the mending of `m` themselves? Nobody mends their own body.
static func _is_own(job: Dictionary, m) -> bool:
	return job["type"] == "repair_crew" and job["who"] == m.name


## Take job `key` off the board (and off the closed jobs of abandoned rooms).
func _erase(key: String) -> void:
	board.erase(key)
	closed.erase(key)


# --- the board ----------------------------------------------------------------------------------

## Rebuild the board from the state of `ship`.
func build_board(ship) -> void:
	var b := {}
	var j := jcfg()
	var grid = ship.grid
	Posts.prune(ship)
	Evacuate.sync(ship)
	ship.lost_rooms = Evacuate.lost_rooms(ship) if combat else []
	for k in ship.hit_at.keys():  # (forget the old hits)
		if ship.clock - float(ship.hit_at[k]) > 30.0:
			ship.hit_at.erase(k)
	var holders := Posts.holders(ship)
	var held := {}  # jobs nobody is sent to, but the player's hand may do
	for c in Fire.sorted_cells(ship.fires.keys()):
		_add(b, _job("extinguish", "fire:%d,%d" % [c.x, c.y], [c], {"cell": c}))
	for m in ship.crew:
		if m.is_down() and not m.is_drone():
			if m.revive_t < 0.0:  # one who is about to get up by themselves (revive_once) is left alone
				var revive := _job("revive", "revive:" + m.name, m.body_cells(), {"who": m.name})
				if _revivable(ship, m):
					_add(b, revive)
				else:
					held[revive["key"]] = revive  # (the player's hand may still do it)
		elif m.hp < m.max_hp and TraitSet.of(m)["mechanical"]:  # (a broken drone is mended, not revived)
			_add(b, _job("repair_crew", "mend:" + m.name, m.body_cells(), {"who": m.name}))
	for c in Fire.sorted_cells(grid.breached.keys()):
		var tile: Dictionary = grid.defs.get_def(grid.breached[c]) if grid.defs != null else {}
		var mult := float(ship.lines.get(str(tile.get("line", "standard")), {}).get("repair", 1.0))
		var extra := {"cell": c, "work": float(j["repair_breach"]["seconds"]) * mult}
		var near := _parts_by_breach(ship, c)
		if not near.is_empty():  # a part (a hull mount's inside half) may fill the only floor beside it, so it is worked from beside the part
			extra["reach"] = near
		_add(b, _job("repair_breach", "breach:%d,%d" % [c.x, c.y], [c], extra))
	for c in Fire.sorted_cells(grid.hp.keys()):  # a wall or door below its hp, not shot open: mended where it stands
		if grid.tiles.has(c) and not grid.breached.has(c) and grid.defs != null and grid.defs.get_def(grid.tiles[c]).has("hp") and grid.max_hp_of(c) - grid.hp_of(c) > 1e-6:
			_add(b, _block_job(ship, c))
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		var family := str(def.get("family", ""))
		if inst["status"] in FAULTY or ship.outside_hurt(uid):
			_add(b, _fix_job(ship, uid))
		if family == "helm" or holders.has(uid) or (bool(def.get("manned", false)) and family in j["man_station"]["families"] and Processing.post_wanted(ship, uid)):
			var post := _job("man_station", "post:%d" % uid, inst["cells"], {"uid": uid, "name": def.get("name", inst["id"]), "family": family, "needs": _needs_of(def), "held": holders.get(uid, "")})
			if family != "helm" and (combat if family == "smelter" else not combat):
				# nothing to shoot at: the helm first, the autopilot needs it; a smelter's post only exists while it has work, so it
				# keeps its priority then and gives way to the guns in a fight
				post["priority"] -= int(j["man_station"].get("idle_penalty", 0))
			_add(b, post)
	var need := Ammo.restock_uids(ship, restocking)
	for uid in restocking.keys():
		if not need.has(uid):
			restocking.erase(uid)
	for uid in need:
		_add(b, _job("restock", "stock:%d" % uid, ship.components.instances[uid]["cells"], {"uid": uid, "name": ship.crafting.name_of(Ammo.wanted_item(ship, uid), ship.components)}))
	for c in ship.belts.cut_cells():
		_add(b, _job("repair_belt", "belt:%d,%d" % [c.x, c.y], [c], {"cell": c}))
	for w in ship.components.wrecks:
		_add(b, _job("clear_wreck", "wreck:%d,%d" % [w["cells"][0].x, w["cells"][0].y], w["cells"], {"id": w["id"], "name": ship.components.def(w["id"]).get("name", w["id"])}))
	for key in orders.keys():
		var uid := int(orders[key]["uid"])
		if not ship.components.instances.has(uid) or _fine(ship, uid):
			orders.erase(key)
		else:
			_add(b, orders[key])
	closed = held
	if not Evacuate.rooms(ship).is_empty() or not ship.lost_rooms.is_empty():  # nobody is sent into an abandoned or lost room: its jobs wait for the player's hand (or for the room to reopen, or the fight to end)
		for key in b.keys():
			var rooms := _job_rooms(ship, b[key])
			if not rooms.is_empty() and not _opened(ship, key) and rooms.all(func(r): return Evacuate.is_abandoned(ship, r) or Evacuate.is_lost(ship, r)):
				closed[key] = b[key]
				b.erase(key)
	board = b
	for key in progress.keys():
		if not board.has(key) and not closed.has(key):
			progress.erase(key)


## The player (F in build mode) asks the nearest crew member to repair part `uid`. Returns what to
## tell the player. Unlike the board, an order also covers a part that works but is damaged.
func order_repair(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return "no system under the mouse"
	var inst: Dictionary = ship.components.instances[uid]
	var name: String = ship.components.def(inst["id"]).get("name", inst["id"])
	if inst["status"] == "overheated":
		return "%s is cooling down" % name
	if _fine(ship, uid):
		return "%s needs no repair" % name
	var job := _fix_job(ship, uid)
	var best = null
	var best_d := 1 << 30
	for m in ship.crew:
		if m.is_player or m.is_drone() or m.is_down() or TraitSet.of(m)["no_tools"]:  # (nobody orders a drone about)
			continue
		var d := absi(m.anchor().x - inst["anchor"].x) + absi(m.anchor().y - inst["anchor"].y) + (1000 if m.post >= 0 else 0)  # (a crew member at a post is the last to be sent)
		if d < best_d:
			best = m
			best_d = d
	if best == null:
		return "no crew to send"
	orders[job["key"]] = job
	build_board(ship)
	paths_used = 0
	var route := _route(ship, best, job, _taken(ship, best), false)  # (an order is not held to the breath budget)
	if route.is_empty():
		orders.erase(job["key"])
		build_board(ship)
		return "%s cannot reach %s" % [best.name, name]
	best.hold = 0.0
	_take(ship, best, board[job["key"]], route["spot"], {})
	if not best.job.is_empty():
		best.job["ordered"] = true
	return "%s will repair %s" % [best.name, name]


func _opened(ship, key: String) -> bool:
	return opened.has(key) and float(opened[key]) > ship.clock


## The jobs of the room round `p` (cell units) and the ones within a few cells of it, board and closed alike, in board order (highest priority first). Posts and beds are not jobs to send anyone to.
func jobs_around(ship, p: Vector2) -> Array:
	var cell := Vector2i(floori(p.x), floori(p.y))
	var rooms := _rooms_of_cells(ship, [cell])
	var out: Array = []
	for job in by_priority(board.values() + closed.values()):
		if job["type"] in ["man_station", "rest", "restock"]:
			continue
		var near: bool = _gap(cell, job["cells"]) <= 3
		if near or _job_rooms(ship, job).any(func(r): return rooms.has(r)):
			out.append(job)
	return out


## Send crew `members` (the selected ones) to the jobs round `p` (a point in cell units): one job each in board order (breach, part, block ...), the nearest
## free person first for each; extras stack on the top job's free slots, and one it has no place for stands by near `p`. Each holds the order as long as a single
## order does (crew.json jobs.order_hold) and then keeps the job until it is done. Returns the lines to tell the player (the first says how many went).
func order_group(ship, members: Array, p: Vector2) -> Array:
	var crew: Array = members.filter(func(m): return ship.crew.has(m) and not m.is_player and not m.is_drone() and not m.is_down())
	var lines: Array = []
	if crew.is_empty():
		return ["no crew to send"]
	build_board(ship)
	var list := jobs_around(ship, p)
	var left: Array = crew.duplicate()
	var claims := {}
	var sent := {}  # name -> label
	paths_used = 0
	for job in list:
		if left.is_empty():
			break
		var who = _nearest_member(left, job)
		if _send(ship, who, job, claims):
			left.erase(who)
			sent[who.name] = job["label"]
	for who in left.duplicate():  # more people than jobs: the extras help with the top job
		if not list.is_empty() and int(claims.get(list[0]["key"], 0)) < int(list[0]["slots"]) and _send(ship, who, list[0], claims):
			sent[who.name] = list[0]["label"]
			left.erase(who)
	var taken: Array = []
	for who in left:  # no place for them: they stand by round the point
		var at := _free_spot(ship.grid, p, taken + _taken(ship, who))
		if at != Pathfinder.NO_CELL and order_move(ship, who, at):
			taken.append(at)
			sent[who.name] = "standing by"
	for who in crew:
		if sent.has(who.name):
			lines.append("%s: %s" % [who.name, sent[who.name]])
			var warn := order_warning(ship, who, _work_left(ship, who, who.job) if not who.job.is_empty() else 0.0)
			if warn != "":
				lines.append(warn)
	return lines


## The member of `list` with the shortest walk (Manhattan, from their anchor) to `job`; ties go to the earlier one.
func _nearest_member(list: Array, job: Dictionary):
	var best = null
	var best_d := 1 << 30
	for m in list:
		var d := _gap(m.anchor(), job["cells"])
		if d < best_d:
			best = m
			best_d = d
	return best


## Order `m` to do `job` for good (the player's order): walk to it and keep it until it is done. False when there is no way there.
func _send(ship, m, job: Dictionary, claims: Dictionary) -> bool:
	var route := _route(ship, m, job, _taken(ship, m), false)
	if route.is_empty():
		return false
	if closed.has(job["key"]):  # a job of a lost or abandoned room: the order puts it back on the board for a while
		closed.erase(job["key"])
		board[job["key"]] = job
	opened[job["key"]] = ship.clock + 20.0
	m.path.clear()
	_take(ship, m, job, route["spot"], claims)
	if m.job.is_empty():
		return false
	m.job["ordered"] = true
	m.hold = float(jcfg().get("order_hold", 8.0))
	return true


## The spread key: `members` (the selected crew) drop what they hold and go to the damaged rooms, one each, the room with the highest job first and the
## nearest crew member first; with more people than rooms the next round takes each room's next job. A crew member at a station post keeps it. Returns the
## lines to tell the player.
func spread(ship, members: Array) -> Array:
	var crew: Array = members.filter(func(m): return ship.crew.has(m) and not m.is_player and not m.is_drone() and not m.is_down() and m.post < 0)
	if crew.is_empty():
		return ["no crew to spread out (a crew member at a post keeps it)"]
	build_board(ship)
	var by_room := {}  # room key (smallest cell) -> jobs, highest first
	var order: Array = []
	for job in by_priority(board.values() + closed.values()):
		if job["type"] in ["man_station", "rest", "restock", "clear_wreck"]:
			continue
		var rooms := _job_rooms(ship, job)
		var key: Vector2i = ship.atmosphere.rooms[rooms[0]]["cells"][0] if not rooms.is_empty() else job["cells"][0]
		if not by_room.has(key):
			by_room[key] = []
			order.append(key)
		by_room[key].append(job)
	for m in crew:
		m.job = {}
		m.path.clear()
		m.hold = 0.0
	var left: Array = crew.duplicate()
	var claims := {}
	var lines: Array = []
	var round_ := 0
	paths_used = 0
	while not left.is_empty():
		var any := false
		for key in order:
			if left.is_empty() or by_room[key].size() <= round_:
				continue
			var job: Dictionary = by_room[key][round_]
			any = true
			var who = _nearest_member(left, job)
			if _send(ship, who, job, claims):
				who.hold = 0.0
				left.erase(who)
				lines.append("%s: %s" % [who.name, job["label"]])
		if not any:
			break
		round_ += 1
	if lines.is_empty():
		return ["nothing to repair: the crew go about their business"]
	return lines


## Hand out the jobs on the board to the crew who are free (or ready to switch).
func assign(ship) -> void:
	paths_used = 0
	var claims := {}  # job key -> crew working it
	var free: Array = []
	for m in ship.crew:
		if m.is_player:
			continue
		if m.is_down() or (m.is_drone() and not Power.drone_fed(ship.power_state, m.name)):  # (a drone with no power drops its work)
			m.job = {}
			m.path.clear()
			continue
		_leave_bad_air(ship, m)
		if m.hold > 0.0:
			continue  # on a manual order
		var ordered: bool = bool(m.job.get("ordered", false))  # the player's order for a job: they keep it until it is done or gone
		if not ordered:
			_breath_check(ship, m)
			_leave_lost(ship, m)
			free.append(m)
		if m.job.is_empty():
			continue
		if _still_valid(ship, m):
			if m.job["type"] != "rest":
				claims[m.job["key"]] = int(claims.get(m.job["key"], 0)) + 1
		else:
			m.job = {}
			m.path.clear()
			if ordered:
				free.append(m)
	var margin := int(jcfg().get("switch_margin", 30))
	for m in free:
		var floor_p := 0 if m.job.is_empty() or _on_post(m) else int(m.job["priority"]) + margin  # (anything their post allows beats the post)
		var pick := _pick(ship, m, claims, floor_p)
		if pick.is_empty():
			continue
		if not m.job.is_empty() and m.job["type"] != "rest":
			claims[m.job["key"]] = int(claims[m.job["key"]]) - 1
		_take(ship, m, pick["job"], pick["spot"], claims)
	for m in free:
		if m.job.is_empty() and m.hp < m.max_hp:
			_rest(ship, m)


## The traits a station's abilities ask of whoever mans it (every `operator_needs` entry), [] when none.
static func _needs_of(def: Dictionary) -> Array:
	var out: Array = []
	for a in def.get("abilities", []):
		for n in a.get("operator_needs", []):
			if not n in out:
				out.append(n)
	return out


## `job` as `m` sees it: a station that needs traits is worth more to crew who have them, less to the rest.
static func _for_member(job: Dictionary, m) -> Dictionary:
	if job["type"] == "man_station" and m.post >= 0 and int(job["uid"]) == m.post:  # their own post: the last thing they do
		var posted := job.duplicate()
		posted["priority"] = 1
		return posted
	var needs: Array = job.get("needs", [])
	if job["type"] != "man_station" or needs.is_empty():
		return job
	var j := job.duplicate()
	j["priority"] = int(job["priority"]) + (QUALIFIED_BONUS if Abilities.meets(m, needs) else -UNQUALIFIED_PENALTY)
	return j


## Is the job of `m` still worth doing? Refreshes their copy from the board.
func _still_valid(ship, m) -> bool:
	var job: Dictionary = m.job
	if job["type"] == "rest":
		return m.hp < m.max_hp and _rest_ok(ship, int(job["uid"])) and patients.get(int(job["uid"]), m.name) == m.name
	if not board.has(job["key"]):
		return false
	var spot = job.get("spot")
	var ordered: bool = bool(job.get("ordered", false))
	m.job = board[job["key"]].duplicate()
	m.job["spot"] = spot
	if ordered:
		m.job["ordered"] = true
	if ordered:
		return true
	if m.job["type"] == "man_station" and not str(m.job.get("held", "")) in ["", m.name]:
		return false  # somebody was posted there
	if m.post >= 0 and not orders.has(m.job["key"]) and not Posts.allows(ship, m, m.job):
		return false  # posted since: only what the post allows (and an order of the player's)
	return not (m.winded and _job_airless(ship, m.job))


## The best job for `m` with a priority of at least `floor_p`: {job, spot}, or {} when none.
func _pick(ship, m, claims: Dictionary, floor_p: int) -> Dictionary:
	var open: Array = []
	var tools: bool = not TraitSet.of(m)["no_tools"]
	var drone_jobs: Array = CrewMember.config().get("drone_jobs", []) if m.is_drone() else []
	for key in board:
		var job: Dictionary = board[key]
		if job["priority"] < floor_p or (not m.job.is_empty() and m.job["key"] == key) or _is_own(job, m) or (not tools and job["type"] in TOOL_JOBS):
			continue
		if m.is_drone() and not job["type"] in drone_jobs:
			continue  # a drone takes only the jobs of crew.json drone_jobs: no station, no revive, no mending a crewmate
		if job["type"] == "man_station" and not str(job.get("held", "")) in ["", m.name]:
			continue  # a post somebody holds
		if (m.post >= 0 and not Posts.allows(ship, m, job)) or (m.winded and _job_airless(ship, job)):
			continue  # posted crew do only what the post allows; hurt crew keep out of airless rooms
		if int(claims.get(key, 0)) < int(job["slots"]):
			open.append(job)
	if open.is_empty():
		return {}
	open = by_priority(open.map(func(job): return _for_member(job, m)))
	var taken := _taken(ship, m)
	var i := 0
	while i < open.size():
		var tier: Array = []
		var p: int = open[i]["priority"]
		while i < open.size() and open[i]["priority"] == p:
			tier.append(open[i])
			i += 1
		for want_free in [true, false]:  # jobs nobody works on first
			var cands := tier.filter(func(job): return (int(claims.get(job["key"], 0)) == 0) == want_free)
			var got := _nearest(ship, m, cands, taken)
			if not got.is_empty():
				return got
	return {}


## Of `cands` (equal priority) the one `m` reaches soonest on foot: {job, spot}, or {}.
## Only the few nearest in a straight line get a path search.
func _nearest(ship, m, cands: Array, taken: Array) -> Dictionary:
	var here: Vector2i = m.anchor()
	cands.sort_custom(func(a, b):
		var da := _gap(here, a["cells"])
		var db := _gap(here, b["cells"])
		return da < db or (da == db and a["key"] < b["key"]))
	var best := {}
	var best_cost := 1 << 30
	for job in cands.slice(0, int(jcfg()["search"]["jobs"])):
		var r := _route(ship, m, job, taken)
		if not r.is_empty() and r["cost"] < best_cost:
			best = {"job": job, "spot": r["spot"]}
			best_cost = r["cost"]
	return best


## How `m` gets next to `job`: {cost (cells to walk), spot (a body anchor)}, or {} when there is no
## way (or the search budget of this hand-out is spent).
func _route(ship, m, job: Dictionary, taken: Array, check := true) -> Dictionary:
	if in_reach(m, job):
		if check and not _lasts(ship, m, m.anchor(), [], _work_left(ship, m, job), _margin()):
			return {}
		return {"cost": 0, "spot": m.anchor(), "path": []}
	var grid = ship.grid
	var start := _start(grid, m)
	var spots := stand_spots(ship, job, m.body_size).filter(func(s): return not _clashes(s, taken))
	spots.sort_custom(func(a, b):
		var da := absi(a.x - start.x) + absi(a.y - start.y)
		var db := absi(b.x - start.x) + absi(b.y - start.y)
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var best := {}
	for spot in spots.slice(0, int(jcfg()["search"]["spots"])):
		if paths_used >= int(jcfg()["search"]["paths"]):
			break
		paths_used += 1
		var path := Pathfinder.find_path(grid, start, spot, Callable(), m.body_size)
		if not path.is_empty() and (best.is_empty() or path.size() - 1 < best["cost"]) and (not check or _lasts(ship, m, spot, path, _work_left(ship, m, job), _margin())):
			best = {"cost": path.size() - 1, "spot": spot, "path": path}
	return best


## Give `job` to `m`, standing on anchor `spot`, and start walking there.
func _take(ship, m, job: Dictionary, spot: Vector2i, claims: Dictionary) -> void:
	m.job = job.duplicate()
	m.job["spot"] = spot
	if in_reach(m, job):
		m.path.clear()
	elif not m.go_to(ship.grid, spot):
		m.job = {}
		return
	if job["type"] != "rest":
		claims[job["key"]] = int(claims.get(job["key"], 0)) + 1


## A hurt crew member with nothing to do goes to a powered medbay nobody is in or heading for, else a bed (not where heal_mult is 0).
func _rest(ship, m) -> void:
	var taken := _taken(ship, m)
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var heal: Dictionary = TraitSet.of(m)["heal_mult"]
	for family in ["medbay", "bed"]:
		if float(heal[family]) <= 0.0:
			continue
		var cands: Array = []
		for uid in uids:
			var inst: Dictionary = ship.components.instances[uid]
			if ship.components.def(inst["id"]).get("family", "") == family and _rest_ok(ship, uid) and (family != "medbay" or _medbay_open(ship, uid, m)) and (air_exempt(m) or not _cells_airless(ship, inst["cells"])):
				cands.append(_job("rest", "rest:%d" % uid, inst["cells"], {"uid": uid}))
		var got := _nearest(ship, m, cands, taken)
		if not got.is_empty():
			_take(ship, m, got["job"], got["spot"], {})
			return


## Is medbay `uid` free for `m`: nobody else lies in it hurt, and no other hurt crew member has set off for it? A medbay is one
## bed (playtest 2, P1): a second hurt crew member waits for it or uses a bed.
func _medbay_open(ship, uid: int, m) -> bool:
	if patients.get(uid, m.name) != m.name:
		return false
	for o in ship.crew:
		if o != m and o.hp < o.max_hp and not o.job.is_empty() and o.job["type"] == "rest" and int(o.job.get("uid", -1)) == uid:
			return false
	return true


## A medbay works on one crew member at a time, the one lying on it (hurt or down, and one it can heal). Whoever was there first stays its patient until
## they are healed or leave; then the first of the crew, in list order, lying on it takes over.
func _choose_patients(ship) -> void:
	var next := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if ship.components.def(inst["id"]).get("family", "") != "medbay":
			continue
		var keep: String = patients.get(uid, "")
		var pick := ""
		for m in ship.crew:
			if m.hp < m.max_hp and inst["cells"].has(m.cell()) and float(TraitSet.of(m)["heal_mult"]["medbay"]) > 0.0:  # one a medbay cannot heal does not hold it
				if m.name == keep:
					pick = keep
					break
				if pick == "":
					pick = m.name
		if pick != "":
			next[uid] = pick
	patients = next


func _rest_ok(ship, uid: int) -> bool:
	if not ship.components.instances.has(uid):
		return false
	var inst: Dictionary = ship.components.instances[uid]
	if ship.components.def(inst["id"]).get("family", "") == "medbay":
		return inst["status"] == "ok" and bool(ship.power_state.get("powered", {}).get(uid, false))
	return true


## Is `m` standing at the post they were given (that is their job right now)?
static func _on_post(m) -> bool:
	return m.post >= 0 and not m.job.is_empty() and m.job["type"] == "man_station" and int(m.job.get("uid", -1)) == m.post


# --- bad air (K3) and abandoned rooms (K2) -------------------------------------------------------

## Does `m` need no air, or have a suit? Drones (no breath), vacuum_walk, o2_use 0 and the `suit` trait: they stay in an airless room.
static func air_exempt(m) -> bool:
	if m.is_drone():
		return true
	var t := TraitSet.of(m)
	return bool(t["vacuum_walk"]) or float(t["o2_use"]) <= 0.0 or m.traits().has("suit")


static func _room_airless(ship, room_id: int) -> bool:
	return room_id >= 0 and ship.atmosphere.pressure_of(room_id) < float(CrewMember.config()["no_air_below"])


## The ids of the rooms round `cells`: a cell's own room, else (a wall cell shot open, a doorway) the rooms beside it, and
## beside the other shot-open cells it joins (the outer layer of a hole through thick armour touches no room itself).
static func _rooms_of_cells(ship, cells: Array) -> Array:
	var out := []
	for c in cells:
		var r: int = ship.atmosphere.room_at(c)
		if r >= 0:
			if not out.has(r):
				out.append(r)
			continue
		var seen := {c: true}
		var todo: Array = [c]
		while not todo.is_empty():
			var h: Vector2i = todo.pop_back()
			for d in SIDES:
				var n: Vector2i = h + d
				var nr: int = ship.atmosphere.room_at(n)
				if nr >= 0:
					if not out.has(nr):
						out.append(nr)
				elif ship.grid.breached.has(n) and not seen.has(n):
					seen[n] = true
					todo.append(n)
	return out


static func _job_rooms(ship, job: Dictionary) -> Array:
	return _rooms_of_cells(ship, job["cells"])


static func _cells_airless(ship, cells: Array) -> bool:
	return _rooms_of_cells(ship, cells).any(func(r): return _room_airless(ship, r))


## Is any room of `job` airless?
static func _job_airless(ship, job: Dictionary) -> bool:
	return _cells_airless(ship, job["cells"])


## K3, once a hand-out: a crew member who breathes becomes `winded` when their hp falls under air.hurt_below (a fraction of the
## maximum) and stops being so over air.back_above. While winded they take no job in an airless room (_pick), and one standing
## in such a room drops their job and walks to the nearest room with air (Evacuate.path_out).
func _breath_check(ship, m) -> void:
	if air_exempt(m):
		m.winded = false
		return
	var a: Dictionary = CrewMember.config().get("air", {})
	var frac: float = m.hp / maxf(m.max_hp, 1.0)
	if m.winded:
		m.winded = frac <= float(a.get("back_above", 0.7))
	elif frac < float(a.get("hurt_below", 0.4)):
		m.winded = true
	if m.winded and _room_airless(ship, ship.atmosphere.room_at(m.cell())) and (not m.job.is_empty() or m.path.is_empty()):  # (one already walking out keeps going)
		m.job = {}
		m.path.clear()
		var out := Evacuate.path_out(ship, m)
		if not out.is_empty():
			m.path.assign(out)


# --- the breath budget and lost rooms (repairs track) --------------------------------------------

static func _margin() -> float:
	return float(CrewMember.config().get("air", {}).get("breath_margin", 1.25))


## Hp a second that bad air costs `m` (crew.json damage_per_s.no_air x their damage_taken.no_air x suffocate_mult); 0 for anyone it cannot hurt.
static func suffocation(m) -> float:
	if air_exempt(m):
		return 0.0
	var t := TraitSet.of(m)
	return float(CrewMember.config()["damage_per_s"]["no_air"]) * float(t["damage_taken"]["no_air"]) * float(t["suffocate_mult"])


static func _anchor_airless(ship, anchor: Vector2i, body: int) -> bool:
	return _room_airless(ship, Evacuate.room_at_anchor(ship, anchor, body))


## The seconds of work `m` still has on `job` (what is done is kept in `progress`), at their own speed.
func _work_left(ship, m, job: Dictionary) -> float:
	if not job["type"] in BREATH_JOBS:
		return 0.0
	var line: String = TraitSet.part_line(ship, job["uid"]) if job["type"] == "repair_component" else ""
	return maxf(float(job.get("work", 0.0)) - float(progress.get(job["key"], 0.0)), 0.0) / maxf(_work_rate(ship, m, job["type"], line) * _fire_mult(ship, job), 0.05)


## Can `m` stand the bad air of a trip to `spot` (walking the body anchors of `path`, then `work` seconds of work there, then out to air)? They need
## `margin` times the seconds they spend in rooms with no air to be less than the seconds they have before their hp falls to air.hurt_below, minus
## `extra` seconds. True without any bad air on the way, and for anyone it cannot hurt (suit, vacuum_walk, no breath). Work counts only in a spot with no air.
static func _lasts(ship, m, spot: Vector2i, path: Array, work: float, margin: float, extra := 0.0) -> bool:
	var rate := suffocation(m)
	if rate <= 0.0 or _margin() <= 0.0:  # (a margin of 0 in the data turns the budget off)
		return true
	var any := false
	for r in ship.atmosphere.rooms:
		if _room_airless(ship, int(r["id"])):
			any = true
			break
	if not any:
		return true
	var speed := maxf(m.speed * m.speed_mod, 0.1)
	var steps := 0
	for p in path:
		steps += int(_anchor_airless(ship, p, m.body_size))
	var t := float(steps) / speed
	if _anchor_airless(ship, spot, m.body_size):
		t += work
		var out := Evacuate.path_out(ship, m, spot)
		if out.is_empty():
			return false  # no way out of there
		for p in out:
			t += float(_anchor_airless(ship, p, m.body_size)) / speed
	elif steps == 0:
		return true
	var have: float = (m.hp - float(CrewMember.config().get("air", {}).get("hurt_below", 0.4)) * m.max_hp) / rate
	return have >= margin * t + extra


## `m` leaves bad air before it hurts: a crew member on a finite job in an airless room who can no longer finish it before air.hurt_below drops it
## (the job stays on the board for the next) and walks out; one on the player's order (it has no work counted) leaves when they cannot get out safely
## any more, with a short line for the log. Once a hand-out.
func _leave_bad_air(ship, m) -> void:
	if air_exempt(m) or m.winded or _margin() <= 0.0:
		return  # (a winded one already walks out: _breath_check)
	var ordered: bool = m.hold > 0.0 or bool(m.job.get("ordered", false))
	var idle: bool = m.job.is_empty() and m.path.is_empty() and not ordered and _room_airless(ship, ship.atmosphere.room_at(m.cell()))  # (an order that ran out in bad air, say)
	var spot: Vector2i = m.anchor()
	var work := 0.0
	if ordered:
		spot = m.path.back() if not m.path.is_empty() else (m.job.get("spot", m.anchor()) if not m.job.is_empty() else m.anchor())
	elif not m.job.is_empty() and m.job["type"] in BREATH_JOBS:
		spot = m.job.get("spot", m.anchor())
		work = _work_left(ship, m, m.job)
	elif not idle:
		return
	var period := float(jcfg().get("period", 1.0))
	if not idle and _lasts(ship, m, spot, m.path, work, 1.0, period):
		return
	var out := Evacuate.path_out(ship, m)
	if out.is_empty() and _room_airless(ship, ship.atmosphere.room_at(m.cell())):
		return  # nowhere to go: they stay with what they were doing
	m.job = {}
	m.hold = 0.0
	m.path.clear()
	m.path.assign(out)
	_since = 1.0e9
	if ordered:  # the one case an order is dropped for the sake of their lungs
		ship.log_event("%s leaves their order: the air is too thin" % m.name)


## The line under a middle-click order (Jobs.order_move or a group order): "<name> won't last in there" when `m`, sent where their path ends, could not
## do it on the breath budget (the order stands all the same), else "". `work`: the seconds of work at the end of it.
static func order_warning(ship, m, work := 0.0) -> String:
	var spot: Vector2i = m.path.back() if not m.path.is_empty() else m.anchor()
	return "" if _lasts(ship, m, spot, m.path, work, _margin()) else "%s won't last in there" % m.name


## Can downed `m` be revived where they lie? In bad air only when they could walk out alive on the hp the revive gives them (crew.json revive_hp, breath_margin
## times the airless walk): else they would go down again in the same room, and whoever revived them would have spent the breath for nothing.
static func _revivable(ship, m) -> bool:
	var rate := suffocation(m)
	if rate <= 0.0 or _margin() <= 0.0 or not _room_airless(ship, ship.atmosphere.room_at(m.cell())):
		return true
	if m.is_player:
		return false  # the soldier walks only when the player says so: nobody revives them into bad air
	var out := Evacuate.path_out(ship, m)
	if out.is_empty():
		return false
	var steps := 0
	for p in out:
		steps += int(_anchor_airless(ship, p, m.body_size))
	return float(CrewMember.config().get("revive_hp", 20)) / rate >= _margin() * float(steps) / maxf(m.speed, 0.1)


## A crew member in a lost room walks out to air (the room posts no jobs); the soldier is their own master.
func _leave_lost(ship, m) -> void:
	if ship.lost_rooms.is_empty() or not Evacuate.is_lost(ship, ship.atmosphere.room_at(m.cell())) or not (not m.job.is_empty() or m.path.is_empty()):
		return
	m.job = {}
	m.path.clear()
	m.path.assign(Evacuate.path_out(ship, m))


# --- walking and working ------------------------------------------------------------------------

## One tick of a crew member with a job: drop it when it is gone, walk to the spot, work in reach.
func _do(ship, m, dt: float) -> void:
	var job: Dictionary = m.job
	if job["type"] != "rest" and not board.has(job["key"]):
		_drop(m)
		return
	if job["type"] == "extinguish" and not ship.fires.has(job["cell"]):
		_drop(m)
		return
	if not m.path.is_empty():
		return
	if in_reach(m, job):
		if job["type"] != "rest":
			work(ship, m, job, dt)
	elif not m.go_to(ship.grid, job["spot"]):
		_drop(m)


func _drop(m) -> void:
	m.job = {}
	m.path.clear()
	_since = 1.0e9  # hand out again at once


func _finish(ship, job: Dictionary) -> void:
	var key: String = job["key"]
	progress.erase(key)
	orders.erase(key)
	_erase(key)
	_since = 1.0e9
	match job["type"]:
		"clear_wreck":
			var w: Dictionary = ship.components.clear_wreck(ship.components.wreck_at(job["cells"][0]))
			if not w.is_empty():
				var refund: Dictionary = ship.wreck_refund(w["id"])
				if refund.has("scrap"):
					refund["scrap"] = roundi(float(refund["scrap"]) * TraitSet.scrap_mult(ship))  # (scrap gauntlets)
				for m in refund:
					ship.inventory.add(m, refund[m])
				ship.log_event("Cleared the wreck of %s%s" % [job["name"], " (+%s)" % ", ".join(refund.keys().map(func(m): return "%d %s" % [refund[m], m])) if not refund.is_empty() else ""])
		"repair_breach":
			if ship.grid.repair(job["cell"]):
				ship.mark_dirty()
				ship.log_event("Breach sealed")
		"repair_belt":
			if ship.belts.repair(job["cell"]):
				ship.log_event("Belt repaired")
		"repair_block":
			ship.grid.hp.erase(job["cell"])  # a cell that is not listed has full hp
		"repair_component":
			if ship.repair(job["uid"]):
				ship.log_event("%s repaired" % job["name"])
		"revive":
			for m in ship.crew:
				if m.name == job["who"] and m.is_down():
					m.hp = minf(float(CrewMember.config().get("revive_hp", 20)), m.max_hp)
					ship.log_event("%s is back on their feet" % m.name)


## The first burning cell under the body of `m` (in (y, x) order), or NO_FIRE.
func _fire_under(ship, m) -> Vector2i:
	var best := NO_FIRE
	for c in m.body_cells():
		if ship.fires.has(c) and (best == NO_FIRE or c.y < best.y or (c.y == best.y and c.x < best.x)):
			best = c
	return best


## Hurt and heal every crew member: fire, thin air, hot rooms (dries_out), beds, medbays and auras
## (data/crew.json, and the traits of each: damage_taken, o2_use, suffocate_mult, vacuum_walk, heal_mult, aura),
## and set how fast each walks in the heat of their room (CrewMember.speed_mod, trait heat_speed).
func _health(ship, dt: float) -> void:
	var cfg := CrewMember.config()
	var dps: Dictionary = cfg["damage_per_s"]
	var auras := TraitSet.room_auras(ship)
	var heats := {}  # room id -> heat of its hottest part, read once and only if somebody dries out
	var heats_read := false
	_choose_patients(ship)
	for m in ship.crew:
		var t := TraitSet.of(m)
		var was_down: bool = m.is_down()
		var dmg := 0.0
		for c in m.body_cells():
			if ship.fires.has(c):
				dmg += float(dps["fire"]) * float(t["damage_taken"]["fire"])
				break
		var room: int = ship.atmosphere.room_at(m.cell())
		if room >= 0 and ship.atmosphere.pressure_of(room) < float(cfg["no_air_below"]) and float(t["o2_use"]) > 0.0 and not t["vacuum_walk"]:
			dmg += float(dps["no_air"]) * float(t["damage_taken"]["no_air"]) * float(t["suffocate_mult"])
		var dry: Dictionary = t["dries_out"]
		var hs: Dictionary = t["heat_speed"]
		var by_heat: bool = float(hs["cold"]) != 1.0 or float(hs["hot"]) != 1.0
		var heat := 0.0
		if room >= 0 and (float(dry["hp_per_s"]) > 0.0 or by_heat):
			if not heats_read:
				heats = Heat.room_heat(ship)
				heats_read = true
			heat = float(heats.get(room, 0.0))
			if heat > float(dry["heat_above"]) and float(dry["hp_per_s"]) > 0.0:
				dmg += float(dry["hp_per_s"])
		m.speed_mod = (TraitSet.heat_factor(t, heat) if room >= 0 and by_heat else 1.0) * float(t["walk_mult"])
		if room >= 0 and float(t["vacuum_speed"]) != 1.0:  # in thin air (vacuum_speed)
			m.speed_mod *= TraitSet.thin_air_factor(t, ship.atmosphere.pressure_of(room))
		if dmg > 0.0:
			m.hurt(dmg * dt)
		var heal := _heal_rate(ship, m) + float(auras.get(room, {}).get("heal_per_s", 0.0))
		if room >= 0:
			heal += TraitSet.low_pressure_heal_rate(t, ship.atmosphere.pressure_of(room))
		if heal > 0.0:
			m.heal(heal * dt)
		if m.is_down() and not was_down:
			m.job = {}
			m.path.clear()
			ship.log_event(("%s is broken" if m.is_drone() else "%s is down") % m.name)
		elif was_down and not m.is_down():
			ship.log_event(("%s is working again" if m.is_drone() else "%s is back on their feet") % m.name)


## An idle crew member with the trait hull_mend mends what is next to their body: `rate` hp a second go to the
## damaged walls beside them (the first in (y, x) order first), and a breach is sealed after `seal` seconds beside it
## (CrewMember.mend_t counts them, and starts over when no breach is beside them). Nothing without the trait; a crew
## member with a job or a path does not mend.
func _mend(ship, m, dt: float) -> void:
	var mend: Dictionary = TraitSet.of(m)["hull_mend"]
	var rate := float(mend["rate"])
	var seal := float(mend["seal"])
	var grid = ship.grid
	var breach := NO_FIRE
	if rate > 0.0 or seal > 0.0:
		var body: Array[Vector2i] = m.body_cells()
		var beside := {}
		for c in body:
			for d in SIDES:
				if not body.has(c + d):
					beside[c + d] = true
		var budget := rate * dt
		for c in Fire.sorted_cells(beside.keys()):
			if budget > 0.0 and grid.hp.has(c) and grid.tile_flag(grid.get_tile(c), "solid"):
				var top: float = grid.max_hp_of(c)
				var now := minf(float(grid.hp[c]) + budget, top)
				budget -= now - float(grid.hp[c])
				if now >= top:
					grid.hp.erase(c)  # a cell that is not listed has full hp
				else:
					grid.hp[c] = now
			if seal > 0.0 and breach == NO_FIRE and grid.breached.has(c):
				breach = c
	if breach == NO_FIRE:
		m.mend_t = 0.0
		return
	m.mend_t += dt
	if m.mend_t >= seal - 1e-6:
		m.mend_t = 0.0
		_finish(ship, {"key": "breach:%d,%d" % [breach.x, breach.y], "type": "repair_breach", "cell": breach})


## hp per second where `m` lies: a bed, or a medbay that is on (its stats.heal scales the rate), times their heal_mult for it.
## Neither heals a crew member who breathes while its room has no air.
func _heal_rate(ship, m) -> float:
	var uid: int = ship.components.at(m.cell())
	if uid < 0:
		return 0.0
	var inst: Dictionary = ship.components.instances[uid]
	var def: Dictionary = ship.components.def(inst["id"])
	var rates: Dictionary = CrewMember.config()["heal_per_s"]
	var heal: Dictionary = TraitSet.of(m)["heal_mult"]
	var family := str(def.get("family", ""))
	if (family == "bed" or family == "medbay") and _room_airless(ship, ship.atmosphere.room_at(m.cell())) and not air_exempt(m):
		return 0.0  # a bed that outheals the suffocation (5 and 5) keeps them lying there: with no air it heals nobody who breathes (a medbay no more), and they leave at air.hurt_below
	match family:
		"bed":
			return float(rates["bed"]) * float(heal["bed"])
		"medbay":
			if _rest_ok(ship, uid) and patients.get(uid, m.name) == m.name:  # one bed: only its patient heals (_health picks it first)
				return float(rates["medbay"]) * float(def.get("stats", {}).get("heal", 1.0)) * float(heal["medbay"])
	return 0.0


## An ion hit of `amount` damage lands on `cell` (Damage.apply calls this): every crew member in a room
## that touches it takes crew.json `ion_hp` x amount x their damage_taken.ion hit points and is stunned
## for their ion_stun seconds.
static func ion_hit(ship, cell: Vector2i, amount: float) -> void:
	var rooms := {}
	for d in [Vector2i.ZERO] + SIDES:
		var r: int = ship.atmosphere.room_of.get(cell + d, -1)
		if r >= 0:
			rooms[r] = true
	for m in ship.crew:
		if not rooms.has(ship.atmosphere.room_of.get(m.cell(), -1)):
			continue
		var t := TraitSet.of(m)
		var hp := float(CrewMember.config().get("ion_hp", 0.0)) * amount * float(t["damage_taken"]["ion"])
		var was_down: bool = m.is_down()
		if hp > 0.0:
			m.hurt(hp)
		m.stun = maxf(m.stun, float(t["ion_stun"]))
		if m.is_down() and not was_down:
			m.job = {}
			m.path.clear()
			ship.log_event("%s is down" % m.name)


# --- places to stand ----------------------------------------------------------------------------

## Is `m` standing next to the cells of `job` (or on them)? For rest: lying on the bed.
func in_reach(m, job: Dictionary) -> bool:
	if job["type"] == "rest":
		return job["cells"].has(m.cell())
	var body: Array[Vector2i] = m.body_cells()
	for c in job["cells"] + job.get("reach", []):
		for b in body:
			if absi(b.x - c.x) + absi(b.y - c.y) <= 1:
				return true
	return false


## Body anchors from which a crew member reaches `job`: next to its cells, not on them (rest: with
## the body's centre on the bed). Spots clear of fire, of doorways, then of parts, are preferred; (y, x) order.
## `body`: the size of the body that stands there (a small one, 1, also finds spots in crawlspaces).
func stand_spots(ship, job: Dictionary, body := Pathfinder.BODY) -> Array[Vector2i]:
	var grid = ship.grid
	var inside := {}
	for c in job["cells"]:
		inside[c] = true
	var seen := {}
	var all: Array[Vector2i] = []
	for c in job["cells"]:
		if job["type"] == "rest":
			_try_spot(grid, c - Vector2i.ONE * (body - 1), [], seen, all, body)
			continue
		for n in _beside(c, inside):
			for oy in body:
				for ox in body:
					_try_spot(grid, n - Vector2i(ox, oy), inside, seen, all, body)
	if all.is_empty() and job.has("reach"):  # a breach in a mount's wall: beside the mount's inside half
		var near := {}
		for c in job["reach"]:
			near[c] = true
		for c in job["reach"]:
			for n in _beside(c, near):
				for oy in body:
					for ox in body:
						_try_spot(grid, n - Vector2i(ox, oy), near, seen, all, body)
	if all.is_empty() and job["type"] != "rest":  # no room beside it: stand on it
		for c in job["cells"]:
			for oy in body:
				for ox in body:
					_try_spot(grid, c - Vector2i(ox, oy), [], seen, all, body)
	all.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var safe := all.filter(func(a): return not Pathfinder.body_cells(a, body).any(func(c): return ship.fires.has(c)))
	if not safe.is_empty():
		all.assign(safe)
	var apart := all.filter(func(a): return not Pathfinder.body_cells(a, body).any(func(c): return ship.grid.tile_flag(ship.grid.get_tile(c), "door")))
	if not apart.is_empty():  # not in a doorway: a body there holds the door open
		all.assign(apart)
	var clear := all.filter(func(a): return not Pathfinder.body_cells(a, body).any(func(c): return ship.components.at(c) >= 0))
	if not clear.is_empty():
		all.assign(clear)
	return all


## The cells of the parts round breach cell `c`: the mount whose wall it is in or beside, and any part on a cell beside it.
func _parts_by_breach(ship, c: Vector2i) -> Array:
	var uids := {}
	if ship.components.link_at(c) >= 0:
		uids[ship.components.link_at(c)] = true
	for d in SIDES:
		var uid: int = ship.components.at(c + d)
		if uid >= 0:
			uids[uid] = true
		var mount: int = ship.components.link_at(c + d)  # the wall beside a mount's wall: its inside half fills the floor there too
		if mount >= 0:
			uids[mount] = true
	var keys: Array = uids.keys()
	keys.sort()
	var out: Array = []
	for uid in keys:
		out.append_array(ship.components.instances[uid]["cells"])
	return out


func _beside(c: Vector2i, inside: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in SIDES:
		if not inside.has(c + d):
			out.append(c + d)
	return out


## Add `anchor` to `out` once if a body fits there and none of its cells is in `avoid`.
func _try_spot(grid, anchor: Vector2i, avoid, seen: Dictionary, out: Array[Vector2i], body := Pathfinder.BODY) -> void:
	if seen.has(anchor):
		return
	seen[anchor] = true
	if not Pathfinder.body_ok(grid, anchor, Callable(), body):
		return
	for c in Pathfinder.body_cells(anchor, body):
		if avoid.has(c):
			return
	out.append(anchor)


## Where `m` starts walking from: their own anchor, or the nearest one a body fits on.
func _start(grid, m) -> Vector2i:
	var a: Vector2i = m.anchor()
	return a if Pathfinder.body_ok(grid, a, Callable(), m.body_size) else Pathfinder.nearest_walkable(grid, m.pos, Callable(), Pathfinder.NO_CELL, m.body_size)


## Spots other crew are standing on or heading for (so two bodies do not end up on one spot).
func _taken(ship, me) -> Array:
	var out := []
	for o in ship.crew:
		if o != me:
			out.append(o.job["spot"] if not o.job.is_empty() and o.job.has("spot") else o.anchor())
	return out


static func _clashes(spot: Vector2i, taken: Array) -> bool:
	for t in taken:
		if absi(spot.x - t.x) < Pathfinder.BODY and absi(spot.y - t.y) < Pathfinder.BODY:
			return true
	return false


## The distance in cells (Manhattan) from `a` to the nearest of `cells`.
static func _gap(a: Vector2i, cells: Array) -> int:
	var best := 1 << 30
	for c in cells:
		best = mini(best, absi(a.x - c.x) + absi(a.y - c.y))
	return best


# --- building jobs ------------------------------------------------------------------------------

static func jcfg() -> Dictionary:
	return CrewMember.config().get("jobs", {})


## A job of `type` from the data (priority, slots, seconds), with `extra` laid over it.
static func _job(type: String, key: String, cells: Array, extra := {}) -> Dictionary:
	var c: Dictionary = jcfg().get(type, {})
	var job := {"key": key, "type": type, "priority": int(c.get("priority", 0)), "cells": cells,
		"slots": int(c.get("slots", 1)), "work": float(c.get("seconds", 0.0))}
	job.merge(extra, true)
	job["label"] = label_of(job)
	return job


## repair_block for the damaged wall or door on `c`: seconds_per_hp for each hp missing times its line's repair multiplier;
## calm_bonus on the priority while no fight is on (a part still comes first).
func _block_job(ship, c: Vector2i) -> Dictionary:
	var grid = ship.grid
	var cfg: Dictionary = jcfg()["repair_block"]
	var mult := float(ship.lines.get(str(grid.defs.get_def(grid.tiles[c]).get("line", "standard")), {}).get("repair", 1.0))
	var extra := {"cell": c, "priority": int(cfg["priority"]) + (0 if combat else int(cfg["calm_bonus"])),
		"work": float(cfg["seconds_per_hp"]) * (grid.max_hp_of(c) - grid.hp_of(c)) * mult}
	var near := _parts_by_breach(ship, c)
	if not near.is_empty():  # a part may fill the only floor beside it: worked from beside the part
		extra["reach"] = near
	return _job("repair_block", "block:%d,%d" % [c.x, c.y], [c], extra)


## repair_component for part `uid`: its seconds in data/crew.json x the line's repair multiplier; weapons, engines and shields
## come first in a fight.
func _fix_job(ship, uid: int) -> Dictionary:
	var inst: Dictionary = ship.components.instances[uid]
	var def: Dictionary = ship.components.def(inst["id"])
	var c: Dictionary = jcfg()["repair_component"]
	var priority := int(c["priority"])
	if combat and str(def.get("family", "")) in c["combat_families"]:
		priority += int(c["combat_bonus"])
	return _job("repair_component", "fix:%d" % uid, inst["cells"], {"uid": uid, "name": def.get("name", inst["id"]),
		"priority": priority, "work": float(c["seconds"]) * float(ship.effective(inst["id"])["repair_mult"])})


## Works and not damaged: nothing to repair.
func _fine(ship, uid: int) -> bool:
	var inst: Dictionary = ship.components.instances[uid]
	return inst["status"] == "ok" and float(inst["hp"]) >= float(ship.effective(inst["id"])["hp"]) and not ship.outside_hurt(uid)


static func _add(board_: Dictionary, job: Dictionary) -> void:
	board_[job["key"]] = job


## Jobs highest priority first, then by key.
static func by_priority(list: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a, b): return a["priority"] > b["priority"] or (a["priority"] == b["priority"] and a["key"] < b["key"]))
	return out


## The HUD words for a job (data/crew.json labels).
static func label_of(job: Dictionary) -> String:
	var words: Dictionary = CrewMember.config().get("labels", {})
	if job["type"] == "man_station" and words.has("station_" + str(job.get("family", ""))):
		return str(words["station_" + str(job["family"])])
	return str(words.get(job["type"], job["type"])).replace("{name}", str(job.get("name", ""))).replace("{who}", str(job.get("who", "")))


# --- the crew line and the manned bonuses -------------------------------------------------------

## "Crew: Ada repairing Laser Mk1, Rook extinguishing, Juno at helm". The player is named only when
## down, hurt or working by hand.
static func crew_line(ship) -> String:
	var words: Dictionary = CrewMember.config().get("labels", {})
	var parts: Array[String] = []
	for m in ship.crew:
		var state := ""
		if m.is_down():
			state = str(words.get("down", "down"))
		elif m.is_player:
			if not m.job.is_empty() and ship.clock - float(m.job.get("t", -99.0)) < HAND_SHOWN:
				state = str(m.job["label"])
			elif m.hp < m.max_hp:
				state = "hurt (%d hp)" % roundi(m.hp)
		else:
			state = str(m.job["label"]) if not m.job.is_empty() else str(words.get("idle", "idle"))
		if state != "":
			parts.append("%s %s" % ["You" if m.is_player else m.name, state])
	return "Crew: " + (", ".join(parts) if not parts.is_empty() else "none")


## The evasion a manned helm adds in a fight (0 when nobody is at it), times the operator's manned factor
## (and an overclock of the helm), plus the operator's own station.evasion_add.
static func evasion_bonus(ship) -> float:
	for uid in ship.manned:
		if _family(ship, uid) == "helm" and _works(ship, uid):
			return float(CrewMember.config()["manned"]["helm_evasion"]) * TraitSet.manned_factor(ship, uid) * CrewFx.overclock_mult(ship, uid) + TraitSet.helm_evasion_add(ship, uid)
	return 0.0


## Multiplier on the cooldown of weapon `uid`: shorter while somebody mans it (by the operator's manned factor, at
## most 90%), and shorter still by the factor of an overclock running on it.
static func cooldown_mult(ship, uid: int) -> float:
	var f := 1.0
	if ship.manned.has(uid) and _family(ship, uid) == "weapon" and _works(ship, uid):
		f = 1.0 - minf(float(CrewMember.config()["manned"]["weapon_cooldown"]) * TraitSet.manned_factor(ship, uid), 0.9)
	return f / CrewFx.overclock_mult(ship, uid)


static func _family(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return ""
	return str(ship.components.def(ship.components.instances[uid]["id"]).get("family", ""))


static func _works(ship, uid: int) -> bool:
	return ship.components.instances.has(uid) and ship.components.instances[uid]["status"] == "ok"


# --- people -------------------------------------------------------------------------------------

## Make sure `ship` has its starting crew: the design's crew list when it has one (`ship.crew_plan`,
## names and species; the entry named like the player in data/crew.json, or marked `player`, is the soldier), else the player's soldier, Ada, and `extra_crew` more NPCs at the beds
## (data/crew.json). Only adds what is missing, and stops at the first one that finds no place for a
## body yet. Returns the new members.
static func spawn_crew(ship) -> Array:
	if not ship.crew_plan.is_empty():
		return _spawn_planned(ship)
	var cfg := CrewMember.config()
	var grid = ship.grid
	var mid := Vector2(grid.size) / 2.0
	var out := []
	var player = _find(ship, func(m): return m.is_player)
	if player == null:
		var c := Pathfinder.nearest_walkable(grid, mid)
		if c == Pathfinder.NO_CELL:
			return out
		player = _person(cfg["player"]["name"], cfg["player"]["look"], Pathfinder.centre_of(c))
		player.is_player = true
		ship.crew.append(player)
		out.append(player)
	var ada_name: String = cfg["ada"]["name"]
	if _find(ship, func(m): return m.name == ada_name) == null and not ship.dead_crew.has(ada_name):
		var c := Pathfinder.nearest_walkable(grid, mid, Callable(), player.anchor())
		if c == Pathfinder.NO_CELL:
			return out
		var ada = _person(ada_name, cfg["ada"]["look"], Pathfinder.centre_of(c))
		ship.crew.append(ada)
		out.append(ada)
	var beds := _beds(ship)
	var have: int = ship.crew.filter(func(m): return not m.is_player and m.name != ada_name).size() + ship.dead_crew.filter(func(n): return n != ada_name).size()  # the dead stay dead
	while have < int(cfg.get("extra_crew", 0)):
		var near := mid
		if not beds.is_empty():
			near = Pathfinder.centre_of(beds[have % beds.size()])
		var spot := _free_spot(grid, near, _anchors(ship))
		if spot == Pathfinder.NO_CELL:
			break
		var looks: Array = cfg["looks"]
		var m = _person(_next_name(ship, cfg["names"]), looks[have % looks.size()], Pathfinder.centre_of(spot))
		ship.crew.append(m)
		out.append(m)
		have += 1
	return out


## spawn_crew for a design with a crew list: each entry not aboard yet, in order. The entry named
## like the player in data/crew.json is the soldier and Ada's gets her look; both stand on the spots
## nearest the middle. The others take the colours of `looks` in order and stand at the beds, the
## n-th at bed n (round the beds when there are fewer).
static func _spawn_planned(ship) -> Array:
	var cfg := CrewMember.config()
	var grid = ship.grid
	var mid := Vector2(grid.size) / 2.0
	var beds := _beds(ship)
	var out := []
	var npc := 0
	for e in ship.crew_plan:
		var who: String = e["name"]
		var is_player: bool = who == cfg["player"]["name"] or bool(e.get("player", false))  # a renamed soldier is marked `player` (run_start.gd)
		var is_ada: bool = who == cfg["ada"]["name"]
		var drone: bool = CrewMember.is_drone_species(str(e["species"]))  # a drone is no crew: it has no bed and no colours of its own
		var nth := npc
		if not is_player and not is_ada and not drone:
			npc += 1
		if _find(ship, func(m): return m.name == who) != null or ship.dead_crew.has(who):
			continue
		var near := mid
		var look: Dictionary = cfg["player"]["look"] if is_player else cfg["ada"]["look"]
		if drone:
			look = {}
		elif not is_player and not is_ada:
			look = cfg["looks"][nth % cfg["looks"].size()]
			if not beds.is_empty():
				near = Pathfinder.centre_of(beds[nth % beds.size()])
		var spot := _free_spot(grid, near, _anchors(ship))
		if spot == Pathfinder.NO_CELL:
			break
		var m = _person(who, look, Pathfinder.centre_of(spot, 1) if drone else Pathfinder.centre_of(spot), str(e["species"]))
		m.is_player = is_player
		ship.crew.append(m)
		out.append(m)
	return out


## The crew of a ship that is not the player's: the design's crew list when it has one, else
## `enemy.count` people (data/crew.json), round the helm. Returns the new members (none when the
## ship has no floor yet).
static func spawn_enemy_crew(ship) -> Array:
	var cfg: Dictionary = CrewMember.config()["enemy"]
	var grid = ship.grid
	var near := Vector2(grid.size) / 2.0
	if not grid.hull.is_empty():
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in grid.hull:
			lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
			hi = Vector2(maxf(hi.x, c.x + 1.0), maxf(hi.y, c.y + 1.0))
		near = (lo + hi) / 2.0
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if _family(ship, uid) == "helm":
			near = Pathfinder.centre_of(ship.components.instances[uid]["cells"][0])
			break
	var out := []
	var plan: Array = ship.crew_plan
	for i in (plan.size() if not plan.is_empty() else int(cfg["count"])):
		var spot := _free_spot(grid, near, _anchors(ship))
		if spot == Pathfinder.NO_CELL:
			break
		var entry: Dictionary = plan[i] if not plan.is_empty() else {}
		var names: Array = cfg["names"]
		var m = _person(str(entry.get("name", _next_name(ship, names))), cfg["look"], Pathfinder.centre_of(spot), str(entry.get("species", "human")))
		var wr := RandomNumberGenerator.new()  # (an enemy's crew wear their race's gear, drawn: from the species alone, seeded by the ship and the person)
		wr.seed = hash([str(ship.name), i, m.name])
		m.kit = load("res://scripts/board/wear.gd").kit_of(load("res://scripts/board/wear.gd").for_crew(m.species, wr))
		ship.crew.append(m)
		out.append(m)
	return out


## Repair drones in the cargo (data/crew.json drone.item: a fabricator made one, a station sold one) go aboard, one small body each,
## beside the fabricator (the middle of the ship without one). Returns the new members. One that finds no room stays in the cargo.
static func launch_drones(ship) -> Array:
	var cfg: Dictionary = CrewMember.config().get("drone", {})
	var item := str(cfg.get("item", ""))
	var out := []
	while item != "" and ship.inventory.count(item) > 0:
		var spot := _free_spot(ship.grid, _drone_home(ship), _anchors(ship))
		if spot == Pathfinder.NO_CELL:
			break
		ship.inventory.add(item, -1)
		var m = _person(drone_name(ship), {}, Pathfinder.centre_of(spot, 1), str(cfg.get("species", "drone")))
		ship.crew.append(m)
		out.append(m)
		ship.log_event("%s is aboard" % m.name)
	return out


## Where a new drone appears: the first cell of the fabricator, else the middle of the grid.
static func _drone_home(ship) -> Vector2:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if _family(ship, uid) == "fabricator":
			return Pathfinder.centre_of(ship.components.instances[uid]["cells"][0])
	return Vector2(ship.grid.size) / 2.0


## The name of the next drone of `ship`: data/crew.json drone.name, then "<name> 2", "<name> 3" ...
static func drone_name(ship) -> String:
	var base := str(CrewMember.config().get("drone", {}).get("name", "Drone"))
	for n in range(1, 100):
		var who := base if n == 1 else "%s %d" % [base, n]
		if _find(ship, func(m): return m.name == who) == null:
			return who
	return base


## Why drone `m` is idle: "broken" (0 hp), "no power" (Power.feed_drones left it none), else "". Always "" for anyone but a drone.
static func drone_status(ship, m) -> String:
	if not m.is_drone():
		return ""
	var labels: Dictionary = CrewMember.config().get("labels", {})
	if m.is_down():
		return str(labels.get("drone_broken", "broken"))
	return "" if Power.drone_fed(ship.power_state, m.name) else str(labels.get("drone_off", "no power"))


## A manual order (middle click): walk to `anchor` and leave the job board alone for a while.
## False when there is no way there.
static func order_move(ship, m, anchor: Vector2i, door_passable: Callable = Callable()) -> bool:
	if m.is_drone() or not m.go_to(ship.grid, anchor, door_passable):  # (a drone takes no orders)
		return false
	m.job = {}
	m.hold = float(jcfg().get("order_hold", 8.0))
	return true


static func _person(p_name: String, p_look: Dictionary, p_pos: Vector2, p_species := "human"):
	var m = CrewMember.new(p_name, p_pos, p_species)
	m.look = p_look.duplicate()
	return m


static func _find(ship, test: Callable):
	for m in ship.crew:
		if test.call(m):
			return m
	return null


## The first of `names` no crew member of `ship` has.
static func _next_name(ship, names: Array) -> String:
	for n in names:
		if _find(ship, func(m): return m.name == n) == null:
			return str(n)
	return "Crew %d" % (ship.crew.size() + 1)


## The first cell of every bed, by uid.
static func _beds(ship) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		if _family(ship, uid) == "bed":
			out.append(ship.components.instances[uid]["cells"][0])
	return out


static func _anchors(ship) -> Array:
	return ship.crew.map(func(m): return m.anchor())


## The body anchor nearest to `near` (cell units, a body centre) that fits and does not overlap a
## body on any of `taken`. NO_CELL when there is none.
static func _free_spot(grid, near: Vector2, taken: Array) -> Vector2i:
	var best := Pathfinder.NO_CELL
	var best_d := INF
	for c: Vector2i in grid.tiles:
		var d := (Pathfinder.centre_of(c) - near).length_squared()
		if d > best_d or (d == best_d and (c.y > best.y or (c.y == best.y and c.x > best.x))):
			continue
		if not _clashes(c, taken) and Pathfinder.body_ok(grid, c):
			best = c
			best_d = d
	return best
