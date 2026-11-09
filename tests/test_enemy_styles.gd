extends "res://tests/base_test.gd"
## The fighting roles (data/enemy_tables.json roles: skirmisher, carrier, boarder, flanker, siege, bulwark): who flies which, what each
## carries (Shipgen) and how each flies (the styles of scripts/combat/pilot_ai.gd), each in a scripted arena against a foe that sits or dashes.

const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Threat = preload("res://scripts/space/threat.gd")

const PIRATE := "res://data/ships/pirate_raider.json"
const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const COURIER := "res://data/ships/starter_courier.json"
const NEW_ROLES: Array[String] = ["skirmisher", "carrier", "boarder", "flanker", "siege", "bulwark"]
const DT := 1.0 / 60.0


## The first ship of `role` (seeds from `seed_value` on, the ones that fell back to a gunboat skipped) that `ok` accepts, built for a fight at
## `stage`; null when none of 30 is.
func _roled(faction: String, size: String, role: String, seed_value: int, budget: float, ok := Callable(), stage := 3):
	for k in 30:
		var ship = Shipgen.build(faction, size, seed_value + k, budget, {"role": role, "stage": stage})
		if ship != null and ship.get_meta("shipgen")["role"] == role and (not ok.is_valid() or ok.call(ship)):
			return ship
	return null


## An arena with `ship` (index 0, at the origin, nose up) against the pirate raider (or the design `foe_path`; index 1) sitting `dist` px
## ahead, nose toward it. The foe holds fire. Returns [arena, the pilot of ship 0].
func _arena(ship, dist: float, seed_value := 11, foe_path := PIRATE) -> Array:
	var a := Arena.new(seed_value)
	a.add_ship(ship, Vector2.ZERO, 0.0)
	a.add_ship(Session.load_ship(foe_path), Vector2(0.0, -dist), PI)
	a.autofire[1] = false
	return [a, PilotAI.new(a, 0, 1, ship.get_meta("ai", {}))]


func _step(a: Arena, ai: PilotAI, seconds: float, each := Callable()) -> void:
	for k in int(seconds / DT):
		ai.think(DT)
		a.step(DT)
		if each.is_valid():
			each.call()


func _events(a: Arena, type: String, ship := -1) -> int:
	var n := 0
	for e in a.events:
		n += int(e["type"] == type and (ship < 0 or int(e.get("ship", -1)) == ship))
	return n


# --- who flies what ------------------------------------------------------------------------------------

func test_every_faction_flies_its_listed_roles() -> void:
	var listed: Dictionary = Shipgen.tables()["roles"]["flies"]
	for faction in ["rustfangs", "concord", "lumen", "wardens", "clans", "hollow"]:
		check(listed.has(faction), faction + " has a list")
		eq(Shipgen.roles_of(faction), listed[faction].keys(), faction + ": roles_of reads its list")
		var news: Array = listed[faction].keys().filter(func(r): return NEW_ROLES.has(r))
		eq(news.size(), 2, faction + " flies two of the new roles")
		var seen := {}
		for sd in 80:
			var role := Shipgen.pick_role(faction, "large", sd)
			check(listed[faction].has(role), "%s: %s is on its list" % [faction, role])
			seen[role] = true
		eq(seen.size(), listed[faction].size(), "%s: every listed role turns up in 80 large ships (%s)" % [faction, str(seen.keys())])
	eq(Shipgen.roles_of("kett"), Shipgen.roles_of("clans"), "a race flies its base faction's roles")
	eq(Shipgen.roles_of("revenant"), Shipgen.roles_of("hollow"), "(the Hollow's race too)")


func test_a_faction_with_no_list_keeps_the_old_ranking() -> void:
	var cfg: Dictionary = Shipgen.tables()["roles"]
	var kept: Dictionary = cfg["flies"]["concord"]
	cfg["flies"].erase("concord")
	var roles: Array = Shipgen.roles_of("concord")
	cfg["flies"]["concord"] = kept
	eq(roles, ["escort", "bulwark", "gunboat", "sniper"], "the favoured categories rank the roles, the table's order breaking ties (shield 4: escort, bulwark; weapons 3, skill 3)")


func test_the_bulwark_first_flies_at_stage_2() -> void:
	var seen := {1: 0, 2: 0}
	for faction in ["concord", "wardens"]:
		for sd in 60:
			for stage in [1, 2]:
				seen[stage] += int(Shipgen.pick_role(faction, "medium", sd, stage == 1, stage) == "bulwark")
	eq(seen[1], 0, "stage 1 pirates field no fortress")
	check(seen[2] > 10, "from stage 2 the Concord and the Wardens fly it (%d of 120)" % seen[2])
	var ship = Shipgen.from_spec(Shipgen.spec("concord", "medium", 5, 120.0, false, 1))
	check(ship != null and ship.get_meta("shipgen")["role"] != "bulwark", "a stage 1 spec rolls another role")


func test_a_stage_with_no_bays_never_rolls_a_carrier_or_a_boarder() -> void:
	for faction in ["lumen", "wardens", "clans", "rustfangs"]:
		for sd in 40:
			check(not Shipgen.pick_role(faction, "large", sd, true) in ["carrier", "boarder"], "%s seed %d: no bay role at stage 1" % [faction, sd])
	var ship = _roled("lumen", "large", "carrier", 3, 300.0, Callable(), 1)
	check(ship != null and not Drones.bays_of(ship).is_empty(), "a pinned carrier still flies its bay (the tools measure it)")


## Every faction builds each of the new roles it flies at every size, at 20 seeds (build() validates every ship it returns; the old
## roles are built by tests/test_enemy_identity.gd and the fights' own tests).
func test_every_faction_size_and_role_builds() -> void:
	var listed: Dictionary = Shipgen.tables()["roles"]["flies"]
	var budget := {"small": 40.0, "medium": 110.0, "large": 260.0}
	for faction in listed:
		for role in Shipgen.roles_of(faction).filter(func(r): return NEW_ROLES.has(r)):
			for size in ["small", "medium", "large"]:
				var bad := 0
				for sd in 20:
					var ship = Shipgen.build(faction, size, 900 + sd * 7, budget[size], {"role": role, "stage": 3})
					if ship == null:
						bad += 1
						continue
					var got := str(ship.get_meta("shipgen")["role"])
					check(got == role or (got == "gunboat" and Shipgen.tables()["roles"]["list"][role].has("bay")), "%s %s %s: built as %s" % [faction, size, role, got])
				eq(bad, 0, "%s %s %s: every seed builds a valid ship" % [faction, size, role])


# --- what each carries -------------------------------------------------------------------------------------

func _bays(ship) -> Array:
	var out: Array = []
	for uid in Drones.bays_of(ship):
		out.append(str(Drones.kit(str(ship.components.instances[uid]["kit"]))["drone"]["role"]))
	return out


func test_each_role_carries_its_kit() -> void:
	var n := 12
	var fell := 0
	var sum := {}
	for role in ["gunboat"] + NEW_ROLES:
		sum[role] = {"accel": 0.0, "crew": 0.0, "missiles": 0, "shields": 0.0, "engines": 0.0}
		for sd in n:
			var ship = Shipgen.build("concord", "large", 40 + sd, 260.0, {"role": role, "stage": 3})
			var m: Dictionary = ship.get_meta("shipgen")
			var p: Dictionary = Threat.power(ship, 0.6)
			sum[role]["accel"] += float(p["accel"]) / n
			sum[role]["crew"] += float(ship.crew_plan.size()) / n
			sum[role]["shields"] += float(m["shields"].size()) / n
			sum[role]["engines"] += float(m["engines"].size()) / n
			sum[role]["missiles"] += int(m["weapons"].any(func(id): return Shipgen._is_missile(str(id))))
			var got := str(m["role"])
			if got != role:
				check(got == "gunboat" and role in ["carrier", "boarder"], "%s seed %d: built as %s (a hull that takes no bay makes a gunboat)" % [role, 40 + sd, got])
				fell += 1
				continue
			eq(ship.get_meta("ai").get("style", ""), "" if role == "gunboat" else role, "%s: its pilot flies its style" % role)
			if role == "carrier":
				check(not _bays(ship).is_empty() and _bays(ship).all(func(r): return r == "combat"), "a carrier flies drone bays with a combat kit: %s" % str(_bays(ship)))
				check(ship.inventory.count(Drones.PART) >= 4, "and the parts to launch them")
			elif role == "boarder":
				check(_bays(ship) == ["boarder"], "a boarder throws boarder pods: %s" % str(_bays(ship)))
			else:
				check(_bays(ship).is_empty(), "%s: no drone bay of its role (a spec's rolled bay is not built here)" % role)
	check(sum["skirmisher"]["accel"] > sum["gunboat"]["accel"] * 1.15, "a skirmisher is quicker than a gunboat (%.1f vs %.1f)" % [sum["skirmisher"]["accel"], sum["gunboat"]["accel"]])
	check(sum["bulwark"]["accel"] < sum["gunboat"]["accel"], "a bulwark is slower (%.1f vs %.1f)" % [sum["bulwark"]["accel"], sum["gunboat"]["accel"]])
	check(sum["bulwark"]["shields"] >= sum["gunboat"]["shields"], "with no less shield (%.2f vs %.2f)" % [sum["bulwark"]["shields"], sum["gunboat"]["shields"]])
	check(sum["boarder"]["crew"] > sum["gunboat"]["crew"], "a boarder carries more crew (%.1f vs %.1f)" % [sum["boarder"]["crew"], sum["gunboat"]["crew"]])
	eq(sum["siege"]["missiles"], n, "every siege boat carries a missile launcher when one is for sale")
	check(fell <= 6, "most carriers and boarders find a wall for their bay (%d of %d fell back to a gunboat)" % [fell, 2 * n])


func test_a_bulwark_breaks_late_and_a_fighting_role_never_rams() -> void:
	var b = Shipgen.build("concord", "medium", 5, 120.0, {"role": "bulwark", "stage": 3})
	check(float(b.get_meta("ai")["break_structure"]) < 0.95, "a bulwark breaks at a lower structure than the 0.95 of the others")
	for sd in 20:
		var s = Shipgen.build("rustfangs", "large", 60 + sd, 260.0, {"role": "skirmisher", "stage": 3})
		check(not bool(s.get_meta("shipgen")["ram"]) and s.get_meta("ai")["style"] == "skirmisher", "a Rustfang skirmisher never rams (seed %d)" % (60 + sd))


func test_the_same_seed_gives_the_same_roled_ship() -> void:
	for role in NEW_ROLES:
		var a = Shipgen.from_spec(Shipgen.spec("lumen", "large", 77, 260.0, false, 3) + ":role:" + role)
		var b = Shipgen.from_spec(Shipgen.spec("lumen", "large", 77, 260.0, false, 3) + ":role:" + role)
		eq(a.grid.tiles, b.grid.tiles, role + ": the same tiles")
		eq(a.get_meta("shipgen")["weapons"], b.get_meta("shipgen")["weapons"], role + ": the same guns")
		eq(Drones.bays_of(a).size(), Drones.bays_of(b).size(), role + ": the same bays")


# --- how each flies ------------------------------------------------------------------------------------

func test_the_skirmisher_runs_when_the_foe_closes_and_opens_the_range_again() -> void:
	var ship = _roled("concord", "medium", "skirmisher", 21, 120.0)
	var d := _arena(ship, 2800.0, 11, "gen:concord:large:7:30000")  # (a foe of many guns, some of which last: with its guns out a skirmisher has nothing to run from)
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	var r := ai.reach()
	_step(a, ai, 12.0)
	check(ai.gap_now() > PilotAI.SKIRMISH_RUN * r, "it holds out at its reach (gap %d, reach %d)" % [ai.gap_now(), r])
	# The foe dashes in at 330 px/s for 4 s, then sits.
	var foe = a.ships[1]
	foe.flight.linear_damping = 0.0
	var least := [INF]
	var ran := [false]
	var away := [false]
	_step(a, ai, 4.0, func():
		foe.flight.vel = (a.ships[0].flight.pos - foe.flight.pos).normalized() * 330.0
		least[0] = minf(least[0], ai.gap_now())
		if ai._running >= 0.0:
			ran[0] = true
			away[0] = away[0] or Vector2.UP.rotated(a.ships[0].flight.angle).dot(a.ships[0].flight.pos - foe.flight.pos) > 0.7)
	foe.flight.vel = Vector2.ZERO
	foe.flight.linear_damping = 1.0
	_step(a, ai, 14.0, func(): away[0] = away[0] or (ai._running >= 0.0 and Vector2.UP.rotated(a.ships[0].flight.angle).dot(a.ships[0].flight.pos - foe.flight.pos) > 0.7))
	check(ran[0], "the foe came inside %.1f of its reach (least gap %d) and it ran" % [PilotAI.SKIRMISH_RUN, least[0]])
	check(away[0], "it turned its nose away and burned")
	check(ai.gap_now() > 0.75 * r, "the range opened again (gap %d, reach %d)" % [ai.gap_now(), r])
	eq(ai._running, -1.0, "and it came back round to fight")
	check(Vector2.UP.rotated(a.ships[0].flight.angle).dot((foe.flight.pos - a.ships[0].flight.pos).normalized()) > 0.0, "nose toward the foe again")


func test_the_carrier_launches_and_keeps_beyond_the_foes_reach() -> void:
	var ship = _roled("lumen", "large", "carrier", 31, 260.0)
	check(ship != null and not Drones.bays_of(ship).is_empty(), "a carrier with its bay")
	var d := _arena(ship, 1500.0)
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	_step(a, ai, 30.0)
	check(_events(a, "drone_launch") >= 1 or not Drones.of_ship(a, 0).is_empty(), "it launched")
	check(ai.gap_now() > ai.foe_reach(), "it keeps beyond the foe's longest gun (gap %d, the foe's reach %d)" % [ai.gap_now(), ai.foe_reach()])
	check(a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos) < Drones.DRONE_REACH, "and within its drones' reach")
	var launched := _events(a, "drone_launch")
	for dr in Drones.of_ship(a, 0):
		Drones.damage(a, dr, 1000.0, 1)  # the foe's guns knock the drones down
	_step(a, ai, 16.0)
	check(_events(a, "drone_launch") > launched, "and it relaunches once a bay has re-armed (%d launches, then %d)" % [launched, _events(a, "drone_launch")])
	ship = _roled("lumen", "large", "carrier", 31, 260.0)
	ship.inventory.add(Drones.PART, -ship.inventory.count(Drones.PART))
	d = _arena(ship, 2400.0)
	var gap0: float = d[1].gap_now()
	_step(d[0], d[1], 12.0)
	check(not d[1].has_drones(), "with no parts it has no drone to fly")
	check(d[1].gap_now() < 0.7 * gap0, "and closes to fight with its guns (gap %d from %d)" % [d[1].gap_now(), gap0])


func test_the_boarder_throws_its_boarders_and_holds_close() -> void:
	var ship = _roled("rustfangs", "medium", "boarder", 41, 120.0)
	check(ship != null and _bays(ship) == ["boarder"], "a boarder with its pods")
	var a := Arena.new(11)
	a.add_ship(ship, Vector2.ZERO, 0.0)
	a.add_ship(Session.load_ship(RUSTBUCKET), Vector2(0.0, -3200.0), PI)
	a.autofire[1] = false
	var ai := PilotAI.new(a, 0, 1, ship.get_meta("ai", {}))
	var thrown := [-1.0]
	var gaps := [0.0, 0]  # the gap summed while its robots are aboard, and the substeps
	_step(a, ai, 30.0, func():
		if thrown[0] < 0.0 and _events(a, "drone_launch") > 0:
			thrown[0] = a.time()
			check(a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos) <= PilotAI.BOARD_THROW, "it throws from its throwing range")
		if not a.ships[1].ship.intruders.is_empty():
			gaps[0] += ai.gap_now()
			gaps[1] += 1)
	check(thrown[0] >= 0.0 and thrown[0] < 12.0, "it closes and throws a pod within 12 s (at %.1f s)" % thrown[0])
	check(_events(a, "pod_breach") >= 1, "a pod cut in")
	check(not a.ships[1].ship.intruders.is_empty(), "and its robots are aboard")
	check(gaps[1] > 0 and gaps[0] / gaps[1] < 2.0 * PilotAI.BOARD_GAP, "while they are aboard it holds close (a gap of %d px on average)" % (gaps[0] / maxf(gaps[1], 1)))


func test_the_flanker_gets_behind_the_foes_beam() -> void:
	var ship = _roled("lumen", "medium", "flanker", 51, 120.0)
	var d := _arena(ship, 1300.0)
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	eq(ai.priority(), ["engine", "weapon"] as Array[String], "it aims at engines and guns first")
	var foe = a.ships[1]
	var behind := [-1.0]
	_step(a, ai, 20.0, func():
		var bow: Vector2 = Vector2.UP.rotated(foe.flight.angle)
		if behind[0] < 0.0 and (a.ships[0].flight.pos - foe.flight.pos).normalized().dot(bow) < -0.2:
			behind[0] = a.time())
	check(behind[0] >= 0.0 and behind[0] <= 15.0, "behind the foe's beam within 15 s (at %.1f s)" % behind[0])
	check(_events(a, "hit", 1) + _events(a, "shield", 1) > 0, "and it hits the foe")
	var swept := [0.0, (a.ships[0].flight.pos - foe.flight.pos).normalized()]  # the bearing swept, the last bearing
	foe.flight.ang_vel = 0.6  # the foe turns: the goal moves, and it goes on round
	_step(a, ai, 10.0, func():
		var now: Vector2 = (a.ships[0].flight.pos - foe.flight.pos).normalized()
		swept[0] += absf(Vector2(swept[1]).angle_to(now))
		swept[1] = now)
	check(swept[0] > 0.5, "it keeps moving across (%.2f rad of bearing in 10 s)" % swept[0])


func test_the_siege_boat_fires_its_volley_then_backs_off() -> void:
	var d := []
	for k in 12:  # a siege boat whose presented side has two volley guns or more (one gun is no volley: it holds and fires)
		d = _arena(_roled("concord", "large", "siege", 61 + k, 260.0), 3600.0, 11, "gen:concord:large:7:30000")  # (a foe of many guns: a siege boat closes on one whose guns are all out)
		_step(d[0], d[1], 1.0)
		if d[1].volley_size() >= 2:
			break
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	check(ai.volley_size() >= 2, "a siege boat with a volley of %d guns" % ai.volley_size())
	a.ships[0].ai_volley = true  # (the session sets it for every enemy)
	var at_volley := [-1.0, 0.0]
	var least := [INF]  # the nearest it came after the volley (its way still carried it in), then the farthest it backed off to
	var most := [0.0]
	_step(a, ai, 40.0, func():
		var dist: float = a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos)
		if at_volley[0] < 0.0 and ai._reload >= 0.0:
			at_volley[0] = a.time()
			at_volley[1] = dist
		elif at_volley[0] >= 0.0 and a.time() < at_volley[0] + PilotAI.SIEGE_BACK_S + 12.0:  # (+5 s until fights-end C: with HOLD_MAX 0.5 its volleys come every 4 s or so, so it backs off over several reloads, not in one)
			least[0] = minf(least[0], dist)
			most[0] = maxf(most[0], dist) if dist > least[0] else most[0])
	check(at_volley[0] >= 0.0, "it fired a volley (%d shots)" % _events(a, "shot", 0))
	check(at_volley[1] > ai.centres_at(0.6 * ai.siege_reach()), "from far off (%d between the centres)" % at_volley[1])
	check(most[0] > least[0] + 60.0, "then the range grew (from %d at the volley it came in to %d and backed off to %d)" % [at_volley[1], least[0], most[0]])
	check(_events(a, "shot", 0) >= 6, "and it came back for more volleys (%d shots)" % _events(a, "shot", 0))


func test_the_bulwark_closes_slowly_and_faces_its_best_sector() -> void:
	var ship = _roled("concord", "medium", "bulwark", 71, 120.0, func(s): return not s.get_meta("shipgen")["shields"].is_empty())
	check(ship != null, "a bulwark with a shield")
	var sid := str(ship.get_meta("shipgen")["shields"][0])
	var stats: Dictionary = ship.components.by_id[sid]["stats"]
	var had = stats.get("sectors")
	stats["sectors"] = 4  # a test-only sectored shield (put back below)
	var d := _arena(ship, 3200.0)
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	var co = a.ships[0]
	eq(co.sectors, 4, "four sectors")
	var fastest := [0.0]
	_step(a, ai, PilotAI.BULWARK_CHASE_S - 0.5, func(): fastest[0] = maxf(fastest[0], co.flight.vel.dot((a.ships[1].flight.pos - co.flight.pos).normalized())))
	check(fastest[0] < PilotAI.BULWARK_CLOSE * 1.3, "it closes slowly (%d px/s at most)" % fastest[0])
	_step(a, ai, 0.5)
	eq(Shields.sector_of_world_dir(co, a.ships[1].flight.pos - co.flight.pos), 0, "with even sectors it shows the foe its bow")
	co.sector_layers[0] = 0.0  # the bow sector is knocked out
	co.sector_wait[0] = 30.0
	_step(a, ai, 6.0)
	var facing := Shields.sector_of_world_dir(co, a.ships[1].flight.pos - co.flight.pos)
	var best := 0
	for s in co.sectors:
		if Shields.hp_of(co, s) > Shields.hp_of(co, best):
			best = s
	check(facing != 0, "it turned the spent bow sector away (facing sector %d)" % facing)
	check(Shields.hp_of(co, facing) >= Shields.hp_of(co, best) - 1e-6, "and shows the foe its strongest one (sector %d: %.1f HP, the best %.1f)" % [facing, Shields.hp_of(co, facing), Shields.hp_of(co, best)])
	_step(a, ai, 10.0)
	check(co.weights.all(func(w): return float(w) <= PilotAI.BULWARK_MAX_W + 1e-6), "no sector holds more than %.1f of its shield (%s)" % [PilotAI.BULWARK_MAX_W, str(co.weights)])
	if had == null:
		stats.erase("sectors")
	else:
		stats["sectors"] = had


func test_the_same_seed_flies_the_same_fight_in_every_style() -> void:
	for role in NEW_ROLES:
		var runs: Array = []
		for k in 2:
			var ship = Shipgen.build("lumen", "medium", 81, 120.0, {"role": role, "stage": 3})
			var d := _arena(ship, 2000.0, 13)
			d[0].autofire[1] = true
			var foe := PilotAI.new(d[0], 1, 0)
			for i in int(6.0 / DT):
				d[1].think(DT)
				foe.think(DT)
				d[0].step(DT)
			runs.append([d[0].ships[0].flight.pos, d[0].ships[1].flight.pos, d[0].events.size()])
		eq(runs[0], runs[1], role + ": the same fight twice")


func test_the_styles_that_keep_away_close_in_once_the_foes_guns_are_out() -> void:
	for role in ["skirmisher", "carrier", "siege"]:
		var ship = _roled("lumen", "large", role, 91, 260.0)
		var d := _arena(ship, 2600.0)
		var a: Arena = d[0]
		var ai: PilotAI = d[1]
		_step(a, ai, 10.0)
		var kept := ai.gap_now()
		var foe = a.ships[1]
		for uid in foe.mounts:
			foe.ship.components.instances[uid]["status"] = "disabled"
		eq(ai.foe_reach(), 0.0, role + ": the foe has no gun left")
		_step(a, ai, 15.0)
		var u: Vector2 = (foe.flight.pos - a.ships[0].flight.pos).normalized()
		var plain := ai.hold_distance(u, ai._intact()) - ai.extent(0, u) - ai.extent(1, -u)
		check(ai.gap_now() < kept - 100.0 and ai.gap_now() < plain + 150.0, "%s: it closed from a gap of %d to %d (a plain pilot holds %d)" % [role, kept, ai.gap_now(), plain])


## A skirmisher never rams: against a foe that sits still it closes to its hold and never touches it.
func test_the_skirmisher_never_touches_a_still_foe() -> void:
	for spec in ["gen:rustfangs:medium:21:8000:s3:role:skirmisher", "gen:clans:medium:304:8000:s3:role:skirmisher", "gen:concord:large:305:20000:s3:role:skirmisher"]:
		var sess := Session.new()
		sess.start(Session.load_ship(RUSTBUCKET), Session.load_ship(spec), 7)
		for n in int(20.0 / DT):
			sess.input = {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}
			sess.tick(DT)
		eq(_events(sess.arena, "ram"), 0, spec + ": no contact in 20 s")
		check(sess.ai.gap_now() > PilotAI.HULL_MARGIN, "%s: a gap of %d px at the end" % [spec, sess.ai.gap_now()])


## A drone bay counts in the threat (Threat.bay_dps): a carrier reads at least the skulls of the same seed built as a gunboat (most seeds, and on the mean).
func test_a_carrier_reads_its_drones_in_the_threat() -> void:
	var courier := Session.load_ship(COURIER)
	var n := 0
	var below := 0
	var sums := [0, 0]
	for sd in 24:
		var faction: String = ["lumen", "wardens", "concord"][sd % 3]
		var size: String = ["medium", "large"][sd % 2]
		var budget: float = [120.0, 260.0][sd % 2]
		var c = Shipgen.build(faction, size, 700 + sd, budget, {"role": "carrier", "stage": 3})
		if c.get_meta("shipgen")["role"] != "carrier":
			continue
		var g = Shipgen.build(faction, size, 700 + sd, budget, {"role": "gunboat", "stage": 3})
		check(Threat.bay_dps(c, c.power_state.get("powered", {})) > 0.0, "seed %d: its bay adds to its damage" % (700 + sd))
		var a: int = Threat.rate(c, courier)["skulls"]
		var b: int = Threat.rate(g, courier)["skulls"]
		n += 1
		sums[0] += a
		sums[1] += b
		below += int(a < b)
	check(n >= 16, "most seeds build a carrier (%d of 24)" % n)
	check(sums[0] >= sums[1], "carriers read at least the skulls of the gunboats of their seeds (%d vs %d over %d)" % [sums[0], sums[1], n])
	check(below * 5 <= n, "and so does most of them one by one (%d of %d read fewer)" % [below, n])
	var plain = Shipgen.build("lumen", "medium", 3, 120.0, {"role": "escort", "stage": 3})
	eq(Threat.bay_dps(plain, plain.power_state.get("powered", {})), 0.0, "a ship with no bay adds nothing")


func test_a_siege_boat_of_one_volley_gun_holds_and_fires() -> void:
	var d := []
	for k in 20:
		d = _arena(_roled("rustfangs", "small", "siege", 40 + k, 50.0), 2600.0, 11, "gen:concord:large:7:30000")
		_step(d[0], d[1], 1.0)
		if d[1].volley_size() == 1:
			break
	eq(d[1].volley_size(), 1, "a siege boat with one volley gun")
	d[0].ships[0].ai_volley = true
	var backed := [false]
	_step(d[0], d[1], 30.0, func(): backed[0] = backed[0] or d[1]._reload >= 0.0)
	check(not backed[0], "it never backs off: one shot is no volley")
	check(_events(d[0], "shot", 0) >= 3, "and it keeps firing (%d shots)" % _events(d[0], "shot", 0))


## With no boarders out a boarder holds inside its throw range (held on the edge of it, it never threw).
func test_a_boarder_waits_inside_its_throw_range() -> void:
	var ship = _roled("rustfangs", "medium", "boarder", 41, 120.0)
	ship.inventory.add(Drones.PART, -ship.inventory.count(Drones.PART))  # nothing to throw: it only holds
	var a := Arena.new(11)
	a.add_ship(ship, Vector2.ZERO, 0.0)
	a.add_ship(Session.load_ship(RUSTBUCKET), Vector2(0.0, -3200.0), PI)
	a.autofire[1] = false
	var ai := PilotAI.new(a, 0, 1, ship.get_meta("ai", {}))
	_step(a, ai, 25.0)
	check(not ai.boarders_out(), "no boarders out")
	var d: float = a.ships[0].flight.pos.distance_to(a.ships[1].flight.pos)
	check(d < 0.95 * PilotAI.BOARD_THROW, "it waits inside its throw range (%d px between the centres, it throws from %d)" % [d, PilotAI.BOARD_THROW])


## A bulwark that a foe keeps out of its reach presses in: after BULWARK_CHASE_S with no gun in reach it closes to BULWARK_PRESS_GAP.
func test_a_kited_bulwark_presses_in() -> void:
	var ship = _roled("concord", "medium", "bulwark", 71, 120.0)
	var d := _arena(ship, 2600.0)
	var a: Arena = d[0]
	var ai: PilotAI = d[1]
	var foe = a.ships[1]
	foe.flight.linear_damping = 0.0
	_step(a, ai, 8.0, func():  # the foe backs off as fast as the bulwark closes: none of its guns reaches
		foe.flight.vel = (foe.flight.pos - a.ships[0].flight.pos).normalized() * maxf(0.0, a.ships[0].flight.vel.dot((foe.flight.pos - a.ships[0].flight.pos).normalized())))
	foe.flight.vel = Vector2.ZERO
	foe.flight.linear_damping = 1.0
	check(not ai.in_reach() and ai._out_of_reach > 5.0, "kept out of reach (%.1f s)" % ai._out_of_reach)
	_step(a, ai, 20.0)
	check(ai._out_of_reach >= PilotAI.BULWARK_CHASE_S, "it presses in")
	check(ai.gap_now() < PilotAI.BULWARK_PRESS_GAP + 150.0, "to a gap of %d px" % ai.gap_now())
	check(ai.in_reach(), "where its guns reach")
