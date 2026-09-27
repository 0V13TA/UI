package UI

import "core:fmt"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

Time_State :: struct {
	delta:       f32,
	elapsed:     f32,
	_last_ticks: u64,
}

App :: struct {
	window:       ^sdl.Window,
	renderer:     ^sdl.Renderer,
	ui:           ^UI_Context,
	anim:         ^Context,
	ev:           ^Event_Context,
	time:         Time_State,
	window_w:     i32,
	window_h:     i32,
	quit:         bool,
	bg_color:     Color,

	// Cached System Cursors
	cursor_arrow: ^sdl.Cursor,
	cursor_hand:  ^sdl.Cursor,
	cursor_ibeam: ^sdl.Cursor,
}

app_init :: proc(
	title: cstring,
	width, height: i32,
	flags: sdl.WindowFlags = sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI,
) -> ^App {
	if sdl.Init(sdl.INIT_VIDEO | sdl.INIT_TIMER | sdl.INIT_EVENTS) != 0 {
		fmt.printfln("SDL Init Error: %s", sdl.GetError())
		return nil
	}

	if ttf.Init() != 0 {
		fmt.printfln("TTF Init Error: %s", sdl.GetError())
		return nil
	}

	app := new(App)
	app.window_w = width
	app.window_h = height
	app.bg_color = hex_rgb(0x18181b)
	app.time._last_ticks = sdl.GetPerformanceCounter()

	app.window = sdl.CreateWindow(
		title,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		width,
		height,
		flags,
	)

	app.renderer = sdl.CreateRenderer(
		app.window,
		-1,
		sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC,
	)
	sdl.SetRenderDrawBlendMode(app.renderer, .BLEND)

	// Initialize Subsystems
	app.ui = ui_context_create(f32(width), f32(height))

	app.anim = new(Context)
	app.anim.states = make(map[Box_ID]^Retained_State)

	app.ev = new(Event_Context)
	app.ev.layout = app.ui.layout
	app.ev.listeners = make(map[Box_ID]Event_Callbacks)
	app.ev.previous_listeners = make(map[Box_ID]Event_Callbacks)
	app.ev.clicked_this_frame = make(map[Box_ID]bool)
	app.ev.scroll_offsets_x = make(map[Box_ID]f32)
	app.ev.scroll_offsets_y = make(map[Box_ID]f32)
	app.ev.text_cursors = make(map[Box_ID]int)
	app.ev.text_selection = make(map[Box_ID]int)
	app.ev.cursor_blink_start = make(map[Box_ID]u64)
	app.ev.cursor_last_position = make(map[Box_ID]int)

	app.cursor_arrow = sdl.CreateSystemCursor(.ARROW)
	app.cursor_hand = sdl.CreateSystemCursor(.HAND)
	app.cursor_ibeam = sdl.CreateSystemCursor(.IBEAM)

	sdl.StartTextInput()

	return app
}

app_destroy :: proc(app: ^App) {
	sdl.StopTextInput()

	// Clean up cursors
	sdl.FreeCursor(app.cursor_arrow)
	sdl.FreeCursor(app.cursor_hand)
	sdl.FreeCursor(app.cursor_ibeam)

	// Clean up event context maps
	delete(app.ev.listeners)
	delete(app.ev.previous_listeners)
	delete(app.ev.focus_order)
	delete(app.ev.text_cursors)
	delete(app.ev.text_selection)
	delete(app.ev.scroll_offsets_x)
	delete(app.ev.scroll_offsets_y)
	delete(app.ev.cursor_blink_start)
	delete(app.ev.clicked_this_frame)
	delete(app.ev.cursor_last_position)
	free(app.ev)

	// Clean up animation context maps
	for _, state in app.anim.states do free(state)
	delete(app.anim.states)
	delete(app.anim.engine.tweens)
	free(app.anim)

	ui_context_destroy(app.ui)
	sdl.DestroyRenderer(app.renderer)
	sdl.DestroyWindow(app.window)
	ttf.Quit()
	sdl.Quit()
	free(app)
}

app_begin_frame :: proc(app: ^App) {
	now := sdl.GetPerformanceCounter()
	freq := sdl.GetPerformanceFrequency()
	app.time.delta = f32(f64(now - app.time._last_ticks) / f64(freq))
	app.time.elapsed += app.time.delta
	app.time._last_ticks = now

	// Reset frame-transient event state
	begin_frame(app.ev)

	// Pump SDL Events directly into the UI Engine
	event: sdl.Event
	for sdl.PollEvent(&event) != false {
		pump_events(app.ev, &event)

		#partial switch event.type {
		case .QUIT:
			app.quit = true

		case .WINDOWEVENT:
			if event.window.event == .RESIZED || event.window.event == .SIZE_CHANGED {
				app.window_w = event.window.data1
				app.window_h = event.window.data2
			}

		}
	}
	app.ev.listeners, app.ev.previous_listeners = app.ev.previous_listeners, app.ev.listeners
	clear(&app.ev.listeners)
	clear(&app.ev.focus_order)

	// Setup Renderer
	r, g, b, a := to_sdl_color(app.bg_color)
	sdl.SetRenderDrawColor(app.renderer, r, g, b, a)
	sdl.RenderClear(app.renderer)

	// Begin UI Layout
	ui_begin_frame(app.ui, app.renderer, app.window_w, app.window_h)
}

app_end_frame :: proc(app: ^App) {
	roots := ui_layout_tree(app.ui)
	if app.ev.focused_id != 0 {
		_, box_exists := app.ui.layout.all_boxes[app.ev.focused_id]
		callbacks, has_callbacks := app.ev.listeners[app.ev.focused_id]
		if !box_exists || !has_callbacks || !callbacks.focusable do set_focus(app.ev, 0)
	}
	if app.ev.pressed_id != 0 && app.ev.pressed_id not_in app.ui.layout.all_boxes {
		app.ev.pressed_id = 0
	}

	// Apply structural animations before constraints are resolved
	for root in roots {
		apply_structural(app.anim, root)
	}

	// Resolve Layout Engine Boundaries
	ui_compute(app.ui)
	refresh_hover(app.ev)

	target_cursor := app.cursor_arrow
	if hovered, ok := app.ui.layout.all_boxes[app.ev.hovered_id]; ok {
		for current := hovered; current != nil; current = current.parent {
			if cb, has_callbacks := app.ev.listeners[current.id];
			   has_callbacks && cb.cursor != .ARROW {
				#partial switch cb.cursor {
				case .HAND:
					target_cursor = app.cursor_hand
				case .IBEAM:
					target_cursor = app.cursor_ibeam
				}
				break
			}
		}
	}
	if sdl.GetCursor() != target_cursor do sdl.SetCursor(target_cursor)

	// Process Animation Lifecycles & Delta Ticks
	process_lifecycles(app.anim, app.ui.layout)
	update(&app.anim.engine, app.time.delta)

	// Apply Visual Transitions
	visual_cb :: proc(user_data: rawptr, state: ^Retained_State) {
		el := (^Element)(user_data)
		if el == nil do return

		el.resolved_opacity = state.opacity

		if state.has_bg_color do el.style.bg_color = transmute(Color)state.bg_color
		if state.has_text_color do el.style.text_color = transmute(Color)state.text_color
		if state.has_border_color do el.style.border_color = transmute(Color)state.border_color
	}
	for root in roots {
		apply_visual(app.anim, root, visual_cb)
	}

	// Draw the generated UI Box Tree
	render_tree(app.ui, app.renderer, roots)
	if app.ev.focus_visible && app.ev.focused_id != 0 {
		if focused, ok := app.ui.layout.all_boxes[app.ev.focused_id]; ok {
			previous_clip: Maybe(Rect) = nil
			if clip, has_clip := focused.clip_rect.?; has_clip {
				previous_clip = clip
				clip_rect := sdl.Rect{i32(clip.x), i32(clip.y), i32(clip.width), i32(clip.height)}
				sdl.RenderSetClipRect(app.renderer, &clip_rect)
			}

			for inset in -2 ..< 1 {
				rect := sdl.Rect {
					i32(focused.x) + i32(inset),
					i32(focused.y) + i32(inset),
					i32(focused.computed_width) - i32(inset) * 2,
					i32(focused.computed_height) - i32(inset) * 2,
				}
				sdl.SetRenderDrawColor(app.renderer, 30, 115, 235, 255)
				sdl.RenderDrawRect(app.renderer, &rect)
			}
			if previous_clip != nil do sdl.RenderSetClipRect(app.renderer, nil)
		}
	}

	// Swap Buffers
	sdl.RenderPresent(app.renderer)
	free_all(context.temp_allocator)
}
