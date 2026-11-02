extends RefCounted
## The people aboard a boarding site (docs/BOARDING.md, stage B3): survivors, hermits, traders, scavengers who talk first, a captive in a nest, and the
## Hollow-touched who talk. Not everyone shoots. E talks: the event panel opens an event of type `boarding_npc` (events.gd), picked by the site kind, the
## region, the theme and the person's role; its outcomes can trade, mark a place, take the person on as crew, turn them on you, make them follow or send
## them away (the effects npc_trade, npc_reveal, npc_join, npc_hostile, npc_follow, npc_leave). Pure logic: boarding.gd (the session) holds it, board_view.gd
## draws it. All numbers are in data/boarding.json `people`.
## A person is {id, role, name, species, m (a CrewMember), room, home, state, ev (the event id picked for them, kept), done, shop, shop_open, ...}.
## state: "here" (standing, can be talked to), "leaving" (walking off), "gone", "joined" (a crew member now), "follow" (in the party until he leaves),
## "hostile" (a foe now: `foe` is its id) or "dead". The people are placed from the site's seed alone, on a stream of their own.

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Party = preload("res://scripts/board/party.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Mods = preload("res://scripts/board/mods.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

var s  ## the session (boarding.gd)
var list: Array = []
var revealed := {}  ## container id -> true: marked on the HUD by someone's word
var revealed_doors := {}  ## door id -> true: the same, a locked door
var _next := 0


func _init(p_session = null) -> void:
	s = p_session


static func cfg() -> Dictionary:
	return Site.config()["people"]


## The roles a person can have (data/boarding.json people.roles).
static func role_ids() -> Array:
	var ids: Array = cfg()["roles"].keys()
	ids.sort()
	return ids


static func has_role(id: String) -> bool:
	return cfg()["roles"].has(id)


func find(id: int) -> Dictionary:
	for n in list:
		if n["id"] == id:
			return n
	return {}


## The people standing in the open, who can be talked to.
func here() -> Array:
	return list.filter(func(n): return n["state"] == "here")


# --- placing them ---------------------------------------------------------------------------------------------------

## Fill the site: how many, who and where, from the site's seed (the kind's `count` and `roles`, tilted by the theme and by a place the Hollow holds).
## `ctx`: {hollow (the place is the Hollow's), mem (what an earlier visit left: people.memory())}.
func spawn_site(ctx := {}) -> void:
	list.clear()
	_next = 0
	revealed.clear()
	revealed_doors.clear()
	var site = s.site
	var pc := cfg()
	var theme := Themes.def(site.theme)
	var kc: Dictionary = pc["kinds"].get(site.kind, {"count": {"0": 1.0}, "roles": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "people", 0)
	var counts: Dictionary = kc["count"].duplicate()
	var more := float(theme.get("npc", {}).get("count", 1.0))
	for k in counts:
		if str(k) != "0":
			counts[k] = float(counts[k]) * more
	var n := Site._weighted_count(counts, rng)
	var hollow := bool(ctx.get("hollow", false))
	for i in n:
		var role := _role(kc["roles"], theme, hollow, rng)
		if role == "":
			break
		var spot := _spot(role, rng)
		if spot.is_empty():
			break
		add(role, spot["pos"], int(spot["room"]), _species(theme, rng), _name(theme, rng))
	var mem: Dictionary = ctx.get("mem", {})
	var saved: Dictionary = mem.get("npcs", {}) if mem.get("npcs") is Dictionary else {}
	for n_ in list:
		var d = saved.get(str(n_["id"]))
		if not d is Dictionary:
			continue
		n_["ev"] = str(d.get("ev", ""))
		n_["done"] = bool(d.get("done", false))
		n_["shop"] = []
		for row in d["shop"] if d.get("shop") is Array else []:
			if row is Dictionary and row.has("item"):
				n_["shop"].append({"item": str(row["item"]), "n": int(row.get("n", 1)), "price": int(row.get("price", 1)), "sold": bool(row.get("sold", false))})  # (JSON gives numbers back as floats)
		n_["shop_open"] = bool(d.get("open", false))
		var st := str(d.get("st", "here"))
		if st == "hostile":
			turn(n_, "", false)  # still around, and still after him
		elif st in ["gone", "joined", "dead", "follow", "leaving"]:
			n_["state"] = "gone" if st != "joined" else "joined"
	for id in mem.get("revealed", []) if mem.get("revealed") is Array else []:
		revealed[int(id)] = true
	for id in mem.get("revealed_doors", []) if mem.get("revealed_doors") is Array else []:
		revealed_doors[int(id)] = true


## A role by the kind's weights x the theme's tilt (x the Hollow's, in a place it holds); "" when the kind holds none.
func _role(weights: Dictionary, theme: Dictionary, hollow: bool, rng: RandomNumberGenerator) -> String:
	var w := {}
	var tilt: Dictionary = theme.get("npc", {}).get("roles", {})
	var mult: Dictionary = cfg()["hollow_mult"]
	for r in weights:
		var x := float(weights[r]) * float(tilt.get(r, 1.0))
		if hollow:
			x *= float(mult.get(r, 1.0))
		if x > 0.0:
			w[r] = x
	return "" if w.is_empty() else str(Foes._pick_weighted(w, rng))


func _species(theme: Dictionary, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = theme.get("species", cfg()["species"])
	var ok := {}
	for sp in w:
		if CrewMember.species_table().get("species", {}).has(sp) and not CrewMember.is_drone_species(str(sp)):
			ok[sp] = w[sp]
	return str(Foes._pick_weighted(ok, rng)) if not ok.is_empty() else "human"


func _name(theme: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool: Array = theme.get("people", []) + cfg()["names"]
	for k in 12:
		var pick := str(pool[rng.randi() % pool.size()])
		if not list.any(func(n): return n["name"] == pick):
			return pick
	return str(pool[rng.randi() % pool.size()])


## A free spot for a person of `role`: a room by the role's weights, then a spot apart from every foe and person already placed. {room, pos} or {}.
func _spot(role: String, rng: RandomNumberGenerator) -> Dictionary:
	var site = s.site
	var pc := cfg()
	var rw: Dictionary = pc["roles"][role].get("rooms", pc["rooms"])
	var spots := []
	for r in site.rooms:
		var w := float(rw.get(r["purpose"], 0.0))
		if r["purpose"] == "gone" or r["id"] == site.airlock["room"] or w <= 0.0:
			continue
		for a in site.free_anchors(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			if p.distance_to(site.airlock["spawn"]) >= float(pc["min_from_airlock"]):
				spots.append({"room": r["id"], "pos": p, "w": w})
	if spots.is_empty():
		return {}
	var rooms := {}
	for sp in spots:
		rooms[sp["room"]] = sp["w"]
	var rid := int(Site._pick_weighted(rooms, rng))
	var here_spots := spots.filter(func(sp): return sp["room"] == rid)
	var apart := float(pc["apart"])
	var pick: Dictionary = here_spots[rng.randi() % here_spots.size()]
	for k in 8:
		var cand: Dictionary = here_spots[rng.randi() % here_spots.size()]
		if not list.any(func(n): return n["m"].pos.distance_to(cand["pos"]) < apart) and not s.foes.list.any(func(f): return f["m"].pos.distance_to(cand["pos"]) < apart):
			pick = cand
			break
	return pick


## A person of `role` standing at `pos`. Returns it.
func add(role: String, pos: Vector2, room: int, species: String, name: String) -> Dictionary:
	var d: Dictionary = cfg()["roles"][role]
	var m := CrewMember.new(name, pos, species)
	m.max_hp = float(d["hp"])
	m.hp = m.max_hp
	m.look = d["look"].duplicate()
	var base := 0.0
	if room >= 0:
		var r: Rect2i = s.site.rooms[room]["rect"]
		base = (Vector2(r.position) + Vector2(r.size) / 2.0 - pos).angle()
	m.facing = Vector2.from_angle(base)
	var n := {"id": _next, "role": role, "name": name, "species": species, "m": m, "d": d, "room": room, "home": pos, "state": "here", "ev": "", "done": false,
		"shop": [], "shop_open": false, "dest": pos, "leave_t": 0.0, "repath": 0.0, "tried": false, "moved": false, "foe": -1}
	_next += 1
	list.append(n)
	return n


# --- talking ----------------------------------------------------------------------------------------------------------

## The person within talking reach of `p` (cells), the nearest; -1 when none.
func nearest(p: Vector2, reach: float) -> int:
	var best := -1
	var bd := reach
	for n in here():
		var d: float = n["m"].pos.distance_to(p)
		if d <= bd:
			best = n["id"]
			bd = d
	return best


## What the event machinery is told about the person it picks an event for (events.gd `requires.site`, `role`, `theme`; `npc` for npc_join).
func node_of(n: Dictionary) -> Dictionary:
	return {"type": "boarding_npc", "site": s.site.kind, "theme": s.site.theme, "role": n["role"],
		"npc": {"id": n["id"], "name": n["name"], "species": n["species"], "role": n["role"], "label": n["d"]["name"]}}


## The event for person `n`: the one they were given the first time (kept, so a second talk is the same page), else a pick of the campaign's events by
## their node. {} when there is none (or no campaign).
func event_for(n: Dictionary) -> Dictionary:
	var c = s.campaign
	if c == null:
		return {}
	if n["ev"] != "" and c.events.has(n["ev"]):
		return c.events.get_event(n["ev"])
	var ev: Dictionary = c.events.pick(c, node_of(n), s.ship)
	n["ev"] = str(ev.get("id", ""))
	return ev


## E at person `id`: {id, name, node, event} for the panel to open, {id, shop: true} for a person with goods out, {say} for one with nothing more to say;
## {} when there is no one there.
func talk(id: int) -> Dictionary:
	var n := find(id)
	if n.is_empty() or n["state"] != "here":
		return {}
	if n["shop_open"]:
		if n["shop"].all(func(x): return bool(x["sold"])):
			return {"id": id, "say": str(cfg()["sold_out"]) % n["name"]}
		return {"id": id, "shop": true, "name": n["name"]}
	if n["done"]:
		return {"id": id, "say": str(cfg()["after"]) % n["name"]}
	return {"id": id, "name": n["name"], "node": node_of(n), "event": event_for(n)}


## The talk is over: `ops` are what the outcomes asked of the session (events.gd result "npc"), `acted` whether any outcome did something. `id` is the
## person (-1 for a site discovery, which has none). Returns {lines, shop (the person whose goods to show, else -1)}.
func finish(id: int, ops: Array, acted: bool) -> Dictionary:
	var n := find(id)
	var lines := []
	var shop := -1
	var left := false  # the person is not here to talk to any more
	for op in ops:
		match str(op.get("op", "")):
			"trade":
				if not n.is_empty() and n["state"] == "here":
					if n["shop"].is_empty():
						n["shop"] = roll_shop(n)
					n["shop_open"] = true
					shop = id
			"reveal":
				var line := reveal(str(op.get("what", "container")), n["id"] if not n.is_empty() else 0)
				if line != "":
					lines.append(line)
			"join":
				if not n.is_empty() and bool(op.get("ok", false)):
					n["state"] = "joined"
					left = true
			"hostile":
				if not n.is_empty() and n["state"] == "here":
					turn(n, str(op.get("kind", "")))
					lines.append("%s turns on you." % n["name"])
					left = true
			"follow":
				if not n.is_empty() and n["state"] == "here":
					Party.add_temp(s, n["m"])
					n["state"] = "follow"
					lines.append("%s follows you." % n["name"])
					left = true
			"leave":
				if not n.is_empty() and n["state"] == "here":
					walk_away(n)
					left = true
			"fight":
				var at: Vector2 = n["m"].pos if not n.is_empty() else s.soldier.pos
				if s.foes.ambush(str(op.get("kind", "scavenger")), int(op.get("n", 1)), at) > 0:
					lines.append("Someone is coming.")
	if not n.is_empty() and n["state"] == "here" and acted and shop < 0 and not left:
		n["done"] = true
	return {"lines": lines, "shop": shop}


# --- what they do ----------------------------------------------------------------------------------------------------

## Person `n` turns on the soldier: a foe of `kind` (else their role's `hostile`) at their feet, already after him. `fresh` is false when a visit brings back
## one who had turned earlier (it is not spoken of). Returns the foe.
func turn(n: Dictionary, kind := "", fresh := true) -> Dictionary:
	var fk := kind
	if fk == "" or not Foes.kinds().has(fk) or fk in ["sentry", "crawler"]:
		fk = str(n["d"].get("hostile", "scavenger"))
	var f: Dictionary = s.foes.add(fk, n["m"].pos, int(n["room"]), false)
	f["npc"] = n["id"]
	s.foes.provoke(f)
	n["state"] = "hostile"
	n["foe"] = f["id"]
	if not fresh:
		f["mode"] = "idle"
	return f


## Person `n` walks off to the room farthest from the soldier and is gone when they get there (or after people.leave_s).
func walk_away(n: Dictionary) -> void:
	var best := Vector2.ZERO
	var bd := -1.0
	for r in s.site.rooms:
		if r["purpose"] == "gone":
			continue
		var anchors: Array = s.site.free_anchors(r["id"])
		if anchors.is_empty():
			continue
		var a: Vector2i = anchors[anchors.size() / 2]
		var p := Vector2(a) + Vector2.ONE
		var d := p.distance_to(s.soldier.pos)
		if d > bd:
			bd = d
			best = p
	n["state"] = "leaving"
	n["dest"] = best
	n["leave_t"] = float(cfg()["leave_s"])
	n["repath"] = 0.0
	n["tried"] = false


## A shot or a blow struck person `n`: they fight back (or, with a shot that kills a weak foe, they still stand: the foe takes the damage).
func shot(n: Dictionary, amount: float) -> void:
	if n["state"] != "here":
		return
	var f := turn(n)
	f["m"].hp = maxf(f["m"].hp - amount, 1.0)
	s.events.append({"type": "hit", "pos": n["m"].pos, "foe": f["id"], "kind": f["kind"]})


## Who the soldier's shots and blows can hit: the people in the open (a captive is not shot at).
func bodies() -> Array:
	var out := []
	var r := float(Site.config()["combat"]["hit_r"])
	for n in here():
		if n["role"] != "captive":
			out.append({"pos": n["m"].pos, "r": r, "ref": n})
	return out


## What the motion tracker is shown: the people who are walking.
func contacts() -> Array:
	var out := []
	for n in list:
		if n["state"] == "leaving" and n["moved"]:
			out.append({"pos": n["m"].pos, "moving": true})
	return out


## The positions of people who open doors by walking through them.
func movers() -> Array:
	return list.filter(func(n): return n["state"] == "leaving").map(func(n): return n["m"].pos)


## `dt` seconds pass: the ones who are leaving walk; the ones standing turn toward the soldier when he is near and in sight.
func tick(dt: float) -> void:
	var face := float(cfg()["face_r"])
	for n in list:
		var m: CrewMember = n["m"]
		match str(n["state"]):
			"here":
				var off: Vector2 = s.soldier.pos - m.pos
				if off.length() <= face and s.site.clear_line(m.pos, s.soldier.pos):
					m.facing = off.normalized()
				n["moved"] = false
			"leaving":
				var prev: Vector2 = m.pos
				n["leave_t"] = float(n["leave_t"]) - dt
				n["repath"] = float(n["repath"]) - dt
				if float(n["repath"]) <= 0.0:
					s.foes.path_to(n, n["dest"])
					n["repath"] = 0.6
					n["tried"] = true
				m.step(dt)
				n["moved"] = m.pos.distance_to(prev) > 0.002
				if m.pos.distance_to(n["dest"]) < 1.6 or float(n["leave_t"]) <= 0.0 or (n["tried"] and m.path.is_empty() and not n["moved"]):
					n["state"] = "gone"
					n["moved"] = false


# --- goods -------------------------------------------------------------------------------------------------------------

## Three things for sale, rolled from the tables of the room the person stands in (and the kind's bonus, the theme's tilt): [{item, n, price, sold}].
## The price is the cargo value of the stack x people.shop.markup (credits are never for sale).
func roll_shop(n: Dictionary) -> Array:
	var sc: Dictionary = cfg()["shop"]
	var site = s.site
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "shop", int(n["id"]))
	var purpose := str(site.rooms[n["room"]]["purpose"]) if n["room"] >= 0 else "storage"
	var table: Array = Loot.table_for(site, purpose if Site.config()["tables"].has(purpose) else "storage").filter(func(o): return str(o["item"]) != "credits")
	var mult := float(Site.config()["kinds"][site.kind]["loot_mult"])
	var out := []
	for k in int(sc["tries"]):
		if out.size() >= int(sc["items"]):
			break
		var o := Loot._pick(table, rng)
		if o.is_empty():
			continue
		var item := str(o["item"])
		var count := 1
		if item == Loot.MOD:  # a trader may carry a mod
			item = Mods.roll_drop(site.kind, s.campaign.stage if s.campaign != null else 1, rng)
		if item == "" or out.any(func(x): return x["item"] == item):
			continue
		if not Mods.is_item(item):
			count = maxi(1, roundi(float(rng.randi_range(int(o["count"][0]), int(o["count"][1]))) * mult))
		out.append({"item": item, "n": count, "price": maxi(1, ceili(float(_value(item)) * float(count) * float(sc["markup"]))), "sold": false})
	return out


func _value(item: String) -> int:
	if s.campaign != null and s.ship != null:
		return s.campaign.value_of(s.ship, item)
	return 5


## Buy row `i` of person `id`'s goods. Returns {ok, text}.
func buy(id: int, i: int) -> Dictionary:
	var n := find(id)
	if n.is_empty() or i < 0 or i >= n["shop"].size():
		return {"ok": false, "text": ""}
	var row: Dictionary = n["shop"][i]
	if bool(row["sold"]):
		return {"ok": false, "text": "Sold."}
	if s.ship == null or s.ship.inventory.count("credits") < int(row["price"]):
		return {"ok": false, "text": str(cfg()["broke"])}
	s.ship.inventory.add("credits", -int(row["price"]))
	s.ship.inventory.add(str(row["item"]), int(row["n"]))
	row["sold"] = true
	return {"ok": true, "text": "+%d %s  (-%d credits)" % [int(row["n"]), s._name(str(row["item"])), int(row["price"])]}


# --- marks on the map --------------------------------------------------------------------------------------------------

## Someone's word marks a place on the HUD (npc_reveal): `what` is "container" (any unopened one, the ones worth most likelier), "blueprint" (the one that
## holds a blueprint), "key" (the one that holds a keycard) or "locked" (a locked door, else a container in a locked room); each falls back to a
## container. Returns the line to tell him ("" when there is nothing left to mark). `salt` keeps two people's words apart.
func reveal(what: String, salt := 0) -> String:
	var site = s.site
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "reveal", salt * 31 + revealed.size() + revealed_doors.size())
	var rc: Dictionary = cfg()["reveal"]
	if what == "locked":
		var doors := {}
		for d in site.doors:
			if d["lock"] in ["hack", "card"] and not s.unlocked.has(d["id"]) and not revealed_doors.has(d["id"]):
				doors[d["id"]] = 1.0
		var did := Site._pick_weighted(doors, rng)
		if did >= 0:
			revealed_doors[did] = true
			return "Marked: a locked door (%s)." % ("hack it" if site.doors[did]["lock"] == "hack" else "wants the %s keycard" % str(site.doors[did]["card"]))
	var w := {}
	for p in site.props:
		var id: int = p["id"]
		if not p["loot"] or s.opened.has(id) or revealed.has(id):
			continue
		var locked: bool = site.rooms[p["room"]]["locked"]
		var x := float(rc["other"])
		if p["slot"] == "blueprint":
			x += float(rc["blueprint"])
		if p["slot"] == "key":
			x += float(rc["key"])
		if locked:
			x += float(rc["locked"])
		if what == "blueprint" and p["slot"] != "blueprint":
			x = 0.0
		elif what == "key" and p["slot"] != "key":
			x = 0.0
		elif what == "locked" and not locked:
			x = 0.0
		w[id] = x
	if w.values().all(func(x): return float(x) <= 0.0):  # nothing of that sort: any container
		for id in w:
			w[id] = 1.0
	var pid := Site._pick_weighted(w, rng)
	if pid < 0:
		return ""
	revealed[pid] = true
	var p: Dictionary = site.props[pid]
	var room := str(cfg()["room_names"].get(site.rooms[p["room"]]["purpose"], "a room"))
	return "Marked: %s, %s." % [str(Site.config()["props"][p["prop"]]["name"]).to_lower(), room]


# --- the visit's memory --------------------------------------------------------------------------------------------------

## What a later visit finds: who is still here, what they were told and were selling, what was marked.
func memory() -> Dictionary:
	var out := {}
	for n in list:
		var st := str(n["state"])
		if st == "hostile":
			var f: Dictionary = s.foes.find(int(n["foe"]))
			st = "dead" if not f.is_empty() and f["dead"] else "hostile"
		elif st in ["follow", "leaving"]:
			st = "gone"
		out[str(n["id"])] = {"st": st, "ev": n["ev"], "done": n["done"], "shop": n["shop"].duplicate(true), "open": n["shop_open"]}
	var r: Array = revealed.keys()
	var rd: Array = revealed_doors.keys()
	r.sort()
	rd.sort()
	return {"npcs": out, "revealed": r, "revealed_doors": rd}
