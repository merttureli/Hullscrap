extends RefCounted
## The value model of a gun (docs/GUNS.md 9), shared by tests/tool_gun_bench.gd and tests/test_gun_versions.gd.
## value = fixed-equivalent damage x shots (x the beam's seconds) / the cooldown (a chain gun's mean over a fight, a charge gun's with its gaps)
##         x (range / 900) ^ 0.35 x (1 + 0.06 pierce) x (1 + 0.04 splash) x 1.1 when it passes shields.
## It is read against the base of the gun's family at its tier (BASES): the existing Mk guns, the Mk guns G2 adds, and for a family with no gun
## of that tier a notional one (the tier steps of the lasers: x1.8 at tier 2, x3.05 at tier 3). The aim class share (swivel 0.8, turret 0.6) is
## paid back by the aim factor (a tracking gun always bears: x1.25, x1.6), so class does not move the value; the bench shows what it does in a fight.

const CHAIN_F := 0.62  ## the mean cooldown factor of a chain gun over a fight (steps 0, 1, 2, 3, 3, 3 ...: (1 + .8 + .64 + 5 x .512) / 8)
const CHARGE_F := 0.97  ## and of a charge gun (the gap between its released volleys)
const BAND := 0.15  ## a version lands within this of its base
## Guns the model misreads, where the fight bench is the judge (tests/tool_gun_bench.gd mode=solo, 60 s, 3 copies, generated enemies of the tier, the fight value
## against the family base): id -> [the bench value of the last run, least allowed, most allowed]. The lights are below their base by design (cheap, power -1, fit
## anywhere, track: 0.7 to 1.0); the swarm pod's six small blasts are worth far less in a fight than the model says; the mortar's splash does well against scrap plate
## (explosive x1.5), the gun strip's against shields; the chain and charge swivels pay the 0.8 share. The finishers (lances, torpedo) may be up to 20% over.
const BENCH := {
	"laser_light": [0.80, 0.7, 1.0], "pulse_light": [0.85, 0.7, 1.0], "flak_turret": [0.80, 0.7, 1.0], "beam_light": [0.77, 0.7, 1.0], "missile_pod": [0.70, 0.7, 1.0],
	"gun_strip": [1.12, 0.85, 1.15], "slug_mortar": [1.25, 0.85, 1.3], "swarm_pod": [0.69, 0.65, 1.15], "pulse_chain": [0.94, 0.85, 1.15], "ion_charge": [0.82, 0.8, 1.15], "beam_long": [0.98, 0.85, 1.15],
}
const EXCEPT := {"laser_lance": 0.2, "beam_spinal": 0.2, "slug_spinal": 0.2, "torpedo": 0.2, "heavy_battery": 0.15}  ## the finishers: their design says more (a wider band, 20%)

## family -> tier -> the base: a weapon id of the data, or an inline entry (notional)
const BASES := {
	"laser": {1: "laser_mk1", 2: "laser_mk2", 3: "laser_mk3"},
	"pulse": {1: "pulse_mk1", 2: "pulse_mk2", 3: "pulse_mk3"},
	"ion": {1: "ion_blast_mk1", 2: "ion_mk2", 3: {"kind": "laser", "damage": 3.9, "cooldown": 4.5, "range": 1400.0}},
	"flak": {1: "shrapnel_cannon_scrap", 2: "flak_mk2", 3: {"kind": "flak", "damage": 3.8, "cooldown": 2.7, "range": 910.0, "shots": 6}},
	"missile": {1: "artemis_mk1", 2: "artemis_mk2", 3: {"kind": "missile", "damage": 9.0, "cooldown": 5.5, "range": 1820.0, "pierce": 1, "splash": 2.5}},
	"beam": {1: "heat_lance_neon", 2: "beam_mk2", 3: {"kind": "beam", "damage": 8.5, "cooldown": 8.7, "range": 1260.0, "duration": 2.0}},
	"slug": {1: "slug_gun", 2: {"kind": "bolt", "damage": 6.5, "cooldown": 2.7, "range": 1330.0, "pierce": 1}, 3: {"kind": "bolt", "damage": 10.5, "cooldown": 2.58, "range": 1470.0, "pierce": 1}},
}


## Value of the entry `w` (a Weapons.def result, or a raw entry with kind, damage, cooldown, range).
static func value(w: Dictionary) -> float:
	var share := 1.0
	if w.has("aim"):
		share = {"fixed": 1.0, "swivel": 0.8, "turret": 0.6}.get(str(w["aim"]), 1.0)
	var cd := float(w["cooldown"])
	if w.get("chain") is Dictionary:
		cd *= CHAIN_F
	if w.get("charge") is Dictionary:
		cd *= CHARGE_F
	var secs := float(w.get("duration", 2.0 if str(w["kind"]) == "beam" else 1.0)) if str(w["kind"]) == "beam" else 1.0
	var dps := float(w["damage"]) / share * float(w.get("shots", 1)) * secs / cd
	var passes := 1.1 if (bool(w.get("pass_shields", false)) or str(w["kind"]) == "missile") else 1.0
	return dps * pow(float(w["range"]) / 1260.0, 0.35) * (1.0 + 0.06 * float(w.get("pierce", 0))) * (1.0 + 0.04 * float(w.get("splash", 0))) * passes


## The base entry of weapon `id` (Weapons instance `weapons`): its family's at its tier.
static func base_of(weapons, id: String, tier: int) -> Dictionary:
	var fam := str(weapons.defs[id].get("family", ""))
	var b = BASES.get(fam, {}).get(tier)
	if b is String:
		return weapons.def(b)
	return b if b is Dictionary else {}


## value(id) / value(base): 1.0 is the base's own. 0 when the gun has no family base (point defence).
static func ratio(weapons, id: String, tier: int) -> float:
	var b := base_of(weapons, id, tier)
	return value(weapons.def(id)) / value(b) if not b.is_empty() else 0.0
