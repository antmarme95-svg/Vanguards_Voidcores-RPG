# dialogue_ui.gd — Letterbox dialogue + Conqueror's Contract parchment + hold-to-sign.
# Port of DialogueUI.js with Godot Control nodes.
class_name DialogueUI extends CanvasLayer

const CHARS_PER_SEC := 64.0
const HOLD_DURATION := 1.1   # seconds to complete signing
const HOLD_DECAY    := 1.6   # multiplier for reverse drain

# ---- color constants ----
const COL_INK      := Color("#eaf6ff")
const COL_INK_DIM  := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL    := Color(0.039, 0.063, 0.086, 0.92)
const COL_PARCHMENT:= Color(0.98, 0.94, 0.82, 1.0)
const COL_INK_DARK := Color(0.08, 0.14, 0.22, 1.0)
const COL_SEPIA    := Color(0.55, 0.38, 0.18, 0.9)

# ---- state ----
var _tree: Dictionary = {}
var _node_id: String = ""
var _current_node: Dictionary = {}
var _full_text: String = ""
var _shown_chars: int = 0
var _typing_elapsed: float = 0.0
var _typing: bool = false
var _on_action: Callable
var _accent: Color = Color("#46e6ff")

# hold-to-sign state
var _holding: bool = false
var _sign_progress: float = 0.0
var _sign_done: bool = false
var _on_signed: Callable

# ---- UI nodes ----
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _dlg_box: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _choices_container: VBoxContainer
var _continue_label: Label
var _contract_panel: Control
var _sign_progress_bar: ColorRect
var _sign_line_drawn: bool = false
var _sign_line: Line2D
var _sign_name_label: Label
var _sign_btn: Button

# ================================================================
func _ready() -> void:
	layer = 8
	_build_letterbox()
	_build_dialogue_box()
	_build_contract_panel()
	visible = false

# ================================================================
func _build_letterbox() -> void:
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color(0, 0, 0, 0.88)
	_letterbox_top.set_anchor(SIDE_LEFT,   0.0)
	_letterbox_top.set_anchor(SIDE_TOP,    0.0)
	_letterbox_top.set_anchor(SIDE_RIGHT,  1.0)
	_letterbox_top.set_anchor(SIDE_BOTTOM, 0.0)
	_letterbox_top.set_offset(SIDE_BOTTOM, 60)
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_top)

	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color(0, 0, 0, 0.88)
	_letterbox_bottom.set_anchor(SIDE_LEFT,   0.0)
	_letterbox_bottom.set_anchor(SIDE_TOP,    1.0)
	_letterbox_bottom.set_anchor(SIDE_RIGHT,  1.0)
	_letterbox_bottom.set_anchor(SIDE_BOTTOM, 1.0)
	_letterbox_bottom.set_offset(SIDE_TOP,   -200)
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_bottom)

func _build_dialogue_box() -> void:
	_dlg_box = PanelContainer.new()
	_dlg_box.set_anchor(SIDE_LEFT,   0.1)
	_dlg_box.set_anchor(SIDE_TOP,    1.0)
	_dlg_box.set_anchor(SIDE_RIGHT,  0.9)
	_dlg_box.set_anchor(SIDE_BOTTOM, 1.0)
	_dlg_box.set_offset(SIDE_TOP,   -194)
	_dlg_box.set_offset(SIDE_BOTTOM,  -6)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.07, 0.94)
	ps.border_width_left   = 1
	ps.border_width_right  = 1
	ps.border_width_top    = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(1,1,1, 0.10)
	ps.content_margin_left   = 18
	ps.content_margin_right  = 18
	ps.content_margin_top    = 12
	ps.content_margin_bottom = 10
	_dlg_box.add_theme_stylebox_override("panel", ps)
	_dlg_box.visible = false  # hidden until open_dialogue — is_open() reads this
	add_child(_dlg_box)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	_dlg_box.add_child(inner)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 13)
	_speaker_label.add_theme_color_override("font_color", _accent)
	inner.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 13)
	_text_label.add_theme_color_override("font_color", COL_INK)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size.y = 80
	inner.add_child(_text_label)

	_choices_container = VBoxContainer.new()
	_choices_container.add_theme_constant_override("separation", 4)
	inner.add_child(_choices_container)

	_continue_label = Label.new()
	_continue_label.text = "E / click — continue"
	_continue_label.add_theme_font_size_override("font_size", 11)
	_continue_label.add_theme_color_override("font_color", COL_INK_DIM)
	_continue_label.visible = false
	inner.add_child(_continue_label)

	# Click-to-advance on the whole box
	var adv_btn := Button.new()
	adv_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	adv_btn.flat = true
	adv_btn.focus_mode = Control.FOCUS_NONE
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	adv_btn.add_theme_stylebox_override("normal",  transparent)
	adv_btn.add_theme_stylebox_override("hover",   transparent)
	adv_btn.add_theme_stylebox_override("pressed", transparent)
	adv_btn.add_theme_stylebox_override("focus",   transparent)
	adv_btn.pressed.connect(_advance)
	_dlg_box.add_child(adv_btn)

func _build_contract_panel() -> void:
	_contract_panel = Control.new()
	_contract_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_contract_panel.visible = false
	add_child(_contract_panel)

	# Semi-opaque dark background
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_contract_panel.add_child(bg)

	# Parchment scroll area — centered
	var scroll_wrap := PanelContainer.new()
	scroll_wrap.set_anchor(SIDE_LEFT,   0.15)
	scroll_wrap.set_anchor(SIDE_TOP,    0.05)
	scroll_wrap.set_anchor(SIDE_RIGHT,  0.85)
	scroll_wrap.set_anchor(SIDE_BOTTOM, 0.95)
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_PARCHMENT
	ps.border_width_left   = 2
	ps.border_width_right  = 2
	ps.border_width_top    = 2
	ps.border_width_bottom = 2
	ps.border_color = Color(0.6, 0.4, 0.2, 0.8)
	ps.content_margin_left   = 28
	ps.content_margin_right  = 28
	ps.content_margin_top    = 20
	ps.content_margin_bottom = 20
	ps.corner_radius_top_left     = 3
	ps.corner_radius_top_right    = 3
	ps.corner_radius_bottom_left  = 3
	ps.corner_radius_bottom_right = 3
	scroll_wrap.add_theme_stylebox_override("panel", ps)
	_contract_panel.add_child(scroll_wrap)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_wrap.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	scroll_wrap.set_meta("content", content)
	scroll_wrap.set_meta("scroll", scroll)

	# Signature zone + sign button are added dynamically in open_contract()

# ================================================================
# Public API
# ================================================================
func is_open() -> bool:
	return _dlg_box.visible

func start_tree(tree: Dictionary, on_action_cb: Callable, speaker_accent: Color = _accent) -> void:
	_tree = tree
	_on_action = on_action_cb
	_accent = speaker_accent
	_speaker_label.add_theme_color_override("font_color", _accent)
	visible = true
	_dlg_box.visible = true
	_show_node(tree.get("start", "greet"))

func jump_to(node_id: String) -> void:
	_dlg_box.visible = true
	_show_node(node_id)

func close_dialogue() -> void:
	_dlg_box.visible = false
	_typing = false

# ================================================================
func _show_node(id: String) -> void:
	if not _tree.has("nodes"):
		return
	var nodes: Dictionary = _tree["nodes"]
	if not nodes.has(id):
		push_error("[DialogueUI] missing node: " + id)
		close_dialogue()
		return
	_node_id = id
	_current_node = nodes[id]
	_speaker_label.text = _current_node.get("speaker", "")
	_choices_container.visible = false
	for child in _choices_container.get_children():
		_choices_container.remove_child(child)
		child.queue_free()
	_continue_label.visible = false

	# Typewriter
	_full_text = _current_node.get("text", "")
	_text_label.text = ""
	_shown_chars = 0
	_typing_elapsed = 0.0
	_typing = true

func _process(dt: float) -> void:
	if not visible:
		return
	if _typing:
		_typing_elapsed += dt
		var target_chars: int = mini(int(_typing_elapsed * CHARS_PER_SEC), _full_text.length())
		if target_chars != _shown_chars:
			_shown_chars = target_chars
			_text_label.text = _full_text.substr(0, _shown_chars)
		if _shown_chars >= _full_text.length():
			_typing = false
			_on_text_done()

	# Hold-to-sign update
	if _contract_panel.visible and not _sign_done:
		if is_instance_valid(_sign_progress_bar):
			_sign_progress += (HOLD_DURATION if _holding else -HOLD_DURATION * HOLD_DECAY) * dt / HOLD_DURATION
			_sign_progress = clampf(_sign_progress, 0.0, 1.0)
			_sign_progress_bar.set_anchor(SIDE_RIGHT, _sign_progress)
			if _sign_progress >= 1.0:
				_sign_done = true
				_complete_signature()

func _on_text_done() -> void:
	var choices = _current_node.get("choices", null)
	if choices != null:
		_choices_container.visible = true
		for choice in choices:
			var btn := Button.new()
			btn.text = choice.get("label", "")
			btn.focus_mode = Control.FOCUS_NONE
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 12)
			var s := StyleBoxFlat.new()
			s.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.08)
			s.border_width_left   = 1
			s.border_color = Color(_accent.r, _accent.g, _accent.b, 0.3)
			s.content_margin_left   = 10
			s.content_margin_right  = 10
			s.content_margin_top    = 6
			s.content_margin_bottom = 6
			btn.add_theme_stylebox_override("normal",  s)
			btn.add_theme_stylebox_override("hover",   s)
			btn.add_theme_stylebox_override("pressed", s)
			btn.add_theme_stylebox_override("focus",   s)
			btn.add_theme_color_override("font_color", COL_INK)
			var next_id: String = choice.get("next", "")
			btn.pressed.connect(func() -> void: _show_node(next_id))
			_choices_container.add_child(btn)
	else:
		_continue_label.visible = true

func _advance() -> void:
	if _typing:
		# fast-forward
		_typing = false
		_shown_chars = _full_text.length()
		_text_label.text = _full_text
		_on_text_done()
		return
	if not _current_node.is_empty() and _current_node.has("choices"):
		return  # choices advance themselves
	var action: String = _current_node.get("action", "")
	if action != "":
		_dlg_box.visible = false
		_on_action.call(action)
	elif _current_node.has("next"):
		_show_node(_current_node["next"])

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _dlg_box.visible:
		return
	if event is InputEventKey and event.pressed:
		var kc: int = (event as InputEventKey).keycode
		if kc == KEY_E or kc == KEY_ENTER or kc == KEY_SPACE:
			_advance()

# ================================================================
# Contract panel
# ================================================================
func open_contract(origin: Dictionary, player_name: String, on_signed_cb: Callable) -> void:
	_on_signed = on_signed_cb
	_sign_progress = 0.0
	_sign_done = false
	_holding = false
	_sign_line_drawn = false

	# Rebuild content
	var scroll_wrap: PanelContainer = _contract_panel.get_child(1) as PanelContainer
	var content: VBoxContainer = scroll_wrap.get_meta("content")

	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

	# Title
	var head := Label.new()
	head.text = "THE CONQUEROR'S CONTRACT"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", COL_INK_DARK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(head)

	var sub := Label.new()
	sub.text = origin.get("city", {}).get("name", "") + " · " + origin.get("recruiter", {}).get("title", "")
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", COL_SEPIA)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)

	# Clauses
	var clauses: Array = ContractData.get_contract_clauses(origin, player_name)
	for clause in clauses:
		var ch_lbl := Label.new()
		ch_lbl.text = clause.get("h", "")
		ch_lbl.add_theme_font_size_override("font_size", 12)
		ch_lbl.add_theme_color_override("font_color", COL_INK_DARK)
		content.add_child(ch_lbl)

		var body_lbl := Label.new()
		var body_text: String = clause.get("body", "")
		# Strip simple HTML bold tags for plain display
		body_text = body_text.replace("<b>", "").replace("</b>", "")
		body_lbl.text = body_text
		body_lbl.add_theme_font_size_override("font_size", 11)
		body_lbl.add_theme_color_override("font_color", COL_SEPIA)
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(body_lbl)

	# Signature line
	var sep := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = COL_SEPIA
	sep.add_theme_stylebox_override("separator", ss)
	content.add_child(sep)

	var sign_zone := VBoxContainer.new()
	sign_zone.add_theme_constant_override("separation", 8)
	content.add_child(sign_zone)

	var sign_hint := Label.new()
	sign_hint.text = "signature of the asset"
	sign_hint.add_theme_font_size_override("font_size", 10)
	sign_hint.add_theme_color_override("font_color", COL_SEPIA)
	sign_zone.add_child(sign_hint)

	# Signature Line2D (scrawl revealed on sign)
	_sign_line = Line2D.new()
	_sign_line.width = 2.0
	_sign_line.default_color = COL_INK_DARK
	_sign_line.visible = false
	# Line2D extends Node2D, not Control — no custom_minimum_size; add a spacer instead
	sign_zone.add_child(_sign_line)
	var line_spacer := Control.new()
	line_spacer.custom_minimum_size = Vector2(0, 30)
	sign_zone.add_child(line_spacer)

	_sign_name_label = Label.new()
	_sign_name_label.text = player_name
	_sign_name_label.add_theme_font_size_override("font_size", 16)
	_sign_name_label.add_theme_color_override("font_color", Color(0.12, 0.22, 0.7, 0.0))
	sign_zone.add_child(_sign_name_label)

	# Hold-to-sign button
	var btn_wrap := PanelContainer.new()
	sign_zone.add_child(btn_wrap)
	var bw_style := StyleBoxFlat.new()
	bw_style.bg_color = Color(0.1, 0.15, 0.25, 0.9)
	bw_style.border_width_left   = 1
	bw_style.border_width_right  = 1
	bw_style.border_width_top    = 1
	bw_style.border_width_bottom = 1
	bw_style.border_color = _accent
	btn_wrap.add_theme_stylebox_override("panel", bw_style)

	var btn_inner := Control.new()
	btn_inner.custom_minimum_size = Vector2(0, 38)
	btn_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_wrap.add_child(btn_inner)

	_sign_progress_bar = ColorRect.new()
	_sign_progress_bar.color = Color(_accent.r, _accent.g, _accent.b, 0.25)
	_sign_progress_bar.set_anchor(SIDE_LEFT,   0.0)
	_sign_progress_bar.set_anchor(SIDE_TOP,    0.0)
	_sign_progress_bar.set_anchor(SIDE_RIGHT,  0.0)  # driven by _sign_progress
	_sign_progress_bar.set_anchor(SIDE_BOTTOM, 1.0)
	_sign_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_inner.add_child(_sign_progress_bar)

	_sign_btn = Button.new()
	_sign_btn.text = "HOLD TO SIGN"
	_sign_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sign_btn.flat = true
	_sign_btn.focus_mode = Control.FOCUS_NONE
	_sign_btn.add_theme_font_size_override("font_size", 13)
	_sign_btn.add_theme_color_override("font_color", _accent)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0, 0, 0, 0)
	_sign_btn.add_theme_stylebox_override("normal",  tb)
	_sign_btn.add_theme_stylebox_override("hover",   tb)
	_sign_btn.add_theme_stylebox_override("pressed", tb)
	_sign_btn.add_theme_stylebox_override("focus",   tb)
	_sign_btn.button_down.connect(func() -> void: _holding = true)
	_sign_btn.button_up.connect(func() -> void: _holding = false)
	btn_inner.add_child(_sign_btn)

	_contract_panel.visible = true

func _complete_signature() -> void:
	_sign_btn.disabled = true
	_sign_btn.text = "SIGNED"
	_sign_line.visible = true
	# Animate scrawl: add points over 0.9s via a tween
	var tween := get_tree().create_tween()
	var points: Array[Vector2] = [
		Vector2(8, 22), Vector2(30, 8), Vector2(50, 28), Vector2(70, 12),
		Vector2(95, 26), Vector2(120, 10), Vector2(148, 24), Vector2(172, 14),
		Vector2(196, 22), Vector2(210, 18),
	]
	# Reveal points progressively
	var delay: float = 0.0
	for i in range(points.size()):
		var pt: Vector2 = points[i]
		var cap_i := i
		tween.tween_callback(func() -> void:
			_sign_line.add_point(pt)
		).set_delay(delay)
		delay += 0.09

	# Fade in name
	var name_tween := get_tree().create_tween()
	name_tween.tween_interval(0.7)
	name_tween.tween_property(_sign_name_label, "theme_override_colors/font_color",
		Color(0.12, 0.22, 0.7, 0.85), 0.5)

	# Close contract, fire callback
	var close_tween := get_tree().create_tween()
	close_tween.tween_interval(1.7)
	close_tween.tween_callback(func() -> void:
		_contract_panel.visible = false
		_on_signed.call()
	)

# public complete path for autotest (bypasses the hold UI)
func complete_sign() -> void:
	if _sign_done:
		return
	_sign_progress = 1.0
	_sign_done = true
	_complete_signature()
