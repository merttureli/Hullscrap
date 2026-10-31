extends "res://tests/base_test.gd"
## The soak test: a campaign played end to end without a screen, in sector space (docs/CONTENT.md section 11). For each
## starter ship and three seeds it makes 25 light-speed jumps along random lanes (the drive spools, then fires). In each
## sector the autopilot (helm.gd, at a time scale) flies the ship to the node's own POI and sometimes to one more, so
## their events run (random allowed choices), stations dock (fuel when low, a payment on the debt), passing ships come
## by, and fights happen in place through the real arena, the pilot AI flying the player's ship too; a win or a capture
## ends in the salvage pick (salvage.gd). A fight over FIGHT_CAP_S simulated seconds counts as a draw and the player
## retreats; one ends too when the enemy is out of range. After every step it checks the numbers (no negative fuel,
## credits or hull, no unknown id), that the autopilot gets where it was sent, and that no event is a dead end.
## Everything is seeded, so a failure replays.

const Arena = preload("res://scripts/combat/arena.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Events = preload("res://scripts/space/events.gd")
const Helm = preload("res://scripts/space/helm.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

const STARTERS: Array[String] = ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]
const SEEDS: Array[int] = [11, 22, 33]
const JUMPS := 25
const FIGHT_CAP_S := 120.0  ## a fight over this many simulated seconds is a draw and the player retreats
const SHORT_CAP_S := 30.0  ## the cap for the second and third seed, so the whole test stays under a minute (SOAK_FULL=1 uses FIGHT_CAP_S for all)
const SIM_STEP := 0.2  ## the ship sim (power, heat, fire, crew) runs this often during a fight (the game runs it each frame, at most 0.25 s)
const MAX_PAGES := 12  ## pages of one event chain before it counts as stuck
const REAL_FIGHTS_PER_RUN := 1  ## fights per run that go through the arena (the rest are stubbed, to keep the test fast); SOAK_FULL=1 in the environment runs them all
const PLAYER_PILOT_EVERY := 3  ## the player's pilot AI thinks every this many ticks (a human is slower than the enemy's 60 Hz)
const MAX_WAITS := 20  ## waits for a passing trader before a run with no fuel counts as stuck
const FLY_STEP := 0.25  ## seconds of one autopilot step: the time scale of the flights
const FLY_CAP_S := 240.0  ## simulated seconds the autopilot has to reach a POI before it counts as lost
const REPAIR_CAP_S := 120.0  ## seconds the crew get to make a ship that cannot fly fly again (the sim runs meanwhile)
const OTHER_POI := 0.5  ## the chance the ship also visits one other new POI of a sector
const WARDEN_TRIES := 8  ## times a run meets the exit warden (pay, pass, fight or turn back, at random) before it gives up on the lane

var _cap_s := FIGHT_CAP_S
var _real_left := 0  # fights of this run still to go through the arena
var _helm: Helm  # the ship's helm in the sector of the run now
var _goals: Array = []  # POI ids still to fly to in this sector
var stats := {"jumps": 0, "events": 0, "fights": 0, "won": 0, "lost": 0, "draw": 0, "docks": 0, "fight_ticks": 0, "waits": 0, "drifts": 0, "tows": 0, "runs": 0, "known": 0, "dead": 0,
	"pois": 0, "flown_s": 0, "salvage": 0, "contacts": 0, "grounded": 0, "wardens": 0, "cleared": 0}


func test_soak_every_starter_every_seed() -> void:
	var t0 := Time.get_ticks_msec()
	for design in STARTERS:
		for s in SEEDS:
			_soak(design, s)
	print("soak: %s in %d ms" % [str(stats), Time.get_ticks_msec() - t0])
	check(stats["jumps"] >= STARTERS.size() * SEEDS.size() * JUMPS, "every run made its jumps (%d)" % stats["jumps"])
	check(stats["fights"] > 0, "the soak met at least one fight")
	check(stats["pois"] + stats["grounded"] >= stats["jumps"], "a POI or more a sector, unless a fight left the ship unable to fly (%d POIs, %d grounded)" % [stats["pois"], stats["grounded"]])
	check(stats["salvage"] > 0, "a won fight led to the salvage of the enemy's parts")
	check(stats["wardens"] > 0 and stats["cleared"] > 0, "the exit warden was met and cleared (%d meetings, %d runs got through)" % [stats["wardens"], stats["cleared"]])


## Every event with choices has a way out that needs nothing: a choice with no requirement that can
## lack items, credits, a species, a trait or a part; or the panel adds Leave when none shows. An event
## whose choices can all be grey (or all hidden but greyed ones) would lock the event panel.
func test_no_event_is_a_dead_end() -> void:
	var ev = Events.shared()
	for id in ev.order:
		var e: Dictionary = ev.events[id]
		var choices = e.get("choices")
		if not (choices is Array) or choices.is_empty():
			continue
		var free := false
		for ch in choices:
			var req = ch.get("requires", {})
			if not (req is Dictionary) or not (req.has("items") or req.has("credits") or req.has("species") or req.has("trait") or req.has("component")):
				free = true
		check(free, "event '%s' has no choice that is always on offer" % id)


# --- one run -------------------------------------------------------------------------------------------

func _soak(design: String, seed_value: int) -> void:
	var tag := "%s/%d" % [design.get_file().get_basename(), seed_value]
	var sim := ShipSim.new()
	var pick := RandomNumberGenerator.new()  # the test's own choices, apart from the campaign's rng
	pick.seed = seed_value * 977 + 5
	var made := 0
	var guard := 0
	var starts := 0
	var c: Campaign = null
	var full := OS.get_environment("SOAK_FULL") != ""
	_real_left = 1000000 if full else REAL_FIGHTS_PER_RUN
	_cap_s = FIGHT_CAP_S if full or seed_value == SEEDS[0] else SHORT_CAP_S
	while made < JUMPS and guard < JUMPS * 6:
		if c == null:  # a new run: the first, or after the ship was wrecked
			starts += 1
			check(sim.choose_ship(design) == "", tag + ": the design loads")
			c = Campaign.new(seed_value + 1000 * (starts - 1))
			check(not c.instant_jump(), tag + ": the light-speed flow is on")
			stats["runs"] += 1
			_audit(tag + " start", c, sim.player_ship())
		guard += 1
		var ship = sim.player_ship()
		var where := "%s jump %d at %s (%s)" % [tag, made, c.current, c.node(c.current)["type"]]
		if not _visit(where, c, sim, pick):
			c = null  # wrecked: the run is over, a new one begins
			continue
		var to := _choose_lane(where, c, sim, pick)
		if to == "":
			break
		var drift: bool = ship.inventory.count("fuel") < 1
		if not _light_speed(where, c, sim, to, drift):
			break
		if drift:
			stats["drifts"] += 1
		made += 1
		stats["jumps"] += 1
		_audit(where + " after the jump", c, ship)
	check(made == JUMPS, "%s: made %d of %d jumps (the run got stuck at %s)" % [tag, made, JUMPS, c.current if c != null else "?"])
	if c != null:
		_warden(tag, c, sim, pick)
	stats["known"] += sim.player_ship().crafting.known.size()  # blueprints at the end of the run (salvage scans add to it)
	stats["dead"] += sim.player_ship().dead_crew.size()  # crew who bled out


## The region's exit beacon (docs/MECHANICS_REVIEW.md P7): its warden holds the lane. The ship arrives as the beacon's POI makes it
## (Campaign.arrive) and meets the warden like any event (pay the toll, good standing, break through or turn back, at random), up
## to WARDEN_TRIES times; once it is cleared the exit is open and the crossing works. False when the run ended with a lost fight.
func _warden(tag: String, c: Campaign, sim, pick: RandomNumberGenerator) -> bool:
	var ship = sim.player_ship()
	c.current = c.drift.exit_id()
	c.visited[c.current] = true
	c._enter(c.current, ship)
	var poi := str(c.current_sector().main_poi()["id"])
	var at := tag + " at the exit"
	for i in WARDEN_TRIES:
		var a := c.arrive(ship)
		if not c.warden_up():
			check(a["exit"] and not a["warden"], at + ": the warden is gone, the exit is open")
			var r := c.cross(c.region_offers()[0], ship)
			check(r["ok"], "%s: crossing after the warden: %s" % [at, r["why"]])
			check(c.is_final() or not c.warden.is_empty(), at + ": the next region has its warden")
			stats["cleared"] += 1
			return true
		check(a["warden"] and not a["exit"] and a["event"].get("title", "") == c.warden["name"], at + ": the warden's event and no exit")
		stats["wardens"] += 1
		if not _event_chain(at, a["event"], c, sim, pick, poi):
			return false
		_audit(at + " after the warden", c, ship)
	return true


## In the sector of the current node: fly to its own POI (its event, a station's dock) and maybe to one other new POI,
## running whatever triggers on the way. False when the run ended with a lost fight.
func _visit(where: String, c: Campaign, sim, pick: RandomNumberGenerator) -> bool:
	var s = c.current_sector()
	var ship = sim.player_ship()
	_helm = Helm.new()
	_helm.refresh(ship)
	_helm.place(s.ship_pos, s.ship_vel, s.ship_angle)
	check(s.ship_pos.distance_to(s.arrival) < 1.0, where + ": the ship arrives at the sector's arrival point")
	_goals = [s.main_poi()["id"]]
	var others: Array = s.pois.filter(func(p): return not p["main"] and p["state"] == Sector.NEW)
	if not others.is_empty() and pick.randf() < OTHER_POI:
		_goals.append(others[pick.randi() % others.size()]["id"])
	while not _goals.is_empty():
		var id: String = _goals.pop_front()
		var poi: Dictionary = s.find(id)
		if poi.is_empty() or (poi["state"] == Sector.DONE and not bool(s.cfg["poi_types"].get(poi["type"], {}).get("repeat", false))):
			continue
		var r := _fly(where, c, sim, pick, s, id)
		if r == "wrecked":
			return false
		if r == "grounded":  # a fight shot away its helm or reactor for good: it only jumps on now
			break
		if r == "lost":
			check(false, "%s: the autopilot did not reach %s (%s) in %d s: %d px away, speed %d, state %s" % [where, id, poi["type"], FLY_CAP_S,
				_helm.flight.pos.distance_to(s.find(id)["pos"]), _helm.flight.vel.length(), _helm.state])
	return true


## Fly to POI `id` with the autopilot, at the time scale, until it triggers: "reached", "wrecked" (a fight was lost on
## the way), "grounded" (the ship cannot fly even after the crew had time to repair it: a wrecked helm, reactor or
## engine stays wrecked) or "lost" (the autopilot failed).
func _fly(where: String, c: Campaign, sim, pick: RandomNumberGenerator, s, id: String) -> String:
	var ship = sim.player_ship()
	_helm.set_course(id)
	var t := 0.0
	var fixing := 0.0
	while t < FLY_CAP_S:
		_helm.refresh(ship)
		if _helm.why_not != "":  # broken down: the crew repair it while the ship coasts
			sim.step(1.0)
			fixing += 1.0
			if fixing > REPAIR_CAP_S:
				stats["grounded"] += 1
				return "grounded"
			continue
		_helm.step(FLY_STEP, s, true)
		stats["flown_s"] += FLY_STEP
		stats["contacts"] += s.tick(FLY_STEP, ship).size()
		t += FLY_STEP
		var res: Dictionary = s.trigger(c, ship)
		if not res.is_empty():
			if not _poi_chain(where, res, c, sim, pick, s):
				return "wrecked"
			if str(res["poi"]["id"]) == id:
				return "reached"
			_helm.set_course(id)
		if _helm.course.is_empty():
			return "reached" if s.find(id).get("state", Sector.NEW) == Sector.DONE else "lost"
	return "lost"


## A POI has triggered (Sector.trigger): its event chain and docking the way map_view.gd open_poi() plays them, then it
## is resolved. False when the run ended with a lost fight.
func _poi_chain(where: String, res: Dictionary, c: Campaign, sim, pick: RandomNumberGenerator, s) -> bool:
	stats["pois"] += 1
	var at := "%s, POI %s (%s)" % [where, res["poi"]["id"], res["poi"]["type"]]
	if res["refused"] == "" and not res["event"].is_empty():
		if not _event_chain(at, res["event"], c, sim, pick, str(res["poi"]["id"])):
			return false
	if res["dock"]:
		_station(at + " (docked)", c, sim.player_ship(), pick)
	s.resolve(str(res["poi"]["id"]))
	_audit(at + " after it", c, sim.player_ship())
	return true


## Light speed to `to`: spool the drive (nothing near blocks it) while the ship coasts, and let it fire. False when it
## was refused (reported).
func _light_speed(where: String, c: Campaign, sim, to: String, drift: bool) -> bool:
	var ship = sim.player_ship()
	var s = c.current_sector()
	var r := c.start_jump(to, ship, s.hostile_near(c.hostile_range()), drift)
	check(r["ok"], "%s: the jump to %s could spool (%s)" % [where, to, r.get("why", "")])
	if not r["ok"]:
		return false
	var state := "spooling"
	var t := 0.0
	while state == "spooling" and t < c.spool_time() + 1.0:
		_helm.step(FLY_STEP, s, true)
		state = c.tick_jump(FLY_STEP, s.hostile_near(c.hostile_range()), ship)
		t += FLY_STEP
	check(state == "jumped", "%s: the jump to %s fired (%s: %s)" % [where, to, state, c.last_jump.get("why", "")])
	return state == "jumped" and c.current == to


## Pick a lane: a random neighbour that may be entered. With no fuel, a drift jump if the hull allows it,
## else a wait for a trader. "" when nothing can be done (a soft-lock, which is reported).
func _choose_lane(where: String, c: Campaign, sim, pick: RandomNumberGenerator) -> String:
	var ship = sim.player_ship()
	var open: Array = []
	for o in c.neighbours(c.current):
		if c.jump_block(o, ship, false) == "" and c.node(o)["type"] != "gate":
			open.append(o)
	if not open.is_empty():
		if ship.inventory.count("fuel") <= 2:  # a sensible player heads for a station to refuel
			var step := _towards_station(c)
			if step != "" and open.has(step):
				return step
		return open[pick.randi() % open.size()]
	var drifts: Array = []
	for o in c.neighbours(c.current):
		if c.jump_block(o, ship, true) == "":
			drifts.append(o)
	if not drifts.is_empty():
		return drifts[pick.randi() % drifts.size()]
	# No fuel, no drift: wait for a trader (time passes) and buy fuel off him if he comes.
	for i in MAX_WAITS:
		var w := c.wait(ship)
		stats["waits"] += 1
		if w["event"].is_empty():
			continue
		_event_chain(where + " (waiting)", w["event"], c, sim, pick)
		if ship.inventory.count("fuel") > 0:
			return _choose_lane(where, c, sim, pick)
	# Still nothing (a broke run in the Hollow tide's far reaches can't afford the trader's fuel): Ma's tow home, which
	# the map always offers with an empty tank so that a run never soft-locks (Y).
	var tow := c.tow(ship)
	stats["tows"] += 1
	check(tow["ok"], "%s: stuck with no fuel, no drift jump, no trader and no tow (fuel %d, credits %d, hull left %d): %s" % [where, ship.inventory.count("fuel"), ship.inventory.count("credits"), c.hull_left(ship), tow["why"]])
	return _choose_lane(where, c, sim, pick) if tow["ok"] else ""


## The first node on the shortest lane path from the ship to a station it can dock at ("" when it is at
## one, or none can be reached).
func _towards_station(c: Campaign) -> String:
	var came := {c.current: ""}
	var queue: Array = [c.current]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at != c.current and not c.station_cfg(at).is_empty() and c.dock_block(at) == "" and c.node(at)["type"] != "gate":
			while came[at] != c.current:
				at = came[at]
			return at
		for o in c.neighbours(at):
			if not came.has(o) and c.node(o)["type"] != "gate":
				came[o] = at
				queue.append(o)
	return ""


## Docked at a station: pay a due payment, buy fuel when low, sell a little, repair, and look at the stock.
func _station(where: String, c: Campaign, ship, pick: RandomNumberGenerator) -> void:
	if c.station_cfg(c.current).is_empty() or c.dock_block(c.current) != "":
		return
	stats["docks"] += 1
	var st := c.station_cfg(c.current)
	var services: Array = st["services"]
	if services.has("debt") and c.behind() > 0 and ship.inventory.count("credits") >= int(c.cfg["debt"]["payment"]):
		var r := c.pay_debt(ship, int(c.cfg["debt"]["payment"]))
		check(r["ok"], where + ": paying the debt: " + str(r["text"]))
	if services.has("fuel"):
		var guard := 0
		while ship.inventory.count("fuel") < 4 and guard < 12:
			guard += 1
			var r := c.buy_fuel(ship, c.current, 1)
			if not r["ok"]:
				break
	if services.has("repair") and c.hull_loss > 0 and ship.inventory.count("credits") > 60:
		var r := c.repair(ship, c.current, c.hull_loss)
		check(r["ok"] or ship.inventory.count("credits") < 2 * c.hull_loss, where + ": repair: " + str(r["text"]))
	if services.has("sell") and ship.inventory.count("scrap") > 100 and pick.randf() < 0.5:
		check(c.sell(ship, "scrap", 50)["ok"], where + ": selling scrap")
	if services.has("stock") and not st["stock"].is_empty() and pick.randf() < 0.3:
		var ids: Array = st["stock"].keys()
		ids.sort()
		var item: String = ids[pick.randi() % ids.size()]
		var r := c.buy(ship, c.current, item, 1)
		check(r["ok"] or ship.inventory.count("credits") < c.stock_price(c.current, item), where + ": buying %s: %s" % [item, r["text"]])
	if services.has("recruit") and pick.randf() < 0.3 and not c.offers.get(c.current, []).is_empty():
		var r := c.recruit(ship, c.current, 0)
		check(r["ok"] or ship.inventory.count("credits") < 150 or "room" in str(r["text"]), where + ": recruiting: " + str(r["text"]))
	_audit(where + " after docking", c, ship)


# --- events and fights ---------------------------------------------------------------------------------

## Play an event and everything that follows (pages, fights) the way the event panel and the map do; `poi` is the POI
## it runs at ("" for a wait), where its fights spawn. A won fight leaves a wreck the ship flies to next. Returns false
## when the run ended with a lost fight.
func _event_chain(where: String, ev: Dictionary, c: Campaign, sim, pick: RandomNumberGenerator, poi := "") -> bool:
	var ship = sim.player_ship()
	var pages := 0
	var queue: Array = [ev]
	while not queue.is_empty():
		var e: Dictionary = queue.pop_front()
		if e.is_empty():
			continue
		pages += 1
		stats["events"] += 1
		if pages > MAX_PAGES:
			check(false, "%s: more than %d pages in one chain (a goto loop?), last event '%s'" % [where, MAX_PAGES, e.get("id", "?")])
			return true
		var view := c.events.choice_view(e, c, ship, c.node(c.current))
		var open: Array = view.filter(func(v): return not v["grey"])
		if view.is_empty():
			continue  # the panel shows Leave
		if open.is_empty():
			check(false, "%s: event '%s' shows only greyed choices: the panel has no way out" % [where, e.get("id", "?")])
			continue
		var v: Dictionary = open[pick.randi() % open.size()]
		if e.get("id", "") == "salvage":  # a sensible player scans a blueprint they can learn
			var scans: Array = open.filter(func(w): return str(w["text"]).begins_with("Scan"))
			if not scans.is_empty():
				v = scans[0]
		if ship.inventory.count("fuel") < 1:  # out of fuel: take what pays in fuel, then in credits
			for gain in ["fuel", "credits"]:
				var wanted: Array = open.filter(func(w): return _gives(e, int(w["index"]), gain))
				if not wanted.is_empty():
					v = wanted[pick.randi() % wanted.size()]
					break
		var r := c.events.choose(e, int(v["index"]), c, ship, c.node(c.current))
		check(r["ok"], "%s: choice %d of '%s' was refused: %s" % [where, v["index"], e.get("id", "?"), r.get("why", "")])
		if not r["ok"]:
			continue
		_audit("%s after '%s'" % [where, e.get("id", "?")], c, ship)
		if str(r["fight"]) != "":
			var res := _fight(where, str(r["fight"]), c, sim, pick, poi)
			var done := c.fight_done(res, ship, r["after_win"])
			_audit(where + " after the fight", c, ship)
			if done["state"] == "lost":
				return false
			if done["fight"] != "":
				queue.append({"id": "(after_win fight)", "text": "-", "choices": [{"text": "Fight", "outcomes": [{"weight": 100, "effects": {"fight": done["fight"]}}]}]})
			elif done["goto"] != "" and c.events.has(done["goto"]):
				queue.append(c.events.get_event(done["goto"]))
			elif done["state"] in ["won", "captured"]:
				queue.append(Salvage.event_for(res.get("enemy"), done["state"], c, ship))
				stats["salvage"] += 1
		elif str(r["goto"]) != "":
			check(c.events.has(r["goto"]), "%s: '%s' goes to an event that does not exist: %s" % [where, e.get("id", "?"), r["goto"]])
			if c.events.has(r["goto"]):
				queue.append(c.events.get_event(r["goto"]))
	return true


## Does some outcome of choice `index` of `e` add `item` to the cargo?
func _gives(e: Dictionary, index: int, item: String) -> bool:
	for o in e["choices"][index].get("outcomes", []):
		var eff = o.get("effects", {})
		if eff is Dictionary and eff.get("items") is Dictionary and float(eff["items"].get(item, 0)) > 0.0:
			return true
	return false


## A fight in place through the real arena, both ships flown by the pilot AI: the enemy spawns at POI `poi`
## (Sector.fight_spawn; ahead of the ship for a wait), the player's ship starts where it flies (Helm.fight_place). It
## ends decided (won, captured, spared: the player takes a surrender when one is offered, escaped), out of range
## (LEAVE_DISTANCE: "fled"), or as a draw over FIGHT_CAP_S. Returns the result the combat view gives the map: {state,
## enemy, hull, hull_max, enemy_pos, offer (spared)}; the helm takes the ship's place after it.
func _fight(where: String, value: String, c: Campaign, sim, pick: RandomNumberGenerator, poi := "") -> Dictionary:
	stats["fights"] += 1
	var s = c.current_sector()
	var spot: Dictionary = s.fight_spawn(c, poi, value) if poi != "" else {}
	if spot.is_empty():
		spot = {"design": c.fight_path(value, str(c.node(c.current)["type"])), "pos": null}
	var place: Dictionary = _helm.fight_place(spot["pos"], Session.SPAWN_DISTANCE, s.size)
	var enemy = Session.load_ship(spot["design"])
	check(enemy != null, "%s: the enemy design loads: %s" % [where, spot["design"]])
	if enemy == null:
		return {"state": "fled", "enemy_pos": place["enemy_pos"]}
	var player = sim.player_ship()
	if _real_left <= 0:
		return _stub_fight(enemy, player, c, pick, place["enemy_pos"])
	_real_left -= 1
	sim.ships.append(enemy)
	var ses := Session.new()
	ses.start(player, enemy, enemy.rng_seed, place)
	var mine = ses.arena.ships[Session.PLAYER]
	var foe = ses.arena.ships[Session.ENEMY]
	check(mine.flight.pos == place["player_pos"] and foe.flight.pos.distance_to(mine.flight.pos) >= Session.SPAWN_DISTANCE - 1.0, where + ": the fight starts in the sector, the enemy at a distance")
	mine.hull = c.fight_hull(mine.hull_max)  # what the campaign says is left of the hull
	ses.arena.hazard = c.hazard_at(c.current)  # the node's sector hazard, as the map sets it
	var pilot := PilotAI.new(ses.arena, Session.PLAYER, Session.ENEMY, {})
	var ticks := int(_cap_s * 60.0)
	var n := 0
	while ses.state() == "fighting" and n < ticks and ses.distance() <= Session.LEAVE_DISTANCE:
		if n % PLAYER_PILOT_EVERY == 0:
			pilot.think(Session.STEP * PLAYER_PILOT_EVERY)
		if ses.morale.state == "offering":
			ses.accept_surrender()  # the player takes a surrender when it is offered
		ses.ai.think(Session.STEP)
		ses.arena.step(Session.STEP)
		ses.morale.tick(Session.STEP)
		n += 1
		if n % int(SIM_STEP * 60.0) == 0:
			sim.step(SIM_STEP)
			s.hostiles = [] if foe.wrecked else [foe.flight.pos]
			check(not c.start_jump(c.neighbours(c.current)[0], player, s.hostile_near(c.hostile_range()))["ok"] or not s.hostile_near(c.hostile_range()), where + ": no jump with the enemy within 2,000 px")
			c.cancel_jump()
		if n % 600 == 0:
			_audit_fight(where, ses)
	_audit_fight(where, ses)
	s.hostiles.clear()
	var state := ses.state()
	if state == "fighting":
		state = "fled"
	stats[{"won": "won", "captured": "won", "spared": "won", "lost": "lost"}.get(state, "draw")] += 1  # escaped and fled are draws
	_helm.place(mine.flight.pos, mine.flight.vel, mine.flight.angle, mine.flight.ang_vel)
	_helm.sync_to(s)
	var res := {"state": state, "enemy": foe.ship, "hull": mine.hull, "hull_max": mine.hull_max, "enemy_pos": foe.flight.pos}
	if state == "spared":
		res["offer"] = ses.morale.offer.duplicate()
	stats["fight_ticks"] += n
	sim.ships.erase(enemy)
	return res


## A fight that is not simulated: the result the combat view would give, picked at random (a win, a
## retreat or a loss, with some hull gone), so the campaign's loot, hull and run-over paths still run.
func _stub_fight(enemy, player, c: Campaign, pick: RandomNumberGenerator, at: Vector2) -> Dictionary:
	var roll := pick.randf()
	var state := "won" if roll < 0.55 else ("fled" if roll < 0.85 else "lost")
	stats["won" if state == "won" else ("draw" if state == "fled" else "lost")] += 1
	var hull_max := float(c.hull_max(player))
	var hull := 0.0 if state == "lost" else maxf(1.0, hull_max - float(c.hull_loss) - pick.randf() * 60.0)
	return {"state": state, "enemy": enemy, "hull": hull, "hull_max": hull_max, "enemy_pos": at}


func _audit_fight(where: String, s: Session) -> void:
	for i in 2:
		var co = s.arena.ships[i]
		check(co.hull >= 0.0 or co.wrecked, "%s: ship %d hull is %s" % [where, i, str(co.hull)])
		check(is_finite(co.flight.pos.x) and is_finite(co.flight.pos.y) and is_finite(co.flight.angle), "%s: ship %d position is not a number: %s" % [where, i, str(co.flight.pos)])
		check(is_finite(co.flight.vel.x) and is_finite(co.flight.vel.y), "%s: ship %d velocity is not a number" % [where, i])
		check(co.layers >= 0.0 if typeof(co.layers) == TYPE_FLOAT else true, "%s: ship %d has negative shield layers" % [where, i])


# --- the numbers ---------------------------------------------------------------------------------------

## The state is sane: no negative cargo or hull, every held id known, the debt and reputation in range.
func _audit(where: String, c: Campaign, ship) -> void:
	for id in ship.inventory.counts:
		var n: int = ship.inventory.counts[id]
		check(n > 0, "%s: %d of %s in the cargo" % [where, n, id])
		check(_known_item(ship, str(id)), "%s: unknown item id '%s' in the cargo" % [where, id])
	check(ship.inventory.count("fuel") >= 0 and ship.inventory.count("credits") >= 0, where + ": negative fuel or credits")
	check(c.hull_loss >= 0 and c.hull_left(ship) >= 1, "%s: hull integrity %d of %d" % [where, c.hull_left(ship), c.hull_max(ship)])
	check(c.debt >= 0 and c.paid >= 0 and c.jumps >= 0, "%s: debt %d, paid %d, jumps %d" % [where, c.debt, c.paid, c.jumps])
	check(c.drift.has(c.current), where + ": the ship is at a node that does not exist: " + c.current)
	for f in c.rep:
		check(c.rep[f] >= -10 and c.rep[f] <= 10, "%s: %s reputation %d" % [where, f, c.rep[f]])
	for m in ship.crew:
		check(m.hp >= 0.0 and m.hp <= m.max_hp + 0.01, "%s: %s has %s hp" % [where, m.name, str(m.hp)])
		check(m.name != "", where + ": a crew member with no name")


func _known_item(ship, id: String) -> bool:
	return id in ["credits", "fuel"] or ship.components.has(id) or ship.crafting.materials.has(id) or Campaign._item_kinds().has(id)


# --- regressions found by the soak ------------------------------------------------------------------------

## A fight leaves breaches, and a damaged hull has a lower maximum than the one the loss was counted
## against: the integrity shown went negative ("Hull -20/170"). It stays at 1 or more.
func test_regression_hull_left_is_never_below_one() -> void:
	var sim := ShipSim.new()
	sim.choose_ship(STARTERS[0])
	var ship = sim.player_ship()
	var c := Campaign.new(1)
	c.hull_loss = c.hull_max(ship) + 20
	eq(c.hull_left(ship), 1, "a loss bigger than the maximum leaves 1")
	c.hull_loss = 0
	eq(c.hull_left(ship), c.hull_max(ship), "no loss leaves the maximum")


## The hull lost in a fight (or an event, or a drift jump) was forgotten at the next fight, which began at
## full hull and then overwrote the loss: repairing at a station did nothing. A fight now begins with the
## integrity the campaign says is left.
func test_regression_a_fight_starts_with_the_hull_the_campaign_has_left() -> void:
	var sim := ShipSim.new()
	sim.choose_ship(STARTERS[1])
	var build := BuildMode.new()
	build.sim = sim
	build.build_on = false
	var view := CombatView.new()
	view.sim = sim
	view.build = build
	var map := MapView.new()
	map.sim = sim
	map.combat = view
	map.size = Vector2(1600.0, 900.0)
	map.new_game(7)
	map._start_fight("pirate_raider", {})
	check(view.active, "the fight starts")
	var mine = view.session.arena.ships[Session.PLAYER]
	eq(mine.hull, mine.hull_max, "a fresh campaign begins the fight at full hull")
	view.leave()
	map.campaign.hull_loss = 40
	map._start_fight("pirate_raider", {})
	check(view.active, "a second fight starts")
	mine = view.session.arena.ships[Session.PLAYER]
	eq(mine.hull, mine.hull_max - 40.0, "40 points lost, 40 points fewer")
	view.leave()
	map.campaign.hull_loss = 100000
	map._start_fight("pirate_raider", {})
	eq(view.session.arena.ships[Session.PLAYER].hull, 1.0, "never below 1")
	view.leave()
	map.free()
	view.free()
	build.free()
	sim.free()


## An event whose every shown choice is greyed (it asks for credits or items you lack) used to leave the
## event panel with nothing to press: no key or click went on. The panel now adds Leave.
func test_regression_an_event_of_only_greyed_choices_still_has_a_way_out() -> void:
	var sim := ShipSim.new()
	sim.choose_ship(STARTERS[1])
	var map := MapView.new()
	map.sim = sim
	map.size = Vector2(1600.0, 900.0)
	map.new_game(7)
	var ev := {"id": "poor_test", "type": "empty", "text": "A toll.", "choices": [
		{"text": "Pay the toll.", "requires": {"credits": 99999}, "outcomes": [{"weight": 100, "text": "", "effects": {}}]}]}
	var finished := [0]
	map.event_panel.finished.connect(func(): finished[0] += 1)
	map.event_panel.open_event(ev)
	eq(map.event_panel.view.size(), 2, "the greyed choice and Leave")
	check(map.event_panel.view[0]["grey"] and not map.event_panel.view[1]["grey"], "the first is greyed, the second is not")
	eq(map.event_panel.choose(1), "", "Leave works")
	check(not map.event_panel.visible, "the panel closes")
	eq(finished[0], 1, "and tells the map it is done")
	map.free()
	sim.free()
