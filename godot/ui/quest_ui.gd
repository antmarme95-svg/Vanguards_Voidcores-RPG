# quest_ui.gd — Quest tracker widget + Conqueror's Choice overlay + end card.
# Port of QuestUI.js with Godot Control nodes.
class_name QuestUI extends CanvasLayer

# ---- color constants ----
const COL_INK      := Color("#eaf6ff")
const COL_INK_DIM  := Color(0.918, 0.965, 1.0, 0.5)
const COL_PANEL    := Color(0.039, 0.063, 0.086, 0.88)
const COL_GOLD     := Color("#ffc94d")
const COL_DONE     := Color(0.4, 0.9, 0.55, 0.9)

# ---- state ----
var _accent: Color = Color("#46e6ff")

# ---- nodes ----
var _tracker_panel: PanelContainer
var _tracker_title: Label
var _tracker_objectives: VBoxContainer
var _tracker_path: Label
var _choice_overlay: Control
var _end_card: Control

# ================================================================
func _ready() -> void:
	layer = 7
	_build_tracker()
	_build_choice_overlay()
	_build_end_card()

	EventBus.on("quest:update",      _on_quest_update)
	EventBus.on("ui:choiceRequested", _on_choice_requested)
	EventBus.on("ui:endCardRequested", _on_end_card_requested)

# ================================================================
func _build_tracker() -> void:
	_tracker_panel = PanelContainer.new()
	_tracker_panel.set_anchor(SIDE_LEFT,   1.0)
	_tracker_panel.set_anchor(SIDE_TOP,    0.0)
	_tracker_panel.set_anchor(SIDE_RIGHT,  1.0)
	_tracker_panel.set_anchor(SIDE_BOTTOM, 0.0)
	_tracker_panel.set_offset(SIDE_LEFT,  -276)
	_tracker_panel.set_offset(SIDE_RIGHT,  -16)
	_tracker_panel.set_offset(SIDE_TOP,    44)
	_tracker_panel.set_offset(SIDE_BOTTOM, 0)
	# Panel auto-sizes vertically to content; fix horizontal width explicitly
	_tracker_panel.custom_minimum_size = Vector2(260, 0)
	_tracker_panel.visible = false
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.02, 0.04, 0.06, 0.80)
	ps.border_width_left   = 1
	ps.border_width_top    = 0
	ps.border_width_right  = 0
	ps.border_width_bottom = 0
	ps.border_color = Color(_accent.r, _accent.g, _accent.b, 0.35)
	ps.content_margin_left   = 12
	ps.content_margin_right  = 12
	ps.content_margin_top    = 10
	ps.content_margin_bottom = 10
	_tracker_panel.add_theme_stylebox_override("panel", ps)
	add_child(_tracker_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_tracker_panel.add_child(vbox)

	_tracker_title = Label.new()
	_tracker_title.add_theme_font_size_override("font_size", 11)
	_tracker_title.add_theme_color_override("font_color", _accent)
	_tracker_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tracker_title)

	_tracker_objectives = VBoxContainer.new()
	_tracker_objectives.add_theme_constant_override("separation", 3)
	vbox.add_child(_tracker_objectives)

	_tracker_path = Label.new()
	_tracker_path.add_theme_font_size_override("font_size", 10)
	_tracker_path.add_theme_color_override("font_color", COL_INK_DIM)
	_tracker_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tracker_path)

func _build_choice_overlay() -> void:
	_choice_overlay = Control.new()
	_choice_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_overlay.visible = false
	add_child(_choice_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.80)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_overlay.add_child(bg)

func _build_end_card() -> void:
	_end_card = Control.new()
	_end_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_card.visible = false
	add_child(_end_card)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_card.add_child(bg)

# ================================================================
# Quest tracker update
# ================================================================
func render_quest(quest_tracker) -> void:
	var q: Dictionary = quest_tracker.quest
	if q.is_empty():
		_tracker_panel.visible = false
		return
	_tracker_panel.visible = true
	_tracker_title.text = q.get("title", "")

	for child in _tracker_objectives.get_children():
		_tracker_objectives.remove_child(child)
		child.queue_free()

	var objectives: Array = q.get("objectives", [])
	for obj in objectives:
		if not obj.get("visible", false):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_tracker_objectives.add_child(row)

		var check := Label.new()
		check.text = "✓" if obj.get("done", false) else "○"
		check.add_theme_font_size_override("font_size", 11)
		check.add_theme_color_override("font_color", COL_DONE if obj.get("done", false) else COL_INK_DIM)
		check.custom_minimum_size.x = 14
		row.add_child(check)

		var obj_lbl := Label.new()
		var count_text := ""
		if obj.has("total"):
			count_text = " (%d/%d)" % [obj.get("count", 0), obj.get("total", 0)]
		obj_lbl.text = obj.get("text", "") + count_text
		obj_lbl.add_theme_font_size_override("font_size", 11)
		var obj_col: Color = COL_INK_DIM if obj.get("done", false) else COL_INK
		obj_lbl.add_theme_color_override("font_color", obj_col)
		obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		obj_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(obj_lbl)

	_tracker_path.text = "⛨ " + q.get("pathLabel", "")

# ================================================================
# Choice overlay
# ================================================================
func show_choice(options: Array, on_pick: Callable) -> void:
	# Clear previous content
	for child in _choice_overlay.get_children():
		if child is ColorRect:
			continue  # keep the bg
		_choice_overlay.remove_child(child)
		child.queue_free()

	var center_box := VBoxContainer.new()
	center_box.add_theme_constant_override("separation", 20)
	center_box.set_anchor(SIDE_LEFT,   0.1)
	center_box.set_anchor(SIDE_TOP,    0.1)
	center_box.set_anchor(SIDE_RIGHT,  0.9)
	center_box.set_anchor(SIDE_BOTTOM, 0.9)
	_choice_overlay.add_child(center_box)

	var heading := Label.new()
	heading.text = "THE CONQUEROR'S CHOICE"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", COL_INK)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(heading)

	var sub := Label.new()
	sub.text = "The Core is ash and the contract is fulfilled — this time.\nBut a mercenary's loyalty is a market, and three buyers are already bidding.\nHow will you handle the purges to come?"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COL_INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_box.add_child(sub)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.add_child(cards_row)

	for opt in options:
		var path_col: Color = Color(opt.get("color", "#46e6ff"))

		# Outer PanelContainer: drives size, has the styled border/bg
		var card_panel := PanelContainer.new()
		card_panel.custom_minimum_size = Vector2(300, 320)
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_panel.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(path_col.r, path_col.g, path_col.b, 0.08)
		cs.border_width_left   = 2
		cs.border_width_right  = 2
		cs.border_width_top    = 2
		cs.border_width_bottom = 2
		cs.border_color = path_col
		cs.content_margin_left   = 16
		cs.content_margin_right  = 16
		cs.content_margin_top    = 20
		cs.content_margin_bottom = 20
		cs.corner_radius_top_left     = 3
		cs.corner_radius_top_right    = 3
		cs.corner_radius_bottom_left  = 3
		cs.corner_radius_bottom_right = 3
		card_panel.add_theme_stylebox_override("panel", cs)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 12)
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_panel.add_child(card_vbox)

		var letter_lbl := Label.new()
		letter_lbl.text = opt.get("letter", "")
		letter_lbl.add_theme_font_size_override("font_size", 11)
		letter_lbl.add_theme_color_override("font_color", path_col)
		letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(letter_lbl)

		var name_lbl := Label.new()
		name_lbl.text = opt.get("name", "")
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", path_col)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(name_lbl)

		var sep_line := HSeparator.new()
		var sep_style := StyleBoxFlat.new()
		sep_style.bg_color = Color(path_col.r, path_col.g, path_col.b, 0.35)
		sep_line.add_theme_stylebox_override("separator", sep_style)
		card_vbox.add_child(sep_line)

		var desc_lbl := Label.new()
		desc_lbl.text = opt.get("desc", "")
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", COL_INK_DIM)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_child(desc_lbl)

		# Clickable button overlay
		var card_btn := Button.new()
		card_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_btn.flat = true
		card_btn.focus_mode = Control.FOCUS_NONE
		var t_style := StyleBoxFlat.new()
		t_style.bg_color = Color(0, 0, 0, 0)
		card_btn.add_theme_stylebox_override("normal",  t_style)
		var h_style := t_style.duplicate() as StyleBoxFlat
		h_style.bg_color = Color(path_col.r, path_col.g, path_col.b, 0.12)
		card_btn.add_theme_stylebox_override("hover",   h_style)
		card_btn.add_theme_stylebox_override("pressed", h_style)
		card_btn.add_theme_stylebox_override("focus",   t_style)
		var opt_id: String = opt.get("id", "")
		card_btn.pressed.connect(func() -> void:
			_choice_overlay.visible = false
			on_pick.call(opt_id)
		)
		card_panel.add_child(card_btn)
		cards_row.add_child(card_panel)

	_choice_overlay.visible = true

# ================================================================
# End card
# ================================================================
func show_end_card(save_ref: SaveState, chosen_path: String, on_continue: Callable) -> void:
	# Clear previous
	for child in _end_card.get_children():
		if child is ColorRect:
			continue
		_end_card.remove_child(child)
		child.queue_free()

	# Get path name
	var path_label: String = "—"
	var path_buf: Dictionary = PathsData.PATH_BUFFS.get(chosen_path, {})
	if not path_buf.is_empty():
		path_label = path_buf.get("label", chosen_path)

	var minutes: int = max(1, int((Time.get_unix_time_from_system() * 1000.0 - float(save_ref.started_at)) / 60000.0))

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 18)
	center.set_anchor(SIDE_LEFT,   0.2)
	center.set_anchor(SIDE_TOP,    0.2)
	center.set_anchor(SIDE_RIGHT,  0.8)
	center.set_anchor(SIDE_BOTTOM, 0.8)
	_end_card.add_child(center)

	var title_lbl := Label.new()
	title_lbl.text = "CONTRACT: ACTIVE"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", COL_INK)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title_lbl)

	var origin: Dictionary = save_ref.get_origin()
	var body_lbl := Label.new()
	body_lbl.text = save_ref.player_name + " of the " + origin.get("name", "Unknown") + " walks The Wilds under a signed\nConqueror's Contract — and a private agenda: " + path_label + ".\n\nThe vertical slice ends here. The continent doesn't."
	body_lbl.add_theme_font_size_override("font_size", 13)
	body_lbl.add_theme_color_override("font_color", COL_INK_DIM)
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(body_lbl)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stats_row)

	for stat_data in [
		["field time", str(minutes) + "m"],
		["maddened purged", str(save_ref.kills)],
		["cores shattered", str(save_ref.cores_purged)],
	]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		stats_row.add_child(col)
		var val_lbl := Label.new()
		val_lbl.text = stat_data[1]
		val_lbl.add_theme_font_size_override("font_size", 20)
		val_lbl.add_theme_color_override("font_color", _accent)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val_lbl)
		var name_lbl := Label.new()
		name_lbl.text = stat_data[0]
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", COL_INK_DIM)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)

	var cont_btn := Button.new()
	cont_btn.text = "Keep Roaming The Wilds"
	cont_btn.focus_mode = Control.FOCUS_NONE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(_accent.r, _accent.g, _accent.b, 0.15)
	bs.border_width_left   = 1
	bs.border_width_right  = 1
	bs.border_width_top    = 1
	bs.border_width_bottom = 1
	bs.border_color = _accent
	bs.content_margin_left   = 16
	bs.content_margin_right  = 16
	bs.content_margin_top    = 10
	bs.content_margin_bottom = 10
	cont_btn.add_theme_stylebox_override("normal",  bs)
	cont_btn.add_theme_stylebox_override("hover",   bs)
	cont_btn.add_theme_stylebox_override("pressed", bs)
	cont_btn.add_theme_stylebox_override("focus",   bs)
	cont_btn.add_theme_color_override("font_color", _accent)
	cont_btn.add_theme_font_size_override("font_size", 14)
	cont_btn.pressed.connect(func() -> void:
		_end_card.visible = false
		on_continue.call()
	)
	center.add_child(cont_btn)

	_end_card.visible = true

# ================================================================
# Event bus handlers
# ================================================================
func _on_quest_update(payload: Dictionary) -> void:
	var qt = payload.get("tracker", null)
	if qt != null:
		render_quest(qt)

func _on_choice_requested(payload: Dictionary) -> void:
	var options: Array = payload.get("options", [])
	# director.pick_path is referenced from the director's perspective;
	# the overlay calls it via EventBus or a stored callable.
	# We emit ui:pathChosen which the director must handle.
	show_choice(options, func(opt_id: String) -> void:
		EventBus.emit_event("ui:pathChosen", {"path_id": opt_id})
	)

func _on_end_card_requested(payload: Dictionary) -> void:
	var save_ref: SaveState = payload.get("save", null)
	if save_ref == null:
		return
	show_end_card(save_ref, save_ref.chosen_path, func() -> void:
		EventBus.emit_event("ui:continueRoam", {})
	)

func set_accent_color(col: Color) -> void:
	_accent = col
	# Retint tracker border
	if _tracker_panel != null:
		var ps := _tracker_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		ps.border_color = Color(col.r, col.g, col.b, 0.35)
		_tracker_panel.add_theme_stylebox_override("panel", ps)
	if _tracker_title != null:
		_tracker_title.add_theme_color_override("font_color", col)
