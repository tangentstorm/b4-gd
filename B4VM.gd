extends Node

var ds = PackedInt32Array() # data stack
var cs = PackedInt32Array() # call stack
var ram = PackedByteArray() # ram
var ip = 0x100


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


func run_op(s:String)->bool:
	# TODO: map these to bytes and dispatch on those
	match s:
		"..": return true # no-op
		"du": ds.push_back(dtos())
		"dr": cs.push_back(dpop())
		"rd": ds.push_back(cpop())
		"sw": var a = dpop(); var b = dpop(); ds.push_back(a); ds.push_back(b)
		"ov": ds.push_back(dnos())
		"ad": var a = dpop(); var b = dpop(); ds.push_back(a + b)
		"sb": var a = dpop(); var b = dpop(); ds.push_back(b - a)
		"ml": var a = dpop(); var b = dpop(); ds.push_back(a * b)
		"dv": var a = dpop(); var b = dpop(); ds.push_back(a / b)
		"md": var a = dpop(); var b = dpop(); ds.push_back(a % b)
		"ng": var a = dpop(); ds.push_back(-a)
		"sl": var a = dpop(); var b = dpop(); ds.push_back(a << b)
		"sr": var a = dpop(); var b = dpop(); ds.push_back(a >> b)
		"an": var a = dpop(); var b = dpop(); ds.push_back(a & b)
		"or": var a = dpop(); var b = dpop(); ds.push_back(a | b)
		"xr": var a = dpop(); var b = dpop(); ds.push_back(a ^ b)
		"nt": var a = dpop(); ds.push_back(~a)
		"eq": var a = dpop(); var b = dpop(); ds.push_back(a == b)
		"ne": var a = dpop(); var b = dpop(); ds.push_back(a != b)
		"lt": var a = dpop(); var b = dpop(); ds.push_back(a < b)
		"gt": var a = dpop(); var b = dpop(); ds.push_back(a > b)
		"le": var a = dpop(); var b = dpop(); ds.push_back(a <= b)
		"ge": var a = dpop(); var b = dpop(); ds.push_back(a >= b)
		"zp": dpop() # "zap"
		"wb": var a = dpop(); var b = dpop(); ram[b] = a
		"rb": ds.push_back(ram[dpop()])
		"lb": ds.push_back(ram[ip]); ip += 1
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
