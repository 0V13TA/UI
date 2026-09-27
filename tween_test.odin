package UI

import "core:math"
import "core:testing"

@(test)
test_cubic_bezier_easing_matches_css_curve :: proc(t: ^testing.T) {
	engine := Engine{tweens = make([dynamic]Tween, context.temp_allocator)}
	value: f32 = 0
	append(
		&engine.tweens,
		Tween {
			target = &value,
			from = 0,
			to = 1,
			duration = 1,
			easing = css_ease,
		},
	)
	update(&engine, 0.5)
	progress := value
	testing.expect(t, math.abs(progress - 0.8024) < 0.001)
}

@(test)
test_delayed_tween_consumes_frame_time_after_delay :: proc(t: ^testing.T) {
	engine := Engine{tweens = make([dynamic]Tween, context.temp_allocator)}
	value: f32 = 0
	props := make([dynamic]Property_Tween, context.temp_allocator)
	append(&props, Property_Tween{target = &value, to = 10})

	tween_to(
		&engine,
		Tween_Vars{duration = 1, delay = 0.25, ease_func = ease_linear, properties = props[:]},
	)
	update(&engine, 0.5)

	testing.expect(t, math.abs(value - 2.5) < 0.001)
	testing.expect_value(t, len(engine.tweens), 1)
}

@(test)
test_replacing_tween_cancels_old_override :: proc(t: ^testing.T) {
	engine := Engine{tweens = make([dynamic]Tween, context.temp_allocator)}
	value: f32 = 0
	has_override := true
	first := make([dynamic]Property_Tween, context.temp_allocator)
	append(&first, Property_Tween{target = &value, to = 10, clear_flag = &has_override})
	tween_to(
		&engine,
		Tween_Vars{duration = 10, ease_func = ease_linear, properties = first[:]},
	)
	update(&engine, 1)

	second := make([dynamic]Property_Tween, context.temp_allocator)
	append(&second, Property_Tween{target = &value, to = 20, clear_flag = &has_override})
	tween_to(
		&engine,
		Tween_Vars{duration = 2, ease_func = ease_linear, properties = second[:]},
	)
	testing.expect_value(t, len(engine.tweens), 1)
	testing.expect(t, has_override)

	update(&engine, 1)
	testing.expect(t, math.abs(value - 10.5) < 0.001)
	testing.expect(t, has_override)
	update(&engine, 1)
	testing.expect_value(t, value, 20.0)
	testing.expect(t, !has_override)
	testing.expect_value(t, len(engine.tweens), 0)
}

@(test)
test_zero_duration_tween_finishes_immediately :: proc(t: ^testing.T) {
	engine := Engine{tweens = make([dynamic]Tween, context.temp_allocator)}
	value: f32 = 0
	props := make([dynamic]Property_Tween, context.temp_allocator)
	append(&props, Property_Tween{target = &value, to = 8})

	tween_to(
		&engine,
		Tween_Vars{duration = 0, ease_func = ease_linear, properties = props[:]},
	)
	update(&engine, 0)

	testing.expect_value(t, value, 8.0)
	testing.expect_value(t, len(engine.tweens), 0)
}

@(test)
test_removed_animation_state_cancels_targeting_tweens :: proc(t: ^testing.T) {
	id := Box_ID(40)
	state := new(Retained_State)
	state.id = id
	state.has_x = true
	ctx := Context {
		engine = {tweens = make([dynamic]Tween, context.temp_allocator)},
		states = make(map[Box_ID]^Retained_State, context.temp_allocator),
	}
	layout := new(Layout_Context, context.temp_allocator)
	layout.all_boxes = make(map[Box_ID]^Box, context.temp_allocator)
	ctx.states[id] = state

	props := make([dynamic]Property_Tween, context.temp_allocator)
	append(&props, Property_Tween{target = &state.x, to = 100, clear_flag = &state.has_x})
	tween_to(
		&ctx.engine,
		Tween_Vars{duration = 1, ease_func = ease_linear, properties = props[:]},
	)

	process_lifecycles(&ctx, layout)

	testing.expect_value(t, len(ctx.engine.tweens), 0)
	testing.expect(t, id not_in ctx.states)
	delete(ctx.states)
	delete(layout.all_boxes)
}
