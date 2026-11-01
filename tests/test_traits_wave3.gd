extends "res://tests/base_test.gd"
## The trait keys race wave 3 needs (docs/waves/races_2_4.md; scripts/crew/traits.gd): revive_once, line_affinity,
## split_on_death, counter_melee, no_suit and vacuum_speed, one test each through the system it changes, plus the two
## races that need no new key (the Choir's aura work_mult; Sable's work_mult breach and ranged_mult), the merge rules and
## the validators. Traits the data has no use for yet are made up in the library for the test (`_trait`) and removed again.

const Fixture = preload("res://tests/fixture_ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const TestContent = preload("res://tests/test_content.gd")

const STEP := 0.1


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _trait(id: String, bag: Dictionary) -> void:
	var e := {"name": id}
	e.merge(bag)
	TraitSet.library()[id] = e


func _done() -> void:
	TraitSet.reset()


## A person on the body anchor (x, y), with the made-up traits `ids` worn (read again: gear does not change the body later).
func _person(p_name: String, x: int, y: int, ids: Array = [], player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))
	m.gear_traits = ids
	m.set_species("human")
	m.pos = Pathfinder.centre_of(Vector2i(x, y), m.body_size)
	m.is_player = player
	return m


func _run(ship: Ship, jobs: Jobs, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		jobs.tick(ship, STEP)
		t += STEP


## Tick the bleeding `seconds` in steps of 1 s; returns the chronicle lines of the whole span.
func _bleed(ship: Ship, seconds: int) -> Array:
	var lines := []
	for i in seconds:
		lines.append_array(Mortality.tick(ship, 1.0))
	return lines


func _named(ship: Ship, who: String):
	for m in ship.crew:
		if m.name == who:
			return m
	return null


## The sealed room of the fixture ship plus a second one under it (y 19..25), full of air.
func _two_rooms() -> Ship:
	var ship := Fixture.room_ship()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0
	return ship


# --- revive_once ---------------------------------------------------------------------------------------

func test_revive_once_stands_the_first_downing_up_after_the_wait_and_only_that_one() -> void:
	_trait("t_dead", {"revive_once": {"after": 10, "hp": 50}})
	var ship := Fixture.room_ship()
	var rev := _person("Rev", 18, 12, ["t_dead"])
	var plain := _person("Plain", 11, 12)
	ship.crew.append_array([rev, plain])
	rev.hurt(1000.0)
	plain.hurt(1000.0)
	var lines := _bleed(ship, 9)
	eq(lines, [], "nothing in 9 s")
	check(rev.is_down(), "still down at 9 s")
	near(rev.down_t, 0.0, "and the bleeding does not count meanwhile")
	lines = _bleed(ship, 1)
	eq(lines, ["Rev rises again."], "at 10 s the chronicle line")
	check(not rev.is_down(), "up")
	near(rev.hp, 50.0, "at the trait's hp")
	check(rev.revived, "and the one revive is spent")
	_bleed(ship, 35)  # 45 s in all: the plain one is dead
	check(not ship.crew.has(plain) and ship.dead_crew == ["Plain"], "a crew member without the trait bleeds out as ever")
	check(ship.crew.has(rev), "the reviver is still aboard")
	# The second time they are down they bleed like anyone.
	rev.hurt(1000.0)
	eq(_bleed(ship, 44), [], "no revive the second time: 44 s")
	near(rev.down_t, 44.0, "the bleeding counts now")
	eq(_bleed(ship, 1), ["Rev has died."], "and they die at 45 s")
	_done()


func test_revive_once_hp_is_capped_at_the_max_and_the_crew_do_not_come_for_a_pending_revive() -> void:
	_trait("t_dead", {"revive_once": {"after": 5, "hp": 5000}})
	var ship := Fixture.room_ship()
	var rev := _person("Rev", 18, 12, ["t_dead"])
	var mate := _person("Mate", 11, 12)
	ship.crew.append_array([rev, mate])
	rev.hurt(1000.0)
	Mortality.tick(ship, 1.0)  # armed
	var jobs := Jobs.new()
	jobs.build_board(ship)
	check(not jobs.board.has("revive:Rev"), "no revive job on the board while the revive is pending")
	_bleed(ship, 4)
	near(rev.hp, rev.max_hp, "a huge hp is capped at their max hp")
	jobs.build_board(ship)
	check(not jobs.board.has("revive:Rev"), "up, so no job either")
	rev.hurt(1000.0)
	Mortality.tick(ship, 1.0)
	jobs.build_board(ship)
	check(jobs.board.has("revive:Rev"), "the second downing has the usual job: the revive is spent")
	_done()


func test_revive_once_picked_up_first_is_spent_all_the_same() -> void:
	_trait("t_dead", {"revive_once": {"after": 10, "hp": 50}})
	var ship := Fixture.room_ship()
	var rev := _person("Rev", 18, 12, ["t_dead"])
	ship.crew.append(rev)
	rev.hurt(1000.0)
	_bleed(ship, 3)
	rev.heal(20.0)  # a medbay or a crewmate got there first
	_bleed(ship, 1)
	check(rev.revived and rev.revive_t < 0.0, "spent, and nothing is pending any more")
	near(rev.hp, 20.0, "they keep the hp they were given")
	_bleed(ship, 20)
	near(rev.hp, 20.0, "nothing lifts them later")
	rev.hurt(1000.0)
	eq(_bleed(ship, 45), ["Rev has died."], "the next downing is a real one")
	_done()


# --- line_affinity -------------------------------------------------------------------------------------

func test_line_affinity_speeds_up_repairs_and_posts_of_that_line_only() -> void:
	_trait("t_rat", {"line_affinity": {"scrap": 2.0}})
	var ship := Fixture.room_ship()
	var scrap := Fixture.put(ship, "engine_scrap_mk1", 10, 10)
	var std := Fixture.put(ship, "engine_mk1", 10, 14)
	check(scrap >= 0 and std >= 0, "both parts fit")
	var rat := _person("Rat", 14, 10, ["t_rat"], true)
	var plain := _person("Plain", 14, 10, [], true)
	eq(TraitSet.part_line(ship, scrap), "scrap", "the line of a part")
	eq(TraitSet.part_line(ship, std), "standard", "a part with no line is standard")
	eq(TraitSet.part_line(ship, 999), "", "no such part: no line")
	ship.crew.append_array([rat, plain])
	near(Jobs._work_rate(ship, rat, "repair_component", "scrap"), 2.0, "a Rattler repairs a scrap part twice as fast")
	near(Jobs._work_rate(ship, rat, "repair_component", "standard"), 1.0, "a standard one at the usual speed")
	near(Jobs._work_rate(ship, rat, "repair_component"), 1.0, "and no part at all too")
	near(Jobs._work_rate(ship, plain, "repair_component", "scrap"), 1.0, "a plain crew member has no affinity")
	# Through the job: the same broken scrap engine is mended in half the time.
	var took := {}
	for who in [rat, plain]:
		var s := Fixture.room_ship()
		var uid := Fixture.put(s, "engine_scrap_mk1", 10, 10)
		s.components.instances[uid]["status"] = "disabled"
		var person := _person("Worker", 12, 10, ["t_rat"] if who == rat else [])
		s.crew.append(person)
		var jobs := Jobs.new()
		var n := 0
		while s.components.instances[uid]["status"] != "ok" and n < 400:
			jobs.tick(s, STEP)
			n += 1
		took[who.name] = n
	check(took["Rat"] > 0 and took["Plain"] > 0 and took["Plain"] < 400, "both finished: %s" % str(took))
	check(absi(took["Plain"] - 2 * took["Rat"]) <= 2, "the Rattler took half the time: %s" % str(took))
	# Manning: a scrap weapon is worth twice as much to them.
	var gun := Fixture.put(ship, "rattle_burst_scrap", 14, 14)
	var laser := Fixture.put(ship, "laser_mk1", 10, 12)
	check(gun >= 0 and laser >= 0, "the guns fit")
	ship.manned[gun] = "Rat"
	near(TraitSet.manned_factor(ship, gun), 2.0, "manning a scrap weapon: x2")
	ship.manned.erase(gun)
	ship.manned[laser] = "Rat"
	near(TraitSet.manned_factor(ship, laser), 1.0, "a standard one: x1")
	ship.manned.erase(laser)
	ship.manned[gun] = "Plain"
	near(TraitSet.manned_factor(ship, gun), 1.0, "someone else on the scrap weapon: x1")
	_done()


# --- split_on_death ------------------------------------------------------------------------------------

func _tess(ship: Ship, p_name := "Tess", x := 11, y := 12) -> CrewMember:
	_trait("t_swarm", {"split_on_death": {"reform_s": 30}})
	var m := _person(p_name, x, y, ["t_swarm"])
	ship.crew.append(m)
	return m


func test_split_on_death_makes_two_small_halves_that_merge_back_at_their_summed_hp() -> void:
	var ship := Fixture.room_ship()
	var tess := _tess(ship)
	var full := tess.max_hp
	tess.hurt(1000.0)
	eq(_bleed(ship, 44), [], "bleeding for 44 s")
	var lines := _bleed(ship, 1)
	eq(lines, ["Tess splits in two."], "at 45 s they split instead of dying")
	eq(ship.crew.size(), 2, "two bodies")
	var b = _named(ship, "Tess b")
	check(b != null, "the other half is 'Tess b'")
	check(ship.dead_crew.is_empty(), "nobody died")
	for h in [tess, b]:
		eq(h.body_size, 1, "%s: a small 1x1 body" % h.name)
		eq(h.body_cells().size(), 1, "%s: on one cell" % h.name)
		near(h.max_hp, full / 2.0, "%s: half the max hp" % h.name)
		near(h.hp, full / 2.0, "%s: and full" % h.name)
		check(h.is_half and not h.is_down(), "%s: a half, and up" % h.name)
		check(h.fits(ship.grid, h.pos), "%s: stands where a small body fits" % h.name)
	check(tess.body_cells()[0] != b.body_cells()[0], "on two different cells")
	eq(tess.species, b.species, "of the same species")
	# They hurt separately, then merge after reform_s from the split.
	tess.hurt(5.0)
	b.hurt(20.0)
	eq(_bleed(ship, 28), [], "28 s later still apart")
	eq(ship.crew.size(), 2, "two halves")
	lines = _bleed(ship, 1)
	eq(lines, [], "29 s after the split: not yet")
	lines = _bleed(ship, 1)
	eq(lines, ["Tess reforms."], "30 s after it they merge")
	eq(ship.crew.size(), 1, "one body")
	check(ship.crew[0] == tess and _named(ship, "Tess b") == null, "the original, the other half gone")
	eq(tess.body_size, 2, "whole again: 2x2")
	near(tess.max_hp, full, "with the full max hp")
	near(tess.hp, (full / 2.0 - 5.0) + (full / 2.0 - 20.0), "at the sum of the halves' hp")
	check(not tess.is_half and tess.split_pair == "", "not a half any more")
	check(tess.fits(ship.grid, tess.pos, Callable(), tess.body_radius() - 0.01), "on a spot a whole body fits")
	_done()


func test_a_downed_half_holds_the_merge_back_until_it_is_up() -> void:
	var ship := Fixture.room_ship()
	var tess := _tess(ship)
	tess.hurt(1000.0)
	_bleed(ship, 45)
	var b = _named(ship, "Tess b")
	b.hurt(1000.0)
	eq(_bleed(ship, 35), [], "35 s after the split, one half down: no merge, and it has not bled out yet")
	eq(ship.crew.size(), 2, "still two halves")
	b.heal(10.0)  # a crewmate got to it
	eq(_bleed(ship, 1), ["Tess reforms."], "the moment it is up they merge")
	near(tess.hp, 50.0 + 10.0, "at the sum of their hp")
	_done()


func test_when_one_half_dies_the_other_stays_small_and_never_splits_again() -> void:
	var ship := Fixture.room_ship()
	var tess := _tess(ship)
	var full := tess.max_hp
	tess.hurt(1000.0)
	_bleed(ship, 45)
	var b = _named(ship, "Tess b")
	b.hurt(1000.0)
	eq(_bleed(ship, 45), ["Tess b has died."], "one half bleeds out: it dies for good (a half does not split)")
	check(ship.dead_crew.has("Tess b"), "remembered")
	eq(ship.crew.size(), 1, "one left")
	eq(tess.body_size, 1, "who stays small")
	near(tess.max_hp, full / 2.0, "with half the max hp")
	eq(tess.split_pair, "", "and no one to merge with")
	_bleed(ship, 60)
	eq(ship.crew.size(), 1, "nothing merges later")
	eq(tess.body_size, 1, "still small")
	tess.hurt(1000.0)
	eq(_bleed(ship, 45), ["Tess has died."], "and the survivor dies for good too")
	_done()


func test_a_member_without_split_on_death_dies_and_the_original_half_can_die_first() -> void:
	var ship := Fixture.room_ship()
	var plain := _person("Plain", 18, 12)
	ship.crew.append(plain)
	plain.hurt(1000.0)
	eq(_bleed(ship, 45), ["Plain has died."], "no trait, no split")
	var tess := _tess(ship, "Tess", 11, 12)
	tess.hurt(1000.0)
	_bleed(ship, 45)
	tess.hurt(1000.0)  # the original half goes down
	eq(_bleed(ship, 45), ["Tess has died."], "the original half dies")
	var b = _named(ship, "Tess b")
	check(b != null and b.body_size == 1 and b.split_pair == "", "the other half stays, small and alone")
	_done()


# --- counter_melee -------------------------------------------------------------------------------------

func test_counter_melee_deals_the_damage_back_to_the_attacker() -> void:
	_trait("t_quills", {"counter_melee": 10})
	_trait("t_thick", {"damage_taken": {"melee": 0.5}})
	_trait("t_gentle", {"melee_mult": 0.3})
	var ship := Fixture.room_ship()
	var quill := _person("Quill", 11, 12, ["t_quills"])
	var plain := _person("Plain", 15, 12)
	ship.crew.append_array([quill, plain])
	var r := CrewAbilities.melee_hit(ship, plain, quill, 20.0)
	near(r["dealt"], 20.0, "the hit lands in full")
	near(r["countered"], 10.0, "and the spines give 10 back")
	near(quill.hp, quill.max_hp - 20.0, "the Quillback lost the hit")
	near(plain.hp, plain.max_hp - 10.0, "the attacker lost the counter")
	var r2 := CrewAbilities.melee_hit(ship, quill, plain, 20.0)
	near(r2["countered"], 0.0, "no counter from a plain crew member")
	near(quill.hp, quill.max_hp - 20.0, "so the Quillback loses nothing more")
	# The attacker's own melee factor scales the hit; their damage_taken.melee the counter.
	var soft := _person("Soft", 11, 14, ["t_gentle", "t_thick"])
	ship.crew.append(soft)
	var r3 := CrewAbilities.melee_hit(ship, soft, quill, 20.0)
	near(r3["dealt"], 6.0, "a gentle attacker (x0.3) hits for 6")
	near(r3["countered"], 5.0, "and a thick-skinned one (x0.5) takes half of the 10")
	# Two spined crew: the counter is never countered.
	var other := _person("Other", 15, 14, ["t_quills"])
	ship.crew.append(other)
	var hp_other := other.hp
	var r4 := CrewAbilities.melee_hit(ship, other, quill, 1.0)
	near(r4["countered"], 10.0, "a spined attacker is pricked as well")
	near(other.hp, hp_other - 10.0, "once: their own spines do not answer the counter")
	near(quill.hp, quill.max_hp - 20.0 - 6.0 - 1.0, "(the Quillback only took the hits)")
	# A hit that puts them down still pricks; a downed one cannot counter.
	var low := _person("Low", 18, 12, ["t_quills"])
	ship.crew.append(low)
	low.hp = 5.0
	var before := plain.hp
	CrewAbilities.melee_hit(ship, plain, low, 50.0)
	check(low.is_down(), "the hit put them down")
	near(plain.hp, before - 10.0, "the spines still prick")
	CrewAbilities.melee_hit(ship, plain, low, 50.0)
	near(plain.hp, before - 10.0, "a downed Quillback cannot counter")
	check(ship.events.any(func(e): return str(e["text"]).contains("Low is down")), "the chronicle says Low is down")
	_done()


# --- no_suit -------------------------------------------------------------------------------------------

func test_no_suit_refuses_suits_with_a_reason_and_nothing_else() -> void:
	_trait("t_spines", {"no_suit": true})
	var q := _person("Quill", 11, 12, ["t_spines"])
	var h := _person("Human", 15, 12)
	check(TraitSet.of(q)["no_suit"] and not TraitSet.of(h)["no_suit"], "the flag is theirs alone")
	var why := q.can_wear("suit")
	check(why != "" and why.contains("Quill"), "can_wear says why: '%s'" % why)
	eq(q.equip("suit"), why, "equip gives the same reason")
	check(not q.gear_traits.has("suit"), "and the suit is not worn")
	check(not TraitSet.of(q)["no_suit"] == false, "still no_suit")
	eq(q.equip("heat_resistant"), "", "other gear is fine")
	check(q.gear_traits.has("heat_resistant"), "and worn")
	near(TraitSet.of(q)["damage_taken"]["fire"], 0.25, "with its effect")
	eq(h.equip("suit"), "", "a crew member without the trait wears a suit")
	check(h.gear_traits.has("suit") and h.traits().has("suit"), "which is theirs now")
	eq(h.equip("suit"), "", "twice is fine")
	eq(h.gear_traits.count("suit"), 1, "and worn once")
	_done()


# --- vacuum_speed --------------------------------------------------------------------------------------

func test_vacuum_speed_scales_the_walk_only_in_thin_air() -> void:
	_trait("t_zero_g", {"vacuum_speed": 1.5, "vacuum_walk": true})
	var ship := _two_rooms()
	var thin := ship.atmosphere.room_at(Vector2i(12, 22))
	var kite := _person("Kite", 11, 21, ["t_zero_g"], true)
	var in_air := _person("Air", 12, 12, ["t_zero_g"], true)
	var plain := _person("Plain", 16, 21, [], true)
	ship.crew.append_array([kite, in_air, plain])
	for p in [0.0, 0.1, 0.29]:
		ship.atmosphere.pressure[thin] = p
		Jobs.new().tick(ship, 0.01)
		near(kite.speed_mod, 1.5, "at %s of the air: x1.5" % p)
		near(plain.speed_mod, 1.0, "a plain crew member never changes")
		near(in_air.speed_mod, 1.0, "nor does anyone in a room with air")
	for p in [0.3, 0.5, 1.0]:
		ship.atmosphere.pressure[thin] = p
		Jobs.new().tick(ship, 0.01)
		near(kite.speed_mod, 1.0, "at %s of the air: no change" % p)
	ship.atmosphere.pressure[thin] = 0.0
	Jobs.new().tick(ship, 0.01)
	var before := kite.pos
	kite.move_input(ship.grid, Vector2.RIGHT, 0.5)
	near(kite.pos.x - before.x, CrewMember.BASE_SPEED * 1.5 * 0.5, "the player's body walks 1.5 as fast", 1e-4)
	near(TraitSet.thin_air_factor(TraitSet.of(plain), 0.0), 1.0, "no vacuum_speed: 1")
	near(TraitSet.thin_air_factor(TraitSet.of(kite), 0.29), 1.5, "the factor in thin air")
	near(TraitSet.thin_air_factor(TraitSet.of(kite), TraitSet.THIN_AIR), 1.0, "and not at 30%")
	# It stacks with heat_speed (a room with no part is at heat 0: cold).
	_trait("t_chill", {"heat_speed": {"cold": 0.5, "below": 20}})
	var both := _person("Both", 20, 21, ["t_zero_g", "t_chill"], true)
	ship.crew.append(both)
	Jobs.new().tick(ship, 0.01)
	near(both.speed_mod, 0.75, "x0.5 for the cold times x1.5 for the thin air")
	_done()


# --- the Choir: aura work_mult needs no new key --------------------------------------------------------

func test_the_choir_aura_speeds_up_the_others_in_the_room() -> void:
	_trait("t_singer", {"aura": {"work_mult": 1.15}, "melee_mult": 0.3})
	var ship := _two_rooms()
	var singer := _person("Sing", 11, 12, ["t_singer"])
	var mate := _person("Mate", 16, 12)
	var away := _person("Away", 12, 21)
	ship.crew.append_array([singer, mate, away])
	near(TraitSet.work_rate(ship, mate, "repair"), 1.15, "the others in the room work x1.15")
	near(TraitSet.work_rate(ship, singer, "repair"), 1.0, "not the singer")
	near(TraitSet.work_rate(ship, away, "repair"), 1.0, "nor anyone in another room")
	near(TraitSet.work_rate(ship, mate, "extinguish"), 1.15, "at every job")
	var second := _person("Sing2", 18, 14, ["t_singer"])
	ship.crew.append(second)
	near(TraitSet.work_rate(ship, mate, "repair"), 1.15 * 1.15, "two singers multiply")
	second.hurt(1000.0)
	near(TraitSet.work_rate(ship, mate, "repair"), 1.15, "a downed singer gives nothing")
	near(CrewAbilities.melee_mult(ship, singer), 0.3, "and a singer hits at x0.3")
	_done()


# --- Sable: work_mult breach and ranged_mult need no new key -------------------------------------------

func test_sable_breach_work_and_ranged_use_the_keys_that_exist() -> void:
	_trait("t_cutter", {"work_mult": {"breach": 2.0}, "ranged_mult": 1.25, "hp_mult": 0.9})
	var took := {}
	for kind in ["cutter", "plain"]:
		var ship := Fixture.room_ship()
		var west := Vector2i(8, 10)
		ship.grid.breach(west)
		ship.mark_dirty()
		ship.refresh()
		var m := _person("Worker", 9, 10, ["t_cutter"] if kind == "cutter" else [])
		ship.crew.append(m)
		var jobs := Jobs.new()
		var n := 0
		while ship.grid.breached.has(west) and n < 400:
			jobs.tick(ship, STEP)
			n += 1
		took[kind] = n
	check(took["plain"] > 4 and took["plain"] < 400, "a plain crew member seals it: %s" % str(took))
	check(absi(took["plain"] - 2 * took["cutter"]) <= 2, "a Sable in half the time: %s" % str(took))
	var sable := _person("Sable", 11, 12, ["t_cutter"])
	near(TraitSet.of(sable)["ranged_mult"], 1.25, "ranged x1.25 is the ranged_mult key")
	near(TraitSet.of(sable)["work_mult"]["breach"], 2.0, "breach work x2 is work_mult.breach")
	near(sable.max_hp, 100.0 * 0.9, "hp x0.9", 1e-4)
	_done()


# --- the keys merge ------------------------------------------------------------------------------------

func test_the_wave_3_keys_default_and_merge() -> void:
	var plain := TraitSet.of(CrewMember.new("X"))
	near(plain["revive_once"]["hp"], 0.0, "no revive by default")
	near(plain["split_on_death"]["reform_s"], 0.0, "no split")
	eq(plain["line_affinity"], {}, "no line affinity")
	near(plain["counter_melee"], 0.0, "no counter")
	check(not plain["no_suit"], "no_suit is false")
	near(plain["vacuum_speed"], 1.0, "vacuum_speed 1")
	_trait("t_a", {"revive_once": {"after": 10, "hp": 30}, "split_on_death": {"reform_s": 40}, "line_affinity": {"scrap": 2.0, "neon": 0.5}, "counter_melee": 5, "vacuum_speed": 1.5})
	_trait("t_b", {"revive_once": {"after": 6, "hp": 60}, "split_on_death": {"reform_s": 20}, "line_affinity": {"scrap": 1.5}, "counter_melee": 7, "vacuum_speed": 2.0, "no_suit": true})
	_trait("t_c", {"revive_once": {"hp": 10}})
	var m := CrewMember.new("X")
	m.gear_traits = ["t_a", "t_b", "t_c"]
	var t := TraitSet.of(m)
	near(t["revive_once"]["hp"], 60.0, "the highest revive hp")
	near(t["revive_once"]["after"], 6.0, "the quickest revive")
	near(t["split_on_death"]["reform_s"], 20.0, "the quickest reform")
	near(t["line_affinity"]["scrap"], 3.0, "line factors multiply")
	near(t["line_affinity"]["neon"], 0.5, "per line")
	near(t["counter_melee"], 12.0, "counters add")
	near(t["vacuum_speed"], 3.0, "vacuum_speed multiplies")
	check(t["no_suit"], "a flag is true if any trait says so")
	var only_hp := CrewMember.new("Y")
	only_hp.gear_traits = ["t_c"]
	near(TraitSet.of(only_hp)["revive_once"]["after"], 0.0, "a revive with no wait is at once")
	_done()


func test_every_trait_key_is_in_the_doc_of_the_trait_library() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/traits.json"))["_doc"]["keys"]
	for k in TraitSet.KEYS:
		check(doc.has(k), "data/traits.json _doc.keys describes '%s'" % k)
	for k in ["revive_once", "line_affinity", "split_on_death", "counter_melee", "no_suit", "vacuum_speed"]:
		check(TraitSet.KEYS.has(k), "%s is a key" % k)
	check(TraitSet.FLAGS.has("no_suit"), "no_suit is a flag")
	eq(TraitSet.OPEN, ["line_affinity"] as Array[String], "line_affinity is the open group")


# --- the validators ------------------------------------------------------------------------------------

func test_the_validators_know_the_wave_3_keys() -> void:
	var good := [
		{"id": "a", "name": "A", "revive_once": {"after": 10, "hp": 50}, "split_on_death": {"reform_s": 30}, "counter_melee": 10, "no_suit": true, "vacuum_speed": 1.5},
		{"id": "b", "name": "B", "line_affinity": {"scrap": 2.0}},
		{"id": "c", "name": "C", "line_affinity": {"scrap": 2, "neon": 0.5, "standard": 1.0}},
	]
	var checker = TestContent.new()
	eq(checker.trait_problems(good), [] as Array[String], "well-formed wave 3 traits pass")
	var bad := [
		{"id": "d", "name": "D", "revive_once": {"after": 10}},
		{"id": "e", "name": "E", "revive_once": {"after": 10, "hp": 50, "x": 1}},
		{"id": "f", "name": "F", "split_on_death": {"reform_s": 0}},
		{"id": "g", "name": "G", "line_affinity": {"plasma": 2.0}},
		{"id": "h", "name": "H", "line_affinity": 2.0},
		{"id": "i", "name": "I", "line_affinity": {"scrap": "fast"}},
		{"id": "j", "name": "J", "no_suit": 1},
		{"id": "k", "name": "K", "counter_melee": "ouch"},
		{"id": "l", "name": "L", "vacuum_speed": true},
		{"id": "m", "name": "M", "counter_melee": {"damage": 10}},
	]
	var problems: Array[String] = checker.trait_problems(bad)
	for t in ["'revive_once' needs a 'hp'", "unknown key 'x'", "'split_on_death' needs a 'reform_s'", "'plasma', which is not a line", "'line_affinity' must be an object",
			"'line_affinity.scrap' must be a number", "'no_suit' must be true or false", "'counter_melee' must be a number", "'vacuum_speed' must be a number"]:
		check(problems.any(func(p): return p.contains(t)), "a problem says: %s (%s)" % [t, str(problems)])
	for who in "defghijklm".split(""):
		check(problems.any(func(p): return p.contains("'%s'" % who)), "trait %s is flagged" % who)
	var chars: Array[String] = CrewAbilities._traits_problems("x", {"revive_once": {"after": 1}, "line_affinity": {"plasma": 1}, "no_suit": 1, "bogus": 1})
	eq(chars.size(), 4, "a character's own trait keys are checked the same way: %s" % str(chars))
	eq(CrewAbilities._traits_problems("x", {"revive_once": {"after": 10, "hp": 50}, "line_affinity": {"scrap": 2.0}, "no_suit": true, "counter_melee": 5}), [] as Array[String], "and pass when well formed")
