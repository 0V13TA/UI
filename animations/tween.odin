package animations

import lc "../layout_calc"
import "core:math"

Callback_Fn :: proc(target: lc.Box_ID, data: rawptr)
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

	// Binary search for parametric 't' given x
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
	^lc.Sizing,
}

Property_Tween :: struct {
	target:   Tween_Target,
	from, to: f32,
}

Tween_Vars :: struct {
	duration, delay: f32,
	ease_func:       Easing,
	properties:      []Property_Tween,
	on_complete:     Callback_Fn,
}

Tween :: struct {
	target:   Tween_Target, // Updated to use the union
	from, to: f32,
	duration: f32,
	delay:    f32, // Added for sequencing
	elapsed:  f32,
	easing:   Easing,
	done:     bool,
}

Engine :: struct {
	tweens: [dynamic]Tween,
}

update :: proc(engine: ^Engine, dt: f32) {
	#reverse for &t, i in engine.tweens {
		if t.done {
			unordered_remove(&engine.tweens, i)
			continue
		}

		// Handle delays
		if t.delay > 0.0 {
			t.delay -= dt
			continue
		}

		t.elapsed = min(t.elapsed + dt, t.duration)

		// NEW: Unpack the Easing union
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

		// The interpolated raw float
		current_val := t.from + (t.to - t.from) * progress

		// THE MAGIC: Write back to memory based on the target type
		switch ptr in t.target {
		case ^f32:
			ptr^ = current_val
		case ^lc.Sizing:
			ptr^ = lc.Fixed{current_val} // Force structural reflows to Fixed
		}

		if t.elapsed >= t.duration do t.done = true
	}
}

// animations/tween.odin
@(private)
get_current_val :: proc(target: Tween_Target) -> f32 {
	switch ptr in target {
	case ^f32:
		return ptr^
	case ^lc.Sizing:
		#partial switch v in ptr^ {
		case lc.Fixed:
			return v.value
		case lc.Percent:
			return v.value
		case lc.ViewPercent:
			return v.value
		case:
			return 0.0 // Fallback for Fit/Grow/Shrink
		}
	}
	return 0.0
}

// gsap.to() - Starts at current memory value, animates to target
to :: proc(engine: ^Engine, vars: Tween_Vars) {
	for prop in vars.properties {
		start_val := get_current_val(prop.target)
		if start_val == prop.to do continue
		_register_tween(engine, prop.target, start_val, prop.to, vars)
	}
}

// gsap.from() - Snaps to provided value, animates back to current memory state
from :: proc(engine: ^Engine, vars: Tween_Vars) {
	for prop in vars.properties {
		end_val := get_current_val(prop.target)
		if prop.from == end_val do continue

		// Instantly snap the UI to the 'from' state
		switch ptr in prop.target {
		case ^f32:
			ptr^ = prop.from
		case ^lc.Sizing:
			ptr^ = lc.Fixed{prop.from}
		}

		_register_tween(engine, prop.target, prop.from, end_val, vars)
	}
}

// gsap.fromTo() - Explicit start and end
from_to :: proc(engine: ^Engine, vars: Tween_Vars) {
	for prop in vars.properties {
		if prop.from == prop.to do continue

		switch ptr in prop.target {
		case ^f32:
			ptr^ = prop.from
		case ^lc.Sizing:
			ptr^ = lc.Fixed{prop.from}
		}

		_register_tween(engine, prop.target, prop.from, prop.to, vars)
	}
}


@(private)
_register_tween :: proc(engine: ^Engine, target: Tween_Target, from, to: f32, vars: Tween_Vars) {
	// Kill any existing tween already targeting this exact pointer — otherwise
	// two tweens racing to write the same ^f32 every frame produces flicker/
	// undefined-looking results, not a clean "latest one wins."
	for &existing in engine.tweens {
		if existing.target == target {
			existing.done = true
		}
	}

	append(
		&engine.tweens,
		Tween {
			target = target,
			from = from,
			to = to,
			duration = vars.duration,
			delay = vars.delay,
			easing = vars.ease_func,
		},
	)
}
