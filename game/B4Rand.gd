extends RefCounted
class_name B4Rand
## Host random device -- b4 opcode `rn` (0xBD, a free public opcode next to `tm`).
##
##   rn ( n - r )   r = random integer in 0..n-1 (0 when n <= 0)
##
## Backed by Godot's RandomNumberGenerator.randi_range(0, n-1), so a cart that
## calls `rn` in the same order as a GDScript port (e.g. arcade mineswpr Direct's
## randcell: x then y) gets the same numbers from the same seed.

const OP_RN := 0xBD

var vm: B4VM
var rng := RandomNumberGenerator.new()


func setup(p_vm: B4VM, seed_value: int = -1) -> void:
	vm = p_vm
	reseed(seed_value)
	vm.add_op(OP_RN, "rn", _rn)


## seed_value < 0 randomizes.
func reseed(seed_value: int) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func _rn() -> void:
	var n := vm.dpop()
	vm.dput(rng.randi_range(0, n - 1) if n > 0 else 0)
