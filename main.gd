extends Control

# --- Константы ---
const BONE_SELECT_RADIUS = 30.0
const DEFAULT_BONE_LENGTH = 100.0
const DEBUG_MODE = true

# Узел для рисования
var center_area: Control

# Скелет и кости
var skeleton: Skeleton2D
var root_bone: Bone2D
var child_bone: Bone2D

# Данные меша
var mesh_vertices: PackedVector2Array = PackedVector2Array([
	Vector2(-100, -100),
	Vector2(100, -100),
	Vector2(100, 100),
	Vector2(-100, 100)
])
var mesh_uvs: PackedVector2Array = PackedVector2Array([
	Vector2(0, 0),
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(0, 1)
])
var mesh_indices: PackedInt32Array = [
	0, 1, 2,
	0, 2, 3
]
var vertex_bone_weights = [
	[[0, 0.8], [1, 0.2]],
	[[0, 0.8], [1, 0.2]],
	[[0, 0.2], [1, 0.8]],
	[[0, 0.2], [1, 0.8]]
]

var texture: Texture2D
var deformed_vertices: PackedVector2Array = []

# Перетаскивание
var selected_bone: Bone2D = null
var is_dragging_bone: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Состояние инструментов
var current_tool: String = "Select"

func _ready():
	_log("=== СКРИПТ ЗАПУЩЕН ===")

	# Получаем ссылку на CenterArea
	center_area = $VBoxContainer/HBoxContainer/CenterArea
	if not center_area:
		_log("ОШИБКА: Не найден узел CenterArea!", true)
		return

	# Настройка layout
	var vbox = $VBoxContainer
	if vbox:
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 0
		vbox.offset_top = 0
		vbox.offset_right = 0
		vbox.offset_bottom = 0

	center_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Подключаем кнопки
	var buttons_path = "VBoxContainer/TopPanel/HBoxContainer"
	var btn_select = get_node_or_null(buttons_path + "/Button_Select")
	var btn_add = get_node_or_null(buttons_path + "/Button_AddBone")
	var btn_weight = get_node_or_null(buttons_path + "/Button_WeightPaint")
	var btn_anim = get_node_or_null(buttons_path + "/Button_Animate")

	if btn_select:
		btn_select.pressed.connect(_on_button_pressed.bind("Select"))
	if btn_add:
		btn_add.pressed.connect(_on_button_pressed.bind("Add Bone"))
	if btn_weight:
		btn_weight.pressed.connect(_on_button_pressed.bind("Weight Paint"))
	if btn_anim:
		btn_anim.pressed.connect(_on_button_pressed.bind("Animate"))

	# Включаем обработку мыши
	center_area.mouse_filter = Control.MOUSE_FILTER_STOP
	center_area.gui_input.connect(_on_center_area_gui_input)
	center_area.focus_mode = Control.FOCUS_ALL

	# Подключаем отрисовку center_area
	center_area.draw.connect(_on_center_area_draw)

	# Создаём скелет
	_create_skeleton()

	# Ждем один кадр, чтобы размеры проинициализировались
	call_deferred("_initialize_rig")

	_log("Инициализация завершена")

func _log(message: String, is_error: bool = false):
	if DEBUG_MODE:
		if is_error:
			print("[ERROR] " + message)
		else:
			print("[LOG] " + message)

func _create_skeleton():
	# Создаём скелет
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)

	# Создаём корневую кость
	root_bone = Bone2D.new()
	root_bone.name = "Root"
	skeleton.add_child(root_bone)

	# Создаём дочернюю кость
	child_bone = Bone2D.new()
	child_bone.name = "Child"
	child_bone.position = Vector2(0, 150)
	root_bone.add_child(child_bone)

	# Генерируем текстуру
	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			image.set_pixel(x, y, Color(float(x)/255.0, float(y)/255.0, 0.5, 1.0))
	texture = ImageTexture.create_from_image(image)

	# Инициализируем деформированные вершины
	deformed_vertices = mesh_vertices.duplicate()

func _initialize_rig():
	if not center_area or not root_bone:
		return

	# Устанавливаем корневую кость в центр
	var center_pos = center_area.size / 2
	root_bone.position = center_pos

	_log("=== РИГ ИНИЦИАЛИЗИРОВАН ===")
	_log("Размер CenterArea: " + str(center_area.size))
	_log("Центр: " + str(center_pos))
	_log("Root: " + str(root_bone.position))
	_log("Child: " + str(child_bone.global_position))

	center_area.queue_redraw()

func _on_button_pressed(tool_name: String):
	current_tool = tool_name
	_log("Инструмент: " + tool_name)

	if tool_name != "Select" and selected_bone:
		selected_bone = null
		is_dragging_bone = false

func _on_center_area_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and current_tool == "Select":
			_try_start_drag()
		elif event.button_index == MOUSE_BUTTON_LEFT and current_tool == "Add Bone":
			_add_bone_at_position(event.position)

	elif event is InputEventMouseMotion and is_dragging_bone:
		_update_drag()

	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_dragging_bone:
			_end_drag()

func _add_bone_at_position(position: Vector2):
	if not skeleton:
		return

	var new_bone = Bone2D.new()
	new_bone.name = "Bone_" + str(skeleton.get_child_count())
	new_bone.position = position - root_bone.global_position
	root_bone.add_child(new_bone)

	# Простые веса для новой кости
	var new_weights = []
	for i in range(mesh_vertices.size()):
		var dist = mesh_vertices[i].distance_to(Vector2.ZERO)
		var weight = clamp(1.0 - dist / 300.0, 0.0, 1.0)
		new_weights.append([[0, 1.0 - weight], [skeleton.get_child_count() - 1, weight]])
	vertex_bone_weights = new_weights

	center_area.queue_redraw()
	_log("Добавлена кость: " + new_bone.name)

func _process(delta):
	if not root_bone or not child_bone:
		return

	var root_transform = root_bone.global_transform
	var child_transform = child_bone.global_transform

	for i in range(mesh_vertices.size()):
		var original = mesh_vertices[i]
		var final_pos = Vector2.ZERO
		var total_weight = 0.0

		for bw in vertex_bone_weights[i]:
			var bone_idx = bw[0]
			var weight = bw[1]
			if weight <= 0.0:
				continue

			total_weight += weight
			var transform = root_transform if bone_idx == 0 else child_transform
			final_pos += weight * (transform * original)

		if total_weight > 0.0:
			deformed_vertices[i] = final_pos / total_weight

	if center_area:
		center_area.queue_redraw()

# --- Отрисовка в center_area ---
func _on_center_area_draw():
	if not center_area or not texture:
		return

	# Рисуем сетку для ориентации
	for x in range(0, int(center_area.size.x), 50):
		center_area.draw_line(Vector2(x, 0), Vector2(x, center_area.size.y), Color(0.2, 0.2, 0.3, 0.3), 1.0)
	for y in range(0, int(center_area.size.y), 50):
		center_area.draw_line(Vector2(0, y), Vector2(center_area.size.x, y), Color(0.2, 0.2, 0.3, 0.3), 1.0)

	# Рисуем меш
	if deformed_vertices.size() > 0:
		for i in range(0, mesh_indices.size(), 3):
			var idx0 = mesh_indices[i]
			var idx1 = mesh_indices[i+1]
			var idx2 = mesh_indices[i+2]

			var points = PackedVector2Array([
				deformed_vertices[idx0],
				deformed_vertices[idx1],
				deformed_vertices[idx2]
			])
			var tri_uvs = PackedVector2Array([
				mesh_uvs[idx0],
				mesh_uvs[idx1],
				mesh_uvs[idx2]
			])
			var colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
			center_area.draw_polygon(points, colors, tri_uvs, texture)

	# Рисуем кости
	if skeleton:
		for child in skeleton.get_children():
			if child is Bone2D:
				var bone = child as Bone2D
				var from = bone.global_position
				var to = from

				var has_child_bone = false
				for grandchild in bone.get_children():
					if grandchild is Bone2D:
						to = grandchild.global_position
						has_child_bone = true
						break

				if not has_child_bone:
					to = from + Vector2(DEFAULT_BONE_LENGTH, 0).rotated(bone.global_rotation)

				var color = Color.RED if bone == selected_bone else Color.YELLOW
				var line_width = 5.0 if bone == selected_bone else 3.0
				var circle_radius = 8.0 if bone == selected_bone else 5.0

				center_area.draw_line(from, to, color, line_width)
				center_area.draw_circle(from, circle_radius, Color.ORANGE)

				var font = get_theme_default_font()
				var text_pos = from + Vector2(0, -20)
				center_area.draw_string(font, text_pos, bone.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

# --- Перетаскивание (ИСПРАВЛЕНО) ---
func _try_start_drag():
	if not skeleton or not center_area:
		return

	# Получаем локальную позицию мыши внутри center_area
	var mouse_local = center_area.get_local_mouse_position()

	var closest_bone: Bone2D = null
	var min_dist = BONE_SELECT_RADIUS

	for child in skeleton.get_children():
		if child is Bone2D:
			var bone = child as Bone2D
			# Преобразуем глобальную позицию кости в локальную внутри center_area
			# Для Control используем: global_position - center_area.global_position
			var bone_local = bone.global_position - center_area.global_position
			var dist = bone_local.distance_to(mouse_local)

			if dist < min_dist:
				min_dist = dist
				closest_bone = bone

	if closest_bone:
		selected_bone = closest_bone
		is_dragging_bone = true
		# Для перетаскивания используем глобальные координаты
		var mouse_global = center_area.get_global_mouse_position()
		drag_offset = closest_bone.global_position - mouse_global
		_log("Выбрана кость: " + selected_bone.name + " (дистанция: " + str(min_dist) + ")")
		center_area.queue_redraw()
	else:
		_log("Кость не найдена в радиусе " + str(BONE_SELECT_RADIUS))

func _update_drag():
	if is_dragging_bone and selected_bone and center_area:
		var mouse_global = center_area.get_global_mouse_position()
		selected_bone.global_position = mouse_global + drag_offset

func _end_drag():
	if is_dragging_bone and selected_bone:
		_log("Перетаскивание завершено: " + selected_bone.name + " -> " + str(selected_bone.global_position))
		is_dragging_bone = false
		selected_bone = null
		center_area.queue_redraw()

# --- Отладка ---
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_log("=== ОТЛАДКА ===")
				_log("Root: " + str(root_bone.global_position if root_bone else "null"))
				_log("Child: " + str(child_bone.global_position if child_bone else "null"))
				_log("Вершины: " + str(deformed_vertices))
				if center_area:
					_log("CenterArea размер: " + str(center_area.size))
					_log("CenterArea глобальная позиция: " + str(center_area.global_position))
			KEY_F2:
				if root_bone and child_bone and center_area:
					var center_pos = center_area.size / 2
					root_bone.position = center_pos
					child_bone.position = Vector2(0, 150)
					center_area.queue_redraw()
					_log("=== СБРОС ПОЗИЦИЙ ===")
					_log("Root: " + str(root_bone.position))
					_log("Child локально: " + str(child_bone.position))
					_log("Child глобально: " + str(child_bone.global_position))

func _notification(what):
	match what:
		NOTIFICATION_WM_SIZE_CHANGED:
			if center_area:
				center_area.queue_redraw()
