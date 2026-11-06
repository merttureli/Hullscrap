extends "res://tests/base_test.gd"
## The four fire groups (docs/GUNS.md 6): LMB, RMB, Q and AUTO. Dragging a gun's weapon bar slot to another section, the right-click cycle,
## Q firing group 3 and E the utility, a fixed gun in AUTO firing only when it bears, a turret in a manual group holding fire until its
## button, the save (components version 8) and the older saves.

const Session = preload("res://scripts/combat/combat_session.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const Components = preload("res://scripts/ship/components.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const PIRATE := "res://data/ships/pirate_raider.json"


func _session(foe := Vector2(0.0, -450.0)) -> Session:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 3, {"enemy_pos": foe})
	return s


func _uid(s: Session, id: String) -> int:
	return s.weapons().filter(func(w): return w["id"] == id)[0]["uid"]


func _group(s: Session, uid: int) -> int:
	return s.weapons().filter(func(w): return w["uid"] == uid)[0]["group"]


func _comps(s: Session) -> Components:
	return s.arena.ships[Session.PLAYER].ship.components


func _bar(s: Session) -> WeaponBar:
	var bar := WeaponBar.new()
	bar.bind(s, func() -> Vector2: return Vector2.ZERO, GunBadges.new())
	bar.size = Vector2(bar.layout()["width"] + 200.0, 400.0)
	return bar


## The bar-local centre of gun `uid`'s slot, and of the section of fire group `g`.
func _slot_pt(bar: WeaponBar, uid: int) -> Vector2:
	var lay := bar.layout()
	for sl in lay["slots"]:
		if sl["w"]["uid"] == uid:
			return sl["rect"].get_center() + bar._base(lay)
	return Vector2(-1.0, -1.0)


func _zone_pt(bar: WeaponBar, g: int) -> Vector2:
	var lay := bar.layout()
	for z in lay["zones"]:
		if z["group"] == g:
			return z["rect"].get_center() + bar._base(lay)
	return Vector2(-1.0, -1.0)


## Run `secs` seconds in small steps (Session.tick keeps only a few substeps of a long one).
func _run(s: Session, secs: float) -> void:
	for i in int(secs / 0.1):
		s.tick(0.1)


## The player's shots from gun `uid` so far.
func _shots(s: Session, uid: int) -> int:
	return s.arena.events.filter(func(e): return e["type"] == "shot" and e["ship"] == Session.PLAYER and e["uid"] == uid).size()


func test_defaults_fixed_guns_by_kind_and_turrets_auto() -> void:
	var w := _session().arena.weapons
	eq([w.group_of("laser_mk1"), w.group_of("test_missile"), w.group_of("rattle_burst_scrap"), w.group_of("laser_turret_mk1")], [1, 2, 0, 0], "lasers LMB, missiles RMB, turrets AUTO")
	eq([w.group_of("laser_mk1", 3), w.group_of("rattle_burst_scrap", 2), w.group_of("test_missile", 0)], [3, 2, 0], "a choice wins, for any gun")
	eq(w.group_of("laser_mk1", -1), 1, "-1 is no choice")


func test_a_drag_moves_a_gun_through_all_four_groups() -> void:
	var s := _session()
	var bar := _bar(s)
	var laser := _uid(s, "laser_mk1")
	eq(bar.layout()["zones"].size(), 4, "four sections")
	for g in [2, 3, 0, 1, 0, 3]:
		var from := _slot_pt(bar, laser)
		check(bar.grab(from, MOUSE_BUTTON_LEFT), "the press on the slot takes it")
		check(bar.motion(from + Vector2(2.0, 0.0)) and not bar.drag["moved"], "a small wobble is not a drag yet")
		bar.motion(from + Vector2(40.0, -10.0))
		check(bar.drag["moved"], "a real move is a drag")
		bar.motion(_zone_pt(bar, g))
		eq(bar.group_at(bar.drag["at"]), g, "the section under the mouse (it lights)")
		eq(bar.release(_zone_pt(bar, g)), g, "dropped in %d" % g)
		eq(_group(s, laser), g, "the session fires it with group %d" % g)
		eq(bar.drag, {}, "nothing in hand")
		eq(_comps(s).group_choice(laser), -1 if g == 1 else g, "the mount keeps the choice (the default as none)")
	check(bar.grab(_slot_pt(bar, laser), MOUSE_BUTTON_LEFT), "again")
	eq(bar.release(_slot_pt(bar, laser)), -1, "let go where it was: nothing moves")
	check(not bar.grab(Vector2(5000.0, 5000.0), MOUSE_BUTTON_LEFT), "a press away from a slot takes nothing")
	check(not bar.grab(_slot_pt(bar, laser), MOUSE_BUTTON_RIGHT), "only the left button drags")


func test_a_drop_off_the_sections_changes_nothing() -> void:
	var s := _session()
	var bar := _bar(s)
	var uid := _uid(s, "laser_mk1")
	bar.grab(_slot_pt(bar, uid), MOUSE_BUTTON_LEFT)
	bar.motion(Vector2(3000.0, 3000.0))
	eq(bar.release(Vector2(3000.0, 3000.0)), -1, "dropped far away")
	eq(_group(s, uid), 1, "still LMB")


func test_a_turret_can_be_dragged_into_a_manual_group_and_back() -> void:
	var s := _session()
	var bar := _bar(s)
	var t := _uid(s, "rattle_burst_scrap")
	bar.grab(_slot_pt(bar, t), MOUSE_BUTTON_LEFT)
	bar.motion(_zone_pt(bar, 3))
	eq(bar.release(_zone_pt(bar, 3)), 3, "into Q")
	eq(GunBadges.style(s.weapons().filter(func(w): return w["uid"] == t)[0])["key"], "3", "its chip is the Q one")
	bar.grab(_slot_pt(bar, t), MOUSE_BUTTON_LEFT)
	bar.motion(_zone_pt(bar, 0))
	eq(bar.release(_zone_pt(bar, 0)), 0, "back to AUTO")
	eq(_comps(s).group_choice(t), -1, "which is its default: no stored choice")


func test_right_click_cycles_lmb_rmb_q_auto() -> void:
	var s := _session()
	var bar := _bar(s)
	var uid := _uid(s, "laser_mk1")
	var seen := []
	for i in 5:
		check(bar.click(_slot_pt(bar, uid), MOUSE_BUTTON_RIGHT), "the click is used up")
		seen.append(_group(s, uid))
	eq(seen, [2, 3, 0, 1, 2], "LMB -> RMB -> Q -> AUTO -> LMB -> RMB")
	check(not bar.click(_slot_pt(bar, uid), MOUSE_BUTTON_LEFT), "a left click is not the cycle")


func test_q_fires_group_3_and_e_is_the_utility() -> void:
	var s := _session()
	var uid := _uid(s, "laser_mk1")
	var aim: Vector2 = s.arena.ships[Session.ENEMY].flight.pos
	GunBadges.assign(_comps(s), s.arena.weapons, uid, 3)
	eq(s.fire_group(1, aim), 0, "LMB no longer fires it")
	eq(s.fire_group(3, aim), 1, "Q fires it")
	check(not WeaponBar.KEY_OF.has(KEY_Q), "Q is not an ability key")
	eq(WeaponBar.KEY_OF[KEY_E], "utility", "E is the utility ability")
	eq(WeaponBar.KEY_LABEL["utility"], "E", "and the slot says so")
	var b := GunBadges.new()
	b.held[3] = true
	eq(s.weapons().map(func(w): return b.outlined(w)), [true, false], "Q held outlines its guns only")


func test_a_fixed_gun_in_auto_fires_only_when_it_bears() -> void:
	var s := _session()
	var uid := _uid(s, "laser_mk1")
	GunBadges.assign(_comps(s), s.arena.weapons, uid, 0)
	_run(s, 3.0)
	check(_shots(s, uid) >= 1, "the foe ahead is in its cone and its range: it fires by itself")
	var side := _session(Vector2(600.0, 0.0))
	var uid2 := _uid(side, "laser_mk1")
	GunBadges.assign(_comps(side), side.arena.weapons, uid2, 0)
	_run(side, 3.0)
	eq(_shots(side, uid2), 0, "the foe abeam is outside its gimbal: it holds fire")
	var far := _session(Vector2(0.0, -2500.0))
	GunBadges.assign(_comps(far), far.arena.weapons, _uid(far, "laser_mk1"), 0)
	_run(far, 2.0)
	eq(_shots(far, _uid(far, "laser_mk1")), 0, "out of range: it holds fire")
	var held := _session()
	GunBadges.assign(_comps(held), held.arena.weapons, _uid(held, "laser_mk1"), 0)
	held.arena.autofire[Session.PLAYER] = false
	_run(held, 3.0)
	eq(_shots(held, _uid(held, "laser_mk1")), 0, "T holds AUTO fixed guns too")
	var plain := _session()
	_run(plain, 3.0)
	eq(_shots(plain, _uid(plain, "laser_mk1")), 0, "a fixed gun in LMB does not fire by itself")


func test_a_turret_in_a_manual_group_holds_fire_until_its_button() -> void:
	var s := _session()
	var t := _uid(s, "rattle_burst_scrap")
	var base := _session()
	_run(base, 3.0)
	check(_shots(base, _uid(base, "rattle_burst_scrap")) >= 1, "(an AUTO turret fires on its own)")
	GunBadges.assign(_comps(s), s.arena.weapons, t, 1)
	_run(s, 3.0)
	eq(_shots(s, t), 0, "in LMB it holds fire")
	var aim: Vector2 = s.arena.ships[Session.ENEMY].flight.pos
	check(s.fire_group(1, aim) >= 1, "LMB held: it tracks and fires")
	check(_shots(s, t) >= 1, "a shot was made")
	GunBadges.assign(_comps(s), s.arena.weapons, t, 3)
	s.arena.ships[Session.PLAYER].cooldowns.clear()
	var before := _shots(s, t)
	_run(s, 2.0)
	eq(_shots(s, t), before, "in Q it holds fire too")
	check(s.fire_group(3, aim) >= 1 and _shots(s, t) == before + 1, "Q held: it fires")


func test_the_choice_survives_a_save_in_every_group() -> void:
	var s := _session()
	var comps := _comps(s)
	var laser := _uid(s, "laser_mk1")
	var turret := _uid(s, "rattle_burst_scrap")
	for g in [0, 1, 2, 3]:
		comps.set_group_choice(laser, g)
		comps.set_group_choice(turret, 3 - g)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(comps.to_dict()))
		eq(int(saved["version"]), Components.VERSION, "saved at the current version")
		var back := Components.new()
		back.load_defs(Ship.COMPONENTS_PATH)
		eq(back.load_dict(saved), "", "loads")
		eq([back.group_choice(laser), back.group_choice(turret)], [g, 3 - g], "group %d (AUTO is 0) came back" % g)
	comps.set_group_choice(laser, -1)
	check(not comps.to_dict()["instances"].any(func(r): return r["uid"] == laser and r.has("group")), "no choice stores nothing")
	check(Components.VERSION >= 8, "the version moved on from 7")


func test_older_saves_load_with_their_choice_or_the_defaults() -> void:
	var s := _session()
	var comps := _comps(s)
	var laser := _uid(s, "laser_mk1")
	var old: Dictionary = JSON.parse_string(JSON.stringify(comps.to_dict()))
	old["version"] = 7
	for r in old["instances"]:
		if r["uid"] == laser:
			r["group"] = 2  # what a version 7 save holds
	var back := Components.new()
	back.load_defs(Ship.COMPONENTS_PATH)
	eq(back.load_dict(old), "", "a version 7 save loads")
	eq(back.group_choice(laser), 2, "its RMB choice is kept")
	for uid in back.instances:
		if uid != laser:
			eq(back.group_choice(uid), -1, "the rest take the defaults")
	old["version"] = 6
	for r in old["instances"]:
		r.erase("group")
	var back6 := Components.new()
	back6.load_defs(Ship.COMPONENTS_PATH)
	eq(back6.load_dict(old), "", "a version 6 save loads")
	eq(back6.group_choice(laser), -1, "and has no choices")
