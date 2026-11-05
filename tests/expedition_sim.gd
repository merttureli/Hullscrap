extends RefCounted
## The reward and loss numbers of the away-team expeditions (docs/CONTENT.md section 17): runs whole expeditions headless over many seeds with the real event
## engine, with a team and a policy, and counts what they pay and cost. `tests/run_expedition_sim.gd` prints the table; tests/test_expeditions.gd checks small runs.
## Policies: "bold" always takes the choice that can pay most and goes on; "random" picks uniformly among the choices on offer (Leave included); "well" picks the choice with the best expected value for the team it has
## (reward minus a price for a lost member, lost gear and hurt), blue options first.

const Expedition = preload("res://scripts/space/expedition.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Regions = preload("res://scripts/space/regions.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const SPECIES := ["human", "basalt", "emberkin", "fenn", "kett", "mire", "sporeling", "gauntling", "grundl", "prismatic"]
const SUITS := ["eva_suit", "exosuit", "heat_suit", "salamander_suit"]
const SKILLS := ["scan", "hack", "heal_burst", "repair_burst"]
const PRICE := {"member": 90.0, "gear": 30.0, "hp": 0.5, "page": 45.0}


## A ship with a soldier and `n` crew of the given species list (cycled), with the gear and skills of `kind_of_team` ("random" or "equipped").
static func make_ship(species: Array, equipped: bool, rng: RandomNumberGenerator) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	var extra := 3
	for i in extra:
		var m := CrewMember.new("Hand%d" % i, Vector2(10 + i, 10), str(species[i % species.size()]))
		s.crew.append(m)
	var k := 0
	for m in s.crew:
		if m.is_drone():
			continue
		var body := ""
		if equipped:
			body = str(SUITS[k % SUITS.size()])
			m.ability = {"id": SKILLS[k % SKILLS.size()]}
		elif rng.randf() < 0.4:
			body = str(SUITS[rng.randi() % SUITS.size()])
		m.kit = {"weapons": [m.sidearm(), ""], "body": body, "mods": ["", ""]}
		k += 1
	return s


## Run `n` expeditions to a `kind` site with `policy`, over seeds seed0.. ; returns the table row {n, mean, tiers, loss_rate, members, gear, hurt, left}.
static func run(kind: String, policy: String, n: int, seed0 := 1, equipped := false) -> Dictionary:
	var c := Campaign.new(seed0)
	var rng := RandomNumberGenerator.new()
	var regions: Array = Regions.all().map(func(r): return str(r["id"]))
	var total := 0.0
	var tiers := {"poor": 0, "fair": 0, "good": 0, "rich": 0}
	var members := 0
	var gear := 0
	var hurt := 0
	var any_loss := 0
	var left := 0
	var done := 0
	for t in n:
		rng.seed = seed0 * 7919 + t
		c.rng.seed = seed0 * 104729 + t
		c.used.clear()
		c.flags.clear()
		c.captives = {}
		var region: String = regions[rng.randi() % regions.size()]
		c.region_id = region
		c.region_data = Regions.get_region(region)
		var ship := make_ship(SPECIES.slice(rng.randi() % 5, 10), equipped, rng)
		var names: Array = Expedition.candidates(ship).map(func(m): return m.name)
		if not equipped:
			names.shuffle()
			names = names.slice(0, rng.randi_range(1, 4))
		var out := trial(c, ship, kind, names, policy, rng)
		if out.is_empty():
			continue
		done += 1
		total += out["value"]
		tiers[Expedition.tier_of(float(out["value"]))] += 1
		members += int(out["members"])
		gear += int(out["gear"])
		hurt += int(out["hurt"])
		any_loss += int(int(out["members"]) > 0)
		left += int(out["left"])
	var d := maxf(float(done), 1.0)
	return {"n": done, "mean": total / d, "tiers": tiers, "loss_rate": float(any_loss) / d, "members": float(members) / d, "gear": float(gear) / d, "hurt": float(hurt) / d, "left": float(left) / d}


## One expedition. Returns {value, members, gear, hurt, left}, {} when no site event could be picked.
static func trial(c, ship, kind: String, names: Array, policy: String, rng: RandomNumberGenerator) -> Dictionary:
	var before := inv_value(ship)
	var r := Expedition.begin(c, ship, {"id": "sim", "type": Expedition.event_type(kind), "name": "Sim"}, names)
	if not r["ok"]:
		return {}
	var ev: Dictionary = r["event"]
	var out := {"members": 0, "gear": 0, "hurt": 0, "left": 0}
	var guard := 0
	while not ev.is_empty() and guard < 8:
		guard += 1
		var view: Array = c.events.choice_view(ev, c, ship, {})
		var open: Array = view.filter(func(v): return not v["grey"])
		if open.is_empty():
			break
		var pick: Dictionary = open[rng.randi() % open.size()] if policy == "random" else (greediest(ev, open) if policy == "bold" else best(c, ev, open, ship))
		var res: Dictionary = c.events.choose(ev, int(pick["index"]), c, ship, {})
		if not res["ok"]:
			break
		for l in res["lines"]:
			var line := str(l)
			if line.contains("is lost"):
				out["members"] += 1
			elif line.contains("lost with them") or line.contains(" loses the "):
				out["gear"] += 1
			elif line.ends_with(" hp") and line.contains(" -"):
				out["hurt"] += 1
		ev = c.events.get_event(str(res["goto"])) if str(res["goto"]) != "" and c.events.has(str(res["goto"])) else {}
		if not ev.is_empty() and ev.get("type") == "page":
			pass
	out["left"] = int(c.expedition.get("team", []).size())
	Expedition.finish(c)
	out["value"] = inv_value(ship) - before
	return out


## The choice of `open` that can pay the most (or leads on), whatever it risks: a team that always pushes on.
static func greediest(ev: Dictionary, open: Array) -> Dictionary:
	var top: Dictionary = open[0]
	var top_v := -1.0
	for v in open:
		var hi := 0.0
		for o in ev["choices"][int(v["index"])].get("outcomes", []):
			var eff: Dictionary = o.get("effects", {}) if o.get("effects") is Dictionary else {}
			hi = maxf(hi, Expedition.value_of(eff) + (200.0 if eff.has("goto") else 0.0))
		if hi > top_v:
			top_v = hi
			top = v
	return top


## The choice of `open` with the best expected value for the team away.
static func best(c, ev: Dictionary, open: Array, ship) -> Dictionary:
	var team := Expedition.members(c, ship)
	var top: Dictionary = open[0]
	var top_v := -INF
	for v in open:
		var ch: Dictionary = ev["choices"][int(v["index"])]
		var outs := Expedition.weighted(ch.get("outcomes", []), team)
		var total := 0.0
		for o in outs:
			total += float(o.get("weight", 1.0))
		var ex := 0.0
		for o in outs:
			var eff: Dictionary = o.get("effects", {}) if o.get("effects") is Dictionary else {}
			var val := Expedition.value_of(eff)
			if eff.has("goto"):
				val += PRICE["page"]
			if eff.has("lose_member"):
				val -= PRICE["member"]
			if eff.has("lose_gear"):
				val -= PRICE["gear"]
			var h = eff.get("hurt", 0)
			val -= PRICE["hp"] * float(h if not h is Dictionary else h.get("hp", 0))
			ex += val * float(o.get("weight", 1.0)) / maxf(total, 0.001)
		if ex > top_v:
			top_v = ex
			top = v
	return top


## What the hold is worth in expedition value units (credits and items).
static func inv_value(ship) -> float:
	var total := 0.0
	for id in ship.inventory.counts:
		total += Expedition.value_of({"items": {id: ship.inventory.count(str(id))}})
	return total
