extends Node
## The front door of the game: the screens around a run and the flow between them. Launch shows the main
## menu (main_menu.gd): Continue loads the ship and campaign saves, New run opens the ship picker, How to
## play opens help_panel.gd (F1 does it anywhere). Esc in the game opens the pause menu (build_mode.gd asks
## open_pause()). When the map reports a lost fight, the run is over: the record goes to the profile, the
## saves are wiped and game_over.gd shows the numbers. When it reports an ending (a won run), the record, the
## score and the ship's design (the hall of ships) go to the profile, the saves are wiped and ending_screen.gd
## shows the page. The first run also gets three hint toasts. The Ledger (ledger_card.gd: the goal card, the tips and the warnings
## of scripts/sim/advisor.gd) has its own layer here; after the first finished run the player is asked once whether to keep it
## (ledger_prompt.gd), and its setting is a row of both menus. The
## screens sit in canvas layers made after the others (so they get the keys first) and the tree is paused
## while one of them is up. The rules are in profile.gd and campaign.gd; this node only wires.

const Profile = preload("res://scripts/ui/profile.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const GameOver = preload("res://scripts/ui/game_over.gd")
const EndingScreen = preload("res://scripts/ui/ending_screen.gd")
const Endings = preload("res://scripts/space/endings.gd")
const HintToast = preload("res://scripts/ui/hint_toast.gd")
const LedgerCard = preload("res://scripts/ui/ledger_card.gd")
const LedgerPrompt = preload("res://scripts/ui/ledger_prompt.gd")
const ShipPicker = preload("res://scripts/ui/ship_picker.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Starfield = preload("res://scripts/space/starfield.gd")
const Audio = preload("res://scripts/audio/audio.gd")

## The first-run hints (profile.gd HINTS), by id.
const HINT_TEXT := {
	"picked": "B: play mode. Click a marker to set a course. M: map",
	"map": "Click a lit node to jump there",
	"fight": "Mouse steers, LMB fires, J: map to jump away",
	"net": "Net Mouth in your cargo: put it on an outer wall to catch scrap",
	"craft": "Click a recipe to queue it. Place the finished part from the build palette (B).",
}
const BLANK_HINT := "Build your ship, then launch: grow the hull, fit the parts from the hold, wire them, then B and M"  ## the Blank frame's, shown at every such start

var sim: Node
var build: Node
var picker: Node
var combat: Node
var sector: Node  ## the sector view: its header (the place, the helm line) is on show while it is visible
var cam: Camera2D
var map: Node  ## the map of the Drift (build_mode.gd makes it)
var profile: Profile
var menu: Control
var help: Control
var over: Control
var ending: Control
var toast: Control
var ledger: Control  ## the Ledger's card (ledger_card.gd)
var prompt: Control  ## the one-time "keep the Ledger on?" (ledger_prompt.gd)
var _map_seen := false  # the map was open last frame
var _fight_seen := false  # so was a fight
var craft: Control  ## the crafting panel (C)
var _craft_seen := false  # it was open last frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	picker = get_node_or_null("../PickerLayer/ShipPicker")
	combat = get_node_or_null("../Combat")
	sector = get_node_or_null("../Sector")
	craft = get_node_or_null("../CraftLayer/CraftingPanel")
	cam = get_node_or_null("../Camera2D")
	profile = Profile.new()
	_make_ui.call_deferred()  # after build_mode.gd added its layers: ours must be the last children to get the keys first


func _make_ui() -> void:
	var root := get_parent()
	ledger = _layer(root, "LedgerLayer", 6, LedgerCard.new())
	ledger.door = self
	toast = _layer(root, "ToastLayer", 7, HintToast.new())
	menu = _layer(root, "MenuLayer", 8, MainMenu.new())
	menu.set_stars(Starfield.new())
	menu.version = Profile.version_label()
	menu.chosen.connect(_on_menu)
	menu.sound = profile.sound.duplicate()
	menu.sound_changed.connect(_on_sound)
	menu.ledger = profile.ledger
	menu.ledger_changed.connect(_on_ledger)
	if Audio.of(self) != null:
		Audio.of(self).apply_settings(profile.sound)  # the volumes the profile kept
	over = _layer(root, "OverLayer", 9, GameOver.new())
	over.chosen.connect(_on_over)
	ending = _layer(root, "EndingLayer", 9, EndingScreen.new())
	ending.chosen.connect(_on_over)
	prompt = _layer(root, "PromptLayer", 9, LedgerPrompt.new())
	prompt.chosen.connect(_on_ledger_asked)
	help = _layer(root, "HelpLayer", 10, HelpPanel.new())
	map = build.drift if build != null else null
	if map != null and map.has_signal("run_over"):
		map.run_over.connect(_on_run_over)
	if map != null and map.has_signal("run_won"):
		map.run_won.connect(_on_run_won)
		map.profile = profile
		if map.campaign != null:
			map.campaign.profile = profile
	if picker != null:
		picker.chosen.connect(_on_ship_picked)
		picker.profile = profile
	show_main()


func _layer(root: Node, layer_name: String, index: int, node: Control) -> Control:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = index
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(node)
	root.add_child(layer)
	return node


func _process(_dt: float) -> void:
	if menu == null:
		return
	get_tree().paused = menu.visible or over.visible or ending.visible or help.visible or prompt.visible
	if map != null:
		var open: bool = map.visible and map.event_panel != null and not map.event_panel.visible and not map.station_panel.visible  # after Ma's first call is read
		if open and not _map_seen:
			_hint("map")
		_map_seen = open
		if not map.visible and sim != null and sim.has_method("player_ship") and sim.player_ship() != null \
				and sim.player_ship().inventory.count("net_mouth_scrap") > 0:
			_hint("net")  # Ma's gift is in the hold: show where it goes
	if craft != null:
		if craft.visible and not _craft_seen:
			_hint("craft")  # the first time the panel opens
		_craft_seen = craft.visible
	if combat != null:
		var fighting: bool = combat.active
		var panel_up: bool = (craft != null and craft.visible) or (build != null and build.get("shields") != null and build.shields.visible)  # a full panel is over the sector: its header is hidden
		toast.top = toast_top(fighting, _map_seen, sector != null and sector.visible and not panel_up)
		if fighting and not _fight_seen:
			_hint("fight")
		_fight_seen = fighting


## Where the hint toast sits (its top, px): under the fight's key hints, under the map's header (a toast at the top bar covered
## its Hull figure), under the sector's two header lines (the place and the helm) when the ship is flying, else under the HUD's top bar.
static func toast_top(fighting: bool, map_open: bool, sector_header := false) -> float:
	return 62.0 if fighting else (106.0 if map_open else (100.0 if sector_header else 48.0))


# --- screens ----------------------------------------------------------------------------------------------

## The main menu, with the last runs and Continue if a run is saved.
func show_main(note := "") -> void:
	menu.recent = profile.last_runs()
	menu.ledger = profile.ledger
	menu.open(MainMenu.Mode.MAIN, Profile.has_save(BuildMode.SAVE_PATH), note)


## Esc in the game: the pause menu (build_mode.gd asks).
func open_pause() -> void:
	if menu == null or menu.visible or over.visible or ending.visible or help.visible or prompt.visible or (picker != null and picker.visible) or (combat != null and combat.active):
		return
	menu.ledger = profile.ledger
	menu.open(MainMenu.Mode.PAUSE)


func _on_menu(id: String) -> void:
	match id:
		"continue":
			_continue()
		"new":
			_new_run()
		"help":
			help.open()
		"quit":
			get_tree().quit()
		"resume":
			menu.close()
		"save_menu":
			build._save()
			if build.save_block != "":
				menu.note = build.save_block  # aboard another vessel: nothing is saved, the pause menu stays
				return
			show_main("Run saved. Continue picks it up.")


## A volume slider of the menu moved: the sound follows at once, the profile keeps it when the mouse is let go.
func _on_sound(kind: String, value: float, final: bool) -> void:
	profile.sound[kind] = value
	if Audio.of(self) != null:
		Audio.of(self).set_volume(kind, value)
	if final:
		profile.save()


## The game over or ending screen was left: the one-time question about the Ledger first (after the first finished run), then where the player chose to go.
func _on_over(id: String) -> void:
	_ask_ledger(func():
		if id == "new":
			_new_run()
		else:
			show_main())


## The Ledger row of a menu was clicked: the setting is kept, and it is the player's answer, so it will not be asked about.
func _on_ledger(mode: String) -> void:
	profile.set_ledger(mode)
	profile.mark_ledger_asked()


## The one-time question ("keep it on?", ledger_prompt.gd) when it is due, then `next`; else `next` at once.
func _ask_ledger(next: Callable) -> void:
	if prompt != null and profile.ledger_ask_due():
		prompt.open(next)
	else:
		next.call()


func _on_ledger_asked(mode: String) -> void:
	profile.set_ledger(mode)
	profile.mark_ledger_asked()


## Is the Ledger's question up? (ledger_card.gd stays out of its way.)
func prompt_up() -> bool:
	return prompt != null and prompt.visible


## New run: the ship picker; Esc there goes back to the main menu. The campaign starts when a ship is chosen.
func _new_run() -> void:
	menu.close()
	over.close()
	ending.close()
	picker.on_escape = show_main
	picker.open()


## Continue: load the ship and the campaign saved with it (Ctrl+L does the same).
func _continue() -> void:
	build._load()
	if not build.message.begins_with("ship loaded"):
		menu.note = build.message
		return
	var ship = sim.player_ship()
	if cam != null and ship != null:
		var f := ShipPicker.fit(ship.grid, get_viewport().get_visible_rect().size)
		cam.zoom = Vector2(f["zoom"], f["zoom"])
		cam.position = f["pos"]
	menu.close()


# --- the run -------------------------------------------------------------------------------------------------

## The map reports a lost fight: record the run, wipe the saves, show the end screen.
func _on_run_over(campaign) -> void:
	var st := GameOver.stats_of(campaign, sim.player_ship())
	var rec := st.duplicate()
	rec["date"] = Time.get_date_string_from_system()
	profile.add_run(rec)
	Profile.clear_saves([BuildMode.SAVE_PATH, map.save_path])
	over.open(st)


## The map reports an ending (a won run): record it, wipe the saves, show the ending page.
func _on_run_won(campaign, ending_id: String) -> void:
	var ship = sim.player_ship()
	var rep := record_win(campaign, ship, ending_id)
	Profile.clear_saves([BuildMode.SAVE_PATH, map.save_path])
	ending.open_ending(rep, ship)


## A won run goes to the profile: its record with the ending and the score, and the ship's design in the hall of ships.
## Returns the report the ending page shows (Endings.report).
func record_win(campaign, ship, ending_id: String) -> Dictionary:
	var rep := Endings.report(campaign, ship, ending_id)
	var rec := GameOver.stats_of(campaign, ship)
	rec.merge({"date": Time.get_date_string_from_system(), "won": true, "ending": ending_id, "ending_title": rep["ending"]["title"], "score": rep["score"]["total"]})
	profile.add_run(rec)
	profile.add_to_hall(Endings.design_of(ship), {"ship": rec["ship"], "ending": ending_id, "score": rec["score"]})
	return rep


func _on_ship_picked() -> void:
	var ship = sim.player_ship() if sim != null else null
	if ship != null and ship.build_first:
		toast.push(BLANK_HINT)  # every blank start, not once per profile
		return
	_hint("picked")


## Show first-run hint `id` if it is due.
func _hint(id: String) -> void:
	if profile.hint_due(id):
		toast.push(HINT_TEXT[id])
		profile.mark_hint(id)
