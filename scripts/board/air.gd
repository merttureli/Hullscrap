extends RefCounted
## Air on foot (docs/BOARDING.md, Beta 4.1): every room of a site has a pressure (site.gd air_of; a beaten ship's rooms keep the pressure the fight left, a generated
## site's are 1) and it does not change during a visit. Pure logic over the session (boarding.gd), whose tick() calls tick() here.
## - A person in a room under crew.json `air.breath_ok` takes the ship's no-air damage a second (`damage_per_s.no_air`, with their traits: suffocate_mult,
##   damage_taken.no_air, vacuum_walk, o2_use 0, the `suit` trait). Body gear that is `sealed` (boarding.json `gear`) stops it. Armour does not soften it.
## - The soldier, his followers and the foes breathe the same way (a foe with `sealed` in its data wears a suit; a crew member of a beaten ship is sealed by their gear).
## - A follower with no seal does not follow into an airless room: wait() keeps them at its door and says so.
## - line() is the AIR line of a card: OK, THIN or NONE, and the seconds the person has left in that air.

const Site = preload("res://scripts/board/site.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const HURT_EVERY := 1.6  ## seconds between the cries of the soldier choking
const NO_SUIT_DOOR := "No air past this door. You need a sealed suit."
const NO_SUIT_BOARD := "Her air is gone. You need a sealed suit."


static func _air() -> Dictionary:
	return CrewMember.config().get("air", {})


## The pressure a person needs in their room to breathe (crew.json air.breath_ok).
static func breath_ok() -> float:
	return float(_air().get("breath_ok", 0.5))


## Is the pressure `p` too thin to breathe?
static func bad(p: float) -> bool:
	return p < breath_ok()


## "OK", "THIN" (under breath_ok) or "NONE" (under crew.json no_air_below, the room is airless).
static func word(p: float) -> String:
	if p >= breath_ok():
		return "OK"
	return "THIN" if p >= float(CrewMember.config().get("no_air_below", 0.15)) else "NONE"


## Does person `m` wear body gear that is sealed (boarding.json `gear`)?
static func suited(m) -> bool:
	return bool(Site.config().get("gear", {}).get(str(m.kit.get("body", "")), {}).get("sealed", false))


## Can the air not hurt `m`: a sealed suit, or a body that needs none (vacuum_walk, o2_use 0, the suit trait, a drone)?
static func sealed(m) -> bool:
	return suited(m) or Jobs.air_exempt(m)


## Hp a second the air costs `m` in a room under breath_ok (0 for anyone it cannot hurt).
static func rate(m) -> float:
	return 0.0 if suited(m) else Jobs.suffocation(m)


## The AIR line of person `m` at point `pos` of `site`: {word, secs (seconds to live in this air, -1 when it does not hurt them), sealed}.
static func line(site, m, pos: Vector2) -> Dictionary:
	var p: float = site.air_at(pos)
	var w := word(p)
	var r := rate(m)
	var secs := -1.0
	if bad(p) and r > 0.0:
		secs = maxf(m.hp, 0.0) / r
	return {"word": w, "secs": secs, "sealed": bad(p) and r <= 0.0}


## Does the ship's hold hold a sealed suit, or does its soldier wear one (or need none)?
static func has_suit(ship) -> bool:
	if ship == null:
		return false
	for m in ship.crew:
		if m.is_player and sealed(m):
			return true
	for item in ship.inventory.counts:
		if ship.inventory.count(str(item)) > 0 and bool(Site.config().get("gear", {}).get(str(item), {}).get("sealed", false)):
			return true
	return false


## Is door `d` of the site shut to person `m`: they have no seal and a room it joins has no air?
static func door_refuses(site, d: Dictionary, m) -> bool:
	if d["lock"] == "gone" or sealed(m):
		return false
	for r in d["rooms"]:
		if bad(site.air_of(int(r))):
			return true
	return false


## `dt` seconds pass: the soldier, the followers and the foes lose hp in a room with no air, unless they are sealed.
static func tick(s, dt: float) -> void:
	var site = s.site
	_breathe(s, s.soldier, dt, "soldier")
	for p in s.party:
		_breathe(s, p["m"], dt, "ally")
	for f in s.foes.list:
		if f["dead"] or f["hidden"] or f["team"] != "foe" or bool(f.get("sealed", f["d"].get("sealed", false))):
			continue
		if bad(site.air_at(f["m"].pos)):
			var r := rate(f["m"])
			if r > 0.0:
				s.foes.suffocate(f, r * dt)


static func _breathe(s, m: CrewMember, dt: float, who: String) -> void:
	if m.is_down() or not bad(s.site.air_at(m.pos)):
		return
	var r := rate(m)
	if r <= 0.0:
		return
	m.hurt(r * dt)
	if who == "soldier":
		s.air_t = float(s.air_t) + dt
		if float(s.air_t) >= HURT_EVERY or m.is_down():
			s.air_t = 0.0
			s.events.append({"type": "hurt", "pos": m.pos, "who": who, "down": m.is_down()})


# --- followers at the door ------------------------------------------------------------------------------------------------

## Should follower `p` (party.gd) stop rather than walk into an airless room? True when the next step of its path enters a room with bad air and the follower
## is in good air with no seal. `s` is the session.
static func holds(s, p: Dictionary) -> bool:
	var m: CrewMember = p["m"]
	if sealed(m) or bad(s.site.air_at(m.pos)) or m.path.is_empty():
		return false
	for a in m.path:  # the anchors it will step on, the body's centre is the anchor plus (1, 1)
		var c := Vector2(a) + Vector2(m.body_size, m.body_size) * 0.5
		if bad(s.site.air_at(c)):
			return true
		if not bad(s.site.air_at(c)) and s.site.room_at(c) != s.site.room_at(m.pos) and s.site.room_at(c) >= 0:
			break  # a room with air next: the walk goes on, and is looked at again then
	return false


## Keep follower `p` at the door if it must (holds): its path is dropped and it says so once per stop. Returns whether it waits.
static func wait(s, p: Dictionary) -> bool:
	if not holds(s, p):
		if not p["m"].path.is_empty():
			p["waiting"] = false
		return false
	p["m"].path.clear()
	if not bool(p.get("waiting", false)):
		p["waiting"] = true
		s.events.append({"type": "line", "text": "%s waits at the door: no air, and no sealed suit." % str(p["m"].name)})
	return true


## The words to warn the party at the airlock: "" when all is well, else which room has no air and who has no suit. Looks at the airlock's own room and the rooms
## its doors lead to.
static func airlock_warning(s) -> String:
	var site = s.site
	var rooms: Array = [int(site.airlock["room"])]
	rooms.append_array(site.rooms_near(int(site.airlock["room"]), 1))
	var thin := false
	for r in rooms:
		if bad(site.air_of(int(r))):
			thin = true
			break
	if not thin:
		return ""
	var bare := []
	if not sealed(s.soldier):
		bare.append(str(s.soldier.name))
	for p in s.party:
		if not sealed(p["m"]):
			bare.append(str(p["m"].name))
	if bare.is_empty():
		return ""
	var where := "The airlock has no air" if bad(site.air_of(int(site.airlock["room"]))) else "The next room has no air"
	return "%s. No sealed suit: %s." % [where, ", ".join(bare)]
