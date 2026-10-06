extends RefCounted
## Host glue for the b4 mineswpr cart (arcade #45 Phase 3): one B4VM with the
## tm terminal (B4Term on a TermGrid) and the rn random device (B4Rand), and
## carts/mineswpr-logic.b4 + carts/mineswpr-play.b4 assembled as one program.
## Used by scenes/Mineswpr.gd and tools/test_mineswpr_screen.gd.

const B4VMScript := preload("res://B4VM.gd")
const B4AsmScript := preload("res://game/B4Asm.gd")
const B4TermScript := preload("res://game/B4Term.gd")
const B4RandScript := preload("res://game/B4Rand.gd")

const CARTS := ["res://carts/mineswpr-logic.b4", "res://carts/mineswpr-play.b4"]
const ENTRY_WORDS := ["keys", "exec", "blink", "draw", "has?", "cell"]
const EXEC_BUF := 0x9700 ## scratch line for exec (mouse clicks)
const KEY_ENTER := 13
const KEY_BACKSPACE := 8

var vm: B4VM
var term: B4Term
var rnd: B4Rand
var words := {} ## entry word -> address
var steps_guard := 5000000


## Assemble the carts against grid. seed_value < 0 randomizes the minefield.
## Returns "" or the first error. The cart's own immediate code runs
## game-new and draw, so the grid shows the board when this returns.
func boot(grid: TermGrid, seed_value: int = -1) -> String:
	dispose()
	vm = B4VMScript.new()
	vm.max_steps = steps_guard
	term = B4TermScript.new()
	term.setup(vm, grid)
	rnd = B4RandScript.new()
	rnd.setup(vm, seed_value)
	var code := PackedStringArray()
	for path in CARTS:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			return "cannot read %s" % path
		code.append(extract_code(text))
	var err: String = B4AsmScript.run(vm, "\n".join(code))
	if not err.is_empty():
		return err
	if vm.guard_hit:
		return "cart boot hit max_steps"
	words.clear()
	for w in ENTRY_WORDS:
		var a: int = B4AsmScript.label(w)
		if a < 0:
			return "cart has no word '%s'" % w
		words[w] = a
	vm.ds.clear()
	return ""


## Run an entry word with args pushed left to right. Returns "" or an error
## (step guard hit, or a word that left junk on the data stack).
func call_word(name: String, args: Array = []) -> String:
	for x in args:
		vm.dput(int(x))
	vm.imrun(words[name])
	if vm.guard_hit:
		return "%s hit max_steps" % name
	return ""


## Queue one key code for tm r, as the scene does for a real keypress.
func push_key(code: int) -> void:
	term.push_key(code)


## Type a string: "\n" = Enter, "\b" = Backspace; then run the cart's keys word.
func type_keys(s: String) -> String:
	for i in s.length():
		var ch := s[i]
		if ch == "\n":
			push_key(KEY_ENTER)
		elif ch == "\b":
			push_key(KEY_BACKSPACE)
		else:
			push_key(ch.unicode_at(0))
	return call_word("keys")


## Run a whole command line (the mouse path), without touching the typed line.
func exec_line(line: String) -> String:
	var n := mini(line.length(), 0x80)
	for i in n:
		vm.ram[EXEC_BUF + i] = line.unicode_at(i) & 0xFF
	return call_word("exec", [EXEC_BUF, n])


func reg(r: String) -> int:
	return vm.geti(vm.rega(r))


func cell_value(c: int) -> int:
	return vm.geti(reg("G") + 4 * c)


func is_flagged(x: int, y: int) -> bool:
	return cell_value(y * 16 + x) & 4 != 0


## The player typed q (the cart's mineswpr-exit-hook).
func quit_requested() -> bool:
	return reg("Z") != 0


func dispose() -> void:
	if vm:
		vm.free()
		vm = null


static func extract_code(text: String) -> String:
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
