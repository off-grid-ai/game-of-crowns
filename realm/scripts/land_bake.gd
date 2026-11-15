extends RefCounted
## The ground's land mask (ground.gd: a cell dry, or walkable, only where its four corners are) made once from the
## realm's own images, off the main thread, and kept (FPS audit 2026-11-15 item 3, docs/research/fps-engine-swaps-2026-11-15.md:
## ground.land read block by block on the main thread, every corner an is_land call, 1-3.5 ms a frame while a host
## walked new ground). The terrain's heightmap (terrain.gd land), its river mask and its Lake tiles are copied on the
## main thread (a worker never touches the terrain node: freed at quit, written while towns level their squares); the
## workers lay the corners with is_land's own rule (a Lake tile, the height bilinear above the sea's dry line, the river
## mask under the water's reading), a row of blocks each; the mask is kept under kept/land/ by a hash of every input,
## and read back in one read on the next start. No fords here: they come after (terrain.ground_changed, read again by
## ground.gd on the main thread). tools/occupancy_probe.gd guards it against terrain.gd's is_land.
##   begin(terrain, lw, lh, lb, lc) -> false without a heightmap;  poll() -> true once cells/blocks hold it.

const Kept := preload("res://scripts/kept.gd")
const DRY := 1  # ground.gd DRY
const WALK := 2  # ground.gd WALK

var cells := PackedByteArray()  # the mask (ground.gd _land), once poll() says so
var blocks := PackedByteArray()  # each block's bits every cell of it has (ground.gd _lblocks)
var read_back := false  # it came from the kept file, not the workers

var _hs := PackedFloat32Array()  # the heightmap, row-major, _hw x _hh
var _hw := 0
var _hh := 0
var _lpu := 4.0  # heightmap samples a world unit
var _river := PackedByteArray()  # the river mask's red, _rw x _rh
var _rw := 0
var _rh := 0
var _lakes := PackedByteArray()  # 1 per Lake tile, _tw x _th
var _tw := 0
var _th := 0
var _tile := 4.0
var _lw := 0  # cells across and down, cells a block's side, a cell's world size
var _lh := 0
var _lb := 16
var _lc := 0.125
var _dry := -0.11  # terrain SEA_LEVEL + DRY_ABOVE
var _water := 0.9  # ground.json rivers.water
var _path := ""
var _sig := ""  # every input's hash, keyed into the header before the path is known
var _rows: Array = []  # block row -> [its cells, its blocks' bits]
var _lock := Mutex.new()
var _task := -1  # the worker keying and reading
var _group := -1  # the workers laying the rows
var _write := -1  # the worker keeping it
var _stage := 0  # 0 keying, 1 laying, 2 held, 3 kept


func begin(terrain: Node3D, lw: int, lh: int, lb: int, lc: float) -> bool:
	var land: Variant = terrain.get("land")
	if not land is Image:
		return false
	var b := self
	var img := land as Image
	b._hw = img.get_width()
	b._hh = img.get_height()
	b._hs = img.get_data().to_float32_array() if img.get_format() == Image.FORMAT_RF else PackedFloat32Array()
	if b._hs.size() != b._hw * b._hh or b._hw < 2 or b._hh < 2:
		return false
	b._lpu = float(terrain.get("land_per_unit") if terrain.get("land_per_unit") != null else 4)
	var rm: Variant = terrain.get("river_mask")
	if rm is Image:
		var r := (rm as Image).duplicate() as Image
		if r.is_compressed():
			r.decompress()
		r.convert(Image.FORMAT_R8)
		b._rw = r.get_width()
		b._rh = r.get_height()
		b._river = r.get_data()
	var tiles: Array = terrain.get("terrain") if terrain.get("terrain") is Array else []
	b._tw = int(terrain.get("width"))
	b._th = int(terrain.get("height"))
	b._lakes.resize(b._tw * b._th)
	for i in mini(tiles.size(), b._lakes.size()):
		b._lakes[i] = 1 if String(tiles[i]) == "Lake" else 0
	var tile: Variant = terrain.get("TILE")
	b._tile = float(tile) if tile != null else 4.0
	var sea: Variant = terrain.get("SEA_LEVEL")
	var above: Variant = terrain.get("DRY_ABOVE")
	b._dry = (float(sea) if sea != null else -0.15) + (float(above) if above != null else 0.04)
	b._water = preload("res://scripts/data.gd").num("ground", "rivers.water", 0.9)
	b._lw = lw
	b._lh = lh
	b._lb = lb
	b._lc = lc
	Kept.code()  # the kept files' version made here, so a worker only asks whether one exists
	_task = WorkerThreadPool.add_task(_key, false, "ground land key")
	return true


## Moves the bake on; true once `cells` and `blocks` hold the mask. Cheap: what the main thread does here is waiting
## on finished workers and joining the rows (one copy).
func poll() -> bool:
	if _stage == 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if read_back:
			_stage = 3
			return true
		_stage = 1
		_rows.resize(ceili(float(_lh) / _lb))
		_group = WorkerThreadPool.add_group_task(_row, _rows.size(), -1, false, "ground land")
		return false
	if _stage == 1:
		if not WorkerThreadPool.is_group_task_completed(_group):
			return false
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
		for r: Array in _rows:
			cells.append_array(r[0])
			blocks.append_array(r[1])
		_rows.clear()
		_stage = 2
		_write = WorkerThreadPool.add_task(_keep.bind(cells, blocks), false, "ground land keep")
		return true
	return true


## Whether nothing of it is still running on a worker (finished ones let go); a bake let go first waits here.
func idle() -> bool:
	for t in [_task, _write]:
		if t >= 0 and not WorkerThreadPool.is_task_completed(t):
			return false
	if _group >= 0 and not WorkerThreadPool.is_group_task_completed(_group):
		return false
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
	if _write >= 0:
		WorkerThreadPool.wait_for_task_completion(_write)
		_write = -1
		_stage = 3
	return true


# --- on the workers -------------------------------------------------------------------------------------------------

## Its kept file's name from a hash of everything it is made of, and the file read back when there is one.
func _key() -> void:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(("%d %d %d %d %.6f %.6f %.6f %.3f %d %d %d %d %d %d" % [_lw, _lh, _lb, _hw, _lc, _dry, _water, _lpu, _hh, _rw, _rh, _tw, _th, roundi(_tile * 1000)]).to_utf8_buffer())
	h.update(_hs.to_byte_array())
	h.update(_river)
	h.update(_lakes)
	_sig = h.finish().hex_encode().substr(0, 16)
	_path = Kept.path("land", _sig, "bin")
	if not FileAccess.file_exists(_path):
		return
	var bytes := FileAccess.get_file_as_bytes(_path)
	if bytes.size() < 12:
		return
	var nc := _lw * _lh
	var nb := ceili(float(_lw) / _lb) * ceili(float(_lh) / _lb)
	if bytes.decode_u32(0) != _lw or bytes.decode_u32(4) != _lh or bytes.decode_u32(8) != _lb:
		return
	var all := bytes.slice(12).decompress(nc + nb, FileAccess.COMPRESSION_ZSTD)
	if all.size() != nc + nb:
		return
	cells = all.slice(0, nc)
	blocks = all.slice(nc)
	read_back = true


## One row of blocks laid: its corners by is_land's rule, a cell the bits all four corners share, a block the bits
## every cell of it has.
func _row(bz: int) -> void:
	var z0 := bz * _lb
	var h := mini(_lb, _lh - z0)
	var w := _lw
	var cw := w + 1
	var corner := PackedByteArray()
	corner.resize(cw * (h + 1))
	for j in h + 1:
		var z := (z0 + j) * _lc
		var tz := clampi(floori(z / _tile), 0, _th - 1) * _tw
		var fz := clampf(z * _lpu - 0.5, 0.0, _hh - 1.001)
		var hz := int(fz)
		var kz := fz - hz
		var r0 := hz * _hw
		var rz := clampi(int(z * _lpu), 0, _rh - 1) * _rw
		for i in cw:
			var x := i * _lc
			var c := 0
			if _lakes[tz + clampi(floori(x / _tile), 0, _tw - 1)] == 0:
				var fx := clampf(x * _lpu - 0.5, 0.0, _hw - 1.001)
				var hx := int(fx)
				var kx := fx - hx
				var top := lerpf(_hs[r0 + hx], _hs[r0 + hx + 1], kx)
				var bottom := lerpf(_hs[r0 + _hw + hx], _hs[r0 + _hw + hx + 1], kx)
				if lerpf(top, bottom, kz) > _dry:
					c = DRY | WALK
					if _rw > 0:
						var v := _river[rz + clampi(int(x * _lpu), 0, _rw - 1)]
						if (1.0 if v == 255 else v / 255.0) >= _water:
							c = 0
			corner[j * cw + i] = c
	var out := PackedByteArray()
	out.resize(h * w)
	var bw := ceili(float(w) / _lb)
	var bits := PackedByteArray()
	bits.resize(bw)
	bits.fill(DRY | WALK)
	for j in h:
		var a := j * cw
		for i in w:
			var c := corner[a + i] & corner[a + i + 1] & corner[a + cw + i] & corner[a + cw + i + 1]
			out[j * w + i] = c
			var b := i / _lb
			bits[b] = bits[b] & c
	_lock.lock()
	_rows[bz] = [out, bits]
	_lock.unlock()


## The mask written beside its place and then put there, so nothing reads it half written.
func _keep(c: PackedByteArray, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var part := _path.get_basename() + ".part." + _path.get_extension()
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(_lw)
	f.store_32(_lh)
	f.store_32(_lb)
	var all := c.duplicate()
	all.append_array(b)
	f.store_buffer(all.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	DirAccess.rename_absolute(part, _path)
