extends RefCounted
## The fit-out of each race flagship, the input of tests/tool_flagships.gd (docs/CONTENT.md section 25). Per race: stage (the run stage it first sails at), ship, captain, role,
## weapons / engines / shields / systems / reactors (the part ids; reactors are topped up with Reactor Mk2 until the power covers the demand), armour (layers), aim (the
## pilot's aim_skill), beds, hull_seed (where to start trying hulls), interior (the widest deck, cells), morale (a style of data/morale.json), yield_frac (the share of its blocks it
## loses before it yields; or yield_hp, that many hp; no time-based yield since fights-end 2026-11), hold (its pilot's ai.hold_fraction), crew (species, repeated in turn) and names (the first is the captain), ammo (stock of each
## ammo kind), edits (hand edits after the hull is built), ram, helm.

const SPECS := {
	"kett": {
		"stage": 3,
		"ship": "Queen of Nine Cells",
		"captain": "Skrit-of-Skrits",
		"role": "hive-queen",
		"weapons": [
			"kett_hive_swarm_launcher",
			"kett_chitin_thrower",
			"kett_drone_picket",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3"
		],
		"engines": [
			"engine_scrap_mk2",
			"engine_scrap_mk2",
			"engine_scrap_mk2"
		],
		"shields": [
			"kett_hive_battery"
		],
		"systems": [
			"kett_brood_hold",
			"medbay"
		],
		"reactors": [
			"kett_nest_reactor",
			"kett_nest_reactor",
			"reactor_mk2",
			"reactor_mk2"
		],
		"armour": 1,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 11,
		"morale": "flagship_kett",
		"crew": [
			"kett"
		],
		"names": [
			"Skrit-of-Skrits",
			"Tik",
			"Tik-Tik",
			"Ch'rr",
			"Vee",
			"Ninefold",
			"Hum",
			"Brood",
			"Mandi",
			"Kell",
			"Sutter",
			"Pip"
		],
		"blurb": "x",
		"interior": 56,
		"ammo": 400,
		"yield_frac": 0.1
	},
	"emberkin": {
		"stage": 5,
		"ship": "The Long Kiln",
		"captain": "Veshti",
		"role": "kiln-barge",
		"weapons": [
			"emberkin_pyre_lance",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"laser_burst",
			"laser_burst"
		],
		"engines": [
			"emberkin_pyre_drive",
			"emberkin_pyre_drive",
			"emberkin_pyre_drive"
		],
		"shields": [
			"emberkin_hearth_shield"
		],
		"systems": [
			"radiator",
			"radiator",
			"medbay"
		],
		"reactors": [
			"emberkin_furnace_core",
			"emberkin_furnace_core",
			"reactor_mk2"
		],
		"armour": 2,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 21,
		"morale": "flagship_emberkin",
		"crew": [
			"emberkin"
		],
		"names": [
			"Veshti",
			"Cinder",
			"Brand",
			"Soot",
			"Ember-Kel",
			"Kindle",
			"Tallow",
			"Hob-em",
			"Pell-em",
			"Mott-em"
		],
		"blurb": "x",
		"interior": 64,
		"yield_frac": 0.1
	},
	"prismatic": {
		"stage": 6,
		"ship": "Cathedral of Seven Notes",
		"captain": "Ilvane",
		"role": "cathedral",
		"weapons": [
			"laser_mk3",
			"laser_mk3",
			"laser_mk3",
			"laser_mk3",
			"laser_mk3",
			"laser_mk3",
			"laser_burst",
			"laser_burst"
		],
		"engines": [
			"engine_mk2",
			"engine_mk2",
			"engine_mk2"
		],
		"shields": [
			"prismatic_lattice_shield"
		],
		"systems": [
			"medbay"
		],
		"helm": "prismatic_resonance_helm",
		"reactors": [
			"prismatic_song_reactor",
			"prismatic_song_reactor",
			"reactor_mk2"
		],
		"armour": 2,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 31,
		"morale": "flagship_prismatic",
		"crew": [
			"prismatic"
		],
		"names": [
			"Ilvane",
			"Aure",
			"Lume",
			"Sela",
			"Verre",
			"Quill",
			"Tessel",
			"Hob-pr",
			"Pell-pr",
			"Mott-pr"
		],
		"blurb": "x",
		"interior": 66,
		"yield_frac": 0.1
	},
	"basalt": {
		"stage": 4,
		"ship": "Deepcut Anvil",
		"captain": "Gorr",
		"role": "anvil",
		"weapons": [
			"basalt_quarry_driver",
			"basalt_quarry_driver",
			"basalt_quarry_driver",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_heavy",
			"basalt_pumice_flak",
			"basalt_pumice_flak"
		],
		"engines": [
			"engine_mk2",
			"engine_mk2",
			"engine_mk2"
		],
		"shields": [
		],
		"systems": [
			"basalt_stonehide_bay",
			"basalt_gravity_anchor"
		],
		"reactors": [
			"basalt_vacuum_forge",
			"basalt_vacuum_forge",
			"reactor_mk1"
		],
		"armour": 3,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 41,
		"morale": "flagship_basalt",
		"edits": [
			{
				"op": "rear_tiles",
				"rows": 3,
				"from": "heavy_armor",
				"tile": "wall"
			}
		],
		"crew": [
			"basalt"
		],
		"names": [
			"Gorr",
			"Tarn",
			"Slate",
			"Brek",
			"Obdur",
			"Kolm",
			"Dunt",
			"Hob-ba",
			"Pell-ba",
			"Mott-ba"
		],
		"blurb": "x",
		"yield_frac": 0.1,
		"interior": 54
	},
	"sporeling": {
		"stage": 5,
		"ship": "Mother's Bloom",
		"captain": "Thallus",
		"role": "bloom",
		"weapons": [
			"sporeling_spore_cannon",
			"sporeling_rot_pod",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"sporeling_pollen_turret",
			"swarm_pod",
			"pulse_mk3"
		],
		"engines": [
			"engine_mk2",
			"engine_mk2",
			"engine_mk2"
		],
		"shields": [
			"sporeling_mycelium_shield"
		],
		"systems": [
			"sporeling_garden_bay",
			"sporeling_garden_bay",
			"medbay"
		],
		"reactors": [
			"sporeling_bloom_reactor",
			"sporeling_bloom_reactor",
			"reactor_mk1"
		],
		"armour": 1,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 51,
		"prow_add": 3,
		"morale": "flagship_sporeling",
		"crew": [
			"sporeling"
		],
		"names": [
			"Thallus",
			"Spore",
			"Hyphae",
			"Morel",
			"Cap",
			"Frond",
			"Lichen",
			"Hob-sp",
			"Pell-sp",
			"Mott-sp"
		],
		"blurb": "x",
		"ammo": 200,
		"yield_frac": 0.1,
		"interior": 60
	},
	"mire": {
		"stage": 5,
		"ship": "The Slow Tide",
		"captain": "Quag",
		"role": "fenwater",
		"weapons": [
			"mire_steam_lance",
			"mire_steam_lance",
			"mire_steam_lance",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"mire_mist_projector",
			"laser_burst",
			"laser_burst"
		],
		"engines": [
			"engine_mk2",
			"engine_mk2"
		],
		"shields": [
		],
		"systems": [
			"mire_spray_deck",
			"mire_spray_deck",
			"medbay"
		],
		"reactors": [
			"mire_wetwell_reactor",
			"mire_wetwell_reactor",
			"reactor_mk2"
		],
		"armour": 1,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 4,
		"hull_seed": 61,
		"morale": "flagship_mire",
		"crew": [
			"mire"
		],
		"names": [
			"Quag",
			"Sedge",
			"Bracken",
			"Reed",
			"Murk",
			"Fen-Tam",
			"Willow",
			"Peat",
			"Lotus",
			"Tarn-Sue",
			"Brine",
			"Moss"
		],
		"blurb": "x",
		"interior": 56,
		"yield_frac": 0.1
	},
	"fenn": {
		"stage": 5,
		"ship": "Fair Exchange",
		"captain": "Tivvik",
		"role": "bazaar-barge",
		"weapons": [
			"fenn_market_missile",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"fenn_spark_lattice",
			"pulse_mk3",
			"pulse_mk3"
		],
		"engines": [
			"fenn_haggle_engine",
			"fenn_haggle_engine",
			"fenn_haggle_engine"
		],
		"shields": [
		],
		"systems": [
			"fenn_quickfix_bay",
			"fenn_quickfix_bay"
		],
		"reactors": [
			"fenn_jury_reactor",
			"fenn_jury_reactor",
			"reactor_mk2"
		],
		"armour": 2,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 71,
		"morale": "flagship_fenn",
		"crew": [
			"fenn"
		],
		"names": [
			"Tivvik",
			"Nib",
			"Quill-Fen",
			"Dabble",
			"Skit",
			"Pocket",
			"Tally",
			"Hob-fe",
			"Pell-fe",
			"Mott-fe"
		],
		"blurb": "x",
		"interior": 44,
		"ammo": 200,
		"yield_frac": 0.1
	},
	"gauntling": {
		"stage": 4,
		"ship": "Spare Parts Prime",
		"captain": "Nine",
		"role": "overseer",
		"weapons": [
			"gauntling_arc_hammer",
			"gauntling_arc_hammer",
			"gauntling_arc_hammer",
			"pulse_mk3",
			"pulse_mk3",
			"gauntling_tesla_picket",
			"laser_burst"
		],
		"engines": [
			"gauntling_overclock_engine",
			"gauntling_overclock_engine",
			"gauntling_overclock_engine"
		],
		"shields": [
		],
		"systems": [
			"gauntling_graft_bay"
		],
		"reactors": [
			"gauntling_arc_core",
			"gauntling_arc_core",
			"reactor_mk1"
		],
		"armour": 2,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 2,
		"hull_seed": 81,
		"morale": "flagship_gauntling",
		"crew": [
			"gauntling",
			"gauntling",
			"drone"
		],
		"names": [
			"Nine",
			"Unit 3",
			"Unit 7",
			"Spark-1",
			"Spark-2",
			"Spark-3",
			"Spark-4",
			"Spark-5"
		],
		"blurb": "x",
		"yield_frac": 0.1
	},
	"grundl": {
		"stage": 5,
		"ship": "Last Barge",
		"captain": "Brunn",
		"role": "ramhead",
		"weapons": [
			"grundl_slug_mortar",
			"grundl_slug_mortar",
			"grundl_slug_mortar",
			"pulse_mk3",
			"pulse_mk3",
			"grundl_barge_flak",
			"grundl_barge_flak",
			"grundl_barge_flak"
		],
		"engines": [
			"grundl_hauler_thrusters",
			"grundl_hauler_thrusters",
			"grundl_hauler_thrusters",
			"grundl_hauler_thrusters"
		],
		"shields": [
		],
		"systems": [
			"grundl_cargo_deck"
		],
		"reactors": [
			"reactor_mk2",
			"reactor_mk2",
			"reactor_mk1"
		],
		"armour": 1,
		"aim": 0.7,
		"hold": 0.4,
		"beds": 3,
		"hull_seed": 91,
		"morale": "flagship_grundl",
		"ram": true,
		"crew": [
			"grundl"
		],
		"names": [
			"Brunn",
			"Oof",
			"Bale",
			"Crate",
			"Tonnage",
			"Heft",
			"Slab",
			"Hob-gr",
			"Pell-gr",
			"Mott-gr"
		],
		"blurb": "x",
		"ammo": 600,
		"yield_frac": 0.1
	},
	"human": {
		"stage": 4,
		"ship": "Concord Ascendant",
		"captain": "Reyne",
		"role": "flagship",
		"weapons": [
			"human_concord_railgun",
			"human_concord_railgun",
			"pulse_mk3",
			"pulse_mk3",
			"pulse_mk3",
			"human_flak_screen",
			"pulse_mk3"
		],
		"engines": [
			"engine_mk2",
			"engine_mk2",
			"engine_mk2"
		],
		"shields": [
			"shield_mk2"
		],
		"systems": [
			"human_comms_array",
			"medbay"
		],
		"reactors": [
			"human_reactor_plus",
			"human_reactor_plus",
			"reactor_mk2"
		],
		"armour": 2,
		"aim": 0.78,
		"hold": 0.4,
		"beds": 4,
		"hull_seed": 101,
		"morale": "flagship_human",
		"crew": [
			"human"
		],
		"names": [
			"Reyne",
			"Lt. Okafor",
			"Sgt. Haldane",
			"Cpl. Ito",
			"Pvt. Marsh",
			"Pvt. Duval",
			"Pvt. Kerr",
			"Pvt. Sato",
			"Pvt. Brandt",
			"Pvt. Lindqvist"
		],
		"blurb": "x",
		"ammo": 200,
		"yield_frac": 0.1
	}
}
