# mcp_runtime_bridge.gd
# AutoLoad singleton for MCP runtime features (screenshot, input simulation)
# This script is automatically injected by the MCP server when running projects
extends Node

const CAPTURE_REQUEST_FILE = "user://mcp_capture_request.txt"
const CAPTURE_OUTPUT_BASE = "user://mcp_screenshot"
const CAPTURE_META_FILE = "user://mcp_screenshot_meta.json"

const INPUT_REQUEST_FILE = "user://mcp_input_request.json"
const INPUT_STATUS_FILE = "user://mcp_input_status.json"

var _capture_pending := false
var _input_pending := false

func _ready() -> void:
	# Ensure we process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	# Check for capture request
	if not _capture_pending and FileAccess.file_exists(CAPTURE_REQUEST_FILE):
		_capture_pending = true
		_handle_capture_request()

	# Check for input request
	if not _input_pending and FileAccess.file_exists(INPUT_REQUEST_FILE):
		_input_pending = true
		_handle_input_request()

func _handle_capture_request() -> void:
	# Read request parameters
	var request_content = FileAccess.get_file_as_string(CAPTURE_REQUEST_FILE)
	var params = _parse_json(request_content)

	# Delete request file immediately to prevent re-processing
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAPTURE_REQUEST_FILE))

	# Wait for frame to finish rendering
	await RenderingServer.frame_post_draw

	# Capture viewport
	var viewport = get_viewport()
	if viewport == null:
		_write_meta(CAPTURE_META_FILE, {"success": false, "error": "No viewport available"})
		_capture_pending = false
		return

	var texture = viewport.get_texture()
	if texture == null:
		_write_meta(CAPTURE_META_FILE, {"success": false, "error": "Viewport has no texture"})
		_capture_pending = false
		return

	var image = texture.get_image()
	if image == null:
		_write_meta(CAPTURE_META_FILE, {"success": false, "error": "Failed to get image from viewport texture"})
		_capture_pending = false
		return

	# Resize if needed
	var max_dim = params.get("max_dimension", 1920)
	var size = image.get_size()
	if size.x > max_dim or size.y > max_dim:
		var scale_factor = float(max_dim) / max(size.x, size.y)
		var new_size = Vector2i(
			int(size.x * scale_factor),
			int(size.y * scale_factor)
		)
		image.resize(new_size.x, new_size.y, Image.INTERPOLATE_LANCZOS)

	# Save image
	var format = params.get("format", "png")
	var output_path = CAPTURE_OUTPUT_BASE + "." + format
	var save_error: int

	if format == "jpg" or format == "jpeg":
		var quality = params.get("quality", 85) / 100.0
		save_error = image.save_jpg(output_path, quality)
	else:
		save_error = image.save_png(output_path)

	if save_error != OK:
		_write_meta(CAPTURE_META_FILE, {"success": false, "error": "Failed to save image: error code " + str(save_error)})
		_capture_pending = false
		return

	# Write metadata
	_write_meta(CAPTURE_META_FILE, {
		"success": true,
		"window_width": DisplayServer.window_get_size().x,
		"window_height": DisplayServer.window_get_size().y,
		"image_width": image.get_width(),
		"image_height": image.get_height(),
	})

	_capture_pending = false

func _handle_input_request() -> void:
	var request_content = FileAccess.get_file_as_string(INPUT_REQUEST_FILE)
	var events = _parse_json(request_content)
	
	# Delete request file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INPUT_REQUEST_FILE))
	
	if events is Array:
		for event_data in events:
			await _process_input_event(event_data)
		_write_meta(INPUT_STATUS_FILE, {"success": true})
	elif events is Dictionary:
		await _process_input_event(events)
		_write_meta(INPUT_STATUS_FILE, {"success": true})
	else:
		_write_meta(INPUT_STATUS_FILE, {"success": false, "error": "Invalid input request format"})
		
	_input_pending = false

func _process_input_event(data: Dictionary) -> void:
	var type = data.get("type", "")
	var action = data.get("action", "click") # click, press, release, move
	
	match type:
		"key":
			var keycode = OS.find_keycode_from_string(data.get("key", ""))
			if keycode == KEY_NONE:
				return
			
			var event = InputEventKey.new()
			event.keycode = keycode
			
			if action == "press" or action == "click":
				event.pressed = true
				Input.parse_input_event(event)
			
			if action == "click":
				await get_tree().process_frame
				event = InputEventKey.new()
				event.keycode = keycode
				event.pressed = false
				Input.parse_input_event(event)
			elif action == "release":
				event.pressed = false
				Input.parse_input_event(event)
				
		"mouse_button":
			var button_index = _get_mouse_button_index(data.get("button", "left"))
			var pos = Vector2(data.get("x", 0), data.get("y", 0))
			
			var event = InputEventMouseButton.new()
			event.button_index = button_index
			event.position = pos
			event.global_position = pos
			
			if action == "press" or action == "click":
				event.pressed = true
				Input.parse_input_event(event)
				
			if action == "click":
				await get_tree().process_frame
				event = InputEventMouseButton.new()
				event.button_index = button_index
				event.position = pos
				event.global_position = pos
				event.pressed = false
				Input.parse_input_event(event)
			elif action == "release":
				event.pressed = false
				Input.parse_input_event(event)
				
		"mouse_motion":
			var pos = Vector2(data.get("x", 0), data.get("y", 0))
			var rel = Vector2(data.get("relative_x", 0), data.get("relative_y", 0))
			
			var event = InputEventMouseMotion.new()
			event.position = pos
			event.global_position = pos
			event.relative = rel
			Input.parse_input_event(event)

		"joy_button":
			var device = data.get("device", 0)
			var button = data.get("button", 0)
			
			var event = InputEventJoypadButton.new()
			event.device = device
			event.button_index = button
			
			if action == "press" or action == "click":
				event.pressed = true
				Input.parse_input_event(event)
				
			if action == "click":
				await get_tree().process_frame
				event = InputEventJoypadButton.new()
				event.device = device
				event.button_index = button
				event.pressed = false
				Input.parse_input_event(event)
			elif action == "release":
				event.pressed = false
				Input.parse_input_event(event)

		"joy_motion":
			var device = data.get("device", 0)
			var axis = data.get("axis", 0)
			var value = data.get("value", 0.0)
			
			var event = InputEventJoypadMotion.new()
			event.device = device
			event.axis = axis
			event.axis_value = value
			Input.parse_input_event(event)

func _get_mouse_button_index(button_name: String) -> int:
	match button_name.to_lower():
		"left": return MOUSE_BUTTON_LEFT
		"right": return MOUSE_BUTTON_RIGHT
		"middle": return MOUSE_BUTTON_MIDDLE
		"wheel_up": return MOUSE_BUTTON_WHEEL_UP
		"wheel_down": return MOUSE_BUTTON_WHEEL_DOWN
		"wheel_left": return MOUSE_BUTTON_WHEEL_LEFT
		"wheel_right": return MOUSE_BUTTON_WHEEL_RIGHT
		"xbutton1": return MOUSE_BUTTON_XBUTTON1
		"xbutton2": return MOUSE_BUTTON_XBUTTON2
	return MOUSE_BUTTON_LEFT

func _parse_json(content: String) -> Variant:
	if content.is_empty():
		return {}
	var json = JSON.new()
	if json.parse(content) == OK:
		return json.data
	return {}

func _write_meta(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
