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
	# Sprint L3: _speed_walk = baseSpeed(3.3) * crouchStealthMult(0.5 default) * speedMult(1.0) = 1.65
	inp["crouch"] = true
	out = lsm.tick(inp, 0.016)
	_assert(out["state"] == "WALK", "1c: WALK when crouch+moving",
		"state=%s" % out["state"])
	_assert(absf(out["planar_speed"] - 1.65) < 0.001, "1c: WALK speed==base(3.3)*stealth(0.5)*mult(1.0)=1.65",
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
	# airborne air_control now comes from _air_control_pct; default cmult has no
	# airControlPct key, so it falls back to 0.5 (balanced tier built-in default).
	_assert(absf(out_j["air_control"] - 0.5) < 0.001, "4c: airborne air_control==0.5 (balanced default)",
		"air_control=%f" % out_j["air_control"])

	# Falling (vel_y <= 0)
	inp["vel_y"] = -2.0
	var out_f: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_f["state"] == "FALLING", "4d: FALLING when vel_y<=0 airborne",
		"state=%s" % out_f["state"])
	_assert(absf(out_f["air_control"] - 0.5) < 0.001, "4e: FALLING air_control==0.5 (balanced default)",
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

# ── Test 8: Per-subclass physiometry profile differentiation (Sprint L0) ─────
# Verifies that HEAVY/LIGHT/BALANCED profiles produce distinct sprint speeds
# and airborne air_control values.
func _test_profile_differentiation() -> void:
	# ---- Profile mults ----
	var heavy: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 0.85, "jumpMult": 0.75,
		"massMult": 1.5, "slideFriction": 0.96, "airControlPct": 0.20,
		"crouchStealthMult": 0.40, "slideSteerMaxDeg": 0, "staminaMult": 1.0,
	}
	var balanced: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 1.0, "jumpMult": 1.0,
		"massMult": 1.0, "slideFriction": 0.92, "airControlPct": 0.50,
		"crouchStealthMult": 0.50, "slideSteerMaxDeg": 22, "staminaMult": 1.0,
	}
	var light: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 1.25, "jumpMult": 1.3,
		"massMult": 0.8, "slideFriction": 0.88, "airControlPct": 0.75,
		"crouchStealthMult": 0.60, "slideSteerMaxDeg": 45, "staminaMult": 1.0,
	}

	var lsm_h: RefCounted = _new_lsm({}, heavy)
	var lsm_b: RefCounted = _new_lsm({}, balanced)
	var lsm_l: RefCounted = _new_lsm({}, light)

	# ---- Sprint speed: LIGHT > BALANCED > HEAVY ----
	# Expected: baseSpeed(3.3) * sprintMult(2.0) * speedMult(1.0) * sprintSpeedMult
	var inp_sprint: Dictionary = _inp_base()
	inp_sprint["moving"]              = true
	inp_sprint["want_sprint"]         = true
	inp_sprint["stamina_ok_for_sprint"] = true

	var out_h_sprint: Dictionary = lsm_h.tick(inp_sprint, 0.016)
	var out_b_sprint: Dictionary = lsm_b.tick(inp_sprint, 0.016)
	var out_l_sprint: Dictionary = lsm_l.tick(inp_sprint, 0.016)

	var exp_heavy:    float = 3.3 * 2.0 * 1.0 * 0.85
	var exp_balanced: float = 3.3 * 2.0 * 1.0 * 1.0
	var exp_light:    float = 3.3 * 2.0 * 1.0 * 1.25

	_assert(out_h_sprint["state"] == "SPRINT", "8a: HEAVY profile → SPRINT state",
		"state=%s" % out_h_sprint["state"])
	_assert(absf(out_h_sprint["planar_speed"] - exp_heavy) < 0.001,
		"8b: HEAVY sprint speed==%f" % exp_heavy,
		"speed=%f" % out_h_sprint["planar_speed"])
	_assert(absf(out_b_sprint["planar_speed"] - exp_balanced) < 0.001,
		"8c: BALANCED sprint speed==%f" % exp_balanced,
		"speed=%f" % out_b_sprint["planar_speed"])
	_assert(absf(out_l_sprint["planar_speed"] - exp_light) < 0.001,
		"8d: LIGHT sprint speed==%f" % exp_light,
		"speed=%f" % out_l_sprint["planar_speed"])
	_assert(out_l_sprint["planar_speed"] > out_b_sprint["planar_speed"],
		"8e: LIGHT sprint speed > BALANCED sprint speed",
		"light=%f balanced=%f" % [out_l_sprint["planar_speed"], out_b_sprint["planar_speed"]])
	_assert(out_b_sprint["planar_speed"] > out_h_sprint["planar_speed"],
		"8f: BALANCED sprint speed > HEAVY sprint speed",
		"balanced=%f heavy=%f" % [out_b_sprint["planar_speed"], out_h_sprint["planar_speed"]])

	# ---- Airborne air_control equals profile's airControlPct ----
	# Reset each LSM with fresh instances to clear FSM state
	var lsm_h2: RefCounted = _new_lsm({}, heavy)
	var lsm_l2: RefCounted = _new_lsm({}, light)

	# Drive airborne: grounded=false, vel_y<0 → FALLING
	var inp_fall: Dictionary = _inp_base()
	inp_fall["grounded"] = false
	inp_fall["vel_y"]    = -2.0
	inp_fall["moving"]   = true

	var out_h_fall: Dictionary = lsm_h2.tick(inp_fall, 0.016)
	var out_l_fall: Dictionary = lsm_l2.tick(inp_fall, 0.016)

	_assert(out_h_fall["state"] == "FALLING", "8g: HEAVY airborne → FALLING",
		"state=%s" % out_h_fall["state"])
	_assert(absf(out_h_fall["air_control"] - 0.20) < 0.001,
		"8h: HEAVY airborne air_control==0.20",
		"air_control=%f" % out_h_fall["air_control"])
	_assert(out_l_fall["state"] == "FALLING", "8i: LIGHT airborne → FALLING",
		"state=%s" % out_l_fall["state"])
	_assert(absf(out_l_fall["air_control"] - 0.75) < 0.001,
		"8j: LIGHT airborne air_control==0.75",
		"air_control=%f" % out_l_fall["air_control"])

# ── Test 9: Sprint L1 — momentum slide model ─────────────────────────────────
func _test_momentum_slide() -> void:
	# Shared profile dicts (matching class_multipliers.json values).
	var heavy_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 0.85, "jumpMult": 0.75,
		"massMult": 1.5, "slideFriction": 0.96, "airControlPct": 0.20,
		"crouchStealthMult": 0.40, "slideSteerMaxDeg": 0, "staminaMult": 1.0,
	}
	var light_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 1.25, "jumpMult": 1.3,
		"massMult": 0.8, "slideFriction": 0.88, "airControlPct": 0.75,
		"crouchStealthMult": 0.60, "slideSteerMaxDeg": 45, "staminaMult": 1.0,
	}

	# ── 9a/9b: 85% entry gate ────────────────────────────────────────────────
	# Default profile: sprint = 3.3 * 2.0 * 1.0 * 1.0 = 6.6; 85% gate = 5.61.
	var lsm_gate: RefCounted = _new_lsm()
	var inp_gate: Dictionary = _inp_base()
	inp_gate["moving"]              = true
	inp_gate["want_sprint"]         = true
	inp_gate["stamina_ok_for_sprint"] = true
	lsm_gate.tick(inp_gate, 0.016)   # reach SPRINT state

	# 9a: horiz_speed=6.0 > 5.61 → should enter SLIDE
	inp_gate["want_sprint"]           = false
	inp_gate["stamina_ok_for_sprint"] = false
	inp_gate["crouch_just_pressed"]   = true
	inp_gate["horiz_speed"]           = 6.0
	var out_gate_pass: Dictionary = lsm_gate.tick(inp_gate, 0.016)
	_assert(out_gate_pass["state"] == "SLIDE",
		"9a: entry gate — horiz_speed=6.0 (>85% of 6.6) → SLIDE",
		"state=%s" % out_gate_pass["state"])

	# 9b: fresh LSM, horiz_speed=5.0 < 5.61 → must NOT enter slide
	var lsm_gate2: RefCounted = _new_lsm()
	var inp_gate2: Dictionary = _inp_base()
	inp_gate2["moving"]              = true
	inp_gate2["want_sprint"]         = true
	inp_gate2["stamina_ok_for_sprint"] = true
	lsm_gate2.tick(inp_gate2, 0.016)   # reach SPRINT
	inp_gate2["want_sprint"]           = false
	inp_gate2["stamina_ok_for_sprint"] = false
	inp_gate2["crouch_just_pressed"]   = true
	inp_gate2["horiz_speed"]           = 5.0
	var out_gate_fail: Dictionary = lsm_gate2.tick(inp_gate2, 0.016)
	_assert(out_gate_fail["state"] != "SLIDE",
		"9b: entry gate — horiz_speed=5.0 (<85% of 6.6) → NOT SLIDE",
		"state=%s" % out_gate_fail["state"])

	# ── 9c/9d: init velocity proportional to mass ────────────────────────────
	# Entry speed = 8.0 for both.
	# HEAVY massMult=1.5 → init = 8.0 * (1 + 1.5*0.15) = 8.0 * 1.225 = 9.8
	# LIGHT  massMult=0.8 → init = 8.0 * (1 + 0.8*0.15) = 8.0 * 1.12  = 8.96
	# HEAVY sprint = 3.3*2.0*1.0*0.85 = 5.61; clamp ceil = 5.61*2 = 11.22 → no clamp at 9.8
	# LIGHT sprint = 3.3*2.0*1.0*1.25 = 8.25; clamp ceil = 16.5 → no clamp at 8.96
	var entry_speed: float = 8.0

	var lsm_h_init: RefCounted = _new_lsm({}, heavy_mult)
	var inp_h_init: Dictionary = _inp_base()
	inp_h_init["moving"]              = true
	inp_h_init["want_sprint"]         = true
	inp_h_init["stamina_ok_for_sprint"] = true
	lsm_h_init.tick(inp_h_init, 0.016)   # SPRINT
	inp_h_init["want_sprint"]           = false
	inp_h_init["stamina_ok_for_sprint"] = false
	inp_h_init["crouch_just_pressed"]   = true
	inp_h_init["horiz_speed"]           = entry_speed
	var out_h_init: Dictionary = lsm_h_init.tick(inp_h_init, 0.016)

	var lsm_l_init: RefCounted = _new_lsm({}, light_mult)
	var inp_l_init: Dictionary = _inp_base()
	inp_l_init["moving"]              = true
	inp_l_init["want_sprint"]         = true
	inp_l_init["stamina_ok_for_sprint"] = true
	lsm_l_init.tick(inp_l_init, 0.016)   # SPRINT
	inp_l_init["want_sprint"]           = false
	inp_l_init["stamina_ok_for_sprint"] = false
	inp_l_init["crouch_just_pressed"]   = true
	inp_l_init["horiz_speed"]           = entry_speed
	var out_l_init: Dictionary = lsm_l_init.tick(inp_l_init, 0.016)

	_assert(out_h_init["state"] == "SLIDE",
		"9c: HEAVY entered SLIDE (horiz_speed=8.0 > 85% of 5.61=4.77)",
		"state=%s" % out_h_init["state"])
	_assert(out_l_init["state"] == "SLIDE",
		"9c2: LIGHT entered SLIDE (horiz_speed=8.0 > 85% of 8.25=7.01)",
		"state=%s" % out_l_init["state"])

	var h_init_speed: float = out_h_init["slide_speed"]
	var l_init_speed: float = out_l_init["slide_speed"]
	var exp_heavy_init: float = entry_speed * (1.0 + 1.5 * 0.15)   # 9.8
	var exp_light_init: float = entry_speed * (1.0 + 0.8 * 0.15)   # 8.96

	_assert(h_init_speed > l_init_speed,
		"9d: HEAVY init slide_speed > LIGHT init slide_speed (heavier = more momentum)",
		"heavy=%f light=%f" % [h_init_speed, l_init_speed])
	_assert(absf(h_init_speed - exp_heavy_init) < 0.05,
		"9d2: HEAVY init slide_speed ≈ 9.8 (tol 0.05)",
		"got=%f exp=%f" % [h_init_speed, exp_heavy_init])
	_assert(absf(l_init_speed - exp_light_init) < 0.05,
		"9d3: LIGHT init slide_speed ≈ 8.96 (tol 0.05)",
		"got=%f exp=%f" % [l_init_speed, exp_light_init])

	# ── 9e: friction decay — HEAVY decays slower than LIGHT ─────────────────
	# Tick 20 frames (dt=1/60) after entry; Heavy(0.96) loses 4%/frame, Light(0.88) 12%/frame.
	var lsm_h_fric: RefCounted = _new_lsm({}, heavy_mult)
	var inp_h_fric: Dictionary = _inp_base()
	inp_h_fric["moving"]              = true
	inp_h_fric["want_sprint"]         = true
	inp_h_fric["stamina_ok_for_sprint"] = true
	lsm_h_fric.tick(inp_h_fric, 0.016)
	inp_h_fric["want_sprint"]           = false
	inp_h_fric["stamina_ok_for_sprint"] = false
	inp_h_fric["crouch_just_pressed"]   = true
	inp_h_fric["horiz_speed"]           = 8.0
	lsm_h_fric.tick(inp_h_fric, 0.016)   # enter slide
	inp_h_fric["crouch_just_pressed"]   = false
	inp_h_fric["horiz_speed"]           = 0.0
	var h_speed_after: float = 0.0
	for _i in range(20):
		var o: Dictionary = lsm_h_fric.tick(inp_h_fric, 1.0 / 60.0)
		h_speed_after = o["slide_speed"]

	var lsm_l_fric: RefCounted = _new_lsm({}, light_mult)
	var inp_l_fric: Dictionary = _inp_base()
	inp_l_fric["moving"]              = true
	inp_l_fric["want_sprint"]         = true
	inp_l_fric["stamina_ok_for_sprint"] = true
	lsm_l_fric.tick(inp_l_fric, 0.016)
	inp_l_fric["want_sprint"]           = false
	inp_l_fric["stamina_ok_for_sprint"] = false
	inp_l_fric["crouch_just_pressed"]   = true
	inp_l_fric["horiz_speed"]           = 8.0
	lsm_l_fric.tick(inp_l_fric, 0.016)   # enter slide
	inp_l_fric["crouch_just_pressed"]   = false
	inp_l_fric["horiz_speed"]           = 0.0
	var l_speed_after: float = 0.0
	for _i in range(20):
		var o: Dictionary = lsm_l_fric.tick(inp_l_fric, 1.0 / 60.0)
		l_speed_after = o["slide_speed"]

	_assert(h_speed_after > l_speed_after,
		"9e: after 20 friction frames, HEAVY slide_speed > LIGHT slide_speed (slower decay)",
		"heavy=%f light=%f" % [h_speed_after, l_speed_after])

	# ── 9f: steer cap getter ─────────────────────────────────────────────────
	var lsm_steer_l: RefCounted = _new_lsm({}, light_mult)
	var lsm_steer_h: RefCounted = _new_lsm({}, heavy_mult)
	_assert(absf(lsm_steer_l.get_slide_steer_max_deg() - 45.0) < 0.001,
		"9f: LIGHT get_slide_steer_max_deg()==45",
		"got=%f" % lsm_steer_l.get_slide_steer_max_deg())
	_assert(absf(lsm_steer_h.get_slide_steer_max_deg() - 0.0) < 0.001,
		"9g: HEAVY get_slide_steer_max_deg()==0",
		"got=%f" % lsm_steer_h.get_slide_steer_max_deg())

# ── Test 10: Sprint L2 — slide→jump leap ─────────────────────────────────────
func _test_slide_jump_leap() -> void:
	# Profile mults (reuse from test 9).
	var heavy_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 0.85, "jumpMult": 0.75,
		"massMult": 1.5, "slideFriction": 0.96, "airControlPct": 0.20,
		"crouchStealthMult": 0.40, "slideSteerMaxDeg": 0, "staminaMult": 1.0,
	}
	var light_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 1.25, "jumpMult": 1.3,
		"massMult": 0.8, "slideFriction": 0.88, "airControlPct": 0.75,
		"crouchStealthMult": 0.60, "slideSteerMaxDeg": 45, "staminaMult": 1.0,
	}

	# ── 10a–10e: Balanced profile leap ──────────────────────────────────────────
	var lsm: RefCounted = _new_lsm()
	var inp: Dictionary = _inp_base()

	# Step 1: get into SPRINT.
	inp["moving"]              = true
	inp["want_sprint"]         = true
	inp["stamina_ok_for_sprint"] = true
	lsm.tick(inp, 0.016)

	# Step 2: enter SLIDE (crouch_just_pressed + horiz_speed above 85% gate).
	# Default sprint = 6.6; 85% gate = 5.61; use 7.0 to clear it.
	inp["want_sprint"]           = false
	inp["stamina_ok_for_sprint"] = false
	inp["crouch_just_pressed"]   = true
	inp["horiz_speed"]           = 7.0
	var out_slide: Dictionary = lsm.tick(inp, 0.016)
	_assert(out_slide["state"] == "SLIDE", "10a: entered SLIDE before leap",
		"state=%s" % out_slide["state"])
	_assert(out_slide["sliding"] == true, "10a2: sliding==true before leap",
		"sliding=%s" % str(out_slide["sliding"]))
	# Record slide_speed from the entry frame; the next tick applies one friction step.
	var slide_speed_entry: float = float(out_slide["slide_speed"])

	# Step 3: on the NEXT tick, apply one friction step then jump.
	inp["crouch_just_pressed"] = false
	inp["horiz_speed"]         = 0.0
	inp["jump_pressed"]        = true
	# One continuation tick (friction applies before jump check).
	# Expected slide_speed after one friction step: slide_speed_entry * pow(0.92, 0.016*60) ≈ * 0.92^0.96
	# We just read it from the output to keep the test data-driven.
	var out_leap: Dictionary = lsm.tick(inp, 0.016)

	_assert(out_leap["state"] == "JUMP", "10b: state==JUMP after slide→jump",
		"state=%s" % out_leap["state"])
	_assert(out_leap["sliding"] == false, "10c: sliding==false after leap",
		"sliding=%s" % str(out_leap["sliding"]))
	_assert(out_leap["jump_velocity"] > 0.0, "10d: jump_velocity>0 after leap",
		"jump_velocity=%f" % out_leap["jump_velocity"])

	# launch_speed should ≈ slide_speed_BEFORE_jump * 0.90 (within tolerance 0.05).
	# The slide_speed after one friction step = slide_speed_entry * pow(0.92, 0.016*60).
	var slide_speed_before_jump: float = slide_speed_entry * pow(0.92, 0.016 * 60.0)
	var expected_launch: float         = slide_speed_before_jump * 0.90
	var actual_launch: float           = float(out_leap.get("launch_speed", -1.0))
	_assert(absf(actual_launch - expected_launch) < 0.05,
		"10e: launch_speed≈slide_speed_before*0.90 (tol 0.05, exp=%f)" % expected_launch,
		"launch_speed=%f expected=%f" % [actual_launch, expected_launch])

	# ── 10f/10g: jump_velocity differs between Heavy and Light ──────────────────
	# jumpForce(8.4) * jumpMult(0.75) = 6.3 for Heavy; * 1.3 = 10.92 for Light.
	# Both must have sliding==false and jump_velocity > 0; Light jump_vel > Heavy jump_vel.
	var _setup_and_leap := func(mult: Dictionary) -> Dictionary:
		var l: RefCounted = _new_lsm({}, mult)
		var i: Dictionary = _inp_base()
		i["moving"] = true
		i["want_sprint"] = true
		i["stamina_ok_for_sprint"] = true
		l.tick(i, 0.016)
		i["want_sprint"] = false
		i["stamina_ok_for_sprint"] = false
		i["crouch_just_pressed"] = true
		i["horiz_speed"] = 9.0   # clears both gates (Heavy 4.77, Light 7.01)
		l.tick(i, 0.016)   # enter slide
		i["crouch_just_pressed"] = false
		i["horiz_speed"] = 0.0
		i["jump_pressed"] = true
		return l.tick(i, 0.016)

	var out_h: Dictionary = _setup_and_leap.call(heavy_mult)
	var out_l: Dictionary = _setup_and_leap.call(light_mult)

	_assert(out_h["state"] == "JUMP" and out_h["jump_velocity"] > 0.0,
		"10f: HEAVY leap → state==JUMP and jump_velocity>0",
		"state=%s jv=%f" % [out_h["state"], out_h["jump_velocity"]])
	_assert(out_l["state"] == "JUMP" and out_l["jump_velocity"] > 0.0,
		"10g: LIGHT leap → state==JUMP and jump_velocity>0",
		"state=%s jv=%f" % [out_l["state"], out_l["jump_velocity"]])
	_assert(out_l["jump_velocity"] > out_h["jump_velocity"],
		"10h: LIGHT jump_velocity > HEAVY jump_velocity (jumpMult 1.3 vs 0.75)",
		"light=%f heavy=%f" % [out_l["jump_velocity"], out_h["jump_velocity"]])

	# ── 10i: normal slide without jump press → no launch_speed ──────────────────
	var lsm2: RefCounted = _new_lsm()
	var inp2: Dictionary = _inp_base()
	inp2["moving"] = true
	inp2["want_sprint"] = true
	inp2["stamina_ok_for_sprint"] = true
	lsm2.tick(inp2, 0.016)
	inp2["want_sprint"] = false
	inp2["stamina_ok_for_sprint"] = false
	inp2["crouch_just_pressed"] = true
	inp2["horiz_speed"] = 7.0
	var out_no_leap: Dictionary = lsm2.tick(inp2, 0.016)
	_assert(out_no_leap.get("launch_speed", 0.0) == 0.0,
		"10i: normal slide (no jump) → launch_speed==0",
		"launch_speed=%f" % out_no_leap.get("launch_speed", 0.0))

# ── Test 11: Sprint L3 — instant interrupts + crouch stealth speed ────────────
func _test_interrupts_and_stealth() -> void:
	# Profile mults used across sub-tests
	var heavy_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 0.85, "jumpMult": 0.75,
		"massMult": 1.5, "slideFriction": 0.96, "airControlPct": 0.20,
		"crouchStealthMult": 0.40, "slideSteerMaxDeg": 0, "staminaMult": 1.0,
	}
	var light_mult: Dictionary = {
		"speedMult": 1.0, "sprintSpeedMult": 1.25, "jumpMult": 1.3,
		"massMult": 0.8, "slideFriction": 0.88, "airControlPct": 0.75,
		"crouchStealthMult": 0.60, "slideSteerMaxDeg": 45, "staminaMult": 1.0,
	}

	# ── Helper: reach SPRINT state ─────────────────────────────────────────────
	var _reach_sprint := func(lsm: RefCounted) -> Dictionary:
		var inp: Dictionary = _inp_base()
		inp["moving"]              = true
		inp["want_sprint"]         = true
		inp["stamina_ok_for_sprint"] = true
		# forward_held defaults to true (not in inp → LSM uses default true)
		return lsm.tick(inp, 0.016)

	# ── 11a: Attack cancels sprint ────────────────────────────────────────────
	var lsm_11a: RefCounted = _new_lsm()
	var out_11a_sprint: Dictionary = _reach_sprint.call(lsm_11a)
	_assert(out_11a_sprint["state"] == "SPRINT", "11a_setup: reached SPRINT",
		"state=%s" % out_11a_sprint["state"])
	var inp_11a: Dictionary = _inp_base()
	inp_11a["moving"]              = true
	inp_11a["want_sprint"]         = true
	inp_11a["stamina_ok_for_sprint"] = true
	inp_11a["attacking"]           = true   # interrupt
	var out_11a: Dictionary = lsm_11a.tick(inp_11a, 0.016)
	_assert(out_11a["state"] != "SPRINT", "11a: attacking==true cancels SPRINT → not SPRINT",
		"state=%s" % out_11a["state"])
	_assert(out_11a["state"] == "RUN", "11a2: attack-cancel SPRINT → RUN (still moving)",
		"state=%s" % out_11a["state"])

	# ── 11b: ADS cancels sprint ───────────────────────────────────────────────
	var lsm_11b: RefCounted = _new_lsm()
	_reach_sprint.call(lsm_11b)
	var inp_11b: Dictionary = _inp_base()
	inp_11b["moving"]              = true
	inp_11b["want_sprint"]         = true
	inp_11b["stamina_ok_for_sprint"] = true
	inp_11b["ads_held"]            = true   # interrupt
	var out_11b: Dictionary = lsm_11b.tick(inp_11b, 0.016)
	_assert(out_11b["state"] != "SPRINT", "11b: ads_held==true cancels SPRINT → not SPRINT",
		"state=%s" % out_11b["state"])
	_assert(out_11b["state"] == "RUN", "11b2: ADS-cancel SPRINT → RUN (still moving)",
		"state=%s" % out_11b["state"])

	# ── 11c: Release-forward cancels sprint (strafing — moving still true) ───
	var lsm_11c: RefCounted = _new_lsm()
	_reach_sprint.call(lsm_11c)
	var inp_11c: Dictionary = _inp_base()
	inp_11c["moving"]              = true     # still strafing
	inp_11c["want_sprint"]         = true
	inp_11c["stamina_ok_for_sprint"] = true
	inp_11c["forward_held"]        = false    # forward released → interrupt
	var out_11c: Dictionary = lsm_11c.tick(inp_11c, 0.016)
	_assert(out_11c["state"] != "SPRINT", "11c: forward_held==false cancels SPRINT → not SPRINT",
		"state=%s" % out_11c["state"])
	_assert(out_11c["state"] == "RUN", "11c2: forward-release SPRINT → RUN (strafing)",
		"state=%s" % out_11c["state"])

	# ── Helper: enter SLIDE from SPRINT ───────────────────────────────────────
	var _enter_slide := func(lsm: RefCounted) -> Dictionary:
		var inp: Dictionary = _inp_base()
		inp["moving"]              = true
		inp["want_sprint"]         = true
		inp["stamina_ok_for_sprint"] = true
		lsm.tick(inp, 0.016)   # reach SPRINT (_was_sprinting becomes true after this tick)
		# Now trigger slide
		inp["want_sprint"]           = false
		inp["stamina_ok_for_sprint"] = false
		inp["crouch_just_pressed"]   = true
		inp["horiz_speed"]           = 7.0   # > 85% of 6.6 = 5.61
		return lsm.tick(inp, 0.016)

	# ── 11d: ADS cancels slide ────────────────────────────────────────────────
	var lsm_11d: RefCounted = _new_lsm()
	var out_11d_slide: Dictionary = _enter_slide.call(lsm_11d)
	_assert(out_11d_slide["state"] == "SLIDE", "11d_setup: entered SLIDE",
		"state=%s" % out_11d_slide["state"])
	var inp_11d: Dictionary = _inp_base()
	inp_11d["moving"]    = true
	inp_11d["ads_held"]  = true   # interrupt
	var out_11d: Dictionary = lsm_11d.tick(inp_11d, 0.016)
	_assert(out_11d["state"] != "SLIDE", "11d: ads_held cancels SLIDE → not SLIDE",
		"state=%s" % out_11d["state"])
	_assert(out_11d["sliding"] == false, "11d2: sliding==false after ADS-cancel slide",
		"sliding=%s" % str(out_11d["sliding"]))

	# ── 11e: Attack cancels slide ─────────────────────────────────────────────
	var lsm_11e: RefCounted = _new_lsm()
	var out_11e_slide: Dictionary = _enter_slide.call(lsm_11e)
	_assert(out_11e_slide["state"] == "SLIDE", "11e_setup: entered SLIDE",
		"state=%s" % out_11e_slide["state"])
	var inp_11e: Dictionary = _inp_base()
	inp_11e["moving"]    = true
	inp_11e["attacking"] = true   # interrupt
	var out_11e: Dictionary = lsm_11e.tick(inp_11e, 0.016)
	_assert(out_11e["state"] != "SLIDE", "11e: attacking cancels SLIDE → not SLIDE",
		"state=%s" % out_11e["state"])
	_assert(out_11e["sliding"] == false, "11e2: sliding==false after attack-cancel slide",
		"sliding=%s" % str(out_11e["sliding"]))

	# ── 11f: Leap still works when not interrupting (regression guard) ────────
	var lsm_11f: RefCounted = _new_lsm()
	var out_11f_slide: Dictionary = _enter_slide.call(lsm_11f)
	_assert(out_11f_slide["state"] == "SLIDE", "11f_setup: entered SLIDE for leap test",
		"state=%s" % out_11f_slide["state"])
	var inp_11f: Dictionary = _inp_base()
	inp_11f["moving"]       = true
	inp_11f["jump_pressed"] = true
	# No interrupt flags — attacking/ads_held default false; forward_held defaults true in LSM
	var out_11f: Dictionary = lsm_11f.tick(inp_11f, 0.016)
	_assert(out_11f["state"] == "JUMP", "11f: slide→jump leap fires when not interrupting → JUMP",
		"state=%s" % out_11f["state"])
	_assert(out_11f["sliding"] == false, "11f2: sliding==false after leap",
		"sliding=%s" % str(out_11f["sliding"]))
	_assert(out_11f["jump_velocity"] > 0.0, "11f3: jump_velocity>0 after leap",
		"jv=%f" % out_11f["jump_velocity"])

	# ── 11g: Crouch stealth speed by profile ──────────────────────────────────
	# HEAVY: 3.3 * 0.40 * 1.0 = 1.32; LIGHT: 3.3 * 0.60 * 1.0 = 1.98
	var lsm_heavy: RefCounted = _new_lsm({}, heavy_mult)
	var lsm_light: RefCounted = _new_lsm({}, light_mult)

	var inp_walk: Dictionary = _inp_base()
	inp_walk["moving"] = true
	inp_walk["crouch"] = true   # crouch walk

	var out_heavy_walk: Dictionary = lsm_heavy.tick(inp_walk, 0.016)
	var out_light_walk: Dictionary = lsm_light.tick(inp_walk, 0.016)

	_assert(out_heavy_walk["state"] == "WALK", "11g_h: HEAVY crouch → WALK",
		"state=%s" % out_heavy_walk["state"])
	_assert(out_light_walk["state"] == "WALK", "11g_l: LIGHT crouch → WALK",
		"state=%s" % out_light_walk["state"])

	var exp_heavy_walk: float = 3.3 * 0.40   # 1.32
	var exp_light_walk: float = 3.3 * 0.60   # 1.98
	_assert(absf(out_heavy_walk["planar_speed"] - exp_heavy_walk) < 0.01,
		"11g_h2: HEAVY walk speed≈1.32 (tol 0.01)",
		"got=%f exp=%f" % [out_heavy_walk["planar_speed"], exp_heavy_walk])
	_assert(absf(out_light_walk["planar_speed"] - exp_light_walk) < 0.01,
		"11g_l2: LIGHT walk speed≈1.98 (tol 0.01)",
		"got=%f exp=%f" % [out_light_walk["planar_speed"], exp_light_walk])
	_assert(out_light_walk["planar_speed"] > out_heavy_walk["planar_speed"],
		"11g_cmp: LIGHT walk speed > HEAVY walk speed",
		"light=%f heavy=%f" % [out_light_walk["planar_speed"], out_heavy_walk["planar_speed"]])

# ── entry point ───────────────────────────────────────────────────────────────
func _init() -> void:
	_test_basic_states()
	_test_instant_sprint()
	_test_class_multiplier()
	_test_air_control()
	_test_slide()
	_test_landing_stutter()
	_test_fov()
	_test_profile_differentiation()
	_test_momentum_slide()
	_test_slide_jump_leap()
	_test_interrupts_and_stealth()

	print("")
	if _fail_count == 0:
		print("ALL_PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _fail_count)
		quit(1)
