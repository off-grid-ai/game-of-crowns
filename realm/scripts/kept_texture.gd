extends Texture2D
## A texture the game paints itself (a tiled ground, a striped cloth) as a file holds it (kept.gd): its pixels, the
## Image it was painted on, never the renderer's copy. Saving an ImageTexture asks the renderer for its pixels back
## (texture_get_data: a GPU read and a fence wait; the beach ball and the torn sheets of kept.write). This one is
## written from the Image its maker already had, on a worker, and handed to the renderer when it is read back.
##
## `hold`: whether it keeps its pixels once drawn. A painted cloth's (256 px) stays, so a material copied from it can
## still be written; a tiled ground's (up to 2048 px a side, megabytes) is let go once written or read.

var _rid: RID  # the renderer's texture, once drawn
var _size := Vector2i.ZERO
var _alpha := false
var _pixels: Image
var _hold := false


## Drawn from `img` at once, its pixels kept (a material painted in play: realistic.gd's stripes).
func paint(img: Image) -> Texture2D:
	_hold = true
	_draw_from(img)
	return self


## Ready to be written with `img`'s pixels and never drawn here: what a ground already drawn (an ImageTexture) is kept
## as. Read back, it draws them and lets them go.
func hold(img: Image, source: Resource = null) -> void:
	_pixels = img
	_hold = false
	_size = img.get_size()
	if source:
		for m in source.get_meta_list():
			set_meta(m, source.get_meta(m))


## The pixels let go once written, unless it keeps them (kept.gd).
func written() -> void:
	if not _hold:
		_pixels = null


func _draw_from(img: Image) -> void:
	if img == null or img.is_empty():
		return
	if _rid.is_valid():
		RenderingServer.free_rid(_rid)
	_rid = RenderingServer.texture_2d_create(img)
	_size = img.get_size()
	_alpha = img.detect_alpha() != Image.ALPHA_NONE
	_pixels = img if _hold else null


func _get_property_list() -> Array:
	# "hold" before "pixels": a file sets them in this order, so reading the pixels knows whether to keep them.
	return [{"name": "hold", "type": TYPE_BOOL, "usage": PROPERTY_USAGE_STORAGE},
		{"name": "pixels", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Image",
			"usage": PROPERTY_USAGE_STORAGE}]


func _get(property: StringName) -> Variant:
	if property == &"hold":
		return _hold
	if property == &"pixels":
		return _pixels
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"hold":
		_hold = value == true
		return true
	if property == &"pixels":
		_draw_from(value as Image)
		return true
	return false


func _get_rid() -> RID:
	return _rid


func _get_width() -> int:
	return _size.x


func _get_height() -> int:
	return _size.y


func _has_alpha() -> bool:
	return _alpha


func _is_pixel_opaque(x: int, y: int) -> bool:
	return _pixels == null or _pixels.get_pixel(x, y).a > 0.5


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rid.is_valid():
		RenderingServer.free_rid(_rid)
