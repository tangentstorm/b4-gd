extends SceneTree

const B4VM = preload("res://B4VM.gd")

func _init():
	print("hello")
	var vm = B4VM.new()
	print(vm.ds)
	vm.free()
	quit()
