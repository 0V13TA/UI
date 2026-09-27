package UI

import "core:math"

Callback_Fn :: proc(target: Box_ID, data: rawptr)
Easing_Fn :: proc(t: f32) -> f32

// --- Easing System ---
Bezier :: distinct [4]f32

Easing :: union {
	Easing_Fn,
	Bezier,
}

// 1. Standard Math Procs
ease_linear :: proc(t: f32) -> f32 {return t}
ease_in_quad :: proc(t: f32) -> f32 {return t * t}
ease_out_quad :: proc(t: f32) -> f32 {return t * (2.0 - t)}
ease_in_out_quad :: proc(t: f32) -> f32 {
	return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
}
ease_in_cubic :: proc(t: f32) -> f32 {return t * t * t}
ease_out_cubic :: proc(t: f32) -> f32 {
	offset := t - 1.0
	return offset * offset * offset + 1.0
}
ease_in_out_cubic :: proc(t: f32) -> f32 {
	if t < 0.5 do return 4.0 * t * t * t
	offset := 2.0 * t - 2.0
	return 0.5 * offset * offset * offset + 1.0
}
ease_in_quart :: proc(t: f32) -> f32 {return t * t * t * t}
ease_out_quart :: proc(t: f32) -> f32 {
	offset := 1.0 - t
	return 1.0 - offset * offset * offset * offset
}
ease_in_out_quart :: proc(t: f32) -> f32 {
	if t < 0.5 do return 8.0 * t * t * t * t
	offset := 1.0 - t
	return 1.0 - 8.0 * offset * offset * offset * offset
}
ease_in_quint :: proc(t: f32) -> f32 {return t * t * t * t * t}
ease_out_quint :: proc(t: f32) -> f32 {
	offset := 1.0 - t
	return 1.0 - offset * offset * offset * offset * offset
}
ease_in_out_quint :: proc(t: f32) -> f32 {
	if t < 0.5 do return 16.0 * t * t * t * t * t
	offset := 1.0 - t
	return 1.0 - 16.0 * offset * offset * offset * offset * offset
}
ease_in_sine :: proc(t: f32) -> f32 {return 1.0 - math.cos(t * math.PI * 0.5)}
ease_out_sine :: proc(t: f32) -> f32 {return math.sin(t * math.PI * 0.5)}
ease_in_out_sine :: proc(t: f32) -> f32 {return -(math.cos(math.PI * t) - 1.0) * 0.5}
ease_in_circ :: proc(t: f32) -> f32 {return 1.0 - math.sqrt(1.0 - t * t)}
ease_out_circ :: proc(t: f32) -> f32 {
	offset := t - 1.0
	return math.sqrt(1.0 - offset * offset)
}
ease_in_out_circ :: proc(t: f32) -> f32 {
	if t < 0.5 do return (1.0 - math.sqrt(1.0 - 4.0 * t * t)) * 0.5
	offset := -2.0 * t + 2.0
	return (math.sqrt(1.0 - offset * offset) + 1.0) * 0.5
}
ease_in_exp :: proc(t: f32) -> f32 {
	return t == 0.0 ? 0.0 : math.pow(2.0, 10.0 * t - 10.0)
}
ease_out_exp :: proc(t: f32) -> f32 {
	return t == 1.0 ? 1.0 : 1.0 - math.pow(2.0, -10.0 * t)
}
ease_in_out_exp :: proc(t: f32) -> f32 {
	if t == 0.0 || t == 1.0 do return t
	if t < 0.5 do return math.pow(2.0, 20.0 * t - 10.0) * 0.5
	return (2.0 - math.pow(2.0, -20.0 * t + 10.0)) * 0.5
}

ease_in_back :: proc(t: f32) -> f32 {
	constant: f32 = 1.70158
	return (constant + 1.0) * t * t * t - constant * t * t
}
ease_out_back :: proc(t: f32) -> f32 {
	constant: f32 = 1.70158
	offset := t - 1.0
	return 1.0 + (constant + 1.0) * offset * offset * offset +
	       constant * offset * offset
}
ease_in_out_back :: proc(t: f32) -> f32 {
	constant: f32 = 1.70158 * 1.525
	if t < 0.5 {
		offset := 2.0 * t
		return offset * offset * ((constant + 1.0) * offset - constant) * 0.5
	}
	offset := 2.0 * t - 2.0
	return (offset * offset * ((constant + 1.0) * offset + constant) + 2.0) * 0.5
}

ease_out_bounce :: proc(t: f32) -> f32 {
	constant: f32 = 7.5625
	divisor: f32 = 2.75
	if t < 1.0 / divisor do return constant * t * t
	if t < 2.0 / divisor {
		offset := t - 1.5 / divisor
		return constant * offset * offset + 0.75
	}
	if t < 2.5 / divisor {
		offset := t - 2.25 / divisor
		return constant * offset * offset + 0.9375
	}
	offset := t - 2.625 / divisor
	return constant * offset * offset + 0.984375
}
ease_in_bounce :: proc(t: f32) -> f32 {return 1.0 - ease_out_bounce(1.0 - t)}
ease_in_out_bounce :: proc(t: f32) -> f32 {
	if t < 0.5 do return (1.0 - ease_out_bounce(1.0 - 2.0 * t)) * 0.5
	return (1.0 + ease_out_bounce(2.0 * t - 1.0)) * 0.5
}

ease_in_elastic :: proc(t: f32) -> f32 {
	if t == 0.0 || t == 1.0 do return t
	period: f32 = 2.0 * f32(math.PI) / 3.0
	return -math.pow(2.0, 10.0 * t - 10.0) *
	       math.sin((10.0 * t - 10.75) * period)
}
ease_out_elastic :: proc(t: f32) -> f32 {
	if t == 0.0 || t == 1.0 do return t
	period: f32 = 2.0 * f32(math.PI) / 3.0
	return math.pow(2.0, -10.0 * t) *
	       math.sin((10.0 * t - 0.75) * period) + 1.0
}
ease_in_out_elastic :: proc(t: f32) -> f32 {
	if t == 0.0 || t == 1.0 do return t
	constant: f32 = 2.0 * f32(math.PI) / 4.5
	if t < 0.5 {
		return -(math.pow(2.0, 20.0 * t - 10.0) *
		         math.sin((20.0 * t - 11.125) * constant)) * 0.5
	}
	return math.pow(2.0, -20.0 * t + 10.0) *
	       math.sin((20.0 * t - 11.125) * constant) * 0.5 + 1.0
}

// 2. Standard CSS Bezier Curves
css_ease :: Bezier{0.25, 0.1, 0.25, 1.0}
css_ease_in :: Bezier{0.42, 0.0, 1.0, 1.0}
css_ease_out :: Bezier{0.0, 0.0, 0.58, 1.0}
css_ease_in_out :: Bezier{0.42, 0.0, 0.58, 1.0}

cubic_bezier :: proc(x1, y1, x2, y2: f32) -> Bezier {
	return Bezier{clamp(x1, 0.0, 1.0), y1, clamp(x2, 0.0, 1.0), y2}
}

// 3. Cubic Bezier Solver
@(private = "file")
_bezier_coord :: proc(p1, p2, t: f32) -> f32 {
	inv_t := 1.0 - t
	return 3.0 * inv_t * inv_t * t * p1 + 3.0 * inv_t * t * t * p2 + t * t * t
}

@(private = "file")
_bezier_derivative :: proc(p1, p2, t: f32) -> f32 {
	inv_t := 1.0 - t
	return 3.0 * inv_t * inv_t * p1 +
	       6.0 * inv_t * t * (p2 - p1) +
	       3.0 * t * t * (1.0 - p2)
}

@(private = "file")
solve_cubic_bezier :: proc(x1, y1, x2, y2, x: f32) -> f32 {
	if x <= 0.0 do return 0.0
	if x >= 1.0 do return 1.0

	curve_x1 := clamp(x1, 0.0, 1.0)
	curve_x2 := clamp(x2, 0.0, 1.0)
	lower: f32 = 0.0
	upper: f32 = 1.0
	t: f32 = x

	for _ in 0 ..< 8 {
		current_x := _bezier_coord(curve_x1, curve_x2, t)
		delta := current_x - x
		if math.abs(delta) < 0.00001 do break
		if current_x < x {
			lower = t
		} else {
			upper = t
		}
		derivative := _bezier_derivative(curve_x1, curve_x2, t)
		candidate := t
		if math.abs(derivative) > 0.00001 do candidate = t - delta / derivative
		if candidate <= lower || candidate >= upper do candidate = (lower + upper) * 0.5
		t = candidate
	}

	for _ in 0 ..< 16 {
		current_x := _bezier_coord(curve_x1, curve_x2, t)
		if math.abs(current_x - x) < 0.00001 do break
		if current_x < x {
			lower = t
		} else {
			upper = t
		}
		t = (lower + upper) * 0.5
	}

	return _bezier_coord(y1, y2, t)
}

Tween_Target :: union {
	^f32,
	^Sizing,
	^[4]f32,
}

Property_Tween :: struct {
	target:               Tween_Target,
	from, to:             f32,
	from_color, to_color: [4]f32,
	clear_flag:           ^bool,
}

Tween_Vars :: struct {
	duration, delay: f32,
	ease_func:       Easing,
	properties:      []Property_Tween,
	on_complete:     Callback_Fn,
}

Tween :: struct {
	delay:                f32,
	elapsed:              f32,
	from, to:             f32,
	from_color, to_color: [4]f32,
	duration:             f32,
	is_from:              bool,
	clear_flag:           ^bool,
	easing:               Easing,
	target:               Tween_Target,
	on_complete:          Callback_Fn,
}

Engine :: struct {
	tweens: [dynamic]Tween,
}

update :: proc(engine: ^Engine, dt: f32) {
	frame_dt := max(dt, 0.0)
	#reverse for &t, i in engine.tweens {
		active_dt := frame_dt
		if t.delay > active_dt {
			t.delay -= active_dt
			if t.is_from {
				switch ptr in t.target {
				case ^f32:
					ptr^ = t.from
				case ^Sizing:
					ptr^ = Fixed{t.from}
				case ^[4]f32:
					ptr^ = t.from_color
				}
			}
			continue
		}

		active_dt = max(active_dt - t.delay, 0.0)
		t.delay = 0.0
		t.elapsed = min(t.elapsed + active_dt, t.duration)

		progress: f32 = 1.0
		if t.duration > 0.0 {
			ratio := t.elapsed / t.duration
			switch e in t.easing {
			case Easing_Fn:
				progress = e(ratio)
			case Bezier:
				progress = solve_cubic_bezier(e[0], e[1], e[2], e[3], ratio)
			}
		}

		switch ptr in t.target {
		case ^f32:
			ptr^ = t.from + (t.to - t.from) * progress
		case ^Sizing:
			ptr^ = Fixed{t.from + (t.to - t.from) * progress}
		case ^[4]f32:
			ptr^[0] = t.from_color[0] + (t.to_color[0] - t.from_color[0]) * progress
			ptr^[1] = t.from_color[1] + (t.to_color[1] - t.from_color[1]) * progress
			ptr^[2] = t.from_color[2] + (t.to_color[2] - t.from_color[2]) * progress
			ptr^[3] = t.from_color[3] + (t.to_color[3] - t.from_color[3]) * progress
		}

		if t.elapsed >= t.duration {
			if t.clear_flag != nil do t.clear_flag^ = false
			if t.on_complete != nil do t.on_complete(0, nil)
			unordered_remove(&engine.tweens, i)
		}
	}
}

@(private = "file")
get_current_f32 :: proc(target: Tween_Target) -> f32 {
	switch ptr in target {
	case ^f32:
		return ptr^
	case ^Sizing:
		#partial switch v in ptr^ {
		case Fixed:
			return v.value
		case Percent:
			return v.value
		case ViewPercent:
			return v.value
		}
	case ^[4]f32:
		return 0.0
	}
	return 0.0
}

tween_to :: proc(engine: ^Engine, vars: Tween_Vars) {
	adjusted_props := make([dynamic]Property_Tween, context.temp_allocator)
	for prop in vars.properties {
		adjusted_prop := prop
		switch ptr in prop.target {
		case ^[4]f32:
			start_val := ptr^
			if start_val == prop.to_color {
				cancel_tween(engine, prop.target)
				if prop.clear_flag != nil do prop.clear_flag^ = false
				continue
			}
			adjusted_prop.from_color = start_val
		case ^f32, ^Sizing:
			start_val := get_current_f32(prop.target)
			if start_val == prop.to {
				cancel_tween(engine, prop.target)
				if prop.clear_flag != nil do prop.clear_flag^ = false
				continue
			}
			adjusted_prop.from = start_val
		}
		append(&adjusted_props, adjusted_prop)
	}
	_register_tweens(engine, adjusted_props[:], vars, false)
}

tween_from :: proc(engine: ^Engine, vars: Tween_Vars) {
	adjusted_props := make([dynamic]Property_Tween, context.temp_allocator)
	for prop in vars.properties {
		adjusted_prop := prop
		switch ptr in prop.target {
		case ^[4]f32:
			end_val := ptr^
			if prop.from_color == end_val {
				cancel_tween(engine, prop.target)
				if prop.clear_flag != nil do prop.clear_flag^ = false
				continue
			}
			adjusted_prop.to_color = end_val
		case ^f32, ^Sizing:
			end_val := get_current_f32(prop.target)
			if prop.from == end_val {
				cancel_tween(engine, prop.target)
				if prop.clear_flag != nil do prop.clear_flag^ = false
				continue
			}
			adjusted_prop.to = end_val
		}
		append(&adjusted_props, adjusted_prop)
	}
	_register_tweens(engine, adjusted_props[:], vars, true)
}

tween_from_to :: proc(engine: ^Engine, vars: Tween_Vars) {
	adjusted_props := make([dynamic]Property_Tween, context.temp_allocator)
	for prop in vars.properties {
		is_noop := false
		switch ptr in prop.target {
		case ^[4]f32:
			is_noop = prop.from_color == prop.to_color
		case ^f32, ^Sizing:
			is_noop = prop.from == prop.to
		}
		if is_noop {
			cancel_tween(engine, prop.target)
			if prop.clear_flag != nil do prop.clear_flag^ = false
			continue
		}
		append(&adjusted_props, prop)
	}
	_register_tweens(engine, adjusted_props[:], vars, true)
}

cancel_tween :: proc(engine: ^Engine, target: Tween_Target) {
	#reverse for tween, i in engine.tweens {
		if tween.target == target {
			if tween.clear_flag != nil do tween.clear_flag^ = false
			unordered_remove(&engine.tweens, i)
		}
	}
}

@(private = "file")
_register_tweens :: proc(
	engine: ^Engine,
	properties: []Property_Tween,
	vars: Tween_Vars,
	is_from: bool,
) {
	if len(properties) == 0 {
		if vars.on_complete != nil do vars.on_complete(0, nil)
		return
	}
	for prop, i in properties {
		scheduled_vars := vars
		if i != 0 do scheduled_vars.on_complete = nil
		_register_tween(engine, prop, scheduled_vars, is_from)
	}
}

@(private = "file")
_register_tween :: proc(
	engine: ^Engine,
	prop: Property_Tween,
	vars: Tween_Vars,
	is_from: bool = false,
) {
	#reverse for &existing, i in engine.tweens {
		if existing.target == prop.target {
			if existing.clear_flag != nil && existing.clear_flag != prop.clear_flag {
				existing.clear_flag^ = false
			}
			unordered_remove(&engine.tweens, i)
		}
	}

	duration := max(vars.duration, 0.0)
	delay := max(vars.delay, 0.0)
	easing := vars.ease_func
	if easing == nil do easing = ease_linear
	append(
		&engine.tweens,
		Tween {
			target = prop.target,
			from = prop.from,
			to = prop.to,
			from_color = prop.from_color,
			to_color = prop.to_color,
			duration = duration,
			delay = delay,
			easing = easing,
			is_from = is_from,
			on_complete = vars.on_complete,
			clear_flag = prop.clear_flag,
		},
	)
}
