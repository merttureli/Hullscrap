extends RefCounted
## The one content loader (docs/CONTENT_PLAN.md section 1). Core data lives in data/<kind>.json; packs
## (data/packs/<id>/) add to it. Every kind is read from the core file, then from the same file of every
## pack in alphabetical pack order, and merged by id:
##   Content.list("components")      the merged entries (copies: change them freely)
##   Content.events() / ships() / regions() / names()
##   Content.read("res://data/components.json")   a drop-in for JSON.parse_string(FileAccess.get_file_as_string(path)):
##                                   the core file's own shape with the pack entries merged in (other paths are read as they are)
## A pack is a folder with a pack.json ({id, name, version, requires, notes}) and any of <kind>.json,
## names.json, events/*.json, ships/*.json and regions/*.json. An entry may be a list element with an `id` or a key of an
## object (weapons.json is keyed by id); packs may use either. A duplicate id is an error unless the later
## entry says "override": true and gives a "reason"; it then replaces the earlier one whole. Problems never
## stop the load: they collect in errors() (tests/test_content.gd fails on them). Parsed files are cached;
## reload() forgets them, and changing `root` or `packs_root` does so by itself.

const DATA_ROOT := "res://data"
const ART_ROOT := "res://art"
## The kinds that are one <kind>.json each. Their entries sit under the key of the same name unless FILE_KEYS says otherwise.
const KINDS: Array[String] = ["components", "weapons", "recipes", "items", "materials", "tiles", "species", "traits", "hand_weapons", "factions"]
const FILE_KEYS := {"hand_weapons": "weapons"}
## The kinds that are read from folders of files. A region file (regions/<id>.json) is one region object.
const FOLDER_KINDS: Array[String] = ["events", "ships", "regions"]
const PACK_FIELDS: Array[String] = ["id", "name", "version", "requires"]
## What else a pack folder may hold (anything .json or any folder not listed is reported as a typo).
const PACK_EXTRA_FILES: Array[String] = ["pack.json", "names.json", "logs.json"]
const PACK_FOLDERS: Array[String] = ["events", "ships", "logs", "regions"]

## Where the core files are; tests point it at a fixture folder.
static var root := DATA_ROOT
## Where the pack folders are; "" means <root>/packs. Tests point it at a folder of fixture packs.
static var packs_root := ""
static var _key := ""  # root|packs_root the cache was built for
static var _packs: Array = []  # [{id, name, version, requires, notes, dir}] in load order
static var _kinds := {}  # kind -> {ids, map (id -> entry), origin (id -> "core" or pack id), file (id -> path), core (the core file's parsed object), body_key, dict (entries are an object keyed by id)}
static var _names := {}
static var _names_loaded := false
static var _errors: Array[String] = []
static var _overrides: Array = []


## Forget everything that was read; the next call reads the files again.
static func reload() -> void:
	_key = ""
	_packs = []
	_kinds = {}
	_names = {}
	_names_loaded = false
	_errors = []
	_overrides = []


## The merged entries of `kind` (a KINDS or FOLDER_KINDS name), core first, then the packs in order. Each is a copy
## with an `id` (a ship is {id, name, path, pack, design}). [] for a kind nobody defines.
static func list(kind: String) -> Array:
	var k := _load_kind(kind)
	var out := []
	for id in k["ids"]:
		out.append(_with_id(k["map"][id], id))
	return out


static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in _load_kind(kind)["ids"]:
		out.append(id)
	return out


static func has(kind: String, id: String) -> bool:
	return _load_kind(kind)["map"].has(id)


## A copy of one entry, or {}.
static func entry(kind: String, id: String) -> Dictionary:
	var k := _load_kind(kind)
	return _with_id(k["map"][id], id) if k["map"].has(id) else {}


## "core" or the id of the pack the entry of `kind` came from ("" when there is none).
static func origin(kind: String, id: String) -> String:
	return str(_load_kind(kind)["origin"].get(id, ""))


## The file the entry came from ("" when there is none).
static func file_of(kind: String, id: String) -> String:
	return str(_load_kind(kind)["file"].get(id, ""))


## Every event of data/events/*.json and of every pack's events/*.json.
static func events() -> Array:
	return list("events")


## Every ship design of data/ships/*.json and of every pack's ships/*.json: {id (the file name), name, path, pack, design}.
static func ships() -> Array:
	return list("ships")


## Every region of data/regions/*.json and of every pack's regions/*.json (docs/CONTENT.md section 15): one object per
## file, its id the `id` field (the file name when it has none).
static func regions() -> Array:
	return list("regions")


## The name pools of names.json (core, then the packs): pool -> names. Lists are joined and objects merged.
static func names() -> Dictionary:
	_ensure()
	if not _names_loaded:
		_names_loaded = true
		_merge_names(root + "/names.json")
		for p in _packs:
			_merge_names(p["dir"] + "/names.json")
	return _names.duplicate(true)


## The packs, in load order: {id, name, version, requires, notes, dir}.
static func packs() -> Array:
	_ensure()
	return _packs.duplicate(true)


## Every problem found while loading, with the file and the id: bad JSON, duplicate ids, pack.json faults, typos in a pack's file names.
static func errors() -> Array[String]:
	_ensure()
	for kind in KINDS:
		_load_kind(kind)
	for kind in FOLDER_KINDS:
		_load_kind(kind)
	names()
	return _errors.duplicate()


## The entries a pack replaced: {kind, id, pack, reason, replaced (the origin it replaced)}.
static func overrides() -> Array:
	errors()
	return _overrides.duplicate(true)


## Does system `id` have art of its own (art/components/<id>.png)? A tier that borrows the lower tier's art does not count.
static func has_art(id: String) -> bool:
	return FileAccess.file_exists("%s/components/%s.png" % [ART_ROOT, id])


## Like JSON.parse_string(FileAccess.get_file_as_string(path)). For a core file of a KINDS kind (res://data/<kind>.json)
## the answer is that file's object with `packs` entries merged into its list or object of entries; for any other path
## the file is read as it is. A fresh copy every time, so a loader may change what it gets.
static func read(path: String):
	var kind := ""
	if path.get_base_dir() == DATA_ROOT and path.get_extension() == "json" and KINDS.has(path.get_file().get_basename()):
		kind = path.get_file().get_basename()
	if kind == "":
		return JSON.parse_string(FileAccess.get_file_as_string(path))
	var k := _load_kind(kind)
	if k["core"] == null and k["ids"].is_empty():
		return JSON.parse_string(FileAccess.get_file_as_string(path))
	var body = {} if k["dict"] else []
	for id in k["ids"]:
		if k["dict"]:
			body[id] = k["map"][id].duplicate(true)
		else:
			body.append(_with_id(k["map"][id], id))
	var doc := {}
	var core: Dictionary = k["core"] if k["core"] != null else {}
	for key in core:
		doc[key] = body if key == k["body_key"] else (core[key].duplicate(true) if (core[key] is Array or core[key] is Dictionary) else core[key])
	doc[k["body_key"]] = body
	return doc


# --- loading --------------------------------------------------------------------------------------

static func _with_id(e: Dictionary, id: String) -> Dictionary:
	var out := e.duplicate(true)
	if not out.has("id"):
		out["id"] = id
	return out


static func _ensure() -> void:
	var key := root + "|" + packs_root
	if key == _key:
		return
	reload()
	_key = key
	_load_packs()


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		_errors.append("%s: not valid JSON (line %d: %s)" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


static func _load_packs() -> void:
	var dir := packs_root if packs_root != "" else root + "/packs"
	var found: Array = Array(DirAccess.get_directories_at(dir)) if DirAccess.dir_exists_absolute(dir) else []
	found.sort()
	for n in found:
		if str(n).begins_with("."):
			continue
		var p := {"id": str(n), "name": str(n), "version": "", "requires": [], "notes": "", "dir": "%s/%s" % [dir, n]}
		_read_pack_json(p)
		_check_pack_files(p)
		_packs.append(p)
	var have := {}
	for p in _packs:
		have[p["id"]] = true
	for p in _packs:
		for r in p["requires"]:
			if not have.has(r):
				_errors.append("%s/pack.json: requires pack '%s', which is not installed" % [p["dir"], r])


static func _read_pack_json(p: Dictionary) -> void:
	var path: String = p["dir"] + "/pack.json"
	if not FileAccess.file_exists(path):
		_errors.append("%s: missing (every pack needs a pack.json)" % path)
		return
	var m = _read_json(path)
	if not m is Dictionary:
		if m != null:
			_errors.append("%s: expected an object" % path)
		return
	for f in PACK_FIELDS:
		if not m.has(f):
			_errors.append("%s: missing field '%s'" % [path, f])
	if m.has("id") and str(m["id"]) != p["id"]:
		_errors.append("%s: id '%s' is not the folder name '%s'" % [path, m["id"], p["id"]])
	for f in ["name", "notes"]:
		if m.has(f) and not m[f] is String:
			_errors.append("%s: '%s' must be text" % [path, f])
		elif m.has(f):
			p[f] = m[f]
	if m.has("version"):
		if m["version"] is String or m["version"] is float:
			p["version"] = str(m["version"])
		else:
			_errors.append("%s: 'version' must be text or a number" % path)
	if m.has("requires"):
		var ok: bool = m["requires"] is Array
		for r in m["requires"] if ok else []:
			ok = ok and r is String
		if ok:
			p["requires"] = m["requires"]
		else:
			_errors.append("%s: 'requires' must be a list of pack ids ([] for none)" % path)


## A misspelt file or folder name would silently drop content, so name it.
static func _check_pack_files(p: Dictionary) -> void:
	var known: Array[String] = PACK_EXTRA_FILES.duplicate()
	for kind in KINDS:
		known.append(kind + ".json")
	for f in DirAccess.get_files_at(p["dir"]):
		if f.ends_with(".json") and not known.has(f):
			_errors.append("%s/%s: not a file a pack reads (expected one of: %s)" % [p["dir"], f, ", ".join(known)])
	for d in DirAccess.get_directories_at(p["dir"]):
		if not PACK_FOLDERS.has(d):
			_errors.append("%s/%s: not a folder a pack reads (expected: %s)" % [p["dir"], d, ", ".join(PACK_FOLDERS)])


static func _load_kind(kind: String) -> Dictionary:
	_ensure()
	if _kinds.has(kind):
		return _kinds[kind]
	var k := {"ids": [], "map": {}, "origin": {}, "file": {}, "core": null, "body_key": FILE_KEYS.get(kind, kind), "dict": false}
	_kinds[kind] = k
	if FOLDER_KINDS.has(kind):
		_add_folder(k, kind, kind)
	elif KINDS.has(kind):
		_add_file(k, kind, root + "/" + kind + ".json", "core")
		for p in _packs:
			_add_file(k, kind, p["dir"] + "/" + kind + ".json", p["id"])
	else:
		push_error("Content: unknown kind '%s'" % kind)
	return k


static func _add_file(k: Dictionary, kind: String, path: String, pack: String) -> void:
	var data = _read_json(path)
	if data == null:
		return
	var key: String = FILE_KEYS.get(kind, kind)
	if data is Dictionary:
		key = key if data.has(key) else kind
	if not (data is Dictionary and data.has(key)):
		_errors.append("%s: expected an object with a \"%s\" entry" % [path, FILE_KEYS.get(kind, kind)])
		return
	if pack == "core":
		k["core"] = data
		k["body_key"] = key
		k["dict"] = data[key] is Dictionary
	elif k["core"] == null and k["ids"].is_empty():
		k["dict"] = data[key] is Dictionary
	for pair in _pairs(data[key], path):
		_add(k, kind, pair[0], pair[1], pack, path, pair[1])


static func _add_folder(k: Dictionary, kind: String, folder: String) -> void:
	var places: Array = [["core", root + "/" + folder]]
	for p in _packs:
		places.append([p["id"], p["dir"] + "/" + folder])
	for place in places:
		if not DirAccess.dir_exists_absolute(place[1]):
			continue
		var files: Array = Array(DirAccess.get_files_at(place[1])).filter(func(f): return f.ends_with(".json"))
		files.sort()
		for f in files:
			var path: String = place[1] + "/" + f
			var data = _read_json(path)
			if data == null:
				continue
			if kind == "ships":
				if data is Dictionary:
					var id: String = f.get_basename()
					_add(k, kind, id, {"id": id, "name": str(data.get("name", id)), "path": path, "pack": place[0], "design": data}, place[0], path, data)
				else:
					_errors.append("%s: expected a ship design object" % path)
			elif kind == "regions":
				if data is Dictionary:
					var rid := str(data.get("id", f.get_basename()))
					_add(k, kind, rid, data, place[0], path, data)
				else:
					_errors.append("%s: expected a region object" % path)
			else:
				var body = data.get("events") if data is Dictionary else data
				for pair in _pairs(body, path):
					_add(k, kind, pair[0], pair[1], place[0], path, pair[1])


## [id, entry] pairs of a list of entries with an `id`, or of an object keyed by id.
static func _pairs(body, path: String) -> Array:
	var out := []
	if body is Array:
		var n := 0
		for e in body:
			n += 1
			if e is Dictionary and e.get("id") is String and e["id"] != "":
				out.append([e["id"], e])
			else:
				_errors.append("%s: entry number %d has no id" % [path, n])
	elif body is Dictionary:
		for id in body:
			if str(id).begins_with("_"):
				continue
			if body[id] is Dictionary:
				out.append([str(id), body[id]])
			else:
				_errors.append("%s: entry '%s' is not an object" % [path, id])
	else:
		_errors.append("%s: expected a list or an object of entries" % path)
	return out


## Add one entry. `meta` is where its override/reason keys are (the entry itself, or a ship's design).
static func _add(k: Dictionary, kind: String, id: String, e: Dictionary, pack: String, path: String, meta: Dictionary) -> void:
	var over: bool = meta.get("override", false) == true
	var reason := str(meta.get("reason", "")).strip_edges()
	if not k["map"].has(id):
		if over:
			_errors.append("%s: %s '%s' says override but no earlier file defines it" % [path, kind, id])
		k["ids"].append(id)
	elif over and reason != "":
		_overrides.append({"kind": kind, "id": id, "pack": pack, "reason": reason, "replaced": k["origin"][id]})
	else:
		_errors.append("%s: duplicate %s id '%s' (first defined in %s)%s" % [path, kind, id, k["file"][id], "" if not over else "; an override needs a non-empty reason"])
		return
	k["map"][id] = e
	k["origin"][id] = pack
	k["file"][id] = path


static func _merge_names(path: String) -> void:
	var data = _read_json(path)
	if data == null:
		return
	if data is Dictionary:
		_merge_into(_names, data, path)
	else:
		_errors.append("%s: expected an object of name pools" % path)


static func _merge_into(dst: Dictionary, src: Dictionary, path: String) -> void:
	for key in src:
		var v = src[key]
		if str(key).begins_with("_"):
			continue
		if not dst.has(key):
			dst[key] = v.duplicate(true) if (v is Array or v is Dictionary) else v
		elif dst[key] is Dictionary and v is Dictionary:
			_merge_into(dst[key], v, path)
		elif dst[key] is Array and v is Array:
			for x in v:
				if not dst[key].has(x):
					dst[key].append(x)
		else:
			_errors.append("%s: names '%s' is not the same kind of thing as in the earlier files" % [path, key])
