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
	for n in data: toks.append('$%X' % n)
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
			_: match s:
				'lb': return 0x80
				_: return s.hex_to_int()
		return 0


func _init():
	var get_cmds = make_input_stream()
	var vm = B4VM.new()
	var done = false
	while not done:
		var line = get_cmds.call()
		if line == "": continue
		if line[0]=="!":
			put_mem(vm, line)
			continue
		var cmds = line.split(" ")
		for cmd in cmds:
			if done: break
			match cmd:
				"%q": done = true
				"%s": vm.step()
				"?d": print('ds: ', hexdump(vm.ds))
				"?c": print('cs: ', hexdump(vm.cs))
				"?i": print('ip: ', '$%X' % vm.ip)
				_:
					if cmd[0]=="@": print(get_mem(vm, cmd.right(-1).hex_to_int()))
					elif vm.run_op(cmd): pass
					elif cmd.is_valid_hex_number() and (cmd==cmd.to_upper()):
						vm.ds.append(cmd.hex_to_int())
					else:
						print("!! what does '",cmd,"' mean?")
						done = true
	vm.free()
	quit()
