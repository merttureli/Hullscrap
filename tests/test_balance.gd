extends "res://tests/base_test.gd"
## The balance pass (docs/BALANCE_REPORT.md, tests/tool_balance.gd): fights between a starter and a generated enemy, both
## flown by the pilot AI, now end; the threat rating's cuts are the calibrated ones and order known pairs.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const COURIER := "res://data/ships/starter_courier.json"
const STEP := 1.0 / 60.0


## A fight as the harness runs it: the player's pilot thinks every 3rd tick at the threat table's player_aim and goes for
## a fleeing foe's engines, the crews run in ShipSim, the player takes a surrender. Returns [state, seconds].
func _fight(player_path: String, spec: String, seed_value: int, cap_s: float) -> Array:
	var player: Ship = Ship.from_design(player_path)
	var enemy: Ship = Session.load_ship(spec)
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	if player.crew_plan.size() == 1:  # a starter has the soldier alone (playtest 2, A1): these fights are the pilot's, with a crew at the guns as in the harness's day
		player.crew_plan = [{"name": "Soldier", "species": "human"}, {"name": "Ada", "species": "human"}, {"name": "Bram", "species": "basalt"}]
	Jobs.spawn_crew(player)
	var s := Session.new()
	s.start(player, enemy, seed_value)
	var pilot := PilotAI.new(s.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = s.morale
	var n := 0
	while s.state() == "fighting" and n < int(cap_s * 60.0):
		if n % 3 == 0:
			pilot.think(STEP * 3)
		if s.morale.state == "offering":
			s.accept_surrender()
		s.ai.think(STEP)
		s.arena.step(STEP)
		s.morale.tick(STEP)
		n += 1
		if n % 12 == 0:
			sim.step(0.2)
	sim.free()
	return [s.state(), n * STEP]


## Fights that used to run to the cap (docs/BALANCE_REPORT.md before: 83% draws, the Courier's gun shot out in seconds and
## its shots spent on the enemy's guns) now end: the pilot holds its gun in range, aims at the hull clear of the guns, and
## the barrels take more than one volley. Three jump 5 fights of the harness (its seeds); at least two end inside 150 s.
func test_starter_fights_at_jump_5_now_end() -> void:
	var ended := []
	for f in [["gen:clans:small:8175:4800", 1015], ["gen:lumen:small:256:4800", 6], ["gen:hollow:small:8175:6720", 1015]]:
		var r := _fight(COURIER, f[0], f[1], 150.0)
		if r[0] != "fighting":
			ended.append("%s %s at %d s" % [f[0], r[0], r[1]])
	check(ended.size() >= 2, "at least two of the three end: %s" % str(ended))


## The threat cuts are the ones the harness measured (docs/BALANCE_REPORT.md: power ratio under 0.5 won about 85% of fights,
## 0.85 to 1.6 about even, over 2.6 about 15%), and they rate known pairs that way: a jump 5 enemy is a skull or two to the
## Courier, a jump 35 large one four or five.
func test_the_threat_cuts_are_the_measured_ones() -> void:
	var cuts: Array = Threat.config()["cuts"]
	eq(cuts, [0.5, 0.85, 1.6, 2.6], "the cuts of the balance pass")
	for k in 3:
		check(float(cuts[k]) < float(cuts[k + 1]), "the cuts rise")
	var courier: Ship = Ship.from_design(COURIER)
	var early := Shipgen.budget_for(1, 5, 1.0)
	var late := Shipgen.budget_for(3, 35, 1.0)
	for f in ["clans", "rustfangs", "lumen"]:
		var weak := Threat.rate(Shipgen.build(f, "small", 256, early), courier)
		check(int(weak["skulls"]) <= 2, "%s at jump 5 (budget %d): %d skulls, ratio %.2f" % [f, early, weak["skulls"], weak["ratio"]])
	for f in ["clans", "rustfangs", "concord"]:  # (a Lumen ship spends its budget on shields and its reactor: a softer late threat)
		var strong := Threat.rate(Shipgen.build(f, "large", 256, late), courier)
		var least := 3 if f == "clans" else 4  # (a Clans ship carries rapid turrets now, whose shots are light: three skulls, a hard fight still)
		check(int(strong["skulls"]) >= least, "%s at jump 35 (budget %d): %d skulls, ratio %.2f" % [f, late, strong["skulls"], strong["ratio"]])
