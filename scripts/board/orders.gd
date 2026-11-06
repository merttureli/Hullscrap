extends RefCounted
## Squad orders on foot (docs/BOARDING.md): the crew who came along (party.gd, up to two) can be sent to a room. Pure logic over the session (boarding.gd).
## - A follower has `sel` (selected, for the next order), `order` ({} = follow the soldier; else {room, spot (where it holds), door, id (the container it works on),
##   work (seconds spent), claim (it stands at the container: nobody else loots it), skip (container id -> true: could not be reached)}), `fallback` (it fell back
##   at 25% health), `doing` (what it did last: go, fight, loot, hold, follow, revive, fall) and `blocked` ("no air" or "no way": party.gd _go).
## - With an order the follower walks there (the normal pathing, shooting back on the way), fights whatever is hostile in the room or in sight, then loots every
##   container of the room (the player's hold time, into the party's haul, a log line), then holds the room facing its door. A locked door stays shut to it and so
##   does an airless room without a suit (Air.wait): it stops and says why.
## - Party.tick(s, dt, Orders.act) calls act() first for each follower; false means "act as a follower of the soldier".

const Site = preload("res://scripts/board/site.gd")
const Air = preload("res://scripts/board/air.gd")
const Party = preload("res://scripts/board/party.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")

const FALL := 0.25  ## health share at or under which a follower on an order falls back to the soldier
const STAND := 0.5  ## cells inside the reach it stands from a container
const COLOURS := ["#4ab8ff", "#ffb84a"]  ## the colour of follower 1 and 2: their room marker, the ring under their feet, the stripe of their card


static func colour(i: int) -> Color:
	return Color(COLOURS[i % COLOURS.size()])


## The name of room `rid` ("Mess", "Engineering").
static func room_name(site, rid: int) -> String:
	if rid < 0 or rid >= site.rooms.size():
		return "room"
	return str(site.rooms[rid]["purpose"]).replace("_", " ").capitalize()


## Can follower `p` take an order: a crew member (not a person met aboard), up, not lying on a bed?
static func can_order(p: Dictionary) -> bool:
	return not bool(p.get("temp", false)) and not p["m"].is_down() and int(p.get("bed", -1)) < 0


## The followers the next order is for: the selected ones, else all.
static func targets(s) -> Array:
	var all: Array = s.party.filter(func(p): return can_order(p))
	var sel: Array = all.filter(func(p): return bool(p.get("sel", false)))
	return sel if not sel.is_empty() else all


## Select follower `i` (an index of the party): alone, or with `add` toggled among those selected. Selecting the only selected one again deselects it.
static func select(s, i: int, add := false) -> void:
	if i < 0 or i >= s.party.size() or not can_order(s.party[i]):
		return
	var was := bool(s.party[i].get("sel", false))
	if not add:
		var others: Array = s.party.filter(func(p): return bool(p.get("sel", false)) and p != s.party[i])
		for p in s.party:
			p["sel"] = false
		s.party[i]["sel"] = not was or not others.is_empty()
	else:
		s.party[i]["sel"] = not was


# --- giving orders ----------------------------------------------------------------------------------------------------

## Send the followers (targets) to room `room`. Returns the words to tell the player, "" when nobody could go (or there is no such room).
static func send(s, room: int) -> String:
	var site = s.site
	if room < 0 or room >= site.rooms.size() or str(site.rooms[room]["purpose"]) == "gone":
		return ""
	var who: Array = targets(s)
	if who.is_empty():
		return ""
	var taken := []
	var names := []
	for p in who:
		var o := {"room": room, "id": -1, "work": 0.0, "claim": false, "skip": {}}
		var h: Dictionary = _hold(s, p, room, taken)
		o["spot"] = h["spot"]
		o["door"] = h["door"]
		taken.append(h["spot"])
		p["order"] = o
		p["fallback"] = false
		p["blocked"] = ""
		p["repath"] = 0.0
		names.append(str(p["m"].name))
	return "%s: go to the %s." % [" and ".join(names), room_name(site, room).to_lower()]


## Where a follower holds room `room`: a free spot just inside the door nearest the soldier (not on a spot already `taken`), and the middle of that door.
static func _hold(s, p: Dictionary, room: int, taken: Array) -> Dictionary:
	var site = s.site
	var best_door := {}
	var bd := INF
	for did in site.rooms[room]["doors"]:
		var d: Dictionary = site.doors[did]
		if d["lock"] == "gone":
			continue
		var dist: float = site.door_centre(d).distance_to(s.soldier.pos)
		if dist < bd:
			bd = dist
			best_door = d
	var door: Vector2 = site.door_centre(best_door) if not best_door.is_empty() else site.centre_of_room(room)
	var spots: Array = []
	for a in site.free_anchors(room):
		var c := Pathfinder.centre_of(a, p["m"].body_size)
		if c.distance_to(door) >= 2.4 and taken.all(func(t): return c.distance_to(t) >= 2.2):
			spots.append(c)
	spots.sort_custom(func(a, b): return a.distance_to(door) < b.distance_to(door))
	return {"spot": spots[0] if not spots.is_empty() else site.centre_of_room(room), "door": door}


## Call the followers (targets) back to the soldier. Returns the words to tell the player, "" when none was on an order.
static func recall(s) -> String:
	var names := []
	for p in targets(s):
		if not p.get("order", {}).is_empty() or bool(p.get("fallback", false)):
			names.append(str(p["m"].name))
		p["order"] = {}
		p["fallback"] = false
	return "%s follow%s you." % [" and ".join(names), "s" if names.size() == 1 else ""] if not names.is_empty() else ""


# --- doing them -------------------------------------------------------------------------------------------------------

## The containers followers are working on (standing at them, looting): id -> true. The player cannot start on one of these.
static func busy(s) -> Dictionary:
	var out := {}
	for p in s.party:
		var o: Dictionary = p.get("order", {})
		if not o.is_empty() and bool(o["claim"]) and not p["m"].is_down():
			out[int(o["id"])] = true
	return out


## Is container `id` empty and done with (opened and everything taken)?
static func _done(s, id: int) -> bool:
	return s.opened.has(id) and not s.left.has(id)


## The hostiles in room `room` (as the shot bodies of foes.gd): the nearest to `from`, {} for none.
static func _room_foe(s, from: Vector2, room: int) -> Dictionary:
	var best := {}
	var bd := INF
	for b in s.foes.bodies():
		var d: float = from.distance_to(b["pos"])
		if d < bd and s.site.room_at(b["pos"]) == room:
			best = b
			bd = d
	return best


## The container follower `p` loots next in room `room`: the one it works on, else the nearest not done, not skipped and not another's. -1 for none.
static func _next_loot(s, p: Dictionary, o: Dictionary) -> int:
	var site = s.site
	var busy_by_others := {}
	for q in s.party:
		var oq: Dictionary = q.get("order", {})
		if q != p and not oq.is_empty() and bool(oq["claim"]) and not q["m"].is_down():
			busy_by_others[int(oq["id"])] = true
	var ok := func(id: int) -> bool:
		return id >= 0 and not _done(s, id) and not o["skip"].has(id) and not busy_by_others.has(id) and s.soldier_claim != id
	if ok.call(int(o["id"])):
		return int(o["id"])
	var best := -1
	var bd := INF
	for q in site.props:
		if q["loot"] and int(q["room"]) == int(o["room"]) and ok.call(q["id"]):
			var d: float = site.centre_of(q).distance_to(p["m"].pos)
			if d < bd:
				bd = d
				best = q["id"]
	return best


## The order step of follower `p` for `dt` seconds. True when it acted on its order, false when it should follow the soldier (no order, or it fell back).
static func act(s, p: Dictionary, dt: float) -> bool:
	var m = p["m"]
	var o: Dictionary = p.get("order", {})
	if bool(p.get("fallback", false)) and m.hp > m.max_hp * FALL:
		p["fallback"] = false
	if o.is_empty():
		return false
	if m.hp <= m.max_hp * FALL:  # too hurt: back to the soldier, and no more orders until it is mended
		p["order"] = {}
		p["fallback"] = true
		p["doing"] = "fall"
		return false
	var room := int(o["room"])
	var inside: bool = s.site.room_at(m.pos) == room
	p["blocked"] = ""
	var foe: Dictionary = Party._target(s, m, p["gun"]["w"])
	if foe.is_empty() and inside:
		foe = _room_foe(s, m.pos, room)
	if not foe.is_empty():
		o["claim"] = false
		o["work"] = 0.0
		p["doing"] = "fight"
		Party.engage(s, p, dt, foe, Vector2.INF)
		return true
	if not inside:
		o["claim"] = false
		o["work"] = 0.0
		p["doing"] = "go"
		Party._go(s, p, o["spot"], dt)
		return true
	var id := _next_loot(s, p, o)
	o["id"] = id
	if id >= 0:
		_loot(s, p, o, id, dt)
		return true
	o["claim"] = false
	p["doing"] = "hold"
	if m.pos.distance_to(o["spot"]) > 1.0:
		Party._go(s, p, o["spot"], dt)
	else:
		m.path.clear()
		var face: Vector2 = o["door"] - m.pos
		if face.length() > 0.1:
			m.facing = face.normalized()
	return true


## Walk to container `id`, hold at it for the player's time (props.<prop>.hold), then open it and take everything into the hold with a log line.
static func _loot(s, p: Dictionary, o: Dictionary, id: int, dt: float) -> void:
	var m = p["m"]
	var pr: Dictionary = s.site.props[id]
	var at: Vector2 = s.site.centre_of(pr)
	if m.pos.distance_to(at) > float(Site.config()["reach"]) - STAND:
		o["claim"] = false
		o["work"] = 0.0
		p["doing"] = "loot"
		Party._go(s, p, at, dt)
		if str(p["blocked"]) == "no way":  # it cannot get to it (a lock, a blocked corner): leave it be
			o["skip"][id] = true
			o["id"] = -1
		return
	m.path.clear()
	m.facing = (at - m.pos).normalized() if at.distance_to(m.pos) > 0.05 else m.facing
	p["doing"] = "loot"
	o["claim"] = true
	o["work"] = float(o["work"]) + dt
	if float(o["work"]) < float(Site.config()["props"][str(pr["prop"])]["hold"]):
		return
	s.open(id)
	var lines: Array = s.take(id, "all")
	o["claim"] = false
	o["work"] = 0.0
	o["id"] = -1
	var got := []
	for l in lines:
		got.append(str(l).substr(1).to_lower() if str(l).begins_with("+") else str(l))
	if not got.is_empty():
		s.events.append({"type": "line", "text": "%s looted %s in the %s." % [m.name, ", ".join(got), room_name(s.site, int(o["room"]))], "pos": m.pos})


# --- what the card says -----------------------------------------------------------------------------------------------

## The state line under follower `p`'s card.
static func state(s, p: Dictionary) -> String:
	var m = p["m"]
	if m.is_down():
		return ""
	var o: Dictionary = p.get("order", {})
	var blocked := str(p.get("blocked", ""))
	if blocked == "no air":
		return "Can't enter: no air"
	if o.is_empty():
		if bool(p.get("fallback", false)):
			return "Falling back"
		return "Fighting" if str(p.get("doing", "")) == "fight" else "Following"
	var where := room_name(s.site, int(o["room"]))
	match str(p.get("doing", "go")):
		"fight":
			return "Fighting"
		"loot":
			return "Looting"
		"hold":
			return "Holding: " + where
	return "Can't enter: locked" if blocked == "no way" else "Going: " + where
