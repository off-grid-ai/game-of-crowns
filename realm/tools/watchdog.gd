## A headless probe's watchdog (supervisor, 2026-11-12: a probe whose run died on a script error before its quit()
## idled forever and held every thread). arm() at the top of a probe's _init: if it hasn't quit by `secs`, it says so
## and quits with 2, so a broken probe ends as a FAIL instead of a hang.
static func arm(tree: SceneTree, secs := 150.0) -> void:
	tree.create_timer(secs).timeout.connect(func() -> void:
		print("PROBE TIMEOUT: no verdict after %d s (a script error before its quit?): FAIL" % int(secs))
		tree.quit(2))
