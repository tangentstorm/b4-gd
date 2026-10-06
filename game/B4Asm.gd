extends RefCounted
class_name B4Asm

## b4i-compatible assembler for cart __code__: registers, named words,
## control-flow macros (.i/.e/.t), signed immediates, gm.

const REGS := "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"

static var _labels: Dictionary = {} # name -> address
static var _asm_stack: Array = [] # compile-time hop slots
static var _first_error: String = ""

static func _err(msg: String) -> void:
	push_error(msg)
	if _first_error.is_empty():
		_first_error = msg

## Address of a :name label from the last run(), or -1.
static func label(name: String) -> int:
	return int(_labels.get(name, -1))


## Assemble source into vm. Returns "" on success, or first assembler error.
static func run(vm: B4VM, source: String) -> String:
	_labels.clear()
	_asm_stack.clear()
	_first_error = ""
	var state := 0 # 0=IMM 1=ASM
	for raw_line in source.split("\n"):
		var line := raw_line
		var hash_i := line.find("#")
		if hash_i >= 0:
			line = line.substr(0, hash_i)
		line = line.strip_edges()
		if line.is_empty():
			continue
		for tok in _tokenize(line):
			state = _handle(vm, tok, state)
			if not _first_error.is_empty():
				return _first_error
	return _first_error

static func _tokenize(line: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var i := 0
	while i < line.length():
		while i < line.length() and line[i] == " ":
			i += 1
		if i >= line.length():
			break
		var start := i
		while i < line.length() and line[i] != " ":
			i += 1
		out.append(line.substr(start, i - start))
	return out

static func _is_reg_op(tok: String) -> bool:
	return tok.length() == 2 and tok[0] in "^@!+`" and REGS.contains(tok[1])

static func _is_named_op(vm: B4VM, tok: String) -> bool:
	if tok in ["..", "c0", "c1", "c2", "n1", "c4", "gm", "tm", "ls"]:
		return true
	if vm._custom_names.has(tok):
		return true
	if _is_reg_op(tok):
		return true
	var op = B4VM.Op.get(tok.to_upper(), -1)
	return op != -1

static func _run_named(vm: B4VM, tok: String) -> void:
	if vm._custom_names.has(tok):
		var fn: Callable = vm._custom_ops[vm._custom_names[tok]]
		fn.call()
		return
	if tok == "gm" and vm._custom_names.has("gm"):
		var fn2: Callable = vm._custom_ops[vm._custom_names["gm"]]
		fn2.call()
		return
	if not vm.run_op(tok):
		push_warning("B4Asm: run_op failed for '%s'" % tok)

static func _emit(vm: B4VM, tok: String) -> void:
	var b := vm.asm_tok(tok)
	if b < 0:
		_err("B4Asm: cannot emit %s" % tok)
		return
	_emit_byte(vm, b)

static func _emit_byte(vm: B4VM, b: int) -> void:
	var a := vm.here()
	vm.ram[a] = b & 0xFF
	vm.set_here(a + 1)

static func _emit_i32(vm: B4VM, v: int) -> void:
	var a := vm.here()
	vm.puti(a, v)
	vm.set_here(a + 4)

static func _emit_call(vm: B4VM, addr: int) -> void:
	_emit(vm, "cl")
	_emit_i32(vm, addr)

static func _parse_signed_hex(s: String) -> Variant:
	## Parse hex with optional leading '-'. Returns null if not hex.
	var neg := false
	var body := s
	if body.begins_with("-"):
		neg = true
		body = body.substr(1)
	if body.is_empty() or not body.is_valid_hex_number():
		return null
	var v: int = body.hex_to_int()
	if neg:
		v = -v
	return v

static func _hop_here(vm: B4VM) -> void:
	if _asm_stack.is_empty():
		_err("B4Asm: hop stack underflow")
		return
	var slot: int = _asm_stack.pop_back()
	var dist := vm.here() - slot
	if dist < 0 or dist > 126:
		_err("B4Asm: hop out of range dist=%d at %d" % [dist, slot])
		return
	vm.ram[slot] = (dist + 1) & 0xFF

static func _macro(vm: B4VM, tok: String) -> void:
	match tok:
		".i":
			_emit(vm, "h0")
			_asm_stack.push_back(vm.here())
			_emit_byte(vm, 0)
		".e":
			_emit(vm, "hp")
			_asm_stack.push_back(vm.here())
			_emit_byte(vm, 0)
			if _asm_stack.size() >= 2:
				var a = _asm_stack[_asm_stack.size() - 1]
				var b = _asm_stack[_asm_stack.size() - 2]
				_asm_stack[_asm_stack.size() - 1] = b
				_asm_stack[_asm_stack.size() - 2] = a
			_hop_here(vm)
		".t":
			_hop_here(vm)
		".w":
			_asm_stack.push_back(vm.here())
		".d":
			_emit(vm, "h0")
			_asm_stack.push_back(vm.here())
			_emit_byte(vm, 0)
		".o":
			# hop back to .w, then resolve .d exit
			_emit(vm, "hp")
			if _asm_stack.size() < 2:
				_err("B4Asm: .o without .w/.d")
				return
			var slot_d: int = _asm_stack.pop_back()
			var dest_w: int = _asm_stack.pop_back()
			var here_now := vm.here()
			var back := dest_w - here_now
			_emit_byte(vm, (back + 1) & 0xFF)
			# resolve .d forward hop to here
			var dist2 := vm.here() - slot_d
			vm.ram[slot_d] = (dist2 + 1) & 0xFF
		_:
			_err("B4Asm: unknown macro '%s'" % tok)

static func _handle(vm: B4VM, tok: String, state: int) -> int:
	var t := tok[0] if tok.length() > 0 else ""
	if tok == ";":
		return 0
	# Control-flow macros (.i .e .t ...)
	if t == "." and tok != ".." and tok.length() >= 2:
		if state == 1:
			_macro(vm, tok)
		else:
			_err("B4Asm: macro %s outside ASM" % tok)
		return state
	# :R / :name — enter ASM; bind register or label
	if t == ":":
		var name := tok.substr(1)
		if tok == ":" or tok == "::":
			return 1
		if name.length() == 1 and REGS.contains(name):
			vm.puti(vm.rega(name), vm.here())
			return 1
		# named word / label
		_labels[name] = vm.here()
		return 1
	# char literals
	if t == "'":
		var parts := tok.substr(1).split("'")
		for ch in parts:
			var c: int
			if ch.is_empty():
				c = 32
			elif ch.length() == 1:
				c = ch.unicode_at(0)
			else:
				_err("B4Asm: bad literal %s" % tok)
				continue
			if state == 1:
				_emit_byte(vm, c)
			else:
				vm.dput(c)
		return state
	# $hex u32 (optional signed $-C0)
	if t == "$":
		var hx := tok.substr(1)
		var parsed = _parse_signed_hex(hx)
		if parsed != null:
			var v: int = parsed
			if state == 1:
				_emit_i32(vm, v)
			else:
				vm.dput(v)
		else:
			_err("B4Asm: bad $ literal %s" % tok)
		return state
	# register ops
	if _is_reg_op(tok):
		var r := vm.rega(tok[1])
		if state == 1:
			if t == "`":
				_emit(vm, "lb")
				_emit_byte(vm, tok.unicode_at(1) & 0xFF)
			else:
				_emit(vm, tok)
		else:
			match t:
				"`": vm.dput(r)
				"^": vm.imrun(vm.geti(r))
				"@": vm.dput(vm.geti(r))
				"!": vm.puti(r, vm.dpop())
				"+":
					var v := vm.geti(r)
					vm.dput(v)
					vm.puti(r, v + vm.vw)
		return state
	# named ops (opcodes)
	if _is_named_op(vm, tok):
		if state == 1:
			_emit(vm, tok)
		else:
			_run_named(vm, tok)
		return state
	# labeled word call / immediate run
	if _labels.has(tok):
		var addr: int = _labels[tok]
		if state == 1:
			_emit_call(vm, addr)
		else:
			vm.imrun(addr)
		return state
	# signed / unsigned hex byte (or imm push)
	var hv = _parse_signed_hex(tok)
	if hv != null:
		var v2: int = hv
		if state == 1:
			_emit_byte(vm, v2 & 0xFF)
		else:
			vm.dput(v2)
		return state
	# An unknown token used to be a warning and assembled to nothing, so a typo
	# or a forward reference to a later label silently dropped code.
	_err("B4Asm: unknown token '%s'" % tok)
	return state
