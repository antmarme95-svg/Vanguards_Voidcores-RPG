# test_locomotion.gd — Headless unit tests for LocomotionStateMachine (PRD-003).
# Run with:
#   godot --headless --path godot --script res://tests/test_locomotion.gd
#
# Prints PASS/FAIL per check; prints "ALL_PASS" at end if all pass.

extends SceneTree

const _LSM = preload("res://gameplay/locomotion_state_machine.gd")

var _pass_count := 0
var _fail_count := 0

func _pass(name: String) -> void:
	print("PASS " + name)
	_pass_count += 1

func _fail(name: String, detail: String) -> void:
	print("FAIL " + name + ": " + detail)
	_fail_count += 1

func _assert(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass(name)
	else:
		_fail(name, detail)

# ── helpers ───────────────────────────────────────────────────────────────────
func _default_loco() -> Dictionary:
	return {
		"baseSpeed":        3.3,
		"sprintMultiplier": 2.0,
		"crouchSpeed":      1.9,
		"gravity":          24.0,
		"jumpForce":        8.4,
		"staminaDrainRate": 15.0,
		"jumpStaminaCost":  7.0,
		"facingBlend":      14.0,
		"airControl":       0.2,
		"slideVelocity":    9.0,
		"slideDecay":       8.0,
		"slideThreshold":   5.0,
		"fovBase":          50.0,
		"fovKickDeg":       8.0,
		"landingStutterPerMeter": 0.03,
		"landingStutterMax":      0.35,
	}

func _default_mult() -> Dictionary:
	return { "speedMult": 1.0, "jumpMult": 1.0, "staminaMult": 1.0 }

func _new_lsm(loco: Dictionary = {}, mult: Dictionary = {}) -> RefCounted:
	var lsm: RefCounted = _LSM.new()
	var l: Dictionary = _default_loco() if loco.is_empty() else loco
	var m: Dictionary = _default_mult() if mult.is_empty() else mult
	lsm.configure(l, m)
	return lsm

# base inp — grounded, not moving, not doing anything
func _inp_base() -> Dictionary:
	return {
		"moving":              false,
		"ix":                  0.0,
		"iz":                  0.0,
		"want_sprint":         false,
		"crouch":              false,
		"grounded":            true,
		"vel_y":               0.0,
		"horiz_speed":         0.0,
		"jump_pressed":        false,
		"stamina_ok_for_sprint": false,
		"crouch_just_pressed": false,
		"cam_yaw_changed":     false,
		"position_y":          0.0,
	}

# ── Test 1: Basic states — Idle/Run/Walk/Sprint ───────────────────────────────
func _test_basic_states() -> void:
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()
	var out: Dictionary

	# Idle when not moving & grounded
	out = lsm.tick(inp, 0.016)
	_assert(out["state"] == "IDLE", "1a: IDLE when not moving & grounded",
		"state=%s" % out["state"])

	# RUN when moving (default, no sprint)
	inp["moving"] = true
	out = lsm.tick(inp, 0.016)
	_assert(out["state"] == "RUN", "1b: RUN when moving (no sprint)",
		"state=%s" % out["state"])
	_assert(absf(out["planar_speed"] - 3.3) < 0.001, "1b: RUN speed==3.3",
		"speed=%f" % out["planar_speed"])

	# WALK when crouch+moving
	inp["crouch"] = true
	out = lsm.tick(inp, 0.016)
	_assert(out["state"] == "WALK", "1c: WALK when crouch+moving",
		"state=%s" % out["state"])
	_assert(absf(out["planar_speed"] - 1.9) < 0.001, "1c: WALK speed==1.9*mult(1.0)=1.9",
		"speed=%f" % out["planar_speed"])

	# SPRINT when want_sprint+stamina
	inp["crouch"]              = false
	inp["want_sprint"]         = true
	inp["stamina_ok_for_sprint"] = true
	out = lsm.tick(inp, 0.016)
	_assert(out["state"] == "SPRINT", "1d: SPRINT when want_sprint+stamina",
		"state=%s" % out["state"])
	_assert(absf(out["planar_speed"] - 6.6) < 0.001, "1d: SPRINT speed==6.6",
		"speed=%f" % out["planar_speed"])

# ── Test 2: Run→Sprint instant ────────────────────────────────────────────────
func _test_instant_sprint() -> void:
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()
	inp["moving"] = true

	# Tick 1: RUN
	var out1: Dictionary = lsm.tick(inp, 0.016)
	_assert(out1["state"] == "RUN", "2a: first tick is RUN",
		"state=%s" % out1["state"])

	# Tick 2: same tick, add want_sprint — must be SPRINT immediately
	inp["want_sprint"]           = true
	inp["stamina_ok_for_sprint"] = true
	var out2: Dictionary = lsm.tick(inp, 0.016)
	_assert(out2["state"] == "SPRINT", "2b: RUN→SPRINT is instant (next tick)",
		"state=%s" % out2["state"])
	_assert(absf(out2["planar_speed"] - 6.6) < 0.001,
		"2c: planar_speed==SPRINT same tick (no intermediate)",
		"speed=%f" % out2["planar_speed"])

# ── Test 3: Class multiplier ──────────────────────────────────────────────────
func _test_class_multiplier() -> void:
	var mult: Dictionary = { "speedMult": 1.5, "jumpMult": 1.0, "staminaMult": 1.0 }
	var lsm: RefCounted = _new_lsm({}, mult)
	var inp: Dictionary = _inp_base()
	inp["moving"] = true

	var out: Dictionary = lsm.tick(inp, 0.016)
	# RUN speed with speedMult=1.5 → 3.3 * 1.5 = 4.95
	_assert(out["state"] == "RUN", "3a: RUN with speedMult=1.5",
		"state=%s" % out["state"])
	var expected_run: float = 3.3 * 1.5
	_assert(absf(out["planar_speed"] - expected_run) < 0.001,
		"3b: RUN speed==3.3*1.5=%f" % expected_run,
		"speed=%f" % out["planar_speed"])

# ── Test 4: Air control ───────────────────────────────────────────────────────
func _test_air_control() -> void:
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()
	inp["moving"]   = true

	# Grounded → air_control == 1.0
	var out_g: Dictionary = lsm.tick(inp, 0.016)
	_assert(absf(out_g["air_control"] - 1.0) < 0.001, "4a: grounded air_control==1.0",
		"air_control=%f" % out_g["air_control"])

	# Go airborne (jump)
	inp["grounded"] = false
	inp["vel_y"]    = 5.0   # going up → JUMP
	var out_j: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_j["state"] == "JUMP", "4b: JUMP when vel_y>0 airborne",
		"state=%s" % out_j["state"])
	_assert(absf(out_j["air_control"] - 0.2) < 0.001, "4c: airborne air_control==0.2",
		"air_control=%f" % out_j["air_control"])

	# Falling (vel_y <= 0)
	inp["vel_y"] = -2.0
	var out_f: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_f["state"] == "FALLING", "4d: FALLING when vel_y<=0 airborne",
		"state=%s" % out_f["state"])
	_assert(absf(out_f["air_control"] - 0.2) < 0.001, "4e: FALLING air_control==0.2",
		"air_control=%f" % out_f["air_control"])

# ── Test 5: Slide ─────────────────────────────────────────────────────────────
func _test_slide() -> void:
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()
	inp["moving"] = true

	# Get into SPRINT
	inp["want_sprint"]           = true
	inp["stamina_ok_for_sprint"] = true
	var out_s: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_s["state"] == "SPRINT", "5a: setup SPRINT",
		"state=%s" % out_s["state"])

	# Trigger slide: crouch_just_pressed + horiz_speed > threshold
	inp["want_sprint"]         = false
	inp["stamina_ok_for_sprint"] = false
	inp["crouch_just_pressed"] = true
	inp["horiz_speed"]         = 7.0   # > slideThreshold (5.0)
	var out_enter: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_enter["state"] == "SLIDE", "5b: enter SLIDE on crouch_just_pressed+SPRINT+speed>threshold",
		"state=%s" % out_enter["state"])
	_assert(out_enter["sliding"] == true, "5c: sliding==true",
		"sliding=%s" % str(out_enter["sliding"]))
	_assert(out_enter["allow_attack"] == true, "5d: allow_attack==true during slide",
		"allow_attack=%s" % str(out_enter["allow_attack"]))

	# Continue sliding — rotate camera every tick (must NOT cancel slide)
	inp["crouch_just_pressed"] = false
	inp["cam_yaw_changed"]     = true
	var still_sliding: bool  = true
	var ticks_slide:   int   = 0
	var prev_speed:    float = float(out_enter["slide_speed"])
	for _i in range(30):
		var out_c: Dictionary = lsm.tick(inp, 0.05)
		if out_c["state"] != "SLIDE":
			still_sliding = false
			break
		ticks_slide += 1
		# Speed must decay
		_assert(out_c["allow_attack"] == true,
			"5e.%d: allow_attack==true during slide tick" % ticks_slide, "")
		prev_speed = float(out_c["slide_speed"])

	_assert(ticks_slide > 0, "5f: slide lasted at least 1 tick with cam_yaw_changed",
		"ticks=%d" % ticks_slide)

	# Run more ticks until we exit the slide
	var slide_exited := false
	for _i in range(60):
		var out_e: Dictionary = lsm.tick(inp, 0.05)
		if out_e["state"] != "SLIDE":
			slide_exited = true
			break
	_assert(slide_exited, "5g: slide exited after speed decayed", "never exited in 90 ticks")

# ── Test 6: Landing stutter ───────────────────────────────────────────────────
func _test_landing_stutter() -> void:
	var lsm: RefCounted = _new_lsm()

	# Small fall
	var dur_small: float = _simulate_fall(lsm, 5.0)   # 5m fall
	lsm = _new_lsm()
	var dur_large: float = _simulate_fall(lsm, 20.0)  # 20m fall

	_assert(dur_large > dur_small,
		"6a: larger fall → longer landing stutter (%f > %f)" % [dur_large, dur_small],
		"dur_small=%f dur_large=%f" % [dur_small, dur_large])

	# Also confirm lock_horizontal was true during LANDING
	lsm = _new_lsm()
	var inp: Dictionary = _inp_base()
	# Simulate: go airborne at height 10, fall to 0
	inp["grounded"]   = false
	inp["vel_y"]      = -5.0
	inp["position_y"] = 10.0
	lsm.tick(inp, 0.016)   # FALLING, record fall_start_y=10

	# Land
	inp["grounded"]   = true
	inp["vel_y"]      = 0.0
	inp["position_y"] = 0.0
	var out_land: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_land["state"] == "LANDING" and out_land["lock_horizontal"] == true,
		"6b: LANDING state has lock_horizontal==true",
		"state=%s lock=%s" % [out_land["state"], str(out_land["lock_horizontal"])])


# Simulate: start airborne at start_height, fall to 0, land, count landing duration
func _simulate_fall(lsm: RefCounted, start_height: float) -> float:
	var inp: Dictionary = _inp_base()
	# First tick airborne going up briefly just to set _was_grounded=true → false
	inp["grounded"]   = true
	inp["position_y"] = start_height
	lsm.tick(inp, 0.016)

	# Go airborne falling
	inp["grounded"]   = false
	inp["vel_y"]      = -3.0
	inp["position_y"] = start_height
	lsm.tick(inp, 0.016)   # FALLING, sets fall_start_y

	# Land
	inp["grounded"]   = true
	inp["vel_y"]      = 0.0
	inp["position_y"] = 0.0
	var out_land: Dictionary = lsm.tick(inp, 0.016)

	if out_land["state"] != "LANDING":
		return 0.0

	# Count duration until LANDING exits
	var elapsed: float = 0.0
	inp["moving"] = false
	for _i in range(200):
		var dt: float = 0.016
		var out_c: Dictionary = lsm.tick(inp, dt)
		if out_c["state"] != "LANDING":
			break
		elapsed += dt
	return elapsed

# ── Test 7: FOV ───────────────────────────────────────────────────────────────
func _test_fov() -> void:
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()
	inp["moving"]              = true
	inp["want_sprint"]         = true
	inp["stamina_ok_for_sprint"] = true

	var out_sprint: Dictionary = lsm.tick(inp, 0.016)
	var expected_sprint_fov: float = 50.0 + 8.0
	_assert(out_sprint["state"] == "SPRINT", "7a: in SPRINT for FOV test",
		"state=%s" % out_sprint["state"])
	_assert(absf(out_sprint["fov_target"] - expected_sprint_fov) < 0.001,
		"7b: fov_target==fovBase+fovKickDeg in SPRINT (%f)" % expected_sprint_fov,
		"fov_target=%f" % out_sprint["fov_target"])

	# Not sprinting → fovBase
	inp["want_sprint"]           = false
	inp["stamina_ok_for_sprint"] = false
	var out_run: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_run["state"] == "RUN", "7c: in RUN for FOV test",
		"state=%s" % out_run["state"])
	_assert(absf(out_run["fov_target"] - 50.0) < 0.001,
		"7d: fov_target==fovBase when not SPRINT",
		"fov_target=%f" % out_run["fov_target"])

# ── entry point ───────────────────────────────────────────────────────────────
func _init() -> void:
	_test_basic_states()
	_test_instant_sprint()
	_test_class_multiplier()
	_test_air_control()
	_test_slide()
	_test_landing_stutter()
	_test_fov()

	print("")
	if _fail_count == 0:
		print("ALL_PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _fail_count)
		quit(1)
