extends RefCounted
## Who wears what aboard (boarding.json `wear`): the body gear of the foes, the people met aboard and the crew of a beaten ship. Pure logic; every pick is a roll of
## a generator the caller seeds from the site and the person (so a site dresses the same on every visit, and no roll of the fight is shifted).
## A person who wears gear is drawn in it, takes its armour and has its traits (kit.gd, CrewMember.traits); a beaten foe's body may hold it (loot.gd).

const Site = preload("res://scripts/board/site.gd")


static func cfg() -> Dictionary:
	return Site.config()["wear"]


## The race gear of region `region` ("" for none): the item whose `regional` entry for the region is the greatest.
static func home_item(region: String) -> String:
	var r: Dictionary = Site.config().get("regional", {}).get(region, {})
	var best := ""
	for item in r:
		if best == "" or float(r[item]) > float(r[best]):
			best = str(item)
	return best


## A weighted pick of `items` ([{weight, item}]) with `x` in 0..1; "" for none.
static func _pick(items: Array, x: float) -> String:
	var total := 0.0
	for o in items:
		total += float(o["weight"])
	if total <= 0.0:
		return ""
	x *= total
	for o in items:
		x -= float(o["weight"])
		if x < 0.0:
			return str(o["item"])
	return str(items[-1]["item"])


## The gear a foe of `kind` wears in `region`, or in a section built by `race` ("" for none). Three rolls of `rng`, always.
static func for_foe(kind: String, region: String, rng: RandomNumberGenerator, race := "") -> String:
	var w: Dictionary = cfg()["foe"].get(kind, {})
	var a := rng.randf()
	var b := rng.randf()
	var c := rng.randf()
	if w.is_empty() or a >= float(w["chance"]):
		return ""
	var home := str(cfg()["race_item"].get(race, "")) if race != "" else home_item(region)  # (aboard a station a race built: the gear of the section's people)
	if home != "" and b < float(cfg()["home"]):
		return home
	return _pick(w["items"], c)


## The gear a person of `role` and `species` wears ("" for none). Three rolls of `rng`, always.
static func for_person(role: String, species: String, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = cfg()["npc"].get(role, {})
	var a := rng.randf()
	var b := rng.randf()
	var c := rng.randf()
	if w.is_empty() or a >= float(w["chance"]):
		return ""
	var race := str(cfg()["race_item"].get(species, ""))
	if race != "" and b < float(cfg()["race"]):
		return race
	return _pick(w["items"], c)


## The gear a crew member of a beaten ship (species `species`) wears: their race's item, with the crew's chance. Two rolls.
static func for_crew(species: String, rng: RandomNumberGenerator) -> String:
	var a := rng.randf()
	var b := rng.randf()
	var race := str(cfg()["race_item"].get(species, ""))
	if race != "" and a < float(cfg()["crew"]["chance"]):
		return race
	return "basic_armor" if b < 0.15 else ""


## `item` as a kit that wears it: what a person's `kit` holds ({} for no gear).
static func kit_of(item: String) -> Dictionary:
	return {"weapons": ["", ""], "body": item, "mods": ["", ""]} if item != "" else {}
