# Desktop keyboard and mouse (POKEWILDS-BUTTON-MAP.md): no touch UI, every key
# does its job in a started world, keys never collide, hints name keys, the
# OPTIONS > CONTROLS rebinding saves, and the mouse clicks menu rows and wheel slices.
# Run: godot --headless --path project -s ../server/desktop_keys_test.gd
extends SceneTree

const Paths = preload("res://scripts/game_data_paths.gd")
const GameOptions = preload("res://scripts/game_options.gd")

var main: Node
var checks := 0
var failed := 0

func check(ok: bool, what: String) -> void:
    checks += 1
    if not ok:
        failed += 1
        printerr("DESKTOP KEYS TEST FAIL: ", what)

func _frames(count: int) -> void:
    for i in count: await process_frame

func key(code: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)

func tap_key(code: Key) -> void:
    key(code, true)
    await _frames(2)
    key(code, false)
    await _frames(3)

## A mouse button at a point of the 320x180 canvas, sent as the window sees it.
func mouse(button: MouseButton, pressed: bool, at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = pressed
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
    Input.parse_input_event(event)
    await _frames(2)

func move_mouse(at: Vector2, relative: Vector2, held: bool) -> void:
    var event := InputEventMouseMotion.new()
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    event.relative = root.get_final_transform().basis_xform(relative)
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
    Input.parse_input_event(event)
    await _frames(2)

func click(at: Vector2) -> void:
    await mouse(MOUSE_BUTTON_LEFT, true, at)
    await mouse(MOUSE_BUTTON_LEFT, false, at)

func _initialize() -> void:
    create_timer(400.0).timeout.connect(func(): printerr("DESKTOP KEYS TEST FAIL: timed out"); quit(2))
    var dir := OS.get_temp_dir().path_join("desktop_keys_test_%d" % Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(dir)
    FileAccess.open(dir.path_join(".private-saves-migrated"), FileAccess.WRITE).close()
    Paths.directory = dir
    change_scene_to_file("res://scenes/main.tscn")
    await _frames(30)
    main = current_scene
    while not main.startup_complete: await process_frame

    # No touch UI on a computer.
    check(not main.touch_on(), "the touch UI is off")
    check(not main.touch_controls.android_runtime and not main.touch_controls.visible, "the on-screen pad is hidden")

    # One key, one job: only the pairs the layout shares on purpose.
    var jobs := {}
    for action in InputRouter.KEYS:
        for code in InputRouter.KEYS[action]:
            jobs[code] = jobs.get(code, []) + [action]
            var event := InputEventKey.new()
            event.physical_keycode = code
            check(InputMap.event_is_action(event, action, true), "%s is bound to %s" % [OS.get_keycode_string(code), action])
    for code in jobs:
        var shared: Array = jobs[code]
        check(shared.size() == 1 or (code == KEY_X and shared == ["cancel", "run"]) or (code == KEY_R and shared == ["ball_mechanics", "battle_catch"]),
            "%s does one job: %s" % [OS.get_keycode_string(code), shared])
    for action in ["confirm", "cancel", "start", "quit_menu", "shoulder_left", "shoulder_right", "field_move_wheel", "ball_mechanics", "pokedex", "map_open", "build_menu", "battle_catch", "zoom_in", "zoom_out", "run"]:
        check(not InputRouter.key_codes(action).is_empty(), "%s has a key" % action)

    # Hints name keys.
    check(InputRouter.hint("A: SELECT   B: BACK") == "Z: SELECT   X: BACK", "A/B hints: " + InputRouter.hint("A: SELECT   B: BACK"))
    check(InputRouter.hint("A USE   B BACK   LEFT/RIGHT PAGE") == "Z USE   X BACK   LEFT/RIGHT PAGE", "battle hint: " + InputRouter.hint("A USE   B BACK   LEFT/RIGHT PAGE"))
    check(InputRouter.hint("1 / 3  L / R") == "1 / 3  C / V", "page hint: " + InputRouter.hint("1 / 3  L / R"))
    check(InputRouter.hint("DPAD/STICK: CURSOR  R STICK: PAN\nL/R: ZOOM  Waypoint: A  B: BACK") == "WASD: CURSOR  DRAG: PAN\nC/V: ZOOM  Waypoint: Z  X: BACK", "map hint: " + InputRouter.hint("DPAD/STICK: CURSOR  R STICK: PAN\nL/R: ZOOM  Waypoint: A  B: BACK"))
    check(InputRouter.hint("A: SHOW THIS WORLD'S PASSWORD") == "Z: SHOW THIS WORLD'S PASSWORD", "no stray letters: " + InputRouter.hint("A: SHOW THIS WORLD'S PASSWORD"))

    # A controller works beside the keys; its use is "physical input" (a phone
    # hides its on-screen pad for it), a touch ends it, the on-screen pad's own
    # joypad events do not count.
    var router: InputRouter = main.input_router
    # Xbox positions; BUTTON LAYOUT TYPE 1 (Nintendo, the default) swaps the faces.
    for pair in [[JOY_BUTTON_A, "confirm"], [JOY_BUTTON_B, "cancel"], [JOY_BUTTON_START, "start"], [JOY_BUTTON_BACK, "map_open"], [JOY_BUTTON_X, "run"], [JOY_BUTTON_Y, "pokedex"], [JOY_BUTTON_LEFT_SHOULDER, "shoulder_left"], [JOY_BUTTON_DPAD_UP, "move_up"]]:
        var button := InputEventJoypadButton.new()
        button.button_index = router._as_layout(pair[0])
        button.pressed = true
        check(InputMap.event_is_action(button, pair[1]), "controller button %d is %s" % pair)
    var pad := InputEventJoypadButton.new()
    pad.button_index = JOY_BUTTON_A
    for pressed in [true, false]:
        pad.pressed = pressed
        Input.parse_input_event(pad.duplicate())
    await _frames(2)
    check(router.physical_input, "a controller press is physical input")
    var finger := InputEventScreenTouch.new()
    finger.position = Vector2(-500, -500)
    for pressed in [true, false]:
        finger.pressed = pressed
        Input.parse_input_event(finger.duplicate())
    await _frames(2)
    check(not router.physical_input, "a touch ends it")
    pad.pressed = true
    Input.parse_input_event(InputRouter.virtual(pad.duplicate()))
    pad.pressed = false
    Input.parse_input_event(InputRouter.virtual(pad.duplicate()))
    await _frames(2)
    check(not router.physical_input, "the on-screen pad is not a controller")
    check(not main.touch_controls.visible, "the on-screen pad never shows on a computer")

    main.coop_menu.close()
    await _frames(5)
    main.world_edit.text = "KeysTest"
    main._start_game()
    var waited := 0
    while not main.started and waited < 36000:
        await process_frame
        waited += 1
    check(main.started, "the world started")
    await _frames(90)
    for i in 10:
        if not main._field_ui_blocks_gameplay(): break
        await tap_key(KEY_X)
        await _frames(20)
    check(not main._field_ui_blocks_gameplay() and main.world.gameplay_enabled, "the field is free")

    # WASD walks, Shift runs; typing on a sign walks nowhere.
    key(KEY_W, true)
    await _frames(2)
    check(router.movement_vector() == Vector2.UP, "W walks up: %s" % router.movement_vector())
    main.sign_dialog.popup_centered(Vector2i(260, 104))
    main.sign_edit.grab_focus()
    await _frames(2)
    check(router.movement_vector() == Vector2.ZERO, "typing on a sign walks nowhere")
    main.sign_dialog.hide()
    key(KEY_W, false)
    key(KEY_SHIFT, true)
    await _frames(2)
    check(router.is_running(), "Shift runs")
    key(KEY_SHIFT, false)
    await _frames(5)

    # = zooms in.
    if GameOptions.enabled("zoom"):
        var zoom: float = main.world.camera_zoom_level
        await tap_key(KEY_EQUAL)
        check(main.world.camera_zoom_level != zoom, "= zooms")
        await tap_key(KEY_MINUS)

    # Enter and Tab open the menu, X and Q close it.
    for pair in [[KEY_ENTER, KEY_X], [KEY_TAB, KEY_Q]]:
        await tap_key(pair[0])
        check(main.game_menu_open, "%s opens the menu" % OS.get_keycode_string(pair[0]))
        await tap_key(pair[1])
        await _frames(5)
        check(not main.game_menu_open, "%s closes the menu" % OS.get_keycode_string(pair[1]))

    # A click on OPTIONS in the menu opens it; change a key there.
    await tap_key(KEY_ENTER)
    var option: Control = main.game_menu_box.get_node("Option%d" % main.GAME_MENU_OPTIONS.find("OPTIONS"))
    await click(option.get_global_rect().get_center())
    await _frames(3)
    var options: Control = main.options_menu
    check(options.visible, "clicking OPTIONS opens it")
    options.build_controls()
    options.controls_page = true
    options.control_index = -1
    for i in options.control_rows.size():
        if options.control_rows[i].size() > 4 and options.control_rows[i][3] == "confirm" and options.control_rows[i][4] == "key": options.control_index = i
    check(options.control_index >= 0, "CONTROLS lists the confirm key")
    check(not options.control_rows.any(func(row): return row[0] == "TOUCH"), "a computer lists no touch buttons")
    options.refresh()
    await tap_key(KEY_Z)
    check(options.listening == "confirm", "A on the row waits for a key")
    await tap_key(KEY_C)
    check(InputRouter.key_codes("confirm") == [KEY_C, KEY_SPACE], "C is the new confirm key: %s" % [InputRouter.key_codes("confirm")])
    check(InputRouter.key_codes("shoulder_left").is_empty(), "C left its old job")
    check(GameOptions.saved_bindings("keys").get("confirm", []) == [KEY_C, KEY_SPACE], "game.ini keeps it: %s" % GameOptions.saved_bindings("keys"))
    check(InputRouter.hint("A: OK") == "C: OK", "hints follow the new key")
    router.load_bindings(GameOptions.saved_bindings("keys"))
    check(InputRouter.key_codes("confirm") == [KEY_C, KEY_SPACE], "it loads back")
    await tap_key(KEY_C)
    await tap_key(KEY_ESCAPE)
    check(options.listening == "" and InputRouter.key_codes("confirm") == [KEY_C, KEY_SPACE], "Escape keeps the key")
    # Controller buttons: the same rules (the row shows only with a controller connected).
    var x_button := router._as_layout(JOY_BUTTON_X)
    router.bind("pokedex", x_button, true)
    check(InputRouter.key_codes("pokedex", true) == [x_button] and InputRouter.key_codes("run", true).is_empty(), "X button moved from run to the Pokedex")
    router.bind("zoom_in", JOY_BUTTON_LEFT_SHOULDER, true)
    check(InputRouter.key_codes("zoom_in", true) == [JOY_BUTTON_LEFT_SHOULDER] and InputRouter.key_codes("zoom_out", true).is_empty() and InputRouter.key_codes("shoulder_left", true).is_empty(), "LB left both its old jobs")
    GameOptions.save_bindings("pad", router.bindings(true))
    router.load_bindings({}, true)
    router.load_bindings(GameOptions.saved_bindings("pad"), true)
    check(InputRouter.key_codes("pokedex", true) == [x_button] and GameOptions.saved_bindings("pad").get("pokedex") == [JOY_BUTTON_X], "controller buttons load back, saved in Xbox positions")
    options.control_index = options.control_rows.size() - 1
    check(options.control_rows[options.control_index][3] == "@reset", "the last row resets")
    await tap_key(KEY_SPACE)
    check(InputRouter.key_codes("confirm") == [KEY_Z, KEY_SPACE] and InputRouter.key_codes("shoulder_left") == [KEY_C], "RESET puts the keys back")
    check(InputRouter.key_codes("run", true) == [x_button] and InputRouter.key_codes("zoom_out", true) == [JOY_BUTTON_LEFT_SHOULDER], "RESET puts the buttons back")
    check(GameOptions.saved_bindings("keys").is_empty() and GameOptions.saved_bindings("pad").is_empty(), "RESET clears game.ini's bindings")
    # The right button goes back.
    await mouse(MOUSE_BUTTON_RIGHT, true, Vector2(160, 90))
    await mouse(MOUSE_BUTTON_RIGHT, false, Vector2(160, 90))
    check(not options.controls_page, "right click leaves CONTROLS")
    options.close()
    main._close_game_menu()
    await _frames(10)

    # M opens the map, a drag pans it, M closes it.
    await tap_key(KEY_M)
    check(main.game_menu_open and main.game_menu_map_screen.visible, "M opens the map")
    check("WASD" in String(main.get_node("UI/GameMenu/MapScreen/Hint").text), "the map hint names keys")
    var pan: Vector2 = main.map_pan
    await mouse(MOUSE_BUTTON_LEFT, true, Vector2(160, 90))
    for i in 4: await move_mouse(Vector2(160 + 8 * (i + 1), 90), Vector2(8, 0), true)
    await mouse(MOUSE_BUTTON_LEFT, false, Vector2(192, 90))
    check(main.map_pan != pan, "a mouse drag pans the map")
    await tap_key(KEY_M)
    await _frames(5)
    check(not main.game_menu_open, "M closes the map")

    # P opens and closes the Pokedex.
    await tap_key(KEY_P)
    check(main.pokedex_menu.visible, "P opens the Pokedex")
    await tap_key(KEY_P)
    await _frames(5)
    check(not main.pokedex_menu.visible, "P closes the Pokedex")

    # Hold F: the field-move wheel; V / C step it, the mouse aims and a click uses a slice.
    key(KEY_F, true)
    await _frames(40)
    check(main.field_move_wheel_open, "holding F opens the wheel")
    await tap_key(KEY_V)
    check(main.field_move_wheel_index == 0, "V picks the first slice: %d" % main.field_move_wheel_index)
    await tap_key(KEY_C)
    check(main.field_move_wheel_index == main.field_move_wheel.entries.size() - 1, "C steps back round: %d" % main.field_move_wheel_index)
    var centre: Vector2 = main.field_move_wheel.get_global_rect().get_center()
    await move_mouse(centre + Vector2(0, -60), Vector2(0, -60), false)
    await _frames(2)
    check(main.field_move_wheel_index == 0, "the mouse aims at the top slice: %d" % main.field_move_wheel_index)
    await click(centre + Vector2(0, -60))
    check(not main.field_move_wheel_open, "a click uses the slice and closes the wheel")
    key(KEY_F, false)
    await _frames(10)
    check(not main.field_move_wheel_open and not main.field_wheel_wait_for_release, "letting go of F reopens nothing")
    await _frames(30)
    for i in 10:
        if not main._field_ui_blocks_gameplay(): break
        await tap_key(KEY_X)
        await _frames(20)

    # Holding the right mouse button opens the wheel too.
    await mouse(MOUSE_BUTTON_RIGHT, true, Vector2(160, 90))
    await _frames(40)
    check(main.field_move_wheel_open, "holding the right button opens the wheel")
    await mouse(MOUSE_BUTTON_RIGHT, false, Vector2(160, 90))
    await _frames(10)
    check(not main.field_move_wheel_open, "letting go closes it")

    print("DESKTOP KEYS TEST: %d checks, %d failed" % [checks, failed])
    quit(1 if failed > 0 else 0)
