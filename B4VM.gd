extends Node

var ds = PackedInt32Array() # data stack
var cs = PackedInt32Array() # call stack
var ram = PackedByteArray() # ram
var ip = 0x100

enum Op {
	EX = 0x7F,
	LB, LI, DU, SW, OV, ZP, DC, CD,
	AD, SB, ML, DV, MD, SH,
	AN, OR, XR, NT,
	EQ, LT,
	HP, H0, CL, RT,
	IO, MV,
	RB, WB, RI, WI, NX, DB }

func pop(ia:PackedInt32Array)->int:
	if ia.size() == 0:
		printerr("stack underflow")
		return 0
	else:
		var res = ia[ia.size() - 1]
		ia.resize(ia.size() - 1)
		return res

func tos(ia:PackedInt32Array)->int:
	# "top of stack"
	if ia.size() == 0:
		printerr("stack underflow")
		return 0
	else:
		return ia[ia.size() - 1]

func nos(ia:PackedInt32Array)->int:
	# "next on stack"
	if ia.size() < 2:
		printerr("stack underflow")
		return 0
	else:
		return ia[ia.size() - 2]

func dtos()->int: return tos(ds)
func dnos()->int: return nos(ds)
func ctos()->int: return tos(cs)
func cpop()->int:	return pop(cs)
func dpop()->int:	return pop(ds)
func dput(n:int): ds.push_back(n)
func cput(n:int): cs.push_back(n)

func todo(s:String): print("TODO: ", s)

func geti(addr:int)->int:
	# fetch a 32-bit little-endian integer from ram
	return ram[addr] | (ram[addr+1] << 8) | (ram[addr+2] << 16) | (ram[addr+3] << 24)

func run_op(s:String)->bool:
	# TODO: map these to bytes and dispatch on those
	match s:
		"..": return true # no-op
		"lb": dput(ram[ip]); ip += 1 # "load byte"
		"li": dput(geti(ip)); ip += 4 # "load integer"
		"du": dput(dtos())
		"ov": dput(dnos())
		"sw": var a = dpop(); var b = dpop(); dput(a); dput(b)
		"zp": dpop() # "zap"
		"dc": cput(dpop())
		"cd": dput(cpop())
		"ad": var a = dpop(); var b = dpop(); dput(b + a)
		"sb": var a = dpop(); var b = dpop(); dput(b - a)
		"ml": var a = dpop(); var b = dpop(); dput(b * a)
		"dv": var a = dpop(); var b = dpop(); dput(int(float(b)/a))
		"md": var a = dpop(); var b = dpop(); dput(b % a)
		"sh": var a = dpop(); var b = dpop(); dput(b << a)
		"an": var a = dpop(); var b = dpop(); dput(b & a)
		"or": var a = dpop(); var b = dpop(); dput(b | a)
		"xr": var a = dpop(); var b = dpop(); dput(b ^ a)
		"nt": var a = dpop(); dput(~a)
		"eq": var a = dpop(); var b = dpop(); dput(-int(b == a))
		"lt": var a = dpop(); var b = dpop(); dput(-int(b < a))
		"hp": todo("hp")
		"h0": todo("h0")
		"cl": todo("cl")
		"rt": ip = cpop()
		"wb": var a = dpop(); var b = dpop(); ram[b] = a
		"rb": dput(ram[dpop()])
		"ri": dput(geti(dpop()))
		_: return false
	return true

func dis(n:int) -> String:
	var op = n & 0xFF
	if op == 0: return '..'
	if op < 0: return '??'
	if op < 32: return '^' + char(op+64) # 64=ord('@')
	if op < 128: return "'" + char(op)
	if op > 256:
		printerr("dis: op out of range: ", op)
		return '??'
	match op:
		0x7F: return '^?'
		0x80: return 'lb'
	return '%02X' % op

func step():
	var op = dis(ram[ip]) # TODO: avoid round-trip through string
	ip += 1
	if not run_op(op):
		print("step: unknown op [",op,"=", ram[ip-1],"] at ram[",ip-1,"]")
		return false
	return true

func _init():
	ram.resize(1024)
