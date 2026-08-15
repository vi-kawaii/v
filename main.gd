extends Control

var viewport: SubViewport
var skeleton: Skeleton2D
var bone: Bone2D
var mesh_instance: MeshInstance2D
var shader_material: ShaderMaterial

# Кастомный узел для отрисовки костей и меша
class RigVisualizer extends Node2D:
	var skeleton_ref: Skeleton2D
	var bone_ref: Bone2D

	func _draw():
		# Рисуем "меш" как прямоугольник
		var center = Vector2(200, 200)
		var size = Vector2(200, 200)

		# Если есть кость, вращаем прямоугольник вокруг кости
		if bone_ref:
			center = bone_ref.global_position
			var points = [
				center + Vector2(-size.x/2, -size.y/2),
				center + Vector2(size.x/2, -size.y/2),
				center + Vector2(size.x/2, size.y/2),
				center + Vector2(-size.x/2, size.y/2)
			]
			# Вращаем точки
			var rotated_points = []
			for p in points:
				var local = p - center
				var rotated = center + Vector2(
					local.x * cos(bone_ref.global_rotation) - local.y * sin(bone_ref.global_rotation),
					local.x * sin(bone_ref.global_rotation) + local.y * cos(bone_ref.global_rotation)
				)
				rotated_points.append(rotated)
			draw_colored_polygon(rotated_points, Color.WHITE)
		else:
			draw_rect(Rect2(center - size/2, size), Color.WHITE)

		# Рисуем кость
		if skeleton_ref:
			for child in skeleton_ref.get_children():
				if child is Bone2D:
					var bone_2d = child as Bone2D
					var from = bone_2d.global_position
					var to = from + Vector2(100, 0).rotated(bone_2d.global_rotation)
					draw_line(from, to, Color.YELLOW, 3.0)
					draw_circle(from, 5.0, Color.ORANGE)

	func _process(_delta):
		queue_redraw()

func _ready():
	# Настройка layout
	var vbox = $VBoxContainer
	var center_area = $VBoxContainer/HBoxContainer/CenterArea
	var viewport_container = $VBoxContainer/HBoxContainer/CenterArea/ViewportContainer
	viewport = $VBoxContainer/HBoxContainer/CenterArea/ViewportContainer/Viewport

	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_top = 0
	vbox.offset_right = 0
	vbox.offset_bottom = 0

	center_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport.size = Vector2(800, 600)

	# Кнопки
	$VBoxContainer/TopPanel/HBoxContainer/Button_Select.pressed.connect(_on_button_pressed.bind("Select"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_AddBone.pressed.connect(_on_button_pressed.bind("Add Bone"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_WeightPaint.pressed.connect(_on_button_pressed.bind("Weight Paint"))
	$VBoxContainer/TopPanel/HBoxContainer/Button_Animate.pressed.connect(_on_button_pressed.bind("Animate"))

	# Клики по вьюпорту
	$VBoxContainer/HBoxContainer/CenterArea.mouse_filter = Control.MOUSE_FILTER_STOP
	$VBoxContainer/HBoxContainer/CenterArea.gui_input.connect(_on_center_area_gui_input)

	# Создаём тестовый риг
	_create_test_rig()

	print("Viewport size: ", viewport.size)

func _on_button_pressed(tool_name: String):
	print("Нажата кнопка инструмента: ", tool_name)

func _on_center_area_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		print("Клик по центральной области: ", event.position)

func _create_test_rig():
	var rig_root = viewport.get_node("RigRoot")

	# --- 1. Создаём скелет ---
	skeleton = Skeleton2D.new()
	bone = Bone2D.new()
	bone.name = "Bone"
	bone.position = Vector2(200, 200)  # Центр прямоугольника
	skeleton.add_child(bone)

	# --- 2. Создаём визуализатор ---
	var visualizer = RigVisualizer.new()
	visualizer.name = "RigVisualizer"
	visualizer.skeleton_ref = skeleton
	visualizer.bone_ref = bone

	# --- 3. Добавляем камеру ---
	var camera = Camera2D.new()
	camera.position = Vector2(400, 300)
	camera.enabled = true

	# --- 4. Добавляем всё в RigRoot ---
	rig_root.add_child(skeleton)
	rig_root.add_child(visualizer)
	rig_root.add_child(camera)

	print("Риг создан")
	print("Скелет: ", skeleton != null)
	print("Кость: ", bone != null)

func _process(delta):
	# Вращаем кость
	if bone:
		bone.rotation += delta * 1.5
