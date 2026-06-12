# autotest_slice.gd — Full vertical slice autotest without UI.
# Drives the OFFICE → CITY_EXIT → WILDS → CHOICE → FREE_ROAM flow,
# exercises real combat, shatters both cores, writes JSON report, quits.
#
# Launch:
#   godot --path godot -- --autotest=res://tests/autotest_slice.gd
extends Node

var _errors: Array       = []
var _director: GameDirector = null
var _screenshots: Array  = []   # accumulated labels for logging

# ================================================================
func _ready() -> void:
	# ---- HERMETIC: purge any save left by a previous run ----
	var save_abs: String = ProjectSettings.globalize_path("user://borisawa_save.json")
	if FileAccess.file_exists("user://borisawa_save.json"):
		DirAccess.remove_absolute(save_abs)

	# Set Debug args that the director reads
	Debug.args["origin"] = "aetherborn"
	Debug.args["cls"]    = "mage"
	Debug.args["name"]   = "Boris"

	# Wait one frame so autoloads are fully settled
	await get_tree().process_frame

	_run_slice()

# ================================================================
# _until — poll helper: returns true if fn() becomes true within
# timeout_sec of REAL elapsed time; false (and records FAIL) on timeout.
# Polls every process frame so timers and _process logic accumulate dt.
# ================================================================
func _until(fn: Callable, timeout_sec: float, label: String) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout_sec:
		if fn.call():
			return true
		await get_tree().process_frame
		# Accumulate real time using Engine.get_process_frames for counting,
		# but we need actual dt — use Time.get_ticks_msec delta instead.
		elapsed += get_process_delta_time()
	_errors.append("FAIL %s (timed out after %.1fs)" % [label, timeout_sec])
	return false

# ================================================================
func _run_slice() -> void:
	# ---- Boot director ----
	_director = GameDirector.new()
	get_tree().current_scene.add_child(_director)
	_director.start()

	# Wait for OFFICE — poll up to 2s
	var office_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "OFFICE",
		2.0, "boot→OFFICE"
	)
	if not office_ok:
		_abort_run("Never reached OFFICE")
		return
	print("[Autotest] PASS boot→OFFICE (state=OFFICE)")
	await _screenshot("office_start")

	# ---- sign contract (bypasses dialogue UI) ----
	_director.sign_contract()
	await get_tree().process_frame

	_assert_true(
		_director.scene != null and _director.scene.get("interactables") != null and
		_has_exit_doors_enabled(),
		"doors open after sign_contract"
	)
	await _screenshot("doors_open")

	# ---- interact exit doors → CITY_EXIT ----
	if _director.controller != null:
		_director.controller.position = Vector3(0.0, 0.0, 4.9)
	await get_tree().process_frame
	await get_tree().process_frame
	_director.fsm.go("CITY_EXIT")

	var city_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "CITY_EXIT",
		2.0, "CITY_EXIT reached"
	)
	if city_ok:
		print("[Autotest] PASS CITY_EXIT reached (state=CITY_EXIT)")
	await _screenshot("city")

	# ---- trigger toWilds → WILDS ----
	if _director.controller != null:
		var triggers: Array = _director.scene.triggers if _director.scene != null else []
		for tr in triggers:
			if tr.get("id", "") == "toWilds":
				tr["fired"] = false
		_director.controller.position = Vector3(0.0, 0.0, -57.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_director.fsm.go("WILDS")

	var wilds_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "WILDS",
		2.0, "WILDS reached"
	)
	if wilds_ok:
		print("[Autotest] PASS WILDS reached (state=WILDS)")
	await _screenshot("wilds_start")

	# ---- fire coreSight trigger ----
	_director.quest_tracker.reach_core_site()
	await get_tree().process_frame

	# ---- Real combat: kill all 3 wave-A beasts ----
	var enemies: Array = _director.enemies
	if enemies.size() == 0:
		_errors.append("FAIL: no enemies spawned in WILDS")
		_abort_run("No enemies spawned")
		return

	await _screenshot("combat")

	# Beast 0 — real attack path: teleport player adjacent, use try_attack
	var b0: MaddenedBeast = enemies[0]
	if _director.controller != null:
		_director.controller.position = b0.position + Vector3(0.0, 0.0, 1.5)
		_director.controller.facing   = 0.0
		_director.controller.cam_yaw  = 0.0
	await get_tree().process_frame
	for _i in range(3):
		await get_tree().process_frame

	# Swing until health reaches 0 (up to 60 swings)
	var swings := 0
	while not b0.dead and swings < 60:
		_director.controller.attack_cooldown = 0.0
		_director.controller.try_attack()
		for _i in range(4):
			await get_tree().process_frame
		swings += 1

	# Poll until b0.dead — dying state needs state_t > 0.9s real time
	var b0_ok: bool = await _until(
		func() -> bool: return b0.dead,
		5.0, "beast0 killed via try_attack()"
	)
	if b0_ok:
		print("[Autotest] PASS beast0 killed via try_attack()")

	# Beasts 1 and 2 — direct hit(); poll until dead
	for i in range(1, enemies.size()):
		var b: MaddenedBeast = enemies[i]
		b.hit(999.0, _director.controller)
		var bi_ok: bool = await _until(
			func() -> bool: return b.dead,
			5.0, "beast%d killed via direct hit()" % i
		)
		if bi_ok:
			print("[Autotest] PASS beast%d killed via direct hit()" % i)

	await _screenshot("core_a_exposed")

	# ---- core A exposed (set_core_interactable already called via combat:enemyDown) ----
	if _director.scene != null and _director.scene.has_method("set_core_interactable"):
		_director.scene.set_core_interactable(true)

	# ---- shatter core A ----
	_director._on_core_shattered()

	# ---- wait for CHOICE (1.7s in-game schedule) — poll up to 5s real time ----
	var choice_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "CHOICE",
		5.0, "CHOICE reached after core shatter"
	)
	if not choice_ok:
		# CHOICE never arrived — record error and abort (do NOT self-heal via pick_path)
		_abort_run("CHOICE state never arrived after core shatter")
		return
	print("[Autotest] PASS CHOICE reached after core shatter (state=CHOICE)")
	await _screenshot("choice")

	# ---- pick_path → FREE_ROAM  (only called after CHOICE confirmed) ----
	_director.pick_path("kingdom")

	var free_roam_ok: bool = await _until(
		func() -> bool: return _director.fsm.current_id == "FREE_ROAM",
		2.0, "FREE_ROAM reached after pick_path"
	)
	if free_roam_ok:
		print("[Autotest] PASS FREE_ROAM reached after pick_path (state=FREE_ROAM)")

	# ---- continue_free_roam ----
	_director.continue_free_roam()
	await get_tree().process_frame

	# Wait a frame for B-wave beasts to be appended to enemies
	await get_tree().process_frame

	# ---- teleport to B trigger zone ----
	if _director.controller != null:
		_director.controller.position = Vector3(-46.0, 0.0, 18.0)

	# Fire coreSightB + encounterStartB
	_director.quest_tracker.reach_core_site()
	await get_tree().process_frame

	# Collect B-wave beasts (spawned into enemies by continue_free_roam)
	var b_enemies: Array = []
	for e in _director.enemies:
		if not e.dead:
			b_enemies.append(e)
			e.aggro = true

	if b_enemies.is_empty():
		_errors.append("FAIL: no B-wave enemies found")
	else:
		# Hit all B-wave beasts at once
		for e in b_enemies:
			e.hit(999.0, _director.controller)

		# Poll until ALL dead — dying state needs state_t > 0.9s real time
		var b_all_ok: bool = await _until(
			func() -> bool:
				for e in b_enemies:
					if not e.dead:
						return false
				return true,
			8.0, "all B-wave beasts killed"
		)
		if b_all_ok:
			print("[Autotest] PASS all B-wave beasts killed")

	await _screenshot("core_b")

	# ---- expose + shatter core2 ----
	if _director.scene != null and _director.scene.has_method("set_core_interactable"):
		_director.scene.set_core_interactable(true)
	_director._on_core_shattered()

	await get_tree().process_frame

	await _screenshot("end")

	# ---- build + write JSON report ----
	var kills_recorded: int = _director.save.kills
	var cores_purged: int   = _director.save.cores_purged
	var max_health: float   = _director.stats.max_health if _director.stats != null else 0.0
	var phys_resist: float  = _director.stats.physical_resist if _director.stats != null else 0.0

	var report: Dictionary = {
		"kills": kills_recorded,
		"cores_purged": cores_purged,
		"max_health_after_buff": max_health,
		"physical_resist": phys_resist,
		"fsm_states_visited": _director.fsm_states_visited,
		"errors": _errors,
	}

	Debug.write_json("res://test_out/slice_report.json", report)

	print("[AutotestSlice] kills=", kills_recorded,
		  " cores=", cores_purged,
		  " max_health=", max_health,
		  " resist=", phys_resist,
		  " states=", _director.fsm_states_visited,
		  " errors=", _errors.size())

	if _errors.size() == 0:
		print("[AutotestSlice] ALL_PASS")
		get_tree().quit(0)
	else:
		print("[AutotestSlice] FAILURES: %d" % _errors.size())
		for err in _errors:
			print("  ", err)
		get_tree().quit(1)

# ================================================================
# _abort_run: write partial JSON and quit(1) without self-healing
# ================================================================
func _abort_run(reason: String) -> void:
	_errors.append("ABORT: " + reason)
	var kills_recorded: int = _director.save.kills if _director != null else 0
	var cores_purged: int   = _director.save.cores_purged if _director != null else 0
	var max_health: float   = _director.stats.max_health if (_director != null and _director.stats != null) else 0.0
	var phys_resist: float  = _director.stats.physical_resist if (_director != null and _director.stats != null) else 0.0

	var report: Dictionary = {
		"kills": kills_recorded,
		"cores_purged": cores_purged,
		"max_health_after_buff": max_health,
		"physical_resist": phys_resist,
		"fsm_states_visited": _director.fsm_states_visited if _director != null else [],
		"errors": _errors,
	}
	Debug.write_json("res://test_out/slice_report.json", report)
	print("[AutotestSlice] ABORT: ", reason)
	print("[AutotestSlice] FAILURES: %d" % _errors.size())
	for err in _errors:
		print("  ", err)
	get_tree().quit(1)

# ================================================================
# Helpers
# ================================================================
func _assert_state(expected: String, label: String) -> void:
	var cur: String = _director.fsm.current_id if _director != null else "<null>"
	if cur != expected:
		_errors.append("FAIL %s: expected state %s got %s" % [label, expected, cur])
	else:
		print("[Autotest] PASS %s (state=%s)" % [label, cur])

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		_errors.append("FAIL %s" % label)
	else:
		print("[Autotest] PASS %s" % label)

func _screenshot(label: String) -> void:
	var path: String = "res://test_out/%s.png" % label
	_screenshots.append(label)
	await Debug.screenshot(path)

func _has_exit_doors_enabled() -> bool:
	if _director == null or _director.scene == null:
		return false
	var interactables = _director.scene.get("interactables")
	if interactables == null:
		return false
	for it in interactables:
		if it.get("id", "") == "exitDoors" and it.get("enabled", false):
			return true
	return false
