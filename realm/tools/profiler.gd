extends SceneTree
## Godot's own profiler, from the shell: the editor's Profiler tab (every function's time, the engine's servers, the
## frame) without the editor. The game is run with --remote-debug tcp://127.0.0.1:<port>; this listens there as the
## editor would, turns on the scripts and servers profilers, answers every break with "continue" so nothing stalls,
## and writes the raw messages (var_to_str, one a line) for tools/profile_report.gd... or, with --dump, the first of
## each kind so their shape can be read. Mac 2026-11-19: "you need to profile it properly".
##   godot --headless --path realm -s res://tools/profiler.gd -- --port=6007 --seconds=60 --out=/path/prof.txt
##   godot --path realm --remote-debug tcp://127.0.0.1:6007 -- <the game's args>

var port := 6007
var seconds := 60.0
var out_path := "user://profile.txt"
var start_file := ""  # --start-file=: begin when this file appears (the realm in play), not after --skip
var skip := 20.0  # seconds after connecting before the profilers start: the load is its own measure
var server := TCPServer.new()
var peer: StreamPeerTCP
var out: FileAccess
var _buf := PackedByteArray()
var _t0 := 0
var _on := false
var _counts := {}
var _tid := 0  # the game's main thread (its own messages carry it): Godot hands a command only to the thread named in it


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--start-file="):
			start_file = a.substr(13)
		elif a.begins_with("--skip="):
			skip = float(a.substr(7))
	if server.listen(port, "127.0.0.1") != OK:
		printerr("profiler: can't listen on %d" % port)
		quit(1)
		return
	out = FileAccess.open(out_path, FileAccess.WRITE)
	print("profiler: listening on %d" % port)


func _process(_delta: float) -> bool:
	if peer == null:
		if server.is_connection_available():
			peer = server.take_connection()
			peer.set_no_delay(true)
			_t0 = Time.get_ticks_msec()
			print("profiler: game connected")
		return false
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		print("profiler: game left")
		return _finish()
	var n := peer.get_available_bytes()
	if n > 0:
		var got: Array = peer.get_partial_data(n)
		_buf.append_array(got[1])
	while _buf.size() >= 4:
		var size := _buf.decode_u32(0)
		if _buf.size() < 4 + size:
			break
		var msg: Variant = bytes_to_var(_buf.slice(4, 4 + size))
		_buf = _buf.slice(4 + size)
		_take(msg)
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	if not _on and _tid != 0 and (FileAccess.file_exists(start_file) if start_file != "" else t >= skip):
		skip = t
		_on = true
		_profilers(true)
		print("profiler: profiling for %d s" % int(seconds))
	if _on and t >= skip + seconds:
		_profilers(false)
		return _finish()
	return false


func _take(msg: Variant) -> void:
	if not msg is Array or (msg as Array).size() < 3:
		return
	var name := String(msg[0])
	if _tid == 0 and name == "performance:profile_frame":
		_tid = int(msg[1])  # sent from the main loop
	_counts[name] = int(_counts.get(name, 0)) + 1
	if name == "debug_enter":
		_send("continue", [])  # a script error breaks into the debugger: the editor's Continue, so the game runs on
	if _on or name.begins_with("servers:function_signature") or name == "debug_enter" or name == "error":
		out.store_line("%.3f\t%s\t%s" % [(Time.get_ticks_msec() - _t0) / 1000.0, name, var_to_str(msg[2]).replace("\n", " ")])


func _profilers(on: bool) -> void:
	# The editor's Profiler: "servers" carries the frame, the servers and every script function (512 a frame). Native
	# calls stay off: timing every engine call from script slowed the frame and, once, the game fell over with them on.
	_send("profiler:servers", [on, [512, false]])


func _send(name: String, data: Array) -> void:
	var bytes := var_to_bytes([name, _tid, data])
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, bytes.size())
	peer.put_data(head + bytes)


func _finish() -> bool:
	out.close()
	print("profiler: messages %s" % str(_counts))
	quit(0)
	return true
