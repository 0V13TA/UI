package animations

import lc "../layout_calc"

Retained_State :: struct {
	id:             lc.Box_ID,
	has_structural: bool,
	width:          f32,
	height:         f32,
	opacity:        f32,
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
		if state.has_structural {
			root.width = lc.Fixed{state.width}
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
