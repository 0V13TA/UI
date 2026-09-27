package UI


Retained_State :: struct {
	id:               Box_ID,
	x:                f32,
	y:                f32,
	width:            f32,
	height:           f32,
	opacity:          f32,
	bg_color:         [4]f32,
	text_color:       [4]f32,
	border_color:     [4]f32,
	has_x:            bool,
	has_y:            bool,
	has_width:        bool,
	has_height:       bool,
	has_bg_color:     bool,
	has_text_color:   bool,
	has_border_color: bool,
}

Context :: struct {
	engine: Engine,
	states: map[Box_ID]^Retained_State,
}

get_state :: proc(ctx: ^Context, id: Box_ID) -> ^Retained_State {
	if s, ok := ctx.states[id]; ok {
		return s
	}
	s := new(Retained_State)
	s.id = id
	s.opacity = 1.0 // Safe default
	ctx.states[id] = s
	return s
}

process_lifecycles :: proc(ctx: ^Context, layout: ^Layout_Context) {
	// Track which IDs need to be purged using the fast temp allocator
	stale_ids := make([dynamic]Box_ID, context.temp_allocator)

	// Identify retained states for boxes that no longer exist in the layout tree
	for id, state in ctx.states {
		if id not_in layout.all_boxes {
			cancel_state_tweens(&ctx.engine, state)
			free(state)
			append(&stale_ids, id)
		}
	}

	// Remove the stale keys from the map
	for id in stale_ids {
		delete_key(&ctx.states, id)
	}
}

@(private = "file")
cancel_state_tweens :: proc(engine: ^Engine, state: ^Retained_State) {
	#reverse for tween, i in engine.tweens {
		uses_state := false
		switch target in tween.target {
		case ^f32:
			uses_state = target == &state.x || target == &state.y ||
			             target == &state.width || target == &state.height ||
			             target == &state.opacity
		case ^[4]f32:
			uses_state = target == &state.bg_color || target == &state.text_color ||
			             target == &state.border_color
		case ^Sizing:
			uses_state = false
		}
		if uses_state do unordered_remove(&engine.tweens, i)
	}
}

apply_structural :: proc(ctx: ^Context, root: ^Box) {
	if root == nil do return

	if state, ok := ctx.states[root.id]; ok {
		if state.has_width do root.width = Fixed{state.width}
		if state.has_height do root.height = Fixed{state.height}

		// NEW: Apply positional overrides for sliding animations
		if state.has_x do root.left = state.x
		if state.has_y do root.top = state.y
	}

	for child in root.children {
		apply_structural(ctx, child)
	}
}

apply_visual :: proc(ctx: ^Context, root: ^Box, apply_fn: proc(_: rawptr, _: ^Retained_State)) {
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
