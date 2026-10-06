extends RefCounted
class_name B4Term
## Host terminal device — b4 opcode `tm` (0xBE), matching Pascal uhw_vt /
## b4f tg/tw/ts/ta wrappers. Backed by TermGrid (CHB/FGB/BGB).
##
## Stack effects (cmd char on TOS, popped first):
##   'g' (x y -)  goto xy
##   'a' (n -)    set attr: low nibble = ANSI fg, high nibble = bg (0 = keep black)
##   'e' (c -)    emit char at cursor, advance
##   's' (-)      clear screen
##   'l' (-)      clear to end of line
##   'c' (- x y)  cursor position
##   'w' (f -)    autowrap: nonzero = wrap at the right edge (default), 0 = clip
##   'k' (- f)    keypressed? (-1 / 0): is there a key in the queue
##   'r' (- c)    readkey: pop the oldest queued key code (0 if none)
##
## The host feeds keys with push_key(code) (e.g. from _unhandled_key_input:
## unicode for printable chars, 13 Enter, 8 Backspace), then runs a cart word
## that drains them with k / r. imrun is synchronous, so a cart never blocks
## waiting for a key.

const OP_TM := 0xBE

var vm: B4VM
var grid: TermGrid
var cur := Vector2i(0, 0)
var fg: int = 7
var autowrap := true ## tm 'w'; off = chars past the right edge are dropped
var bg: int = 0
var _key_queue: PackedInt32Array = PackedInt32Array()


func setup(p_vm: B4VM, p_grid: TermGrid) -> void:
	vm = p_vm
	grid = p_grid
	vm.add_op(OP_TM, "tm", _tm)


func push_key(code: int) -> void:
	_key_queue.push_back(code)


func _tm() -> void:
	var cmd := vm.dpop_char()
	match cmd:
		"g":
			var y := vm.dpop()
			var x := vm.dpop()
			_goxy(x, y)
		"a":
			var n := vm.dpop() & 0xFF
			fg = n & 0x0F
			bg = (n >> 4) & 0x0F
		"e":
			_emit(vm.dpop() & 0xFF)
		"s":
			grid.cscr(7, 0)
			cur = Vector2i(0, 0)
			fg = 7
			bg = 0
		"l":
			_clreol()
		"w":
			autowrap = vm.dpop() != 0
		"c":
			vm.dput(cur.x)
			vm.dput(cur.y)
		"k":
			vm.dput(-1 if _key_queue.size() > 0 else 0)
		"r":
			if _key_queue.size() > 0:
				vm.dput(_key_queue[0])
				_key_queue.remove_at(0)
			else:
				vm.dput(0)
		_:
			push_warning("tm: unknown cmd '%s'" % cmd)


func _goxy(x: int, y: int) -> void:
	cur.x = clampi(x, 0, grid.grid_wh.x - 1)
	cur.y = clampi(y, 0, grid.grid_wh.y - 1)


func _emit(code: int) -> void:
	if code == 10: # \n
		cur.x = 0
		cur.y = mini(cur.y + 1, grid.grid_wh.y - 1)
		return
	if code == 13: # \r
		cur.x = 0
		return
	if cur.x >= grid.grid_wh.x:
		return # only reachable with autowrap off: clip
	grid.put(cur.x, cur.y, String.chr(code), fg, bg)
	cur.x += 1
	if autowrap and cur.x >= grid.grid_wh.x:
		cur.x = 0
		cur.y = mini(cur.y + 1, grid.grid_wh.y - 1)


func _clreol() -> void:
	for x in range(cur.x, grid.grid_wh.x):
		grid.put(x, cur.y, " ", fg, bg)
