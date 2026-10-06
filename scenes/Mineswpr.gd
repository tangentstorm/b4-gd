extends Control
## mineswpr on b4: hosts carts/mineswpr-logic.b4 + carts/mineswpr-play.b4 on a
## TermGrid (arcade #45 Phase 3). The cart draws every cell through tm and reads
## the keyboard through tm k / tm r; this script only forwards input.
##
## Keys: type mswp' commands at the ok prompt (hex: `5 C ?`, `a b +`, `r`, `q`),
## Enter runs the line, Backspace edits. Mouse: left = `x y ?`, right = `x y +`
## (or `-` on a flag), sent to the cart's exec word as a command line.
## F2 boots a fresh cart. `q` halts the cart (the original's exit hook).
##
## Esc closes the window (Direct's side panel says "Esc menu": in the arcade it
## opens the pause menu).
##
## Args (after --): --seed <n> fixed minefield; --proof smoke (types a short
## game through the real key path, prints the screen, exits 0 if the cart ran
## it cleanly; automatic when headless); --shot <png> with --proof, also save a
## screenshot (needs a display).

const Cart := preload("res://game/MineswprCart.gd")
const BOARD_ROW := 3
const BOARD_COL := 4

@onready var term_grid: TermGrid = %TermGrid
@onready var status_label: Label = %StatusLabel

var cart = Cart.new()
var seed_value := -1
var halted := false
var _blink := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--seed":
			seed_value = int(args[i + 1])
	term_grid.cell_clicked.connect(_on_cell_clicked)
	_boot()
	if "--proof" in args or DisplayServer.get_name() == "headless":
		_proof.call_deferred()


func _exit_tree() -> void:
	cart.dispose()


func _boot() -> void:
	halted = false
	var err: String = cart.boot(term_grid, seed_value)
	_status(err if err else "")


func _status(err: String) -> void:
	if err:
		status_label.text = "error: " + err
	elif halted:
		status_label.text = "q: cart halted (mineswpr-exit-hook). F2 = new cart"
	else:
		status_label.text = "b4 cart: mineswpr-logic.b4 + mineswpr-play.b4%s   F2 = new cart" \
			% ("" if seed_value < 0 else "  seed %d" % seed_value)


func _process(delta: float) -> void:
	if halted:
		return
	_blink += delta
	if _blink >= 0.5:
		_blink = 0.0
		_after(cart.call_word("blink"))


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if e == null or not e.pressed:
		return
	if e.keycode == KEY_F2:
		_boot()
		get_viewport().set_input_as_handled()
		return
	if e.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if halted:
		return
	var code := 0
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			code = Cart.KEY_ENTER
		KEY_BACKSPACE:
			code = Cart.KEY_BACKSPACE
		_:
			if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
				return
			if e.unicode < 32 or e.unicode > 126:
				return
			code = e.unicode
	cart.push_key(code)
	_after(cart.call_word("keys"))
	_blink = 0.0
	get_viewport().set_input_as_handled()


func _on_cell_clicked(col: int, row: int, button: int) -> void:
	if halted:
		return
	var gx := (col - BOARD_COL) / 4
	var gy := row - BOARD_ROW
	if col < BOARD_COL or gx >= 16 or gy < 0 or gy >= 16:
		return
	var op := "?"
	if button == MOUSE_BUTTON_RIGHT:
		op = "-" if cart.is_flagged(gx, gy) else "+"
	elif button != MOUSE_BUTTON_LEFT:
		return
	_after(cart.exec_line("%X %X %s" % [gx, gy, op]))


func _after(err: String) -> void:
	if cart.vm.ds.size() > 0:
		err = "cart left %s on the data stack" % cart.vm.ds
		cart.vm.ds.clear()
	if cart.quit_requested():
		halted = true
	_status(err)


## Smoke: a short typed game, sent as InputEventKeys through the viewport, so
## it goes through _unhandled_key_input -> tm key queue -> the cart's keys word.
func _proof() -> void:
	var errs := []
	var lines := ["3 4", "\b\b\b0 0 ?\n", "5 c +\n", "6 0 ?\n", "4 4 ?\n", "2 3", "\n", "click", "q\n"]
	for line: String in lines:
		if line == "click":
			# right-click the [-] of cell (B,F): the cart runs "B F +"
			term_grid.cell_clicked.emit(BOARD_COL + 4 * 0xB + 1, BOARD_ROW + 0xF, MOUSE_BUTTON_RIGHT)
			if not cart.is_flagged(0xB, 0xF):
				errs.append("right-click on (B,F) did not flag it")
			continue
		for i in line.length():
			var ev := InputEventKey.new()
			ev.pressed = true
			match line[i]:
				"\n": ev.keycode = KEY_ENTER
				"\b": ev.keycode = KEY_BACKSPACE
				_: ev.unicode = line.unicode_at(i)
			get_viewport().push_input(ev)
		if status_label.text.begins_with("error"):
			errs.append("%s: %s" % [JSON.stringify(line), status_label.text])
	for y in term_grid.grid_wh.y:
		print(term_grid.row_text(y))
	var ok: bool = errs.is_empty() and cart.quit_requested() \
		and term_grid.row_text(0).contains("MINESWPR.RXE")
	print("errors: ", errs)
	print("scene proof: %s" % ("PASS" if ok else "FAIL"))
	var args := OS.get_cmdline_user_args()
	var shot := args.find("--shot")
	if shot >= 0 and shot + 1 < args.size() and DisplayServer.get_name() != "headless":
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
		print("screenshot: ", args[shot + 1])
	cart.dispose()
	get_tree().quit(0 if ok else 1)
