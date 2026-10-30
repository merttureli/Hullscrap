extends RefCounted
## The one place crew traits become numbers (docs/CONTENT_PLAN.md section 2). A trait is a bag of generic
## keys in the trait library: data/traits.json plus the traits.json of every pack (the `traits` table of
## data/species.json is still read for ids the library lacks). TraitSet.of(member) merges the bags of the
## member's species (its entry may carry keys inline, merged first), personal and gear traits into one
## Dictionary of numbers, and every rule a key changes asks for it here, so a new race is data only.
## Merging: factors multiply, amounts add, `mechanical` is true if any trait says so, ion_stun and the
## dries_out threshold take the strongest. data/traits.json `_doc` describes the keys too.
## The keys (see KEYS for the sub-keys of the groups):
## - `hp_mult`: factor on the species' max hp (CrewMember.set_species).
## - `speed_mult`: factor on the species' walk speed (CrewMember.set_species).
## - `o2_use`: factor on the air they breathe; 0 = does not breathe, and then cannot suffocate (ShipSim, Jobs).
## - `suffocate_mult`: factor on the damage they take in a room with no air (Jobs).
## - `damage_taken`: factors on damage by source: fire and no_air (Jobs), ion (Jobs.ion_hit), melee and ranged (kept for on-foot fights).
## - `work_mult`: factors on the speed of their work, by job: repair, extinguish, breach, man, heal_others (Jobs); restock, craft (kept).
## - `heal_mult`: factors on what a bed and a medbay heal them (Jobs).
## - `mechanical`: beds do not heal them; a hurt one gets a repair_crew job that any other crew member does (Jobs).
## - `aura`: o2_per_s and heal_per_s for the room they stand in (ShipSim, Jobs), work_mult for the others there (work_rate).
## - `station`: power_bonus, power the part they man gets (Power.solve through station_bonus), and manned_mult (manned_factor).
## - `melee_mult`: factor on their melee damage in on-foot fights (kept: nothing reads it yet).
## - `ranged_mult`: factor on their ranged damage in on-foot fights (kept: nothing reads it yet).
## - `swarm`: work speed +per_other for each other crew member of their species in the room, at most +max (work_rate).
## - `dries_out`: hp_per_s lost in a room whose hottest part is above heat_above (Jobs, Heat.room_heat).
## - `ion_stun`: seconds stunned when an ion hit lands on their room (Jobs.ion_hit).
## The result is shared and cached: read it, do not change it.

const Content = preload("res://scripts/data/content.gd")

const LEGACY_PATH := "res://data/species.json"  ## its `traits` table is the old home of the library
const DAMAGE: Array[String] = ["fire", "no_air", "melee", "ranged", "ion"]
const WORK: Array[String] = ["repair", "extinguish", "breach", "man", "restock", "craft", "heal_others"]
const HEAL: Array[String] = ["bed", "medbay"]
## Every key a trait may use -> its sub-keys ([] for a plain number or flag).
const KEYS := {
	"hp_mult": [], "speed_mult": [], "o2_use": [], "suffocate_mult": [],
	"damage_taken": DAMAGE, "work_mult": WORK, "heal_mult": HEAL, "mechanical": [],
	"aura": ["o2_per_s", "heal_per_s", "work_mult"], "station": ["power_bonus", "manned_mult"],
	"melee_mult": [], "ranged_mult": [], "swarm": ["per_other", "max"],
	"dries_out": ["heat_above", "hp_per_s"], "ion_stun": [],
}
const META: Array[String] = ["id", "name", "blurb", "notes", "override", "reason"]  ## the fields of a trait entry that are not keys
const FACTORS: Array[String] = ["hp_mult", "speed_mult", "o2_use", "suffocate_mult", "melee_mult", "ranged_mult"]
const FACTOR_GROUPS: Array[String] = ["damage_taken", "work_mult", "heal_mult"]
## The old `mult` stats of a trait, as keys (repair_time is a time factor: work_mult repair and breach are 1 / it).
const LEGACY := {"no_air_damage": ["damage_taken", "no_air"], "fire_damage": ["damage_taken", "fire"], "heal_others": ["work_mult", "heal_others"]}

static var _key := ""  # Content root|packs_root the library and cache were built for
static var _library := {}  # trait id -> its entry
static var _cache := {}  # species|traits -> the resolved Dictionary


## Forget the library and every resolved set; the next call reads the data again.
static func reset() -> void:
	_key = ""
	_library = {}
	_cache = {}


## The trait library: id -> entry (data/traits.json, the packs' traits.json, then the legacy table for ids still missing).
## It is the live table: a test may add to it, then call reset() to put it back.
static func library() -> Dictionary:
	_ensure()
	return _library


static func _ensure() -> void:
	var k := Content.root + "|" + Content.packs_root
	if k == _key:
		return
	reset()
	_key = k
	var legacy = Content.read(LEGACY_PATH) if FileAccess.file_exists(LEGACY_PATH) else null
	if legacy is Dictionary and legacy.get("traits") is Dictionary:
		for id in legacy["traits"]:
			if legacy["traits"][id] is Dictionary:
				_library[id] = legacy["traits"][id]
	for e in Content.list("traits"):
		_library[e["id"]] = e


## The numbers of `member` (a CrewMember): species, personal and gear traits merged. Keys and defaults:
## hp_mult, speed_mult, o2_use, suffocate_mult, melee_mult, ranged_mult 1.0; ion_stun 0.0; mechanical false;
## damage_taken {fire, no_air, melee, ranged, ion}, work_mult {repair, extinguish, breach, man, restock, craft,
## heal_others} and heal_mult {bed, medbay} all 1.0; aura {o2_per_s 0, heal_per_s 0, work_mult 1};
## station {power_bonus 0, manned_mult 1}; swarm {per_other 0, max 0}; dries_out {heat_above INF, hp_per_s 0}.
static func of(member) -> Dictionary:
	_ensure()
	var ids: Array = member.traits()
	var key := "%s|%s" % [member.species, ",".join(PackedStringArray(ids))]
	if _cache.has(key):
		return _cache[key]
	var out := _fresh()
	_merge(out, bag_of(Content.entry("species", str(member.species))))
	for id in ids:
		_merge(out, bag_of(_library.get(id, {})))
	if out["mechanical"]:
		out["heal_mult"]["bed"] = 0.0  # a bed does nothing for a machine: the repair_crew job does
	_cache[key] = out
	return out


## The keys of a species or trait entry as a bag: the entries of KEYS it has, plus its old `mult` object
## (no_air_damage, fire_damage, repair_time, heal_others) turned into keys.
static func bag_of(entry: Dictionary) -> Dictionary:
	var bag := {}
	for k in KEYS:
		if entry.has(k):
			bag[k] = entry[k]
	var mult = entry.get("mult")
	if mult is Dictionary:
		for stat in mult:
			var v := float(mult[stat])
			if LEGACY.has(stat):
				_scale(bag, LEGACY[stat][0], LEGACY[stat][1], v)
			elif stat == "repair_time":
				for job in ["repair", "breach"]:
					_scale(bag, "work_mult", job, 1.0 / maxf(v, 0.01))
	return bag


static func _scale(bag: Dictionary, group: String, sub: String, v: float) -> void:
	var g: Dictionary = bag[group].duplicate() if bag.get(group) is Dictionary else {}
	g[sub] = float(g.get(sub, 1.0)) * v
	bag[group] = g


static func _fresh() -> Dictionary:
	var out := {
		"hp_mult": 1.0, "speed_mult": 1.0, "o2_use": 1.0, "suffocate_mult": 1.0, "melee_mult": 1.0, "ranged_mult": 1.0,
		"ion_stun": 0.0, "mechanical": false,
		"aura": {"o2_per_s": 0.0, "heal_per_s": 0.0, "work_mult": 1.0},
		"station": {"power_bonus": 0.0, "manned_mult": 1.0},
		"swarm": {"per_other": 0.0, "max": 0.0},
		"dries_out": {"heat_above": INF, "hp_per_s": 0.0},
	}
	for group in FACTOR_GROUPS:
		out[group] = {}
		for sub in KEYS[group]:
			out[group][sub] = 1.0
	return out


## Fold the bag `bag` into the resolved set `out`.
static func _merge(out: Dictionary, bag: Dictionary) -> void:
	for k in bag:
		var v = bag[k]
		if k in FACTORS:
			out[k] = float(out[k]) * float(v)
		elif k == "ion_stun":
			out[k] = maxf(float(out[k]), float(v))
		elif k == "mechanical":
			out[k] = bool(out[k]) or bool(v)
		elif not v is Dictionary:
			continue
		elif k in FACTOR_GROUPS:
			for sub in v:
				if out[k].has(sub):
					out[k][sub] = float(out[k][sub]) * float(v[sub])
		elif k == "aura" or k == "station" or k == "swarm" or k == "dries_out":
			for sub in v:
				if not out[k].has(sub):
					continue
				var f := float(v[sub])
				if sub in ["work_mult", "manned_mult"]:
					out[k][sub] = float(out[k][sub]) * f
				elif sub == "heat_above":
					out[k][sub] = minf(float(out[k][sub]), f)
				else:
					out[k][sub] = float(out[k][sub]) + f


# --- rules that need the ship ---------------------------------------------------------------------

## How fast `m` does a job of `kind` (WORK) on `ship`, 1.0 being the normal speed: their work_mult for it,
## times the swarm bonus (1 + per_other per other up crew member of their species in their room, at most
## 1 + max), times the aura work_mult of every other up crew member in their room.
static func work_rate(ship, m, kind: String) -> float:
	var t := of(m)
	var rate := float(t["work_mult"].get(kind, 1.0))
	var room: int = ship.atmosphere.room_at(m.cell())
	if room < 0:
		return maxf(rate, 0.0)
	var sw: Dictionary = t["swarm"]
	var kin := 0
	for o in ship.crew:
		if o == m or o.is_down() or ship.atmosphere.room_at(o.cell()) != room:
			continue
		rate *= float(of(o)["aura"]["work_mult"])
		if o.species == m.species:
			kin += 1
	if float(sw["per_other"]) > 0.0:
		rate *= 1.0 + minf(float(sw["max"]), float(sw["per_other"]) * kin)
	return maxf(rate, 0.0)


## What the auras of the up crew give the room each stands in: room id -> {o2_per_s, heal_per_s} (rooms without one are left out).
static func room_auras(ship) -> Dictionary:
	var out := {}
	for m in ship.crew:
		if m.is_down():
			continue
		var a: Dictionary = of(m)["aura"]
		var room: int = ship.atmosphere.room_at(m.cell())
		if room < 0 or (float(a["o2_per_s"]) == 0.0 and float(a["heal_per_s"]) == 0.0):
			continue
		var r: Dictionary = out.get(room, {"o2_per_s": 0.0, "heal_per_s": 0.0})
		r["o2_per_s"] = float(r["o2_per_s"]) + float(a["o2_per_s"])
		r["heal_per_s"] = float(r["heal_per_s"]) + float(a["heal_per_s"])
		out[room] = r
	return out


## The crew member at the post of part `uid` (ship.manned) who is up, or null.
static func operator_of(ship, uid: int):
	var who = ship.manned.get(uid)
	if who == null:
		return null
	for m in ship.crew:
		if m.name == who and not m.is_down():
			return m
	return null


## The power the manned parts get from their operators: part uid -> station.power_bonus (only the nonzero ones).
## Power.solve adds it to the part's figure; Ship.refresh passes it as mods["bonus"].
static func station_bonus(ship) -> Dictionary:
	var out := {}
	for uid in ship.manned:
		var who = operator_of(ship, uid)
		if who != null and float(of(who)["station"]["power_bonus"]) != 0.0:
			out[uid] = float(of(who)["station"]["power_bonus"])
	return out


## The factor on the bonuses a manned post gives (helm evasion, weapon cooldown): the operator's "man" work
## rate times their station.manned_mult; 1.0 when nobody is there.
static func manned_factor(ship, uid: int) -> float:
	var who = operator_of(ship, uid)
	if who == null:
		return 1.0
	return work_rate(ship, who, "man") * float(of(who)["station"]["manned_mult"])
