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

func _init():
	var get_cmds = make_input_stream()
	var vm = B4VM.new()
	var done = false
	while not done:
		var cmds = get_cmds.call().split(" ")
		for cmd in cmds:
			if done: break
			match cmd:
				"%q": done = true
				"?d": print('ds: ', hexdump(vm.ds))
				"?c": print('cs: ', hexdump(vm.cs))
				"?i": print('ip: ', '$%X' % vm.ip)
				_:
					if vm.run_op(cmd): pass
					elif cmd.is_valid_hex_number() and (cmd==cmd.to_upper()):
						vm.ds.append(cmd.hex_to_int())
					else:
						print("!! what does '",cmd,"' mean?")
						done = true
	vm.free()
	quit()
