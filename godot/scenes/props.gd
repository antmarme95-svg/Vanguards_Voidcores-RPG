## props.gd — static prop builders, porting props.js helpers.
## All methods return Node3D (or subclass) ready to add_child into a scene.
## Does NOT use GPUParticles3D — motes are small sphere billboards on a Node3D.
class_name Props extends RefCounted

# ---------------------------------------------------------------------------
# room — floor + back/left/right/front walls with a 2.4-wide door gap + ceiling
# ---------------------------------------------------------------------------
static func room(p: Dictionary) -> Node3D:
	var w: float = p.get("w", 12.0)
	var h: float = p.get("h", 4.6)
	var d: float = p.get("d", 10.0)
	var floor_color: Color = p.get("floor", Color("#cfd8e6"))
	var wall_color: Color = p.get("wall", Color("#8fa6c4"))
	var trim_color: Color = p.get("trim", Color("#e8eef8"))

	var g = Node3D.new()

	# floor
	var floor_mi = _box(Vector3(w, 0.2, d), ToonMaterials.toon_mat(floor_color))
	floor_mi.position.y = -0.1
	g.add_child(floor_mi)

	var wmat = ToonMaterials.toon_mat(wall_color)
	# back wall
	g.add_child(_wall_box(Vector3(w, h, 0.25), Vector3(0.0, h * 0.5, -d * 0.5), wmat))
	# left wall
	g.add_child(_wall_box(Vector3(0.25, h, d), Vector3(-w * 0.5, h * 0.5, 0.0), wmat))
	# right wall
	g.add_child(_wall_box(Vector3(0.25, h, d), Vector3(w * 0.5, h * 0.5, 0.0), wmat))
	# front left
	g.add_child(_wall_box(Vector3(w * 0.5 - 1.2, h, 0.25), Vector3(-(w * 0.25 + 0.6), h * 0.5, d * 0.5), wmat))
	# front right
	g.add_child(_wall_box(Vector3(w * 0.5 - 1.2, h, 0.25), Vector3(w * 0.25 + 0.6, h * 0.5, d * 0.5), wmat))
	# lintel above doorway
	var lintel_h: float = h - 2.7
	var lintel_mi = _box(Vector3(2.4, lintel_h, 0.25), ToonMaterials.toon_mat(wall_color))
	lintel_mi.position = Vector3(0.0, 2.7 + lintel_h * 0.5, d * 0.5)
	g.add_child(lintel_mi)
	# ceiling
	var ceil_mi = _box(Vector3(w, 0.2, d), ToonMaterials.toon_mat(trim_color))
	ceil_mi.position.y = h + 0.1
	g.add_child(ceil_mi)
	return g

static func _wall_box(sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi = _box(sz, mat)
	mi.position = pos
	return mi

# ---------------------------------------------------------------------------
# sliding_doors — returns Node3D; per-frame tick via set_meta("tick", callable)
# ---------------------------------------------------------------------------
static func sliding_doors(color: Color, glow_color: Color) -> Node3D:
	var g = Node3D.new()
	var mat = ToonMaterials.toon_mat(color)
	for side in [-1, 1]:
		var panel = _box(Vector3(1.2, 2.7, 0.12), mat)
		panel.position = Vector3(float(side) * 0.6, 1.35, 0.0)
		panel.set_meta("door_side", side)
		var seam_mat = ToonMaterials.glow_mat(glow_color, 0.9)
		var seam = _box(Vector3(0.05, 2.5, 0.13), seam_mat)
		seam.position = Vector3(float(-side) * 0.55, 1.35, 0.0)
		# seam is local to world since parent panel is in g directly
		g.add_child(panel)
		g.add_child(seam)
		panel.set_meta("seam", seam)
	g.set_meta("open_amount", 0.0)
	return g

## Call this from _process(delta) to animate the doors.
## g = the Node3D returned by sliding_doors
## opening = true to open, false to close
static func tick_doors(g: Node3D, delta: float, opening: bool) -> void:
	var cur: float = g.get_meta("open_amount")
	var target: float = 1.0 if opening else 0.0
	cur = clamp(cur + (target - cur) * min(1.0, delta * 0.9 * 8.0), 0.0, 1.0)
	g.set_meta("open_amount", cur)
	for child in g.get_children():
		if child.has_meta("door_side"):
			var side: int = child.get_meta("door_side")
			child.position.x = float(side) * (0.6 + cur * 1.15)

# ---------------------------------------------------------------------------
# aether_pipe — tube along CatmullRom-ish points (approximated with cylinders)
# ---------------------------------------------------------------------------
static func aether_pipe(points: Array, glow_color: Color, radius: float = 0.06) -> Node3D:
	var g = Node3D.new()
	var glow_mat = ToonMaterials.glow_mat(glow_color, 0.85)
	var shell_mat = ToonMaterials.toon_mat(Color("#2b3038"))
	# draw segments between consecutive points
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg = _cylinder_segment(a, b, radius, glow_mat)
		g.add_child(seg)
	# joint spheres at each point
	for pt in points:
		var jt = MeshInstance3D.new()
		var jmesh = SphereMesh.new()
		jmesh.radius = radius * 1.9
		jmesh.height = radius * 3.8
		jt.mesh = jmesh
		jt.material_override = shell_mat
		jt.position = pt
		g.add_child(jt)
	return g

static func _cylinder_segment(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var diff = b - a
	var length = diff.length()
	var mi = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = length
	mi.mesh = mesh
	mi.material_override = mat
	var mid = (a + b) * 0.5
	mi.position = mid
	if diff.length_squared() > 0.0001:
		# Align cylinder Y-axis (its long axis) to diff direction.
		# Use basis rotation directly — avoids look_at which needs the node in-tree.
		var dir = diff.normalized()
		var up = Vector3.UP
		if abs(dir.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var basis = Basis.looking_at(dir, up)
		# CylinderMesh extends along Y; looking_at aligns -Z to target, so rotate to Y
		basis = basis.rotated(basis.x, PI * 0.5)
		mi.basis = basis
	return mi

# ---------------------------------------------------------------------------
# crystal_lamp
# ---------------------------------------------------------------------------
static func crystal_lamp(color: Color, height: float = 2.1) -> Node3D:
	var g = Node3D.new()
	var post = MeshInstance3D.new()
	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.05
	post_mesh.bottom_radius = 0.07
	post_mesh.height = height
	post.mesh = post_mesh
	post.material_override = ToonMaterials.toon_mat(Color("#3a3f4a"))
	post.position.y = height * 0.5
	g.add_child(post)

	var crystal = _box(Vector3(0.22, 0.22, 0.22), ToonMaterials.glow_mat(color, 1.1))
	crystal.position.y = height + 0.18
	g.add_child(crystal)

	var cage = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.182
	torus.outer_radius = 0.2
	cage.mesh = torus
	cage.material_override = ToonMaterials.toon_mat(Color("#3a3f4a"))
	cage.position.y = height + 0.18
	cage.rotation.x = PI * 0.5
	g.add_child(cage)
	return g

# ---------------------------------------------------------------------------
# banner — flat plane with a programmatically-drawn sigil texture
# ---------------------------------------------------------------------------
static func banner(theme: Dictionary) -> Node3D:
	var prop_set: String = theme.get("propSet", "skyland")
	var accent: Color = Color(theme.get("accent", "#46e6ff"))

	# Build a 128x192 image with a dark background + simple geometric sigil
	var img = Image.create(128, 192, false, Image.FORMAT_RGBA8)
	img.fill(Color("#181c24"))
	_draw_sigil(img, prop_set, accent)
	# Border
	_draw_rect_border(img, 8, 8, 120, 184, accent, 4)

	var tex = ImageTexture.create_from_image(img)

	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.albedo_texture = tex
	mesh_mat.albedo_color = Color(1, 1, 1, 1)

	var plane_mi = MeshInstance3D.new()
	var pmesh = PlaneMesh.new()
	pmesh.size = Vector2(0.85, 1.3)
	plane_mi.mesh = pmesh
	plane_mi.material_override = mesh_mat
	plane_mi.rotation.x = -PI * 0.5

	var rod = MeshInstance3D.new()
	var rmesh = CylinderMesh.new()
	rmesh.top_radius = 0.025
	rmesh.bottom_radius = 0.025
	rmesh.height = 1.0
	rod.mesh = rmesh
	rod.material_override = ToonMaterials.toon_mat(Color("#3a3f4a"))
	rod.rotation.z = PI * 0.5
	rod.position.y = 0.7

	var g = Node3D.new()
	g.add_child(plane_mi)
	g.add_child(rod)
	return g

static func _draw_sigil(img: Image, prop_set: String, col: Color) -> void:
	match prop_set:
		"skyland":
			# Triangle (eye-spire) + circle
			_draw_line_img(img, Vector2(64, 22), Vector2(96, 95), col, 6)
			_draw_line_img(img, Vector2(96, 95), Vector2(32, 95), col, 6)
			_draw_line_img(img, Vector2(32, 95), Vector2(64, 22), col, 6)
			_draw_circle_img(img, Vector2(64, 70), 14, col, 4)
		"forge":
			# Gear circle + hammer
			_draw_circle_img(img, Vector2(64, 70), 26, col, 5)
			_fill_rect_img(img, Rect2(56, 20, 16, 56), col)
			_fill_rect_img(img, Rect2(40, 20, 48, 14), col)
		_:  # docks: two curved lines (approximated with line segments)
			_draw_line_img(img, Vector2(45, 25), Vector2(70, 60), col, 5)
			_draw_line_img(img, Vector2(70, 60), Vector2(50, 100), col, 5)
			_draw_line_img(img, Vector2(80, 25), Vector2(60, 60), col, 5)
			_draw_line_img(img, Vector2(60, 60), Vector2(84, 100), col, 5)

static func _draw_line_img(img: Image, from: Vector2, to: Vector2, col: Color, thickness: int) -> void:
	var steps = int(from.distance_to(to)) * 2 + 1
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var pt = from.lerp(to, t)
		_fill_circle_img(img, pt, thickness / 2, col)

static func _draw_circle_img(img: Image, center: Vector2, radius: float, col: Color, thickness: int) -> void:
	var steps = int(radius * PI * 2.0) + 16
	for i in range(steps):
		var angle = float(i) / float(steps) * TAU
		var pt = center + Vector2(cos(angle), sin(angle)) * radius
		_fill_circle_img(img, pt, thickness / 2, col)

static func _fill_circle_img(img: Image, center: Vector2, radius: int, col: Color) -> void:
	var ix = int(center.x)
	var iy = int(center.y)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var px = ix + dx
				var py = iy + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, col)

static func _fill_rect_img(img: Image, rect: Rect2, col: Color) -> void:
	for y in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
		for x in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				img.set_pixel(x, y, col)

static func _draw_rect_border(img: Image, x1: int, y1: int, x2: int, y2: int, col: Color, thickness: int) -> void:
	for t in range(thickness):
		for x in range(x1 + t, x2 - t):
			if y1 + t >= 0 and y1 + t < img.get_height():
				img.set_pixel(x, y1 + t, col)
			if y2 - t - 1 >= 0 and y2 - t - 1 < img.get_height():
				img.set_pixel(x, y2 - t - 1, col)
		for y in range(y1 + t, y2 - t):
			if x1 + t >= 0 and x1 + t < img.get_width():
				img.set_pixel(x1 + t, y, col)
			if x2 - t - 1 >= 0 and x2 - t - 1 < img.get_width():
				img.set_pixel(x2 - t - 1, y, col)

# ---------------------------------------------------------------------------
# spin_gear
# ---------------------------------------------------------------------------
static func spin_gear(radius: float, color: Color) -> Node3D:
	var g = Node3D.new()
	var mat = ToonMaterials.toon_mat(color)

	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = radius * 0.82
	torus.outer_radius = radius
	ring.mesh = torus
	ring.material_override = mat
	g.add_child(ring)

	for i in range(8):
		var a = float(i) / 8.0 * TAU
		var tooth = _box(
			Vector3(radius * 0.22, radius * 0.3, radius * 0.18),
			mat
		)
		tooth.position = Vector3(cos(a) * radius * 1.18, sin(a) * radius * 1.18, 0.0)
		tooth.rotation.z = a
		g.add_child(tooth)
		if i < 3:
			var spoke = _box(Vector3(radius * 0.08, radius * 1.9, radius * 0.08), mat)
			spoke.rotation.z = a
			g.add_child(spoke)
	g.set_meta("spin", 0.4)
	return g

# ---------------------------------------------------------------------------
# floating_crystal
# ---------------------------------------------------------------------------
static func floating_crystal(color: Color, size: float = 0.22) -> Node3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(size, size * 1.6, size)
	mi.mesh = mesh
	mi.material_override = ToonMaterials.glow_mat(color, 1.0)
	var g = Node3D.new()
	g.add_child(mi)
	g.set_meta("bob_seed", randf() * TAU)
	return g

# ---------------------------------------------------------------------------
# crate_stack
# ---------------------------------------------------------------------------
static func crate_stack(accent: Color) -> Node3D:
	var g = Node3D.new()
	var mat = ToonMaterials.toon_mat(Color("#6e5a40"))
	var defs = [
		[0.62, Vector3(0.0, 0.0, 0.0), 0.1],
		[0.62, Vector3(0.7, 0.0, 0.1), -0.2],
		[0.5, Vector3(0.3, 0.62, 0.05), 0.35],
	]
	for d in defs:
		var s: float = d[0]
		var pos: Vector3 = d[1]
		var ry: float = d[2]
		var c = _box(Vector3(s, s, s), mat)
		c.position = pos + Vector3(0.0, s * 0.5, 0.0)
		c.rotation.y = ry
		g.add_child(c)
	var rope = MeshInstance3D.new()
	var tmesh = TorusMesh.new()
	tmesh.inner_radius = 0.24
	tmesh.outer_radius = 0.3
	rope.mesh = tmesh
	rope.material_override = ToonMaterials.toon_mat(Color("#8a7a55"))
	rope.rotation.x = PI * 0.5
	rope.position = Vector3(-0.7, 0.07, 0.4)
	g.add_child(rope)
	return g

# ---------------------------------------------------------------------------
# book_stack
# ---------------------------------------------------------------------------
static func book_stack() -> Node3D:
	var g = Node3D.new()
	var colors = [Color("#7a3b3b"), Color("#3b5a7a"), Color("#4a6e3b"), Color("#6e5a8a")]
	var y = 0.0
	for i in range(4):
		var h = 0.05 + 0.03 * (float(i) * 0.37 + 0.2)  # deterministic substitute for Math.random
		var b = _box(Vector3(0.3 - float(i) * 0.03, h, 0.22), ToonMaterials.toon_mat(colors[i % colors.size()]))
		b.position = Vector3((float(i) - 2.0) * 0.012, y + h * 0.5, 0.0)
		b.rotation.y = (float(i) - 2.0) * 0.2
		g.add_child(b)
		y += h
	return g

# ---------------------------------------------------------------------------
# rib_arc — TRUE half-torus arch spanning ceiling-to-floor.
# Mirrors JS: TorusGeometry(r, r*0.07, 7, 22, Math.PI)
# Sweeps 22 ring-segments over PI radians; 7 tube-sides.
# The resulting arch stands in the XY plane (Y = up, X = left-right).
# ---------------------------------------------------------------------------
static func rib_arc(radius: float, color: Color) -> MeshInstance3D:
	var tube_r = radius * 0.07        # tube radius (matches JS r*0.07)
	var ring_segs  = 22               # segments around the arc
	var tube_sides = 7                # sides of the tube cross-section

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build vertex grid: (ring_segs+1) rings × tube_sides points
	# Arc sweeps from -PI/2 (left ground) to +PI/2 (right ground) around Y axis,
	# centred at origin, rising along Y.
	# i = ring index (0..ring_segs), j = tube index (0..tube_sides-1)
	for i in range(ring_segs + 1):
		var arc_t = float(i) / float(ring_segs)   # 0..1
		var arc_angle = arc_t * PI                # 0..PI  (left → top → right)
		# Centre of this ring on the arc (in XY plane, arc in front)
		var cx = -sin(arc_angle) * radius         # left(-r) → 0 → right(+r)
		var cy = cos(arc_angle) * radius + radius  # 0 → +r → 0  (arch peak = 2*r up)
		# Actually use the standard torus parameterisation:
		# arc sweeps in XY; tube rotates around the arc tangent.
		# Torus centre ring: point = (cx, cy, 0)
		# Tube tangent direction (along arc): d_arc/d_angle = (-cos, -sin, 0)... wait
		# Simpler: sweep arc_angle ∈ [0, PI], point on arc ring:
		#   P = (sin(arc_angle)*radius, cos(arc_angle)*radius, 0)
		# that gives Y from +radius (top when arc=0) down to -radius (arc=PI).
		# We want arch from ground left (-radius, 0, 0) rising to top (0, radius, 0) to ground right (radius, 0, 0).
		# Use: P = (-cos(arc_angle)*radius, sin(arc_angle)*radius, 0)
		#   arc=0 → (-r, 0, 0)  left ground
		#   arc=PI/2 → (0, r, 0)  apex
		#   arc=PI  → (+r, 0, 0)  right ground
		var px = -cos(arc_angle) * radius
		var py = sin(arc_angle) * radius

		# Tube tangent (normalised d/d_angle):
		var tx = sin(arc_angle)    # d(-cos)/d_a = sin
		var ty = cos(arc_angle)    # d(sin)/d_a  = cos
		# Normal to arc in XY plane (inward = toward centre of torus): (-px, -py) normalised
		var nx_arc = -cos(arc_angle)  # inward radial = toward origin = (-px/r, -py/r)
		var ny_arc = -sin(arc_angle)
		# Tube sweeps in the plane perpendicular to tangent (t).
		# Basis vectors perp to (tx, ty, 0): radial2D = (nx_arc, ny_arc, 0), out-of-plane = (0,0,1)
		for j in range(tube_sides):
			var tube_angle = float(j) / float(tube_sides) * TAU
			# Tube point displacement: tube_r * (cos(tube_angle)*radial + sin(tube_angle)*z_axis)
			var dx = cos(tube_angle) * nx_arc * tube_r
			var dy = cos(tube_angle) * ny_arc * tube_r
			var dz = sin(tube_angle) * tube_r
			var vx = px + dx
			var vy = py + dy
			var vz = dz
			# Normal points outward from tube centre
			var norm = Vector3(dx, dy, dz).normalized()
			if norm.length_squared() < 0.0001:
				norm = Vector3(nx_arc, ny_arc, 0.0).normalized()
			st.set_normal(norm)
			st.set_uv(Vector2(arc_t, float(j) / float(tube_sides)))
			st.add_vertex(Vector3(vx, vy, vz))

	# Build quad indices
	for i in range(ring_segs):
		for j in range(tube_sides):
			var j_next = (j + 1) % tube_sides
			var a = i       * tube_sides + j
			var b = i       * tube_sides + j_next
			var c = (i + 1) * tube_sides + j
			var d = (i + 1) * tube_sides + j_next
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)

	var mesh = st.commit()
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = ToonMaterials.toon_mat(color)
	return mi

# ---------------------------------------------------------------------------
# tree
# ---------------------------------------------------------------------------
static func tree(scale_val: float = 1.0) -> Node3D:
	var g = Node3D.new()
	var trunk = MeshInstance3D.new()
	var tmesh = CylinderMesh.new()
	tmesh.top_radius = 0.18 * scale_val
	tmesh.bottom_radius = 0.28 * scale_val
	tmesh.height = 2.4 * scale_val
	trunk.mesh = tmesh
	trunk.material_override = ToonMaterials.toon_mat(Color("#5a4030"))
	trunk.position.y = 1.2 * scale_val
	g.add_child(trunk)

	var greens = [Color("#3f9e4f"), Color("#2e8a4a"), Color("#55b04e")]
	for i in range(3):
		var blob = MeshInstance3D.new()
		var bmesh = SphereMesh.new()
		var r = (1.0 - float(i) * 0.22) * scale_val
		bmesh.radius = r
		bmesh.height = r * 2.0
		blob.mesh = bmesh
		blob.material_override = ToonMaterials.toon_mat(greens[i % greens.size()])
		# Deterministic offsets to avoid random in static context
		var ox = (float(i) * 0.17 - 0.08) * scale_val
		var oz = (float(i) * -0.13 + 0.05) * scale_val
		blob.position = Vector3(ox, (2.4 + float(i) * 0.75) * scale_val, oz)
		g.add_child(blob)
	return g

# ---------------------------------------------------------------------------
# rock
# ---------------------------------------------------------------------------
static func rock(scale_val: float = 1.0) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.5 * scale_val
	mesh.height = 1.0 * scale_val
	mi.mesh = mesh
	mi.material_override = ToonMaterials.toon_mat(Color("#8d9499"))
	# Deterministic squash
	mi.scale = Vector3(1.0, 0.7 + (scale_val * 0.13) - 0.03, 1.0)
	return mi

# ---------------------------------------------------------------------------
# sky_dome — large inverted sphere with vertex-color gradient (top/horizon)
# ---------------------------------------------------------------------------
static func sky_dome(top_color: Color, horizon_color: Color, radius: float = 400.0) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build sphere manually for vertex colors
	var lat_segs = 16
	var lon_segs = 24
	for lat in range(lat_segs + 1):
		var theta = float(lat) / float(lat_segs) * PI
		var sin_t = sin(theta)
		var cos_t = cos(theta)
		for lon in range(lon_segs + 1):
			var phi = float(lon) / float(lon_segs) * TAU
			var x = sin_t * cos(phi)
			var y = cos_t
			var z = sin_t * sin(phi)
			var t_val = clamp((y + 1.0) * 0.5, 0.0, 1.0)
			var t_curved = pow(t_val, 0.65)
			var col = horizon_color.lerp(top_color, t_curved)
			st.set_color(col)
			st.set_uv(Vector2(float(lon) / float(lon_segs), float(lat) / float(lat_segs)))
			st.set_normal(Vector3(-x, -y, -z))
			st.add_vertex(Vector3(x, y, z) * radius)

	# Indices (flipped winding for back-face = inside view)
	for lat in range(lat_segs):
		for lon in range(lon_segs):
			var i00 = lat * (lon_segs + 1) + lon
			var i10 = i00 + 1
			var i01 = i00 + (lon_segs + 1)
			var i11 = i01 + 1
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i10)
			st.add_index(i00)
			st.add_index(i01)
			st.add_index(i11)

	var mesh = st.commit()

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	# Note: fog_enabled does not exist in Godot 4 StandardMaterial3D — removed

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi

# ---------------------------------------------------------------------------
# motes — deterministic small spheres on a rotating Node3D (no GPUParticles3D)
# ---------------------------------------------------------------------------
static func motes(count: int, color: Color, spread: float, size: float = 0.05, y_spread: float = -1.0) -> Node3D:
	var g = Node3D.new()
	var mat = ToonMaterials.glow_mat(color, 1.0)
	# Deterministic placement using a simple LCG-ish pattern
	var ys = y_spread if y_spread >= 0.0 else spread * 0.5
	var seed_val = 12345
	for i in range(count):
		seed_val = (seed_val * 1664525 + 1013904223) & 0x7FFFFFFF
		var fx = (float((seed_val >> 8) & 0xFFFF) / 65535.0 - 0.5) * spread
		seed_val = (seed_val * 1664525 + 1013904223) & 0x7FFFFFFF
		var fy = (float((seed_val >> 8) & 0xFFFF) / 65535.0) * ys
		seed_val = (seed_val * 1664525 + 1013904223) & 0x7FFFFFFF
		var fz = (float((seed_val >> 8) & 0xFFFF) / 65535.0 - 0.5) * spread

		var mi = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = size
		mesh.height = size * 2.0
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(fx, fy, fz)
		g.add_child(mi)
	return g

# ---------------------------------------------------------------------------
# Internal helper — MeshInstance3D box
# ---------------------------------------------------------------------------
static func _box(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	return mi
