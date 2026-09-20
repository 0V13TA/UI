package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

// ---------------------------------------------------------
// --- 1. APPLICATION STATE
// ---------------------------------------------------------

App_State :: struct {
	list_items:        []string,
	list_selected:     int,
	main_router:       renderer.Router_State,

	// Component Test States
	test_switch:       bool,
	test_color:        [4]f32,
	color_picker_open: bool,
	selected_date:     [3]int, // [YYYY, MM, DD]
	date_picker_open:  bool,

	// Carousel State
	sdl_rend:          ^sdl.Renderer,
	carousel_idx:      int,
	carousel_images:   []string,
}

// ---------------------------------------------------------
// --- 2. PAGE PROCEDURES
// ---------------------------------------------------------

page_home :: proc(
	ui_ctx: ^renderer.UI_Context,
	ev_ctx: ^ev.Event_Context,
	anim_ctx: ^anim.Context,
	raw_state: rawptr,
) {
	renderer.scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 24,
			width = lc.Percent{100},
			height = lc.Percent{100},
			padding = renderer.space(40),
		},
		salt = "home_scroll",
	)
	defer renderer.scroll_end(ui_ctx)

	renderer.text(
		ui_ctx,
		ev_ctx,
		"Welcome Home",
		user_style = {font_size = 48, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
	)
	renderer.text(
		ui_ctx,
		ev_ctx,
		"This is a minimal test of the isolated router component.",
		user_style = {text_color = renderer.Color{0.4, 0.4, 0.4, 1}},
	)
}

page_components :: proc(
	ui_ctx: ^renderer.UI_Context,
	ev_ctx: ^ev.Event_Context,
	anim_ctx: ^anim.Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	renderer.scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 32,
			width = lc.Percent{100},
			height = lc.Percent{100},
			padding = renderer.space(40),
		},
		salt = "comp_scroll",
	)
	defer renderer.scroll_end(ui_ctx)

	renderer.text(
		ui_ctx,
		ev_ctx,
		"Interactive Widgets",
		user_style = {font_size = 48, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
	)

	// A flex row to hold our components side-by-side
	renderer.element_open(ui_ctx, {style = {direction = .ROW, gap = 48, width = lc.Percent{100}}})
	defer renderer.element_close(ui_ctx)

	// A flex column to stack them neatly on the left
	renderer.element_open(ui_ctx, {style = {direction = .COLUMN, gap = 24, width = lc.Fit(true)}})
	defer renderer.element_close(ui_ctx)

	renderer.switch_toggle(ui_ctx, ev_ctx, anim_ctx, "Toggle Feature", &state.test_switch)

	renderer.color_picker(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		"Theme Color",
		&state.test_color,
		&state.color_picker_open,
		salt = "cp1",
	)

	renderer.date_picker(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		"Launch Date",
		&state.selected_date,
		&state.date_picker_open,
		salt = "dp1",
	)
}

page_carousel :: proc(
	ui_ctx: ^renderer.UI_Context,
	ev_ctx: ^ev.Event_Context,
	anim_ctx: ^anim.Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	renderer.scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 32,
			width = lc.Percent{100},
			height = lc.Percent{100},
			padding = renderer.space(40),
		},
		salt = "carousel_scroll",
	)
	defer renderer.scroll_end(ui_ctx)

	renderer.text(
		ui_ctx,
		ev_ctx,
		"Image Gallery",
		user_style = {font_size = 48, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
	)

	// Center the carousel horizontally
	renderer.element_open(
		ui_ctx,
		{
			style = {
				direction = .COLUMN,
				align_items = .CENTER,
				width = lc.Percent{100},
				padding = renderer.space(40, 0),
			},
		},
	)
	defer renderer.element_close(ui_ctx)

	// Massive Viewport
	renderer.carousel_paths(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		state.sdl_rend,
		state.carousel_images,
		&state.carousel_idx,
		viewport_style = {
			width = lc.Fixed{600},
			height = lc.Fixed{400},
			border_radius = renderer.space(12),
		},
		salt = "main_carousel",
	)
}

// ---------------------------------------------------------
// --- 3. MAIN LOOP
// ---------------------------------------------------------

main :: proc() {
	sdl.Init({.VIDEO})
	defer sdl.Quit()
	ttf.Init()
	defer ttf.Quit()
	img.Init({.PNG, .JPG})
	defer img.Quit()

	window := sdl.CreateWindow(
		"OvietaOS - Minimal Test",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1024,
		768,
		{.SHOWN, .RESIZABLE},
	)
	defer sdl.DestroyWindow(window)

	sdl_rend := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(sdl_rend)
	sdl.SetRenderDrawBlendMode(sdl_rend, .BLEND)

	ui_ctx := renderer.ui_context_create(1024, 768)
	defer renderer.ui_context_destroy(ui_ctx)

	ev_ctx := ev.Event_Context {
		layout               = ui_ctx.layout,
		listeners            = make(map[lc.Box_ID]ev.Event_Callbacks),
		clicked_this_frame   = make(map[lc.Box_ID]bool),
		scroll_offsets_x     = make(map[lc.Box_ID]f32),
		scroll_offsets_y     = make(map[lc.Box_ID]f32),
		text_cursors         = make(map[lc.Box_ID]int),
		text_selection       = make(map[lc.Box_ID]int),
		cursor_blink_start   = make(map[lc.Box_ID]u64),
		cursor_last_position = make(map[lc.Box_ID]int),
	}

	anim_ctx := anim.Context {
		states = make(map[lc.Box_ID]^anim.Retained_State),
	}

	cursor_arrow := sdl.CreateSystemCursor(.ARROW)
	cursor_hand := sdl.CreateSystemCursor(.HAND)
	cursor_ibeam := sdl.CreateSystemCursor(.IBEAM)
	defer sdl.FreeCursor(cursor_arrow)
	defer sdl.FreeCursor(cursor_hand)
	defer sdl.FreeCursor(cursor_ibeam)

	perf_freq := f64(sdl.GetPerformanceFrequency())
	last_time := sdl.GetPerformanceCounter()

	// Setup our minimal state
	app := App_State {
		sdl_rend        = sdl_rend,
		list_items      = {"Home", "Components", "Carousel"},
		list_selected   = 0,
		test_color      = {0.15, 0.4, 0.8, 1.0},
		selected_date   = {2026, 9, 20},
		// Swap these paths out for actual large images if you have them!
		carousel_images = {
			"assets/pictures/carousel/slide1.png",
			"assets/pictures/carousel/slide2.png",
			"assets/pictures/carousel/slide3.png",
		},
	}

	my_pages := []renderer.Page_Proc{page_home, page_components, page_carousel}

	running := true
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last_time) / perf_freq
		last_time = now
		frame_dt := f32(min(dt, 0.1))

		ev.begin_frame(&ev_ctx)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			ev.pump_events(&ev_ctx, &event)
			if event.type == .QUIT do running = false
		}

		target_cursor := cursor_arrow
		if cb, ok := ev_ctx.listeners[ev_ctx.hovered_id]; ok {
			#partial switch cb.cursor {
			case .HAND:
				target_cursor = cursor_hand
			case .IBEAM:
				target_cursor = cursor_ibeam
			}
		}
		if sdl.GetCursor() != target_cursor do sdl.SetCursor(target_cursor)

		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

		// --- BUILD UI TREE ---
		renderer.ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)

		// Root Container
		renderer.element_open(
			ui_ctx,
			{
				style = {
					direction = .ROW,
					width = lc.ViewPercent{100},
					height = lc.ViewPercent{100},
					bg_color = renderer.Color{0.96, 0.96, 0.98, 1},
				},
			},
		)

		// Sidebar
		renderer.element_open(
			ui_ctx,
			{
				style = {
					gap = 24,
					direction = .COLUMN,
					width = lc.Fixed{240},
					height = lc.Percent{100},
					padding = renderer.space(24, 16),
					border = renderer.space(0, 1, 0, 0),
					bg_color = renderer.Color{1, 1, 1, 1},
					border_color = renderer.Color{0.85, 0.85, 0.85, 1},
				},
			},
		)
		renderer.text(
			ui_ctx,
			&ev_ctx,
			"TEST OS",
			user_style = {font_size = 24, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
		)
		renderer.list_view(
			ui_ctx,
			&ev_ctx,
			app.list_items,
			&app.list_selected,
			wrapper_style = {
				height = lc.Grow{1},
				border = renderer.space(0),
				bg_color = renderer.Color{0, 0, 0, 0},
			},
		)
		renderer.element_close(ui_ctx) // Close Sidebar

		// Main Content Area (Router handles the layout wrapper)
		renderer.router_view(
			ui_ctx,
			&ev_ctx,
			&anim_ctx,
			&app.main_router,
			app.list_selected,
			my_pages,
			&app,
			salt = "main_router",
		)

		renderer.element_close(ui_ctx) // Close Root Container

		// --- COMPUTE AND RENDER ---
		roots := renderer.ui_layout_tree(ui_ctx)
		for root in roots do anim.apply_structural(&anim_ctx, root)

		renderer.ui_compute(ui_ctx)
		anim.update(&anim_ctx.engine, frame_dt)

		visual_cb :: proc(user_data: rawptr, state: ^anim.Retained_State) {
			el := (^renderer.Element)(user_data)
			if el == nil do return
			el.resolved_opacity = state.opacity
			if state.has_bg_color do el.style.bg_color = transmute(renderer.Color)state.bg_color
			if state.has_text_color do el.style.text_color = transmute(renderer.Color)state.text_color
			if state.has_border_color do el.style.border_color = transmute(renderer.Color)state.border_color
		}
		for root in roots do anim.apply_visual(&anim_ctx, root, visual_cb)

		sdl.SetRenderDrawColor(sdl_rend, 240, 240, 245, 255)
		sdl.RenderClear(sdl_rend)
		renderer.render_tree(ui_ctx, sdl_rend, roots)
		sdl.RenderPresent(sdl_rend)
	}
}
