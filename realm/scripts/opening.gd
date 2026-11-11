extends RefCounted
## The first ten minutes (docs/review/first-ten-minutes-plan.md): which opening plays. One rule,
## read by every part of it (the title, the splash, the storybook's end, the Hand's prompts, the
## ruling seen on the map). v2 is the default since the judge's ruling on gate r6 (card at 0:50 and
## the first ruling at 0:56 from Begin); --opening=v1 brings back the old opening.

static func v2() -> bool:
	return not OS.get_cmdline_user_args().has("--opening=v1")
