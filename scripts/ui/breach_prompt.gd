extends Control
## The breach prompt (playtest 2, K2): a small card near the room that is losing air, "Breach: <room>  [R] Repair  [V] Evacuate",
## with a bar that runs down the seconds left to answer. The logic is crew/breach_alert.gd; this node feeds it the real frame time
## (not the scaled one: the prompt slows the game down), sets Engine.time_scale from it, takes R and V (or a click on the card),
## and says the result on the crew bar. R and V go to the prompt first while it is up (also in a fight, where R would restart).
## The time scale is always put back to 1 when the prompt goes, the ship changes, or this node leaves the tree.
## Lives in the crew view's canvas layer, so a fight (which puts the crew view away) keeps it; in a fight, where the ship is drawn
## elsewhere, the card sits at the top of the screen.

const BreachAlert = preload("res://scripts/crew/breach_alert.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const CARD := Vector2(380.0, 58.0)
const BTN := Vector2(112.0, 22.0)
const MAX_DT := 0.1  ## longest real step the countdown takes, seconds: a stalled frame does not eat the whole answer time
const FIGHT_TOP := 76.0  ## y of the card when the ship is not drawn by the crew view
const EDGE := Color("#e0453a")

var view  ## the crew view (crew_view.gd)
var alert := BreachAlert.new()
var _ship = null
var _last_us := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var real := clampf(float(now - _last_us) / 1.0e6, 0.0, MAX_DT)
	_last_us = now
	tick(real)


## Advance by `real_dt` real seconds: watch the ship, show or hide the card, set the game speed.
func tick(real_dt: float) -> void:
	var ship = view.ship_now() if view != null else null
	if ship != _ship:
		_ship = ship
		alert.reset()
	var paused: bool = view != null and view.sim != null and bool(view.sim.get("paused"))
	alert.update(ship, real_dt, paused)
	Engine.time_scale = alert.time_scale()
	visible = not alert.current().is_empty()
	if visible:
		queue_redraw()


## The card for the prompt on show on a screen of `screen` px: beside the room, kept inside the screen; at the top in a fight.
func card_rect(screen: Vector2) -> Rect2:
	var c := alert.current()
	var at := Vector2(screen.x / 2.0, FIGHT_TOP + CARD.y / 2.0)
	if not c.is_empty() and view != null and view.visible and view.build != null:
		var ship = view.ship_now()
		var id: int = ship.atmosphere.room_at(c["key"]) if ship != null else -1
		if id >= 0:
			var sum := Vector2.ZERO
			var cells: Array = ship.atmosphere.rooms[id]["cells"]
			for cell in cells:
				sum += Vector2(cell) + Vector2(0.5, 0.5)
			var room_px: Vector2 = view.get_global_transform_with_canvas() * view._world(sum / float(cells.size()))
			at = room_px + Vector2(0.0, -CARD.y)  # over the room, not on it
	var pos := at - CARD / 2.0
	return Rect2(pos.clamp(Vector2(8.0, 48.0), (screen - CARD - Vector2(8.0, 8.0)).max(Vector2(8.0, 48.0))), CARD)


func _screen() -> Vector2:
	return size if size != Vector2.ZERO else get_viewport_rect().size


## The rectangle of the Repair (0) or Evacuate (1) button inside `card`.
static func button_rect(card: Rect2, i: int) -> Rect2:
	return Rect2(card.position + Vector2(CARD.x - 2.0 * (BTN.x + 8.0) - 2.0 + i * (BTN.x + 8.0), 28.0), BTN)


## Only the card takes the mouse.
func _has_point(p: Vector2) -> bool:
	return visible and card_rect(_screen()).has_point(p)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var card := card_rect(_screen())
		for i in 2:
			if button_rect(card, i).has_point(e.position):
				answer("repair" if i == 0 else "evacuate")
				accept_event()
				return


func _input(e: InputEvent) -> void:
	if alert.current().is_empty() or not (e is InputEventKey) or not e.pressed or e.echo or e.ctrl_pressed or e.meta_pressed or e.alt_pressed:
		return
	if e.keycode == KEY_R:
		answer("repair")
	elif e.keycode == KEY_V:
		answer("evacuate")
	else:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## The player's answer: "repair" or "evacuate". The game speed goes back at once.
func answer(choice: String) -> void:
	var ship = view.ship_now() if view != null else null
	if ship == null:
		return
	var line := alert.respond(ship, choice)
	Engine.time_scale = alert.time_scale()
	visible = not alert.current().is_empty()
	if view != null:
		view.say(line)


func _draw() -> void:
	var c := alert.current()
	if c.is_empty():
		return
	var card := card_rect(_screen())
	UiKit.bar(self, card, 0.94)
	draw_rect(card, EDGE, false, 2.0)
	UiKit.text(self, "Breach: %s" % c["name"], card.position + Vector2(12.0, 22.0), 15, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24.0, UiKit.bold())
	var more := alert.queue.size() - 1
	if more > 0:
		UiKit.text(self, "+%d more" % more, card.position + Vector2(CARD.x - 12.0, 22.0), 11, UiKit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 80.0)
	for i in 2:
		var r := button_rect(card, i)
		UiKit.button(self, r, i == 1, false)
		UiKit.text(self, "[%s] %s" % ["R" if i == 0 else "V", "Repair" if i == 0 else "Evacuate"], r.position + Vector2(0.0, 16.0), 13, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var frac := clampf(float(c["left"]) / maxf(float(BreachAlert.cfg().get("prompt_s", 3.0)), 0.1), 0.0, 1.0)
	draw_rect(Rect2(card.position + Vector2(12.0, 40.0), Vector2(110.0, 5.0)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(card.position + Vector2(12.0, 40.0), Vector2(110.0 * frac, 5.0)), EDGE if bool(c["slow"]) else UiKit.AMBER)
	UiKit.text(self, "slowed" if bool(c["slow"]) else "no answer: repair", card.position + Vector2(12.0, 55.0), 9, UiKit.DIM_TEXT)
