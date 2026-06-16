## day_night.gd — Fake day/night cycle skeleton.
## Baked-lightmap-friendly: drives only ambient/sky/sun interpolation.
## NO SDFGI, NO real-time GI.
##
## USAGE:
##   Set cycle_speed = 0.0  → paused at time_of_day (default 0.5 = NOON = current baseline).
##   Set cycle_speed > 0.0  → advances time_of_day each frame and interpolates keyframes.
##   time_of_day wraps 0..1 (0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk).
class_name DayNightCycle extends Node

# ---- tunables (exported so the Inspector can drive them) ----
@export var time_of_day: float = 0.5   # 0..1; 0.5 == NOON == current baseline
@export var cycle_speed: float = 0.0   # day fraction per second; 0.0 == paused

# ---- scene references (set by TheWilds before add_child) ----
var env: Environment = null
var sun: DirectionalLight3D = null
var hemi_fill: DirectionalLight3D = null

# ================================================================
# KEYFRAMES
# Each entry: { t, ambient_col, ambient_energy, bg_col, fog_col,
#               sun_col, sun_energy, sun_pitch, sun_yaw,
#               hemi_col, hemi_energy }
#
# t is the normalized time position (0..1).
# Keyframes must be sorted by t ascending and must cover the full 0..1
# loop (the list wraps: after the last key, the next is [0] again).
#
# NOON (t=0.5) values match the_wilds.gd _build_environment()/_build_lights() EXACTLY.
# ================================================================
const _KF: Array = [
	# MIDNIGHT (t = 0.0)
	{
		"t": 0.0,
		"ambient_col":    Color(0.06, 0.07, 0.12, 1.0),  # deep blue-black
		"ambient_energy": 0.05,
		"bg_col":         Color(0.04, 0.05, 0.10, 1.0),  # near-black sky
		"fog_col":        Color(0.04, 0.05, 0.10, 1.0),
		"sun_col":        Color(0.20, 0.22, 0.40, 1.0),  # cool blue moonlight
		"sun_energy":     0.08,
		"sun_pitch":     -10.0,                           # nearly flat / below horizon
		"sun_yaw":       127.0,                           # opposite side from noon
		"hemi_col":       Color(0.15, 0.18, 0.30, 1.0),
		"hemi_energy":    0.04,
	},
	# DAWN (t = 0.25)
	{
		"t": 0.25,
		"ambient_col":    Color(0.65, 0.52, 0.58, 1.0),  # soft rose
		"ambient_energy": 0.18,
		"bg_col":         Color(0.85, 0.60, 0.50, 1.0),  # warm horizon orange
		"fog_col":        Color(0.85, 0.60, 0.50, 1.0),
		"sun_col":        Color(1.00, 0.72, 0.40, 1.0),  # deep orange sunrise
		"sun_energy":     0.55,
		"sun_pitch":     -18.0,                           # low on the horizon
		"sun_yaw":        20.0,
		"hemi_col":       Color(0.72, 0.68, 0.90, 1.0),
		"hemi_energy":    0.10,
	},
	# NOON (t = 0.5)  ← MUST MATCH BASELINE EXACTLY
	{
		"t": 0.5,
		"ambient_col":    Color("#a8d8c0"),               # #a8d8c0
		"ambient_energy": 0.30,
		"bg_col":         Color("#bfe3d4"),               # #bfe3d4
		"fog_col":        Color("#bfe3d4"),               # #bfe3d4
		"sun_col":        Color("#fff2d8"),               # #fff2d8
		"sun_energy":     1.1,
		"sun_pitch":     -66.0,
		"sun_yaw":       -53.0,
		"hemi_col":       Color("#bfe8ff"),               # #bfe8ff
		"hemi_energy":    0.18,
	},
	# DUSK (t = 0.75)
	{
		"t": 0.75,
		"ambient_col":    Color(0.62, 0.45, 0.38, 1.0),  # warm amber
		"ambient_energy": 0.15,
		"bg_col":         Color(0.78, 0.45, 0.32, 1.0),  # rich sunset orange
		"fog_col":        Color(0.78, 0.45, 0.32, 1.0),
		"sun_col":        Color(1.00, 0.60, 0.28, 1.0),  # deep sunset orange
		"sun_energy":     0.45,
		"sun_pitch":     -12.0,
		"sun_yaw":       -230.0,
		"hemi_col":       Color(0.80, 0.60, 0.70, 1.0),
		"hemi_energy":    0.08,
	},
]

# ================================================================
func _ready() -> void:
	# Apply once so the scene always boots at the correct keyframe.
	# Because time_of_day defaults to 0.5 (NOON) and NOON == current baseline,
	# this is visually a no-op — rendered output is identical to before.
	apply(time_of_day)

func _process(delta: float) -> void:
	if cycle_speed > 0.0:
		time_of_day = fmod(time_of_day + cycle_speed * delta, 1.0)
		apply(time_of_day)
	# cycle_speed == 0 → do nothing; apply() was already called in _ready()

# ================================================================
# apply() — lerp between the two bracketing keyframes and write to refs.
# ================================================================
func apply(t: float) -> void:
	if env == null or sun == null or hemi_fill == null:
		return

	# Find the two keyframes that bracket t.
	# KF list is sorted ascending. We wrap: after the last, next = first.
	var n = _KF.size()
	var a_idx = n - 1   # "before" keyframe index
	var b_idx = 0       # "after"  keyframe index

	for i in range(n):
		if _KF[i]["t"] <= t:
			a_idx = i
		else:
			b_idx = i
			break

	# If t is beyond the last keyframe, wrap: b = first keyframe (with t+1.0 concept)
	if _KF[a_idx]["t"] > t:
		# t is before the first keyframe — wrap: a = last, b = first
		a_idx = n - 1
		b_idx = 0

	var a = _KF[a_idx]
	var b = _KF[b_idx]

	# Compute local blend factor f in [0..1]
	var f: float
	if a_idx == b_idx:
		f = 0.0
	else:
		var at: float = a["t"]
		var bt: float = b["t"]
		if bt > at:
			f = (t - at) / (bt - at)
		else:
			# Wrapping: b is "first KF" which is at bt+1.0 relative to a
			var span: float = (1.0 - at) + bt
			f = (t - at) / span if span > 0.0 else 0.0

	f = clampf(f, 0.0, 1.0)

	# Write environment
	env.ambient_light_color  = (a["ambient_col"] as Color).lerp(b["ambient_col"],  f)
	env.ambient_light_energy = lerpf(a["ambient_energy"], b["ambient_energy"], f)
	env.background_color     = (a["bg_col"]  as Color).lerp(b["bg_col"],  f)
	env.fog_light_color      = (a["fog_col"] as Color).lerp(b["fog_col"], f)

	# Write sun
	sun.light_color  = (a["sun_col"] as Color).lerp(b["sun_col"], f)
	sun.light_energy = lerpf(a["sun_energy"], b["sun_energy"], f)
	sun.rotation_degrees = Vector3(
		lerpf(a["sun_pitch"], b["sun_pitch"], f),
		lerpf(a["sun_yaw"],   b["sun_yaw"],   f),
		0.0
	)

	# Write hemi fill
	hemi_fill.light_color  = (a["hemi_col"] as Color).lerp(b["hemi_col"], f)
	hemi_fill.light_energy = lerpf(a["hemi_energy"], b["hemi_energy"], f)
