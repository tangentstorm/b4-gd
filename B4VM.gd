extends Node
class_name B4VM

## b4 VM — extended for gm / game loop while keeping cli.gd ops working.

var ds: Array[int] = [] # data stack (64-bit Godot ints; PackedInt32Array wrapped FFFFFFFF to -1)
var cs: Array[int] = [] # call stack
var ram = PackedByteArray() # ram
var ip = 0x100
var vw = 4 # value width in bytes
var st = 1 # run state (1=running, 0=halted)
var dbg = 0
var max_steps := 100000 ## imrun step guard (raise for long-running words)
var guard_hit := false ## true if the last imrun stopped at max_steps

## Custom ops registered via add_op (byte -> {name, fn})
var _custom_ops: Dictionary = {} # int -> Callable
var _custom_names: Dictionary = {} # String -> int
var _custom_bytes: Dictionary = {} # int -> String
var _dis_cache: Dictionary = {} ## opcode byte -> op name, for step()

const REGS = "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
const RAM_SIZE = 65536

enum Op {
	EX = 0x7F,
	AD, SB, ML, DV, MD, SH,
	AN, OR, XR, NT, EQ, LT,
	DU, SW, OV, ZP, DC, CD,
	RV, WV, LB, LI,
	JM, HP, H0, CL, RT, NX,
	VB = 0xC0, VI, # VI=0xC1; bytes 0xC0/0xC1 also mean c0/c1 (JS)
	DB = 0xFE, HL
}

# Extra named constants matching JS (for assembler / carts)
const OP_C0 = 0xC0
const OP_C1 = 0xC1
const OP_C2 = 0xF6
const OP_N1 = 0xF7
const OP_C4 = 0xF8
const OP_GM = 0xA0
const OP_TM = 0xBE  # terminal device (TermGrid / uhw_vt)
const OP_LS = 0x9C  # load signed byte (immeiate)

var opk = Op.keys()
var opv = Op.values()

func clear():
	ds.clear()
	cs.clear()
	ram.clear()
	ram.resize(RAM_SIZE)
	ip = 0x100
	vw = 4
	st = 1
	dbg = 0
	# HERE (_) starts at 0x100
	puti(rega("_"), 0x100)

func rega(c: String) -> int:
	return 4 * (c.unicode_at(0) - 64)

func _gr(r: String) -> int:
	return geti(rega(r))

func _sr(r: String, x: int) -> void:
	puti(rega(r), x)

func here() -> int:
	return _gr("_")

func set_here(a: int) -> void:
	_sr("_", a)

func pop(ia: Array) -> int:
	if ia.size() == 0:
		printerr("stack underflow")
		return 0
	else:
		var res = ia[ia.size() - 1]
		ia.resize(ia.size() - 1)
		return res

func tos(ia: Array) -> int:
	if ia.size() == 0:
		printerr("stack underflow")
		return 0
	else:
		return ia[ia.size() - 1]

func nos(ia: Array) -> int:
	if ia.size() < 2:
		printerr("stack underflow")
		return 0
	else:
		return ia[ia.size() - 2]

func dtos() -> int: return tos(ds)
func dnos() -> int: return nos(ds)
func ctos() -> int: return tos(cs)
func cpop() -> int: return pop(cs)
func dpop() -> int: return pop(ds)
func dput(n: int): ds.push_back(n)
func cput(n: int): cs.push_back(n)

func dpop_char() -> String:
	return String.chr(dpop() & 0xFF)

func todo(s: String): print("TODO: ", s)

func geti(addr: int) -> int:
	# fetch a signed 32-bit little-endian integer from ram
	var n: int = ram[addr] | (ram[addr + 1] << 8) | (ram[addr + 2] << 16) | (ram[addr + 3] << 24)
	if n >= 0x80000000:
		n -= 0x100000000
	return n

func puti(addr: int, n: int):
	ram[addr] = n & 0xFF
	ram[addr + 1] = (n >> 8) & 0xFF
	ram[addr + 2] = (n >> 16) & 0xFF
	ram[addr + 3] = (n >> 24) & 0xFF

func _go(a):
	ip = maxi(0x100, a) - 1

func _i8(a) -> int:
	# signed byte (two's complement, like JS b4 `(ram[a]<<24)>>24`).
	# Was -(r & 0x7F) - 1, which sent every backward hop (.o / nx) to the
	# wrong address: $FF meant -128 instead of -1.
	var r = ram[a]
	if r >= 0x80:
		r -= 0x100
	return r

func _hop(): _go(ip + _i8(ip + 1))
func _rb(): dput(ram[dpop()])
func _ri(): dput(geti(dpop()))
func _wi():
	var a = dpop()
	var v = dpop()
	puti(a, v)
func _wb():
	var a = dpop()
	var b = dpop()
	ram[a] = b & 0xFF

func add_op(opbyte: int, opname: String, opfunc: Callable) -> void:
	_custom_ops[opbyte] = opfunc
	_custom_names[opname] = opbyte
	_custom_bytes[opbyte] = opname

func asm_tok(s: String) -> int:
	if s == "..":
		return 0
	if _custom_names.has(s):
		return _custom_names[s]
	if s == "c0":
		return OP_C0
	if s == "c1":
		return OP_C1
	if s == "c2":
		return OP_C2
	if s == "n1":
		return OP_N1
	if s == "c4":
		return OP_C4
	if s == "gm":
		return OP_GM
	if s == "tm":
		return OP_TM
	if s == "ls":
		return OP_LS
	# register-form ops: ^A @A !A +A
	if s.length() == 2 and s[0] in "^@!+" and REGS.contains(s[1]):
		var ri = s.unicode_at(1) - 64
		match s[0]:
			"^": return ri
			"@": return 0x20 + ri
			"!": return 0x40 + ri
			"+": return 0x60 + ri
	var op = Op.get(s.to_upper(), -1)
	if op != -1:
		return op
	# hex byte
	if s.is_valid_hex_number():
		return s.hex_to_int() & 0xFF
	return -1

func run_op(s: String) -> bool:
	match s:
		"..": return true
		"ad":
			var a = dpop(); var b = dpop(); dput(b + a)
		"sb":
			var a = dpop(); var b = dpop(); dput(b - a)
		"ml":
			var a = dpop(); var b = dpop(); dput(b * a)
		"dv":
			var a = dpop(); var b = dpop(); dput(int(float(b) / a))
		"md":
			var a = dpop(); var b = dpop(); dput(b % a)
		"sh":
			var a = dpop(); var b = dpop()
			if a < 0:
				dput(b >> (-a))  # match JS >>> for +vals; arithmetic OK for fixed-point
			else:
				dput(b << a)
		"an":
			var a = dpop(); var b = dpop(); dput(b & a)
		"or":
			var a = dpop(); var b = dpop(); dput(b | a)
		"xr":
			var a = dpop(); var b = dpop(); dput(b ^ a)
		"nt":
			var a = dpop(); dput(~a)
		"eq":
			var a = dpop(); var b = dpop(); dput(-int(b == a))
		"lt":
			var a = dpop(); var b = dpop(); dput(-int(b < a))
		"du": dput(dtos())
		"ov": dput(dnos())
		"sw":
			var a = dpop(); var b = dpop(); dput(a); dput(b)
		"zp": dpop()
		"dc": cput(dpop())
		"cd": dput(cpop())
		"wv": _wb() if vw == 1 else _wi()
		"rv": _rb() if vw == 1 else _ri()
		"vb": vw = 1
		"vi": vw = 4
		"lb":
			dput(ram[ip + 1]); ip += 1
		"li":
			dput(geti(ip + 1)); ip += 4
		"hp": _hop()
		"h0":
			if dpop() == 0:
				_hop()
			else:
				ip += 1
		"jm": _go(geti(ip + 1))
		"cl":
			cput(ip + 5); _go(geti(ip + 1))
		"rt":
			var a = cpop()
			if a:
				_go(a)
			else:
				st = 0
		"nx":
			if ctos() > 0:
				cput(cpop() - 1)
			if ctos() == 0:
				cpop(); ip += 1
			else:
				_hop()
		"c0": dput(0)
		"c1": dput(1)
		"c2": dput(2)
		"n1": dput(-1)
		"c4": dput(4)
		"ls":
			var sb = ram[ip + 1]
			if sb >= 0x80:
				sb -= 0x100
			dput(sb); ip += 1
		"hl": st = 0
		"db": dbg = 1
		_:
			if _custom_names.has(s):
				var b = _custom_names[s]
				var fn: Callable = _custom_ops[b]
				fn.call()
				return true
			return false
	return true

func dis(n: int) -> String:
	var op = n & 0xFF
	if op == 0:
		return ".."
	if op < 0:
		return "??"
	if op < 0x20:
		return "^" + String.chr(64 + op)
	if op < 0x40:
		return "@" + String.chr(64 + op - 0x20)
	if op < 0x60:
		return "!" + String.chr(64 + op - 0x40)
	if op < 0x80:
		return "+" + String.chr(64 + op - 0x60)
	if _custom_bytes.has(op):
		return _custom_bytes[op]
	if op == OP_C1:
		return "c1"
	if op == OP_C2:
		return "c2"
	if op == OP_N1:
		return "n1"
	if op == OP_C4:
		return "c4"
	if op == OP_LS:
		return "ls"
	# OP_C0 overlaps VB
	if op == OP_C0:
		return "c0"
	if op > 256:
		printerr("dis: op out of range: ", op)
		return "??"
	for i in range(len(opv)):
		if opv[i] == op:
			return opk[i].to_lower()
	return "%02X" % op

func _er(r: int) -> void:
	cput(ip + 1)
	_go(geti(r))

func _rr(r: int) -> void:
	dput(geti(r))

func _wr(r: int) -> void:
	puti(r, dpop())

func _ir(r: int) -> void:
	var d = dpop()
	var v = geti(r)
	dput(v)
	puti(r, v + d)

func step() -> bool:
	var opb = ram[ip]
	if opb == 0:
		ip += 1
		return true
	# Register-form opcodes (match JS)
	if opb < 0x20:
		_er(4 * opb)
		ip += 1
		return true
	if opb < 0x40:
		_rr(4 * (opb - 0x20))
		ip += 1
		return true
	if opb < 0x60:
		_wr(4 * (opb - 0x40))
		ip += 1
		return true
	if opb < 0x80:
		_ir(4 * (opb - 0x60))
		ip += 1
		return true
	# Custom ops
	if _custom_ops.has(opb):
		var fn: Callable = _custom_ops[opb]
		fn.call()
		ip += 1
		return true
	# Named / enum ops via string dispatch (dis() scans the enum; cache it)
	var op = _dis_cache.get(opb, "")
	if op == "":
		op = dis(opb)
		_dis_cache[opb] = op
	if not run_op(op):
		print("step: unknown op [", op, "=", opb, "] at ram[", ip, "]")
		return false
	ip += 1
	return true

## Immediate-run a word at address a (like JS imrun). Saves/restores ip.
func imrun(a: int) -> void:
	if a == 0:
		return
	st = 1
	dbg = 0
	cput(ip)
	cput(0)
	ip = a
	var guard = 0
	guard_hit = false
	while st and not dbg and guard < max_steps:
		if not step():
			break
		guard += 1
	if st and not dbg and guard >= max_steps:
		guard_hit = true
	if not dbg:
		ip = cpop()

func _init():
	clear()
