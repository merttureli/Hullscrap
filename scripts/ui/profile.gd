extends RefCounted
## The player's profile (user://profile.json), kept between runs: which first-run hints were shown and a
## one-line record of every finished run (the main menu lists the last five). No nodes. A missing or
## broken file is an empty profile. Also the version label of the main menu and the save helpers the
## front door uses (is there a run to continue, wipe the saves when the ship is scrap).

const PATH := "user://profile.json"
const VERSION := 1
const MAX_RUNS := 20  ## records kept
const SHOWN_RUNS := 5  ## records the main menu lists
const HINTS: Array[String] = ["picked", "map", "fight"]  ## the first-run hints, in the order they come
const BETA := "Beta 1"
const VERSION_PATH := "res://version.txt"  ## the short git hash, written when the game is exported

var path := PATH
var hints := {}  ## hint id -> true once shown
var runs: Array = []  ## finished runs, oldest first: {ship, jumps, credits, debt, crew, events, fights, date}


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


## Read the file. A missing or broken one leaves an empty profile.
func load_file() -> void:
	hints = {}
	runs = []
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


## Write the file. Returns "" or why not.
func save() -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not write " + ProjectSettings.globalize_path(path)
	f.store_string(JSON.stringify({"version": VERSION, "hints": hints, "runs": runs}, "  "))
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


## One line for a record: "Courier: 14 jumps, 230 cr, debt 480, 3 crew, 9 events, 4 fights won".
static func run_line(r: Dictionary) -> String:
	var line := "%s: %d jumps, %d cr, debt %d, %d crew, %d events, %d fights won" % [
		str(r.get("ship", "?")), int(r.get("jumps", 0)), int(r.get("credits", 0)), int(r.get("debt", 0)),
		int(r.get("crew", 0)), int(r.get("events", 0)), int(r.get("fights", 0))]
	var date := str(r.get("date", ""))
	return "%s  %s" % [date, line] if date != "" else line


# --- saves and version --------------------------------------------------------------------------------

## Is there a saved run to continue (the ship save; the campaign is saved with it)?
static func has_save(ship_path: String) -> bool:
	return FileAccess.file_exists(ship_path)


## Delete the save files: death is final.
static func clear_saves(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## "Beta 1 (a1b2c3d)" with the short git hash from version.txt (the export writes "Beta 1 <hash>"; a bare
## hash works too), else "Beta 1 (dev)".
static func version_label(file := VERSION_PATH) -> String:
	var short := "dev"
	if FileAccess.file_exists(file):
		var words := FileAccess.get_file_as_string(file).strip_edges().get_slice("\n", 0).split(" ", false)
		if not words.is_empty() and words[-1].length() >= 4 and words[-1].is_valid_hex_number():
			short = words[-1].left(7)
	return "%s (%s)" % [BETA, short]
