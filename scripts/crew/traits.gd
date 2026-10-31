extends RefCounted
## The one place crew traits become numbers (docs/CONTENT_PLAN.md section 2). A trait is a bag of generic
## keys in the trait library: data/traits.json plus the traits.json of every pack (the `traits` table of
## data/species.json is still read for ids the library lacks). TraitSet.of(member) merges the bags of the
## member's species (its entry may carry keys inline, merged first), personal and gear traits into one
## Dictionary of numbers, and every rule a key changes asks for it here, so a new race is data only.
## Merging: factors multiply, amounts add, `mechanical` is true if any trait says so, ion_stun and the
## dries_out threshold take the strongest, the true/false keys (FLAGS) are true if any trait says so, `body` takes the smallest.
## Inside a group amounts add, except: the heat thresholds take the widest; a time that starts something (hull_mend.seal, revive_once.after, split_on_death.reform_s) takes the quickest one that is set (0 = not set); revive_once.hp takes the highest.
## data/traits.json `_doc` describes the keys too.
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
## - `station`: power_bonus, power the part they man gets (Power.solve through station_bonus), manned_mult (manned_factor), and evasion_add (evasion the helm gets while they man it, Jobs.evasion_bonus through helm_evasion_add).
## - `melee_mult`: factor on their melee damage in on-foot fights (kept: nothing reads it yet).
## - `ranged_mult`: factor on their ranged damage in on-foot fights (kept: nothing reads it yet).
## - `swarm`: work speed +per_other for each other crew member of their species in the room, at most +max (work_rate).
## - `dries_out`: hp_per_s lost in a room whose hottest part is above heat_above (Jobs, Heat.room_heat).
## - `ion_stun`: seconds stunned when an ion hit lands on their room (Jobs.ion_hit).
## - `body`: the body's size in cells: 2 (the default, 2x2) or 1 (a small body, 1x1, that also walks 1-wide crawlspaces); read when the species is set (CrewMember.body_size, Pathfinder).
## - `reveal_enemy`: while they are aboard and up, your enemy schematic shows the enemy's crew (reveals_enemy, Schematic).
## - `heat_speed`: walk speed x`cold` in a room whose hottest part is below `below`, x`hot` above `above` (heat_factor, set by Jobs as CrewMember.speed_mod).
## - `vacuum_walk`: no air penalties: they do not suffocate and the vacuum does not slow them (Jobs); give it with `o2_use` 0 to also not use air.
## - `no_tools`: they take no repair or extinguish jobs (Jobs.TOOL_JOBS).
## - `hull_mend`: idle, they repair `rate` hp a second in all of the damaged walls next to them and seal a breach next to them in `seal` seconds (Jobs).
## - `revive_once`: the first time they go down (once a run: CrewMember.revived), they stand up again after `after` seconds at `hp` hit points, and do not bleed out meanwhile (Mortality, Jobs); no `hp` above 0 = none.
## - `line_affinity`: line id -> factor on the speed of their work on the parts of that equipment line: repairing one (repair_component) and manning one (work_rate, manned_factor). Factors multiply.
## - `split_on_death`: when they bleed out they become two small 1x1 halves with half the hp each, that merge back into one after `reform_s` seconds if both live and are up (Mortality); 0 = they just die.
## - `counter_melee`: damage dealt straight back to whoever hits them in a melee (CrewAbilities.melee_hit). Amounts add.
## - `no_suit`: they cannot wear a suit or armour (CrewMember.can_wear / equip refuse it, with a reason).
## - `vacuum_speed`: factor on their walk speed in a room with less than THIN_AIR of its air (set by Jobs as CrewMember.speed_mod, with heat_speed).
## The result is shared and cached: read it, do not change it.

const Content = preload("res://scripts/data/content.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const Stats = preload("res://scripts/sim/stats.gd")

const LEGACY_PATH := "res://data/species.json"  ## its `traits` table is the old home of the library
const DAMAGE: Array[String] = ["fire", "no_air", "melee", "ranged", "ion"]
const WORK: Array[String] = ["repair", "extinguish", "breach", "man", "restock", "craft", "heal_others"]
const HEAL: Array[String] = ["bed", "medbay"]
const FLAGS: Array[String] = ["mechanical", "vacuum_walk", "no_tools", "reveal_enemy", "no_suit"]  ## the keys that are true or false
const OPEN: Array[String] = ["line_affinity"]  ## the groups whose sub-keys are not a fixed list: line ids (data/lines.json) -> a number
const THIN_AIR := 0.3  ## a room with less than this share of its air is "thin" for vacuum_speed
const SUIT_TRAITS: Array[String] = ["suit"]  ## the gear traits that are a suit or armour: no_suit refuses them (add the armour ones here)
const BODIES: Array[int] = [1, 2]  ## the sizes `body` may have
## Every key a trait may use -> its sub-keys ([] for a plain number or flag).
const KEYS := {
	"hp_mult": [], "speed_mult": [], "o2_use": [], "suffocate_mult": [],
	"damage_taken": DAMAGE, "work_mult": WORK, "heal_mult": HEAL, "mechanical": [],
	"aura": ["o2_per_s", "heal_per_s", "work_mult"], "station": ["power_bonus", "manned_mult", "evasion_add"],
	"melee_mult": [], "ranged_mult": [], "swarm": ["per_other", "max"],
	"dries_out": ["heat_above", "hp_per_s"], "ion_stun": [],
	"body": [], "reveal_enemy": [], "heat_speed": ["cold", "hot", "below", "above"], "vacuum_walk": [], "no_tools": [],
	"hull_mend": ["rate", "seal"],
	"revive_once": ["after", "hp"], "line_affinity": [], "split_on_death": ["reform_s"], "counter_melee": [], "no_suit": [], "vacuum_speed": [],
}
const META: Array[String] = ["id", "name", "blurb", "notes", "override", "reason"]  ## the fields of a trait entry that are not keys
const FACTORS: Array[String] = ["hp_mult", "speed_mult", "o2_use", "suffocate_mult", "melee_mult", "ranged_mult", "vacuum_speed"]
const FACTOR_GROUPS: Array[String] = ["damage_taken", "work_mult", "heal_mult"]
const GROUPS: Array[String] = ["aura", "station", "swarm", "dries_out", "heat_speed", "hull_mend", "revive_once", "split_on_death"]  ## the groups with their own merge rule per sub-key
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


## Problems in the value `v` of key `k` of a trait or species entry (`at` says where it is) that the validators' shape checks do not
## see: an OPEN group must be an object of equipment lines (data/lines.json) -> number; revive_once needs an hp above 0 and
## split_on_death a reform_s above 0, or the trait would do nothing.
static func extra_problems(at: String, k: String, v) -> Array[String]:
	var out: Array[String] = []
	if k in OPEN:
		if not v is Dictionary:
			return ["%s: '%s' must be an object of line -> number" % [at, k]]
		var lines := Stats.load_lines()
		for sub in v:
			if not lines.has(str(sub)):
				out.append("%s: '%s' names '%s', which is not a line (%s)" % [at, k, sub, ", ".join(lines.keys())])
			elif not (v[sub] is float or v[sub] is int):
				out.append("%s: '%s.%s' must be a number" % [at, k, sub])
	elif v is Dictionary and k in ["revive_once", "split_on_death"]:
		var sub := "hp" if k == "revive_once" else "reform_s"
		var n = v.get(sub, 0)
		if not ((n is float or n is int) and n > 0):
			out.append("%s: '%s' needs a '%s' above 0, or it does nothing" % [at, k, sub])
	return out


## The numbers of `member` (a CrewMember): species, personal and gear traits merged. Keys and defaults:
## hp_mult, speed_mult, o2_use, suffocate_mult, melee_mult, ranged_mult 1.0; ion_stun 0.0; mechanical false;
## damage_taken {fire, no_air, melee, ranged, ion}, work_mult {repair, extinguish, breach, man, restock, craft,
## heal_others} and heal_mult {bed, medbay} all 1.0; aura {o2_per_s 0, heal_per_s 0, work_mult 1};
## station {power_bonus 0, manned_mult 1, evasion_add 0}; swarm {per_other 0, max 0}; dries_out {heat_above INF, hp_per_s 0};
## body 2; vacuum_walk, no_tools, reveal_enemy, no_suit false; heat_speed {cold 1, hot 1, below -INF, above INF}; hull_mend {rate 0, seal 0};
## revive_once {after 0, hp 0}; split_on_death {reform_s 0}; line_affinity {} (a line it does not list is 1); counter_melee 0; vacuum_speed 1.
static func of(member) -> Dictionary:
	_ensure()
	var ids: Array = member.traits()
	var key := "%s|%s|%s" % [member.species, ",".join(PackedStringArray(ids)), member.character]
	if _cache.has(key):
		return _cache[key]
	var out := _fresh()
	var sp := Content.entry("species", str(member.species))
	_merge(out, bag_of(sp if not sp.is_empty() else Characters.unique_species(str(member.species))))
	_merge(out, bag_of(Characters.bag(member.character)))  # a unique character's own keys
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
		"ion_stun": 0.0, "body": 2,
		"aura": {"o2_per_s": 0.0, "heal_per_s": 0.0, "work_mult": 1.0},
		"station": {"power_bonus": 0.0, "manned_mult": 1.0, "evasion_add": 0.0},
		"swarm": {"per_other": 0.0, "max": 0.0},
		"dries_out": {"heat_above": INF, "hp_per_s": 0.0},
		"heat_speed": {"cold": 1.0, "hot": 1.0, "below": -INF, "above": INF},
		"hull_mend": {"rate": 0.0, "seal": 0.0},
		"revive_once": {"after": 0.0, "hp": 0.0}, "split_on_death": {"reform_s": 0.0}, "line_affinity": {},
		"counter_melee": 0.0, "vacuum_speed": 1.0,
	}
	for flag in FLAGS:
		out[flag] = false
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
		elif k in FLAGS:
			out[k] = bool(out[k]) or bool(v)
		elif k == "body":
			out[k] = mini(int(out[k]), clampi(int(v), BODIES[0], BODIES[-1]))
		elif k == "counter_melee":
			out[k] = float(out[k]) + float(v)
		elif not v is Dictionary:
			continue
		elif k in OPEN:
			for sub in v:
				out[k][str(sub)] = float(out[k].get(str(sub), 1.0)) * float(v[sub])
		elif k in FACTOR_GROUPS:
			for sub in v:
				if out[k].has(sub):
					out[k][sub] = float(out[k][sub]) * float(v[sub])
		elif k in GROUPS:
			for sub in v:
				if not out[k].has(sub):
					continue
				var f := float(v[sub])
				if sub in ["work_mult", "manned_mult", "cold", "hot"]:
					out[k][sub] = float(out[k][sub]) * f
				elif sub in ["heat_above", "above"]:
					out[k][sub] = minf(float(out[k][sub]), f)
				elif sub == "below":
					out[k][sub] = maxf(float(out[k][sub]), f)
				elif sub in ["seal", "after", "reform_s"]:  # the quickest time wins; 0 = not set (hull_mend: cannot seal)
					out[k][sub] = f if float(out[k][sub]) <= 0.0 else (minf(float(out[k][sub]), f) if f > 0.0 else float(out[k][sub]))
				elif k == "revive_once" and sub == "hp":  # the highest wins
					out[k][sub] = maxf(float(out[k][sub]), f)
				else:
					out[k][sub] = float(out[k][sub]) + f


# --- rules that need the ship ---------------------------------------------------------------------

## How fast `m` does a job of `kind` (WORK) on `ship`, 1.0 being the normal speed: their work_mult for it,
## times the swarm bonus (1 + per_other per other up crew member of their species in their room, at most
## 1 + max), times the aura work_mult of every other up crew member in their room, times a crewmate's rally there.
## `line`: the equipment line of the part they work on ("" = not a part): times their line_affinity for it.
static func work_rate(ship, m, kind: String, line := "") -> float:
	var t := of(m)
	var rate := float(t["work_mult"].get(kind, 1.0)) * float(t["line_affinity"].get(line, 1.0))
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
	rate *= CrewFx.rally_factor(ship, m, room)  # a crewmate's rally ability
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
## rate (with their line_affinity for the part's line) times their station.manned_mult; 1.0 when nobody is there.
static func manned_factor(ship, uid: int) -> float:
	var who = operator_of(ship, uid)
	if who == null:
		return 1.0
	return work_rate(ship, who, "man", part_line(ship, uid)) * float(of(who)["station"]["manned_mult"])


## The equipment line (data/lines.json) of part `uid` of `ship`: "standard" when its def names none, "" for no such part.
static func part_line(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return ""
	return str(ship.components.def(ship.components.instances[uid]["id"]).get("line", Stats.DEFAULT_LINE))


## The factor on a walk speed that the heat of the room (`heat`) puts on a crew member whose resolved set is `t`:
## heat_speed.cold below `below`, heat_speed.hot above `above`, 1.0 between (and for crew with no heat_speed).
static func heat_factor(t: Dictionary, heat: float) -> float:
	var h: Dictionary = t["heat_speed"]
	var f := 1.0
	if heat < float(h["below"]):
		f *= float(h["cold"])
	if heat > float(h["above"]):
		f *= float(h["hot"])
	return f


## The factor on a walk speed that thin air puts on a crew member whose resolved set is `t`: vacuum_speed in a room whose
## air is below THIN_AIR of full (`pressure`, a fraction), 1.0 above it (and for crew with no vacuum_speed).
static func thin_air_factor(t: Dictionary, pressure: float) -> float:
	return float(t["vacuum_speed"]) if pressure < THIN_AIR else 1.0


## Does a crew member of `ship` who is up have `reveal_enemy`? Then the enemy's schematic shows its crew.
static func reveals_enemy(ship) -> bool:
	for m in ship.crew:
		if not m.is_down() and of(m)["reveal_enemy"]:
			return true
	return false


## The evasion that whoever mans part `uid` adds on top of the post's own (station.evasion_add); 0 with nobody there.
static func helm_evasion_add(ship, uid: int) -> float:
	var who = operator_of(ship, uid)
	return 0.0 if who == null else float(of(who)["station"]["evasion_add"])
