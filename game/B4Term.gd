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
##   'k' (- f)    keypressed? (-1 / 0) — stub for now
##   'r' (- c)    readkey — stub (pushes 0)

const OP_TM := 0xBE

var vm: B4VM
var grid: TermGrid
var cur := Vector2i(0, 0)
var fg: int = 7
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
	grid.put(cur.x, cur.y, String.chr(code), fg, bg)
	cur.x += 1
	if cur.x >= grid.grid_wh.x:
		cur.x = 0
		cur.y = mini(cur.y + 1, grid.grid_wh.y - 1)


func _clreol() -> void:
	for x in range(cur.x, grid.grid_wh.x):
		grid.put(x, cur.y, " ", fg, bg)
