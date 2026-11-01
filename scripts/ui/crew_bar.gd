extends Control
## The crew bar, bottom right: one card per crew member of the player's ship with their portrait (the head of their
## art rig, in their outfit colour), name, hp bar, what they are doing now, and, when they carry an active ability
## (crew_abilities.gd), its icon with a ring: green when ready, filling while it cools down (the seconds left in the
## middle), gold and emptying while its effect runs. Clicking a card selects that crew member (a gold frame; the
## world shows a ring round them); clicking the ability icon selects them and uses it, like G. Cards stack up from
## the bottom, and a second column starts to the left when the screen is full. The selected member's backstory
## (backstory.gd) shows in a box above the cards, and in the tooltip of any card. A line above the cards says what
## the last use did, or why it was refused. Placeholder shapes and letters until the icons have art.
## Reads the crew view (crew_view.gd: ship_now(), selected, select(), use_ability()), and takes only left clicks
## on the cards (everything else falls through to the world; a wheel step over a card is swallowed, so it never zooms).

const Art = preload("res://scripts/view/art.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const CARD := Vector2(238.0, 58.0)
const GAP := 4.0
const MARGIN := 14.0
const TOP_RESERVED := 250.0  ## px kept free at the top of the screen for the HUD text
const PORTRAIT := 44.0  ## the portrait box, px
const ICON := 40.0  ## the ability icon, px
const BG := Color(0.04, 0.07, 0.11, 0.86)
const EDGE := Color("#3b5a78")
const GOLD := Color("#ffd24a")
const TEXT := Color("#cfe6ff")
const DIM := Color("#6b7686")
const READY := Color("#4fd08a")
const BAD := Color("#e0453a")
const HP_BG := Color(0.12, 0.15, 0.2)
const FLASH_FOR := 3.0  ## seconds the line above the cards stays
const STORY_W := 360.0  ## width of the backstory box of the selected member, px
const STORY_SIZE := 13

var view  ## the crew view (crew_view.gd)
var flash_text := ""
var flash_left := 0.0
var _crops := {}  # head sheet id + frame -> the used rectangle of that frame (source px), for the portrait


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Say `text` above the cards for a few seconds.
func flash(text: String) -> void:
	flash_text = text
	flash_left = FLASH_FOR
	queue_redraw()


func _process(dt: float) -> void:
	visible = view != null and view.bar_visible()
	if flash_left > 0.0:
		flash_left -= dt
	if visible:
		queue_redraw()


# --- layout ----------------------------------------------------------------------------------------------

func _screen() -> Vector2:
	return size if size != Vector2.ZERO else get_viewport_rect().size


func _crew() -> Array:
	var ship = view.ship_now() if view != null else null
	return ship.crew if ship != null else []


## The rectangle of each card for `n` crew on a screen of `screen` px: stacked up from the bottom right, in
## columns as tall as the screen allows.
static func card_rects(n: int, screen: Vector2) -> Array[Rect2]:
	var rows := maxi(1, int((screen.y - TOP_RESERVED - MARGIN) / (CARD.y + GAP)))
	var out: Array[Rect2] = []
	for i in n:
		var col := i / rows
		var row := i % rows
		var in_col := mini(rows, n - col * rows)
		var x := screen.x - MARGIN - (col + 1) * CARD.x - col * GAP
		var y := screen.y - MARGIN - (in_col - row) * (CARD.y + GAP) + GAP
		out.append(Rect2(Vector2(x, y), CARD))
	return out


## The icon of the ability on the card at `card`.
static func icon_rect(card: Rect2) -> Rect2:
	return Rect2(card.position + Vector2(CARD.x - ICON - 8.0, (CARD.y - ICON) / 2.0), Vector2(ICON, ICON))


## The index of the card under `p` (this control's own coordinates), -1 for none.
func card_at(p: Vector2) -> int:
	var rects := card_rects(_crew().size(), _screen())
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


## The tooltip of the card under the mouse: who they are and their backstory.
func _get_tooltip(at_position: Vector2) -> String:
	var i := card_at(at_position)
	if i < 0:
		return ""
	var m = _crew()[i]
	return "%s\n%s" % [m.name, m.backstory()]


## Only the cards take the mouse: a click anywhere else goes on to the world.
func _has_point(p: Vector2) -> bool:
	return visible and card_at(p) >= 0


func _gui_input(e: InputEvent) -> void:
	if UiKit.is_wheel(e):
		accept_event()  # the wheel over a card never zooms the world
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if click(e.position) != "":
			accept_event()


## A left click at `p`: on an ability icon it selects the member and uses the ability ("use"), elsewhere on a card
## it selects them ("select"); "" when it is not on a card.
func click(p: Vector2) -> String:
	var i := card_at(p)
	if i < 0 or view == null:
		return ""
	var m = _crew()[i]
	view.select(m)
	if not CrewAbilities.of(m).is_empty() and icon_rect(card_rects(_crew().size(), _screen())[i]).has_point(p):
		view.use_ability(m)  # the view says what happened (flash)
		return "use"
	return "select"


# --- drawing ----------------------------------------------------------------------------------------------

func _draw() -> void:
	if view == null:
		return
	var ship = view.ship_now()
	if ship == null:
		return
	var rects := card_rects(ship.crew.size(), _screen())
	for i in rects.size():
		_card(rects[i], ship, ship.crew[i], ship.crew[i] == view.selected)
	if ship.crew.has(view.selected):
		_story(rects, view.selected)
	if flash_left > 0.0 and flash_text != "" and not rects.is_empty():
		var font := ThemeDB.fallback_font
		var top := rects[0].position.y
		for r in rects:
			top = minf(top, r.position.y)
		var a := clampf(flash_left / 0.6, 0.0, 1.0)
		var w := font.get_string_size(flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at := Vector2(_screen().x - MARGIN - w, top - 8.0)  # right-aligned to the cards
		draw_string(font, at + Vector2(1, 1), flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9 * a))
		draw_string(font, at, flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(GOLD, a))


## The backstory of `m` in a box above the cards (clear of the flash line), right-aligned with them: their name and
## species, then the story wrapped.
func _story(rects: Array[Rect2], m) -> void:
	var text: String = m.backstory()
	if text == "" or rects.is_empty():
		return
	var font := ThemeDB.fallback_font
	var top := rects[0].position.y
	for r in rects:
		top = minf(top, r.position.y)
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, STORY_W - 20.0, STORY_SIZE).y + 38.0
	var box := Rect2(Vector2(_screen().x - MARGIN - STORY_W, maxf(top - 30.0 - h, MARGIN)), Vector2(STORY_W, h))
	draw_rect(box, BG)
	draw_rect(box, GOLD, false, 1.0)
	var kind := str(CrewMember.species_def(m.species).get("name", m.species))
	draw_string(font, box.position + Vector2(10.0, 19.0), "%s, %s" % [m.name, kind], HORIZONTAL_ALIGNMENT_LEFT, STORY_W - 20.0, 14, GOLD)
	draw_multiline_string(font, box.position + Vector2(10.0, 22.0 + font.get_ascent(STORY_SIZE) + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, STORY_W - 20.0, STORY_SIZE, -1, TEXT)


func _card(r: Rect2, ship, m, selected: bool) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(r, BG)
	draw_rect(r, GOLD if selected else (BAD if m.is_down() else EDGE), false, 2.0 if selected else 1.0)
	var box := Rect2(r.position + Vector2(7.0, (CARD.y - PORTRAIT) / 2.0), Vector2(PORTRAIT, PORTRAIT))
	_portrait(box, m)
	var has_icon: bool = not CrewAbilities.of(m).is_empty()
	var text_w := CARD.x - PORTRAIT - 22.0 - (ICON + 28.0 if has_icon else 0.0)
	var x := r.position.x + PORTRAIT + 15.0
	draw_string(font, Vector2(x, r.position.y + 18.0), m.name + (" (you)" if m.is_player else ""), HORIZONTAL_ALIGNMENT_LEFT, text_w, 14, GOLD if selected else TEXT)
	var bar := Rect2(Vector2(x, r.position.y + 24.0), Vector2(text_w, 6.0))
	var frac := clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	draw_rect(bar, HP_BG)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), READY.lerp(BAD, 1.0 - frac))
	draw_string(font, Vector2(x, r.position.y + 47.0), _doing(m), HORIZONTAL_ALIGNMENT_LEFT, text_w + (20.0 if has_icon else 0.0), 12, DIM if m.job.is_empty() else TEXT)  # under the G, up to the icon
	if has_icon:
		_ability(icon_rect(r), CrewAbilities.card(ship, m), selected)


## What the card says they are doing: down, stunned, their job's words, or idle.
func _doing(m) -> String:
	if m.is_down():
		return "down"
	if m.is_stunned():
		return "stunned"
	return str(m.job["label"]) if not m.job.is_empty() else "idle"


## The head of the rig of `m` (the frame of their character's head, else the usual one) in their outfit colour,
## cropped to what is drawn and fitted into `box`; a coloured disc with the initial when there is no art.
func _portrait(box: Rect2, m) -> void:
	draw_rect(box, Color(0.09, 0.12, 0.17))
	var sheet = Art.crew(Art.crew_rig(m.rig()))
	var head = sheet.layers.get("head") if sheet != null else null
	var look: Dictionary = view.look_of(m) if view != null else m.look
	var suit := Color(look.get("suit", "#33c6d6"))
	if head == null:
		draw_circle(box.get_center(), PORTRAIT * 0.36, suit)
		draw_string(ThemeDB.fallback_font, box.get_center() + Vector2(-5.0, 6.0), m.name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		return
	var frame: int = head.named_frames.get(m.head, head.named_frames.get("hair", 0))
	var crop := _crop(head, frame)
	var k := floorf(minf((box.size.x - 4.0) / crop.size.x, (box.size.y - 4.0) / crop.size.y))
	k = maxf(k, 1.0)
	var dest := Rect2(box.get_center() - crop.size * k / 2.0, crop.size * k)
	draw_texture_rect_region(head.tinted(suit), dest, Rect2(head.region(frame).position + crop.position, crop.size), Color(0.5, 0.5, 0.55) if m.is_down() else Color.WHITE)


## The rectangle (in frame px) that holds the pixels of head frame `frame`.
func _crop(head, frame: int) -> Rect2:
	var key := "%d:%d" % [head.get_instance_id(), frame]
	if not _crops.has(key):
		var used := Rect2i(Vector2i.ZERO, Vector2i(head.frame))
		if head.image != null:
			var u: Rect2i = head.image.get_region(Rect2i(head.region(frame))).get_used_rect()
			if u.size.x > 0 and u.size.y > 0:
				used = u
		_crops[key] = Rect2(used)
	return _crops[key]


## The ability icon in `r`: a tag on a dark square inside a ring (see the class comment).
func _ability(r: Rect2, card: Dictionary, selected: bool) -> void:
	var font := ThemeDB.fallback_font
	var a: Dictionary = card["ability"]
	var col := Color(a["color"])
	var c := r.get_center()
	var radius := ICON / 2.0 + 1.0
	var state: String = card["state"]
	draw_rect(r.grow(-3.0), Color(0.07, 0.1, 0.15))
	draw_arc(c, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.13), 3.0, true)
	var from := -PI / 2.0
	match state:
		"running":
			var dur := maxf(float(a["params"].get("duration", card["active_left"])), 0.001)
			draw_arc(c, radius, from, from + TAU * clampf(card["active_left"] / dur, 0.0, 1.0), 40, GOLD, 3.0, true)
		"cooling":
			var cd := maxf(float(a["cooldown"]), 0.001)
			draw_arc(c, radius, from, from + TAU * clampf(1.0 - card["cooldown_left"] / cd, 0.0, 1.0), 40, col.darkened(0.25), 3.0, true)
		"ready":
			draw_arc(c, radius, 0.0, TAU, 40, READY, 3.0, true)
		_:
			draw_arc(c, radius, 0.0, TAU, 40, BAD, 3.0, true)
	if state == "cooling":
		var s := str(ceili(card["cooldown_left"] - 1e-6))
		draw_string(font, c + Vector2(-ICON / 2.0, 6.0), s, HORIZONTAL_ALIGNMENT_CENTER, ICON, 16, TEXT)
	else:
		draw_string(font, c + Vector2(-ICON / 2.0, 6.0), str(a["tag"]), HORIZONTAL_ALIGNMENT_CENTER, ICON, 16, col if state != "blocked" else DIM)
	if selected and state == "ready":  # the key that uses it, left of the icon
		draw_string(font, c + Vector2(-ICON / 2.0 - 14.0, 5.0), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
