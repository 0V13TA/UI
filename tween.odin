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
ease_out_exp :: proc(t: f32) -> f32 {return t == 1.0 ? 1.0 : 1.0 - math.pow(2.0, -10.0 * t)}

// 2. Standard CSS Bezier Curves
css_ease :: Bezier{0.25, 0.1, 0.25, 1.0}
css_ease_in :: Bezier{0.42, 0.0, 1.0, 1.0}
css_ease_out :: Bezier{0.0, 0.0, 0.58, 1.0}
css_ease_in_out :: Bezier{0.42, 0.0, 0.58, 1.0}

// 3. Cubic Bezier Solver
@(private)
_bezier_coord :: proc(p1, p2, t: f32) -> f32 {
	inv_t := 1.0 - t
	return 3.0 * inv_t * inv_t * t * p1 + 3.0 * inv_t * t * t * p2 + t * t * t
}

@(private)
solve_cubic_bezier :: proc(x1, y1, x2, y2, x: f32) -> f32 {
	if x <= 0.0 do return 0.0
	if x >= 1.0 do return 1.0

	lower: f32 = 0.0
	upper: f32 = 1.0
	t: f32 = x

	for _ in 0 ..< 15 {
		current_x := _bezier_coord(x1, x2, t)
		if math.abs(current_x - x) < 0.001 do break
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
	done:                 bool,
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
	#reverse for &t, i in engine.tweens {
		if t.done {
			if t.elapsed >= t.duration && t.on_complete != nil {
				t.on_complete(0, nil)
			}
			unordered_remove(&engine.tweens, i)
			continue
		}

		if t.delay > 0.0 {
			t.delay -= dt
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

		t.elapsed = min(t.elapsed + dt, t.duration)

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
			t.done = true
			if t.clear_flag != nil do t.clear_flag^ = false
		}
	}
}

@(private)
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
	for prop in vars.properties {
		adjusted_prop := prop
		switch ptr in prop.target {
		case ^[4]f32:
			start_val := ptr^
			if start_val == prop.to_color do continue
			adjusted_prop.from_color = start_val
		case ^f32, ^Sizing:
			start_val := get_current_f32(prop.target)
			if start_val == prop.to do continue
			adjusted_prop.from = start_val
		}
		_register_tween(engine, adjusted_prop, vars, false)
	}
}

tween_from :: proc(engine: ^Engine, vars: Tween_Vars) {
	for prop in vars.properties {
		adjusted_prop := prop
		switch ptr in prop.target {
		case ^[4]f32:
			end_val := ptr^
			if prop.from_color == end_val do continue
			adjusted_prop.to_color = end_val
		case ^f32, ^Sizing:
			end_val := get_current_f32(prop.target)
			if prop.from == end_val do continue
			adjusted_prop.to = end_val
		}
		_register_tween(engine, adjusted_prop, vars, true)
	}
}

tween_from_to :: proc(engine: ^Engine, vars: Tween_Vars) {
	for prop in vars.properties {
		switch ptr in prop.target {
		case ^[4]f32:
			if prop.from_color == prop.to_color do continue
		case ^f32, ^Sizing:
			if prop.from == prop.to do continue
		}
		_register_tween(engine, prop, vars, true)
	}
}

@(private)
_register_tween :: proc(
	engine: ^Engine,
	prop: Property_Tween,
	vars: Tween_Vars,
	is_from: bool = false,
) {
	for &existing in engine.tweens {
		if existing.target == prop.target {
			existing.done = true
		}
	}

	append(
		&engine.tweens,
		Tween {
			target = prop.target,
			from = prop.from,
			to = prop.to,
			from_color = prop.from_color,
			to_color = prop.to_color,
			duration = vars.duration,
			delay = vars.delay,
			easing = vars.ease_func,
			is_from = is_from,
			on_complete = vars.on_complete,
			clear_flag = prop.clear_flag,
		},
	)
}
