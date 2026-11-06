extends RefCounted
## What a part says about itself (data/describe.json holds the words). One description, short, in five parts, shown by the
## selection card (hud_card.gd, through palette.gd) and by the crafting panel's selected recipe:
##   what      what its family does, 8 words at most
##   stats     [label, value] pairs for the stats the part has (read from the part's stats, weapons.json, flight.json,
##             crew.json and the shield timing: the numbers the game itself uses, not copies)
##   keywords  one per mechanic it has (keyword(): label, colour, hover line): its weapon kind, its damage type, AUTO, RAPID ...
##   lore      the first sentence of its blurb
##   cost      its recipe's materials ({id: n}, {} when it has none), and level: the fabricator level it needs
## The same keyword is shown in the same colour on the card, the palette's weapon cards and the combat weapon bar.
## Pure logic, no nodes: tests/test_describe.gd checks it.

const Weapons = preload("res://scripts/combat/weapons.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Flight = preload("res://scripts/sim/flight.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Content = preload("res://scripts/data/content.gd")
const Mods = preload("res://scripts/board/mods.gd")

const PATH := "res://data/describe.json"
const STAT_NAMES := {"rate": "fire rate", "damage": "damage"}
const KEY_NAMES := {"engine": "Shift", "shield": "Space", "utility": "E"}  ## the ability keys (weapon_bar.gd KEY_LABEL)
const MINUS := "\u2212"

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


## The description of id `id` on `ship`: {what, stats, keywords, lore, cost, level}. A part gets all of it; a material, an item
## or gear gets its line, its lore and its recipe. `rot`: the quarter turns an engine is held at (-1: not known; says how
## each wall uses it).
static func of(id: String, ship, rot := -1, angle := -1.0) -> Dictionary:
	var out := {"what": "", "stats": [], "keywords": [], "lore": "", "cost": {}, "level": 0}
	if ship.crafting.has(id):
		var r: Dictionary = ship.crafting.def(id)
		out["cost"] = r.get("materials", {})
		out["level"] = int(r.get("fab_level", 1))
	if not ship.components.has(id):
		return _of_item(id, out)
	var def: Dictionary = ship.components.def(id)
	var eff: Dictionary = ship.effective(id)
	var fam := str(def.get("family", ""))
	var words := "medbay_arm" if fam == "medbay" and float(def.get("stats", {}).get("reach", 0.0)) > 0.0 else fam  # a healing arm, not the bed
	out["what"] = fill(str(data()["families"].get(words, "")), {"break_delay": Abilities.shield_break_delay()})
	out["lore"] = first_sentence(str(def.get("blurb", "")))
	var rows: Array = out["stats"]
	var kws: Array = out["keywords"]
	var mount := Mounts.is_mount(def)
	var tail := []  # a turret's or a fixed gun's aim, after the size
	if fam == "weapon":
		_weapon(id, rows, kws, tail)
		if weapons().has(id) and str(weapons().defs[id].get("version", "")) != "":
			out["what"] = str(weapons().defs[id]["version"])  # the card names the version and what it does
	else:
		_stats(def, eff, fam, rot, rows, angle)
	if fam == "drone_bay":
		rows.append(["Launches", "tier %d and below" % int(def["bay"]["max_tier"])])
		rows.append(["Re-arm", "%s s (25%% quicker with crew)" % num(float(def["bay"]["rearm_s"]))])
	var pw := float(eff["power"])
	if pw != 0.0:
		rows.append(["Power", ("+" if pw > 0.0 else MINUS) + num(absf(pw))])
	rows.append(["HP", "%d%s" % [eff["hp"], " (out %d)" % int(def["mount"]["outside_hp"]) if mount else ""]])
	var size: Array = def["size"]
	rows.append(["Size", "%d\u00d7%d" % [size[0], size[1]] + (" (out %d\u00d7%d)" % [def["mount"]["outside"][0], def["mount"]["outside"][1]] if mount else "")])
	rows.append_array(tail)
	if def.get("manned", false):
		kws.append(keyword("manned"))
	if float(eff["heat_per_s"]) > float(eff["cooling"]):
		kws.append(keyword("hot"))
	if def.get("line", "") == "scrap":
		kws.append(keyword("faulty", {"n": float(eff["malfunction_per_min"])}))
	elif def.get("line", "") == "neon":
		kws.append(keyword("ion_weak", {"n": float(eff["ion_vulnerability"])}))
	for a in def.get("abilities", []):
		if str(a.get("type", "")) != "passive":
			kws.append(keyword("ability", {"name": str(a.get("name", a.get("id", ""))), "key": str(KEY_NAMES.get(a.get("key", ""), str(a.get("key", "?")).capitalize())),
				"duration": float(a.get("duration", 0)), "cooldown": float(a.get("cooldown", 0))}))
	if str(def.get("quirk", "")) != "":
		kws.append(keyword("quirk", {"quirk": str(def["quirk"])}))
	return out


## What a picture card shows of part `id` instead of its name: {stats: [{icon, text, what}] (two or three figures, chosen by family: a gun's
## damage, rate and range; a shield's layers and recharge; an engine's thrust; a reactor's power; any other part's hp and power), aim:
## "fixed", "swivel", "turret" for a gun (read from its weapons.json entry, so a new aim class shows by its name), else ""}.
static func glance(id: String, ship) -> Dictionary:
	var out := {"stats": [], "aim": ""}
	if not ship.components.has(id):
		return out
	var def: Dictionary = ship.components.def(id)
	var eff: Dictionary = ship.effective(id)
	var st: Dictionary = eff["stats"]
	var rows: Array = out["stats"]
	match str(def.get("family", "")):
		"weapon":
			if weapons().has(id):
				var w: Dictionary = weapons().def(id)
				var beam: bool = w["kind"] == "beam"
				rows.append({"icon": "st_damage", "text": num(float(w["damage"]) * (1.0 if beam else maxf(1.0, float(w["shots"])))) + ("/s" if beam else ""), "what": "Damage"})
				rows.append({"icon": "st_rate", "text": num(snappedf(1.0 / maxf(float(w["cooldown"]), 0.05), 0.1)), "what": "Shots a second"})
				rows.append({"icon": "st_range", "text": num(float(w["range"])), "what": "Range"})
				out["aim"] = str(w.get("aim", "turret" if w["turret"] else "fixed"))
		"shield":
			rows.append({"icon": "st_layers", "text": num(float(st.get("layers", 1.0))), "what": "Layers"})
			rows.append({"icon": "st_recharge", "text": num(float(st.get("recharge", Abilities.shield_base()))) + "s", "what": "Recharge"})
		"engine":
			rows.append({"icon": "st_thrust", "text": num(float(st.get("thrust", 0.0))), "what": "Thrust"})
		_:
			var pw := float(eff["power"])
			if pw != 0.0:
				rows.append({"icon": "power", "text": ("+" if pw > 0.0 else MINUS) + num(absf(pw)), "what": "Power"})
			rows.append({"icon": "st_hp", "text": str(eff["hp"]), "what": "HP"})
	if str(def.get("family", "")) in ["engine", "shield", "weapon"] and rows.size() < 3:
		rows.append({"icon": "st_hp", "text": str(eff["hp"]), "what": "HP"})
	return out


## The description as plain text, a line each (what tests and plain readers get).
static func text(id: String, ship, rot := -1, angle := -1.0) -> String:
	var d := of(id, ship, rot, angle)
	var lines: Array[String] = [d["what"]]
	for r in d["stats"]:
		lines.append("%s: %s" % [r[0], r[1]])
	for k in d["keywords"]:
		lines.append("%s: %s" % [k["label"], k["hover"]])
	lines.append(d["lore"])
	return "\n".join(lines.filter(func(l): return l != ""))


## Keyword `id` ready to show: {id, label (upper case), color, hover}, its {holes} filled from `vals` ({} for an unknown id).
static func keyword(id: String, vals := {}) -> Dictionary:
	var k: Dictionary = data()["keywords"].get(id, {})
	if k.is_empty():
		return {}
	return {"id": id, "label": fill(str(k["label"]), vals).to_upper(), "color": Color(str(k["color"])), "hover": fill(str(k["hover"]), vals)}


## The weapon kind ("laser", "bolt", "flak", "missile", "beam") of weapon id `id`, or "" when it is not a weapon.
static func weapon_kind(id: String) -> String:
	return str(weapons().def(id)["kind"]) if weapons().has(id) else ""


## The kind of weapon `id` as a keyword, and AUTO after it for a turret: what the palette's cards and the weapon bar show.
static func weapon_tags(id: String) -> Array:
	if not weapons().has(id):
		return []
	var out := [keyword(weapon_kind(id))]
	if weapons().def(id)["turret"]:
		out.append(keyword("auto"))
	return out


## `s` up to its first sentence.
static func first_sentence(s: String) -> String:
	var at := -1
	for sep in [". ", "! ", "? "]:
		var i := s.find(sep)
		if i >= 0 and (at < 0 or i < at):
			at = i
	return s.substr(0, at + 1) if at >= 0 else s


static func _of_item(id: String, out: Dictionary) -> Dictionary:
	var item: Dictionary = Content.entry("items", id)
	var kind := str(item.get("kind", "")) if not item.is_empty() else ("material" if Content.has("materials", id) else "")
	out["what"] = str(item.get("does", data()["items"].get(kind, "")))
	out["lore"] = first_sentence(str(item.get("blurb", Content.entry("materials", id).get("blurb", ""))))
	if kind == "drone" and item.get("drone") is Dictionary:  # a drone kit: its tier, hp, role and what a launch costs
		var dd: Dictionary = item["drone"]
		var roles := {"defence": "defence: guards your ship", "combat": "combat: circles the foe", "limpet": "limpet: clamps to the hull and works on the room behind", "boarder": "boarder: cuts in and drops a robot"}
		out["stats"] = [["Tier", str(dd["tier"])], ["HP", str(dd["hp"])], ["Role", str(roles.get(str(dd["role"]), str(dd["role"])))],
			["Launch", "%d part%s" % [dd["tier"], "" if int(dd["tier"]) == 1 else "s"]]]
		if dd.get("gun") is Dictionary:
			out["stats"].append(["Fires", "%s every %s s" % [str(dd["gun"].get("family", "")), num(float(dd["gun"]["cooldown"]))]])
		elif dd.get("effect") is Dictionary:
			out["stats"].append(["Works", "%s for %s s" % [str(dd["effect"]["kind"]), num(float(dd["effect"]["seconds"]))]])
	if kind == "mod" and Mods.is_item(id):  # a boarding mod: what it does, the numbers of its tier and who they work for
		var h := Mods.hover(id)
		out["what"] = str(h[0])
		var p := Mods.parse(id)
		out["stats"] = [Mods.numbers(p["mod"], int(p["tier"]))["stat"].duplicate(), ["Worn by", "the party" if Mods.def(p["mod"])["scope"] == "party" else "the wearer"]]
		out["keywords"] = [keyword("mod")]
	return out


# --- stats -------------------------------------------------------------------------------------------------

## The rows of the stats a non-weapon part has, from data/describe.json `stats`.
static func _stats(def: Dictionary, eff: Dictionary, fam: String, rot: int, rows: Array, angle := -1.0) -> void:
	var st: Dictionary = eff["stats"]
	var table: Dictionary = data()["stats"]
	for k in st:
		var v := float(st[k])
		var t: Array = table.get(k, [str(k).replace("_", " ").capitalize(), "{v}"])
		if v == 0.0 or str(t[1]) == "skip" or (t.size() > 2 and t[2] == "if_not_1" and is_equal_approx(v, 1.0)):
			continue
		rows.append([t[0], str(t[1]).replace("{v}", big(v) if k == "radar_range" else num(v))])
		if k == "thrust":
			rows.append(["Push", _pushes(v, rot, angle)])
	match fam:
		"shield":
			if not st.has("recharge"):
				rows.append(["Recharge", str(table["recharge"][1]).replace("{v}", num(Abilities.shield_base()))])
		"medbay":
			rows.append(["Heals", "%s hp/s" % num(float(CrewMember.config()["heal_per_s"]["medbay"]) * float(st.get("heal", 1.0)))])
		"bed":
			rows.append(["Heals", "%s hp/s" % num(float(CrewMember.config()["heal_per_s"]["bed"]))])


## Where an engine's thrust `t` goes at `rot` (the nozzle's turn), or along `angle` (degrees, an engine on a sloped face: R does not
## turn it): forward and sideways, as Flight.thrusts_of splits it.
static func _pushes(t: float, rot: int, angle := -1.0) -> String:
	var share := num(t * _side_share())
	if rot < 0 and angle < 0.0:
		return "forward, +%s side" % share
	var part := Flight.split(t, -(Mounts.normal_of(angle) if angle >= 0.0 else Vector2(Mounts.outward(rot))))
	if angle >= 0.0:
		return "%s %s, %s side" % [num(absf(part.y)), "fwd" if part.y > 0.0 else "back", num(absf(part.x))]
	if absf(part.x) > absf(part.y):
		return "%s side, %s back" % [num(absf(part.x)), share]
	if part.y > 0.0:
		return "%s fwd, %s side" % [num(part.y), share]
	return "brakes: turn it (R)"


# --- weapons -----------------------------------------------------------------------------------------------

## The rows and the keywords of weapon `id` (weapons.json, defaults merged: weapons.gd def); `tail`: its aim rows, which
## come after the size.
static func _weapon(id: String, rows: Array, kws: Array, tail: Array) -> void:
	if not weapons().has(id):
		return
	var w: Dictionary = weapons().def(id)
	var shots := int(w["shots"])
	var dmg := num(float(w["damage"]))
	if w["kind"] == "beam":
		dmg += "/s \u00d7%s s" % num(float(w["duration"]))
	elif shots > 1:
		dmg += " \u00d7%d" % shots
	rows.append(["Damage", dmg])
	rows.append(["Every", "%s s" % num(float(w["cooldown"]))])
	rows.append(["Range", num(float(w["range"]))])
	if w["turret"]:
		tail.append(["Arc", "%s\u00b0" % num(float(w["arc"]))])
		tail.append(["Track", "%s\u00b0/s" % num(float(w["track"]))])
		tail.append(["Hit", "%s%%" % num(float(w["accuracy"]) * 100.0)])
	else:
		tail.append(["Gimbal", "%s\u00b0" % num(float(w["gimbal"]))])
		tail.append(["Fire", ["AUTO", "LMB", "RMB", "Q"][weapons().group_of(id)]])
	kws.append(keyword(str(w["kind"])))
	kws.append(keyword(str(w["damage_type"])))
	if w["turret"]:
		kws.append(keyword("auto"))
	if w.get("rapid", false):
		kws.append(keyword("rapid"))
	if w["pass_shields"]:
		kws.append(keyword("pass_shields"))
	if w.get("chain") is Dictionary:
		kws.append(keyword("chain", w["chain"]))
	if w.get("charge") is Dictionary:
		kws.append(keyword("charge", w["charge"]))
	if int(w["pierce"]) > 0:
		kws.append(keyword("pierce", {"n": w["pierce"]}))
	if float(w["splash"]) > 0.0:
		kws.append(keyword("splash", {"n": w["splash"]}))
	if float(w["fire_chance"]) > 0.0:
		kws.append(keyword("fire", {"p": float(w["fire_chance"]) * 100.0}))
	if str(w["ammo"]) != "":
		kws.append(keyword("ammo", {"ammo": str(w["ammo"])}))
	if float(w["jam_chance"]) > 0.0:
		kws.append(keyword("jam", {"p": float(w["jam_chance"]) * 100.0}))
	if float(w["heat_per_shot"]) > 0.0:
		kws.append(keyword("heat", {"n": w["heat_per_shot"]}))
	if float(w.get("breach_chance", 0.0)) > 0.0:
		kws.append(keyword("breach", {"p": float(w["breach_chance"]) * 100.0}))
	var e := Effects.of(w)
	for k in e:
		if not (k in data()["idle"]):
			kws.append(keyword(str(k), _effect_vals(str(k), e[k])))


## The numbers an effect's keyword fills its holes with: the effect's own object (or a number for ammo_mult), and what
## the label and the hover line need besides.
static func _effect_vals(key: String, v) -> Dictionary:
	if not v is Dictionary:
		return {key: v}
	var vals: Dictionary = v.duplicate()
	match key:
		"corrode":
			vals["inv"] = 1.0 / maxf(float(v.get("resist_mult", 1.0)), 0.01)
		"needs_operator":
			var who = v.get("species", "")
			vals["who"] = " or ".join((who if who is Array else [who]).map(func(s): return str(s).capitalize())) if who != "" else "crew member"
	if key in ["needs_operator", "needs_crew_in_room"]:
		vals["stat"] = STAT_NAMES.get(str(v.get("stat", "damage" if key == "needs_operator" else "rate")), "damage")
		vals["count"] = float(v.get("count", 1))
	return vals
