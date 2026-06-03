class_name ButtonSpec

var control: String
var text: String

func _init(
	a_control: String,
	a_text: String
):
	control = a_control
	text = a_text

static func create_button_from_spec(a_spec: ButtonSpec) -> Button:
	var ret: Button = Button.new()
	ret.text = a_spec.text
	ret.name = a_spec.control
	ret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ret.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# clean up passing of binding
	ret.connect("pressed", func(): ret.get_parent().get_parent().get_parent()._on_control_button_pressed(ret.name))
	return ret
