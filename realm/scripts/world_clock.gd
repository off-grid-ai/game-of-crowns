extends Node
## The realm's one clock (Mac 2026-11-16: pause freezes the world completely). It counts only while the realm runs:
## the tree's pause (main.gd _hold_world) stops it, as it stops every world node, and it runs at the game's speed
## (Engine.time_scale, already in delta). Every world timer reads it (WorldClock.seconds / msec) instead of the real
## clock, so nothing jumps on unpause; and every world shader reads it as the global `world_time` (project.godot
## shader_globals) instead of TIME, so soldiers, water, flames, banners and plants hold still too. Interface shaders
## keep TIME. Ticked by the one autoload (project.godot autoload Clock); no other script advances world time.

const PARAM := &"world_time"
static var _t := 0.0
static var _rollover: float = ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0)


## The realm's seconds since the game began, stopped while paused.
static func seconds() -> float:
	return _t


## The same in whole milliseconds, for timers written against Time.get_ticks_msec.
static func msec() -> int:
	return int(_t * 1000.0)


## What the shaders see as world_time: the realm's seconds, rolled over as TIME is (float precision).
static func shader_time() -> float:
	return fmod(_t, _rollover)


## A timer on the realm's clock: it stops while the realm is paused (Godot's own, process_always off).
static func timer(seconds_: float) -> SceneTreeTimer:
	return (Engine.get_main_loop() as SceneTree).create_timer(seconds_, false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = -1000  # before every world node reads it this frame
	RenderingServer.global_shader_parameter_set(PARAM, shader_time())


func _process(delta: float) -> void:
	_t += delta
	RenderingServer.global_shader_parameter_set(PARAM, shader_time())
