package renderer

import anim "../animations"
import lc "../layout_calc"
import "core:hash"

Anim_Target :: union {
	string,
	Class,
	lc.Box_ID,
}

// The user-friendly GSAP-style payload
Anim_Props :: struct {
	duration, delay: f32,
	ease:            anim.Easing_Fn,
	stagger:         f32,

	// Optional Target Properties
	width, height:   Maybe(f32),
	opacity:         Maybe(f32),
	x, y:            Maybe(f32), // Translates to left/top
}

// --- TIMELINE ORCHESTRATION ---

Timeline_Step :: struct {
	is_from: bool, // Differentiates between 'to' and 'from' tweens
	target:  Anim_Target,
	props:   Anim_Props,
	pos:     TL_Pos,
	offset:  f32,
}

Timeline :: struct {
	ctx:      ^UI_Context,
	anim_ctx: ^anim.Context,
	steps:    [dynamic]Timeline_Step,
}

TL_Pos :: enum {
	SEQUENCE,
	WITH_PREV,
	ABSOLUTE,
}

timeline :: proc(ctx: ^UI_Context, anim_ctx: ^anim.Context) -> Timeline {
	return Timeline{ctx = ctx, anim_ctx = anim_ctx}
}

// 1. Strictly Queue Instructions (No Math Here)
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

// 2. Flush and Execute (Called after ui_end_frame)
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
			// Calculate total block duration including staggers
			total_duration := step.props.duration + (step.props.stagger * f32(count - 1))

			// Adjust delay relative to the timeline
			adjusted_props := step.props
			adjusted_props.delay += start_time

			// Route to the correct base tween function
			if step.is_from {
				from(tl.ctx, tl.anim_ctx, step.target, adjusted_props)
			} else {
				to(tl.ctx, tl.anim_ctx, step.target, adjusted_props)
			}

			last_start_time = start_time
			cursor = max(cursor, start_time + total_duration)
		}
	}

	// Clean up the dynamic array after flushing
	delete(tl.steps)
}

to :: proc(ctx: ^UI_Context, anim_ctx: ^anim.Context, target: Anim_Target, props: Anim_Props) {
	boxes := _resolve_targets(ctx, target)

	for box, i in boxes {
		// 1. Fetch the persistent state that survives frame-to-frame
		state := anim.get_state(anim_ctx, box.id)

		// 2. The Artificial Increment Stagger
		calculated_delay := props.delay + (props.stagger * f32(i))

		tweens := make([dynamic]anim.Property_Tween, context.temp_allocator)

		if v, ok := props.width.?; ok {
			state.has_structural = true
			// 3. Point the blind engine at the persistent state float
			append(&tweens, anim.Property_Tween{target = &state.width, to = v})
		}
		if v, ok := props.opacity.?; ok {
			append(&tweens, anim.Property_Tween{target = &state.opacity, to = v})
		}

		safe_ease := props.ease
		if safe_ease == nil do safe_ease = anim.ease_linear
		anim.to(
			&anim_ctx.engine,
			anim.Tween_Vars {
				duration = props.duration,
				delay = calculated_delay,
				ease_func = safe_ease,
				properties = tweens[:],
			},
		)
	}
}

@(private)
_resolve_targets :: proc(ctx: ^UI_Context, target: Anim_Target) -> [dynamic]^lc.Box {
	results := make([dynamic]^lc.Box, context.temp_allocator)

	switch t in target {
	case string:
		id := lc.Box_ID(hash.fnv32(transmute([]byte)t))
		if box, ok := ctx.layout.all_boxes[id]; ok {
			append(&results, box)
		}
	case Class:
		// Traverse deterministically via the root boxes
		for root in ctx.layout.root_boxes {
			_collect_by_class(root, t, &results)
		}
	case lc.Box_ID:
		// Implement Box ID
		for root in ctx.layout.root_boxes {
			_collect_by_id(root, t, &results)
		}
	}
	return results
}

@(private)
_collect_by_class :: proc(box: ^lc.Box, target: Class, results: ^[dynamic]^lc.Box) {
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

@(private)
_collect_by_id :: proc(box: ^lc.Box, target: lc.Box_ID, results: ^[dynamic]^lc.Box) {
	if box == nil do return

	if box.id == target {
		append(results, box)
		return // Uncomment this early return to optimize if your IDs are strictly unique
	}

	for child in box.children {
		_collect_by_id(child, target, results)
	}
}

// Add this under your existing `to :: proc(...)` in renderer/animate.odin
from :: proc(ctx: ^UI_Context, anim_ctx: ^anim.Context, target: Anim_Target, props: Anim_Props) {
	boxes := _resolve_targets(ctx, target)
	for box, i in boxes {
		state := anim.get_state(anim_ctx, box.id)
		calculated_delay := props.delay + (props.stagger * f32(i))
		tweens := make([dynamic]anim.Property_Tween, context.temp_allocator)

		if v, ok := props.width.?; ok {
			state.has_structural = true
			append(&tweens, anim.Property_Tween{target = &state.width, from = v})
		}
		if v, ok := props.opacity.?; ok {
			append(&tweens, anim.Property_Tween{target = &state.opacity, from = v})
		}

		safe_ease := props.ease
		if safe_ease == nil do safe_ease = anim.ease_linear

		anim.from(
			&anim_ctx.engine,
			anim.Tween_Vars {
				duration = props.duration,
				delay = calculated_delay,
				ease_func = safe_ease,
				properties = tweens[:],
			},
		)
	}
}
