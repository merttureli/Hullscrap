extends RefCounted
## The player's profile (user://profile.json), kept between runs: which first-run hints were shown, a
## one-line record of every finished run (the main menu lists the last five), the unlocks earned
## (data/unlocks.json: the hangar reads them), the landmarks met (docs/CONTENT.md section 13) and the hall of
## ships (the design of the ship of each run that ended in an ending, the last 20, one file each in the
## folder next to the profile), the new-run options picked in the hangar (`start`), the sound volumes (`sound`) and the Ledger (the guidance
## program of scripts/sim/advisor.gd: its setting, the tips it has shown, whether the player was asked, the run it follows). No nodes. A missing or broken file is an empty profile. Also the version label of the main menu and the save helpers the
## front door uses (is there a run to continue, wipe the saves when the ship is scrap).

const PATH := "user://profile.json"
## 2 adds `unlocks`, `landmarks`, `hall` and `hall_seq`; a version 1 file loads with none.
## 3 adds `start` (the new-run options chosen last time, run_start.gd); an older file loads with the plain defaults.
## 4 adds `sound` (the Master, Music and SFX sliders, audio.gd); an older file loads with the default volumes.
## 5 adds the Ambience slider to `sound` (an older file keeps the default for it).
## 6 adds the Ledger: `ledger` (full, warn or off), `ledger_asked`, `tips` and `ledger_run`; an older file loads as Full with no tips seen.
const VERSION := 6
const MAX_RUNS := 20  ## records kept
const SHOWN_RUNS := 5  ## records the main menu lists
const HALL_MAX := 20  ## ships the hall of ships keeps
const HINTS: Array[String] = ["picked", "map", "fight", "net", "craft"]  ## the first-run hints, in the order they come
const SOUND_DEFAULTS := {"master": 0.8, "music": 0.6, "sfx": 0.8, "ambience": 0.8}  ## the volume sliders (0 to 1)
const LEDGER_MODES: Array[String] = ["full", "warn", "off"]  ## the Ledger's settings: card, tips and warnings; warnings only; nothing
const BETA := "Beta 3"
const VERSION_PATH := "res://version.txt"  ## the short git hash, written when the game is exported

var path := PATH
var hints := {}  ## hint id -> true once shown
var runs: Array = []  ## finished runs, oldest first: {ship, jumps, credits, debt, crew, events, fights, date}; a win adds {won, ending, ending_title, score}
var unlocks := {}  ## unlock id -> the date it was earned
var landmarks := {}  ## landmark (event) id -> {title, date}
var hall: Array = []  ## the hall of ships, oldest first: {file, ship, ending, score, date}
var hall_seq := 0  ## the number of the next hall file
var start := {}  ## the new-run options chosen in the hangar: {species, variant, skin} (run_start.gd), each an unlock id or ""; {} = the defaults
var sound := SOUND_DEFAULTS.duplicate()  ## the volume sliders of the main menu: {master, music, sfx, ambience}, each 0 to 1
var ledger := "full"  ## the Ledger's setting (LEDGER_MODES)
var ledger_asked := false  ## the one-time "keep it on?" after the first finished run has been put to the player
var tips := {}  ## Ledger tip id -> the date it was shown, in the order shown (the journal's Ledger tab lists them)
var ledger_run := {}  ## what the Ledger keeps of the run it follows (advisor.gd state): {seed, base, warned, announced}


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


## Read the file. A missing or broken one leaves an empty profile.
func load_file() -> void:
	hints = {}
	runs = []
	unlocks = {}
	landmarks = {}
	hall = []
	hall_seq = 0
	start = {}
	sound = SOUND_DEFAULTS.duplicate()
	ledger = "full"
	ledger_asked = false
	tips = {}
	ledger_run = {}
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return
	if d.get("hints") is Dictionary:
		for k in HINTS:
			if bool(d["hints"].get(k, false)):
				hints[k] = true
	if d.get("runs") is Array:
		for r in d["runs"]:
			if r is Dictionary:
				runs.append(r)
		runs = runs.slice(maxi(runs.size() - MAX_RUNS, 0))
	if d.get("unlocks") is Dictionary:
		for k in d["unlocks"]:
			unlocks[str(k)] = str(d["unlocks"][k])
	if d.get("landmarks") is Dictionary:
		for k in d["landmarks"]:
			if d["landmarks"][k] is Dictionary:
				landmarks[str(k)] = d["landmarks"][k]
	if d.get("hall") is Array:
		for h in d["hall"]:
			if h is Dictionary and str(h.get("file", "")) != "":
				hall.append(h)
		hall = hall.slice(maxi(hall.size() - HALL_MAX, 0))
	hall_seq = int(d.get("hall_seq", hall.size()))
	if d.get("start") is Dictionary:
		for k in d["start"]:
			start[str(k)] = str(d["start"][k])
	if d.get("sound") is Dictionary:
		for k in SOUND_DEFAULTS:
			if d["sound"].has(k):
				sound[k] = clampf(float(d["sound"][k]), 0.0, 1.0)
	if LEDGER_MODES.has(str(d.get("ledger", ""))):
		ledger = str(d["ledger"])
	ledger_asked = bool(d.get("ledger_asked", false))
	if d.get("tips") is Dictionary:
		for k in d["tips"]:
			tips[str(k)] = str(d["tips"][k])
	if d.get("ledger_run") is Dictionary:
		ledger_run = d["ledger_run"]


## Write the file. Returns "" or why not.
func save() -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not write " + ProjectSettings.globalize_path(path)
	f.store_string(JSON.stringify({"version": VERSION, "hints": hints, "runs": runs, "unlocks": unlocks, "landmarks": landmarks, "hall": hall, "hall_seq": hall_seq, "start": start, "sound": sound,
		"ledger": ledger, "ledger_asked": ledger_asked, "tips": tips, "ledger_run": ledger_run}, "  "))
	return ""


# --- first-run hints ---------------------------------------------------------------------------------

## Is hint `id` due: not shown yet, and no run has ended (the first run only)?
func hint_due(id: String) -> bool:
	return HINTS.has(id) and not hints.has(id) and runs.is_empty()


## Remember that hint `id` was shown.
func mark_hint(id: String) -> void:
	if HINTS.has(id) and not hints.has(id):
		hints[id] = true
		save()


# --- the Ledger ------------------------------------------------------------------------------------------

## Has Ledger tip `id` been shown to this profile?
func has_tip(id: String) -> bool:
	return tips.has(id)


## Remember that Ledger tip `id` was shown (once: the date of the first time stays) and write the file. True when it is new.
func mark_tip(id: String) -> bool:
	if tips.has(id):
		return false
	tips[id] = Time.get_date_string_from_system()
	save()
	return true


## Set the Ledger to `mode` (LEDGER_MODES) and write the file. False for an unknown mode.
func set_ledger(mode: String) -> bool:
	if not LEDGER_MODES.has(mode):
		return false
	ledger = mode
	save()
	return true


## Is the one-time "The Ledger: keep it on?" due: a run has ended, the player was not asked yet, and the Ledger is not off already?
func ledger_ask_due() -> bool:
	return not ledger_asked and not runs.is_empty() and ledger != "off"


## The player answered (or the setting was chosen by hand): never ask again.
func mark_ledger_asked() -> void:
	if not ledger_asked:
		ledger_asked = true
		save()


# --- runs --------------------------------------------------------------------------------------------

## Record a finished run (see stats_of in game_over.gd) and write the file.
func add_run(rec: Dictionary) -> void:
	runs.append(rec)
	runs = runs.slice(maxi(runs.size() - MAX_RUNS, 0))
	save()


## The newest `n` runs, newest first.
func last_runs(n := SHOWN_RUNS) -> Array:
	var out := runs.duplicate()
	out.reverse()
	return out.slice(0, n)


## "1 jump", "3 jumps".
static func _count(n: int, word: String) -> String:
	return "%d %s" % [n, word if n == 1 else word + "s"]


## One line for a record: "Courier: 14 jumps, 230 cr, debt 480, 3 crew, 9 events, 4 fights won"; a win adds
## " - The Haven, score 1250".
static func run_line(r: Dictionary) -> String:
	var line := "%s: %s, %d cr, debt %d, %d crew, %s, %s won" % [
		str(r.get("ship", "?")), _count(int(r.get("jumps", 0)), "jump"), int(r.get("credits", 0)), int(r.get("debt", 0)),
		int(r.get("crew", 0)), _count(int(r.get("events", 0)), "event"), _count(int(r.get("fights", 0)), "fight")]
	if bool(r.get("won", false)):
		line += " - %s, score %d" % [str(r.get("ending_title", "The End")), int(r.get("score", 0))]
	var date := str(r.get("date", ""))
	return "%s  %s" % [date, line] if date != "" else line


# --- unlocks and landmarks ----------------------------------------------------------------------------------

func has_unlock(id: String) -> bool:
	return unlocks.has(id)


## Earn unlock `id` and write the file. Returns true when it is new, false when the profile had it already.
func unlock(id: String) -> bool:
	if unlocks.has(id):
		return false
	unlocks[id] = Time.get_date_string_from_system()
	save()
	return true


func has_landmark(id: String) -> bool:
	return landmarks.has(id)


## Record landmark `id` (an event id) with its `title` the first time it is met, and write the file. Returns true when it is
## new to the profile; meeting it again in a later run records nothing more.
func record_landmark(id: String, title: String) -> bool:
	if landmarks.has(id):
		return false
	landmarks[id] = {"title": title, "date": Time.get_date_string_from_system()}
	save()
	return true


# --- the hall of ships ----------------------------------------------------------------------------------------

## The folder of the hall's design files: next to the profile, named after it (user://profile_hall).
func hall_dir() -> String:
	return path.get_basename() + "_hall"


## The file of hall entry `i` (oldest first), "" when there is none.
func hall_file(i: int) -> String:
	return "%s/%s" % [hall_dir(), hall[i]["file"]] if i >= 0 and i < hall.size() else ""


## Put a ship design (Endings.design_of) into the hall, with {ship, ending, score}: it is written to a file of its own
## (a design is tens of KB) and the oldest beyond HALL_MAX are dropped with theirs. Returns "" or why not.
func add_to_hall(design: Dictionary, meta: Dictionary) -> String:
	var dir := hall_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return "could not make " + ProjectSettings.globalize_path(dir)
	hall_seq += 1
	var file := "hall_%04d.json" % hall_seq
	var f := FileAccess.open("%s/%s" % [dir, file], FileAccess.WRITE)
	if f == null:
		return "could not write " + ProjectSettings.globalize_path("%s/%s" % [dir, file])
	f.store_string(JSON.stringify(design))
	f.close()
	hall.append({"file": file, "ship": str(meta.get("ship", "?")), "ending": str(meta.get("ending", "")), "score": int(meta.get("score", 0)), "date": Time.get_date_string_from_system()})
	while hall.size() > HALL_MAX:
		var old: Dictionary = hall.pop_front()
		clear_saves(["%s/%s" % [dir, old["file"]]])
	return save()


# --- saves and version --------------------------------------------------------------------------------

## Is there a saved run to continue (the ship save; the campaign is saved with it)?
static func has_save(ship_path: String) -> bool:
	return FileAccess.file_exists(ship_path)


## Delete the save files: death is final.
static func clear_saves(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## "Beta 3 (a1b2c3d)" with the short git hash from version.txt (the export writes "Beta 3 <hash>"; a bare
## hash works too), else "Beta 3 (dev)".
static func version_label(file := VERSION_PATH) -> String:
	var short := "dev"
	if FileAccess.file_exists(file):
		var words := FileAccess.get_file_as_string(file).strip_edges().get_slice("\n", 0).split(" ", false)
		if not words.is_empty() and words[-1].length() >= 4 and words[-1].is_valid_hex_number():
			short = words[-1].left(7)
	return "%s (%s)" % [BETA, short]
