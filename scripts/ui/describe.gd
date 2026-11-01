extends RefCounted
## What a part says about itself (data/describe.json holds the words). One description, in four parts, shown by the
## selection card (hud_card.gd, through palette.gd) and by the crafting panel's selected recipe:
##   does   what its family does, one sentence
##   rows   its stats, [label, value] for the ones the part has (read from the part's stats, weapons.json, flight.json,
##          crew.json and the shield timing: the numbers the game itself uses, not copies)
##   kinds  what its type means: the weapon kind, the damage type, each trait and effect it carries (lines)
##   notes  the part's own quirk text and the line's (Scrap, Neon) notes
##   lore   its blurb
## Pure logic, no nodes: tests/test_describe.gd checks it.

const Weapons = preload("res://scripts/combat/weapons.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/describe.json"
const STAT_NAMES := {"rate": "fire rate", "damage": "damage"}

static var _data := {}
static var _weapons: Weapons
static var _flight: Flight


## data/describe.json (read once).
static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d
	return _data


## A number: whole ones plain, others with up to two decimals (2.65, 4.5).
static func num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s


## A whole number with thousands commas (6,000).
static func big(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


## `tpl` with {key} filled by num() (or the text of a String) and {key%} by a percent.
static func fill(tpl: String, vals: Dictionary) -> String:
	var out := tpl
	for k in vals:
		var v = vals[k]
		if v is String:
			out = out.replace("{%s}" % k, v)
		elif v is int or v is float:
			out = out.replace("{%s%%}" % k, num(float(v) * 100.0)).replace("{%s}" % k, num(float(v)))
	return out


static func weapons() -> Weapons:
	if _weapons == null:
		_weapons = Weapons.new()
	return _weapons


static func _side_share() -> float:
	if _flight == null:
		_flight = Flight.new()
	return _flight.side_share


## The description of id `id` on `ship`: {does, rows, kinds, notes, lore}. A part gets all of it; a material, an item or
## gear gets its line and its lore. `rot`: the quarter turns an engine is held at (-1: not known; says how each wall
## uses it).
static func of(id: String, ship, rot := -1) -> Dictionary:
	if not ship.components.has(id):
		return _of_item(id)
	var def: Dictionary = ship.components.def(id)
	var eff: Dictionary = ship.effective(id)
	var fam := str(def.get("family", ""))
	var out := {"does": fill(str(data()["families"].get(fam, "")), {"break_delay": Abilities.shield_break_delay()}),
		"rows": [], "kinds": [], "notes": [], "lore": str(def.get("blurb", ""))}
	var rows: Array = out["rows"]
	var size: Array = def["size"]
	rows.append(["Size", "%dx%d" % [size[0], size[1]] + (" + %dx%d outside" % [def["mount"]["outside"][0], def["mount"]["outside"][1]] if Mounts.is_mount(def) else "")])
	var pw := float(eff["power"])
	if pw != 0.0:
		rows.append(["Power", ("makes " if pw > 0.0 else "draws ") + num(absf(pw))])
	rows.append(["HP", "%d%s" % [eff["hp"], " (outside %d)" % int(def["mount"]["outside_hp"]) if Mounts.is_mount(def) else ""]])
	if fam == "weapon":
		_weapon(id, rows, out["kinds"])
	else:
		_stats(def, eff, fam, rot, rows)
	rows.append(["Heat", "%s/s, cools %s/s, limit %s" % [num(eff["heat_per_s"]), num(eff["cooling"]), num(eff["heat_limit"])]])
	if def.get("manned", false):
		rows.append(["Crew", "works better manned"])
	var notes: Array = out["notes"]
	if str(def.get("quirk", "")) != "":
		notes.append(str(def["quirk"]))
	if def.get("line", "") == "scrap":
		notes.append("Scrap line: malfunctions more often (%s a minute)." % num(eff["malfunction_per_min"]))
	elif def.get("line", "") == "neon":
		notes.append("Neon line: ion hits do x%s." % num(eff["ion_vulnerability"]))
	return out


## The description as plain text, a line each (what tests and plain readers get).
static func text(id: String, ship, rot := -1) -> String:
	var d := of(id, ship, rot)
	var lines: Array[String] = [d["does"]]
	for r in d["rows"]:
		lines.append("%s: %s" % [r[0], r[1]])
	lines.append_array(d["kinds"])
	lines.append_array(d["notes"])
	lines.append(d["lore"])
	return "\n".join(lines.filter(func(l): return l != ""))


static func _of_item(id: String) -> Dictionary:
	var item: Dictionary = Content.entry("items", id)
	var kind := str(item.get("kind", "")) if not item.is_empty() else ("material" if Content.has("materials", id) else "")
	var blurb := str(item.get("blurb", Content.entry("materials", id).get("blurb", "")))
	return {"does": str(data()["items"].get(kind, "")), "rows": [], "kinds": [], "notes": [], "lore": blurb}


# --- stats -------------------------------------------------------------------------------------------------

## The rows of the stats a non-weapon part has, from data/describe.json `stats`.
static func _stats(def: Dictionary, eff: Dictionary, fam: String, rot: int, rows: Array) -> void:
	var st: Dictionary = eff["stats"]
	var table: Dictionary = data()["stats"]
	for k in st:
		var v := float(st[k])
		var t: Array = table.get(k, [str(k).replace("_", " ").capitalize(), "{v}"])
		if v == 0.0 or str(t[1]) == "skip" or (t.size() > 2 and t[2] == "if_not_1" and is_equal_approx(v, 1.0)):
			continue
		rows.append([t[0], str(t[1]).replace("{v}", big(v) if k == "radar_range" else num(v))])
		if k == "thrust":
			rows.append(["Pushes", _pushes(v, rot)])
	match fam:
		"shield":
			if not st.has("recharge"):
				rows.append(["Recharge", str(table["recharge"][1]).replace("{v}", num(Abilities.shield_base()))])
		"medbay":
			rows.append(["Heals", "%s hp a second" % num(float(CrewMember.config()["heal_per_s"]["medbay"]) * float(st.get("heal", 1.0)))])
		"bed":
			rows.append(["Heals", "%s hp a second" % num(float(CrewMember.config()["heal_per_s"]["bed"]))])


## Where an engine's thrust `t` goes at `rot` (the nozzle's turn): forward and sideways, as Flight.thrusts_of splits it.
static func _pushes(t: float, rot: int) -> String:
	var share := num(t * _side_share())
	if rot < 0:
		return "rear wall: forward; side wall: sideways only. Every engine adds %s sideways either way" % share
	var part := Flight.split(t, -Vector2(Mounts.outward(rot)))
	if absf(part.x) > absf(part.y):
		return "sideways only: %s one way, %s the other" % [num(absf(part.x)), share]
	if part.y > 0.0:
		return "%s forward, %s sideways either way" % [num(part.y), share]
	return "like this it only brakes: turn it (R) so the nozzle points back. %s sideways either way" % share


# --- weapons -----------------------------------------------------------------------------------------------

## The rows and the type lines of weapon `id` (weapons.json, defaults merged: weapons.gd def).
static func _weapon(id: String, rows: Array, kinds: Array) -> void:
	if not weapons().has(id):
		return
	var w: Dictionary = weapons().def(id)
	var d: Dictionary = data()
	var shots := int(w["shots"])
	var beam: bool = w["kind"] == "beam"
	var per := " a second for %s s" % num(float(w["duration"])) if beam else (" a volley" if shots > 1 else " a shot")
	rows.append(["Damage", "%s%s %s%s" % [num(float(w["damage"])), " x %d" % shots if shots > 1 else "", w["damage_type"], per]])
	rows.append(["Fires", "every %s s" % num(float(w["cooldown"]))])
	rows.append(["Range", "%s px" % num(float(w["range"]))])
	if w["turret"]:
		rows.append(["Aim", fill(d["effects"]["turret"], {"arc": w["arc"], "track": w["track"], "accuracy": w["accuracy"]})])
	else:
		rows.append(["Aim", fill(d["effects"]["fixed"], {"gimbal": w["gimbal"]})])
		rows.append(["Fire with", "%s (group %d), or its number key" % ["left mouse" if weapons().group_of(id) == 1 else "right mouse", weapons().group_of(id)]])
	kinds.append(str(d["kinds"].get(w["kind"], "")))
	kinds.append(str(d["damage"].get(w["damage_type"], "")))
	var fx: Dictionary = d["effects"]
	if w.get("rapid", false):
		kinds.append(fx["rapid"])
	if int(w["pierce"]) > 0:
		kinds.append(fill(fx["pierce"], {"n": w["pierce"]}))
	if float(w["fire_chance"]) > 0.0:
		kinds.append(fill(fx["fire"], {"p": float(w["fire_chance"]) * 100.0}))
	if float(w["splash"]) > 0.0:
		kinds.append(fill(fx["splash"], {"n": w["splash"]}))
	if w["pass_shields"] and w["kind"] != "missile":
		kinds.append(fx["pass_shields"])
	if str(w["ammo"]) != "":
		kinds.append(fill(fx["ammo"], {"ammo": str(w["ammo"])}))
	if float(w["jam_chance"]) > 0.0:
		kinds.append(fill(fx["jam"], {"p": float(w["jam_chance"]) * 100.0}))
	if float(w["heat_per_shot"]) > 0.0:
		kinds.append(fill(fx["heat"], {"n": w["heat_per_shot"]}))
	if float(w.get("breach_chance", 0.0)) > 0.0:
		kinds.append(fill(fx["breach"], {"p": float(w["breach_chance"]) * 100.0}))
	var e := Effects.of(w)
	for k in e:
		if not (k in d["idle"]):
			kinds.append(_effect_line(str(k), e[k]))


## The line of effect `key` with the numbers `v` (an effect's object, or a number for ammo_mult).
static func _effect_line(key: String, v) -> String:
	var tpl := str(data()["effects"].get(key, ""))
	if not v is Dictionary:
		return fill(tpl, {key: v})
	var vals: Dictionary = v.duplicate()
	match key:
		"acid":
			vals["spread"] = float(v.get("spread", 0.0))
		"corrode":
			vals["inv"] = 1.0 / maxf(float(v.get("resist_mult", 1.0)), 0.01)
		"needs_operator":
			var who = v.get("species", "")
			vals["who"] = " or ".join((who if who is Array else [who]).map(func(s): return str(s).capitalize())) if who != "" else "crew member"
		"self_room":
			var parts := []
			for pk in data()["self_room_parts"]:
				if float(v.get(pk, 0.0)) > 0.0:
					parts.append(fill(data()["self_room_parts"][pk], {"v": float(v[pk])}))
			vals["parts"] = ", ".join(parts)
	if key in ["needs_operator", "needs_crew_in_room"]:
		vals["stat"] = STAT_NAMES.get(str(v.get("stat", "damage" if key == "needs_operator" else "rate")), "damage")
		vals["count"] = float(v.get("count", 1))
	return fill(tpl, vals)
