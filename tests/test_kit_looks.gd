extends "res://tests/base_test.gd"
## Body gear you can see (scripts/crew/person_drawer.gd draw_gear, data/boarding.json `looks`).

const PersonDrawer = preload("res://scripts/crew/person_drawer.gd")
const Site = preload("res://scripts/board/site.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")


## A canvas that only counts what it is asked to draw.
class Counter extends RefCounted:
	var calls := 0
	var colors := []

	func draw_set_transform(_p, _r, _s) -> void:
		pass

	func draw_circle(_c, _r, col) -> void:
		calls += 1
		colors.append(col)

	func draw_arc(_c, _r, _a, _b, _n, _col, _w, _aa) -> void:
		calls += 1

	func draw_rect(_r, col, _fill := true, _w := -1.0) -> void:
		calls += 1
		colors.append(col)


func _count(item: String, over_head: bool) -> Counter:
	var c := Counter.new()
	PersonDrawer.draw_gear(c, Vector2.ZERO, 0.0, 1.0, item, over_head)
	return c


func test_every_body_has_a_look() -> void:
	for item in Site.config()["kit"]["bodies"]:
		var d := PersonDrawer.gear_look(str(item))
		check(not d.is_empty(), "%s has a look" % item)
		check(_count(str(item), false).calls > 0, "%s draws pieces under the head" % item)


func test_no_kit_draws_nothing() -> void:
	eq(_count("", false).calls, 0, "no gear, nothing drawn")
	eq(_count("", true).calls, 0, "no gear, nothing over the head")
	eq(_count("not_gear", false).calls, 0, "an unknown item draws nothing")
	var m := CrewMember.new("Rook", Vector2.ZERO, "human")
	eq(PersonDrawer.gear_of(m), "", "an unset kit wears nothing")
	m.kit = {"weapons": ["", ""], "body": "exosuit", "mods": ["", ""]}
	eq(PersonDrawer.gear_of(m), "exosuit", "the kit's body is what is drawn")


func test_the_looks_differ() -> void:
	var seen := {}
	for item in Site.config()["kit"]["bodies"]:
		var c := _count(str(item), false)
		var first: Color = c.colors[0]
		seen[str(item)] = "%s/%d" % [first.to_html(), c.calls]
	eq(seen.values().size(), Site.config()["kit"]["bodies"].size(), "five bodies")
	var uniq := {}
	for v in seen.values():
		uniq[v] = true
	eq(uniq.size(), seen.size(), "no two gear items look alike: %s" % str(seen))


func test_helmet_and_tones() -> void:
	check(_count("eva_suit", true).calls > 0, "the EVA suit has a clear helmet over the head")
	eq(_count("exosuit", true).calls, 0, "the exosuit has no helmet")
	eq(PersonDrawer.gear_look("salamander_suit")["color"], "#c4411f", "ember red")
