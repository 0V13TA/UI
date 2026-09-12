package animations

import lc "../layout_calc"
import "core:math"

Callback_Fn :: proc(target: lc.Box_ID, data: rawptr)
Easing_Fn :: proc(t: f32) -> f32

ease_linear :: proc(t: f32) -> f32 {return t}
ease_out_exp :: proc(t: f32) -> f32 {return t == 1.0 ? 1.0 : 1.0 - math.pow(2.0, -10.0 * t)}

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
	ease_func:       Easing_Fn,
	properties:      []Property_Tween,
	on_complete:     Callback_Fn,
}

Tween :: struct {
	target:   Tween_Target, // Updated to use the union
	from, to: f32,
	duration: f32,
	delay:    f32, // Added for sequencing
	elapsed:  f32,
	easing:   Easing_Fn,
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
		progress := t.duration > 0.0 ? t.easing(t.elapsed / t.duration) : 1.0

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
