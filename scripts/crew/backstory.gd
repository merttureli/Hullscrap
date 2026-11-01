extends RefCounted
## Who a crew member is, in words (data/backstory.json): what the crew card, the hire row and the recruit line tell.
## - a unique character tells its `lore` (data/characters.json);
## - the player's soldier and a species with a `fixed` line (a repair drone) tell that line;
## - everyone else gets two sentences put together from the tables by a generator seeded by hash(name, species), so
##   the same Gneiss is the same person in every run and every save. It never draws on the campaign's rng.
## No nodes. CrewMember.backstory() keeps the text in the save.

const Characters = preload("res://scripts/crew/characters.gd")
const CONFIG_PATH := "res://data/backstory.json"

static var _config := {}  # data/backstory.json, read on first use


## data/backstory.json as a Dictionary (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary:
			_config = data
	return _config


## The story of `who` of `species`: the lore of unique character `character`, the player's line, a species' fixed line,
## else a generated one. "" when there is none to tell.
static func of(who: String, species: String, character := "", is_player := false) -> String:
	var cfg := config()
	var chr := Characters.entry(character)
	if not chr.is_empty():
		return str(chr.get("lore", ""))
	if is_player:
		return str(cfg.get("player", ""))
	var fixed = cfg.get("fixed")
	if fixed is Dictionary and fixed.has(species):
		return str(fixed[species])
	if cfg.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|%s" % [who, species]).hash()
	var extra = cfg.get("species", {}).get(species, {})
	var share := float(cfg.get("species_share", 0.5))
	return str(cfg.get("template", "")).format({
		"home": _pick(rng, cfg.get("home", {}).get(species, cfg.get("home_default", "")), []),
		"past": _pick(rng, cfg.get("past", []), extra.get("past", []), share),
		"why": _pick(rng, cfg.get("why", [])),
		"quirk": _pick(rng, cfg.get("quirk", []), extra.get("quirk", []), share),
	})


## The recruit line of an event ("Gneiss tells you: ..."): the story as they say it for an ordinary recruit, the lore
## as it stands for a unique character, the fixed line as it is. "" when there is none.
static func intro(who: String, species: String, character := "") -> String:
	var story := of(who, species, character)
	var fixed = config().get("fixed")
	if story == "" or character != "" or (fixed is Dictionary and fixed.has(species)):
		return story
	return "%s tells you: \"%s\"" % [who, story]


## One entry of `pool` (a string, or a list), or of `special` instead of it `share` of the time. "" for nothing to pick.
static func _pick(rng: RandomNumberGenerator, pool, special := [], share := 0.0) -> String:
	var use_special: bool = rng.randf() < share and special is Array and not special.is_empty()
	var list = special if use_special else pool
	if list is String:
		return list
	return str(list[rng.randi() % list.size()]) if list is Array and not list.is_empty() else ""
