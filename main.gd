extends Control

func _ready():
	# Кнопки
	$VBoxContainer/TopPanel/HBoxContainer/Button_Select.pressed.connect(_on_button_pressed.bind("Select"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_AddBone.pressed.connect(_on_button_pressed.bind("Add Bone"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_WeightPaint.pressed.connect(_on_button_pressed.bind("Weight Paint"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_Animate.pressed.connect(_on_button_pressed.bind("Animate"))

	# Клики по вьюпорту
	$VBoxContainer/HBoxContainer/CenterArea.mouse_filter = Control.MOUSE_FILTER_STOP
	$VBoxContainer/HBoxContainer/CenterArea.gui_input.connect(_on_center_area_gui_input)

func _on_button_pressed(tool_name: String):
	print("Нажата кнопка инструмента: ", tool_name)

# Обработка кликов по центральной области
func _on_center_area_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var pos = event.position
		print("Клик по вьюпорту в координатах: ", pos)
