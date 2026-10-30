class_name InputRouter
extends Node

signal controller_state_changed(connected: bool)
signal touch_edit_changed(enabled: bool)

var touch_edit_mode := false
var controller_connected := false
var diagonal_enabled := true
var auto_run_enabled := false
# Godot reports physical face-button positions in Xbox order.
var button_layout := 1
const FACE_SWAP := {JOY_BUTTON_A:JOY_BUTTON_B, JOY_BUTTON_B:JOY_BUTTON_A, JOY_BUTTON_X:JOY_BUTTON_Y, JOY_BUTTON_Y:JOY_BUTTON_X}
## Desktop keys (POKEWILDS-BUTTON-MAP.md has the layout and why). The original
## PokeWilds keys stay: arrows, Z = A, X = B and hold to run, Enter = Start.
## The first key of each is the one button hints name, so Z and X keep the
## A and B hints the same width. OPTIONS > CONTROLS can change the first key.
const KEYS := {
    "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
    "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
    "confirm": [KEY_Z, KEY_SPACE], "cancel": [KEY_X, KEY_Q], "run": [KEY_SHIFT, KEY_X],
    "start": [KEY_ENTER, KEY_TAB, KEY_KP_ENTER], "quit_menu": [KEY_ESCAPE],
    "shoulder_left": [KEY_C], "shoulder_right": [KEY_V],
    "field_move_wheel": [KEY_F], "ball_mechanics": [KEY_R],
    # Battle and field never share a screen, so R throws a ball in both.
    "battle_catch": [KEY_R], "pokedex": [KEY_P], "map_open": [KEY_M], "build_menu": [KEY_B],
    "zoom_in": [KEY_EQUAL, KEY_KP_ADD], "zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
}
## Controller buttons, in Xbox positions (set_button_layout swaps the faces).
## Sticks and triggers are axes, set in _install_default_actions.
const PADS := {
    "confirm": [JOY_BUTTON_A], "cancel": [JOY_BUTTON_B], "run": [JOY_BUTTON_X], "pokedex": [JOY_BUTTON_Y],
    "start": [JOY_BUTTON_START], "map_open": [JOY_BUTTON_BACK],
    # The bumpers page menus and wheels, and zoom the field and the map.
    "shoulder_left": [JOY_BUTTON_LEFT_SHOULDER], "zoom_out": [JOY_BUTTON_LEFT_SHOULDER],
    "shoulder_right": [JOY_BUTTON_RIGHT_SHOULDER], "zoom_in": [JOY_BUTTON_RIGHT_SHOULDER],
    "move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
    "move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
}

## A controller or a hardware keyboard is what the player uses now (a phone
## hides its on-screen buttons for it); a touch makes it false again.
signal physical_input_changed(active: bool)
var physical_input := false
## A real keyboard was used (not the phone's on-screen one): OPTIONS > CONTROLS lists keys.
var keyboard_seen := false

## The one platform switch. A phone (or a computer started with --touch-ui,
## for the tests) gets the touch UI; a computer gets keyboard and mouse, and
## never the touch UI, whatever its screen. Both take controllers. A
## touchscreen laptop counts as a computer: its taps arrive as mouse clicks.
static func touch_runtime() -> bool:
    return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch-ui")

func _ready() -> void:
    _install_default_actions()
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    controller_connected = Input.get_connected_joypads().size() > 0
    physical_input = controller_connected
    keyboard_seen = not touch_runtime()

## The on-screen pad sends real joypad events (one event keeps dual bindings);
## this tag tells them from a physical controller's.
static func virtual(event: InputEvent) -> InputEvent:
    event.set_meta(&"touch_pad", true)
    return event

## main._input passes every event here first (before any menu marks it handled).
func observe(event: InputEvent) -> void:
    if event.has_meta(&"touch_pad"): return
    if event is InputEventScreenTouch and event.pressed: _set_physical(false)
    elif (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5): _set_physical(true)
    elif event is InputEventKey and event.pressed and not event.echo and _game_key(event):
        # The phone's own keyboard (typing a name) is not a hardware keyboard.
        if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0: return
        keyboard_seen = true
        _set_physical(true)
        # Desktop: F11 switches between a window and full screen.
        if event.physical_keycode == KEY_F11 and not touch_runtime():
            var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

static func _game_key(event: InputEventKey) -> bool:
    if event.physical_keycode == KEY_F11: return true
    for action in KEYS:
        if InputMap.event_is_action(event, action): return true
    return false

func _set_physical(active: bool) -> void:
    if active == physical_input: return
    physical_input = active
    physical_input_changed.emit(active)

func _install_default_actions() -> void:
    _ensure_action("field_move_wheel", 0.20)
    for action in KEYS: set_codes(action, KEYS[action])
    _ensure_action("touch_config")
    # Holding the right mouse button opens the field-move wheel too: aim with the mouse, release to use.
    _ensure_mouse_button_action("field_move_wheel", MOUSE_BUTTON_RIGHT)
    _ensure_mouse_button_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
    _ensure_mouse_button_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

    # Remove every old assignment for the controls whose jobs are exact. This
    # prevents saved/project mappings from making Select act like Android Back
    # or leaving old shoulder/trigger jobs active beside the requested ones.
    _remove_joy_button_from_all(JOY_BUTTON_Y)
    _remove_joy_button_from_all(JOY_BUTTON_BACK)
    _remove_joy_button_from_all(JOY_BUTTON_LEFT_SHOULDER)
    _remove_joy_button_from_all(JOY_BUTTON_RIGHT_SHOULDER)
    _remove_joy_axis_from_all(JOY_AXIS_TRIGGER_LEFT)
    _remove_joy_axis_from_all(JOY_AXIS_TRIGGER_RIGHT)

    # Standard Android/Godot controller mapping. Android system Back is not an
    # InputMap button; main.gd handles its window notification independently.
    for action in PADS: set_codes(action, PADS[action], true)
    # L2 retains the field/build wheel. The optional ball system owns R2.
    _ensure_joy_axis("field_move_wheel", JOY_AXIS_TRIGGER_LEFT, 1.0)
    _ensure_joy_axis("ball_mechanics", JOY_AXIS_TRIGGER_RIGHT, 1.0)
    _ensure_joy_axis("move_left", 0, -1.0)
    _ensure_joy_axis("move_right", 0, 1.0)
    _ensure_joy_axis("move_up", 1, -1.0)
    _ensure_joy_axis("move_down", 1, 1.0)
    _ensure_joy_axis("map_pan_left", JOY_AXIS_RIGHT_X, -1.0)
    _ensure_joy_axis("map_pan_right", JOY_AXIS_RIGHT_X, 1.0)
    _ensure_joy_axis("map_pan_up", JOY_AXIS_RIGHT_Y, -1.0)
    _ensure_joy_axis("map_pan_down", JOY_AXIS_RIGHT_Y, 1.0)

func set_button_layout(layout: int) -> void:
    layout = clampi(layout, 0, 1)
    if layout == button_layout: return
    # Change only face-button events, retaining keys, axes, device filters and
    # all Start/Select/shoulder bindings. Clear held actions before remapping.
    for action in InputMap.get_actions():
        var replacements: Array = []
        for event in InputMap.action_get_events(action):
            if event is InputEventJoypadButton and FACE_SWAP.has(event.button_index):
                Input.action_release(action)
                var replacement: InputEventJoypadButton = event.duplicate()
                replacement.button_index = FACE_SWAP[event.button_index]
                replacements.append([event, replacement])
        for pair in replacements: InputMap.action_erase_event(action, pair[0])
        for pair in replacements: InputMap.action_add_event(action, pair[1])
    button_layout = layout

func face_button_name(button: int) -> String:
    var names := ["B", "A", "Y", "X"] if button_layout == 0 else ["A", "B", "X", "Y"]
    return names[button] if button >= 0 and button < names.size() else ""

func _ensure_action(action: StringName, deadzone := 0.35) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action, deadzone)

func _ensure_key_action(action: StringName, keycode: Key) -> void:
    _ensure_action(action)
    var ev := InputEventKey.new()
    ev.physical_keycode = keycode
    InputMap.action_add_event(action, ev)

func _ensure_joy_button(action: StringName, button_index: int) -> void:
    _ensure_action(action)
    var ev := InputEventJoypadButton.new()
    ev.button_index = button_index
    InputMap.action_add_event(action, ev)

func _ensure_joy_axis(action: StringName, axis: int, value: float) -> void:
    _ensure_action(action)
    var ev := InputEventJoypadMotion.new()
    ev.axis = axis
    ev.axis_value = value
    InputMap.action_add_event(action, ev)

func _remove_joy_button_from_all(button_index: int) -> void:
    for action in InputMap.get_actions():
        for event in InputMap.action_get_events(action):
            if event is InputEventJoypadButton and \
                    (event as InputEventJoypadButton).button_index == button_index:
                InputMap.action_erase_event(action, event)

func _remove_joy_axis_from_all(axis_index: int) -> void:
    for action in InputMap.get_actions():
        for event in InputMap.action_get_events(action):
            if event is InputEventJoypadMotion and \
                    (event as InputEventJoypadMotion).axis == axis_index:
                InputMap.action_erase_event(action, event)

func _ensure_mouse_button_action(
        action: StringName,
        button_index: MouseButton
    ) -> void:
    _ensure_action(action)
    var ev := InputEventMouseButton.new()
    ev.button_index = button_index
    InputMap.action_add_event(action, ev)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
    controller_connected = Input.get_connected_joypads().size() > 0
    controller_state_changed.emit(controller_connected)
    _set_physical(controller_connected)

func set_touch_edit(enabled: bool) -> void:
    if touch_edit_mode == enabled:
        return
    touch_edit_mode = enabled
    touch_edit_changed.emit(enabled)

func toggle_touch_edit() -> void:
    set_touch_edit(not touch_edit_mode)

func movement_vector() -> Vector2:
    # Gameplay only: leave the shared menu InputMap bindings untouched.
    var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down").normalized()
    if movement == Vector2.ZERO or _typing():
        return Vector2.ZERO
    for device in _movement_devices():
        var dpad := Vector2(
            int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
            int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)) - int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP)))
        if dpad != Vector2.ZERO:
            return cardinal_dpad_vector(dpad)
    return movement if diagonal_enabled else cardinal_dpad_vector(movement)

func _movement_devices() -> PackedInt32Array:
    return Input.get_connected_joypads()

static func cardinal_dpad_vector(direction: Vector2) -> Vector2:
    if maxf(absf(direction.x), absf(direction.y)) <= 0.30:
        return Vector2.ZERO
    if absf(direction.x) > absf(direction.y):
        return Vector2(signf(direction.x), 0.0)
    return Vector2(0.0, signf(direction.y))

## Keys typed into a text box must not walk the player: the sign editor is a
## window of its own and leaves gameplay on.
func _typing() -> bool:
    for viewport in [get_viewport()] + Array(get_viewport().get_embedded_subwindows()):
        var focus: Control = viewport.gui_get_focus_owner()
        if focus is LineEdit or focus is TextEdit: return true
    return false

## Rebinding (OPTIONS > CONTROLS). `pad` picks controller buttons, else keys.
## The codes bound to an action, first one first.
static func key_codes(action: StringName, pad := false) -> Array:
    var codes := []
    for event in InputMap.action_get_events(action):
        if pad and event is InputEventJoypadButton: codes.append(event.button_index)
        elif not pad and event is InputEventKey: codes.append(event.physical_keycode if event.physical_keycode else event.keycode)
    return codes

func set_codes(action: StringName, codes: Array, pad := false) -> void:
    _ensure_action(action)
    for event in InputMap.action_get_events(action):
        if (event is InputEventJoypadButton) if pad else (event is InputEventKey): InputMap.action_erase_event(action, event)
    for code in codes:
        if pad: _ensure_joy_button(action, code)
        else: _ensure_key_action(action, code)

## The new key or button becomes the action's first (its others, like the
## arrows, stay) and leaves every other action: one key, one job. Two actions
## that share one by default (X: back and run, R: throw in the field and in
## battle, a bumper: page and zoom) keep sharing it.
func bind(action: StringName, code: int, pad := false) -> void:
    var defaults: Dictionary = PADS if pad else KEYS
    var plain := _as_layout(code) if pad else code
    for other in KEYS:
        var held := key_codes(other, pad)
        if other != action and code in held and not (plain in defaults.get(other, []) and plain in defaults.get(action, [])):
            held.erase(code)
            set_codes(other, held, pad)
    var codes := key_codes(action, pad)
    codes.erase(code)
    if codes.is_empty(): codes.append(code)
    else: codes[0] = code
    set_codes(action, codes, pad)

## A face button in the Xbox positions PADS and game.ini use, or back: TYPE 1
## (Nintendo) swaps the faces in the InputMap (set_button_layout).
func _as_layout(button: int) -> int:
    return FACE_SWAP.get(button, button) if button_layout == 0 else button

## Every action's keys or buttons, as game.ini keeps them ([keys] / [pad]).
func bindings(pad := false) -> Dictionary:
    var result := {}
    for action in KEYS: result[action] = key_codes(action, pad).map(func(code): return _as_layout(code) if pad else code)
    return result

## game.ini's bindings over the defaults; a damaged entry keeps its default.
## An empty dictionary is RESET.
func load_bindings(saved: Dictionary, pad := false) -> void:
    var defaults: Dictionary = PADS if pad else KEYS
    for action in KEYS:
        var codes = saved.get(action, defaults.get(action, []))
        if not (codes is Array and codes.all(func(code): return typeof(code) == TYPE_INT and code >= 0)): codes = defaults.get(action, [])
        set_codes(action, codes.map(func(code): return _as_layout(code) if pad else code), pad)

## Button hints name the keys on a computer played without a controller:
## "A: SELECT" reads "Z: SELECT", "L / R" reads "C / V". Only hint text is
## passed in, so a lone A, B, L or R is always a button.
static var _hint_tokens: RegEx
static func hint(text: String) -> String:
    if touch_runtime() or not Input.get_connected_joypads().is_empty(): return text
    if _hint_tokens == null: _hint_tokens = RegEx.create_from_string("DPAD/STICK|R STICK|(?<![\\w'])[ABLR](?![\\w'])")
    var out := ""
    var at := 0
    for found in _hint_tokens.search_all(text):
        var token := found.get_string()
        var keys := ""
        if token == "DPAD/STICK":
            for action in ["move_up", "move_left", "move_down", "move_right"]: keys += key_name(action)
        elif token == "R STICK": keys = "DRAG"
        else: keys = key_name({"A": "confirm", "B": "cancel", "L": "shoulder_left", "R": "shoulder_right"}[token])
        out += text.substr(at, found.get_start() - at) + keys
        at = found.get_end()
    return out + text.substr(at)

static func key_name(action: StringName) -> String:
    var keys := key_codes(action)
    return OS.get_keycode_string(keys[0]).to_upper() if not keys.is_empty() else "--"

func is_running() -> bool:
    return auto_run_enabled or Input.is_action_pressed("run")
