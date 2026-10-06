extends Control
## Hello-term runner: TermGrid + tm device + carts/hello-term.b4

@onready var term_grid: TermGrid = %TermGrid
@onready var status_label: Label = %StatusLabel

var vm: B4VM
var term: B4Term

const CART_PATH := "res://carts/hello-term.b4"
const EXPECT_ROW0 := "hello term"
const EXPECT_ROW1 := "color ok"
const EXPECT_FG0 := 0x0B # light yellow / ANSI 11
const EXPECT_FG1_OK := 0x0A # light green / ANSI 10


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var proof := "proof" in args or DisplayServer.get_name() == "headless"

	vm = B4VM.new()
	term = B4Term.new()
	term.setup(vm, term_grid)

	var err := _load_and_run(CART_PATH)
	if not err.is_empty():
		status_label.text = "error: %s" % err
		print(status_label.text)
		if proof:
			await get_tree().create_timer(0.05).timeout
			if vm:
				vm.free()
				vm = null
			get_tree().quit(1)
		return

	var row0 := term_grid.row_text(0).strip_edges()
	var row1 := term_grid.row_text(1).strip_edges()
	status_label.text = "hello-term | row0=%s | row1=%s" % [row0, row1]
	print(status_label.text)
	print("fg[0,0]=%d fg[0,8]=%d fg[1,0]=%d fg[1,6]=%d" % [
		term_grid.fg_at(0, 0), term_grid.fg_at(8, 0),
		term_grid.fg_at(0, 1), term_grid.fg_at(6, 1),
	])

	if proof:
		var ok := row0.begins_with(EXPECT_ROW0) and row1.begins_with(EXPECT_ROW1)
		ok = ok and term_grid.fg_at(0, 0) == EXPECT_FG0
		ok = ok and term_grid.fg_at(6, 1) == EXPECT_FG1_OK
		print("proof: %s" % ("PASS" if ok else "FAIL"))
		await get_tree().create_timer(0.05).timeout
		if vm:
			vm.free()
			vm = null
		get_tree().quit(0 if ok else 1)


func _load_and_run(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "cannot open %s" % path
	var text := f.get_as_text()
	var code := _extract_code(text)
	if code.is_empty():
		return "no __code__ in %s" % path
	return B4Asm.run(vm, code)


func _extract_code(text: String) -> String:
	var lines := text.split("\n")
	var in_code := false
	var buf: PackedStringArray = PackedStringArray()
	for raw in lines:
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
