extends RefCounted
## The rules of the ambience, pure logic so they are tested headless (audio.gd feeds them and plays what they say):
## - bed_for: which space bed a place has. By region id first (data/audio.json `_beds.by_region`), else by the region's faction
##   (`by_faction`), else the default; a place the tide has taken (or tide pressure from HOLLOW_PRESSURE, as the music's Hollow) has the Hollow's.
## - room_cutoff: the cutoff of the Room bus's low-pass, which opens with the reactor's load: a dull hum when the reactor idles, air and hiss at full load.
## - creak: the hull's creak, once when the hull drops under CREAK_BELOW of its integrity and again every CREAK_EVERY seconds while it stays low
##   (it re-arms above CREAK_BACK, so a hull at the edge does not creak back and forth).
## - hazard_loop: the ambient loop of a fight's hazard (data/hazards.json `sound`).

const Hazards = preload("res://scripts/combat/hazards.gd")

const ROOM_CLOSED := 450.0  ## Hz: the Room low-pass with the reactor idle
const ROOM_OPEN := 7500.0  ## Hz: and at full load
const CREAK_BELOW := 0.5  ## hull fraction under which the hull creaks
const CREAK_BACK := 0.55  ## and above which it stops until it drops again
const CREAK_EVERY := 24.0  ## seconds between two creaks while the hull is low

var _low := false  # the hull is under CREAK_BELOW
var _t := 0.0  # seconds to the next creak


## The bed of a place: `table` is data/audio.json `_beds`. A Hollow place has the Hollow's bed whatever its region.
static func bed_for(table: Dictionary, region_id: String, faction: String, hollow := false) -> String:
	if hollow and table.has("hollow"):
		return str(table["hollow"])
	var by_region: Dictionary = table.get("by_region", {})
	if by_region.has(region_id):
		return str(by_region[region_id])
	var by_faction: Dictionary = table.get("by_faction", {})
	if by_faction.has(faction):
		return str(by_faction[faction])
	return str(table.get("default", ""))


## The Room bus cutoff (Hz) for a reactor load of 0 to 1: equal musical steps from ROOM_CLOSED to ROOM_OPEN.
static func room_cutoff(load_frac: float) -> float:
	return ROOM_CLOSED * pow(ROOM_OPEN / ROOM_CLOSED, clampf(load_frac, 0.0, 1.0))


## The ambient loop id of hazard `id` ({id, dir} of a fight's arena.hazard is passed as its id), "" for none.
static func hazard_loop(id: String) -> String:
	return str(Hazards.def(id).get("sound", ""))


## Look at the hull (`frac` of its integrity, 0 to 1) after `dt` seconds: true when it should creak now.
func creak(frac: float, dt: float) -> bool:
	if frac >= CREAK_BACK:
		_low = false
		return false
	if frac >= CREAK_BELOW and not _low:
		return false
	if not _low:
		_low = true
		_t = CREAK_EVERY
		return true
	_t -= dt
	if _t <= 0.0:
		_t = CREAK_EVERY
		return true
	return false
