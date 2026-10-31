extends RefCounted
## What the crew do on their own (docs/PLAN.md pillar 4). One Jobs object per ship (ShipSim keeps
## them); tick() runs every frame. Utility style, no randomness, so the same ship plays out the same.
##
## The job board is rebuilt from the ship's state every `period` seconds (and at once after a job
## is finished): `extinguish` a burning cell (100), `revive` a downed crew member (95),
## `repair_breach` a shot-open wall (90), `repair_component` a malfunctioning or disabled part (80,
## +10 for a weapon, engine or shield in a fight; also a hull mount whose outside half is damaged and
## whose link is intact, from its inside half), `repair_crew` a hurt `mechanical` crew member (75,
## done by any other crew member: beds do not heal them), `man_station` (50, out of a fight 45 but the helm: the helm, and weapons,
## shields and engines flagged manned), `clear_wreck` (30: the debris of a part that was shot to pieces,
## which gives back half its recipe). A job has `slots` places (two crew stack on a fire) and a place to
## stand next to it. Numbers are in data/crew.json.
## Each hand-out, an idle crew member takes the highest-priority job with a free place, preferring
## jobs nobody works on, then the nearest by walking distance (only the nearest few get a path
## search, see `search` in the data). A crew member keeps their job until it is done or a job at
## least `switch_margin` priority points higher shows up. The player's soldier is never given a
## job; the player works a job by standing next to it and holding E (hand_work). Hurt crew with
## nothing to do rest on a bed (5 hp/s) or in a powered medbay (15 hp/s).
## What the crew's traits change (traits.gd, the library in data/traits.json) is asked there: work speed
## (work_rate: repair, extinguish, breach, revive, swarm and aura bonuses), air and fire damage, room heat
## (dries_out, heat_speed), healing (heal_mult, auras), ion hits (ion_hit: damage and stun), vacuum_walk (no suffocation),
## no_tools (no repair or extinguish jobs) and hull_mend (idle crew mend the walls and breaches next to them).
## Repairs take `seconds` x the repair multiplier of the part's line (of the wall's line for a
## breach). A crew member at a station marks it in `ship.manned` (uid -> name): a manned helm adds
## evasion in a fight and a manned weapon cools down faster (see evasion_bonus, cooldown_mult).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Heat = preload("res://scripts/sim/heat.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const QUALIFIED_BONUS := 15  ## a station whose abilities need traits: crew who have them prefer it by this much
const UNQUALIFIED_PENALTY := 20  ## ...and crew who lack them look elsewhere first
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const FAULTY: Array[String] = ["malfunction", "disabled"]  ## part statuses a crew member can repair
const NO_FIRE := Vector2i(-1, -1)  ## "no burning cell"
const HAND_SHOWN := 0.6  ## seconds the HUD still says what the player was doing by hand
## The TraitSet work_mult a job type is done at.
## The jobs that need tools: a crew member with the trait no_tools takes none of them.
const TOOL_JOBS: Array[String] = ["extinguish", "repair_breach", "repair_component", "repair_crew"]
const WORK_KIND := {"extinguish": "extinguish", "repair_breach": "breach", "repair_component": "repair", "repair_crew": "repair", "revive": "heal_others"}

var board := {}  ## job key -> job: {key, type, priority, cells, slots, work, label, ...}
var progress := {}  ## job key -> seconds of work done so far (kept while the job stays on the board)
var orders := {}  ## job key -> job: repairs the player ordered (F), kept until done
var combat := false  ## a fight is on: weapons, engines and shields get repaired first
var paths_used := 0  ## path searches the last hand-out made
var _since := 1.0e9  ## seconds since the board was rebuilt (huge: build it on the first tick)


# --- the frame ----------------------------------------------------------------------------------

## Advance the crew of `ship` by `dt` seconds: rebuild the board and hand out jobs when it is time,
## walk and work, then hurt and heal. `in_combat`: a fight is on.
func tick(ship, dt: float, in_combat := false) -> void:
	combat = in_combat
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
	for key in by_priority(board.values()).map(func(j): return j["key"]):
		var job: Dictionary = board[key]
		if job["type"] != "man_station" and in_reach(m, job) and not _is_own(job, m) and (tools or not job["type"] in TOOL_JOBS):
			work(ship, m, job, dt)
			m.job = {"key": key, "type": job["type"], "label": job["label"], "hand": true, "t": ship.clock}
			return key
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
					board.erase("fire:%d,%d" % [foot.x, foot.y])
				return
			if ship.fires.has(c):
				ship.fires[c] = float(ship.fires[c]) - rate
			if not ship.fires.has(c) or ship.fires[c] <= 0.0:
				Fire.extinguish(ship, c)
				board.erase(job["key"])  # done: everyone on it moves on at the next hand-out
				_since = 1.0e9
		"man_station":
			ship.manned[job["uid"]] = m.name
		"repair_breach", "repair_component", "revive", "clear_wreck":
			var key: String = job["key"]
			progress[key] = float(progress.get(key, 0.0)) + dt * _work_rate(ship, m, job["type"])
			if progress[key] >= float(job["work"]) - 1e-6:
				_finish(ship, job)
		"repair_crew":  # mends the hurt crewmate (hp a second) until they are whole
			var who = _find(ship, func(x): return x.name == job["who"])
			if who != null and not who.is_down() and who.hp < who.max_hp:
				who.heal(float(jcfg()["repair_crew"]["rate"]) * _work_rate(ship, m, "repair_crew") * dt)
			if who == null or who.is_down() or who.hp >= who.max_hp:
				board.erase(job["key"])
				_since = 1.0e9


## How fast `m` does a job of `type`, 1.0 being normal: the work_mult of their traits for it (fast_repair
## works a repair or a breach 1 / 0.6 times as fast, a Basalt revives at half speed), with the swarm and
## aura bonuses of the crew in their room (TraitSet.work_rate), times what the parts in their room do to the work
## (Abilities.work_mult: room_work_mult, wet).
static func _work_rate(ship, m, type: String) -> float:
	return TraitSet.work_rate(ship, m, WORK_KIND.get(type, "repair")) * Abilities.work_mult(ship, m)


## Is `job` the mending of `m` themselves? Nobody mends their own body.
static func _is_own(job: Dictionary, m) -> bool:
	return job["type"] == "repair_crew" and job["who"] == m.name


# --- the board ----------------------------------------------------------------------------------

## Rebuild the board from the state of `ship`.
func build_board(ship) -> void:
	var b := {}
	var j := jcfg()
	var grid = ship.grid
	for c in Fire.sorted_cells(ship.fires.keys()):
		_add(b, _job("extinguish", "fire:%d,%d" % [c.x, c.y], [c], {"cell": c}))
	for m in ship.crew:
		if m.is_down():
			_add(b, _job("revive", "revive:" + m.name, m.body_cells(), {"who": m.name}))
		elif m.hp < m.max_hp and TraitSet.of(m)["mechanical"]:
			_add(b, _job("repair_crew", "mend:" + m.name, m.body_cells(), {"who": m.name}))
	for c in Fire.sorted_cells(grid.breached.keys()):
		var tile: Dictionary = grid.defs.get_def(grid.breached[c]) if grid.defs != null else {}
		var mult := float(ship.lines.get(str(tile.get("line", "standard")), {}).get("repair", 1.0))
		_add(b, _job("repair_breach", "breach:%d,%d" % [c.x, c.y], [c], {"cell": c, "work": float(j["repair_breach"]["seconds"]) * mult}))
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		var family := str(def.get("family", ""))
		if inst["status"] in FAULTY or ship.outside_hurt(uid):
			_add(b, _fix_job(ship, uid))
		if family == "helm" or (bool(def.get("manned", false)) and family in j["man_station"]["families"]):
			var post := _job("man_station", "post:%d" % uid, inst["cells"], {"uid": uid, "name": def.get("name", inst["id"]), "family": family, "needs": _needs_of(def)})
			if family != "helm" and not combat:
				post["priority"] -= int(j["man_station"].get("idle_penalty", 0))  # nothing to shoot at: the helm first, the autopilot needs it
			_add(b, post)
	for w in ship.components.wrecks:
		_add(b, _job("clear_wreck", "wreck:%d,%d" % [w["cells"][0].x, w["cells"][0].y], w["cells"], {"id": w["id"], "name": ship.components.def(w["id"]).get("name", w["id"])}))
	for key in orders.keys():
		var uid := int(orders[key]["uid"])
		if not ship.components.instances.has(uid) or _fine(ship, uid):
			orders.erase(key)
		else:
			_add(b, orders[key])
	board = b
	for key in progress.keys():
		if not board.has(key):
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
		if m.is_player or m.is_down() or TraitSet.of(m)["no_tools"]:
			continue
		var d := absi(m.anchor().x - inst["anchor"].x) + absi(m.anchor().y - inst["anchor"].y)
		if d < best_d:
			best = m
			best_d = d
	if best == null:
		return "no crew to send"
	orders[job["key"]] = job
	build_board(ship)
	paths_used = 0
	var route := _route(ship, best, job, _taken(ship, best))
	if route.is_empty():
		orders.erase(job["key"])
		build_board(ship)
		return "%s cannot reach %s" % [best.name, name]
	best.hold = 0.0
	_take(ship, best, board[job["key"]], route["spot"], {})
	return "%s will repair %s" % [best.name, name]


## Hand out the jobs on the board to the crew who are free (or ready to switch).
func assign(ship) -> void:
	paths_used = 0
	var claims := {}  # job key -> crew working it
	var free: Array = []
	for m in ship.crew:
		if m.is_player:
			continue
		if m.is_down():
			m.job = {}
			m.path.clear()
			continue
		if m.hold > 0.0:
			continue  # on a manual order
		free.append(m)
		if m.job.is_empty():
			continue
		if _still_valid(ship, m):
			if m.job["type"] != "rest":
				claims[m.job["key"]] = int(claims.get(m.job["key"], 0)) + 1
		else:
			m.job = {}
			m.path.clear()
	var margin := int(jcfg().get("switch_margin", 30))
	for m in free:
		var floor_p := 0 if m.job.is_empty() else int(m.job["priority"]) + margin
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
		return m.hp < m.max_hp and _rest_ok(ship, int(job["uid"]))
	if not board.has(job["key"]):
		return false
	var spot = job.get("spot")
	m.job = board[job["key"]].duplicate()
	m.job["spot"] = spot
	return true


## The best job for `m` with a priority of at least `floor_p`: {job, spot}, or {} when none.
func _pick(ship, m, claims: Dictionary, floor_p: int) -> Dictionary:
	var open: Array = []
	var tools: bool = not TraitSet.of(m)["no_tools"]
	for key in board:
		var job: Dictionary = board[key]
		if job["priority"] < floor_p or (not m.job.is_empty() and m.job["key"] == key) or _is_own(job, m) or (not tools and job["type"] in TOOL_JOBS):
			continue
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
func _route(ship, m, job: Dictionary, taken: Array) -> Dictionary:
	if in_reach(m, job):
		return {"cost": 0, "spot": m.anchor()}
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
		if not path.is_empty() and (best.is_empty() or path.size() - 1 < best["cost"]):
			best = {"cost": path.size() - 1, "spot": spot}
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


## A hurt crew member with nothing to do goes to a powered medbay, else a bed (not where heal_mult is 0).
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
			if ship.components.def(inst["id"]).get("family", "") == family and _rest_ok(ship, uid):
				cands.append(_job("rest", "rest:%d" % uid, inst["cells"], {"uid": uid}))
		var got := _nearest(ship, m, cands, taken)
		if not got.is_empty():
			_take(ship, m, got["job"], got["spot"], {})
			return


func _rest_ok(ship, uid: int) -> bool:
	if not ship.components.instances.has(uid):
		return false
	var inst: Dictionary = ship.components.instances[uid]
	if ship.components.def(inst["id"]).get("family", "") == "medbay":
		return inst["status"] == "ok" and bool(ship.power_state.get("powered", {}).get(uid, false))
	return true


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
	board.erase(key)
	_since = 1.0e9
	match job["type"]:
		"clear_wreck":
			var w: Dictionary = ship.components.clear_wreck(ship.components.wreck_at(job["cells"][0]))
			if not w.is_empty():
				var refund: Dictionary = ship.wreck_refund(w["id"])
				for m in refund:
					ship.inventory.add(m, refund[m])
				ship.log_event("Cleared the wreck of %s%s" % [job["name"], " (+%s)" % ", ".join(refund.keys().map(func(m): return "%d %s" % [refund[m], m])) if not refund.is_empty() else ""])
		"repair_breach":
			if ship.grid.repair(job["cell"]):
				ship.mark_dirty()
				ship.log_event("Breach sealed")
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
		m.speed_mod = TraitSet.heat_factor(t, heat) if room >= 0 and by_heat else 1.0
		if dmg > 0.0:
			m.hurt(dmg * dt)
		var heal := _heal_rate(ship, m) + float(auras.get(room, {}).get("heal_per_s", 0.0))
		if heal > 0.0:
			m.heal(heal * dt)
		if m.is_down() and not was_down:
			m.job = {}
			m.path.clear()
			ship.log_event("%s is down" % m.name)
		elif was_down and not m.is_down():
			ship.log_event("%s is back on their feet" % m.name)


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


## hp per second where `m` lies: a bed, or a medbay that is on (its stats.heal scales the rate), times
## their heal_mult for it.
func _heal_rate(ship, m) -> float:
	var uid: int = ship.components.at(m.cell())
	if uid < 0:
		return 0.0
	var inst: Dictionary = ship.components.instances[uid]
	var def: Dictionary = ship.components.def(inst["id"])
	var rates: Dictionary = CrewMember.config()["heal_per_s"]
	var heal: Dictionary = TraitSet.of(m)["heal_mult"]
	match str(def.get("family", "")):
		"bed":
			return float(rates["bed"]) * float(heal["bed"])
		"medbay":
			if _rest_ok(ship, uid):
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
	for c in job["cells"]:
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


## repair_component for part `uid`: 5 s x the line's repair multiplier; weapons, engines and shields
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
## names and species), else the player's soldier, Ada, and `extra_crew` more NPCs at the beds
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
		var is_player: bool = who == cfg["player"]["name"]
		var is_ada: bool = who == cfg["ada"]["name"]
		var nth := npc
		if not is_player and not is_ada:
			npc += 1
		if _find(ship, func(m): return m.name == who) != null or ship.dead_crew.has(who):
			continue
		var near := mid
		var look: Dictionary = cfg["player"]["look"] if is_player else cfg["ada"]["look"]
		if not is_player and not is_ada:
			look = cfg["looks"][nth % cfg["looks"].size()]
			if not beds.is_empty():
				near = Pathfinder.centre_of(beds[nth % beds.size()])
		var spot := _free_spot(grid, near, _anchors(ship))
		if spot == Pathfinder.NO_CELL:
			break
		var m = _person(who, look, Pathfinder.centre_of(spot), str(e["species"]))
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
		ship.crew.append(m)
		out.append(m)
	return out


## A manual order (middle click): walk to `anchor` and leave the job board alone for a while.
## False when there is no way there.
static func order_move(ship, m, anchor: Vector2i, door_passable: Callable = Callable()) -> bool:
	if not m.go_to(ship.grid, anchor, door_passable):
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
