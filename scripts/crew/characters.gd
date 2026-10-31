extends RefCounted
## Unique characters (docs/CONTENT.md section 16): data/characters.json plus the characters.json of every pack
## (Content kind "characters"). A character is a named crew member with an active ability; the schema is in the
## `_doc` of data/characters.json and is checked by CrewAbilities.problems(). This is the runtime side, with no
## dependency on CrewMember or TraitSet (they read it): look a character up, say which species it is, and make a
## crew member into it (apply). A one-of-a-kind character has a `unique_species` and the species id "unique:<id>",
## which CrewMember.species_def and TraitSet.of resolve through unique_species().

const Content = preload("res://scripts/data/content.gd")
const UNIQUE := "unique:"  ## prefix of the species id of a character with a `unique_species`


## The character `id` (a copy), or {} for an id nobody defines.
static func entry(id: String) -> Dictionary:
	return Content.entry("characters", id) if id != "" else {}


static func ids() -> Array[String]:
	return Content.ids("characters")


## The species id a member of character `c` has: its `species`, else "unique:<id>".
static func species_id(c: Dictionary) -> String:
	return str(c["species"]) if c.get("species") is String else UNIQUE + str(c.get("id", ""))


## The species entry of the one-of-a-kind species `species_id` ("unique:<id>"), {} for any other id.
static func unique_species(species: String) -> Dictionary:
	if not species.begins_with(UNIQUE):
		return {}
	var u = entry(species.substr(UNIQUE.length())).get("unique_species")
	return u if u is Dictionary else {}


## The personal trait ids of character `id` (its `traits` when that is a list), [] otherwise.
static func trait_ids(id: String) -> Array:
	var t = entry(id).get("traits")
	return t if t is Array else []


## The personal trait keys of character `id` (its `traits` when that is an object), {} otherwise.
static func bag(id: String) -> Dictionary:
	var t = entry(id).get("traits")
	return t if t is Dictionary else {}


## The name of the species of character `c` for the UI ("Basalt", or its unique species' name).
static func label(c: Dictionary) -> String:
	var sp := species_id(c)
	var u := unique_species(sp)
	if not u.is_empty():
		return str(u.get("name", c.get("name", sp)))
	return str(Content.entry("species", sp).get("name", sp))


## Make crew member `m` (a CrewMember) the character `id`: name, species (so hp, speed and traits are read again),
## ability, the outfit tint and the head frame of its `rig`. False for an unknown id (nothing changes).
static func apply(m, id: String) -> bool:
	var c := entry(id)
	if c.is_empty():
		return false
	m.character = id
	m.name = str(c.get("name", id))
	m.set_species(species_id(c))
	if c.get("ability") is Dictionary:
		m.ability = c["ability"].duplicate(true)
	var rig = c.get("rig")
	m.head = ""
	if rig is Dictionary:
		m.head = str(rig.get("head", ""))
		if rig.has("tint"):
			m.look = m.look.duplicate()
			m.look["suit"] = str(rig["tint"])
	return true
