extends SceneTree
## Kept files written without reading the renderer back (Mac's battle run 2026-11-15: SLOW-FRAME 1350 ms, kept.write
## 1201, 'timeout waiting for fence' at kept.gd _write: ResourceSaver.save of an ArrayMesh / ImageTexture on the main
## thread read its data back from the GPU). Keeps a mesh and a ground the way play does (realistic.gd: an ImporterMesh
## merged with detail levels, UV2, a custom array and bones, handed to the renderer with get_mesh; terrain.gd tiled: an
## Image drawn as an ImageTexture) and asserts:
##  - keep() returns at once and the file is written on a worker (pending() right after; keep under 20 ms for a big mesh);
##  - what is written is the CPU form (kept_mesh.gd / kept_texture.gd), so nothing is asked of the renderer;
##  - read back, it matches: surface count, vertex and index counts, detail levels, format bits (UV2, custom, bones),
##    material, metas; the image's size, and the texture is drawn (a valid RID).
## Exits 0 when all hold, 1 otherwise.
## perl -e 'alarm shift; exec @ARGV' 120 arch -arm64 godot --headless --path realm -s res://tools/kept_write_probe.gd

const Kept := preload("res://scripts/kept.gd")
const KeptMesh := preload("res://scripts/kept_mesh.gd")
const KeptTexture := preload("res://scripts/kept_texture.gd")
const DIR := "user://kept_write_probe/"

var _bad := 0


func _initialize() -> void:
	_clear()
	var im := _plain_mesh(120, 120)
	var mesh := im.get_mesh()
	mesh.set_meta("path", "res://probe.glb")
	var mpath := DIR + "models/probe_whole.res"
	var t0 := Time.get_ticks_usec()
	Kept.keep(mesh, mpath, im)
	var spent := (Time.get_ticks_usec() - t0) / 1000.0
	_check(Kept.pending(), "the mesh is written on a worker (pending right after keep)")
	_check(spent < 20.0, "keep returns at once (%.1f ms)" % spent)

	var img := Image.create(1024, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.4, 0.3, 0.8))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("copies", Vector2(4, 1))
	var tpath := DIR + "tiled/probe.res"
	Kept.keep(tex, tpath, img)

	var cloth := Image.create(256, 256, false, Image.FORMAT_RGB8)
	cloth.fill(Color.RED)
	var painted: Texture2D = KeptTexture.new().paint(cloth)
	var cpath := DIR + "tiled/cloth.res"
	Kept.keep(painted, cpath, null)

	Kept.flush()
	_check(not Kept.pending(), "nothing left pending after flush")

	var back: Resource = ResourceLoader.load(mpath, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back is ArrayMesh and back.get_script() == KeptMesh, "the mesh's file holds the plain arrays (kept_mesh.gd)")
	if back is ArrayMesh:
		var m := back as ArrayMesh
		_check(m.get_surface_count() == im.get_surface_count(), "surface count %d == %d" % [m.get_surface_count(), im.get_surface_count()])
		for s in mini(m.get_surface_count(), im.get_surface_count()):
			var arr := im.get_surface_arrays(s)
			_check(m.surface_get_array_len(s) == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "surface %d vertex count" % s)
			_check(m.surface_get_array_index_len(s) == (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), "surface %d index count" % s)
			var fmt := m.surface_get_format(s)
			_check(fmt & Mesh.ARRAY_FORMAT_TEX_UV2 != 0, "surface %d keeps its UV2" % s)
			_check(fmt & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "surface %d keeps its custom array" % s)
			_check(fmt & Mesh.ARRAY_FORMAT_BONES != 0 and fmt & Mesh.ARRAY_FORMAT_WEIGHTS != 0, "surface %d keeps its bones" % s)
			var lods: Array = RenderingServer.mesh_get_surface(m.get_rid(), s).get("lods", [])
			_check(lods.size() == im.get_surface_lod_count(s), "surface %d detail levels %d == %d" % [s, lods.size(), im.get_surface_lod_count(s)])
			_check(m.surface_get_material(s) != null, "surface %d keeps its material" % s)
		_check(m.get_meta("path", "") == "res://probe.glb", "the mesh keeps its metas")

	var tback: Resource = ResourceLoader.load(tpath, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(tback is Texture2D and tback.get_script() == KeptTexture, "the ground's file holds its pixels (kept_texture.gd)")
	if tback is Texture2D:
		var t := tback as Texture2D
		_check(t.get_width() == 1024 and t.get_height() == 256, "the ground's size %dx%d" % [t.get_width(), t.get_height()])
		_check(t.get_rid().is_valid(), "the ground is drawn once read")
		_check(t.get_meta("copies", Vector2.ZERO) == Vector2(4, 1), "the ground keeps its metas")
	var cback: Resource = ResourceLoader.load(cpath, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(cback is Texture2D and (cback as Texture2D).get_width() == 256 and (cback as Texture2D).get_rid().is_valid(), "a painted cloth reads back drawn")

	print("KEPT-WRITE-PROBE %s (%d failed)" % ["PASS" if _bad == 0 else "FAIL", _bad])
	_clear()
	quit(1 if _bad > 0 else 0)


## A merged model the way realistic.gd makes one: two surfaces, indexed, UV2, a custom array, bones, detail levels.
func _plain_mesh(nx: int, ny: int) -> ImporterMesh:
	var im := ImporterMesh.new()
	for surface in 2:
		var verts := PackedVector3Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var custom := PackedFloat32Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var idx := PackedInt32Array()
		for y in ny:
			for x in nx:
				var h := sin(x * 0.3) * cos(y * 0.2) * 0.5
				verts.append(Vector3(x * 0.1, h + surface, y * 0.1))
				uv.append(Vector2(float(x) / nx, float(y) / ny))
				uv2.append(Vector2(float(x) / nx, 0.5))
				custom.append_array([x * 0.01, y * 0.01, 0.0, 1.0])
				bones.append_array([0, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
		for y in ny - 1:
			for x in nx - 1:
				var a := y * nx + x
				idx.append_array([a, a + nx, a + 1, a + 1, a + nx, a + nx + 1])
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_CUSTOM0] = custom
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		arr[Mesh.ARRAY_INDEX] = idx
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.5, 0.4)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat, "s%d" % surface,
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	im.generate_lods(25.0, 60.0, [])
	return im


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
	print("%s %s" % ["ok  " if ok else "FAIL", what])


func _clear() -> void:
	for d in ["models", "tiled"]:
		var dir: String = DIR + d + "/"
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir + f)
