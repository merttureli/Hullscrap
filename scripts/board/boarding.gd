extends RefCounted
## One visit to a boarding site (docs/BOARDING.md, stage B1): the site, the soldier on it, what was opened, taken and unlocked. Pure logic:
## board_view.gd reads input and draws, this keeps the rules (and is what the tests drive).
## - start() builds the site for a POI of a sector (the seed is the sector's and the POI's, so a site is the same on every visit) and
##   puts the soldier at the airlock. What earlier visits opened and unlocked is in the sector's `boarded` memory (sector.gd saves it).
## - open() rolls a container's contents (loot.gd); take() moves them to the ship's hold: materials and parts to the cargo, a blueprint
##   is learned at once, a log goes to the journal (campaign.logs_found), a keycard is held for the doors of its colour.
## - A hack door opens after holding E for `hack_s` seconds (the view counts them, then calls unlock()); a card door needs the keycard.
## - leave() writes the visit to the sector's memory and says whether the site is cleared (every container opened): its POI is done then.
## - The sector does not tick while aboard (sector_view.gd), the Hollow tide's linger clock does (map_view.gd).
## offer() is the other half: it puts the "Board her" choice into the event a boardable POI rolls.

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const People = preload("res://scripts/board/people.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")

const WRECK_PARTS := 5  ## most parts of the enemy that a boarded wreck holds in its containers

## The boarding kind of each POI type that can be boarded (sector.gd poi_types); the wreck a won fight leaves is boarded from its salvage page.
const POI_KINDS := {"wreck": "derelict", "abandoned_station": "station", "pirate_nest": "nest"}

var site
var campaign = null  ## campaign.gd (null in a test that has none)
var ship = null  ## the player's ship: its hold takes the loot
var sector = null  ## sector.gd: where the memory of the visit is kept
var poi_id := ""
var spec := {}  ## the `board` effect: {kind, name?, parts?}
var soldier: CrewMember  ## a copy of the player's soldier on the site (hp is carried back by leave)
var opened := {}  ## container id -> true
var left := {}  ## container id -> the contents still in an opened container
var unlocked := {}  ## door id -> true
var keys := {}  ## key id -> true: the keycards held
var cleared := false
var finished := false
var said: Array = []  ## everything taken or learned this visit, in words
var guns: Array = []  ## the weapons he carries, one or two (arms.gd guns); `cur` is the one in his hands
var cur := 0
var rng := RandomNumberGenerator.new()  ## every roll of a fight comes from here (seeded from the site)
var events: Array = []  ## what happened since the view last looked (take_events): shots, hits, clicks, swaps ... {type, ...}
var foes  ## foes.gd: everyone hostile aboard
var spare_rounds := 0  ## the rounds he holds when there is no ship (a test)
var hollow_place := false  ## the place was the Hollow's when he came (hollow-touched stand in it)
var hollow := false  ## the Hollow took the place while he was aboard (note_hollow)
var downed := false  ## the soldier went down: the view fades out and calls leave()
var party: Array = []  ## the crew who came along (party.gd), and a person who follows for now (`temp`)
var people  ## people.gd: everyone aboard who is not hostile (survivors, traders, a captive ...)
var seen_marks := {}  ## mark id -> true: the discoveries (site.marks) that have been shown


## A visit to POI `poi_id` of `sector` with the `board` effect `spec` ({kind, name?, parts?}). The soldier stands at the airlock.
static func start(p_campaign, p_sector, p_poi_id: String, p_spec: Dictionary, p_ship):
	var b = new()
	b.campaign = p_campaign
	b.sector = p_sector
	b.ship = p_ship
	b.poi_id = p_poi_id
	b.spec = p_spec.duplicate(true)
	var mem: Dictionary = p_sector.boarded.get(p_poi_id, {}) if p_sector != null else {}
	if not mem.is_empty():
		b.spec["kind"] = mem["kind"]
		b.spec["parts"] = mem["parts"]
		b.spec["name"] = mem["name"]
	var faction := ""
	var theme := str(mem.get("theme", ""))  # (a place is dressed the way it was the first time)
	var hollow_now: bool = p_campaign != null and p_campaign.is_hollow(p_campaign.current)
	if p_campaign != null:
		faction = str(p_campaign.region_data.get("faction", ""))
		if mem.is_empty():
			theme = Themes.for_region(p_campaign.region_data, hollow_now)
	var seed_value: int = Site._mix(p_sector.seed_value if p_sector != null else 0, p_poi_id, 0)
	b.site = Site.make(seed_value, str(b.spec["kind"]), {"faction": faction, "name": str(b.spec.get("name", "")), "parts": b.spec.get("parts", []), "theme": theme})
	b.spec["name"] = b.site.site_name
	b.spec["parts"] = b.site.parts
	b.soldier = _soldier_of(p_ship)
	b.soldier.pos = b.site.airlock["spawn"]
	b.rng.seed = Site._mix(seed_value, "fight", 0)
	b.foes = Foes.new(b)
	b._arm()
	for id in mem.get("opened", []):
		b.opened[int(id)] = true
	for id in mem.get("unlocked", []):
		b.unlocked[int(id)] = true
		b.site.unlock_door(int(id))
	for id in mem.get("keys", []):
		b.keys[str(id)] = true
	var held: Dictionary = mem.get("left", {})
	for id in held:
		b.left[int(id)] = held[id]
	b.cleared = b.opened.size() >= b.site.containers().size()
	b.hollow_place = hollow_now
	b.spec["crew"] = int(mem.get("crew", p_spec.get("crew", 0)))
	b.foes.spawn_site({"hollow": b.hollow_place, "crew": b.spec["crew"], "mem": mem.get("foes", {})})
	b.people = People.new(b)
	b.people.spawn_site({"hollow": b.hollow_place, "mem": mem.get("people", {})})
	for id in mem.get("marks", []) if mem.get("marks") is Array else []:
		b.seen_marks[int(id)] = true
	return b


## A copy of the ship's soldier (its look, health and species) to walk the site; a plain human when the ship has none.
static func _soldier_of(p_ship) -> CrewMember:
	if p_ship != null:
		for m in p_ship.crew:
			if m.is_player:
				var c = CrewMember.from_dict(m.to_dict())
				if c != null:
					return c
	var s := CrewMember.new("Soldier", Vector2.ZERO, "human")
	s.is_player = true
	return s


# --- containers --------------------------------------------------------------------------------------------------

## How many containers the site has, and how many are open.
func total() -> int:
	return site.containers().size()


func opened_count() -> int:
	return opened.size()


## Open container `id` (its contents were rolled now, or are what an earlier look left). The contents: {items, blueprint, log, key}.
func open(id: int) -> Dictionary:
	if not opened.has(id):
		opened[id] = true
		left[id] = Loot.resolve(site, id, _ctx())
		cleared = opened.size() >= total()
	return left.get(id, {"items": {}, "blueprint": "", "log": "", "key": ""})


## What is left in container `id` as rows for a list: [{key ("item:<id>", "blueprint", "log" or "key"), text}].
func entries(id: int) -> Array:
	var out := []
	var c: Dictionary = left.get(id, {})
	var ids: Array = c.get("items", {}).keys()
	ids.sort()
	for item in ids:
		out.append({"key": "item:" + str(item), "text": "%s x%d" % [_name(str(item)), int(c["items"][item])]})
	if str(c.get("blueprint", "")) != "":
		out.append({"key": "blueprint", "text": "Blueprint: " + _name(_output_of(str(c["blueprint"])))})
	if str(c.get("log", "")) != "":
		out.append({"key": "log", "text": "Log: " + _log_title(str(c["log"]))})
	if str(c.get("key", "")) != "":
		out.append({"key": "key", "text": "%s keycard" % str(c["key"]).capitalize()})
	return out


## Take `what` ("all" or an entry key) out of container `id` into the hold. Returns the lines to tell the player.
func take(id: int, what := "all") -> Array:
	var lines := []
	var c: Dictionary = left.get(id, {})
	if c.is_empty():
		return lines
	if what == "all" or what.begins_with("item:"):
		for item in c["items"].keys():
			if what == "all" or what == "item:" + str(item):
				var n: int = int(c["items"][item])
				if ship != null:
					ship.inventory.add(str(item), n)
				lines.append("+%d %s" % [n, _name(str(item))])
				var found := _found(str(item))
				if found != "":
					lines.append(found)
				c["items"].erase(item)
	if (what == "all" or what == "blueprint") and str(c["blueprint"]) != "":
		var rid: String = c["blueprint"]
		if ship != null and ship.crafting.unlock(rid):
			lines.append("Blueprint learned: " + _name(_output_of(rid)))
		c["blueprint"] = ""
	if (what == "all" or what == "log") and str(c["log"]) != "":
		var lid: String = c["log"]
		if campaign != null:
			campaign.logs_found[lid] = true
		lines.append("Log found: " + _log_title(lid))
		c["log"] = ""
	if (what == "all" or what == "key") and str(c["key"]) != "":
		keys[str(c["key"])] = true
		lines.append("%s keycard" % str(c["key"]).capitalize())
		c["key"] = ""
	if Loot.empty(c):
		left.erase(id)
	said.append_array(lines)
	return lines


# --- doors, the airlock ------------------------------------------------------------------------------------------

## Unlock door `id` (a hack ends here after hack_s of holding E; a card door wants its keycard). Returns "" or why not.
func unlock(id: int, hacked := false) -> String:
	var d: Dictionary = site.doors[id]
	if d["lock"] == "" or unlocked.has(id):
		return ""
	if d["lock"] == "card" and not keys.has(d["card"]):
		return "It wants the %s keycard." % str(d["card"])
	if d["lock"] == "hack" and not hacked:
		return "Hold E to hack the lock."
	unlocked[id] = true
	site.unlock_door(id)
	return ""


## Is the door open to the soldier (it never had a lock, or it was unlocked)?
func door_open_to_soldier(id: int) -> bool:
	return site.doors[id]["lock"] == "" or unlocked.has(id)


## Callable(door cell) -> bool for CrewMember.move_input: locked doors are shut.
func door_passable() -> Callable:
	return func(c: Vector2i) -> bool:
		var d: int = site.door_of.get(c, -1)
		return d < 0 or door_open_to_soldier(d)


## Is the soldier close enough to the hatch to leave?
func at_airlock() -> bool:
	return soldier.pos.distance_to(site.hatch_centre()) <= float(Site.config()["airlock_reach"])


# --- the soldier's weapons ---------------------------------------------------------------------------------------

## Arm him: his species' sidearm, and a second hand weapon from the hold when it holds one (a found rifle). Both are loaded from the rounds in the hold.
func _arm() -> void:
	guns = []
	var side := soldier.sidearm()
	var g = Arms.make_gun(side, false)
	if g == null:
		g = Arms.make_gun("service_pistol", false)
	guns.append(g)
	if ship != null:
		var items: Dictionary = Arms.cfg()["hand_items"]
		for item in items:
			if ship.inventory.count(item) > 0 and str(items[item]) != str(g["id"]):
				guns.append(Arms.make_gun(str(items[item]), false))
				break
	for gun in guns:
		gun["mag"] = _take(int(gun["w"]["mag"]))
	cur = 0


## The rounds in the hold.
func reserve() -> int:
	return ship.inventory.count(str(Arms.cfg()["ammo_item"])) if ship != null else spare_rounds


## Take up to `n` rounds out of the hold; returns how many came.
func _take(n: int) -> int:
	var k := mini(maxi(n, 0), reserve())
	if ship != null:
		ship.inventory.add(str(Arms.cfg()["ammo_item"]), -k)
	else:
		spare_rounds -= k
	return k


func _give(n: int) -> void:
	if n <= 0:
		return
	if ship != null:
		ship.inventory.add(str(Arms.cfg()["ammo_item"]), n)
	else:
		spare_rounds += n


## A hand weapon came into the hold: when his second hand is empty he takes it up. Returns the words, "" for anything else.
func _found(item: String) -> String:
	var wid := Arms.item_weapon(item)
	if wid == "" or guns.size() >= 2 or guns.any(func(g): return g["id"] == wid):
		return ""
	var g = Arms.make_gun(wid, false)
	if g == null:
		return ""
	g["mag"] = _take(int(g["w"]["mag"]))
	guns.append(g)
	return "%s ready: Q swaps." % str(g["w"]["name"])


func gun() -> Dictionary:
	return guns[cur]


## Use the weapon in his hands toward `dir` (radians): a shot, or a swing for a melee weapon. Returns "shot", "swing", "empty", "reloading",
## "wait" (still cooling) or "down".
func fire(dir: float) -> String:
	if soldier.is_down() or finished:
		return "down"
	var g: Dictionary = guns[cur]
	if float(g["reload"]) > 0.0:
		return "reloading"
	if float(g["cd"]) > 0.0:
		return "wait"
	if Arms.has_mag(g) and int(g["mag"]) <= 0:
		g["cd"] = 0.35
		events.append({"type": "click", "pos": soldier.pos})
		return "empty"
	Arms.spend(g)
	var w: Dictionary = g["w"]
	var c := Arms.cfg()
	if bool(w["melee"]):
		_swing(dir, w)
		return "swing"
	var spread := rng.randf_range(-float(w["spread"]), float(w["spread"]))
	var r := Arms.trace(site, soldier.pos, dir + spread, float(w["range"]), foes.bodies() + people.bodies(), rng)
	var from := soldier.pos + Vector2.from_angle(dir) * float(c["muzzle"])
	events.append({"type": "shot", "from": from, "to": r["end"], "who": "soldier", "class": str(w["class"]), "kind": r["kind"]})
	if r["ref"] != null:
		_strike(r["ref"], float(w["damage"]), r["end"])
	foes.noise(soldier.pos, float(c["noise_gun"]))
	return "shot"


func _swing(dir: float, w: Dictionary) -> void:
	var c := Arms.cfg()
	var reach: float = float(w["range"]) + 0.9
	var half := deg_to_rad(float(c["swing_arc_deg"])) / 2.0
	events.append({"type": "swing", "from": soldier.pos, "dir": dir, "reach": reach, "who": "soldier"})
	for b in foes.bodies() + people.bodies():
		if Arms.in_arc(soldier.pos, dir, half, reach, b["pos"]):
			_strike(b["ref"], float(w["damage"]), b["pos"])
	foes.noise(soldier.pos, float(c["noise_swing"]))


## A shot or a blow of the soldier's hit `ref`: a foe is hurt, a person (who has a role) turns on him.
func _strike(ref: Dictionary, amount: float, at: Vector2) -> void:
	if ref.has("role"):
		people.shot(ref, amount)
	else:
		foes.hurt(ref, amount, at)


## R: reload the weapon in his hands from the rounds in the hold. False when there is nothing to do.
func reload() -> bool:
	if soldier.is_down() or not Arms.start_reload(guns[cur], reserve()):
		return false
	events.append({"type": "reload", "pos": soldier.pos})
	return true


## Q: take up the other weapon he carries. False when he has only one.
func swap() -> bool:
	if guns.size() < 2 or soldier.is_down():
		return false
	cur = 1 - cur
	guns[cur]["cd"] = maxf(float(guns[cur]["cd"]), float(Arms.cfg()["swap_s"]))
	events.append({"type": "swap", "pos": soldier.pos})
	return true


## Hand the view what happened since it last asked, and forget it.
func take_events() -> Array:
	var out := events
	events = []
	return out


## One tick of a fight, `dt` seconds with the flashlight pointing `aim` (radians), lit or not: the weapons cool and reload, the foes and the crew
## act, the doors open for whoever comes near them, a fallen soldier is noticed.
func tick(dt: float, aim := 0.0, light_on := true) -> void:
	var take := func(n: int) -> int: return _take(n)
	for g in guns:
		Arms.tick(g, dt, take)
	foes.tick(dt, aim, light_on)
	people.tick(dt)
	Party.tick(self, dt)
	update_doors(float(Arms.cfg()["door_near"]))
	if soldier.is_down() and not downed:
		downed = true
		events.append({"type": "downed", "pos": soldier.pos})
	_check_marks()
	if events.size() > 300:
		events = events.slice(events.size() - 300)


## Open the doors someone stands near (the soldier, his crew, a foe that is up) and shut the rest; a locked door stays shut. Each change is an event.
func update_doors(near: float) -> void:
	var movers: Array = [soldier.pos]
	for p in party:
		movers.append(p["m"].pos)
	movers.append_array(people.movers())
	for f in foes.list:
		if not f["dead"] and not f["hidden"] and f["kind"] != "sentry":
			movers.append(f["m"].pos)
	for d in site.doors:
		if d["lock"] == "gone":
			continue
		var mid: Vector2 = site.door_centre(d)
		var want := false
		if door_open_to_soldier(d["id"]):
			for q in movers:
				if q.distance_to(mid) <= near:
					want = true
					break
		if want != site.grid.is_door_open(d["cells"][0]):
			site.grid.set_door_open(d["cells"][0], want)
			events.append({"type": "door", "id": d["id"], "open": want, "pos": mid})


## Take the crew named in `names` along (at most party_max of the eligible ones; party.gd). Returns how many came.
func join_party(names: Array) -> int:
	party = Party.join(self, names)
	return party.size()


## Names of the crew who are down, in the party.
func downed_party() -> Array:
	return Party.downed(self).filter(func(p): return not bool(p.get("temp", false))).map(func(p): return str(p["src"].name))


## A downed member of the party (a follower's CrewMember) gets up with revive_hp of their health.
func revive_member(m: CrewMember) -> void:
	if not m.is_down():
		return
	m.hp = m.max_hp * float(Arms.cfg()["revive_hp"])
	m.down_t = 0.0
	events.append({"type": "revived", "pos": m.pos})


## Who a foe may shoot or strike: [{pos, r, ref, moving}] the soldier and the crew who are up.
func party_bodies() -> Array:
	var out := []
	var r := float(Arms.cfg()["hit_r"])
	if not soldier.is_down():
		out.append({"pos": soldier.pos, "r": r, "ref": soldier, "moving": foes.soldier_moving})
	for p in party:
		if not p["m"].is_down():
			out.append({"pos": p["m"].pos, "r": r, "ref": p["m"], "moving": p["moving"]})
	return out


## `amount` damage to party member `m` (the soldier or a follower's CrewMember).
func hurt_member(m: CrewMember, amount: float, _from: Vector2) -> void:
	if m.is_down():
		return
	m.hurt(amount)
	events.append({"type": "hurt", "pos": m.pos, "who": "soldier" if m == soldier else "ally", "down": m.is_down()})


## The Hollow may have taken the place: `now` is whether it has. True once, the tick it does while he is aboard (the foes appear then).
func note_hollow(now: bool) -> bool:
	if not now or hollow or hollow_place:
		return false
	hollow = true
	foes.hollow_arrives()
	events.append({"type": "hollow"})
	return true


## What the motion tracker is shown (board_view.gd contacts_source): the foes that are up and out of their vents.
func contacts() -> Array:
	return foes.contacts() + people.contacts()


## Leave: the soldier's health goes back to the ship's (a soldier who went down wakes at the airlock with down_hp of it, and the site is closed for
## good: its POI is done), the visit is written to the sector's memory. Returns {cleared, said, name, kind, poi, downed, text (what to tell him, "" for
## the usual words)}.
func leave() -> Dictionary:
	finished = true
	for g in guns:
		_give(int(g["mag"]))
		g["mag"] = 0
	var lost: Array = []
	for p in party:  # the crew on their feet come home; the ones down are lost
		if bool(p.get("temp", false)):  # a person met aboard stays aboard
			said.append("%s stays behind." % str(p["m"].name))
		elif p["m"].is_down():
			lost.append(str(p["src"].name))
			if ship != null:
				Mortality.lose(ship, p["src"])
			said.append("%s was left behind." % str(p["src"].name))
		else:
			p["src"].hp = minf(p["m"].hp, p["src"].max_hp)
	var text := ""
	if downed:
		soldier.hp = soldier.max_hp * float(Arms.cfg()["down_hp"])
		text = str(Arms.cfg()["down_text"])
	cleared = downed or opened.size() >= total()
	if ship != null:
		for m in ship.crew:
			if m.is_player:
				m.hp = minf(soldier.hp, m.max_hp)
	if sector != null and poi_id != "":
		sector.boarded[poi_id] = memory()
	return {"cleared": cleared, "said": said.duplicate(), "name": site.site_name, "kind": site.kind, "poi": poi_id, "downed": downed, "text": text, "lost": lost}


## What a later visit finds: the kind and the parts (so the same site is made again), what was opened and unlocked, what was left in the open ones.
func memory() -> Dictionary:
	var held := {}
	for id in left:
		held[str(id)] = left[id].duplicate(true)
	var o: Array = opened.keys()
	var u: Array = unlocked.keys()
	var k: Array = keys.keys()
	o.sort()
	u.sort()
	k.sort()
	return {"kind": site.kind, "name": site.site_name, "parts": site.parts.duplicate(), "opened": o, "unlocked": u, "keys": k, "left": held, "cleared": cleared,
		"crew": int(spec.get("crew", 0)), "foes": foes.memory(), "theme": site.theme, "people": people.memory(), "marks": seen_marks.keys()}


# --- people and discoveries -------------------------------------------------------------------------------------

## E at person `id`: what the view has to open (people.gd talk): {id, name, node, event}, {id, shop: true} or {id, say}; {} when no one is there.
func talk(id: int) -> Dictionary:
	return people.talk(id)


## The talk (a person's, or a discovery's: `id` -1) is over: `ops` are what the outcomes asked for (events.gd result "npc"), `acted` whether any outcome did
## something. Returns {lines, shop}; the lines are also said.
func finish_talk(id: int, ops: Array, acted: bool) -> Dictionary:
	var r: Dictionary = people.finish(id, ops, acted)
	said.append_array(r["lines"])
	return r


## Buy row `i` of person `id`'s goods. Returns {ok, text}.
func buy(id: int, i: int) -> Dictionary:
	var r: Dictionary = people.buy(id, i)
	if bool(r["ok"]):
		said.append(str(r["text"]))
	return r


## A marked spot is entered the first time (the "discover" event): {id: -1, node, event} for the panel to open, {} when no event fits.
func discover(mark_id: int) -> Dictionary:
	if campaign == null or mark_id < 0 or mark_id >= site.marks.size():
		return {}
	var m: Dictionary = site.marks[mark_id]
	var node := {"type": "boarding_site", "site": site.kind, "theme": site.theme, "mark": m["kind"]}
	var ev: Dictionary = campaign.events.pick(campaign, node, ship)
	return {"id": -1, "name": "", "node": node, "event": ev} if not ev.is_empty() else {}


## Is some foe on the hunt (it has noticed someone)?
func hunted() -> bool:
	return foes.live().any(func(f): return str(f["mode"]) in ["hunt", "attack", "cover", "flee", "stalk"] or float(f["track"]) > 0.0)


## The first time the soldier stands in a room with a marked spot, with no foe on the hunt, a "discover" event is told to the view (once for the spot).
func _check_marks() -> void:
	if site.marks.is_empty() or soldier.is_down() or finished:
		return
	var rid: int = site.room_at(soldier.pos)
	for m in site.marks:
		if m["room"] == rid and not seen_marks.has(m["id"]) and not hunted():
			seen_marks[m["id"]] = true
			events.append({"type": "discover", "mark": m["id"], "pos": m["pos"]})
			return


# --- the context -------------------------------------------------------------------------------------------------

## What loot.gd needs to know of the run: the tier, the blueprints not held, the logs not found.
func _ctx() -> Dictionary:
	var ctx := {"tier": 1, "unknown": [], "levels": {}, "logs": [], "log_factions": {}, "faction": ""}
	if campaign != null:
		ctx["tier"] = campaign.tier()
		ctx["faction"] = str(campaign.region_data.get("faction", ""))
		for id in campaign.events.logs:
			if not campaign.logs_found.has(id):
				ctx["logs"].append(id)
				ctx["log_factions"][id] = str(campaign.events.logs[id].get("faction", ""))
	if ship != null:
		var skip: Array = Site.config()["blueprint"]["skip"]
		for rid in ship.crafting.order:
			var d: Dictionary = ship.crafting.def(rid)
			if not ship.crafting.is_known(rid) and not skip.has(rid) and str(d.get("category", "")) != "material":
				ctx["unknown"].append(rid)
				ctx["levels"][rid] = int(d.get("fab_level", 1))
	return ctx


func _name(id: String) -> String:
	if ship != null:
		return ship.crafting.name_of(id, ship.components)
	return id.capitalize()


func _output_of(rid: String) -> String:
	if ship != null and ship.crafting.has(rid):
		return str(ship.crafting.def(rid)["output"]["item"])
	return rid


func _log_title(id: String) -> String:
	if campaign != null and campaign.events.logs.has(id):
		return str(campaign.events.logs[id].get("title", id))
	return id


# --- the choice ------------------------------------------------------------------------------------------------

## The words when every container is open.
static func cleared_text() -> String:
	return str(Site.config()["cleared_text"])


## Is `kind` a kind of site (data/boarding.json)?
static func has_kind(kind: String) -> bool:
	return Site.config()["kinds"].has(kind)


## The boarding kind of POI `poi`, "" when it cannot be boarded.
static func kind_for(poi: Dictionary) -> String:
	if bool(poi.get("wreck", false)):
		return "wreck"
	return str(POI_KINDS.get(str(poi.get("type", "")), ""))


## A copy of event `ev` with the "Board her" choice added (its effect is `board: spec`, `extra` is added to the spec), and a free way out when the
## event has none (unless `leave` is false: a salvage page is a pick of one prize).
## An empty event stays empty.
static func offer(ev: Dictionary, kind: String, extra := {}, leave := true) -> Dictionary:
	if ev.is_empty() or kind == "":
		return ev
	var text: Dictionary = Site.config()["offer"][kind]
	var out := ev.duplicate(true)
	var choices: Array = out.get("choices", []) if out.get("choices") is Array else []
	var spec := {"kind": kind}
	spec.merge(extra)
	choices.append({"text": text["text"], "outcomes": [{"weight": 1, "text": text["flavor"], "effects": {"board": spec}}]})
	if leave and not choices.any(func(ch): return _free(ch)):
		choices.append({"text": Site.config()["leave_text"], "outcomes": [{"weight": 1, "text": "", "effects": {}}]})
	out["choices"] = choices
	return out


## A choice that asks for nothing and does nothing: a way out.
static func _free(ch) -> bool:
	if not ch is Dictionary:
		return false
	if (ch.get("requires") is Dictionary and not ch["requires"].is_empty()) or bool(ch.get("pay", false)):
		return false
	for o in ch.get("outcomes", []):
		if o is Dictionary and o.get("effects") is Dictionary and not o["effects"].is_empty():
			return false
	return true
