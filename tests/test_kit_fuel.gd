extends "res://tests/base_test.gd"
## Fuel (Beta 4.1): the numbers the fuel table of the progression bot was measured with (tests/tool_progress.gd, stages 1 to 3, report section "Fuel"), pinned, and the
## ledger that books where every unit of fuel came from and went. A change to one of these numbers has to be measured again (the table is in the report of the track `kit`).

const Progress = preload("res://tests/tool_progress.gd")
const Content = preload("res://scripts/data/content.gd")


func test_the_fuel_numbers_the_table_was_measured_with() -> void:
	var fuel: Dictionary = Content.read("res://data/drift.json")["fuel"]
	eq(int(fuel["start"]), 22, "a run starts with 22 fuel")
	eq(fuel["stock"].map(func(v): return int(v)), [6, 10], "a fuel visit has 6 to 10 units on sale")
	eq(int(fuel["price"]), 14, "at 14 credits a unit")
	var canister := {}
	for t in Content.read("res://data/debris.json")["types"]:
		if str(t["id"]) == "fuel_canister":
			canister = t
	eq(float(canister["weight"]), 1.0, "a fuel canister weighs 1 in the debris")
	eq(int(canister["yield"]["fuel"]), 1, "and holds 1 fuel")
	var extra: Array = Content.read("res://data/morale.json")["offer"]["extra"]
	eq(extra.filter(func(e): return e["item"] == "fuel")[0]["count"].map(func(v): return int(v)), [1, 2], "a surrender may offer 1 to 2 fuel")


func test_the_ledger_books_fuel_by_where_it_came_from_and_went() -> void:
	var led := Progress.FuelLedger.new()
	led.add("fuel", 5)  # (before any tag: "other")
	led.tag = "debris"
	led.add("fuel", 1)
	led.add("scrap", 40)  # (only fuel is booked)
	led.tag = "jump"
	led.add("fuel", -2)
	led.tag = "event:ada_hears_loop"
	led.add("fuel", 3)
	led.tag = "jump"
	led.add("fuel", -10)  # (a count never drops below 0: only the 7 that were there go)
	eq(led.by["other"], [5, 0], "the start")
	eq(led.by["debris"], [1, 0], "a canister")
	eq(led.by["event:ada_hears_loop"], [3, 0], "an event, by its id")
	eq(led.by["jump"], [0, 9], "the jumps, what really left")
	eq(led.count("fuel"), 0, "and the hold agrees")
	check(not led.by.has("scrap"), "nothing but fuel is booked")
