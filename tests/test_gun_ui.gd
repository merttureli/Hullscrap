extends "res://tests/base_test.gd"
## Seeing which gun is which (docs/GUNS.md 7): the chips and their groups, the held group's outline, the right-click group choice and
## its save, the hover link between a weapon bar slot and the gun, the flash, and the chain and charge pips (with a stub).

const Session = preload("res://scripts/combat/combat_session.gd")
const GunBadges = preload("res://scripts/ui/gun_badges.gd")
const WeaponBar = preload("res://scripts/ui/weapon_bar.gd")
const Components = preload("res://scripts/ship/components.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const PIRATE := "res://data/ships/pirate_raider.json"


class StubWeapons extends RefCounted:
	func def(_id: String) -> Dictionary:
		return {}
	func chain_max(_d: Dictionary) -> int:
		return 3
	func chain_steps(_a, _i: int, _u: int) -> int:
		return 2
	func charge_max(_d: Dictionary) -> int:
		return 3
	func charges(_a, _i: int, _u: int) -> int:
		return 1


class StubArena extends RefCounted:
	var weapons := StubWeapons.new()


class StubSession extends RefCounted:
	const PLAYER := 0
	var arena := StubArena.new()


func _session() -> Session:
	var s := Session.new()
	s.start(Session.load_ship(PIRATE), Session.load_ship(PIRATE), 3)
	s.arena.add_mount(Session.PLAYER, "test_missile", Vector2(31.0, 28.0))
	return s


func test_every_gun_has_a_chip_with_its_key_and_group() -> void:
	var s := _session()
	var list := s.weapons()
	eq(list.size(), 3, "laser, rattle turret and the added missile")
	var keys := []
	for i in list.size():
		keys.append([GunBadges.key_of(i), GunBadges.style(list[i])["key"]])
	eq(keys, [[1, "1"], [2, "auto"], [3, "2"]], "a laser is LMB, a turret auto, a missile RMB; keys 1-3")
	var marks := list.map(func(w): return GunBadges.style(w)["mark"])
	eq(marks, ["dot", "arc", "ring"], "dot, arc and ring differ without colour")
	eq(GunBadges.key_of(9), 0, "no key past 9")
	eq(list.map(func(w): return GunBadges.bar_group(w)), [1, 3, 2], "the bar groups")


func test_holding_a_group_outlines_exactly_that_group() -> void:
	var s := _session()
	var b := GunBadges.new()
	b.held[1] = true
	eq(s.weapons().map(func(w): return b.outlined(w)), [true, false, false], "LMB held: the laser only, not the turret or the missile")
	b.held = {1: false, 2: true}
	eq(s.weapons().map(func(w): return b.outlined(w)), [false, false, true], "RMB held: the missile only")


func test_the_group_choice_cycles_and_survives_a_save() -> void:
	var s := _session()
	var co = s.arena.ships[Session.PLAYER]
	var comps: Components = co.ship.components
	var w := s.arena.weapons
	var laser: int = s.weapons()[0]["uid"]
	var turret: int = s.weapons()[1]["uid"]
	eq(GunBadges.cycle(comps, w, laser), 2, "a click moves the laser to RMB")
	eq(s.weapons()[0]["group"], 2, "and the session fires it with RMB")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(comps.to_dict()))
	eq(int(saved["version"]), Components.VERSION, "saved at the current version")
	var back := Components.new()
	back.load_defs(Ship.COMPONENTS_PATH)
	eq(back.load_dict(saved), "", "loads")
	eq(back.group_choice(laser), 2, "the choice came back")
	eq(GunBadges.cycle(comps, w, laser), 1, "another click: back to LMB")
	check(not comps.to_dict()["instances"].any(func(r): return r.has("group")), "the default is stored as no choice")
	eq(GunBadges.cycle(comps, w, turret), 0, "a turret stays auto")
	eq(s.weapons()[1]["group"], w.group_of("rattle_burst_scrap"), "its group is untouched")


func test_an_old_save_loads_with_the_default_groups() -> void:
	var s := _session()
	var comps: Components = s.arena.ships[Session.PLAYER].ship.components
	var old: Dictionary = JSON.parse_string(JSON.stringify(comps.to_dict()))
	old["version"] = 6
	var back := Components.new()
	back.load_defs(Ship.COMPONENTS_PATH)
	eq(back.load_dict(old), "", "a version 6 save loads")
	for uid in back.instances:
		eq(back.group_choice(uid), 0, "no choice: the kind's default")


func test_hover_links_the_slot_and_the_gun() -> void:
	var s := _session()
	var b := GunBadges.new()
	var bar := WeaponBar.new()
	bar.bind(s, func() -> Vector2: return Vector2.ZERO, b)
	var lay := bar.layout()
	eq(lay["slots"].map(func(x): return x["w"]["id"]), ["laser_mk1", "test_missile", "rattle_burst_scrap"], "the bar is grouped LMB, RMB, auto")
	eq(lay["heads"].map(func(h): return h["group"]), [1, 2, 3], "each group has its header")
	bar.size = Vector2(lay["width"], 400.0)
	var sl: Dictionary = lay["slots"][2]
	eq(bar.slot_at(sl["rect"].get_center())["w"]["uid"], sl["w"]["uid"], "the point on a slot finds it")
	b.bar_hover = sl["w"]["uid"]
	eq(b.hover_uid(), sl["w"]["uid"], "the slot lights its gun")
	b.bar_hover = -1
	var co = s.arena.ships[Session.PLAYER]
	var uid: int = s.weapons()[0]["uid"]
	var at := GunBadges.chip_world(s.arena, Session.PLAYER, uid, co.mounts[uid])
	b.world_hover = b.gun_at(s, at, 0.5)
	eq(b.world_hover, uid, "the mouse on a gun's chip finds the gun")
	eq(b.hover_uid(), uid, "and lights its slot")
	eq(b.gun_at(s, at + Vector2(5000.0, 0.0), 0.5), -1, "far from any gun: none")
	# a right-click on a slot cycles that gun
	var laser_slot: Dictionary = lay["slots"][0]
	check(bar.click(laser_slot["rect"].get_center() + Vector2((bar.size.x - lay["width"]) / 2.0, 0.0), MOUSE_BUTTON_RIGHT), "the click is used up")
	eq(s.weapons().filter(func(w): return w["id"] == "laser_mk1")[0]["group"], 2, "the laser moved to RMB")


func test_a_shot_flashes_the_chip() -> void:
	var b := GunBadges.new()
	eq(b.flash_of(7), 0.0, "quiet")
	b.on_fire(7)
	check(b.flash_of(7) > 0.9, "lit at the shot")
	eq(b.flash_of(8), 0.0, "other guns stay dark")


func test_pips_read_the_chain_and_charge_accessors() -> void:
	var p := WeaponBar.pips_of(StubSession.new(), {"id": "x", "uid": 1})
	eq(p, {"chain": [2, 3], "charge": [1, 3]}, "steps and stored charges from the accessors")
	var none := WeaponBar.pips_of(_session(), {"id": "laser_mk1", "uid": 1})
	check(none["chain"][1] >= 0 and none["charge"][1] >= 0, "a plain gun reads without error")
