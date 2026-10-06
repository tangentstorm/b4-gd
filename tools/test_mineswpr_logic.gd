extends SceneTree
## Headless proof: carts/mineswpr-logic.b4 on the b4 VM vs golden vectors from
## arcade mineswpr Direct (tests/mineswpr_golden.json).
##
## Run: godot --headless --path . --script res://tools/test_mineswpr_logic.gd
## Prints "ok: ..." / "FAIL: ..." lines, then "proof: PASS" or "proof: FAIL";
## exit code 0 on PASS.
##
## Options (after --):  --cart <path>   check another cart (e.g. a mutant)
##                      --max-steps <n> imrun guard per word (default 2000000)

const B4VMScript := preload("res://B4VM.gd")
const B4AsmScript := preload("res://game/B4Asm.gd")
const B4RandScript := preload("res://game/B4Rand.gd")

const CART_PATH := "res://carts/mineswpr-logic.b4"
const GOLDEN_PATH := "res://tests/mineswpr_golden.json"

var code := ""
var max_steps := 2000000
var vm: B4VM
var rnd: B4Rand
var _checks := 0
var _fail := 0


func _check(cond: bool, msg: String) -> bool:
	_checks += 1
	if cond:
		print("ok: ", msg)
	else:
		print("FAIL: ", msg)
		_fail += 1
	return cond


func _fail_msg(msg: String) -> void:
	_checks += 1
	_fail += 1
	print("FAIL: ", msg)


## Fresh VM + rn device, cart assembled. Returns assembler error or "".
func boot(seed_value: int = 1) -> String:
	if vm:
		vm.free()
	vm = B4VMScript.new()
	vm.max_steps = max_steps
	rnd = B4RandScript.new()
	rnd.setup(vm, seed_value)
	return B4AsmScript.run(vm, code)


## Run a word with args pushed left to right; returns the data stack after.
func word(name: String, args: Array = []) -> PackedInt32Array:
	var a: int = B4AsmScript.label(name)
	if a < 0:
		_fail_msg("word '%s' is not defined in the cart" % name)
		return PackedInt32Array()
	for x in args:
		vm.dput(int(x))
	vm.imrun(a)
	if vm.guard_hit:
		_fail_msg("word '%s' hit max_steps" % name)
	var out: PackedInt32Array = vm.ds.duplicate()
	vm.ds.clear()
	return out


func reg(r: String) -> int:
	return vm.geti(vm.rega(r))


func cell_value(i: int) -> int:
	return vm.geti(reg("G") + 4 * i)


func grid_rows() -> Array:
	var rows := []
	for y in 16:
		var s := ""
		for x in 16:
			var v := cell_value(y * 16 + x)
			if v < 0 or (v & 0xF8) != 0 or (v >> 8) > 8:
				s += "??"
			else:
				s += "%d%d" % [v >> 8, v & 7]
		rows.append(s)
	return rows


func grid_sig() -> int:
	var h := 0
	for i in 256:
		h = (h * 31 + cell_value(i) + i) & 0x7FFFFFFF
	return h


func covered_count() -> int:
	var r := word("covered-count")
	return r[0] if r.size() == 1 else -1


## Compare VM state to a golden state dict; returns "" or a description.
func diff_state(g: Dictionary) -> String:
	var errs := []
	if reg("F") != int(g["flags"]):
		errs.append("flagCount %d != %d" % [reg("F"), int(g["flags"])])
	var over := reg("O")
	if over != (-1 if g["over"] else 0):
		errs.append("gameOver? %d != %s" % [over, g["over"]])
	var cov := covered_count()
	if cov != int(g["covered"]):
		errs.append("covered-count %d != %d" % [cov, int(g["covered"])])
	if g.has("grid"):
		var rows := grid_rows()
		for y in 16:
			if rows[y] != g["grid"][y]:
				errs.append("row %X: b4 %s != golden %s" % [y, rows[y], g["grid"][y]])
				break
	if grid_sig() != int(g["sig"]):
		errs.append("grid sig %d != %d" % [grid_sig(), int(g["sig"])])
	return "; ".join(errs)


func do_step(s: Array) -> void:
	var op: String = s[0]
	match op:
		"prod", "flag+", "flag-":
			word(op, [int(s[2]) * 16 + int(s[1])])
		"flood":
			word("flood", [int(s[1]), int(s[2])])
		"game-new":
			word("game-new")
		_:
			_fail_msg("unknown golden op %s" % op)


func load_mines(mines: Array) -> void:
	word("grid-fill")
	for m in mines:
		word("mine-set", [int(m[1]) * 16 + int(m[0])])
	word("hints-create")
	word("game-reset")


func run_steps(name: String, steps: Array) -> void:
	var n := 0
	for st in steps:
		do_step(st["do"])
		var d := diff_state(st)
		if not d.is_empty():
			_fail_msg("%s step %d %s: %s" % [name, n, JSON.stringify(st["do"]), d])
			return
		n += 1
	_check(true, "%s: %d steps match Direct" % [name, n])


func _initialize() -> void:
	var gold = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	if gold == null:
		print("FAIL: cannot read ", GOLDEN_PATH)
		print("proof: FAIL")
		quit(1)
		return
	var cart := CART_PATH
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--cart":
			cart = args[i + 1]
		elif args[i] == "--max-steps":
			max_steps = int(args[i + 1])
	code = _extract_code(FileAccess.get_file_as_string(cart))
	var err := boot()
	if not _check(err.is_empty(), "cart assembles (%s)" % (err if err else "no errors")):
		_finish()
		return
	print("golden: arcade %s %s" % [gold["source"]["commit"].left(7), gold["source"]["file"]])

	# -- point methods
	var bad := []
	for p in gold["points"]:
		var r := word("inbounds?", [p["x"], p["y"]])
		var want := -1 if p["inbounds"] else 0
		if r.size() != 1 or r[0] != want:
			bad.append("inbounds? %d %d -> %s" % [p["x"], p["y"], r])
		if p.has("cell"):
			var c := word("cell", [p["x"], p["y"]])
			if c.size() != 1 or c[0] != int(p["cell"]):
				bad.append("cell %d %d -> %s" % [p["x"], p["y"], c])
	for t in gold["c2xy"]:
		var r := word("c>xy", [t[0]])
		if r.size() != 2 or r[0] != int(t[1]) or r[1] != int(t[2]):
			bad.append("c>xy %d -> %s" % [t[0], r])
	_check(bad.is_empty(), "point methods inbounds? / cell / c>xy %s" % ", ".join(bad))

	# -- game-new from a seed: same mines + hints as Direct Logic.new(seed)
	for s in gold["seeds"]:
		boot(int(s["seed"]))
		word("game-new")
		var rows := grid_rows()
		var mines := []
		for i in 256:
			if cell_value(i) & 1:
				mines.append(i)
		var ok: bool = rows == s["grid"] and mines.size() == s["mines"].size()
		var detail := ""
		if not ok:
			for y in 16:
				if rows[y] != s["grid"][y]:
					detail = " row %X b4 %s golden %s" % [y, rows[y], s["grid"][y]]
					break
		ok = ok and reg("F") == 0 and reg("O") == 0 and covered_count() == 256
		_check(ok, "game-new seed %d: %d mines, grid == Direct%s" % [s["seed"], mines.size(), detail])

	# -- scripted scenarios (mines loaded explicitly, like Direct load_mines)
	for sc in gold["scenarios"]:
		boot()
		load_mines(sc["mines"])
		var d := diff_state(sc["start"])
		if not d.is_empty():
			_fail_msg("%s setup: %s" % [sc["name"], d])
			continue
		run_steps(sc["name"], sc["steps"])

	# -- seeded play: game-new + scripted random ops (rng stream parity)
	for pl in gold["play"]:
		boot(int(pl["seed"]))
		word("game-new")
		var d := diff_state(pl["start"])
		if not d.is_empty():
			_fail_msg("%s start: %s" % [pl["name"], d])
			continue
		run_steps(pl["name"], pl["steps"])
		var e := diff_state(pl["end"])
		_check(e.is_empty(), "%s end grid == Direct %s" % [pl["name"], e])

	_finish()


func _finish() -> void:
	var ok := _fail == 0
	print("proof: %s (%d checks, %d failed)" % ["PASS" if ok else "FAIL", _checks, _fail])
	if vm:
		vm.free()
		vm = null
	quit(0 if ok else 1)


static func _extract_code(text: String) -> String:
	var buf := PackedStringArray()
	var in_code := false
	for raw in text.split("\n"):
		var t := raw.strip_edges()
		if t == "__code__":
			in_code = true
			continue
		if t.begins_with("__") and t.ends_with("__"):
			in_code = false
			continue
		if in_code:
			buf.append(raw)
	return "\n".join(buf)
