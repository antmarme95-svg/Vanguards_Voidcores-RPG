## PipelineConfig — single source of truth for GLOBAL cel-shading pipeline parameters.
## These are pipeline-level constants (not per-character) per PRD-001 §3.
## NOT an autoload — instantiate or call static methods directly.
class_name PipelineConfig extends RefCounted

# Global GradientTexture1D ramp resource path (PRD-001 §4 production approach).
# CONSTANT interpolation → hard 4-band stepped diffuse; shared across ALL toon materials.
const RAMP_PATH: String = "res://rendering/toon_ramp.tres"

# Ambient lift — baked into EMISSION so surfaces are lit even with no direct light.
const AMBIENT_LIFT: float = 0.14

# Fresnel rim — color and strength for the BotW-style rim highlight.
const RIM_COLOR: Color = Color(0.749, 0.910, 1.0)
const RIM_STRENGTH: float = 0.18

# Inverted-hull outline defaults.
const OUTLINE_THICKNESS: float = 0.02
const OUTLINE_DARKEN: float = 0.7

# Cached ramp texture — loaded once, shared by all apply_to() calls.
static var _ramp_tex: GradientTexture1D = null

static func _get_ramp() -> GradientTexture1D:
	if _ramp_tex == null:
		_ramp_tex = load(RAMP_PATH) as GradientTexture1D
	return _ramp_tex

## Apply all toon pipeline parameters to a ShaderMaterial that uses toon.gdshader.
## Sets the global ramp texture + ambient/rim so every toon material shares one resource.
static func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("toon_ramp", _get_ramp())
	mat.set_shader_parameter("ambient_lift", AMBIENT_LIFT)
	mat.set_shader_parameter("rim_color", RIM_COLOR)
	mat.set_shader_parameter("rim_strength", RIM_STRENGTH)
