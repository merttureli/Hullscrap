extends "res://tests/base_test.gd"
## Small fixes found in the Beta 3 playthrough (docs/waves/playtest_2.md): text that overflowed.

const Fixture = preload("res://tests/fixture_ship.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const FrontDoor = preload("res://scripts/ui/front_door.gd")


func test_every_weapon_name_fits_its_slot() -> void:
	var ship := Fixture.room_ship()
	var font := ThemeDB.fallback_font
	var longest := 0
	for id in ship.components.ids():
		var def: Dictionary = ship.components.def(id)
		if str(def.get("family", "")) != "weapon":
			continue
		var shown := WeaponBar.fit_name(str(def["name"]))
		var w := font.get_string_size(shown["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(shown["size"])).x
		check(w <= WeaponBar.NAME_W + 0.5, "%s fits its slot: %s at %d is %.0f px" % [id, shown["text"], shown["size"], w])
		longest = maxi(longest, str(def["name"]).length())
	check(longest >= 20, "the longest name (a turret) was among them")
	eq(WeaponBar.fit_name("Pulse Mk1"), {"size": 14, "text": "Pulse Mk1"}, "a short name keeps its size")
	var turret := WeaponBar.fit_name("Concord Point Turret")
	eq(turret["text"], "Concord Point Turret", "a long name is not cut when a smaller size holds it")
	check(int(turret["size"]) < 14, "it just gets smaller")
	var huge := WeaponBar.fit_name("The Extremely Long Named Weapon")
	check(str(huge["text"]).ends_with("…"), "one that cannot fit at the smallest size gets an ellipsis")


func test_two_markers_close_on_an_edge_keep_their_labels_apart() -> void:
	var vp := Vector2(1600.0, 900.0)
	var taken: Array = []
	var first := SectorView.place_label(Vector2(700.0, 860.0), 150.0, vp, taken)
	taken.append(Rect2(first + Vector2(0.0, -12.0), Vector2(150.0, 16.0)))
	var second := SectorView.place_label(Vector2(740.0, 860.0), 150.0, vp, taken)
	var box := Rect2(second + Vector2(0.0, -12.0), Vector2(150.0, 16.0))
	check(not taken[0].intersects(box), "the second label does not print over the first: %s then %s" % [str(first), str(second)])
	check(second != first and second.y <= vp.y - 4.0, "and it stays on the screen")
	eq(SectorView.place_label(Vector2(100.0, 100.0), 80.0, vp, []), Vector2(60.0, 100.0 + SectorView.ICON * 0.5 + 14.0), "alone, a label sits under its icon")


func test_the_hint_toast_stays_clear_of_the_maps_header() -> void:
	eq(FrontDoor.toast_top(false, false), 48.0, "in play it sits under the top bar")
	eq(FrontDoor.toast_top(true, false), 62.0, "in a fight under the key hints")
	check(FrontDoor.toast_top(false, true) > 90.0, "over the map it drops below the header line (y 70 to 90)")
