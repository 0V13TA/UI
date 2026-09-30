package UI

import "core:fmt"
import sdl "./vendor/sdl2"
import "./vendor/sdl2/ttf"

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
	ui_scale:     f32,
	quit:         bool,
	bg_color:     Color,
	event_router: proc(app: ^App, event: ^sdl.Event, data: rawptr) -> bool,
	event_router_data: rawptr,

	// Cached System Cursors
	cursor_arrow: ^sdl.Cursor,
	cursor_hand:  ^sdl.Cursor,
	cursor_ibeam: ^sdl.Cursor,
}

app_init :: proc(
	title: cstring,
	width, height: i32,
	flags: sdl.WindowFlags = sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI,
	asset_dir: string = "assets",
) -> ^App {
	if sdl.Init(sdl.INIT_VIDEO | sdl.INIT_TIMER | sdl.INIT_EVENTS) != 0 {
		fmt.printfln("SDL Init Error: %s", sdl.GetError())
		return nil
	}

	if ttf.Init() != 0 {
		fmt.printfln("TTF Init Error: %s", sdl.GetError())
		sdl.Quit()
		return nil
	}

	app := new(App)
	app.window_w = width
	app.window_h = height
	app.ui_scale = 1.0
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
	if app.window == nil {
		fmt.printfln("SDL Window Error: %s", sdl.GetError())
		ttf.Quit()
		sdl.Quit()
		free(app)
		return nil
	}
	sdl.GetWindowSize(app.window, &app.window_w, &app.window_h)

	app.renderer = sdl.CreateRenderer(
		app.window,
		-1,
		sdl.RENDERER_ACCELERATED | sdl.RENDERER_PRESENTVSYNC,
	)
	if app.renderer == nil {
		fmt.printfln("SDL Renderer Error: %s", sdl.GetError())
		sdl.DestroyWindow(app.window)
		ttf.Quit()
		sdl.Quit()
		free(app)
		return nil
	}
	sdl.SetRenderDrawBlendMode(app.renderer, .BLEND)

	when ODIN_PLATFORM_SUBTARGET == .Android {
		ddpi, hdpi, vdpi: f32
		if sdl.GetDisplayDPI(0, &ddpi, &hdpi, &vdpi) == 0 && ddpi > 0 {
			app.ui_scale = min(max(ddpi / 160.0, 0.75), 4.0)
		} else {
			fmt.printfln("SDL display DPI unavailable; using default UI scale")
		}

		output_w, output_h: i32
		if sdl.GetRendererOutputSize(app.renderer, &output_w, &output_h) == 0 &&
		   app_set_android_display_size(app, output_w, output_h) {
			// Android UI coordinates use density-independent pixels.
		} else {
			fmt.printfln("SDL logical display sizing failed: %s", sdl.GetError())
			sdl.DestroyRenderer(app.renderer)
			sdl.DestroyWindow(app.window)
			ttf.Quit()
			sdl.Quit()
			free(app)
			return nil
		}
	}

	// Initialize Subsystems
	app.ui = ui_context_create(f32(app.window_w), f32(app.window_h), asset_dir)

	app.anim = new(Context)
	app.anim.states = make(map[Box_ID]^Retained_State)

	app.ev = event_context_create(
		app.ui.layout,
		f32(app.window_w),
		f32(app.window_h),
		f32(app.window_w),
		f32(app.window_h),
	)

	app.cursor_arrow = sdl.CreateSystemCursor(.ARROW)
	app.cursor_hand = sdl.CreateSystemCursor(.HAND)
	app.cursor_ibeam = sdl.CreateSystemCursor(.IBEAM)

	return app
}

@(private)
app_set_android_display_size :: proc(app: ^App, pixel_w, pixel_h: i32) -> bool {
	if pixel_w <= 0 || pixel_h <= 0 do return false

	logical_w := max(i32(f32(pixel_w) / app.ui_scale), 1)
	logical_h := max(i32(f32(pixel_h) / app.ui_scale), 1)
	if sdl.RenderSetLogicalSize(app.renderer, logical_w, logical_h) != 0 do return false

	app.window_w = logical_w
	app.window_h = logical_h
	return true
}

ui_begin_app :: proc(
	title: cstring = "Odin UI",
	width: i32 = 800,
	height: i32 = 600,
	flags: sdl.WindowFlags = sdl.WINDOW_SHOWN | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI,
	asset_dir: string = "assets",
) -> ^App {
	return app_init(title, width, height, flags, asset_dir)
}

app_set_event_router :: proc(
	app: ^App,
	router: proc(app: ^App, event: ^sdl.Event, data: rawptr) -> bool,
	data: rawptr = nil,
) {
	app.event_router = router
	app.event_router_data = data
}

app_destroy :: proc(app: ^App) {
	sdl.StopTextInput()
	component_state_destroy()

	// Clean up cursors
	sdl.FreeCursor(app.cursor_arrow)
	sdl.FreeCursor(app.cursor_hand)
	sdl.FreeCursor(app.cursor_ibeam)

	event_context_destroy(app.ev)

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
		consumed := app.event_router != nil &&
		            app.event_router(app, &event, app.event_router_data)
		if !consumed do pump_events(app.ev, &event)

		#partial switch event.type {
		case .QUIT:
			app.quit = true

		case .WINDOWEVENT:
			if event.window.event == .RESIZED || event.window.event == .SIZE_CHANGED {
				when ODIN_PLATFORM_SUBTARGET == .Android {
					if !app_set_android_display_size(app, event.window.data1, event.window.data2) {
						fmt.printfln("SDL logical display resize failed: %s", sdl.GetError())
						app.quit = true
					}
				} else {
					app.window_w = event.window.data1
					app.window_h = event.window.data2
				}
				app.ev.viewport_w = f32(app.window_w)
				app.ev.viewport_h = f32(app.window_h)
				app.ev.input_screen_w = f32(app.window_w)
				app.ev.input_screen_h = f32(app.window_h)
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

app_create_nested_context :: proc(host: ^App) -> ^App {
	nested := new(App)
	nested.renderer = host.renderer
	nested.window_w = host.window_w
	nested.window_h = host.window_h
	nested.ui_scale = host.ui_scale
	nested.ui = ui_context_create(
		f32(host.window_w),
		f32(host.window_h),
		host.ui.asset_dir,
	)
	nested.anim = new(Context)
	nested.anim.states = make(map[Box_ID]^Retained_State)
	nested.ev = event_context_create(
		nested.ui.layout,
		f32(host.window_w),
		f32(host.window_h),
		f32(host.window_w),
		f32(host.window_h),
	)
	return nested
}

app_destroy_nested_context :: proc(nested: ^App) {
	if nested == nil do return

	event_context_destroy(nested.ev)
	for _, state in nested.anim.states do free(state)
	delete(nested.anim.states)
	delete(nested.anim.engine.tweens)
	free(nested.anim)
	ui_context_destroy(nested.ui)
	free(nested)
}

app_begin_nested_frame :: proc(
	nested: ^App,
	width, height: i32,
	origin_x, origin_y: f32,
	input_screen_w, input_screen_h: f32,
	delta: f32,
	events: []sdl.Event,
) -> bool {
	if nested == nil || width <= 0 || height <= 0 do return false

	nested.window_w = width
	nested.window_h = height
	nested.time.delta = delta
	nested.ev.viewport_w = f32(width)
	nested.ev.viewport_h = f32(height)
	nested.ev.input_origin_x = origin_x
	nested.ev.input_origin_y = origin_y
	nested.ev.input_screen_w = input_screen_w
	nested.ev.input_screen_h = input_screen_h

	begin_frame(nested.ev)
	for &event in events {
		pump_events(nested.ev, &event)
	}
	nested.ev.listeners, nested.ev.previous_listeners =
		nested.ev.previous_listeners, nested.ev.listeners
	clear(&nested.ev.listeners)
	clear(&nested.ev.focus_order)

	ui_begin_frame(nested.ui, nested.renderer, width, height)
	return true
}

@(private)
app_resolve_ui_frame :: proc(app: ^App) -> []^Box {
	roots := ui_layout_tree(app.ui)
	if app.ev.focused_id != 0 {
		_, box_exists := app.ui.layout.all_boxes[app.ev.focused_id]
		callbacks, has_callbacks := app.ev.listeners[app.ev.focused_id]
		if !box_exists || !has_callbacks || !callbacks.focusable || callbacks.disabled {
			set_focus(app.ev, 0)
		}
	}
	if app.ev.pressed_id != 0 && app.ev.pressed_id not_in app.ui.layout.all_boxes {
		app.ev.pressed_id = 0
	}

	for root in roots {
		apply_structural(app.anim, root)
	}
	ui_compute(app.ui)
	refresh_hover(app.ev)
	return roots
}

@(private)
app_finalize_ui_frame :: proc(app: ^App, roots: []^Box) {
	process_lifecycles(app.anim, app.ui.layout)
	update(&app.anim.engine, app.time.delta)

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
}

app_end_nested_frame :: proc(nested: ^App, bounds: sdl.Rect) -> bool {
	if nested == nil || bounds.w <= 0 || bounds.h <= 0 do return false

	roots := app_resolve_ui_frame(nested)
	app_finalize_ui_frame(nested, roots)

	old_viewport: sdl.Rect
	old_clip: sdl.Rect
	sdl.RenderGetViewport(nested.renderer, &old_viewport)
	sdl.RenderGetClipRect(nested.renderer, &old_clip)
	old_clip_enabled := sdl.RenderIsClipEnabled(nested.renderer)

	viewport := bounds
	if sdl.RenderSetViewport(nested.renderer, &viewport) != 0 {
		fmt.printfln("SDL nested canvas viewport error: %s", sdl.GetError())
		return false
	}

	nested_clip := sdl.Rect{0, 0, bounds.w, bounds.h}
	if old_clip_enabled {
		left := max(old_clip.x, bounds.x)
		top := max(old_clip.y, bounds.y)
		right := min(old_clip.x + old_clip.w, bounds.x + bounds.w)
		bottom := min(old_clip.y + old_clip.h, bounds.y + bounds.h)
		nested_clip = sdl.Rect{
			max(left - bounds.x, 0),
			max(top - bounds.y, 0),
			max(right - left, 0),
			max(bottom - top, 0),
		}
	}
	if sdl.RenderSetClipRect(nested.renderer, &nested_clip) != 0 {
		fmt.printfln("SDL nested canvas clip error: %s", sdl.GetError())
		sdl.RenderSetViewport(nested.renderer, &old_viewport)
		if old_clip_enabled do sdl.RenderSetClipRect(nested.renderer, &old_clip)
		else do sdl.RenderSetClipRect(nested.renderer, nil)
		return false
	}

	initial_clip := Rect {
		f32(nested_clip.x),
		f32(nested_clip.y),
		f32(nested_clip.w),
		f32(nested_clip.h),
	}
	render_tree(nested.ui, nested.renderer, roots, initial_clip)
	if nested.ev.focus_visible && nested.ev.focused_id != 0 {
		if focused, ok := nested.ui.layout.all_boxes[nested.ev.focused_id]; ok {
			if clip, has_clip := focused.clip_rect.?; has_clip {
				focus_clip := sdl.Rect{i32(clip.x), i32(clip.y), i32(clip.width), i32(clip.height)}
				clipped_focus: sdl.Rect
				sdl.IntersectRect(&nested_clip, &focus_clip, &clipped_focus)
				sdl.RenderSetClipRect(nested.renderer, &clipped_focus)
			}
			ring_width := i32(max(focused.focus_width, 0.0))
			r, g, b, a := to_sdl_color(focused.focus_color)
			for inset in -ring_width ..< 0 {
				rect := sdl.Rect {
					i32(focused.x) + i32(inset),
					i32(focused.y) + i32(inset),
					i32(focused.computed_width) - i32(inset) * 2,
					i32(focused.computed_height) - i32(inset) * 2,
				}
				sdl.SetRenderDrawColor(nested.renderer, r, g, b, a)
				sdl.RenderDrawRect(nested.renderer, &rect)
			}
		}
	}

	sdl.RenderSetViewport(nested.renderer, &old_viewport)
	if old_clip_enabled do sdl.RenderSetClipRect(nested.renderer, &old_clip)
	else do sdl.RenderSetClipRect(nested.renderer, nil)
	return true
}

app_end_frame :: proc(app: ^App) {
	roots := app_resolve_ui_frame(app)

	target_cursor := app.cursor_arrow
	if hovered, ok := app.ui.layout.all_boxes[app.ev.hovered_id]; ok {
		for current := hovered; current != nil; current = current.parent {
			if cb, has_callbacks := app.ev.listeners[current.id];
			   has_callbacks && !cb.disabled && cb.cursor != .ARROW {
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

	app_finalize_ui_frame(app, roots)

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

			ring_width := i32(max(focused.focus_width, 0.0))
			r, g, b, a := to_sdl_color(focused.focus_color)
			for inset in -ring_width ..< 0 {
				rect := sdl.Rect {
					i32(focused.x) + i32(inset),
					i32(focused.y) + i32(inset),
					i32(focused.computed_width) - i32(inset) * 2,
					i32(focused.computed_height) - i32(inset) * 2,
				}
				sdl.SetRenderDrawColor(app.renderer, r, g, b, a)
				sdl.RenderDrawRect(app.renderer, &rect)
			}
			if previous_clip != nil do sdl.RenderSetClipRect(app.renderer, nil)
		}
	}

	// Swap Buffers
	sdl.RenderPresent(app.renderer)
	free_all(context.temp_allocator)
}
