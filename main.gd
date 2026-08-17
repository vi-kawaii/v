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

# --- Weight Paint ---
var weight_paint_bone: Bone2D = null          # Активная кость для рисования
var brush_radius: float = 80.0               # Радиус кисти
var brush_strength: float = 0.3              # Сила кисти (0.0 - 1.0)
var is_painting: bool = false                # Зажата ли кнопка мыши

func _ready():
	_log("=== СКРИПТ ЗАПУЩЕН ===")

	center_area = $VBoxContainer/HBoxContainer/CenterArea
	if not center_area:
		_log("ОШИБКА: Не найден узел CenterArea!", true)
		return

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

	center_area.mouse_filter = Control.MOUSE_FILTER_STOP
	center_area.gui_input.connect(_on_center_area_gui_input)
	center_area.focus_mode = Control.FOCUS_ALL

	center_area.draw.connect(_on_center_area_draw)

	call_deferred("_create_skeleton_and_rig")

	_log("Инициализация запущена, ожидаем завершения...")

func _log(message: String, is_error: bool = false):
	if DEBUG_MODE:
		if is_error:
			print("[ERROR] " + message)
		else:
			print("[LOG] " + message)

func _create_skeleton_and_rig():
	if not center_area:
		_log("ОШИБКА: center_area не инициализирован!", true)
		return

	_log("=== СОЗДАНИЕ СКЕЛЕТА ВНУТРИ CENTER_AREA ===")

	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	center_area.add_child(skeleton)
	_log("Скелет добавлен в center_area")

	root_bone = Bone2D.new()
	root_bone.name = "Root"
	var center_pos = center_area.size / 2
	root_bone.position = center_pos
	skeleton.add_child(root_bone)
	_log("Root создан в позиции: " + str(root_bone.position))

	child_bone = Bone2D.new()
	child_bone.name = "Child"
	child_bone.position = Vector2(0, 150)
	root_bone.add_child(child_bone)
	_log("Child создан, локальная позиция: " + str(child_bone.position))
	_log("Child глобальная позиция (относительно center_area): " + str(child_bone.global_position))

	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			image.set_pixel(x, y, Color(float(x)/255.0, float(y)/255.0, 0.5, 1.0))
	texture = ImageTexture.create_from_image(image)

	deformed_vertices = mesh_vertices.duplicate()

	_log("=== РИГ ГОТОВ ===")
	_log("Размер CenterArea: " + str(center_area.size))
	_log("Root.position: " + str(root_bone.position))
	_log("Child.global_position (локально в center_area): " + str(child_bone.global_position))

	center_area.queue_redraw()

func _on_button_pressed(tool_name: String):
	current_tool = tool_name
	_log("Инструмент: " + tool_name)

	# При переключении в Weight Paint сбрасываем выделение
	if tool_name != "Select" and selected_bone:
		selected_bone = null
		is_dragging_bone = false

	# Если переключились в Weight Paint, но нет активной кости — выбираем первую попавшуюся
	if tool_name == "Weight Paint" and weight_paint_bone == null:
		var all_bones = _get_all_bones()
		if all_bones.size() > 0:
			weight_paint_bone = all_bones[0]
			_log("Автоматически выбрана кость для Weight Paint: " + weight_paint_bone.name)

func _on_center_area_gui_input(event: InputEvent):
	# --- Режим Weight Paint ---
	if current_tool == "Weight Paint":
		# Клик левой кнопкой — начать рисование
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = true
			_paint_weights(event.position)

		# Отпускание левой кнопки — остановить рисование
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = false

		# Движение мыши с зажатой кнопкой — продолжать рисование
		elif event is InputEventMouseMotion and is_painting:
			_paint_weights(event.position)

		# Правый клик — выбрать кость для рисования
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_select_weight_paint_bone(event.position)

		return  # Выходим, чтобы не обрабатывать другие режимы

	# --- Режим Select ---
	if current_tool == "Select":
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_try_start_drag(event.position)

		elif event is InputEventMouseMotion and is_dragging_bone:
			_update_drag(event.position)

		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_dragging_bone:
				_end_drag()

		return

	# --- Режим Add Bone ---
	if current_tool == "Add Bone":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_add_bone_at_position(event.position)

		return

# --- WEIGHT PAINT: Рисование весов ---
func _paint_weights(position: Vector2):
	if not weight_paint_bone:
		_log("ОШИБКА: Не выбрана кость для Weight Paint! Правый клик по кости.", true)
		return

	# Находим индекс активной кости
	var all_bones = _get_all_bones()
	var bone_index = -1
	for i in range(all_bones.size()):
		if all_bones[i] == weight_paint_bone:
			bone_index = i
			break

	if bone_index == -1:
		_log("ОШИБКА: Активная кость не найдена в скелете!", true)
		return

	# Проходим по всем вершинам и изменяем веса в радиусе кисти
	for i in range(mesh_vertices.size()):
		# Вершина в локальных координатах (она же деформированная)
		var vertex_pos = deformed_vertices[i]
		var dist = vertex_pos.distance_to(position)

		if dist < brush_radius:
			# Чем ближе вершина к центру кисти, тем сильнее эффект
			var falloff = 1.0 - (dist / brush_radius)
			var weight_delta = brush_strength * falloff

			# Ищем слот с активной костью
			var found = false
			for j in range(vertex_bone_weights[i].size()):
				if vertex_bone_weights[i][j][0] == bone_index:
					# Увеличиваем вес
					vertex_bone_weights[i][j][1] += weight_delta
					found = true
					break

			# Если слота нет — добавляем
			if not found:
				vertex_bone_weights[i].append([bone_index, weight_delta])

			# Нормализуем веса (сумма = 1.0)
			var total_weight = 0.0
			for bw in vertex_bone_weights[i]:
				total_weight += bw[1]

			if total_weight > 0.0:
				for j in range(vertex_bone_weights[i].size()):
					vertex_bone_weights[i][j][1] /= total_weight

	_log("Рисование весов: позиция " + str(position) + ", кость " + weight_paint_bone.name)
	center_area.queue_redraw()

# --- WEIGHT PAINT: Выбор кости правым кликом ---
func _select_weight_paint_bone(position: Vector2):
	var all_bones = _get_all_bones()
	var closest_bone: Bone2D = null
	var min_dist = BONE_SELECT_RADIUS

	for bone in all_bones:
		if bone is Bone2D:
			var dist = bone.global_position.distance_to(position)
			if dist < min_dist:
				min_dist = dist
				closest_bone = bone

	if closest_bone:
		weight_paint_bone = closest_bone
		_log("Выбрана кость для Weight Paint: " + weight_paint_bone.name)
		center_area.queue_redraw()
	else:
		_log("Кость не найдена в радиусе " + str(BONE_SELECT_RADIUS))

# --- Add Bone ---
func _add_bone_at_position(position: Vector2):
	if not skeleton or not root_bone:
		_log("ОШИБКА: Скелет или корневая кость не существуют!", true)
		return

	var all_bones = _get_all_bones()
	var bone_index = all_bones.size()

	var new_bone = Bone2D.new()
	new_bone.name = "Bone_" + str(bone_index)
	new_bone.position = position - root_bone.position
	root_bone.add_child(new_bone)

	_log("Добавлена кость: " + new_bone.name + " с индексом " + str(bone_index))
	_log("Позиция (локальная): " + str(new_bone.position))

	var updated_weights = []
	for i in range(mesh_vertices.size()):
		var vertex_weights = vertex_bone_weights[i].duplicate()
		vertex_weights.append([bone_index, 0.0])

		var total_weight = 0.0
		for bw in vertex_weights:
			total_weight += bw[1]

		if total_weight > 0.0:
			for j in range(vertex_weights.size()):
				vertex_weights[j][1] /= total_weight
		else:
			var equal_weight = 1.0 / vertex_weights.size()
			for j in range(vertex_weights.size()):
				vertex_weights[j][1] = equal_weight

		updated_weights.append(vertex_weights)

	vertex_bone_weights = updated_weights

	_log("=== ОБНОВЛЕНЫ ВЕСА ===")
	for i in range(mesh_vertices.size()):
		_log("Вершина " + str(i) + ": " + str(vertex_bone_weights[i]))

	center_area.queue_redraw()
	_log("Новая кость добавлена и веса обновлены")

# --- Вспомогательные функции ---
func _get_all_bones() -> Array:
	var bones = []
	_recursive_collect_bones(skeleton, bones)
	return bones

func _recursive_collect_bones(node: Node, bones: Array):
	for child in node.get_children():
		if child is Bone2D:
			bones.append(child)
			_recursive_collect_bones(child, bones)

# --- Process ---
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

# --- Отрисовка ---
func _on_center_area_draw():
	if not center_area or not texture:
		return

	# Сетка для ориентации
	for x in range(0, int(center_area.size.x), 50):
		center_area.draw_line(Vector2(x, 0), Vector2(x, center_area.size.y), Color(0.2, 0.2, 0.3, 0.3), 1.0)
	for y in range(0, int(center_area.size.y), 50):
		center_area.draw_line(Vector2(0, y), Vector2(center_area.size.x, y), Color(0.2, 0.2, 0.3, 0.3), 1.0)

	# --- РИСУЕМ МЕШ (всегда с текстурой) ---
	if deformed_vertices.size() > 0:
		# Рисуем текстурированный меш
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

		# --- WIREFRAME (сетка полигонов) ---
		for i in range(0, mesh_indices.size(), 3):
			var idx0 = mesh_indices[i]
			var idx1 = mesh_indices[i+1]
			var idx2 = mesh_indices[i+2]

			var p0 = deformed_vertices[idx0]
			var p1 = deformed_vertices[idx1]
			var p2 = deformed_vertices[idx2]

			# Линии треугольника (КРАСНЫЕ)
			center_area.draw_line(p0, p1, Color(1.0, 0.0, 0.0, 0.5), 1.0)
			center_area.draw_line(p1, p2, Color(1.0, 0.0, 0.0, 0.5), 1.0)
			center_area.draw_line(p2, p0, Color(1.0, 0.0, 0.0, 0.5), 1.0)

		# --- ВЕСА (цветные точки поверх текстуры) ---
		# Рисуем ТОЛЬКО в режиме Weight Paint
		if current_tool == "Weight Paint" and weight_paint_bone:
			# Находим индекс активной кости
			var all_bones = _get_all_bones()
			var bone_index = -1
			for i in range(all_bones.size()):
				if all_bones[i] == weight_paint_bone:
					bone_index = i
					break

			if bone_index != -1:
				# Рисуем точки поверх всего
				for i in range(deformed_vertices.size()):
					var weight = 0.0
					for bw in vertex_bone_weights[i]:
						if bw[0] == bone_index:
							weight = bw[1]
							break

					# Цвет от синего (0) к красному (1)
					var color = Color(weight, 0.0, 1.0 - weight)
					var radius = 10.0  # чуть больше для видимости
					center_area.draw_circle(deformed_vertices[i], radius, color)

					# Контур точки для лучшей видимости
					center_area.draw_circle(deformed_vertices[i], radius, Color(0.0, 0.0, 0.0, 0.3), 1.0)

					# Текст с весом
					var font = get_theme_default_font()
					var text = str(weight).substr(0, 4)
					var text_pos = deformed_vertices[i] + Vector2(-10, -18)
					center_area.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# --- РИСУЕМ КОСТИ ---
	if skeleton:
		var all_bones = _get_all_bones()
		for bone in all_bones:
			if bone is Bone2D:
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

				# Подсветка для активной кости в Weight Paint
				var is_active = (current_tool == "Weight Paint" and bone == weight_paint_bone)
				var color = Color.GREEN if is_active else (Color.RED if bone == selected_bone else Color.YELLOW)
				var line_width = 6.0 if is_active else (5.0 if bone == selected_bone else 3.0)
				var circle_radius = 10.0 if is_active else (8.0 if bone == selected_bone else 5.0)

				center_area.draw_line(from, to, color, line_width)
				center_area.draw_circle(from, circle_radius, Color.ORANGE)

				var font = get_theme_default_font()
				var text_pos = from + Vector2(0, -20)
				center_area.draw_string(font, text_pos, bone.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	# --- КРУГ КИСТИ (всегда сверху) ---
	if current_tool == "Weight Paint":
		var mouse_pos = center_area.get_local_mouse_position()
		center_area.draw_circle(mouse_pos, brush_radius, Color(1.0, 1.0, 1.0, 0.15))
		center_area.draw_circle(mouse_pos, brush_radius, Color(1.0, 1.0, 1.0, 0.5), 1.0)

		# Дополнительно: центр круга
		center_area.draw_circle(mouse_pos, 3.0, Color(1.0, 1.0, 1.0, 0.8))

# --- Перетаскивание ---
func _try_start_drag(local_pos: Vector2):
	if not skeleton or not center_area:
		return

	_log("=== ПОПЫТКА ВЫБОРА КОСТИ ===")
	_log("Позиция клика (локальная): " + str(local_pos))

	var closest_bone: Bone2D = null
	var min_dist = BONE_SELECT_RADIUS

	var all_bones = _get_all_bones()
	for bone in all_bones:
		if bone is Bone2D:
			var bone_pos = bone.global_position
			var dist = bone_pos.distance_to(local_pos)
			_log("Кость " + bone.name + " в " + str(bone_pos) + ", дистанция: " + str(dist))

			if dist < min_dist:
				min_dist = dist
				closest_bone = bone

	if closest_bone:
		selected_bone = closest_bone
		is_dragging_bone = true
		drag_offset = closest_bone.global_position - local_pos
		_log("=== ВЫБРАНА КОСТЬ ===")
		_log("Имя: " + selected_bone.name)
		_log("Позиция: " + str(selected_bone.global_position))
		_log("Смещение: " + str(drag_offset))
		center_area.queue_redraw()
	else:
		_log("Кость не найдена в радиусе " + str(BONE_SELECT_RADIUS))

func _update_drag(local_pos: Vector2):
	if is_dragging_bone and selected_bone and center_area:
		selected_bone.global_position = local_pos + drag_offset

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
				if root_bone:
					_log("Root.position: " + str(root_bone.position))
					_log("Root.global_position: " + str(root_bone.global_position))
				if child_bone:
					_log("Child.position: " + str(child_bone.position))
					_log("Child.global_position: " + str(child_bone.global_position))
				_log("Вершины: " + str(deformed_vertices))
				if center_area:
					_log("CenterArea размер: " + str(center_area.size))
					_log("CenterArea глобальная позиция: " + str(center_area.global_position))
				if weight_paint_bone:
					_log("Weight Paint активная кость: " + weight_paint_bone.name)
				else:
					_log("Weight Paint активная кость: не выбрана")
			KEY_F2:
				if root_bone and child_bone and center_area:
					var center_pos = center_area.size / 2
					root_bone.position = center_pos
					child_bone.position = Vector2(0, 150)
					center_area.queue_redraw()
					_log("=== СБРОС ПОЗИЦИЙ ===")
					_log("Root: " + str(root_bone.position))
					_log("Child локально: " + str(child_bone.position))
			KEY_F3:
				# Увеличить радиус кисти
				brush_radius = min(brush_radius + 10, 200)
				_log("Радиус кисти: " + str(brush_radius))
			KEY_F4:
				# Уменьшить радиус кисти
				brush_radius = max(brush_radius - 10, 20)
				_log("Радиус кисти: " + str(brush_radius))
			KEY_F5:
				# Увеличить силу кисти
				brush_strength = min(brush_strength + 0.1, 1.0)
				_log("Сила кисти: " + str(brush_strength))
			KEY_F6:
				# Уменьшить силу кисти
				brush_strength = max(brush_strength - 0.1, 0.05)
				_log("Сила кисти: " + str(brush_strength))

func _notification(what):
	match what:
		NOTIFICATION_WM_SIZE_CHANGED:
			if center_area:
				center_area.queue_redraw()
