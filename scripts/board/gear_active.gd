extends RefCounted
## The active of body gear on foot (G; boarding.json `actives`, `gear.<item>.active`): a Dash (jump pack), a Brace (chitin plate), a Patch (medic's sash). Pure logic on the
## boarding session (boarding.gd): `use` starts it and sets the cooldown, `tick` runs the dash and the brace, the cooldown and the allies a spore mantle mends.
## The cooldown shows on the soldier's card (board_cards.gd).

const Site = preload("res://scripts/board/site.gd")
const Kit = preload("res://scripts/board/kit.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")


static func cfg() -> Dictionary:
	return Site.config()["actives"]


## The key that uses it ("G").
static func key() -> String:
	return str(cfg()["key"])


## The active the soldier of session `s` has now ({id, name, cooldown, ...}), {} for none.
static func current(s) -> Dictionary:
	var id := Kit.active_of(s.soldier)
	if id == "" or not cfg().has(id):
		return {}
	var d: Dictionary = cfg()[id].duplicate()
	d["id"] = id
	return d


## Use the soldier's active toward `dir` (radians). Returns {ok, text}: the text is what the view says.
static func use(s, dir: float) -> Dictionary:
	var a := current(s)
	if a.is_empty():
		return {"ok": false, "text": "Nothing in your gear to use."}
	if s.soldier.is_down() or s.finished:
		return {"ok": false, "text": ""}
	if s.active_cd > 0.0:
		return {"ok": false, "text": "%s: %d s." % [a["name"], ceili(s.active_cd)]}
	match str(a["id"]):
		"dash":
			s.dash_left = float(a["cells"])
			s.dash_dir = dir
		"brace":
			s.brace_t = float(a["time"])
		"patch":
			var reach := float(a["reach"])
			var who := [s.soldier]
			for p in s.party:
				if p["m"].pos.distance_to(s.soldier.pos) <= reach:
					who.append(p["m"])
			for m in who:
				if not m.is_down():
					m.heal(m.max_hp * float(a["share"]))
	s.active_cd = float(a["cooldown"])
	s.events.append({"type": "active", "id": str(a["id"]), "pos": s.soldier.pos, "dir": dir})
	return {"ok": true, "text": "%s." % a["name"]}


## `dt` seconds pass: the cooldown, the brace, the dash, how fast the party walks in its gear, and what a spore mantle mends.
static func tick(s, dt: float) -> void:
	s.active_cd = maxf(s.active_cd - dt, 0.0)
	s.brace_t = maxf(s.brace_t - dt, 0.0)
	for m in _people(s):
		m.speed_mod = float(TraitSet.of(m)["walk_mult"])
	if s.dash_left > 0.0 and not s.soldier.is_down():
		var a: Dictionary = cfg()["dash"]
		var dist := minf(float(a["cells"]) / float(a["time"]) * dt, s.dash_left)
		var before: Vector2 = s.soldier.pos
		s.soldier.move_input(s.site.walk, Vector2.from_angle(s.dash_dir), dist / maxf(s.soldier.speed * s.soldier.speed_mod, 0.01), s.soldier_passable())
		var flown: float = s.soldier.pos.distance_to(before)
		s.dash_left = 0.0 if flown < dist * 0.5 else s.dash_left - dist  # (a wall ends it)
	for w in _people(s):  # a spore mantle slowly mends the allies near its wearer
		var rate := Kit.gear_num(w, "ally_heal", 0.0)
		if rate <= 0.0 or w.is_down():
			continue
		for o in _people(s):
			if o != w and not o.is_down() and o.pos.distance_to(w.pos) <= Kit.gear_num(w, "ally_r", 3.5):
				o.heal(rate * dt)


static func _people(s) -> Array:
	var out := [s.soldier]
	for p in s.party:
		out.append(p["m"])
	return out
