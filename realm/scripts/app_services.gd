extends Node
## In the packaged app (Game of Crowns.app) the game brings its own realm:
## it starts the bundled bridge (Contents/Resources/bridge/app.js on the bundled
## Node), which runs Freeciv and the local model, and stops it when the game
## quits. Run from the editor or the repo, it does nothing: the bridge is
## started by hand there. If a bridge is already listening, that one is used.

const PORT := 8787

var _pid := -1


func _ready() -> void:
	if not OS.has_feature("template") or OS.get_name() != "macOS":
		return
	var res := OS.get_executable_path().get_base_dir().path_join("../Resources").simplify_path()
	var app := res.path_join("bridge/app.js")
	var node := res.path_join("runtime/node/bin/node")
	if not FileAccess.file_exists(app) or not FileAccess.file_exists(node) or _listening():
		return
	var home := OS.get_environment("HOME").path_join("Library/Application Support/Game of Crowns")
	DirAccess.make_dir_recursive_absolute(home.path_join("logs"))
	OS.set_environment("GOC_HOME", home)
	OS.set_environment("GOC_PARENT_PID", str(OS.get_process_id()))
	var log := home.path_join("logs/bridge.log")
	_pid = OS.create_process("/bin/sh", ["-c", "exec \"$0\" \"$1\" >>\"$2\" 2>&1", node, app, log])


func _listening() -> bool:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", PORT) != OK:
		return false
	for i in 30:
		tcp.poll()
		var s := tcp.get_status()
		if s == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			return true
		if s == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(10)
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop()


func _exit_tree() -> void:
	_stop()


## A polite stop, so Freeciv is put away properly (OS.kill would be SIGKILL).
## Should the game die instead, the bridge notices its parent is gone and stops.
func _stop() -> void:
	if _pid > 0:
		OS.execute("/bin/kill", ["-TERM", str(_pid)])
		_pid = -1
