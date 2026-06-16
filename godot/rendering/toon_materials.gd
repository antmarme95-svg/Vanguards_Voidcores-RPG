## ToonMaterials — static factory helpers matching the JS ToonMaterials.js API.
## toon_mat / toon_mat_textured wrap the spatial toon.gdshader.
## glow_mat creates an unshaded emissive StandardMaterial3D.
## add_outline injects an inverted-hull next_pass outline (cached per color+thickness).
class_name ToonMaterials extends RefCounted

const SHADER_PATH = "res://rendering/toon.gdshader"
const _PipelineConfig = preload("res://rendering/pipeline_config.gd")

# Outline cache: key = "<hex>_<thickness>" -> StandardMaterial3D
static var _outline_cache: Dictionary = {}

# Shader resource cached after first load
static var _toon_shader: Shader = null

static func _get_shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = load(SHADER_PATH)
	return _toon_shader

## Create a flat toon material with a solid albedo color.
static func toon_mat(color: Color) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = _get_shader()
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("use_texture", false)
	_PipelineConfig.apply_to(mat)
	return mat

## Create a toon material that samples an albedo texture (head / warpaint atlas).
static func toon_mat_textured(tex: Texture2D) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = _get_shader()
	mat.set_shader_parameter("albedo_color", Color(1, 1, 1, 1))
	mat.set_shader_parameter("use_texture", true)
	mat.set_shader_parameter("albedo_texture", tex)
	_PipelineConfig.apply_to(mat)
	return mat

## Unshaded emissive glow — for aether veins, crystals, projectile trails.
## Mirrors JS glowMat(color, intensity): multiplies color by strength.
static func glow_mat(color: Color, strength: float = 1.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color * strength
	mat.albedo_color = color * strength
	mat.no_depth_test = false
	return mat

## Attach an inverted-hull outline as next_pass on the given material.
## Caches outline passes per (color.to_html() + str(thickness)) to avoid duplicates.
## Matches JS addOutline(group, { thickness }) — darkened 0.7 of the base color.
static func add_outline(mat: Material, base_color: Color, thickness: float = 0.02) -> void:
	var key = base_color.to_html() + "_" + str(thickness)
	var outline_pass: StandardMaterial3D
	if _outline_cache.has(key):
		outline_pass = _outline_cache[key]
	else:
		outline_pass = StandardMaterial3D.new()
		outline_pass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_pass.cull_mode = BaseMaterial3D.CULL_FRONT
		outline_pass.grow = true
		outline_pass.grow_amount = thickness
		outline_pass.albedo_color = base_color.darkened(_PipelineConfig.OUTLINE_DARKEN)
		_outline_cache[key] = outline_pass
	mat.next_pass = outline_pass
