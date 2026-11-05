extends RefCounted
## Away-team expeditions (docs/CONTENT.md section 17, tuning in data/expeditions.json). A site is a sector POI of type exp_<kind> that never triggers by
## itself: the player flies within its reach, presses E, picks a team of 1 to 4 and sends it down. The event chain that follows is read against the TEAM:
## `species`, `trait`, `gear`, `skill` and `suits` in a choice's requires, the `boost` of an outcome, and `crew_hp` all look at the team only.
## Pure logic over the campaign `c` (c.expedition, c.captives) and the ship; no nodes, no drawing. Randomness is the campaign's seeded rng.
## - c.expedition = {poi, kind, team (names), page (the event id now shown)} while a team is away, {} otherwise. Saved.
## - A member lost (`lose_member`: dead, captured or gone) leaves the ship with every item they carried: the kit is NOT given back to the hold
##   (Mortality.lose). A captured one is remembered in c.captives (name -> species) with the flags `captive` and `captive_<name>`, for a later `rescue`.
## - The soldier never dies: lose_member on a lone soldier knocks them down instead.

const Content = preload("res://scripts/data/content.gd")
const Party = preload("res://scripts/board/party.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Air = preload("res://scripts/board/air.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")

const PATH := "res://data/expeditions.json"
const PREFIX := "exp_"
const BOOST_KEYS: Array = ["gear", "species", "trait", "skill"]

static var _cfg := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("kinds") is Dictionary, "bad expedition data: " + PATH)
		_cfg = data
	return _cfg


static func kinds() -> Array:
	return config()["kinds"].keys()


## The kind ("planet", "base", "ruin", "platform") of POI `poi`, "" for any other POI.
static func kind_of(poi: Dictionary) -> String:
	var t := str(poi.get("type", ""))
	return t.trim_prefix(PREFIX) if t.begins_with(PREFIX) and kinds().has(t.trim_prefix(PREFIX)) else ""


static func event_type(kind: String) -> String:
	return PREFIX + kind


static func airless(kind: String) -> bool:
	return bool(config()["kinds"].get(kind, {}).get("airless", false))


static func team_max() -> int:
	return int(config()["team"]["max"])


# --- the team ----------------------------------------------------------------------------------------------

## Who may go: the soldier, then the crew who are up and not posted to a part.
static func candidates(ship) -> Array:
	var out := []
	if ship == null:
		return out
	for m in ship.crew:
		if m.is_player and not m.is_drone():
			out.append(m)
	out.append_array(Party.eligible(ship))
	return out


## "" when `names` is a team that may go, else why not (size 1 to team.max, each a candidate, no repeats).
static func check_team(ship, names: Array) -> String:
	if names.size() < int(config()["team"]["min"]):
		return "Pick at least one."
	if names.size() > team_max():
		return "At most %d can go." % team_max()
	var ok: Array = candidates(ship).map(func(m): return m.name)
	for i in names.size():
		if not ok.has(names[i]) or names.find(names[i]) != i:
			return "%s cannot go." % names[i]
	return ""


## The CrewMember objects of the team away now (those still aboard, in the order picked).
static func members(c, ship) -> Array:
	var out := []
	for n in c.expedition.get("team", []):
		for m in ship.crew:
			if m.name == n:
				out.append(m)
	return out


## Send `names` to site `poi`: picks the first page by the campaign's rng. {ok, why, event}; c.expedition is set when ok.
static func begin(c, ship, poi: Dictionary, names: Array) -> Dictionary:
	var kind := kind_of(poi)
	var why := "not a site" if kind == "" else check_team(ship, names)
	if why != "":
		return {"ok": false, "why": why, "event": {}}
	var ev: Dictionary = c.events.pick(c, {"id": c.current, "type": event_type(kind), "place": ""}, ship)
	if ev.is_empty():
		return {"ok": false, "why": "There is nothing to find here.", "event": {}}
	c.expedition = {"poi": str(poi["id"]), "kind": kind, "team": names.duplicate(), "page": str(ev["id"])}
	return {"ok": true, "why": "", "event": ev}


## The team is home: the expedition is over.
static func finish(c) -> void:
	c.expedition = {}


static func active(c) -> bool:
	return c != null and not c.expedition.is_empty()


# --- reading the team ---------------------------------------------------------------------------------------

## Every item id `m` wears or carries: body gear, mods and the item behind each hand weapon (plus the weapon ids).
static func gear_of(m) -> Array:
	var out := []
	if m.kit.is_empty():
		return out
	var k := Kit.of(m)
	if str(k["body"]) != "":
		out.append(str(k["body"]))
	for item in k["mods"]:
		if str(item) != "":
			out.append(str(item))
	for w in k["weapons"]:
		if str(w) != "":
			out.append(str(w))
			var it := Kit.item_of(str(w))
			if it != "":
				out.append(it)
	return out


static func has_gear(team: Array, item: String) -> bool:
	return team.any(func(m): return gear_of(m).has(item))


static func has_skill(team: Array, skill: String) -> bool:
	return team.any(func(m): return not m.is_down() and str(m.ability.get("id", "")) == skill)


static func has_species(team: Array, species: String) -> bool:
	return team.any(func(m): return not m.is_down() and str(m.species) == species)


static func has_trait(team: Array, t: String) -> bool:
	return team.any(func(m): return not m.is_down() and m.traits().has(t))


## Does every member of `team` breathe with no air (a sealed suit, or a body that needs none)?
static func all_sealed(team: Array) -> bool:
	return team.all(func(m): return Air.sealed(m))


static func _list(v) -> Array:
	return v if v is Array else ([] if v == null else [v])


## The first member of `team` who meets the requirement keys of `req` (species, trait, gear, skill): the one who "chose", else null.
static func actor_for(team: Array, req: Dictionary):
	for m in team:
		if m.is_down():
			continue
		var fits := false
		for s in _list(req.get("species")) + _list(req.get("species_any")):
			fits = fits or str(m.species) == str(s)
		for t in _list(req.get("trait")):
			fits = fits or m.traits().has(str(t))
		for g in _list(req.get("gear")):
			fits = fits or gear_of(m).has(str(g))
		for s in _list(req.get("skill")):
			fits = fits or str(m.ability.get("id", "")) == str(s)
		if fits:
			return m
	return null


## Does `team` meet one `boost` entry ({gear|species|trait|skill: id or list, x: factor})?
static func boost_holds(team: Array, b: Dictionary) -> bool:
	for k in BOOST_KEYS:
		for v in _list(b.get(k)):
			var yes: bool = has_gear(team, str(v)) if k == "gear" else (has_skill(team, str(v)) if k == "skill" else (has_species(team, str(v)) if k == "species" else has_trait(team, str(v))))
			if yes:
				return true
	return false


## `outcomes` with each weight multiplied by the `x` of every `boost` the team meets (a copy; the data is untouched).
static func weighted(outcomes: Array, team: Array) -> Array:
	var out := []
	for o in outcomes:
		var d: Dictionary = o.duplicate()
		var w := float(d.get("weight", 1.0))
		for b in _list(d.get("boost")):
			if b is Dictionary and boost_holds(team, b):
				w *= float(b.get("x", 1.0))
		d["weight"] = w
		out.append(d)
	return out


# --- odds, shown on a choice -----------------------------------------------------------------------------

static func _harms(eff: Dictionary) -> bool:
	return eff.has("hurt") or eff.has("goto") or eff.has("lose_member") or eff.has("lose_gear") or int(eff.get("crew_hp", 0)) < 0


## The tag a choice shows in an expedition: {text, tone ("loss", "gear", "risk")} or {} for a safe one. Odds count the team's boosts.
static func risk_tag(ch: Dictionary, team: Array) -> Dictionary:
	var outs := weighted(_list(ch.get("outcomes")), team)
	var total := 0.0
	var harm := 0.0
	var loses := false
	var gear := false
	for o in outs:
		var eff: Dictionary = o.get("effects", {}) if o.get("effects") is Dictionary else {}
		var w: float = maxf(float(o.get("weight", 1.0)), 0.0)
		total += w
		if _harms(eff):
			harm += w
		loses = loses or (eff.has("lose_member") and w > 0.0)
		gear = gear or (eff.has("lose_gear") and w > 0.0)
	if total <= 0.0 or harm <= 0.0:
		return {}
	var p := harm / total
	var r: Dictionary = config()["risk"]
	if loses:
		return {"text": "[may lose crew: %d%%]" % roundi(p * 100.0), "tone": "loss"}
	if gear:
		return {"text": "[may lose gear: %d%%]" % roundi(p * 100.0), "tone": "gear"}
	return {"text": "[risk: %s]" % ("low" if p <= float(r["low"]) else ("medium" if p <= float(r["mid"]) else "high")), "tone": "risk"}


# --- effects -------------------------------------------------------------------------------------------

static func _pick(c, team: Array, actor, who: String):
	var up: Array = team.filter(func(m): return not m.is_down()) if not team.is_empty() else []
	if up.is_empty():
		up = team
	if up.is_empty():
		return null
	if who == "actor" and actor != null and team.has(actor):
		return actor
	return up[c.rng.randi() % up.size()]


static func _slug(name: String) -> String:
	return name.to_lower().replace(" ", "_")


## Apply the expedition effects of `eff` (hurt, lose_member, lose_gear, rescue, and crew_hp on the team) to the campaign and ship.
## `actor` is the member whose skill, species, trait or gear the choice used (or null). Returns {lines, who}: the changes in words and the
## name `{who}` stands for in the outcome's text.
static func apply(eff: Dictionary, c, ship, actor = null) -> Dictionary:
	var lines := []
	var team := members(c, ship)
	var who := ""
	if actor != null:
		who = actor.name
	elif not team.is_empty():
		who = team[0].name
	if eff.has("hurt"):
		var h = eff["hurt"]
		var hp := float(h if not h is Dictionary else h.get("hp", 0))
		var m = _pick(c, team, actor, "random" if not h is Dictionary else str(h.get("who", "random")))
		if m != null and hp > 0.0:
			m.hurt(hp)
			who = m.name
			lines.append("%s -%d hp" % [m.name, roundi(hp)])
			if m.is_down():
				lines.append("%s is down." % m.name)
	if eff.has("lose_member"):
		var l = eff["lose_member"]
		var how := str(l if not l is Dictionary else l.get("how", "dead"))
		var m = _pick(c, team.filter(func(x): return not x.is_player), actor, "random" if not l is Dictionary else str(l.get("who", "random")))
		if m == null:
			var lone = _pick(c, team, actor, "random")  # the soldier alone: knocked down, never lost
			if lone != null:
				lone.hurt(lone.hp)
				who = lone.name
				lines.append("%s is knocked senseless." % lone.name)
		else:
			who = m.name
			var gear := Kit.carried_text(ship, m)
			lines.append("%s is lost (%s)" % [m.name, {"dead": "killed", "captured": "captured", "gone": "gone"}.get(how, how)])
			if gear != "":
				lines.append("%s lost with them." % gear)
			if how == "captured":
				c.captives[m.name] = str(m.species)
				c.flags["captive"] = true
				c.flags["captive_" + _slug(m.name)] = true
			Mortality.lose(ship, m)  # the kit is gone, not back in the hold
			c.expedition["team"] = c.expedition["team"].filter(func(n): return n != m.name)
	if eff.has("lose_gear"):
		var g = eff["lose_gear"]
		var slot := str(g if g is String else (g.get("slot", "") if g is Dictionary else ""))
		var m = _pick(c, team.filter(func(x): return _carried(x, slot).size() > 0), actor, "random" if not g is Dictionary else str(g.get("who", "random")))
		if m != null:
			var opts := _carried(m, slot)
			var pick: Array = opts[c.rng.randi() % opts.size()]
			var k := Kit.of(m)
			var name := "gear"
			if pick[0] == "body":
				name = Kit._name(ship, str(k["body"]))
				k["body"] = ""
			elif pick[0] == "mod":
				name = Mods.label(str(k["mods"][pick[1]]))
				k["mods"][pick[1]] = ""
			else:
				name = str(Arms.weapon(str(k["weapons"][pick[1]])).get("name", "weapon"))
				k["weapons"][pick[1]] = ""
			m.kit = k
			who = m.name
			lines.append("%s loses the %s." % [m.name, name])
	if eff.has("rescue") and not c.captives.is_empty():
		var n: String = c.captives.keys()[0]
		var back: String = c.add_crew(ship, n, str(c.captives[n]))
		if back != "":
			ship.dead_crew.erase(n)
			c.captives.erase(n)
			c.flags.erase("captive_" + _slug(n))
			if c.captives.is_empty():
				c.flags.erase("captive")
			who = n
			lines.append("%s rejoins the crew" % n)
	return {"lines": lines, "who": who}


## The things `m` carries that can be lost, as [slot, index] pairs ("body", "mod" or "weapon"; their own sidearm never); `slot` "" = any.
static func _carried(m, slot: String) -> Array:
	var out := []
	if m.kit.is_empty():
		return out
	var k := Kit.of(m)
	if (slot == "" or slot == "body") and str(k["body"]) != "":
		out.append(["body", 0])
	for i in k["mods"].size():
		if (slot == "" or slot == "mod") and str(k["mods"][i]) != "":
			out.append(["mod", i])
	for i in k["weapons"].size():
		if (slot == "" or slot == "weapon") and str(k["weapons"][i]) != "" and str(k["weapons"][i]) != m.sidearm():
			out.append(["weapon", i])
	return out


# --- rating a reward (the sim and the tests) -----------------------------------------------------------------

## What a set of effects pays, in the value units of data/expeditions.json: items by their rate, a blueprint, special gear (items.json kind special).
static func value_of(eff: Dictionary) -> float:
	var v: Dictionary = config()["value"]
	var total := 0.0
	var items = eff.get("items", {})
	for id in items:
		var n := float(items[id])
		if n <= 0.0:
			continue
		var rate: float = float(v[id]) if v.has(id) else (float(v["gear"]) if Content.ids("items").has(id) and _special(id) else float(v["other"]))
		total += n * rate
	total += float(v["blueprint"]) * _list(eff.get("blueprint")).size()
	return total


static func _special(id: String) -> bool:
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for it in items.get("items", []):
		if str(it.get("id", "")) == id:
			return str(it.get("kind", "")) in ["special", "mod"]
	return false


## The tier name ("poor", "fair", "good", "rich") of a reward worth `value`.
static func tier_of(value: float) -> String:
	var best := "poor"
	var t: Dictionary = config()["tiers"]
	for k in t:
		if value >= float(t[k]) and float(t[k]) >= float(t[best]):
			best = k
	return best
