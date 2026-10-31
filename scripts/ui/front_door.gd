extends Node
## The front door of the game: the screens around a run and the flow between them. Launch shows the main
## menu (main_menu.gd): Continue loads the ship and campaign saves, New run opens the ship picker, How to
## play opens help_panel.gd (F1 does it anywhere). Esc in the game opens the pause menu (build_mode.gd asks
## open_pause()). When the map reports a lost fight, the run is over: the record goes to the profile, the
## saves are wiped and game_over.gd shows the numbers. When it reports an ending (a won run), the record, the
## score and the ship's design (the hall of ships) go to the profile, the saves are wiped and ending_screen.gd
## shows the page. The first run also gets three hint toasts. The
## screens sit in canvas layers made after the others (so they get the keys first) and the tree is paused
## while one of them is up. The rules are in profile.gd and campaign.gd; this node only wires.

const Profile = preload("res://scripts/ui/profile.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const GameOver = preload("res://scripts/ui/game_over.gd")
const EndingScreen = preload("res://scripts/ui/ending_screen.gd")
const Endings = preload("res://scripts/space/endings.gd")
const HintToast = preload("res://scripts/ui/hint_toast.gd")
const ShipPicker = preload("res://scripts/ui/ship_picker.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const Starfield = preload("res://scripts/space/starfield.gd")

## The first-run hints (profile.gd HINTS), by id.
const HINT_TEXT := {
	"picked": "B: play mode, M: map",
	"map": "Click a lit neighbour to jump",
	"fight": "Mouse steers, LMB fires, J spools the jump drive to escape",
	"net": "Ma's Net Mouth is in your cargo: B, Tab to Systems, put it on an outer wall to catch drifting scrap",
}

var sim: Node
var build: Node
var picker: Node
var combat: Node
var cam: Camera2D
var map: Node  ## the map of the Drift (build_mode.gd makes it)
var profile: Profile
var menu: Control
var help: Control
var over: Control
var ending: Control
var toast: Control
var _map_seen := false  # the map was open last frame
var _fight_seen := false  # so was a fight


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sim = get_node_or_null("../ShipSim")
	build = get_node_or_null("../BuildMode")
	picker = get_node_or_null("../PickerLayer/ShipPicker")
	combat = get_node_or_null("../Combat")
	cam = get_node_or_null("../Camera2D")
	profile = Profile.new()
	_make_ui.call_deferred()  # after build_mode.gd added its layers: ours must be the last children to get the keys first


func _make_ui() -> void:
	var root := get_parent()
	toast = _layer(root, "ToastLayer", 7, HintToast.new())
	menu = _layer(root, "MenuLayer", 8, MainMenu.new())
	menu.set_stars(Starfield.new())
	menu.version = Profile.version_label()
	menu.chosen.connect(_on_menu)
	over = _layer(root, "OverLayer", 9, GameOver.new())
	over.chosen.connect(_on_over)
	ending = _layer(root, "EndingLayer", 9, EndingScreen.new())
	ending.chosen.connect(_on_over)
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
	get_tree().paused = menu.visible or over.visible or ending.visible or help.visible
	if map != null:
		var open: bool = map.visible and map.event_panel != null and not map.event_panel.visible and not map.station_panel.visible  # after Ma's first call is read
		if open and not _map_seen:
			_hint("map")
		_map_seen = open
		if not map.visible and sim != null and sim.has_method("player_ship") and sim.player_ship() != null \
				and sim.player_ship().inventory.count("net_mouth_scrap") > 0:
			_hint("net")  # Ma's gift is in the hold: show where it goes
	if combat != null:
		var fighting: bool = combat.active
		toast.top = 62.0 if fighting else 6.0
		if fighting and not _fight_seen:
			_hint("fight")
		_fight_seen = fighting


# --- screens ----------------------------------------------------------------------------------------------

## The main menu, with the last runs and Continue if a run is saved.
func show_main(note := "") -> void:
	menu.recent = profile.last_runs()
	menu.open(MainMenu.Mode.MAIN, Profile.has_save(BuildMode.SAVE_PATH), note)


## Esc in the game: the pause menu (build_mode.gd asks).
func open_pause() -> void:
	if menu == null or menu.visible or over.visible or ending.visible or help.visible or (picker != null and picker.visible) or (combat != null and combat.active):
		return
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
			show_main("Run saved. Continue picks it up.")


func _on_over(id: String) -> void:
	if id == "new":
		_new_run()
	else:
		show_main()


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
	_hint("picked")


## Show first-run hint `id` if it is due.
func _hint(id: String) -> void:
	if profile.hint_due(id):
		toast.push(HINT_TEXT[id])
		profile.mark_hint(id)
