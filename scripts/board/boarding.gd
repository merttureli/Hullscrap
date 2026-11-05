extends RefCounted
## One visit to a boarding site (docs/BOARDING.md, stage B1): the site, the soldier on it, what was opened, taken and unlocked. Pure logic:
## board_view.gd reads input and draws, this keeps the rules (and is what the tests drive).
## - start() builds the site for a POI of a sector (the seed is the sector's and the POI's, so a site is the same on every visit) and
##   puts the soldier at the airlock. What earlier visits opened and unlocked is in the sector's `boarded` memory (sector.gd saves it).
## - open() rolls a container's contents (loot.gd); take() moves them to the ship's hold: materials and parts to the cargo, a blueprint
##   is learned at once, a log goes to the journal (campaign.logs_found), a keycard is held for the doors of its colour.
## - A hack door opens after holding E for `hack_s` seconds (the view counts them, then calls unlock()); a card door needs the keycard.
## - leave() writes the visit to the sector's memory and says whether the site is cleared (every container opened): its POI is done then.
## - The sector does not tick while aboard (sector_view.gd), nor does the Hollow tide's linger clock (map_view.gd).
## offer() is the other half: it puts the "Board her" choice into the event a boardable POI rolls.

const Site = preload("res://scripts/board/site.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const HeatFoot = preload("res://scripts/board/heat_foot.gd")
const Loot = preload("res://scripts/board/loot.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Arms = preload("res://scripts/board/arms.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const People = preload("res://scripts/board/people.gd")
const Themes = preload("res://scripts/board/themes.gd")
const Mortality = preload("res://scripts/crew/mortality.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Bolts = preload("res://scripts/board/bolts.gd")
const Air = preload("res://scripts/board/air.gd")
const WreckSite = preload("res://scripts/board/wreck_site.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const GearActive = preload("res://scripts/board/gear_active.gd")
const Beds = preload("res://scripts/board/beds.gd")

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
var quiet_s := 1.0e9  ## seconds since a foe last had noticed anyone (the Leave button wants Arms.cfg() leave_quiet_s of it)
var downed := false  ## the soldier went down: the view fades out and calls leave()
var party: Array = []  ## the crew who came along (party.gd), and a person who follows for now (`temp`)
var people  ## people.gd: everyone aboard who is not hostile (survivors, traders, a captive ...)
var beds  ## beds.gd: who lies on which bed
var seen_marks := {}  ## mark id -> true: the discoveries (site.marks) that have been shown
var flares: Array = []  ## B4: the flares of a flare gun that burn on the site: [{id, pos, wait (seconds until it lands), t (seconds left burning)}]
var cur_room := -1  ## the room the soldier stands in (the last one, in a doorway)
var spotted: Array = []  ## B4: the rooms a Spotter Cam in the party shows (room ids, none without one)
var _door_note := 0.0
var air_t := 0.0  ## seconds since the soldier last cried out choking (air.gd)
var air_warned := false  ## the warning at the airlock was given (air.gd airlock_warning)
var air_seen := {}  ## room id -> seconds since the soldier first saw it airless (the NO AIR label of the view)
var _flare_id := 0
var active_cd := 0.0  ## seconds until the soldier's gear active (G) can be used again (gear_active.gd)
var brace_t := 0.0  ## seconds of a Brace left: the soldier takes brace.share x the damage
var dash_left := 0.0  ## cells of a Dash still to fly
var dash_dir := 0.0  ## the way of the Dash (radians)


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
	var opts := {"faction": faction, "name": str(b.spec.get("name", "")), "parts": b.spec.get("parts", []), "theme": theme, "region": str(p_campaign.region_data.get("id", "")) if p_campaign != null else ""}
	if not mem.is_empty():  # (a station first seen before module stations stays as it was: classic)
		opts["gen"] = str(mem.get("gen", "classic"))
		opts["state"] = str(mem.get("state", ""))
	var kept: Dictionary = p_sector.wreck_ships.get(p_poi_id, {}) if p_sector != null and str(b.spec["kind"]) == "wreck" else {}
	if not kept.is_empty():  # the wreck of a ship she beat is that ship (wreck_site.gd); one with none stored is a generated site
		opts["fight"] = str(kept.get("fight", "won"))
		b.site = WreckSite.make(seed_value, kept["ship"], opts)
	if b.site == null:
		b.site = Site.make(seed_value, str(b.spec["kind"]), opts)
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
	if bool(mem.get("power", false)):
		b.restore_power()
	var held: Dictionary = mem.get("left", {})
	for id in held:
		b.left[int(id)] = held[id]
	b.hollow_place = hollow_now
	b.spec["crew"] = int(mem.get("crew", p_spec.get("crew", 0)))
	b.foes.spawn_site({"hollow": b.hollow_place, "crew": b.spec["crew"], "mem": mem.get("foes", {})})
	b.cleared = b.opened_count() >= b.total()  # (after the foes: the bodies of the beaten are containers too, but no part of what clears a site)
	b.people = People.new(b)
	b.people.spawn_site({"hollow": b.hollow_place, "mem": mem.get("people", {})})
	b.beds = Beds.new(b)
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
	var n := 0
	for id in opened:
		if id < 0 or id >= site.props.size() or not site.props[id].has("foe"):
			n += 1
	return n


## Open container `id` (its contents were rolled now, or are what an earlier look left). The contents: {items, blueprint, log, key}.
func open(id: int) -> Dictionary:
	if not opened.has(id):
		opened[id] = true
		left[id] = Loot.resolve(site, id, _ctx())
		_rig(id)
		cleared = opened_count() >= total()
	return left.get(id, {"items": {}, "blueprint": "", "log": "", "key": ""})


## The Salvage Rig of the party (mods.gd) adds to the stacks of container `id` it was just opened: what it adds is kept in `bonus` ({item: n}, already in `items`) for the list to show.
## Its fractions come from a stream of the site's seed and the container, so the same container gives the same bonus.
func _rig(id: int) -> void:
	var tier := Mods.party_tier(self, "salvage_rig")
	if tier <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "rig", id)
	var c: Dictionary = left[id]
	var extra := Mods.salvage(c["items"], tier, rng)
	for item in extra:
		c["items"][item] = int(c["items"].get(item, 0)) + int(extra[item])
	c["bonus"] = extra


## What is left in container `id` as rows for a list: [{key ("item:<id>", "blueprint", "log" or "key"), text}].
func entries(id: int) -> Array:
	var out := []
	var c: Dictionary = left.get(id, {})
	var ids: Array = c.get("items", {}).keys()
	ids.sort()
	for item in ids:
		var row := {"key": "item:" + str(item), "text": "%s x%d" % [_name(str(item)), int(c["items"][item])]}
		var extra := int(c.get("bonus", {}).get(item, 0))
		if extra > 0:  # the Salvage Rig's share, shown in the mod's colour
			row["bonus"] = "+%d %s" % [extra, _name(str(item)).to_lower()]
			row["color"] = Mods.color("salvage_rig")
		out.append(row)
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
				if str(item) == "scrap":
					n = roundi(float(n) * (float(TraitSet.of(soldier).get("scrap_mult", 1.0)) if soldier != null else 1.0))  # (scrap gauntlets)
				if ship != null:
					ship.inventory.add(str(item), n)
				lines.append("+%d %s" % [n, _name(str(item))])
				var found := _found(str(item))
				if found != "":
					lines.append(found)
				c["items"].erase(item)
				if c.get("bonus") is Dictionary:
					c["bonus"].erase(item)
	if (what == "all" or what == "blueprint") and str(c["blueprint"]) != "":
		var rid: String = c["blueprint"]
		if ship != null and ship.crafting.unlock(rid):
			lines.append(ship.crafting.learned_line(rid, ship.components))
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


## Callable(door cell) -> bool for the soldier's own steps: as door_passable, and a door into a room with no air is shut to him unless he wears a seal (air.gd).
func soldier_passable() -> Callable:
	return func(c: Vector2i) -> bool:
		var d: int = site.door_of.get(c, -1)
		return d < 0 or (door_open_to_soldier(d) and not Air.door_refuses(site, site.doors[d], soldier))


## Does the airlock open on air too thin to breathe (he needs a sealed suit to go aboard)?
func needs_suit() -> bool:
	return Air.bad(site.air_of(int(site.airlock["room"])))


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

## Arm him: the weapons of his kit (kit.gd), else his species' sidearm and a second hand weapon from the hold when it holds one (a found rifle). Both are loaded
## from the rounds in the hold.
func _arm() -> void:
	guns = []
	if Kit.is_set(soldier):
		for w in Kit.weapons_of(soldier):
			guns.append(Arms.make_gun(str(w), false, Kit.gear_num(soldier, "mag", 1.0)))
	else:
		var side := soldier.sidearm()
		var g = Arms.make_gun(side, false, Kit.gear_num(soldier, "mag", 1.0))
		if g == null:
			g = Arms.make_gun("service_pistol", false)
		guns.append(g)
		if ship != null:
			var items: Dictionary = Arms.cfg()["hand_items"]
			for item in items:
				if ship.inventory.count(item) > 0 and str(items[item]) != str(g["id"]):
					guns.append(Arms.make_gun(str(items[item]), false))
					break
	guns = guns.filter(func(g): return g != null)
	if guns.is_empty():
		guns.append(Arms.make_gun("service_pistol", false))
	for gun in guns:
		gun["mag"] = _take(int(gun["w"]["mag"]))
	cur = 0


## Re-arm him after the loadout screen changed his kit on the ship (`src` is the ship's own soldier): the rounds he held go back first.
func rearm(src) -> void:
	for g in guns:
		_give(int(g["mag"]))
	soldier.kit = src.kit.duplicate(true)
	_arm()


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
	var g = Arms.make_gun(wid, false, Kit.gear_num(soldier, "mag", 1.0))
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
	var from := soldier.pos + Vector2.from_angle(dir) * float(c["muzzle"])
	shoot(soldier, "soldier", from, dir + spread, w, foes.bodies() + people.bodies())
	foes.noise(soldier.pos, float(c["noise_gun"]))
	return "shot"


## One shot of party member `m` (the soldier or a follower; `who` "soldier" or "ally") from `from` along `ang` with weapon `w`: a ray that stops at the first body,
## or goes on through as many as the Overcharge Coil of `m` allows, and the shot event the view flies as a bolt. The bodies it hits take the damage now (the logic does
## not wait for the bolt); the events of the hits say when the bolt arrives (`delay`), so the view shows them then. A flare gun leaves a flare where it lands.
func shoot(m, who: String, from: Vector2, ang: float, w: Dictionary, bodies: Array) -> void:
	var dmg := float(w["damage"]) * Mods.damage_mult(m)
	var look := Bolts.look(str(w["id"]), Mods.bolt_size(m))
	var reach := float(w["range"])
	var start: Vector2 = m.pos
	var skip = null
	var r := {}
	var hits := []
	for k in Mods.pierce(m) + 1:
		r = Arms.trace(site, start, ang, reach, bodies, rng, skip)
		if r["ref"] == null:
			break
		hits.append(r)
		skip = r["ref"]
		reach -= start.distance_to(r["end"])
		start = r["end"]
		if reach <= 0.0:
			break
	var end: Vector2 = r["end"]
	var ev := {"type": "shot", "from": from, "to": end, "who": who, "class": str(w["class"]), "kind": r["kind"], "weapon": str(w["id"]), "look": look,
		"t": Bolts.travel(look, from.distance_to(end))}
	events.append(ev)
	for h in hits:
		var i0 := events.size()
		_strike(h["ref"], dmg, h["end"])
		_delay(i0, Bolts.travel(look, from.distance_to(h["end"])), look)
	if str(w["id"]) == str(Site.config()["flare"]["weapon"]):
		_flare(end, float(ev["t"]))


## The events since index `i0` that show a body being hit happen when the bolt arrives, `t` seconds from now, and flash in the bolt's colour (`look`).
func _delay(i0: int, t: float, look := {}) -> void:
	for i in range(i0, events.size()):
		if str(events[i]["type"]) in ["hit", "down", "hurt", "downed"]:
			if t > 0.0:
				events[i]["delay"] = t
			if not look.is_empty():
				events[i]["tint"] = str(look["color"])


func _swing(dir: float, w: Dictionary) -> void:
	var c := Arms.cfg()
	var reach: float = float(w["range"]) + 0.9
	var half := deg_to_rad(float(c["swing_arc_deg"])) / 2.0
	var dmg := float(w["damage"]) * Mods.damage_mult(soldier) * float(TraitSet.of(soldier)["melee_mult"])  # (scrap gauntlets)
	events.append({"type": "swing", "from": soldier.pos, "dir": dir, "reach": reach, "who": "soldier", "look": Bolts.look(str(w["id"]), Mods.bolt_size(soldier))})
	for b in foes.bodies() + people.bodies():
		if Arms.in_arc(soldier.pos, dir, half, reach, b["pos"]):
			_strike(b["ref"], dmg, b["pos"], true)
	foes.noise(soldier.pos, float(c["noise_swing"]))


## A shot or a blow of the soldier's hit `ref`: a foe is hurt, a person (who has a role) turns on him.
func _strike(ref: Dictionary, amount: float, at: Vector2, melee := false) -> void:
	if ref.has("role"):
		people.shot(ref, amount)
	else:
		foes.hurt(ref, amount, at)
		if melee and ref.has("m") and not soldier.is_down():  # a foe in chitin hits back
			var back := Foes.counter_melee(ref["m"])
			if back > 0.0:
				hurt_member(soldier, back, ref["m"].pos)


# --- flares ---------------------------------------------------------------------------------------------------------------

## A flare lands at `at` in `wait` seconds and burns flare.burn_s seconds. At most flare.max burn at once: the oldest goes out.
func _flare(at: Vector2, wait: float) -> void:
	var fc: Dictionary = Site.config()["flare"]
	_flare_id += 1
	flares.append({"id": _flare_id, "pos": at, "wait": wait, "t": float(fc["burn_s"])})
	events.append({"type": "flare", "id": _flare_id, "pos": at, "delay": wait})
	while flares.size() > int(fc["max"]):
		events.append({"type": "flare_out", "id": flares[0]["id"]})
		flares.remove_at(0)


## Does a burning flare light point `p` (within flare.radius cells of one, a clear line between)? It counts as an emergency light for what a foe sees.
func flare_lit(p: Vector2) -> bool:
	var r := float(Site.config()["flare"]["radius"])
	for f in flares:
		if float(f["wait"]) <= 0.0 and f["pos"].distance_to(p) <= r and site.clear_line(f["pos"], p):
			return true
	return false


func _tick_flares(dt: float) -> void:
	var keep := []
	for f in flares:
		if float(f["wait"]) > 0.0:
			f["wait"] = float(f["wait"]) - dt
		else:
			f["t"] = float(f["t"]) - dt
		if float(f["t"]) > 0.0:
			keep.append(f)
		else:
			events.append({"type": "flare_out", "id": f["id"]})
	flares = keep


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
	GearActive.tick(self, dt)
	HeatFoot.tick(self, dt)
	var take := func(n: int) -> int: return _take(n)
	for g in guns:
		Arms.tick(g, dt, take)
	foes.tick(dt, aim, light_on)
	quiet_s = 0.0 if hunted() else quiet_s + dt
	Air.tick(self, dt)
	_air_look(dt)
	people.tick(dt)
	beds.tick(dt)
	Party.tick(self, dt)
	_tick_flares(dt)
	_look_around()
	update_doors(float(Arms.cfg()["door_near"]))
	if soldier.is_down() and not downed:
		downed = true
		events.append({"type": "downed", "pos": soldier.pos})
	_check_marks()
	if events.size() > 300:
		events = events.slice(events.size() - 300)


## The air round the soldier: the warning at the airlock once, and the rooms with no air he has seen (the view labels them, air_seen).
func _air_look(dt: float) -> void:
	if not air_warned:
		air_warned = true
		var w := Air.airlock_warning(self)
		if w != "":
			events.append({"type": "line", "text": w})
	_door_note -= dt
	if _door_note <= 0.0:
		for d in site.doors:
			if Air.door_refuses(site, d, soldier) and soldier.pos.distance_to(site.door_centre(d)) <= 2.2:
				_door_note = 3.0
				events.append({"type": "line", "text": Air.NO_SUIT_DOOR})
				break
	for rid in air_seen.keys():
		air_seen[rid] = float(air_seen[rid]) + dt
	for r in site.rooms:
		var rid: int = r["id"]
		if r["purpose"] == "gone" or air_seen.has(rid) or not Air.bad(site.air_of(rid)):
			continue
		var mid: Vector2 = site.centre_of_room(rid)
		if site.room_at(soldier.pos) == rid or (soldier.pos.distance_to(mid) <= float(Arms.cfg()["flash_range"]) and site.clear_line(soldier.pos, mid)):
			air_seen[rid] = 0.0


## Open the doors someone stands near (the soldier, his crew, a foe that is up) and shut the rest; a locked door stays shut. Each change is an event.
func update_doors(near: float) -> void:
	var movers: Array = [{"pos": soldier.pos, "m": soldier}]
	for p in party:
		movers.append({"pos": p["m"].pos, "m": p["m"]})
	for q in people.movers():
		movers.append({"pos": q, "m": null})
	for f in foes.list:
		if not f["dead"] and not f["hidden"] and f["kind"] != "sentry":
			movers.append({"pos": f["m"].pos, "m": null})
	for d in site.doors:
		if d["lock"] == "gone":
			continue
		var mid: Vector2 = site.door_centre(d)
		var want := false
		if door_open_to_soldier(d["id"]):
			for q in movers:
				if q["pos"].distance_to(mid) <= near and not (q["m"] != null and Air.door_refuses(site, d, q["m"])):  # (a door with no air behind it stays shut to the unsealed)
					want = true
					break
		if want != site.grid.is_door_open(d["cells"][0]):
			site.grid.set_door_open(d["cells"][0], want)
			events.append({"type": "door", "id": d["id"], "open": want, "pos": mid})


## G on foot: use the active of the body gear the soldier wears (gear_active.gd). Returns {ok, text}.
func use_active(dir: float) -> Dictionary:
	return GearActive.use(self, dir)


## Seconds of holding E to hack a lock, and to revive a downed crewman: the soldier's gear speeds them (a rigger's harness, a medic's sash).
func hack_time() -> float:
	return float(Site.config()["hack_s"]) / maxf(Kit.gear_num(soldier, "hack", 1.0), 0.1)


func revive_time() -> float:
	return float(Arms.cfg()["revive_s"]) / maxf(Kit.gear_num(soldier, "revive", 1.0), 0.1)


## The soldier repaired the generator: its section is lit and its dead doors open (site.restore_power). Returns how many doors.
func restore_power() -> int:
	var opened_doors: Array = site.restore_power()
	for id in opened_doors:
		unlocked[int(id)] = true
		site.unlock_door(int(id))
	return opened_doors.size()


## Seconds E is held at the generator.
func power_time() -> float:
	return float(StationGen.config().get("power", {}).get("repair_s", 4.0))


## Take the crew named in `names` along (at most party_max of the eligible ones; party.gd). Returns how many came.
func join_party(names: Array) -> int:
	if Air.bad(site.air_of(int(site.airlock["room"]))):  # a crew member with no sealed suit stays aboard the ship rather than step into an airless airlock
		var keep := []
		for src in Party.eligible(ship):
			if names.has(src.name) and Air.sealed(src):
				keep.append(src.name)
			elif names.has(src.name):
				said.append("%s stays aboard: no air, and no sealed suit." % src.name)
		names = keep
	party = Party.join(self, names)
	return party.size()


## Names of the crew who are down, in the party.
func downed_party() -> Array:
	return Party.downed(self).filter(func(p): return not bool(p.get("temp", false))).map(func(p): return str(p["src"].name))


## What a crew member who is left behind takes with them, in words ("Carbine, Basic Armour"), "" for a bare sidearm.
func lost_kit(name: String) -> String:
	for p in party:
		if p["src"] != null and str(p["src"].name) == name:
			return Kit.carried_text(ship, p["src"])
	return ""


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


## `amount` damage to party member `m` (the soldier or a follower's CrewMember), less what their body gear takes (boarding.json `armor`), and what a Brace takes.
## `by` is the foe kind that fired: a Prism Cloak throws back a share of an energy bolt (gear.<item>.deflect, wear.energy_foes) and it does no harm.
func hurt_member(m: CrewMember, amount: float, _from: Vector2, by := "") -> void:
	if m.is_down():
		return
	if by != "" and Site.config()["wear"]["energy_foes"].has(by) and rng.randf() < Kit.gear_num(m, "deflect", 0.0):
		events.append({"type": "deflect", "pos": m.pos})
		return
	var share := Kit.armor_mult(m)
	if m == soldier and brace_t > 0.0:
		share *= float(Site.config()["actives"]["brace"]["share"])
	m.hurt(amount * share)
	events.append({"type": "hurt", "pos": m.pos, "who": "soldier" if m == soldier else "ally", "down": m.is_down()})


## The Hollow may have taken the place: `now` is whether it has. True once, the tick it does while he is aboard (the foes appear then).
func note_hollow(now: bool) -> bool:
	if not now or hollow or hollow_place:
		return false
	hollow = true
	foes.hollow_arrives()
	events.append({"type": "hollow"})
	return true


## What the motion tracker is shown (board_view.gd contacts_source): the foes that are up and out of their vents. A Spotter Cam of Mk II or III in the party
## makes the foes in the rooms it shows ping even standing still.
func contacts() -> Array:
	var out: Array = foes.contacts()
	var cam := Mods.party_tier(self, "spotter_cam")
	if cam > 0 and bool(Mods.numbers("spotter_cam", cam)["tracker"]):
		for c in out:
			if spotted.has(site.room_at(c["pos"])):
				c["moving"] = true
	return out + people.contacts()


## The room he stands in, and the rooms the party's Spotter Cam shows from it (site.rooms_near).
func _look_around() -> void:
	var rid: int = site.room_at(soldier.pos)
	if rid >= 0:
		cur_room = rid
	var cam := Mods.party_tier(self, "spotter_cam")
	spotted = site.rooms_near(cur_room, int(Mods.numbers("spotter_cam", cam)["depth"])) if cam > 0 and cur_room >= 0 else []


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
	cleared = downed or opened_count() >= total()
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
		if site.remembered(id):
			held[str(id)] = left[id].duplicate(true)
	var o: Array = opened.keys().filter(func(id): return site.remembered(id))
	var u: Array = unlocked.keys()
	var k: Array = keys.keys()
	o.sort()
	u.sort()
	k.sort()
	return {"kind": site.kind, "name": site.site_name, "parts": site.parts.duplicate(), "opened": o, "unlocked": u, "keys": k, "left": held, "cleared": cleared,
		"crew": int(spec.get("crew", 0)), "foes": foes.memory(), "theme": site.theme, "people": people.memory(), "marks": seen_marks.keys(), "gen": site.gen, "state": site.state,
		"power": bool(site.power.get("restored", false))}


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


## May the party leave with one click (the Leave button)? Only while nobody has been hunted for leave_quiet_s.
func can_quick_leave() -> bool:
	return not finished and not downed and quiet_s >= float(Arms.cfg()["leave_quiet_s"])


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
	var ctx := {"tier": 1, "stage": 1, "unknown": [], "levels": {}, "logs": [], "log_factions": {}, "faction": ""}
	if campaign != null:
		ctx["tier"] = campaign.tier()
		ctx["stage"] = campaign.stage
		ctx["faction"] = str(campaign.region_data.get("faction", ""))
		for id in campaign.events.logs:
			if not campaign.logs_found.has(id):
				ctx["logs"].append(id)
				ctx["log_factions"][id] = str(campaign.events.logs[id].get("faction", ""))
	if ship != null:
		ctx["ship"] = ship  # (loot.gd picks the blueprint the ship can craft next)
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
## `suit` true marks the choice as one that needs a sealed suit (the wreck's airlock has no air, wreck_site.gd airless_airlock): it shows grey with the reason until the ship has one.
static func offer(ev: Dictionary, kind: String, extra := {}, leave := true, suit := false) -> Dictionary:
	if ev.is_empty() or kind == "":
		return ev
	var text: Dictionary = Site.config()["offer"][kind]
	var out := ev.duplicate(true)
	var choices: Array = out.get("choices", []) if out.get("choices") is Array else []
	var spec := {"kind": kind}
	spec.merge(extra)
	var row := {"text": text["text"], "outcomes": [{"weight": 1, "text": text["flavor"], "effects": {"board": spec}}]}
	if suit:
		row["needs_suit"] = true
	choices.append(row)
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
