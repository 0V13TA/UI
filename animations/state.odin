package animations

import lc "../layout_calc"

Retained_State :: struct {
	id:         lc.Box_ID,
	x:          f32,
	y:          f32,
	width:      f32,
	height:     f32,
	opacity:    f32,
	has_x:      bool,
	has_y:      bool,
	has_width:  bool,
	has_height: bool,
}

Context :: struct {
	engine: Engine,
	states: map[lc.Box_ID]^Retained_State,
}

get_state :: proc(ctx: ^Context, id: lc.Box_ID) -> ^Retained_State {
	if s, ok := ctx.states[id]; ok {
		return s
	}
	s := new(Retained_State)
	s.id = id
	s.opacity = 1.0 // Safe default
	ctx.states[id] = s
	return s
}

process_lifecycles :: proc(ctx: ^Context, layout: ^lc.Layout_Context) {
	// Future: Handle mount/unmount animations here
}

apply_structural :: proc(ctx: ^Context, root: ^lc.Box) {
	if root == nil do return

	if state, ok := ctx.states[root.id]; ok {
		if state.has_width {
			root.width = lc.Fixed{state.width}
		}
		if state.has_height {
			root.height = lc.Fixed{state.height}
		}
	}

	for child in root.children {
		apply_structural(ctx, child)
	}
}

apply_visual :: proc(ctx: ^Context, root: ^lc.Box, apply_fn: proc(_: rawptr, _: ^Retained_State)) {
	if root == nil do return
	if state, ok := ctx.states[root.id]; ok {
		if root.user_data != nil {
			apply_fn(root.user_data, state)
		}
	}
	for child in root.children {
		apply_visual(ctx, child, apply_fn)
	}
}
