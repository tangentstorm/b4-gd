"""
Hello
"""
extends SceneTree

const B4VM = preload("res://B4VM.gd")


func make_input_stream():
	# returns a function that gets a string
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		var f = FileAccess.open("res://"+args[0],FileAccess.READ)
		return func():
			return f.get_line().strip_edges()
	else:
		return func():
			return OS.read_string_from_stdin().strip_edges()

func hexdump(data:PackedInt32Array) -> String:
	var toks = []
	for n in data: toks.append('%X' % n)
	return '[' + ' '.join(toks) + ']'


func get_mem(vm:B4VM, adr:int)->String:
	var buf = []
	for i in range(adr, adr+16):
		if i < 0: continue
		if i >= vm.ram.size(): buf.append('..')
		else: buf.append(vm.dis(vm.ram[i]))
	return ' '.join(buf)

func put_mem(vm:B4VM, line:String):
	var toks = line.split(" ")
	var addr = toks[0].right(-1).hex_to_int()
	for i in range(1, toks.size()):
		var tok = toks[i]
		var asm = asm_tok(tok)
		# print('putting ',tok,' -> $', ("%X"%asm), ' at ',addr)
		vm.ram[addr] = asm
		addr += 1

func asm_tok(s:String)->int:
	if len(s) != 2:
		printerr("asm tokens should be len 2. got: ",s)
		return 0
	else:
		match s[0]:
			"'": return s.to_ascii_buffer()[1]
			_:
				if s == '..': return 0
				var op = B4VM.Op.get(s.to_upper(), -1)
				if op == -1: return s.hex_to_int()
				else: return op
		return 0

func ord(s:String)->int:
	return s.to_ascii_buffer()[0]

const REGS = "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"

func _init():
	var get_cmds = make_input_stream()
	var vm = B4VM.new()
	var done = false
	while not done:
		var line = get_cmds.call()
		if line == "": continue
		if line[0]==":":
			put_mem(vm, line)
			continue
		var cmds = line.split(" ")
		for cmd in cmds:
			if done: break
			match cmd:
				"%C": vm.clear()
				"%q": done = true
				"%s": vm.step()
				"?d": print('ds: ', hexdump(vm.ds))
				"?c": print('cs: ', hexdump(vm.cs))
				"?i": print('ip: ', '%X' % vm.ip)
				_:
					if cmd[0]=="?": print(get_mem(vm, cmd.right(-1).hex_to_int()))
					elif cmd[0]=="'":
						if len(cmd) > 1: vm.dput(cmd[1].to_ascii_buffer()[0])
						else: vm.dput(32) # ord(' ')
					elif cmd[0]=="`":
						if len(cmd) != 2: print("malformed dictionary address: ", cmd)
						else: vm.dput(4*(ord(cmd[1])-64))
					elif vm.run_op(cmd): pass
					elif cmd.is_valid_hex_number() and (cmd==cmd.to_upper()):
						vm.dput(cmd.hex_to_int())
					elif len(cmd)==2 and cmd[0] in "!@+`" and cmd[1] in REGS:
						var ra = 4*ord(cmd[1])-64
						match cmd[0]:
							"!": vm.puti(ra, vm.dpop())
							"@": vm.dput(vm.geti(ra))
							"+": var v=vm.geti(ra); vm.dput(v); vm.puti(ra, v+vm.vw)
							"`": vm.dput(ra)
							_: print("!! what does '",cmd,"' mean?"); done=true
					else:
						print("!! what does '",cmd,"' mean?")
						done = true
	vm.free()
	quit()
