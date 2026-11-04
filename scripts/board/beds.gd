extends RefCounted
## Beds on foot (docs/BOARDING.md, data/boarding.json beds): the soldier holds E by a working bed and heals; held by a hurt follower near a free working
## bed (as long as a revive takes), the follower lies down on it and heals until full. One person to a bed. Nobody heals while a foe hunts the party:
## a follower on a bed gets up to fight. Pure logic over the session (boarding.gd), whose tick() calls tick() here; board_view.gd reads input and draws.
## The beds themselves are the site's (site.gd beds: where they stand and whether they work, from the seed).

const Site = preload("res://scripts/board/site.gd")

var s  ## the session
var resting := {}  ## bed id -> the follower (a party entry) lying on it
var healing := -1  ## the bed the soldier is healing on (-1: none), for the view
var _heal_left := 0.0  # seconds `healing` stays set after the last heal


func _init(p_session = null) -> void:
	s = p_session


static func cfg() -> Dictionary:
	return Site.config()["beds"]


## The nearest bed whose middle is within `reach` cells of `p`, -1 for none (`working` only the working ones).
func near(p: Vector2, reach: float, working := false) -> int:
	var best := -1
	var best_d := reach
	for b in s.site.beds:
		var d: float = s.site.bed_centre(b).distance_to(p)
		if d <= best_d and (not working or bool(b["works"])):
			best = b["id"]
			best_d = d
	return best


## Is bed `id` free (nobody lies on it)?
func is_free(id: int) -> bool:
	return not resting.has(id)


## Why the soldier cannot heal on bed `id` now ("" when he can).
func why_not(id: int) -> String:
	var b: Dictionary = s.site.beds[id]
	if not bool(b["works"]):
		return str(cfg()["broken"])
	if not is_free(id):
		return str(cfg()["busy"])
	if s.hunted():
		return str(cfg()["refuse"])
	return ""


## The soldier holds E by bed `id` for `dt` seconds: he heals heal_hp_s a second. Returns "" or why not (full: the `full` line, once he is).
func heal(id: int, dt: float) -> String:
	var why := why_not(id)
	if why != "":
		return why
	var m = s.soldier
	if m.hp >= m.max_hp:
		return str(cfg()["full"])
	m.hp = minf(m.hp + float(cfg()["heal_hp_s"]) * dt, m.max_hp)
	healing = id
	_heal_left = 0.2
	return ""


## The free working bed nearest follower `i` (within `reach` cells of them), -1 for none.
func bed_for(i: int, reach: float) -> int:
	var m = s.party[i]["m"]
	var best := -1
	var best_d := reach
	for b in s.site.beds:
		var d: float = s.site.bed_centre(b).distance_to(m.pos)
		if bool(b["works"]) and is_free(b["id"]) and d <= best_d:
			best = b["id"]
			best_d = d
	return best


## Put follower `i` on bed `id`: they lie on it (their place is kept to stand up on). Returns "" or why not.
func lay(i: int, id: int) -> String:
	var why := why_not(id)
	if why != "":
		return why
	var p: Dictionary = s.party[i]
	p["bed"] = id
	p["stood"] = p["m"].pos
	p["m"].path.clear()
	p["m"].pos = s.site.bed_centre(s.site.beds[id])
	resting[id] = p
	s.events.append({"type": "line", "text": str(cfg()["lie"]) % p["m"].name, "pos": p["m"].pos})
	return ""


## Follower `p` gets off their bed, back where they stood.
func rise(p: Dictionary) -> void:
	var id := int(p.get("bed", -1))
	if id < 0:
		return
	resting.erase(id)
	p["bed"] = -1
	p["m"].pos = p.get("stood", p["m"].pos)
	s.events.append({"type": "line", "text": str(cfg()["up"]) % p["m"].name, "pos": p["m"].pos})


## `dt` seconds pass: the followers on beds heal, and get up when they are full, when a foe hunts the party, or when they went down.
func tick(dt: float) -> void:
	_heal_left -= dt
	if _heal_left <= 0.0:
		healing = -1
	var hunted: bool = s.hunted()
	for id in resting.keys():
		var p: Dictionary = resting[id]
		var m = p["m"]
		if not hunted and not m.is_down():
			m.hp = minf(m.hp + float(cfg()["heal_hp_s"]) * dt, m.max_hp)
		if hunted or m.is_down() or m.hp >= m.max_hp:
			rise(p)


## Is follower `p` lying on a bed?
static func lying(p: Dictionary) -> bool:
	return int(p.get("bed", -1)) >= 0
