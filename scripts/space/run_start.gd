extends RefCounted
## What the unlocks a player has do at the start of a run (docs/CONTENT.md sections 13 and 19, unlocks.gd). A starter ship is
## the hangar's own; the rest are here. Three kinds are a CHOICE, a row of options under the hangar's ship (SLOTS: the
## soldier's species, a map variant, a hull skin) that the profile remembers (`start`, profile.gd); the fourth, a blueprint,
## is simply known in the fabricator at the start of every new run. A choice is {species, variant, skin}: each the id of an
## unlock the profile has, or "" (or missing) for the plain default. Everything is data (the payloads in unlocks.json); this
## script only applies it: apply_ship when the ship is chosen (ship_picker.gd), apply_campaign when the campaign is made
## (map_view.gd). No nodes, no drawing, no randomness.

const Unlocks = preload("res://scripts/space/unlocks.gd")
const Content = preload("res://scripts/data/content.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const SLOTS: Array[String] = ["species", "variant", "skin"]
## The kind of unlock each slot offers.
const KIND_OF := {"species": "species_start", "variant": "map_variant", "skin": "skin"}
## The slot's label on the hangar's row, and what its default (no unlock) is called.
const LABELS := {"species": "Soldier", "variant": "Map", "skin": "Hull skin"}
const DEFAULTS := {"species": "Ship's own", "variant": "Standard", "skin": "Standard"}


## The unlocks of `kind` that `profile` has (null = nothing earned), in catalogue order.
static func owned(profile, kind: String) -> Array:
	return Unlocks.of_kind(kind).filter(func(u): return profile != null and profile.has_unlock(str(u["id"])))


## The options of `slot`: the default {id: "", name} first, then each unlock the profile has {id, name}.
static func options(profile, slot: String) -> Array:
	var out := [{"id": "", "name": DEFAULTS[slot]}]
	for u in owned(profile, KIND_OF[slot]):
		out.append({"id": str(u["id"]), "name": str(u.get("name", u["id"]))})
	return out


## Is there anything to choose (some slot has an option besides its default)?
static func has_choices(profile) -> bool:
	return SLOTS.any(func(s): return options(profile, s).size() > 1)


## `choice` as it can be for `profile`: every slot, each an unlock the profile has of the slot's kind, else "".
static func clean(choice: Dictionary, profile) -> Dictionary:
	var out := {}
	for s in SLOTS:
		var id := str(choice.get(s, ""))
		out[s] = id if options(profile, s).any(func(o): return o["id"] == id) else ""
	return out


## `choice` with `slot` moved `step` options on (wrapping over the default and the unlocks the profile has).
static func cycle(choice: Dictionary, profile, slot: String, step: int) -> Dictionary:
	var out := clean(choice, profile)
	var list := options(profile, slot)
	var at := 0
	for i in list.size():
		if list[i]["id"] == out[slot]:
			at = i
	out[slot] = list[posmod(at + step, list.size())]["id"]
	return out


## What `slot` of `choice` is called on the row: the option's name.
static func name_of(choice: Dictionary, profile, slot: String) -> String:
	var id := str(clean(choice, profile)[slot])
	return Unlocks.name_of(id) if id != "" else str(DEFAULTS[slot])


## The recipe ids every new run starts with: the blueprint unlocks the profile has.
static func blueprints(profile) -> Array[String]:
	var out: Array[String] = []
	for u in owned(profile, "blueprint"):
		var id := str(Unlocks.payload_of(str(u["id"])).get("blueprint", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


# --- applying -------------------------------------------------------------------------------------------------

## Put the starting unlocks on the player's `ship` (just loaded from its design): the soldier's species, the blueprints known
## at the start (the core data/recipes.json `start_known` first, which a design's own saved list may lack, then the profile's), the hull skin, and the
## repair drone every run starts with (add_drone). Returns a line for each thing done.
## Every run also starts with at least data/drift.json fuel.start fuel (fuel_up), whatever the design's cargo says.
static func apply_ship(ship, choice: Dictionary, profile) -> Array[String]:
	var lines: Array[String] = []
	fuel_up(ship)
	var pick := clean(choice, profile)
	if pick["species"] != "":
		var p := Unlocks.payload_of(str(pick["species"]))
		if soldier(ship, str(p.get("species", "")), str(p.get("name", ""))):
			lines.append("Your soldier is %s" % Unlocks.name_of(str(pick["species"])))
	for id in JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json")).get("start_known", []):  # (a design saves its own, older list: the core file's is the floor of every run; a pack's start list is not)
		ship.crafting.unlock(str(id))
	for id in blueprints(profile):
		if ship.crafting.unlock(id):
			lines.append("Known from the start: " + ship.crafting.name_of(str(ship.crafting.def(id)["output"]["item"]), ship.components))
	ship.crafting.mark_seen()  # the starting blueprints are not NEW
	ship.skin = str(Unlocks.payload_of(str(pick["skin"])).get("skin", "")) if pick["skin"] != "" else ""
	if add_drone(ship):
		lines.append("A repair drone is aboard: it mends, fights fires and reloads by itself, on 1 power")
	for l in lines:
		ship.log_event(l)
	return lines


## Top the cargo's fuel up to fuel.start of data/drift.json (a design with more keeps it). Fuel is scarce (stations sell a few units, most
## traders none), so the tank a run starts with is a real part of its budget: tests/tool_fuel_rate.gd measures what a run is left with.
static func fuel_up(ship) -> void:
	var start := int(Content.read("res://data/drift.json")["fuel"]["start"])
	ship.inventory.add("fuel", maxi(0, start - ship.inventory.count("fuel")))


## Every run starts with one repair drone (playtest 2, R1; data/crew.json `drone`, species `drone`): its entry joins the design's crew list, which is
## what Jobs.spawn_crew puts aboard. A list with no entries (the default crew) gets the soldier first, so the run is the soldier and the drone.
## It is added here, not in the starter files. False when the list has a drone already.
static func add_drone(ship) -> bool:
	if ship.crew_plan.any(func(e): return CrewMember.is_drone_species(str(e.get("species", "")))):
		return false
	var cfg: Dictionary = CrewMember.config()
	if ship.crew_plan.is_empty():
		ship.crew_plan.append({"name": cfg["player"]["name"], "species": "human", "player": true})
	ship.crew_plan.append(drone_entry())
	return true


## The crew-list entry of the starting drone: {name, species}.
static func drone_entry() -> Dictionary:
	var cfg: Dictionary = CrewMember.config()["drone"]
	return {"name": str(cfg["name"]), "species": str(cfg["species"])}


## How the hangar names the starting drone beside the crew: "Drone (Repair Drone)".
static func drone_label() -> String:
	var e := drone_entry()
	return "%s (%s)" % [e["name"], CrewMember.species_def(str(e["species"])).get("name", "Drone")]


## Make the ship's soldier (the player's crew member of its crew list) a `species`, named `name` when given. False when the ship
## has no crew list (the default crew is the soldier and Ada, both human) or `species` is empty.
static func soldier(ship, species: String, who := "") -> bool:
	return swap_soldier(ship.crew_plan, species, who)


## The same on a crew list [{name, species}]: the entry named like the player in data/crew.json, or marked `player`, becomes the
## species (and the name), marked `player` so the new name still takes the soldier's place (jobs.gd); a list with none gets one at the front.
static func swap_soldier(plan: Array, species: String, who := "") -> bool:
	if species == "" or plan.is_empty():
		return false
	var home: String = CrewMember.config()["player"]["name"]
	var at := -1
	for i in plan.size():
		if bool(plan[i].get("player", false)) or plan[i]["name"] == home:
			at = i
			break
	var entry := {"name": who if who != "" else home, "species": species, "player": true}
	if at >= 0:
		plan[at] = entry
	else:
		plan.push_front(entry)
	return true


## `crew` (a design's crew list) as it would be flown with `choice`: the soldier of the chosen species. A copy.
static func crew_shown(crew: Array, choice: Dictionary, profile) -> Array:
	var out := crew.duplicate(true)
	var id := str(clean(choice, profile)["species"])
	if id != "":
		var p := Unlocks.payload_of(id)
		swap_soldier(out, str(p.get("species", "")), str(p.get("name", "")))
	return out


## Put the map variant of `choice` on the new campaign `c` (campaign.gd set_variant).
static func apply_campaign(c, choice: Dictionary, profile) -> void:
	var id := str(clean(choice, profile)["variant"])
	if id != "":
		c.set_variant(str(Unlocks.payload_of(id).get("variant", "")))
