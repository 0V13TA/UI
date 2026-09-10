package renderer

import lc "../layout_calc"
import rl "vendor:raylib"

MAX_TOUCHES :: 10

Pointer_State :: struct {
	pos:           rl.Vector2,
	delta:         rl.Vector2, // Tracks swipe speed / drag distance
	scroll:        rl.Vector2, // Tracks hardware scroll wheel
	is_down:       bool,
	pressed:       bool,
	released:      bool,
	touch_count:   i32,
	touches:       [MAX_TOUCHES]rl.Vector2,
	current_state: enum {
		IDLE,
		PRESSED_THIS_FRAME,
		HELD,
		RELEASED_THIS_FRAME,
	},
}

Interaction_State :: struct {
	is_hovered: bool,
	is_active:  bool, // Mouse/Touch is currently held down on this element
	is_focused: bool,

	// Dispatched Events
	clicked:    bool, // Fired the moment the touch/click is released
	pressed:    bool, // Fired the moment the touch/click begins
	released:   bool,
	drag_delta: rl.Vector2, // Available while is_active is true
	scroll:     rl.Vector2, // Available while is_hovered is true
}

get_interaction :: proc(ctx: ^UI_Context, id: lc.Box_ID) -> Interaction_State {
	state: Interaction_State
	state.is_hovered = (ctx.hovered_id == id)
	state.is_active = (ctx.active_id == id)
	state.is_focused = (ctx.focused_id == id)

	if state.is_hovered {
		state.scroll = ctx.pointer.scroll
		if ctx.pointer.pressed do state.pressed = true
	}

	if state.is_active {
		state.drag_delta = ctx.pointer.delta
		if ctx.pointer.released do state.released = true
		if ctx.pointer.released && state.is_hovered do state.clicked = true
	}

	return state
}
