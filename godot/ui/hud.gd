# hud.gd — BotW-inspired HUD.
# Compass strip top-center, health/magicka bars bottom-left, stamina wheel
# near screen center-right, interact prompt bottom-center, quest:toast top-right,
# passive/allegiance chips, hit vignette on combat:playerHit.
class_name HUD extends CanvasLayer

# ---- color constants ----
const COL_INK       := Color("#eaf6ff")
const COL_INK_DIM   := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL     := Color(0.039, 0.063, 0.086, 0.88)
const COL_HEALTH_HI := Color("#4ddd88")
const COL_HEALTH_LO := Color("#ff4d5e")
const COL_MAGICKA   := Color("#6688ff")
const COL_STAMINA   := Color("#ffe066")
const COL_STAMINA_EX:= Color("#ff4d5e")
const COL_COMPASS_N := Color("#ff5566")
const COL_COMPASS   := Color(0.918, 0.965, 1.0, 0.7)
const COL_COMPASS_TICK := Color(0.918, 0.965, 1.0, 0.35)
const PX_PER_DEG    := 3.2

# ---- compass data ----
const COMPASS_LABELS := [
	{"deg": 0,   "txt": "N",  "cardinal": true},
	{"deg": 45,  "txt": "NE", "cardinal": false},
	{"deg": 90,  "txt": "E",  "cardinal": false},
	{"deg": 135, "txt": "SE", "cardinal": false},
	{"deg": 180, "txt": "S",  "cardinal": false},
	{"deg": 225, "txt": "SW", "cardinal": false},
	{"deg": 270, "txt": "W",  "cardinal": false},
	{"deg": 315, "txt": "NW", "cardinal": false},
]

# ---- state ----
var _accent: Color = Color("#46e6ff")
var _hit_flash: float = 0.0
var _health_display: float = 1.0
var _magicka_display: float = 1.0
var _stamina_display: float = 1.0
var _exhausted: bool = false
var _toast_timer: float = 0.0
var _markers: Array = []   # [{id, icon, world_pos or bearing_deg}]

# ---- UI nodes ----
var _compass_strip: Control
var _compass_items: Array = []
var _compass_marker_labels: Array = []
var _health_bar: ColorRect
var _magicka_bar: ColorRect
var _stamina_wheel: StaminaWheel  # inner class
var _interact_prompt: Control
var _interact_label: Label
var _passive_chip: PanelContainer
var _passive_chip_label: Label
var _allegiance_chip: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _vignette: ColorRect
var _crosshair: Control

# ================================================================
func _ready() -> void:
	layer = 6
	_build_compass()
	_build_vitals()
	_build_interact_prompt()
	_build_toast()
	_build_vignette()
	_build_crosshair()
	_build_chips()
	_stamina_wheel = StaminaWheel.new()
	_stamina_wheel.set_accent(_accent)
	add_child(_stamina_wheel)
	visible = false

	EventBus.on("quest:toast",        _on_toast)
	EventBus.on("combat:playerHit",   _on_player_hit)
	EventBus.on("passive:toggled",    _on_passive_toggled)
	EventBus.on("player:ads_changed", func(p): set_ads(p.get("active", false)))

# ================================================================
func _build_compass() -> void:
	var wrap := Control.new()
	wrap.set_anchor(SIDE_LEFT,   0.0)
	wrap.set_anchor(SIDE_TOP,    0.0)
	wrap.set_anchor(SIDE_RIGHT,  1.0)
	wrap.set_anchor(SIDE_BOTTOM, 0.0)
	wrap.set_offset(SIDE_TOP,    0)
	wrap.set_offset(SIDE_BOTTOM, 36)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	# Gradient mask panel
	var bg := PanelContainer.new()
	bg.set_anchor(SIDE_LEFT,   0.2)
	bg.set_anchor(SIDE_TOP,    0.0)
	bg.set_anchor(SIDE_RIGHT,  0.8)
	bg.set_anchor(SIDE_BOTTOM, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.06, 0.72)
	ps.border_width_bottom = 1
	ps.border_color = Color(1,1,1, 0.08)
	bg.add_theme_stylebox_override("panel", ps)
	wrap.add_child(bg)

	# Needle
	var needle := ColorRect.new()
	needle.color = Color("#46e6ff", 0.9)
	needle.set_anchor(SIDE_LEFT,   0.5)
	needle.set_anchor(SIDE_TOP,    0.7)
	needle.set_anchor(SIDE_RIGHT,  0.5)
	needle.set_anchor(SIDE_BOTTOM, 1.0)
	needle.set_offset(SIDE_LEFT,  -1)
	needle.set_offset(SIDE_RIGHT,  1)
	needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(needle)

	_compass_strip = wrap

	# Build label/tick nodes
	_compass_items.clear()
	for deg in range(0, 360, 15):
		var label_def: Dictionary = {}
		for ld in COMPASS_LABELS:
			if ld["deg"] == deg:
				label_def = ld
				break

		var el: Label
		if not label_def.is_empty():
			el = Label.new()
			el.text = label_def["txt"]
			el.add_theme_font_size_override("font_size", 11)
			if label_def.get("cardinal", false) and label_def["txt"] == "N":
				el.add_theme_color_override("font_color", COL_COMPASS_N)
			else:
				el.add_theme_color_override("font_color", COL_COMPASS)
		else:
			el = Label.new()
			el.text = "|"
			var is_major: bool = (deg % 45 == 0)
			el.add_theme_font_size_override("font_size", 11 if is_major else 8)
			el.add_theme_color_override("font_color", COL_COMPASS_TICK)
		el.set_anchor(SIDE_TOP, 0.15)
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compass_strip.add_child(el)
		_compass_items.append({"deg": float(deg), "el": el})

func _build_vitals() -> void:
	var panel := PanelContainer.new()
	panel.set_anchor(SIDE_LEFT,   0.0)
	panel.set_anchor(SIDE_TOP,    1.0)
	panel.set_anchor(SIDE_RIGHT,  0.0)
	panel.set_anchor(SIDE_BOTTOM, 1.0)
	panel.set_offset(SIDE_LEFT,   16)
	panel.set_offset(SIDE_RIGHT,  240)
	panel.set_offset(SIDE_TOP,    -92)
	panel.set_offset(SIDE_BOTTOM, -16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.06, 0.72)
	ps.border_width_left   = 1
	ps.border_width_top    = 1
	ps.border_width_right  = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(1,1,1, 0.08)
	ps.content_margin_left   = 10
	ps.content_margin_right  = 10
	ps.content_margin_top    = 8
	ps.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_health_bar  = _make_bar(vbox, "Health",  COL_HEALTH_HI)
	_magicka_bar = _make_bar(vbox, "Magicka", COL_MAGICKA)

func _make_bar(parent: VBoxContainer, label_text: String, bar_color: Color) -> ColorRect:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_INK_DIM)
	row.add_child(lbl)

	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0, 6)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.08, 0.1, 0.14, 0.9)
	ts.corner_radius_top_left     = 2
	ts.corner_radius_top_right    = 2
	ts.corner_radius_bottom_left  = 2
	ts.corner_radius_bottom_right = 2
	track.add_theme_stylebox_override("panel", ts)
	row.add_child(track)

	var fill := ColorRect.new()
	fill.color = bar_color
	fill.set_anchor(SIDE_LEFT,   0.0)
	fill.set_anchor(SIDE_TOP,    0.0)
	fill.set_anchor(SIDE_RIGHT,  1.0)
	fill.set_anchor(SIDE_BOTTOM, 1.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	return fill

func _build_interact_prompt() -> void:
	_interact_prompt = Control.new()
	_interact_prompt.set_anchor(SIDE_LEFT,   0.5)
	_interact_prompt.set_anchor(SIDE_TOP,    1.0)
	_interact_prompt.set_anchor(SIDE_RIGHT,  0.5)
	_interact_prompt.set_anchor(SIDE_BOTTOM, 1.0)
	_interact_prompt.set_offset(SIDE_LEFT,  -120)
	_interact_prompt.set_offset(SIDE_RIGHT,  120)
	_interact_prompt.set_offset(SIDE_TOP,   -54)
	_interact_prompt.set_offset(SIDE_BOTTOM, -20)
	_interact_prompt.visible = false
	_interact_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_prompt)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.06, 0.82)
	ps.border_width_bottom = 1
	ps.border_color = Color(1,1,1, 0.12)
	ps.content_margin_left   = 12
	ps.content_margin_right  = 12
	ps.content_margin_top    = 6
	ps.content_margin_bottom = 6
	bg.add_theme_stylebox_override("panel", ps)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_prompt.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(hbox)

	var key_lbl := Label.new()
	key_lbl.text = "E"
	key_lbl.add_theme_font_size_override("font_size", 12)
	key_lbl.add_theme_color_override("font_color", _accent)
	hbox.add_child(key_lbl)

	var dash := Label.new()
	dash.text = "—"
	dash.add_theme_font_size_override("font_size", 12)
	dash.add_theme_color_override("font_color", COL_INK_DIM)
	hbox.add_child(dash)

	_interact_label = Label.new()
	_interact_label.add_theme_font_size_override("font_size", 12)
	_interact_label.add_theme_color_override("font_color", COL_INK)
	hbox.add_child(_interact_label)

func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.set_anchor(SIDE_LEFT,   1.0)
	_toast_panel.set_anchor(SIDE_TOP,    0.0)
	_toast_panel.set_anchor(SIDE_RIGHT,  1.0)
	_toast_panel.set_anchor(SIDE_BOTTOM, 0.0)
	_toast_panel.set_offset(SIDE_LEFT,  -300)
	_toast_panel.set_offset(SIDE_RIGHT,  -16)
	_toast_panel.set_offset(SIDE_TOP,    40)
	_toast_panel.set_offset(SIDE_BOTTOM, 80)
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.06, 0.88)
	ps.border_width_left   = 2
	ps.border_color = _accent
	ps.content_margin_left   = 14
	ps.content_margin_right  = 14
	ps.content_margin_top    = 8
	ps.content_margin_bottom = 8
	_toast_panel.add_theme_stylebox_override("panel", ps)
	add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.add_theme_color_override("font_color", COL_INK)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)

func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.color = Color(COL_HEALTH_LO.r, COL_HEALTH_LO.g, COL_HEALTH_LO.b, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

func _build_crosshair() -> void:
	_crosshair = CrosshairDot.new()
	_crosshair.set_anchor(SIDE_LEFT,   0.5)
	_crosshair.set_anchor(SIDE_TOP,    0.5)
	_crosshair.set_anchor(SIDE_RIGHT,  0.5)
	_crosshair.set_anchor(SIDE_BOTTOM, 0.5)
	_crosshair.set_offset(SIDE_LEFT,  -12)
	_crosshair.set_offset(SIDE_RIGHT,   12)
	_crosshair.set_offset(SIDE_TOP,   -12)
	_crosshair.set_offset(SIDE_BOTTOM,  12)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

func show_crosshair() -> void:
	if _crosshair != null:
		_crosshair.visible = true

func hide_crosshair() -> void:
	if _crosshair != null:
		_crosshair.visible = false

func set_ads(active: bool) -> void:
	if _crosshair != null and _crosshair is CrosshairDot:
		(_crosshair as CrosshairDot).ads = active
		_crosshair.queue_redraw()

func _build_chips() -> void:
	_passive_chip = PanelContainer.new()
	_passive_chip.set_anchor(SIDE_LEFT,   0.0)
	_passive_chip.set_anchor(SIDE_TOP,    1.0)
	_passive_chip.set_anchor(SIDE_RIGHT,  0.0)
	_passive_chip.set_anchor(SIDE_BOTTOM, 1.0)
	_passive_chip.set_offset(SIDE_LEFT,   16)
	_passive_chip.set_offset(SIDE_RIGHT,  260)
	_passive_chip.set_offset(SIDE_TOP,   -118)
	_passive_chip.set_offset(SIDE_BOTTOM, -96)
	_passive_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.12)
	ps.border_width_left   = 1
	ps.border_color = Color(_accent.r, _accent.g, _accent.b, 0.4)
	ps.content_margin_left   = 8
	ps.content_margin_right  = 8
	ps.content_margin_top    = 3
	ps.content_margin_bottom = 3
	_passive_chip.add_theme_stylebox_override("panel", ps)
	add_child(_passive_chip)

	_passive_chip_label = Label.new()
	_passive_chip_label.add_theme_font_size_override("font_size", 10)
	_passive_chip_label.add_theme_color_override("font_color", _accent)
	_passive_chip.add_child(_passive_chip_label)

	_allegiance_chip = Label.new()
	_allegiance_chip.visible = false
	_allegiance_chip.set_anchor(SIDE_LEFT,   0.0)
	_allegiance_chip.set_anchor(SIDE_TOP,    1.0)
	_allegiance_chip.set_anchor(SIDE_RIGHT,  0.0)
	_allegiance_chip.set_anchor(SIDE_BOTTOM, 1.0)
	_allegiance_chip.set_offset(SIDE_LEFT,   16)
	_allegiance_chip.set_offset(SIDE_RIGHT,  180)
	_allegiance_chip.set_offset(SIDE_TOP,   -140)
	_allegiance_chip.set_offset(SIDE_BOTTOM, -118)
	_allegiance_chip.add_theme_font_size_override("font_size", 10)
	_allegiance_chip.add_theme_color_override("font_color", COL_INK_DIM)
	_allegiance_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_allegiance_chip)

# ================================================================
# Public API
# ================================================================
func show_prompt(label_text: String) -> void:
	_interact_label.text = label_text
	_interact_prompt.visible = true

func hide_prompt() -> void:
	_interact_prompt.visible = false

func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_timer = 3.0

func set_passive(origin: Dictionary) -> void:
	if origin.is_empty():
		return
	var passive: Dictionary = origin.get("passive", {})
	var hint: String = passive.get("hint", "")
	var name_str: String = passive.get("name", "")
	_passive_chip_label.text = hint + "  " + name_str
	var theme: Dictionary = origin.get("theme", {})
	var accent_hex: String = theme.get("accent", "#46e6ff")
	var ac := Color(accent_hex)
	_passive_chip_label.add_theme_color_override("font_color", ac)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(ac.r, ac.g, ac.b, 0.12)
	ps.border_width_left   = 1
	ps.border_color = Color(ac.r, ac.g, ac.b, 0.4)
	ps.content_margin_left   = 8
	ps.content_margin_right  = 8
	ps.content_margin_top    = 3
	ps.content_margin_bottom = 3
	_passive_chip.add_theme_stylebox_override("panel", ps)

func set_allegiance(label_text: String, col: Color) -> void:
	_allegiance_chip.text = "⛨ " + label_text
	_allegiance_chip.add_theme_color_override("font_color", col)
	_allegiance_chip.visible = true

func set_markers(markers: Array) -> void:
	# Clear old marker labels
	for ml in _compass_marker_labels:
		if is_instance_valid(ml):
			ml.queue_free()
	_compass_marker_labels.clear()
	_markers = markers.duplicate()
	# Create new labels
	for m in _markers:
		var ml := Label.new()
		ml.text = m.get("icon", "◆")
		ml.add_theme_font_size_override("font_size", 12)
		ml.add_theme_color_override("font_color", _accent)
		ml.set_anchor(SIDE_TOP, 0.15)
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compass_strip.add_child(ml)
		_compass_marker_labels.append(ml)

func set_accent_color(col: Color) -> void:
	_accent = col

# ================================================================
# Per-frame update — called by game_director._gameplay_update
# stats: Stats node, cam_yaw: float radians, player_pos: Vector3
# ================================================================
func update_hud(stats_node, cam_yaw: float, player_pos: Vector3) -> void:
	if stats_node == null:
		return
	# ---- health lerp ----
	var hp_ratio: float = stats_node.health / stats_node.max_health
	_health_display = lerp(_health_display, hp_ratio, 0.12)
	_health_bar.set_anchor(SIDE_RIGHT, _health_display)
	var health_col: Color = COL_HEALTH_HI.lerp(COL_HEALTH_LO, 1.0 - _health_display)
	_health_bar.color = health_col

	# ---- magicka lerp ----
	var mp_ratio: float = stats_node.magicka / stats_node.max_magicka
	_magicka_display = lerp(_magicka_display, mp_ratio, 0.12)
	_magicka_bar.set_anchor(SIDE_RIGHT, _magicka_display)

	# ---- stamina wheel ----
	var sp_ratio: float = stats_node.stamina / stats_node.max_stamina
	_stamina_display = lerp(_stamina_display, sp_ratio, 0.18)
	_exhausted = stats_node.exhausted
	_stamina_wheel.set_ratio(_stamina_display)
	_stamina_wheel.set_exhausted(_exhausted)
	_stamina_wheel.visible = sp_ratio < 0.995

	# ---- compass ----
	_update_compass(cam_yaw, player_pos)

	# ---- hit flash decay ----
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - get_process_delta_time() * 2.2)
		_vignette.color = Color(COL_HEALTH_LO.r, COL_HEALTH_LO.g, COL_HEALTH_LO.b, _hit_flash * 0.55)

	# ---- toast timer ----
	if _toast_timer > 0.0:
		_toast_timer -= get_process_delta_time()
		if _toast_timer <= 0.0:
			_toast_panel.visible = false

func _update_compass(cam_yaw: float, player_pos: Vector3) -> void:
	var strip_width: float = _compass_strip.size.x if _compass_strip.size.x > 0.0 else 1280.0
	var cx: float = strip_width * 0.5
	var heading: float = rad_to_deg(cam_yaw)

	for item in _compass_items:
		var off: float = _wrap_deg(item["deg"] - heading)
		var el: Label = item["el"]
		if absf(off) > 75.0:
			el.visible = false
		else:
			el.visible = true
			el.position.x = cx + off * PX_PER_DEG - el.size.x * 0.5

	for i in range(_markers.size()):
		if i >= _compass_marker_labels.size():
			break
		var m: Dictionary = _markers[i]
		var bearing: float = m.get("bearing_deg", 0.0)
		if m.has("world_pos") and player_pos != Vector3.ZERO:
			var wp: Vector3 = m["world_pos"]
			bearing = rad_to_deg(atan2(wp.x - player_pos.x, -(wp.z - player_pos.z)))
		var off: float = _wrap_deg(bearing - heading)
		var ml: Label = _compass_marker_labels[i]
		if absf(off) > 70.0:
			ml.visible = false
		else:
			ml.visible = true
			ml.position.x = cx + off * PX_PER_DEG - ml.size.x * 0.5

static func _wrap_deg(d: float) -> float:
	var r: float = fmod(d + 180.0, 360.0)
	if r < 0.0:
		r += 360.0
	return r - 180.0

# ================================================================
# Event handlers
# ================================================================
func _on_toast(payload: Dictionary) -> void:
	show_toast(payload.get("text", ""))

func _on_player_hit(_payload: Dictionary) -> void:
	_hit_flash = 1.0

func _on_passive_toggled(payload: Dictionary) -> void:
	# night-vision handled by passives system; chip highlight
	var active: bool = payload.get("active", false)
	_passive_chip_label.modulate = Color.WHITE if active else Color(1,1,1, 0.65)

# ================================================================
# Stamina wheel — inner Control drawn via _draw()
# ================================================================
class StaminaWheel extends Control:
	var _ratio: float = 1.0
	var _exhausted: bool = false
	var _accent: Color = Color("#ffe066")
	const WHEEL_R := 28.0
	const WHEEL_THICKNESS := 4.0

	func _ready() -> void:
		# position: right side of screen, center-ish vertically (BotW style)
		set_anchor(SIDE_LEFT,   1.0)
		set_anchor(SIDE_TOP,    0.5)
		set_anchor(SIDE_RIGHT,  1.0)
		set_anchor(SIDE_BOTTOM, 0.5)
		set_offset(SIDE_LEFT,  -(WHEEL_R * 2.0 + 20.0))
		set_offset(SIDE_RIGHT,  -20.0)
		set_offset(SIDE_TOP,    -(WHEEL_R + 8.0))
		set_offset(SIDE_BOTTOM,  WHEEL_R + 8.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_ratio(r: float) -> void:
		_ratio = r
		queue_redraw()

	func set_exhausted(ex: bool) -> void:
		_exhausted = ex
		queue_redraw()

	func set_accent(col: Color) -> void:
		_accent = col

	func _draw() -> void:
		var cx: float = size.x * 0.5
		var cy: float = size.y * 0.5
		# Background ring
		draw_arc(Vector2(cx, cy), WHEEL_R, 0.0, TAU, 64, Color(1,1,1, 0.08), WHEEL_THICKNESS, true)
		# Fill arc (from top = -PI/2, clockwise)
		if _ratio > 0.0:
			var arc_end: float = -PI * 0.5 + _ratio * TAU
			var fill_col: Color = Color("#ff4d5e") if _exhausted else _accent
			draw_arc(Vector2(cx, cy), WHEEL_R, -PI * 0.5, arc_end, 64, fill_col, WHEEL_THICKNESS, true)

# ================================================================
# Crosshair dot — small circle with dark outline, visible on any bg
# ================================================================
class CrosshairDot extends Control:
	var ads: bool = false
	func _draw() -> void:
		var cx: float = size.x * 0.5
		var cy: float = size.y * 0.5
		if ads:
			# Tighter aiming reticle: small center dot + thin ring + 4 ticks
			draw_circle(Vector2(cx, cy), 2.0, Color(0.0, 0.0, 0.0, 0.55))
			draw_circle(Vector2(cx, cy), 1.2, Color(1.0, 1.0, 1.0, 0.95))
			draw_arc(Vector2(cx, cy), 7.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.75), 1.0, true)
			var tick: float = 3.0
			draw_line(Vector2(cx, cy - 7.0 - tick), Vector2(cx, cy - 7.0), Color(1, 1, 1, 0.75), 1.0)
			draw_line(Vector2(cx, cy + 7.0), Vector2(cx, cy + 7.0 + tick), Color(1, 1, 1, 0.75), 1.0)
			draw_line(Vector2(cx - 7.0 - tick, cy), Vector2(cx - 7.0, cy), Color(1, 1, 1, 0.75), 1.0)
			draw_line(Vector2(cx + 7.0, cy), Vector2(cx + 7.0 + tick, cy), Color(1, 1, 1, 0.75), 1.0)
		else:
			draw_circle(Vector2(cx, cy), 4.0, Color(0.0, 0.0, 0.0, 0.55))
			draw_circle(Vector2(cx, cy), 2.5, Color(1.0, 1.0, 1.0, 0.90))
