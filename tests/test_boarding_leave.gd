extends "res://tests/base_test.gd"
## The Leave button (L) aboard another vessel: back to the ship with a click when no foe has hunted the party for leave_quiet_s, after a fade, by leave()'s own path.

const Boarding = preload("res://scripts/board/boarding.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const Site = preload("res://scripts/board/site.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Campaign = preload("res://scripts/space/campaign.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Rook", Vector2(10, 10), "human"))
	s.crew.append(CrewMember.new("Tess", Vector2(12, 10), "fenn"))
	s.inventory.add("hand_ammo", 40 - s.inventory.count("hand_ammo"))
	return s


## A view aboard an empty station (no foes), with `party` crew along; `camp` gives it a sector to remember the visit.
func _view(party := 0, camp = null):
	var sh := _ship()
	var sector = camp.current_sector() if camp != null else null
	var s = Boarding.start(camp, sector, "pz", {"kind": "station"}, sh)
	s.site = Site.make(31, "station", {"faction": "clans"})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	s.foes.list.clear()
	if party > 0:
		s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, party))
	var b := BoardView.new()
	b.ask_party = false
	b.enter(s)
	return b


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _step(b, seconds: float, dt := 0.05) -> void:
	for i in int(seconds / dt):
		if not b.active:
			return
		b.step(dt)


func _hunter(b) -> Dictionary:
	var s = b.session
	var f: Dictionary = s.foes.add("pirate", s.soldier.pos + Vector2(20.0, 0.0), -1)
	f["mode"] = "hunt"
	return f


func test_leave_works_when_unseen_after_the_fade() -> void:
	var b = _view()
	var s = b.session
	eq(b.quick_leave(), "", "the button starts")
	check(b._go_t >= 0.0 and b.active, "the fade runs, still aboard")
	_step(b, float(Arms.cfg()["leave_fade_s"]) - 0.3)
	check(b.active, "still aboard before the fade ends")
	_step(b, 0.6)
	check(not b.active and s.finished, "back on the ship after the fade, by leave()")


func test_the_key_leaves_too() -> void:
	var b = _view()
	b._unhandled_input(_key(KEY_L))
	check(b._go_t >= 0.0, "L starts it")
	b.leave()


func test_leave_is_refused_while_hunted_and_after_until_quiet() -> void:
	var b = _view()
	var s = b.session
	var f := _hunter(b)
	_step(b, 0.2)
	check(not s.can_quick_leave(), "a hunting foe refuses it")
	check(b.quick_leave() != "" and b._go_t < 0.0, "the button says why and does not start")
	eq(b.quick_leave(), str(Arms.cfg()["leave_hunted"]), "Not while they hunt you")
	s.foes.list.erase(f)
	_step(b, float(Arms.cfg()["leave_quiet_s"]) - 2.0)
	check(not s.can_quick_leave(), "still too soon after the foe lost them")
	_step(b, 3.0)
	check(s.can_quick_leave(), "quiet for leave_quiet_s: it works")
	b.leave()


func test_the_airlock_still_leaves_while_hunted() -> void:
	var b = _view()
	_hunter(b)
	_step(b, 0.2)
	b.target = {"type": "airlock"}
	b.press_e()
	check(not b.active, "E at the airlock leaves at any time")


func test_a_downed_follower_asks_first() -> void:
	var b = _view(1)
	var s = b.session
	var name: String = str(s.party[0]["src"].name)
	s.party[0]["m"].hp = 0.0
	eq(b.quick_leave(), "", "the click asks")
	check(b._ask_leave and b._go_t < 0.0, "a question stands, nothing started")
	check(b.leave_question().begins_with("Leave %s behind?" % name), "it names them: %s" % b.leave_question())
	b._unhandled_input(_key(KEY_ESCAPE))
	check(not b._ask_leave and b._go_t < 0.0 and b.active, "Esc cancels")
	b.quick_leave()
	b._unhandled_input(_key(KEY_ENTER))
	check(not b._ask_leave and b._go_t >= 0.0, "Enter confirms: the fade starts")
	_step(b, 2.0)
	check(not b.active, "and they go")
	check(not s.ship.crew.any(func(m): return m.name == name), "the follower who was down is lost, as today")


func test_the_sites_memory_survives_a_leave() -> void:
	var camp := Campaign.new(5)
	var b = _view(0, camp)
	var s = b.session
	var ids: Array = s.site.containers()
	s.open(ids[0])
	b.quick_leave()
	_step(b, 2.0)
	check(not b.active, "gone")
	var mem: Dictionary = camp.current_sector().boarded["pz"]
	check(mem["opened"].has(ids[0]), "the opened container is remembered")
	check(not bool(mem["cleared"]), "and the site is not closed: you can come back")
