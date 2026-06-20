# locomotion_state_machine.gd — Pure, headless locomotion FSM for Borisawa.
# PRD-003: slide / air-control / FOV-kick / landing-stutter.
#
# NO scene/node dependencies — all math is pure and deterministic.
# Consumers must preload:
#   const _LSM = preload("res://gameplay/locomotion_state_machine.gd")
#
# Usage:
#   var lsm = _LSM.new()
#   lsm.configure(Config.locomotion(), Config.class_mult(origin_id, class_id))
#   var out = lsm.tick(inp, dt)
#
# inp keys (all required, pass sensible defaults if not applicable):
#   moving:bool           — any planar WASD pressed
#   ix:float              — raw horizontal input (-1..1, camera-space)
#   iz:float              — raw vertical input (-1..1, camera-space)
#   want_sprint:bool      — SHIFT held
#   crouch:bool           — crouch state (toggled by C)
#   grounded:bool         — player is on the ground
#   vel_y:float           — current vertical velocity
#   horiz_speed:float     — current horizontal speed magnitude (for slide entry)
#   jump_pressed:bool     — KEY_SPACE just pressed this tick
#   stamina_ok_for_sprint:bool — caller already drained stamina for sprint this tick
#   crouch_just_pressed:bool  — C was just pressed this tick
#   cam_yaw_changed:bool  — camera rotated this tick (must NOT cancel slide)
#
# Output dictionary:
#   state:String          — one of the STATE_* consts
#   planar_speed:float    — horizontal speed to use (already class-scaled)
#   air_control:float     — 0.0-1.0 multiplier for horizontal movement when airborne
#   sliding:bool          — true while in SLIDE state
#   slide_speed:float     — current slide speed (only meaningful when sliding==true)
#   lock_horizontal:bool  — true during LANDING stutter (suppress horiz move)
#   fov_target:float      — camera FOV to lerp toward
#   jump_velocity:float   — >0 the frame a jump starts (caller sets vel_y, grounded=false)
#   allow_attack:bool     — true unless a future state needs to block it

class_name LocomotionStateMachine extends RefCounted

# ── State string constants ─────────────────────────────────────────────────────
const STATE_IDLE    := "IDLE"
const STATE_WALK    := "WALK"
const STATE_RUN     := "RUN"
const STATE_SPRINT  := "SPRINT"
const STATE_JUMP    := "JUMP"
const STATE_SLIDE   := "SLIDE"
const STATE_FALLING := "FALLING"
const STATE_LANDING := "LANDING"

# ── Config (injected via configure()) ─────────────────────────────────────────
var _base_speed:        float = 3.3
var _sprint_mult:       float = 2.0   # SPRINT = baseSpeed * sprintMultiplier
var _crouch_speed:      float = 1.9
var _jump_force:        float = 8.4
var _air_control:       float = 0.2
var _slide_velocity:    float = 9.0
var _slide_decay:       float = 8.0
var _slide_threshold:   float = 5.0
var _fov_base:          float = 50.0
var _fov_kick:          float = 8.0
var _landing_per_meter: float = 0.03
var _landing_max:       float = 0.35

# class multipliers — base
var _speed_mult:  float = 1.0
var _jump_mult:   float = 1.0
# class multipliers — physiometry (Sprint L0)
var _sprint_speed_mult:   float = 1.0
var _mass_mult:           float = 1.0
var _slide_friction:      float = 0.92
var _air_control_pct:     float = 0.5
var _crouch_stealth_mult: float = 0.5
var _slide_steer_max_deg: float = 22.0

# ── Derived speed tiers (recomputed on configure) ──────────────────────────────
var _speed_run:    float = 3.3
var _speed_walk:   float = 1.9
var _speed_sprint: float = 6.6

# ── Internal FSM state ─────────────────────────────────────────────────────────
var _state:          String = STATE_IDLE
var _slide_speed:    float  = 0.0
var _landing_timer:  float  = 0.0
var _fall_start_y:   float  = 0.0   # world Y when we left the ground
var _was_grounded:   bool   = true  # previous tick grounded flag
var _was_sprinting:  bool   = false # true when last-ground-state was SPRINT


# ── configure ──────────────────────────────────────────────────────────────────
# Call once when the class is known.
# loco  = Config.locomotion()
# cmult = Config.class_mult(origin_id, class_id)
func configure(loco: Dictionary, cmult: Dictionary) -> void:
	_base_speed        = float(loco.get("baseSpeed",        3.3))
	_sprint_mult       = float(loco.get("sprintMultiplier", 2.0))
	_crouch_speed      = float(loco.get("crouchSpeed",      1.9))
	_jump_force        = float(loco.get("jumpForce",        8.4))
	_air_control       = float(loco.get("airControl",       0.2))
	_slide_velocity    = float(loco.get("slideVelocity",    9.0))
	_slide_decay       = float(loco.get("slideDecay",       8.0))
	_slide_threshold   = float(loco.get("slideThreshold",   5.0))
	_fov_base          = float(loco.get("fovBase",          50.0))
	_fov_kick          = float(loco.get("fovKickDeg",       8.0))
	_landing_per_meter = float(loco.get("landingStutterPerMeter", 0.03))
	_landing_max       = float(loco.get("landingStutterMax",      0.35))

	_speed_mult = float(cmult.get("speedMult",  1.0))
	_jump_mult  = float(cmult.get("jumpMult",   1.0))
	# Sprint L0: physiometry fields (stored for L1–L3 use; sprintSpeedMult + airControlPct applied now)
	_sprint_speed_mult   = float(cmult.get("sprintSpeedMult",   1.0))
	_mass_mult           = float(cmult.get("massMult",          1.0))
	_slide_friction      = float(cmult.get("slideFriction",     0.92))
	_air_control_pct     = float(cmult.get("airControlPct",     0.5))
	_crouch_stealth_mult = float(cmult.get("crouchStealthMult", 0.5))
	_slide_steer_max_deg = float(cmult.get("slideSteerMaxDeg",  22.0))

	_speed_run    = _base_speed   * _speed_mult
	_speed_walk   = _base_speed * _crouch_stealth_mult * _speed_mult
	_speed_sprint = _base_speed * _sprint_mult * _speed_mult * _sprint_speed_mult


# ── tick ───────────────────────────────────────────────────────────────────────
func tick(inp: Dictionary, dt: float) -> Dictionary:
	var moving:              bool  = inp.get("moving",              false)
	var want_sprint:         bool  = inp.get("want_sprint",         false)
	var crouch:              bool  = inp.get("crouch",              false)
	var grounded:            bool  = inp.get("grounded",            true)
	var vel_y:               float = inp.get("vel_y",               0.0)
	var horiz_speed:         float = inp.get("horiz_speed",         0.0)
	var jump_pressed:        bool  = inp.get("jump_pressed",        false)
	var stamina_ok:          bool  = inp.get("stamina_ok_for_sprint", false)
	var crouch_just_pressed: bool  = inp.get("crouch_just_pressed", false)
	# Sprint L3: interrupt inputs — non-interrupting defaults so old callers/tests are unaffected.
	var attacking:    bool = inp.get("attacking",    false)
	var ads_held:     bool = inp.get("ads_held",     false)
	var forward_held: bool = inp.get("forward_held", true)   # default TRUE — no interrupt for existing callers
	var interrupt:    bool = attacking or ads_held or (not forward_held)
	# cam_yaw_changed is intentionally read but NEVER used to cancel slide.
	# (variable kept so the caller can always pass it without error)
	# var _cam_yaw_changed: bool = inp.get("cam_yaw_changed", false)

	var jump_velocity: float = 0.0
	var lock_horizontal: bool = false

	# ── Landing: just touched down from FALLING ────────────────────────────────
	if not _was_grounded and grounded and _state == STATE_FALLING:
		var fall_height: float = maxf(0.0, _fall_start_y - inp.get("position_y", 0.0))
		var stutter: float = clampf(fall_height * _landing_per_meter, 0.0, _landing_max)
		if stutter > 0.001:
			_state = STATE_LANDING
			_landing_timer = stutter

	# ── LANDING timer countdown ────────────────────────────────────────────────
	if _state == STATE_LANDING:
		_landing_timer -= dt
		lock_horizontal = true
		if _landing_timer > 0.0:
			# Still stunned — return immediately, do not fall through to normal states.
			_was_grounded = grounded
			return _build_output(
				STATE_LANDING, 0.0, 1.0, false, 0.0, true, _fov_base, 0.0, true
			)
		# Timer expired — transition out.
		_state = STATE_IDLE

	# ── Jump initiation ────────────────────────────────────────────────────────
	if grounded and jump_pressed and _state != STATE_SLIDE:
		jump_velocity = _jump_force * _jump_mult
		# grounded becomes false next tick (caller sets it); we jump from current
		# state, so mark as airborne immediately for this tick's state resolution.
		# We still return the speed for this frame so the player keeps momentum.

	# ── Airborne states ────────────────────────────────────────────────────────
	if not grounded:
		# Record fall start height when we just left the ground
		if _was_grounded:
			_fall_start_y = inp.get("position_y", 0.0)
		if vel_y > 0.0:
			_state = STATE_JUMP
		else:
			_state = STATE_FALLING
		_was_grounded = grounded
		return _build_output(
			_state,
			horiz_speed,       # preserve momentum in air; caller scales by air_control
			_air_control_pct,  # per-profile airborne air control (Sprint L0)
			false,             # sliding
			0.0,               # slide_speed
			false,             # lock_horizontal
			_fov_base,         # no FOV kick while airborne
			jump_velocity,
			true               # allow_attack
		)

	# ── Ground state machine ───────────────────────────────────────────────────

	# SLIDE: enter when crouch just pressed while previous state was SPRINT
	# and horizontal speed exceeds 85% of sprint max (momentum gate).
	var slide_entering: bool = false
	if crouch_just_pressed and (_state == STATE_SPRINT or _was_sprinting) and horiz_speed > _speed_sprint * 0.85 and not interrupt:
		_state = STATE_SLIDE
		_slide_speed = clampf(horiz_speed * (1.0 + _mass_mult * 0.15), 0.0, _speed_sprint * 2.0)
		slide_entering = true

	if _state == STATE_SLIDE:
		# Sprint L3: interrupt (attacking / ADS / forward released) — exit slide immediately
		# this same tick; fall through to the normal ground-state selection below.
		if interrupt:
			_state = STATE_RUN if moving else STATE_IDLE
			_slide_speed = 0.0
			# _state is now RUN/IDLE — the block below picks up the correct state.
		else:
			# Full initial momentum on the entry frame; friction only on continuation frames.
			if not slide_entering:
				_slide_speed *= pow(_slide_friction, dt * 60.0)
			# Slide→Jump leap: cancel slide and launch with 90% of current slide speed.
			if jump_pressed:
				var launch: float = _slide_speed * 0.90
				jump_velocity = _jump_force * _jump_mult
				_state = STATE_JUMP
				_fall_start_y = inp.get("position_y", 0.0)
				_slide_speed = 0.0
				_was_grounded = grounded
				_was_sprinting = false
				return _build_output(
					STATE_JUMP,
					launch,
					_air_control_pct,
					false,       # sliding
					0.0,         # slide_speed
					false,       # lock_horizontal
					_fov_base,
					jump_velocity,
					true,        # allow_attack
					launch       # launch_speed signals the leap to the controller
				)
			# Exit slide when speed drops to WALK level (or below minimum ~0.5)
			var exit_threshold: float = maxf(_speed_walk, 0.5)
			if _slide_speed <= exit_threshold:
				_state = STATE_RUN if moving else STATE_IDLE
				_slide_speed = 0.0
			else:
				_was_grounded = grounded
				_was_sprinting = false
				return _build_output(
					STATE_SLIDE,
					_slide_speed,
					1.0,   # full control of slide direction is already locked by caller
					true,  # sliding
					_slide_speed,
					false, # lock_horizontal
					_fov_base,
					0.0,   # no jump_velocity during normal slide
					true   # allow_attack during slide
				)

	# Normal ground states
	var new_state: String
	var planar_speed: float

	if not moving:
		new_state    = STATE_IDLE
		planar_speed = 0.0
	elif want_sprint and stamina_ok and not interrupt:
		# Sprint intent (Shift) wins over a held crouch toggle so the player can always
		# sprint → C-press → slide, even if crouch was previously toggled on.
		new_state    = STATE_SPRINT
		planar_speed = _speed_sprint
	elif crouch:
		new_state    = STATE_WALK
		planar_speed = _speed_walk
	else:
		new_state    = STATE_RUN
		planar_speed = _speed_run

	_state = new_state
	_was_sprinting = (new_state == STATE_SPRINT)
	_was_grounded  = grounded

	var fov_t: float = (_fov_base + _fov_kick) if new_state == STATE_SPRINT else _fov_base

	return _build_output(
		_state,
		planar_speed,
		1.0,      # full air_control on ground
		false,    # sliding
		0.0,      # slide_speed
		lock_horizontal,
		fov_t,
		jump_velocity,
		true      # allow_attack
	)


# ── Helpers ───────────────────────────────────────────────────────────────────
func _build_output(
		state: String,
		planar_speed: float,
		air_control: float,
		sliding: bool,
		slide_speed: float,
		lock_horizontal: bool,
		fov_target: float,
		jump_velocity: float,
		allow_attack: bool,
		launch_speed: float = 0.0
) -> Dictionary:
	return {
		"state":          state,
		"planar_speed":   planar_speed,
		"air_control":    air_control,
		"sliding":        sliding,
		"slide_speed":    slide_speed,
		"lock_horizontal": lock_horizontal,
		"fov_target":     fov_target,
		"jump_velocity":  jump_velocity,
		"allow_attack":   allow_attack,
		"launch_speed":   launch_speed,
	}


# ── Accessors for tests ───────────────────────────────────────────────────────
func get_speed_run()    -> float: return _speed_run
func get_speed_walk()   -> float: return _speed_walk
func get_speed_sprint() -> float: return _speed_sprint
func get_air_control()  -> float: return _air_control_pct
func get_slide_steer_max_deg() -> float: return _slide_steer_max_deg
func get_state()        -> String: return _state
