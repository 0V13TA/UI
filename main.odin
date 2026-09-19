package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import "core:fmt"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

main :: proc() {
	sdl.Init({.VIDEO})
	defer sdl.Quit()
	ttf.Init()
	defer ttf.Quit()
	img.Init({.PNG, .JPG})
	defer img.Quit()

	window := sdl.CreateWindow(
		"Odin UI Engine - Dashboard",
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

	WALLPOET :: "./assets/font/Wallpoet-Regular.ttf"
	CAACUPEONE :: "./assets/font/CaacupeOne-Regular.ttf"
	SANKOFA_DISPLAY :: "./assets/font/SankofaDisplay-Regular.ttf"
	KABLAMMO :: "./assets/font/Kablammo-Regular-VariableFont_MORF.ttf"

	cursor_arrow := sdl.CreateSystemCursor(.ARROW)
	cursor_hand := sdl.CreateSystemCursor(.HAND)
	cursor_ibeam := sdl.CreateSystemCursor(.IBEAM)
	defer sdl.FreeCursor(cursor_arrow)
	defer sdl.FreeCursor(cursor_hand)
	defer sdl.FreeCursor(cursor_ibeam)

	perf_freq := f64(sdl.GetPerformanceFrequency())
	last_time := sdl.GetPerformanceCounter()

	// ---------------------------------------------------------
	// --- COMPONENT STATES
	// ---------------------------------------------------------

	// Navigation
	list_items := []string{"Dashboard", "User Directory", "Settings"}
	list_selected := 0

	// Tab State
	tab_labels := []string{"Controls", "Statistics"}
	active_tab := 0

	// Form States
	my_options := []string{"Admin", "Developer", "Designer", "Guest"}
	my_dropdown_open := false
	my_selected_idx := -1

	my_switch_val := false
	my_multi_open := false
	my_multi_states := [4]bool{false, false, false, false}

	my_combo_open := false
	my_combo_idx := -1
	my_combo_buf := make([dynamic]u8)
	defer delete(my_combo_buf)

	// Interactive States
	my_progress: f32 = 0.35
	accordion_open := true

	// Overlay States
	my_modal_open := false
	my_toast_open := false
	my_context_open := false
	my_context_x, my_context_y: f32 = 0, 0

	// Table Data
	table_headers := []string{"ID", "Name", "Role", "Status"}
	table_data := [][]string {
		{"101", "Alice Doe", "Admin", "Active"},
		{"102", "Bob Smith", "Developer", "Offline"},
		{"103", "Charlie", "Designer", "Active"},
		{"104", "David O.", "Guest", "Offline"},
		{"105", "Eve", "Developer", "Active"},
	}
	table_cols := []lc.Sizing{lc.Fixed{60}, lc.Grow{1}, lc.Fixed{120}, lc.Fixed{100}}

	running := true
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last_time) / perf_freq
		last_time = now

		ev.begin_frame(&ev_ctx)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			ev.pump_events(&ev_ctx, &event)
			if event.type == .QUIT do running = false

			// Capture right clicks anywhere to spawn the context menu
			if event.type == .MOUSEBUTTONDOWN && event.button.button == sdl.BUTTON_RIGHT {
				my_context_open = true
				my_context_x = f32(event.button.x)
				my_context_y = f32(event.button.y)
			}
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
		ctx_w, ctx_h := f32(win_w), f32(win_h)

		// ---------------------------------------------------------
		// --- UI LAYOUT TREE
		// ---------------------------------------------------------
		renderer.ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)

		{
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
			defer renderer.element_close(ui_ctx)

			{
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
				defer renderer.element_close(ui_ctx)

				renderer.text(
					ui_ctx,
					&ev_ctx,
					"OVIETAOS",
					user_style = {
						font_size = 30,
						font_name = CAACUPEONE,
						text_color = renderer.Color{0.1, 0.1, 0.1, 1},
					},
				)

				renderer.list_view(
					ui_ctx,
					&ev_ctx,
					list_items,
					&list_selected,
					wrapper_style = {
						height = lc.Grow{1},
						direction = .COLUMN,
						width = lc.Percent{100},
						border = renderer.space(0),
						bg_color = renderer.Color{0, 0, 0, 0},
					},
				)
			}

			{
				renderer.scroll_begin(
					ui_ctx,
					&ev_ctx,
					user_style = {
						gap = 32,
						width = lc.Grow{1},
						direction = .COLUMN,
						height = lc.Percent{100},
						padding = renderer.space(32, 48),
					},
				)
				defer renderer.scroll_end(ui_ctx)

				renderer.text(
					ui_ctx,
					&ev_ctx,
					list_items[list_selected],
					user_style = {
						font_size = 64,
						font_name = SANKOFA_DISPLAY,
						text_color = renderer.Color{0.1, 0.1, 0.1, 1},
					},
				)

				if list_selected == 0 {
					renderer.tabs(ui_ctx, &ev_ctx, tab_labels, &active_tab)

					if active_tab == 0 {
						{
							renderer.element_open(
								ui_ctx,
								{style = {direction = .ROW, gap = 24, width = lc.Percent{100}}},
							)
							defer renderer.element_close(ui_ctx)

							{
								renderer.element_open(
									ui_ctx,
									{style = {direction = .COLUMN, gap = 16, width = lc.Grow{1}}},
								)
								defer renderer.element_close(ui_ctx)

								renderer.dropdown(
									ui_ctx,
									&ev_ctx,
									"Select a role...",
									my_options,
									&my_selected_idx,
									&my_dropdown_open,
									wrapper_style = {
										width = lc.Percent{100},
										border = renderer.space(1),
										padding = renderer.space(12, 16),
										border_radius = renderer.space(6),
										bg_color = renderer.Color{1, 1, 1, 1},
										text_color = renderer.Color{0, 0, 0, 1},
									},
								)

								renderer.combobox(
									ui_ctx,
									&ev_ctx,
									"Search roles...",
									my_options,
									&my_combo_buf,
									&my_combo_idx,
									&my_combo_open,
									wrapper_style = {
										width = lc.Percent{100},
										height = lc.Fixed{50},
										padding = [4]f32{8, 8, 8, 8},
										border = [4]f32{1, 1, 1, 1},
										border_radius = [4]f32{6, 6, 6, 6},
										bg_color = renderer.Color{1, 1, 1, 1},
									},
								)

							}

							{
								renderer.element_open(
									ui_ctx,
									{style = {direction = .COLUMN, gap = 16, width = lc.Grow{1}}},
								)
								defer renderer.element_close(ui_ctx)

								renderer.multi_select(
									ui_ctx,
									&ev_ctx,
									"Permissions",
									my_options,
									my_multi_states[:],
									&my_multi_open,
									wrapper_style = {
										width = lc.Percent{100},
										border = [4]f32{1, 1, 1, 1},
										padding = [4]f32{12, 16, 12, 16},
										border_radius = [4]f32{6, 6, 6, 6},
										bg_color = renderer.Color{1, 1, 1, 1},
										text_color = renderer.Color{0, 0, 0, 1},
									},
								)
								renderer.switch_toggle(
									ui_ctx,
									&ev_ctx,
									"Dark Mode",
									&my_switch_val,
								)
							}
						}


						{
							renderer.element_open(
								ui_ctx,
								{
									style = {
										gap = 24,
										direction = .COLUMN,
										width = lc.Percent{100},
										border = renderer.space(1),
										padding = renderer.space(24),
										border_radius = renderer.space(8),
										bg_color = renderer.Color{1, 1, 1, 1},
										border_color = renderer.Color{0.9, 0.9, 0.9, 1},
									},
								},
							)
							defer renderer.element_close(ui_ctx)

							renderer.text(
								ui_ctx,
								&ev_ctx,
								"Volume Control",
								user_style = {
									font_size = 21,
									font_name = WALLPOET,
									text_color = renderer.Color{0.4, 0.4, 0.4, 1},
								},
							)

							renderer.slider(ui_ctx, &ev_ctx, &anim_ctx, &my_progress, 0.0, 1.0)
							renderer.progress_bar(
								ui_ctx,
								my_progress,
								wrapper_style = {
									width = lc.Percent{100},
									height = lc.Fixed{8},
									bg_color = renderer.Color{0.9, 0.9, 0.9, 1},
									border_radius = [4]f32{4, 4, 4, 4},
								},
							)

							{
								renderer.element_open(
									ui_ctx,
									{
										style = {
											direction = .ROW,
											justify_content = .SPACE_BETWEEN,
											align_items = .CENTER,
											width = lc.Percent{100},
										},
									},
								)
								defer renderer.element_close(ui_ctx)

								if renderer.button(ui_ctx, &ev_ctx, "Show Toast Overlay") do my_toast_open = true
								renderer.spinner(ui_ctx)
							}

						}
					} else if active_tab == 1 do renderer.text(ui_ctx, &ev_ctx, "Statistics content goes here")
				} else if list_selected == 1 {
					renderer.table(ui_ctx, &ev_ctx, table_headers, table_data, table_cols)
					{
						renderer.element_open(
							ui_ctx,
							{
								style = {
									direction = .ROW,
									justify_content = .END,
									width = lc.Percent{100},
									padding = renderer.space(16, 0, 0, 0),
								},
							},
						)
						defer renderer.element_close(ui_ctx)
						if renderer.button(
							ui_ctx,
							&ev_ctx,
							"Delete User",
							user_style = {
								bg_color = renderer.Color{0.9, 0.2, 0.2, 1},
								font_name = KABLAMMO,
							},
						) {my_modal_open = true}
					}
				} else if list_selected == 2 {
					if renderer.accordion_begin(
						ui_ctx,
						&ev_ctx,
						sdl_rend,
						"Advanced Settings",
						&accordion_open,
					) {
						defer renderer.accordion_end(ui_ctx, true)
						renderer.text(
							ui_ctx,
							&ev_ctx,
							"Warning: Modifying these values may break the layout engine.",
							user_style = {text_color = renderer.Color{0.6, 0.6, 0.6, 1}},
						)
						renderer.switch_toggle(
							ui_ctx,
							&ev_ctx,
							"Enable Experimental Rendering",
							&my_switch_val,
						)
					}
				}
			}

			if renderer.modal_begin(ui_ctx, &ev_ctx, &my_modal_open) {
				defer renderer.modal_end(ui_ctx, true)

				renderer.text(
					ui_ctx,
					&ev_ctx,
					"Delete User",
					user_style = {font_size = 32, font_name = SANKOFA_DISPLAY},
				)
				renderer.text(
					ui_ctx,
					&ev_ctx,
					"Are you sure you want to permanently delete this user? This action cannot be undone.",
					user_style = {
						text_wrap = .LETTER,
						font_name = WALLPOET,
						text_color = renderer.Color{0.4, 0.4, 0.4, 1},
					},
				)

				{
					renderer.element_open(
						ui_ctx,
						{
							style = {
								direction = .ROW,
								gap = 12,
								justify_content = .END,
								width = lc.Percent{100},
								padding = [4]f32{16, 0, 0, 0},
							},
						},
					)
					defer renderer.element_close(ui_ctx)

					if renderer.button(ui_ctx, &ev_ctx, "Cancel", user_style = {bg_color = renderer.Color{0.9, 0.9, 0.9, 1}, text_color = renderer.Color{0.1, 0.1, 0.1, 1}}) do my_modal_open = false
					if renderer.button(
						ui_ctx,
						&ev_ctx,
						"Confirm Delete",
						user_style = {bg_color = renderer.Color{0.9, 0.2, 0.2, 1}},
					) {
						fmt.println("User Deleted")
						my_modal_open = false
					}
				}
			}

			{
				renderer.element_open(
					ui_ctx,
					{
						style = {
							right = 24.0,
							bottom = 24.0,
							z_index = 4000,
							position = .FIXED,
							direction = .COLUMN_REVERSE,
						},
					},
				)
				defer renderer.element_close(ui_ctx)

				renderer.toast(
					ui_ctx,
					&ev_ctx,
					"Action Successful",
					"Component library integration complete.",
					.SUCCESS,
					&my_toast_open,
				)
			}

			if active, target := renderer.context_menu_begin(
				ui_ctx,
				&ev_ctx,
				my_context_x,
				my_context_y,
				&my_context_open,
			); active {
				defer renderer.context_menu_end(ui_ctx, true)
				if renderer.button(ui_ctx, &ev_ctx, "Copy ID", user_style = {text_align = .LEFT}) do my_context_open = false
				if renderer.button(ui_ctx, &ev_ctx, "Inspect Element", user_style = {text_align = .LEFT}) do my_context_open = false
				if renderer.button(ui_ctx, &ev_ctx, "Delete Node", user_style = {text_align = .LEFT, text_color = renderer.Color{0.9, 0.2, 0.2, 1}}) do my_context_open = false
			}
		}

		roots := renderer.ui_layout_tree(ui_ctx)
		for root in roots {
			anim.apply_structural(&anim_ctx, root)
		}
		renderer.ui_compute(ui_ctx)
		anim.update(&anim_ctx.engine, 0.016)

		visual_cb :: proc(user_data: rawptr, state: ^anim.Retained_State) {
			el := (^renderer.Element)(user_data)
			if el != nil do el.resolved_opacity = state.opacity
		}
		for root in roots {
			anim.apply_visual(&anim_ctx, root, visual_cb)
		}

		sdl.SetRenderDrawColor(sdl_rend, 240, 240, 245, 255)
		sdl.RenderClear(sdl_rend)
		renderer.render_tree(ui_ctx, sdl_rend, roots)
		sdl.RenderPresent(sdl_rend)
	}
}
