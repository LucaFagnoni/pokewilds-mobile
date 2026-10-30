# PokeWilds Input Map

One action map serves every device (`scripts/input_router.gd`: `KEYS`, `PADS`).
A computer plays with keyboard and mouse (and a controller); a phone with the
touch controls (and a controller or a hardware keyboard).

| Action | Keyboard | Mouse | Controller | Touch |
|---|---|---|---|---|
| Move / menu cursor | W A S D or arrow keys | | D-pad / left stick | stick |
| Confirm / interact (A) | Z or Space | left click on a row | A | A |
| Back / cancel (B) | X or Q | right click (menus) | B | B |
| Run (hold) | Shift, or hold X | | X | hold B |
| Menu (Start) | Enter or Tab | | Start | menu button |
| Save / quit prompt | Escape | | | Android Back |
| Previous / next (L / R): pages, pockets, materials, paint, dig, teleport, wheel slices | C / V | | LB / RB | L1 / R1 |
| Field-move wheel (hold, aim, release) | hold F, aim with W A S D or C / V | hold right button, aim with the mouse; left click uses a slice | hold LT / L2 | MOSSE |
| Quick CUT / SMASH / HEADBUTT | tap F | | tap LT | tap MOSSE |
| Throw / recall (tap), ball wheel (hold) | R | | RT / R2 | LANCIO |
| Party wheel | F + R | | LT + RT | MOSSE + LANCIO |
| Battle: throw a ball | R | | | |
| Battle: throw the last ball again | P | | Y | button |
| Pokedex | P | | Y | menu |
| Map | M | click the minimap; drag pans the map, click places the cursor | Select / Back | tap the minimap |
| BUILD (open / close) | B | | | field-move wheel |
| Zoom (field and map) | - / = | wheel | LB / RB | pinch |
| Scroll a list | arrows | wheel | D-pad | drag |
| World chat (online) | T | click the chat button | | chat button |
| Full screen (computer) | F11 | | | |
| Change keys / buttons | OPTIONS > CONTROLS | | OPTIONS > CONTROLS | touch layout: OPTIONS > MOVE BUTTONS |

## Why this layout

The original PokeWilds (sheerst/pokewilds) played on arrows, **Z = A**, **X = B
(hold to run)** and **Enter = Start**, with `keyboard-` remapping lines in
`settings.txt`. Those keys all still work, so a player of the original needs
nothing new. Around them:

- **WASD** moves as in most PC games; the arrows stay.
- **Space** confirms and **Q** goes back beside the left hand on WASD; **Shift**
  runs, so X is free to be "back" alone if you prefer.
- **C / V** (already the Godot port's L / R) sit under the left hand for the
  building materials, paint colours, dig choices and menu pages.
- **F** (field) holds the field-move wheel and **R** throws a ball, the two
  triggers side by side above them; R also throws in battle (field and battle
  never share a screen).
- Mnemonic letters for screens: **M**ap, **P**okedex, **B**uild, **T**alk.
- **Escape** opens the save / quit prompt; **Tab** is a second menu key.
- E is left free: the co-op server list uses it for EDIT / SAVE.

One key does one job. The only shared keys are deliberate: X is back and run
(the original's "hold B to run"), R is both throws. Menus and gameplay read the
same actions, so W A S D also move every menu cursor.

## Mouse

A click works wherever a finger tap works on a phone (the game's own rows:
start menu, party, bag, storage, battle commands and moves, options, Pokedex,
yes / no prompts, co-op boxes, the minimap and clock). On the map a click places
the cursor and a drag pans. The wheel scrolls a list, or zooms where there is
no list. The right button goes back in menus; in the field, holding it opens
the field-move wheel: aim with the mouse, release (or left click a slice) to use.
A touchscreen laptop is a computer: keyboard first, and its taps arrive as
mouse clicks.

## Rebinding

OPTIONS > CONTROLS lists every action. On a KEYBOARD row (a computer, or a
phone once a real keyboard was used) or a CONTROLLER row (while one is
connected), A waits for the new key or button; Escape keeps the old one. It
becomes the action's first key (the one hints show); the others, like the
arrows, stay. Taking a key from another action removes it there, except the
pairs that share one by default. RESET puts every key and button back. Saved
in game.ini (`[keys]`, `[pad]`, buttons in Xbox positions), never per world.

## Platform split

`InputRouter.touch_runtime()` is the one switch (`OS.has_feature("mobile")`,
or `--touch-ui` for the tests):

- **Phone only:** on-screen pad and touch layout (OPTIONS > MOVE BUTTONS),
  touch setup screen and start tiles, haptics, A HINT, Android Back. The pad
  hides while a controller or hardware keyboard is in use (HIDE WITH
  CONTROLLER) and comes back on the next touch.
- **Computer only:** keyboard button hints ("Z: SELECT" for "A: SELECT"),
  mouse clicks through the touch surfaces, mouse-aimed wheel, F11 full screen.
  The touch UI never shows.
- **Shared:** the action map, controllers, rebinding, C / V wheel stepping.

The touch scripts and their art ship in every build: the main scene and the
mouse path load them, so export filters cannot drop them.
