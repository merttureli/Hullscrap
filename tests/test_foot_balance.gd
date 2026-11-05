extends "res://tests/base_test.gd"
## On-foot balance (boarding.json `enemies`, tests/foot_bench.gd): a scripted starting soldier kills about 3 common foes per 100 hp lost, the same seed plays the same
## fight, and a foe that is alerted calls the idle mates within its alert_r (so a fight is 2-3 foes at once, not one by one).

const Bench = preload("res://tests/foot_bench.gd")
const Foes = preload("res://scripts/board/foes.gd")

const SEEDS := [1, 38, 75, 112, 149, 186]


func _sum(kind: String) -> Dictionary:
	var kills := 0
	var lost := 0.0
	for sd in SEEDS:
		var r: Dictionary = Bench.run(kind, sd, "start", 60, 0)
		check(not r.is_empty(), "%s %d builds" % [kind, sd])
		if r.is_empty():
			continue
		for k in r["kills"]:
			kills += int(r["kills"][k])
		lost += float(r["lost_total"])
	return {"kills": kills, "lost": lost, "per_bar": 100.0 * kills / maxf(lost, 1.0)}


func test_a_starting_soldier_kills_two_to_four_foes_per_health_bar() -> void:
	var sc := _sum("only_scavenger")
	var pi := _sum("only_pirate")
	check(sc["per_bar"] >= 2.0 and sc["per_bar"] <= 4.5, "scavengers: %.2f kills per 100 hp lost" % sc["per_bar"])
	check(pi["per_bar"] >= 1.5 and pi["per_bar"] <= 4.0, "pirates: %.2f kills per 100 hp lost" % pi["per_bar"])
	var both: float = 100.0 * (sc["kills"] + pi["kills"]) / maxf(sc["lost"] + pi["lost"], 1.0)
	check(both >= 2.0 and both <= 4.0, "both together: %.2f kills per 100 hp lost" % both)


func test_the_same_seed_plays_the_same_fight() -> void:
	var a: Dictionary = Bench.run("station", 75, "start", 60, 0)
	var b: Dictionary = Bench.run("station", 75, "start", 60, 0)
	check(not a.is_empty(), "the station builds")
	eq(a["kills"], b["kills"], "the same kills")
	eq(a["lost_total"], b["lost_total"], "the same health lost")
	eq(a["time"], b["time"], "the same length")


func _two_foes(kind: String, apart: float):
	var s = Bench.session("station", 31, "start", 60, 0)
	s.foes = Foes.new(s)
	var room: int = int(s.site.airlock["room"])
	var a: Dictionary = s.foes.add(kind, s.soldier.pos + Vector2(20, 0), room)
	var b: Dictionary = s.foes.add(kind, a["m"].pos + Vector2(apart, 0), room)
	return [s, a, b]


func test_an_alerted_scavenger_calls_the_idle_mates_within_its_call_radius() -> void:
	var call_r := float(Foes.def("scavenger")["alert_r"])
	check(call_r >= 8.0, "scavengers call from %.1f cells" % call_r)
	var near: Array = _two_foes("scavenger", call_r - 0.5)
	near[1]["mode"] = "idle"
	near[2]["mode"] = "idle"
	near[0].foes._alert(near[1], near[0].soldier.pos)
	eq(near[1]["mode"], "hunt", "the one that noticed hunts")
	eq(near[2]["mode"], "hunt", "a mate %.1f cells off is called in" % (call_r - 0.5))
	var far: Array = _two_foes("scavenger", call_r + 1.0)
	far[1]["mode"] = "idle"
	far[2]["mode"] = "idle"
	far[0].foes._alert(far[1], far[0].soldier.pos)
	eq(far[2]["mode"], "idle", "a mate further off than the call radius stays")
