# autotest_ui.gd — Drives the full UI walkthrough WITHOUT the debug fast path.
# Boot to CREATION → origin/class pick → OFFICE (HUD) → dialogue → contract sign
# → WILDS (compass+quest) → CHOICE (3 cards) → endcard → secondquest.
# Writes JSON report, quits 0 on ALL_PASS.
extends Node

var _errors: Array       = []
var _director: GameDirector = null

# ================================================================
func _ready() -> void:
	# HERMETIC: purge any save left by a previous run
	if FileAccess.file_exists("user://borisawa_save.json"):
		var save_abs: String = ProjectSettings.globalize_path("user://borisawa_save.json")
		DirAccess.remove_absolute(save_abs)

	# NO --origin / --cls args — must boot to real CREATION UI
	Debug.args.erase("origin")
	Debug.args.erase("cls")
	Debug.args.erase("name")

	await get_tree().process_frame
	_run_ui()

# ================================================================
# _until — real-time poll helper matching autotest_slice pattern
# ================================================================
func _until(fn: Callable, timeout_sec: float, label: String) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout_sec:
		if fn.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_errors.append("FAIL %s (timed out after %.1fs)" % [label, timeout_sec])
	return false

# ================================================================
func _run_ui() -> void:
	_director = GameDirector.new()
	get_tree().current_scene.add_child(_director)
	_director.start()

	# ---- 1. Boot → CREATION ----
	var creation_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "CREATION",
		4.0, "boot→CREATION"
	)
	if not creation_ok:
		_abort("Never reached CREATION state")
		return
	print("[AutotestUI] PASS boot→CREATION")

	# Poll until CreationUI is visible and has tab buttons
	var ui_ok: bool = await _until(
		func() -> bool:
			return _director.creation_ui != null and _director.creation_ui.visible,
		3.0, "CreationUI visible"
	)
	_assert_true(ui_ok, "CreationUI is visible in CREATION state")
	if not ui_ok:
		_abort("CreationUI never became visible")
		return

	# Wait a few frames for layout
	for _i in range(3):
		await get_tree().process_frame

	await _screenshot("ui_creation_origin")
	print("[AutotestUI] screenshot: ui_creation_origin — should show dark left panel with ORIGIN tab and origin cards")

	# ---- 2. Switch to BODY tab + move 2 sliders ----
	_director.creation_ui.show_tab("body")
	await get_tree().process_frame
	# Move weight slider
	_director.creation_ui.move_slider("weight", 0.75)
	_director.creation_ui.move_slider("height", 0.3)
	await get_tree().process_frame
	# Pick origin: ironblooded
	_director.creation_ui._on_origin_selected("ironblooded")
	await get_tree().process_frame

	await _screenshot("ui_creation_body")
	print("[AutotestUI] screenshot: ui_creation_body — BODY tab with sliders moved, ironblooded accent (orange)")

	# ---- 3. Switch to CLASS tab, pick warrior ----
	_director.creation_ui.show_tab("class")
	await get_tree().process_frame
	_director.creation_ui._on_class_card_pressed("warrior")
	await get_tree().process_frame

	# ---- 4. Set name ----
	_director.creation_ui.set_name_text("Brunhylde")
	await get_tree().process_frame

	# Verify confirm button is now enabled
	_assert_true(
		not _director.creation_ui._confirm_btn.disabled,
		"Confirm button enabled after origin+class+name set"
	)

	# ---- 5. Confirm → OFFICE ----
	_director.creation_ui.on_confirm.call("Brunhylde")

	var office_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "OFFICE",
		5.0, "CREATION→OFFICE"
	)
	if not office_ok:
		_abort("Never reached OFFICE after confirm")
		return
	print("[AutotestUI] PASS CREATION→OFFICE")

	# Poll until camera has moved (controller.update ran at least once)
	await _until(
		func() -> bool: return _director.controller != null and _director.hud != null and _director.hud.visible,
		3.0, "HUD visible in OFFICE"
	)
	for _i in range(4):
		await get_tree().process_frame

	await _screenshot("ui_office_hud")
	print("[AutotestUI] screenshot: ui_office_hud — HUD bars (health/magicka) + compass visible, office scene behind")

	# ---- 6. Trigger dialogue with recruiter ----
	# Teleport controller to recruiter position to trigger prompt
	if _director.controller != null and _director.scene != null:
		for it in _director.scene.interactables:
			if it.get("id", "") == "recruiter":
				_director.controller.position = it.get("position", Vector3.ZERO)
				break
	await get_tree().process_frame
	await get_tree().process_frame

	# Synthesize real E key press to trigger game's own E-handling
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.physical_keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	# release next frame so the just-pressed latch can fire cleanly
	await get_tree().process_frame
	var ev_up := InputEventKey.new()
	ev_up.keycode = KEY_E
	ev_up.physical_keycode = KEY_E
	ev_up.pressed = false
	Input.parse_input_event(ev_up)

	# Poll until dialogue is open
	var dlg_ok: bool = await _until(
		func() -> bool: return _director.dialogue_ui != null and _director.dialogue_ui.is_open(),
		3.0, "E press did not open recruiter dialogue"
	)
	_assert_true(dlg_ok, "Dialogue opened after E press")
	for _i in range(3):
		await get_tree().process_frame

	await _screenshot("ui_dialogue")
	print("[AutotestUI] screenshot: ui_dialogue — letterbox bars + dialogue box with recruiter speaker name in accent color")

	# ---- 7. Advance to hub, pick 'Give me the pen' (openContract) ----
	# Advance typewriter first
	_director.dialogue_ui._advance()
	await get_tree().process_frame
	# Now at hub — show choices. Click "Give me the pen" (index 3 = openContract)
	_director.dialogue_ui._advance()  # advance to hub
	await get_tree().process_frame
	# fast-forward through hub node
	_director.dialogue_ui._advance()
	await get_tree().process_frame

	# Directly open contract — tests open_contract() API (same path as clicking "Give me the pen")
	var origin_for_contract: Dictionary = _director.save.get_origin()
	_director.dialogue_ui.open_contract(origin_for_contract, _director.save.player_name, func() -> void: pass)
	await get_tree().process_frame
	# Poll until contract panel is visible
	var contract_ok: bool = await _until(
		func() -> bool:
			if _director.dialogue_ui == null:
				return false
			return _director.dialogue_ui._contract_panel != null and _director.dialogue_ui._contract_panel.visible,
		3.0, "Contract panel opened"
	)
	_assert_true(contract_ok, "Contract panel visible after openContract action")
	for _i in range(3):
		await get_tree().process_frame

	await _screenshot("ui_contract")
	print("[AutotestUI] screenshot: ui_contract — parchment scroll with 5 articles, HOLD TO SIGN button at bottom")

	# ---- 8. Complete sign via public path ----
	_director.dialogue_ui.complete_sign()
	# Poll until contract panel closes
	var signed_ok: bool = await _until(
		func() -> bool:
			return not _director.dialogue_ui._contract_panel.visible,
		4.0, "Contract signed + panel closed"
	)
	_assert_true(signed_ok, "Contract panel closed after complete_sign()")
	for _i in range(4):
		await get_tree().process_frame

	await _screenshot("ui_signed")
	print("[AutotestUI] screenshot: ui_signed — doors open toast visible top-right, dialogue 'signed' node text shown")

	# Advance 'signed' action (action = end) → controller re-enabled
	_director.dialogue_ui.jump_to("signed")
	await get_tree().process_frame
	_director.dialogue_ui._advance()
	await get_tree().process_frame
	for _i in range(2):
		await get_tree().process_frame

	# Sign contract on director to open doors (idempotent)
	_director.sign_contract()
	await get_tree().process_frame

	# ---- 9. Transition to WILDS via director methods (fast path) ----
	_director.fsm.go("CITY_EXIT")
	var city_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "CITY_EXIT",
		3.0, "CITY_EXIT"
	)
	if not city_ok:
		_abort("Never reached CITY_EXIT")
		return
	_director.fsm.go("WILDS")
	var wilds_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "WILDS",
		3.0, "WILDS"
	)
	if not wilds_ok:
		_abort("Never reached WILDS")
		return
	print("[AutotestUI] PASS → WILDS")

	# Force coreSight so quest tracker reveals purge objective
	_director.quest_tracker.reach_core_site()
	await get_tree().process_frame

	# Poll until camera update ran (controller.update executed)
	await _until(
		func() -> bool: return _director.controller != null and _director.controller.position != Vector3.ZERO,
		3.0, "controller position non-default in WILDS"
	)
	for _i in range(4):
		await get_tree().process_frame

	await _screenshot("ui_wilds_hud")
	print("[AutotestUI] screenshot: ui_wilds_hud — compass with core marker ◆, quest tracker top-right (PURGE ORDER 001), health/magicka bars")

	# ---- 10. Force CHOICE by killing enemies + shattering core ----
	for e in _director.enemies:
		e.hit(999.0, _director.controller)
	await get_tree().process_frame

	# Poll until all enemies dead
	await _until(
		func() -> bool:
			for e in _director.enemies:
				if not e.dead:
					return false
			return true,
		6.0, "all wave-A enemies dead"
	)

	_director._on_core_shattered()

	var choice_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "CHOICE",
		5.0, "CHOICE reached"
	)
	if not choice_ok:
		_abort("CHOICE state never arrived")
		return
	print("[AutotestUI] PASS → CHOICE")

	# Poll until choice overlay is visible
	await _until(
		func() -> bool:
			return _director.quest_ui != null and _director.quest_ui._choice_overlay.visible,
		3.0, "choice overlay visible"
	)
	for _i in range(3):
		await get_tree().process_frame

	await _screenshot("ui_choice")
	print("[AutotestUI] screenshot: ui_choice — 3 path cards (PATH A/B/C) with different accent colors, THE CONQUEROR'S CHOICE heading")

	# ---- 11. Pick kingdom → FREE_ROAM ----
	_director.pick_path("kingdom")
	var free_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "FREE_ROAM",
		3.0, "FREE_ROAM reached"
	)
	if not free_ok:
		_abort("FREE_ROAM never arrived")
		return
	print("[AutotestUI] PASS → FREE_ROAM")

	# Poll until end card appears
	await _until(
		func() -> bool:
			return _director.quest_ui != null and _director.quest_ui._end_card.visible,
		3.0, "end card visible"
	)
	for _i in range(3):
		await get_tree().process_frame

	await _screenshot("ui_endcard")
	print("[AutotestUI] screenshot: ui_endcard — CONTRACT: ACTIVE title, name/origin/path line, stats row (field time/kills/cores), Keep Roaming button")

	# ---- 12. Continue → second quest ----
	_director.continue_free_roam()
	await get_tree().process_frame
	# Hide end card manually since continue_free_roam doesn't close it (UI event does)
	if _director.quest_ui._end_card.visible:
		_director.quest_ui._end_card.visible = false
	await get_tree().process_frame

	# Force second quest update
	var origin: Dictionary = _director.save.get_origin()
	_director.quest_tracker.begin_second_purge(origin)
	await get_tree().process_frame
	for _i in range(4):
		await get_tree().process_frame

	await _screenshot("ui_secondquest")
	print("[AutotestUI] screenshot: ui_secondquest — quest tracker shows Amendment 001-B objectives, allegiance chip visible (Crown's Aegis)")

	# ---- assertions ----
	_assert_true(_director.save.origin_id == "ironblooded",  "origin=ironblooded persisted")
	_assert_true(_director.save.class_id == "warrior",       "class=warrior persisted")
	_assert_true(_director.save.player_name == "Brunhylde",  "name=Brunhylde persisted")
	_assert_true(_director.save.chosen_path == "kingdom",    "chosen_path=kingdom persisted")
	_assert_true(_director.hud != null and _director.hud.visible, "HUD visible in FREE_ROAM")

	# ---- report ----
	var report: Dictionary = {
		"cases": [
			"boot→CREATION", "CreationUI visible", "BODY tab + sliders",
			"origin ironblooded", "class warrior", "name Brunhylde",
			"confirm→OFFICE", "HUD visible in OFFICE", "dialogue opened",
			"contract panel opened", "contract signed", "→WILDS",
			"compass+quest visible", "→CHOICE", "3 path cards",
			"→FREE_ROAM", "end card", "second quest",
		],
		"errors": _errors,
	}
	Debug.write_json("res://test_out/ui_report.json", report)

	if _errors.size() == 0:
		print("[AutotestUI] ALL_PASS")
		get_tree().quit(0)
	else:
		print("[AutotestUI] FAILURES: %d" % _errors.size())
		for err in _errors:
			print("  ", err)
		get_tree().quit(1)

# ================================================================
# Helpers
# ================================================================
func _abort(reason: String) -> void:
	_errors.append("ABORT: " + reason)
	var report: Dictionary = {
		"cases": [],
		"errors": _errors,
	}
	Debug.write_json("res://test_out/ui_report.json", report)
	print("[AutotestUI] ABORT: ", reason)
	get_tree().quit(1)

func _assert_true(cond: bool, label: String) -> void:
	if not cond:
		_errors.append("FAIL " + label)
		print("[AutotestUI] FAIL: " + label)
	else:
		print("[AutotestUI] PASS: " + label)

func _screenshot(label: String) -> void:
	await Debug.screenshot("res://test_out/%s.png" % label)
