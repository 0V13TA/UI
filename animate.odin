package UI

import "core:hash"

Anim_Target :: union {
	string,
	Class,
	Box_ID,
}

Anim_Props :: struct {
	duration, delay: f32,
	ease:            Easing,
	stagger:         f32,

	// Target Properties
	width, height:   Maybe(f32),
	opacity:         Maybe(f32),
	x, y:            Maybe(f32),
	bg_color:        Maybe([4]f32),
	text_color:      Maybe([4]f32),
	border_color:    Maybe([4]f32),
}

// --- TIMELINE ORCHESTRATION ---

Timeline_Step :: struct {
	is_from: bool,
	target:  Anim_Target,
	props:   Anim_Props,
	pos:     TL_Pos,
	offset:  f32,
}

Timeline :: struct {
	ctx:      ^UI_Context,
	anim_ctx: ^Context,
	steps:    [dynamic]Timeline_Step,
}

TL_Pos :: enum {
	SEQUENCE,
	WITH_PREV,
	ABSOLUTE,
}

timeline :: proc(ctx: ^UI_Context, anim_ctx: ^Context) -> Timeline {
	return Timeline{ctx = ctx, anim_ctx = anim_ctx}
}

tl_to :: proc(
	tl: ^Timeline,
	target: Anim_Target,
	props: Anim_Props,
	pos := TL_Pos.SEQUENCE,
	offset: f32 = 0.0,
) {
	append(
		&tl.steps,
		Timeline_Step{is_from = false, target = target, props = props, pos = pos, offset = offset},
	)
}

tl_from :: proc(
	tl: ^Timeline,
	target: Anim_Target,
	props: Anim_Props,
	pos := TL_Pos.SEQUENCE,
	offset: f32 = 0.0,
) {
	append(
		&tl.steps,
		Timeline_Step{is_from = true, target = target, props = props, pos = pos, offset = offset},
	)
}

tl_play :: proc(tl: ^Timeline) {
	cursor: f32 = 0.0
	last_start_time: f32 = 0.0

	for step in tl.steps {
		start_time: f32 = 0.0
		switch step.pos {
		case .SEQUENCE:
			start_time = cursor + step.offset
		case .WITH_PREV:
			start_time = last_start_time + step.offset
		case .ABSOLUTE:
			start_time = step.offset
		}

		boxes := _resolve_targets(tl.ctx, step.target)
		count := len(boxes)

		if count > 0 {
			total_duration := step.props.duration + (step.props.stagger * f32(count - 1))
			adjusted_props := step.props
			adjusted_props.delay += start_time

			if step.is_from {
				from(tl.ctx, tl.anim_ctx, step.target, adjusted_props)
			} else {
				to(tl.ctx, tl.anim_ctx, step.target, adjusted_props)
			}

			last_start_time = start_time
			cursor = max(cursor, start_time + total_duration)
		}
	}

	delete(tl.steps)
}

to :: proc(ctx: ^UI_Context, anim_ctx: ^Context, target: Anim_Target, props: Anim_Props) {
	boxes := _resolve_targets(ctx, target)
	for box, i in boxes {
		state := get_state(anim_ctx, box.id)

		// 1. Read Current Frame, fallback to History, fallback to 0
		if !state.has_width {
			if w, ok := box.width.(Fixed); ok do state.width = w.value
			else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.width = prev.computed_width
		}
		if !state.has_height {
			if h, ok := box.height.(Fixed); ok do state.height = h.value
			else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.height = prev.computed_height
		}
		if !state.has_x {
			if l, ok := box.left.?; ok do state.x = l
			else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.x = prev.left.? or_else 0.0
			else do state.x = 0.0
		}
		if !state.has_y {
			if t, ok := box.top.?; ok do state.y = t
			else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.y = prev.top.? or_else 0.0
			else do state.y = 0.0
		}

		calculated_delay := props.delay + (props.stagger * f32(i))
		tweens := make([dynamic]Property_Tween, context.temp_allocator)

		if v, ok := props.width.?; ok {
			state.has_width = true
			append(
				&tweens,
				Property_Tween{target = &state.width, to = v, clear_flag = &state.has_width},
			)
		}
		if v, ok := props.height.?; ok {
			state.has_height = true
			append(
				&tweens,
				Property_Tween{target = &state.height, to = v, clear_flag = &state.has_height},
			)
		}
		if v, ok := props.opacity.?; ok {
			append(&tweens, Property_Tween{target = &state.opacity, to = v})
		}
		if v, ok := props.x.?; ok {
			state.has_x = true
			append(&tweens, Property_Tween{target = &state.x, to = v, clear_flag = &state.has_x})
		}
		if v, ok := props.y.?; ok {
			state.has_y = true
			append(&tweens, Property_Tween{target = &state.y, to = v, clear_flag = &state.has_y})
		}

		if v, ok := props.bg_color.?; ok {
			if !state.has_bg_color && box.user_data != nil {
				el := (^Element)(box.user_data)
				c := el.style.bg_color.? or_else Color{0, 0, 0, 0}
				state.bg_color = transmute([4]f32)c
			}
			state.has_bg_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.bg_color,
					to_color = v,
					clear_flag = &state.has_bg_color,
				},
			)
		}
		if v, ok := props.text_color.?; ok {
			if !state.has_text_color && box.user_data != nil {
				el := (^Element)(box.user_data)
				c := el.style.text_color.? or_else Color{0, 0, 0, 1}
				state.text_color = transmute([4]f32)c
			}
			state.has_text_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.text_color,
					to_color = v,
					clear_flag = &state.has_text_color,
				},
			)
		}
		if v, ok := props.border_color.?; ok {
			if !state.has_border_color && box.user_data != nil {
				el := (^Element)(box.user_data)
				c := el.style.border_color.? or_else Color{0, 0, 0, 0}
				state.border_color = transmute([4]f32)c
			}
			state.has_border_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.border_color,
					to_color = v,
					clear_flag = &state.has_border_color,
				},
			)
		}

		safe_ease := props.ease
		if safe_ease == nil do safe_ease = ease_linear

		tween_to(
			&anim_ctx.engine,
			Tween_Vars {
				duration = props.duration,
				delay = calculated_delay,
				ease_func = safe_ease,
				properties = tweens[:],
			},
		)
	}
}

from :: proc(ctx: ^UI_Context, anim_ctx: ^Context, target: Anim_Target, props: Anim_Props) {
	boxes := _resolve_targets(ctx, target)
	for box, i in boxes {
		state := get_state(anim_ctx, box.id)

		// A 'from' tween ALWAYS targets the true layout position.
		// We forcefully reset the state here to erase interrupted mid-tween coordinates.
		if w, ok := box.width.(Fixed); ok do state.width = w.value
		else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.width = prev.computed_width

		if h, ok := box.height.(Fixed); ok do state.height = h.value
		else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.height = prev.computed_height

		if l, ok := box.left.?; ok do state.x = l
		else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.x = prev.left.? or_else 0.0
		else do state.x = 0.0

		if t, ok := box.top.?; ok do state.y = t
		else if prev, ok := ctx.layout.prev_all_boxes[box.id]; ok do state.y = prev.top.? or_else 0.0
		else do state.y = 0.0

		if box.user_data != nil {
			el := (^Element)(box.user_data)
			if props.bg_color != nil do state.bg_color = transmute([4]f32)(el.style.bg_color.? or_else Color{0, 0, 0, 0})
			if props.text_color != nil do state.text_color = transmute([4]f32)(el.style.text_color.? or_else Color{0, 0, 0, 1})
			if props.border_color != nil do state.border_color = transmute([4]f32)(el.style.border_color.? or_else Color{0, 0, 0, 0})
		}

		calculated_delay := props.delay + (props.stagger * f32(i))
		tweens := make([dynamic]Property_Tween, context.temp_allocator)

		if v, ok := props.width.?; ok {
			state.has_width = true
			append(
				&tweens,
				Property_Tween{target = &state.width, from = v, clear_flag = &state.has_width},
			)
		}
		if v, ok := props.height.?; ok {
			state.has_height = true
			append(
				&tweens,
				Property_Tween{target = &state.height, from = v, clear_flag = &state.has_height},
			)
		}
		if v, ok := props.opacity.?; ok {
			append(&tweens, Property_Tween{target = &state.opacity, from = v})
		}
		if v, ok := props.x.?; ok {
			state.has_x = true
			append(&tweens, Property_Tween{target = &state.x, from = v, clear_flag = &state.has_x})
		}
		if v, ok := props.y.?; ok {
			state.has_y = true
			append(&tweens, Property_Tween{target = &state.y, from = v, clear_flag = &state.has_y})
		}

		if v, ok := props.bg_color.?; ok {
			state.has_bg_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.bg_color,
					from_color = v,
					clear_flag = &state.has_bg_color,
				},
			)
		}
		if v, ok := props.text_color.?; ok {
			state.has_text_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.text_color,
					from_color = v,
					clear_flag = &state.has_text_color,
				},
			)
		}
		if v, ok := props.border_color.?; ok {
			state.has_border_color = true
			append(
				&tweens,
				Property_Tween {
					target = &state.border_color,
					from_color = v,
					clear_flag = &state.has_border_color,
				},
			)
		}

		safe_ease := props.ease
		if safe_ease == nil do safe_ease = ease_linear

		tween_from(
			&anim_ctx.engine,
			Tween_Vars {
				duration = props.duration,
				delay = calculated_delay,
				ease_func = safe_ease,
				properties = tweens[:],
			},
		)
	}
}

@(private = "file")
_resolve_targets :: proc(ctx: ^UI_Context, target: Anim_Target) -> [dynamic]^Box {
	results := make([dynamic]^Box, context.temp_allocator)

	switch t in target {
	case string:
		id := Box_ID(hash.fnv32(transmute([]byte)t))
		if box, ok := ctx.layout.all_boxes[id]; ok {
			append(&results, box)
		}
	case Class:
		for root in ctx.layout.root_boxes {
			_collect_by_class(root, t, &results)
		}
	case Box_ID:
		// NEW: Instantly resolve Box ID via the hashmap instead of recursing
		if box, ok := ctx.layout.all_boxes[t]; ok {
			append(&results, box)
		}
	}
	return results
}

@(private = "file")
_collect_by_class :: proc(box: ^Box, target: Class, results: ^[dynamic]^Box) {
	if box == nil do return

	if el := (^Element)(box.user_data); el != nil {
		for cls in el.classes {
			if cls == target {
				append(results, box)
				break
			}
		}
	}

	for child in box.children {
		_collect_by_class(child, target, results)
	}
}

@(private = "file")
_collect_by_id :: proc(box: ^Box, target: Box_ID, results: ^[dynamic]^Box) {
	if box == nil do return

	if box.id == target {
		append(results, box)
		return
	}

	for child in box.children {
		_collect_by_id(child, target, results)
	}
}
