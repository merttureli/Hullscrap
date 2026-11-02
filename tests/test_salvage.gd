extends "res://tests/base_test.gd"
## Salvage after a fight (scripts/space/salvage.gd, Campaign.fight_done, the map's hook): the pick-1-of-3 event
## of the enemy's surviving parts, the blueprint scan, the strip scrap, and what each of the six fight states pays.

const Campaign = preload("res://scripts/space/campaign.gd")
const Events = preload("res://scripts/space/events.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const RAIDER := "res://data/ships/pirate_raider.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## The Pirate Raider keeping only the parts whose ids are in `keep` (all of them when empty).
func _enemy(keep: Array = []) -> Ship:
	var e: Ship = Ship.from_design(RAIDER)
	if not keep.is_empty():
		for uid in e.components.instances.keys():
			if not keep.has(e.components.instances[uid]["id"]):
				e.components.remove_uid(uid)
	return e


## The ids the "Cut out" rows hand over, in row order.
func _cut_ids(ev: Dictionary) -> Array:
	var out := []
	for ch in ev["choices"]:
		var items: Dictionary = ch["outcomes"][0]["effects"].get("items", {})
		if ch["text"].begins_with("Cut out") and items.size() == 1:
			out.append(items.keys()[0])
	return out


func _row(ev: Dictionary, start: String) -> int:
	for i in ev["choices"].size():
		if ev["choices"][i]["text"].begins_with(start):
			return i
	return -1


# --- the event ------------------------------------------------------------------------------------------

func test_only_surviving_parts_are_offered_never_wrecked_beds_or_helms() -> void:
	var enemy := _enemy()
	var ids := []
	for inst in enemy.components.instances.values():
		ids.append(inst["id"])
	check(ids.has("helm"), "the raider has a helm (so the test means something)")
	for uid in enemy.components.instances.keys():
		if enemy.components.instances[uid]["id"] == "shield_mk1":
			enemy.components.wreck(uid)  # shot to pieces in the fight: gone from the ship
	for uid in enemy.components.instances.keys():
		if enemy.components.instances[uid]["id"] == "laser_mk1":
			enemy.components.instances[uid]["id"] = "bed"  # a bed where the laser was
	for seed_value in 40:
		var c := Campaign.new(seed_value)
		var ev := Salvage.event_for(enemy, "captured", c, _ship())
		for id in _cut_ids(ev):
			check(id != "shield_mk1", "seed %d: a wrecked shield is not offered" % seed_value)
			check(id != "helm" and id != "bed", "seed %d: no helm, no bed (%s)" % [seed_value, id])
			check(ids.has(id), "seed %d: %s is a part of the ship" % [seed_value, id])


func test_three_candidates_for_a_win_four_for_a_capture_and_the_same_every_time_for_a_seed() -> void:
	var enemy := _enemy()
	var seen := {}
	for seed_value in 30:
		var won := Salvage.event_for(enemy, "won", Campaign.new(seed_value), _ship())
		var cap := Salvage.event_for(enemy, "captured", Campaign.new(seed_value), _ship())
		eq(_cut_ids(won).size(), 3, "a win offers 3 parts")
		eq(_cut_ids(cap).size(), 4, "a capture offers 4")
		var again := Salvage.event_for(enemy, "won", Campaign.new(seed_value), _ship())
		eq(again, won, "seed %d: the same seed gives the same event" % seed_value)
		var uniq := {}
		for id in _cut_ids(won):
			uniq[id] = true
		eq(uniq.size(), 3, "three different parts")
		seen[str(_cut_ids(won))] = true
	check(seen.size() > 3, "different seeds offer different parts (%d sets)" % seen.size())
	var two := _enemy(["laser_mk1", "engine_mk1"])
	eq(_cut_ids(Salvage.event_for(two, "captured", Campaign.new(1), _ship())).size(), 2, "a ship with two kinds of part offers two")


func test_the_event_has_the_texts_and_the_rows_in_order() -> void:
	var enemy := _enemy()
	var won := Salvage.event_for(enemy, "won", Campaign.new(3), _ship())
	eq([won["id"], won["type"], won["once"]], ["salvage", "salvage", false], "id, type and once")
	eq(won["title"], "Salvage: Pirate Raider", "the panel is titled by the wreck, not the node")
	eq(won["text"], "The Pirate Raider hangs dead, venting. Your cutters have time for one job before she breaks up.", "the won text")
	var texts: Array = won["choices"].map(func(ch): return ch["text"])
	check(texts[0].begins_with("Cut out the ") and texts[2].begins_with("Cut out the "), "the cut rows come first")
	check(texts[-1].begins_with("Strip her for scrap (+"), "a win ends with the strip row")
	for ch in won["choices"]:
		eq(ch["outcomes"].size(), 1, "one outcome per row")
	var cap := Salvage.event_for(enemy, "captured", Campaign.new(3), _ship())
	eq(cap["text"], "Nobody is left standing aboard the Pirate Raider. Your crew strip her hold, then pick one prize to cut loose.", "the captured text")
	check(_row(cap, "Strip") < 0, "a captured ship has no strip row: fight_done paid it")
	eq(Salvage.event_for(_enemy(["helm"]), "captured", Campaign.new(1), _ship()), {}, "nothing to cut and no strip row: no event")


func test_a_scan_row_only_for_an_unknown_recipe_and_it_unlocks_the_blueprint() -> void:
	var c := Campaign.new(4)
	var ship := _ship()
	check(not ship.crafting.is_known("reactor_mk2"), "the Reactor Mk2 blueprint is not known at the start")
	var enemy := _enemy(["laser_mk1", "engine_mk1", "reactor_mk2"])
	var ev := Salvage.event_for(enemy, "won", c, ship)
	var scan := _row(ev, "Scan the ")
	check(scan >= 0, "an unknown recipe gets a scan row")
	eq(ev["choices"][scan]["text"], "Scan the Reactor Mk2 (learn its blueprint)", "its text")
	eq(ev["choices"][scan]["outcomes"][0]["effects"], {"blueprint": ["reactor_mk2"]}, "its effect")
	eq(ev["choices"].filter(func(ch): return ch["text"].begins_with("Scan")).size(), 1, "only one scan row")
	var r := c.events.choose(ev, scan, c, ship)
	check(r["ok"], "the row can be taken")
	check(ship.crafting.is_known("reactor_mk2"), "taking it unlocks the blueprint")
	check(r["lines"].any(func(l): return l.begins_with("Blueprint learned")), "and says so")
	eq(_row(Salvage.event_for(enemy, "won", c, ship), "Scan the "), -1, "known now: no scan row")
	var known_only := _enemy(["laser_mk1", "engine_mk1"])
	eq(_row(Salvage.event_for(known_only, "won", c, _ship()), "Scan the "), -1, "parts whose recipes are known have no scan row")


func test_the_scan_row_is_the_highest_tier_unknown_recipe() -> void:
	var c := Campaign.new(5)
	var ship := _ship()
	var enemy := _enemy(["laser_mk1", "engine_mk1", "reactor_mk2"])
	for uid in enemy.components.instances.keys():
		if enemy.components.instances[uid]["id"] == "laser_mk1":
			enemy.components.instances[uid]["id"] = "pulse_mk1"  # tier 1, recipe unknown
	check(not ship.crafting.is_known("pulse_mk1") and not ship.crafting.is_known("reactor_mk2"), "both recipes are unknown")
	var ev := Salvage.event_for(enemy, "won", c, ship)
	eq(ev["choices"][_row(ev, "Scan the ")]["outcomes"][0]["effects"], {"blueprint": ["reactor_mk2"]}, "tier 2 beats tier 1")
	ship.crafting.unlock("reactor_mk2")
	ev = Salvage.event_for(enemy, "won", c, ship)
	eq(ev["choices"][_row(ev, "Scan the ")]["outcomes"][0]["effects"], {"blueprint": ["pulse_mk1"]}, "with the tier 2 known, the tier 1 is scanned")


func test_the_strip_scrap_follows_the_formula() -> void:
	var enemy := _enemy()
	var n := Salvage.parts(enemy).size()
	eq(n, 8, "the raider has 8 parts that can be cut out (9 less the helm)")
	for jumps in [0, 10, 25]:
		var c := Campaign.new(2)
		c.jumps = jumps
		var want: int = (int(c.cfg["loot"]["strip_base"]) + int(c.cfg["loot"]["strip_per_part"]) * n) * c.tier()
		eq(want, (20 + 6 * n) * c.tier(), "the numbers of data/drift.json: 20 + 6 per part, times the tier")
		var ev := Salvage.event_for(enemy, "won", c, _ship())
		var strip: Dictionary = ev["choices"][_row(ev, "Strip her for scrap")]
		eq(strip["outcomes"][0]["effects"], {"items": {"scrap": want}}, "the scrap at tier %d" % c.tier())
		eq(strip["text"], "Strip her for scrap (+%d)" % want, "and the row says so")
	var c1 := Campaign.new(2)
	var shield_uid := -1
	for uid in enemy.components.instances.keys():
		if enemy.components.instances[uid]["id"] == "shield_mk1":
			shield_uid = uid
	enemy.components.wreck(shield_uid)
	eq(Salvage.strip_scrap(enemy, c1), 20 + 6 * (n - 1), "a part the fight wrecked is no scrap")


func test_every_row_can_be_taken_and_pays_what_it_says() -> void:
	var enemy := _enemy()
	var c := Campaign.new(8)
	var ship := _ship()
	var ev := Salvage.event_for(enemy, "won", c, ship)
	for i in ev["choices"].size():
		var eff: Dictionary = ev["choices"][i]["outcomes"][0]["effects"]
		var before := ship.inventory.counts.duplicate()
		var r := c.events.choose(ev, i, c, ship)
		check(r["ok"], "row %d can be taken: %s" % [i, r.get("why", "")])
		if eff.has("items"):
			for id in eff["items"]:
				eq(ship.inventory.count(id), int(before.get(id, 0)) + int(eff["items"][id]), "row %d gives %s" % [i, id])
	check(not c.used.has("salvage"), "the event is not spent (once is false)")


func test_the_events_validator_accepts_every_effect_of_the_event() -> void:
	var ev_checker := Events.new("res://tests")
	var known := Events._known()
	for state in ["won", "captured"]:
		var ev := Salvage.event_for(_enemy(), state, Campaign.new(6), _ship())
		var errs: Array[String] = []
		var bad := func(msg: String) -> void: errs.append(msg)
		ev_checker._check_keys(ev, Events.EVENT_KEYS + ["type"], "", bad)
		for ch in ev["choices"]:
			ev_checker._check_keys(ch, Events.CHOICE_KEYS, "choice: ", bad)
			check(ch["text"] is String and ch["text"] != "", "a row has text")
			for o in ch["outcomes"]:
				ev_checker._check_keys(o, Events.OUTCOME_KEYS, "outcome: ", bad)
				ev_checker._check_effects(o["effects"], "salvage " + state, known, bad)
		eq(errs, [], "%s: the validator has nothing to say" % state)


# --- Campaign.fight_done in each state -------------------------------------------------------------------

func test_won_pays_credits_only_and_counts_as_a_win() -> void:
	var c := Campaign.new(1)
	var ship := _ship()
	var before := ship.inventory.counts.duplicate()
	var r := c.fight_done({"state": "won", "enemy": _enemy()}, ship)
	var dc: int = ship.inventory.count("credits") - int(before.get("credits", 0))
	check(dc >= 20 and dc <= 60, "credits 20-60 at tier 1 (%d)" % dc)
	for id in ship.inventory.counts:
		if id != "credits":
			eq(ship.inventory.count(id), int(before.get(id, 0)), "no %s: the player picks from the wreck" % id)
	eq([c.fights_won, r["state"]], [1, "won"], "a win")
	eq(r["lines"], ["+%d credits" % dc], "the lines")


func test_captured_pays_one_and_a_half_times_the_credits_and_the_strip_scrap() -> void:
	var enemy := _enemy()
	for jumps in [0, 12]:
		var c := Campaign.new(1)
		c.jumps = jumps
		var ship := _ship()
		var before := ship.inventory.counts.duplicate()
		var r := c.fight_done({"state": "captured", "enemy": enemy}, ship)
		var t := c.tier()
		var dc: int = ship.inventory.count("credits") - int(before.get("credits", 0))
		check(dc >= roundi(20 * t * 1.5) and dc <= roundi(60 * t * 1.5), "credits x1.5 at tier %d (%d)" % [t, dc])
		eq(ship.inventory.count("scrap") - int(before.get("scrap", 0)), (20 + 6 * 8) * t, "the strip scrap at tier %d" % t)
		eq([c.fights_won, r["state"]], [1, "captured"], "it counts as a win")
		check(r["lines"].size() == 2 and r["lines"][1].begins_with("+%d scrap" % ((20 + 6 * 8) * t)), "the lines say what the crew stripped")


func test_spared_pays_the_offer_with_the_credits_times_the_tier() -> void:
	var c := Campaign.new(1)
	c.jumps = 12  # tier 2
	var ship := _ship()
	var before := ship.inventory.counts.duplicate()
	var r := c.fight_done({"state": "spared", "enemy": _enemy(), "offer": {"credits": 30, "fuel": 2, "scrap": 15}}, ship)
	eq(ship.inventory.count("credits"), int(before.get("credits", 0)) + 60, "credits x tier 2")
	eq(ship.inventory.count("fuel"), int(before.get("fuel", 0)) + 2, "fuel as offered")
	eq(ship.inventory.count("scrap"), int(before.get("scrap", 0)) + 15, "scrap as offered (only credits scale)")
	eq(r["text"], "They dump the goods out of the airlock and limp away.", "the text")
	eq(c.fights_won, 1, "it counts as a win")
	eq(r["state"], "spared", "state")
	var again := c.fight_done({"state": "spared"}, ship)
	eq(again["lines"], [], "no offer, no goods")


func test_escaped_pays_nothing_and_fled_and_lost_are_as_before() -> void:
	var c := Campaign.new(1)
	var ship := _ship()
	var before := ship.inventory.counts.duplicate()
	var r := c.fight_done({"state": "escaped", "enemy": _enemy()}, ship)
	eq(ship.inventory.counts, before, "the cargo is untouched")
	eq(r["text"], "They're gone, and whatever they carried went with them.", "the text")
	eq([r["state"], r["lines"], c.fights_won], ["escaped", [], 0], "no lines, no win")
	var fled := c.fight_done({"state": "fled"}, ship)
	eq([fled["state"], fled["text"], ship.inventory.counts, c.fights_won], ["fled", "You break away. The fight is not finished, but you are.", before, 0], "fled as before")
	var lost := c.fight_done({"state": "lost"}, ship)
	eq([lost["state"], lost["text"]], ["lost", "Your ship is wrecked. The Drift keeps what is left of it."], "lost as before")


func test_after_win_runs_for_a_capture_and_a_sparing_too() -> void:
	var after := {"text": "Their ledger floats by.", "effects": {"items": {"fuel": 2}}}
	for state in ["captured", "spared"]:
		var c := Campaign.new(1)
		var ship := _ship()
		var fuel := ship.inventory.count("fuel")
		var r := c.fight_done({"state": state, "enemy": _enemy()}, ship, after)
		eq(ship.inventory.count("fuel"), fuel + 2, state + ": the after_win effects ran")
		check(r["text"].ends_with("Their ledger floats by."), state + ": and its text is shown")


# --- the map ----------------------------------------------------------------------------------------------

## A stand-in for the combat view (as in test_drift.gd).
class FakeCombat extends Node:
	signal finished(result: Dictionary)
	var active := false

	func enter(_path := "") -> String:
		active = true
		return ""


func _screen() -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var fake := FakeCombat.new()
	var map := MapView.new()
	map.sim = sim
	map.combat = fake
	fake.finished.connect(map._on_fight_finished)
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = 5
	map.open()
	map.event_panel.size = map.size
	map.station_panel.size = map.size
	map.event_panel.close()
	return {"map": map, "sim": sim, "fake": fake}


func _fight(d: Dictionary, result: Dictionary) -> void:
	var map: MapView = d["map"]
	map.event_panel.open_event(map.campaign.events.get_event("repo_fight"))
	map.event_panel.choose(0)
	map.event_panel.proceed()
	d["fake"].finished.emit(result)


func test_the_map_shows_a_salvage_notice_then_the_pick_after_a_win_or_a_capture() -> void:
	for state in ["won", "captured"]:
		var d := _screen()
		var map: MapView = d["map"]
		_fight(d, {"state": state, "enemy": _enemy()})
		eq(map.event_panel.title, "Salvage", state + ": the notice is titled Salvage")
		map.event_panel.proceed()
		eq(map.event_panel.event.get("id", ""), "salvage", state + ": the pick follows")
		check(map.event_panel.view.size() >= 4, state + ": it has its rows (%d)" % map.event_panel.view.size())
		d["map"].free()
		d["sim"].free()
		d["fake"].free()


func test_the_map_offers_no_salvage_after_a_sparing_or_an_escape() -> void:
	for state in ["spared", "escaped"]:
		var d := _screen()
		var map: MapView = d["map"]
		_fight(d, {"state": state, "enemy": _enemy(), "offer": {"credits": 10}})
		eq(map.event_panel.title, "Salvage" if state == "spared" else "The fight is over", state + ": the notice title")
		map.event_panel.proceed()
		check(map.event_panel.event.get("id", "") != "salvage", state + ": no salvage pick")
		d["map"].free()
		d["sim"].free()
		d["fake"].free()
