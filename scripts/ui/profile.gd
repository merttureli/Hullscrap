extends RefCounted
## The player's profile (user://profile.json), kept between runs: which first-run hints were shown, a
## one-line record of every finished run (the main menu lists the last five), the unlocks earned
## (data/unlocks.json: the hangar reads them), the landmarks met (docs/CONTENT.md section 13) and the hall of
## ships (the design of the ship of each run that ended in an ending, the last 20, one file each in the
## folder next to the profile) and the new-run options picked in the hangar (`start`). No nodes. A missing or broken file is an empty profile. Also the version label of the main menu and the save helpers the
## front door uses (is there a run to continue, wipe the saves when the ship is scrap).

const PATH := "user://profile.json"
## 2 adds `unlocks`, `landmarks`, `hall` and `hall_seq`; a version 1 file loads with none.
## 3 adds `start` (the new-run options chosen last time, run_start.gd); an older file loads with the plain defaults.
const VERSION := 3
const MAX_RUNS := 20  ## records kept
const SHOWN_RUNS := 5  ## records the main menu lists
const HALL_MAX := 20  ## ships the hall of ships keeps
const HINTS: Array[String] = ["picked", "map", "fight", "net", "craft"]  ## the first-run hints, in the order they come
const BETA := "Beta 2"
const VERSION_PATH := "res://version.txt"  ## the short git hash, written when the game is exported

var path := PATH
var hints := {}  ## hint id -> true once shown
var runs: Array = []  ## finished runs, oldest first: {ship, jumps, credits, debt, crew, events, fights, date}; a win adds {won, ending, ending_title, score}
var unlocks := {}  ## unlock id -> the date it was earned
var landmarks := {}  ## landmark (event) id -> {title, date}
var hall: Array = []  ## the hall of ships, oldest first: {file, ship, ending, score, date}
var hall_seq := 0  ## the number of the next hall file
var start := {}  ## the new-run options chosen in the hangar: {species, variant, skin} (run_start.gd), each an unlock id or ""; {} = the defaults


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


## Write the file. Returns "" or why not.
func save() -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not write " + ProjectSettings.globalize_path(path)
	f.store_string(JSON.stringify({"version": VERSION, "hints": hints, "runs": runs, "unlocks": unlocks, "landmarks": landmarks, "hall": hall, "hall_seq": hall_seq, "start": start}, "  "))
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


## "Beta 2 (a1b2c3d)" with the short git hash from version.txt (the export writes "Beta 2 <hash>"; a bare
## hash works too), else "Beta 2 (dev)".
static func version_label(file := VERSION_PATH) -> String:
	var short := "dev"
	if FileAccess.file_exists(file):
		var words := FileAccess.get_file_as_string(file).strip_edges().get_slice("\n", 0).split(" ", false)
		if not words.is_empty() and words[-1].length() >= 4 and words[-1].is_valid_hex_number():
			short = words[-1].left(7)
	return "%s (%s)" % [BETA, short]
