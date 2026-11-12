extends SceneTree
## Guards the one wind (weather_fx.gd owns it: WeatherFx.wind, and the shader global `wind` it sets). CPU-side readers
## take WeatherFx.wind, never RenderingServer.global_shader_parameter_get (an editor-only call: outside the editor
## it logs "This function should never be used outside the editor" every time, ~200 a render in focus r12/r13, from
## hearths.gd _drift). Fails (exit 1) when:
## - hearths' chimney smoke does not lean with WeatherFx.wind (set to a wind of its own here);
## - any script under res://scripts calls global_shader_parameter_get.
## Run it and grep its log for ERROR too: none should come from _drift.
##   arch -arm64 godot --headless --path realm -s res://tools/wind_probe.gd

const WeatherFx := preload("res://scripts/weather_fx.gd")
const Hearths := preload("res://scripts/hearths.gd")

var _bad := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var was := WeatherFx.wind
	WeatherFx.wind = Vector4(0.0, 0.0, -1.0, 1.0)  # due north, a storm: unlike any fallback
	var h: Node = Hearths.new(null)  # never added: no _ready, no data read
	var smoke := GPUParticles3D.new()
	smoke.process_material = ParticleProcessMaterial.new()
	h.get("_styled").append(weakref(smoke))
	h.call("_drift")
	var g: Vector3 = (smoke.process_material as ParticleProcessMaterial).gravity
	_check(g.z < -0.01 and absf(g.x) < 0.001, "smoke leans %s, not with WeatherFx.wind (north)" % g)
	WeatherFx.wind = was
	smoke.free()
	h.free()
	_scan("res://scripts")
	print("WIND %s: %d problems" % ["PASS" if _bad == 0 else "FAIL", _bad])
	quit(1 if _bad > 0 else 0)
	return true


func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			var n := 0
			for line in src.split("\n"):
				n += 1
				if line.contains("global_shader_parameter_get") and not line.strip_edges().begins_with("#"):
					_check(false, "%s:%d reads the shader global back (editor-only)" % [f, n])
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
		print("WIND FAIL ", what)
