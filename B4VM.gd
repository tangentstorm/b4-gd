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
	JM, HP, H0, CL, RT, NX,
	IO, MV,
	RB, WB, RI, WI,
	DB=0xFE, HL}

var opk = Op.keys()
var opv = Op.values()

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

func puti(addr:int, n:int):
	# write 32-bit int as little-endian bytes to ram
	ram[addr] = n & 0xFF
	ram[addr+1] = (n >> 8) & 0xFF
	ram[addr+2] = (n >> 16) & 0xFF
	ram[addr+3] = (n >> 24) & 0xFF


func _go(a): ip = max(0x100,a)-1

func _i8(a) -> int:
	var r=ram[a]
	if (r>=0x80): r=-(r&0x7F)-1
	return r

func _hop(): _go(ip+_i8(ip+1))

func run_op(s:String)->bool:
	# TODO: map these to bytes and dispatch on those
	match s:
		"..": return true # no-op
		"lb": dput(ram[ip+1]); ip += 1 # "load byte"
		"li": dput(geti(ip+1)); ip += 3 # "load integer"
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
		"wb": var a = dpop(); var b = dpop(); ram[a] = b
		"rb": dput(ram[dpop()])
		"ri": dput(geti(dpop()))
		"wi": var adr = dpop(); var val = dpop(); puti(adr, val)
		"rx": var adr = (4*24); var ptr = geti(adr); puti(adr, ptr+4); dput(geti(ptr))
		"ry": var adr = (4*25); var ptr = geti(adr); puti(adr, ptr+4); dput(geti(ptr))
		"wz": var adr = (4*26); var ptr = geti(adr); puti(adr, ptr+4); puti(ptr, dpop())
		"hp": _hop()
		"h0":
			if dpop() == 0: _hop()
			else: ip += 1
		"jm": _go(geti(ip+1))
		"cl": cput(ip+4); _go(geti(ip+1))
		"rt": _go(cpop())
		"nx":
				if ctos()>0: cput(cpop()-1)
				if ctos()==0: cpop(); ip += 1
				else: _hop()
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
	for i in range(len(opv)):
		if opv[i] == op:
			return opk[i].to_lower()
	return '%02X' % op

func step():
	var op = dis(ram[ip]) # TODO: avoid round-trip through string
	if not run_op(op):
		print("step: unknown op [",op,"=", ram[ip],"] at ram[",ip,"]")
		return false
	ip += 1
	return true

func _init():
	ram.resize(1024)
