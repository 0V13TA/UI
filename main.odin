package UI

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

// Global Fonts
WALLPOET :: "./assets/font/Wallpoet-Regular.ttf"
CAACUPEONE :: "./assets/font/CaacupeOne-Regular.ttf"
SANKOFA_DISPLAY :: "./assets/font/SankofaDisplay-Regular.ttf"
KABLAMMO :: "./assets/font/Kablammo-Regular-VariableFont_MORF.ttf"

// Centralized Application State
App_State :: struct {
	sdl_rend:          ^sdl.Renderer,

	// Navigation
	list_items:        []string,
	list_selected:     int,
	main_router:       Router_State,

	// Tab State (Dashboard)
	tab_labels:        []string,
	active_tab:        int,
	tab_router:        Router_State,

	// Dashboard Form State
	my_options:        []string,
	my_dropdown_open:  bool,
	my_selected_idx:   int,
	my_switch_val:     bool,
	my_multi_open:     bool,
	my_multi_states:   [4]bool,
	my_combo_open:     bool,
	my_combo_idx:      int,
	my_combo_buf:      [dynamic]u8,
	my_progress:       f32,
	my_toast_open:     bool,

	// Directory State
	table_headers:     []string,
	users:             [dynamic][4]string,
	table_cols:        []Sizing,
	form_user_name:    [dynamic]u8,
	target_user_id:    [dynamic]u8,
	form_role_idx:     int,
	form_status_idx:   int,
	status_options:    []string,
	create_modal_open: bool,
	delete_modal_open: bool,
	next_id:           int,

	// Settings State
	accordion_open:    bool,

	// New Rapid-Fire Components
	my_color:          [4]f32,
	color_picker_open: bool,
	carousel_idx:      int,
	carousel_images:   []string,
	selected_date:     [3]int, // [YYYY, MM, DD]
	date_picker_open:  bool,
	debug_mode_open:   bool,
}

// ---------------------------------------------------------
// --- PAGE PROCEDURES
// ---------------------------------------------------------

page_dashboard :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	dash_scroll_id := scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 32,
			width = Percent{100},
			height = Percent{100},
			padding = space(32, 48),
		},
		salt = "dash_scroll",
	)
	defer scroll_end(ui_ctx, ev_ctx, dash_scroll_id, anim_ctx)

	text(
		ui_ctx,
		ev_ctx,
		state.list_items[state.main_router.current_idx],
		user_style = {font_size = 64, font_name = SANKOFA_DISPLAY},
	)

	tabs(ui_ctx, ev_ctx, state.tab_labels, &state.active_tab)

	tab_pages := []Page_Proc{tab_controls, tab_statistics}
	router_view(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		&state.tab_router,
		state.active_tab,
		tab_pages,
		state,
		wrapper_style = {height = Fit(true), gap = 32},
		salt = "tab_router",
	)
}

tab_controls :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	element_open(ui_ctx, {style = {direction = .ROW, gap = 24, width = Percent{100}}})
	defer element_close(ui_ctx) // Close Row

	// --- Column 1 ---
	{
		element_open(ui_ctx, {style = {direction = .COLUMN, gap = 16, width = Grow{1}}})
		defer element_close(ui_ctx)

		dropdown(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Select a role...",
			state.my_options,
			&state.my_selected_idx,
			&state.my_dropdown_open,
			wrapper_style = {
				width = Percent{100},
				border = space(1),
				padding = space(12, 16),
				border_radius = space(6),
				bg_color = Color{1, 1, 1, 1},
				text_color = Color{0, 0, 0, 1},
			},
		)
		combobox(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Search roles...",
			state.my_options,
			&state.my_combo_buf,
			&state.my_combo_idx,
			&state.my_combo_open,
			wrapper_style = {
				width = Percent{100},
				height = Fixed{50},
				padding = [4]f32{8, 8, 8, 8},
				border = [4]f32{1, 1, 1, 1},
				border_radius = [4]f32{6, 6, 6, 6},
				bg_color = Color{1, 1, 1, 1},
			},
		)
	}

	// --- Column 2 ---
	{
		element_open(ui_ctx, {style = {direction = .COLUMN, gap = 16, width = Grow{1}}})
		defer element_close(ui_ctx)

		multi_select(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Permissions",
			state.my_options,
			state.my_multi_states[:],
			&state.my_multi_open,
			wrapper_style = {
				width = Percent{100},
				border = [4]f32{1, 1, 1, 1},
				padding = [4]f32{12, 16, 12, 16},
				border_radius = [4]f32{6, 6, 6, 6},
				bg_color = Color{1, 1, 1, 1},
				text_color = Color{0, 0, 0, 1},
			},
		)
		switch_toggle(ui_ctx, ev_ctx, anim_ctx, "Dark Mode", &state.my_switch_val)
	}

	// --- Column 3 (New Components) ---
	{
		element_open(ui_ctx, {style = {direction = .COLUMN, gap = 16, width = Grow{1}}})
		defer element_close(ui_ctx)

		color_picker(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Brand Accent",
			&state.my_color,
			&state.color_picker_open,
			salt = "cp1",
		)

		// The exact 6-argument call required by components.odin
		date_picker(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Launch Date",
			&state.selected_date,
			&state.date_picker_open,
			salt = "dp1",
		)

		carousel_paths(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			state.sdl_rend,
			state.carousel_images,
			&state.carousel_idx,
			wrapper_style = {width = Percent{100}}, // Explicitly bound the Fit(true) parent
			viewport_style = {width = Percent{100}, height = Fixed{160}},
			arrow_style = {width = Fixed{32}, height = Fixed{32}, padding = space(8)},
			auto_play = true,
			salt = "carousel1",
		)
	}
}

tab_statistics :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	raw_state: rawptr,
) {
	text(ui_ctx, ev_ctx, "Statistics content goes here")
}

page_directory :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	dir_scroll_id := scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 32,
			width = Percent{100},
			height = Percent{100},
			padding = space(32, 48),
		},
		salt = "dir_scroll",
	)
	defer scroll_end(ui_ctx, ev_ctx, dir_scroll_id, anim_ctx)

	text(
		ui_ctx,
		ev_ctx,
		state.list_items[state.main_router.current_idx],
		user_style = {font_size = 64, font_name = SANKOFA_DISPLAY},
	)

	display_data := make([][]string, len(state.users), context.temp_allocator)
	for i in 0 ..< len(state.users) {
		display_data[i] = state.users[i][:]
	}

	table(
		ui_ctx,
		ev_ctx,
		state.table_headers,
		display_data,
		state.table_cols,
		cell_text_style = {font_name = WALLPOET},
	)

	element_open(
		ui_ctx,
		{
			style = {
				direction = .ROW,
				justify_content = .END,
				gap = 12,
				width = Percent{100},
				padding = space(16, 0, 0, 0),
			},
		},
	)
	defer element_close(ui_ctx)

	if button(ui_ctx, ev_ctx, "Add User", user_style = {bg_color = Color{0.2, 0.6, 0.3, 1}}) {
		state.create_modal_open = true
		clear(&state.form_user_name)
		state.form_role_idx = 0
		state.form_status_idx = 0
	}

	if button(ui_ctx, ev_ctx, "Delete User", user_style = {bg_color = Color{0.9, 0.2, 0.2, 1}}) {
		state.delete_modal_open = true
		clear(&state.target_user_id)
	}

	// Modals (Rendered Out-of-Flow)
	if modal_begin(ui_ctx, ev_ctx, anim_ctx, &state.create_modal_open, salt = "create_modal") {
		defer modal_end(ui_ctx, true)
		text(
			ui_ctx,
			ev_ctx,
			"New User",
			user_style = {font_size = 32, font_name = SANKOFA_DISPLAY},
		)
		text_input(
			ui_ctx,
			ev_ctx,
			&state.form_user_name,
			placeholder = "Enter Name...",
			salt = "name_input",
		)

		@(static) role_open: bool
		dropdown(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Role",
			state.my_options,
			&state.form_role_idx,
			&role_open,
			salt = "role_drop",
		)

		@(static) status_open: bool
		dropdown(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Status",
			state.status_options,
			&state.form_status_idx,
			&status_open,
			salt = "status_drop",
		)

		element_open(
			ui_ctx,
			{
				style = {
					direction = .ROW,
					gap = 12,
					justify_content = .END,
					width = Percent{100},
					padding = [4]f32{16, 0, 0, 0},
				},
			},
		)
		defer element_close(ui_ctx)

		if button(ui_ctx, ev_ctx, "Cancel", user_style = {bg_color = Color{0.9, 0.9, 0.9, 1}, text_color = Color{0.1, 0.1, 0.1, 1}}) do state.create_modal_open = false

		if button(
			ui_ctx,
			ev_ctx,
			"Save User",
			user_style = {bg_color = Color{0.15, 0.4, 0.8, 1}},
		) {
			new_id := fmt.tprintf("%d", state.next_id)
			state.next_id += 1
			cloned_name := strings.clone(string(state.form_user_name[:]))
			append(
				&state.users,
				[4]string {
					new_id,
					cloned_name,
					state.my_options[state.form_role_idx],
					state.status_options[state.form_status_idx],
				},
			)
			state.create_modal_open = false
			state.my_toast_open = true
		}
	}

	if modal_begin(ui_ctx, ev_ctx, anim_ctx, &state.delete_modal_open, salt = "del_modal") {
		defer modal_end(ui_ctx, true)
		text(
			ui_ctx,
			ev_ctx,
			"Delete User",
			user_style = {font_size = 32, font_name = SANKOFA_DISPLAY},
		)
		text(
			ui_ctx,
			ev_ctx,
			"Enter the ID of the user you want to permanently delete.",
			user_style = {text_color = Color{0.4, 0.4, 0.4, 1}},
		)
		text_input(
			ui_ctx,
			ev_ctx,
			&state.target_user_id,
			placeholder = "User ID (e.g. 101)",
			salt = "id_input",
		)

		element_open(
			ui_ctx,
			{
				style = {
					direction = .ROW,
					gap = 12,
					justify_content = .END,
					width = Percent{100},
					padding = [4]f32{16, 0, 0, 0},
				},
			},
		)
		defer element_close(ui_ctx)

		if button(ui_ctx, ev_ctx, "Cancel", user_style = {bg_color = Color{0.9, 0.9, 0.9, 1}, text_color = Color{0.1, 0.1, 0.1, 1}}) do state.delete_modal_open = false

		if button(
			ui_ctx,
			ev_ctx,
			"Confirm Delete",
			user_style = {bg_color = Color{0.9, 0.2, 0.2, 1}},
		) {
			target_str := string(state.target_user_id[:])
			for i in 0 ..< len(state.users) {
				if state.users[i][0] == target_str {
					ordered_remove(&state.users, i)
					break
				}
			}
			state.delete_modal_open = false
		}
	}
}

page_settings :: proc(
	ui_ctx: ^UI_Context,
	ev_ctx: ^Event_Context,
	anim_ctx: ^Context,
	raw_state: rawptr,
) {
	state := (^App_State)(raw_state)

	set_scroll_id := scroll_begin(
		ui_ctx,
		ev_ctx,
		user_style = {
			gap = 32,
			width = Percent{100},
			height = Percent{100},
			padding = space(32, 48),
		},
		salt = "set_scroll",
	)
	defer scroll_end(ui_ctx, ev_ctx, set_scroll_id, anim_ctx)

	text(
		ui_ctx,
		ev_ctx,
		state.list_items[state.main_router.current_idx],
		user_style = {font_size = 64, font_name = SANKOFA_DISPLAY},
	)

	if accordion_begin(
		ui_ctx,
		ev_ctx,
		anim_ctx,
		state.sdl_rend,
		"Advanced Settings",
		&state.accordion_open,
	) {
		defer accordion_end(ui_ctx, true)
		text(
			ui_ctx,
			ev_ctx,
			"Warning: Modifying these values may break the layout engine.",
			user_style = {text_color = Color{0.6, 0.6, 0.6, 1}},
		)
		switch_toggle(
			ui_ctx,
			ev_ctx,
			anim_ctx,
			"Enable Experimental Rendering",
			&state.my_switch_val,
		)
	}
}

// ---------------------------------------------------------
// --- MAIN APPLICATION
// ---------------------------------------------------------

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

	ui_ctx := ui_context_create(1024, 768)
	defer ui_context_destroy(ui_ctx)

	ev_ctx := Event_Context {
		layout               = ui_ctx.layout,
		listeners            = make(map[Box_ID]Event_Callbacks),
		clicked_this_frame   = make(map[Box_ID]bool),
		scroll_offsets_x     = make(map[Box_ID]f32),
		scroll_offsets_y     = make(map[Box_ID]f32),
		text_cursors         = make(map[Box_ID]int),
		text_selection       = make(map[Box_ID]int),
		cursor_blink_start   = make(map[Box_ID]u64),
		cursor_last_position = make(map[Box_ID]int),
	}

	anim_ctx := Context {
		states = make(map[Box_ID]^Retained_State),
	}

	cursor_arrow := sdl.CreateSystemCursor(.ARROW)
	cursor_hand := sdl.CreateSystemCursor(.HAND)
	cursor_ibeam := sdl.CreateSystemCursor(.IBEAM)
	defer sdl.FreeCursor(cursor_arrow)
	defer sdl.FreeCursor(cursor_hand)
	defer sdl.FreeCursor(cursor_ibeam)

	perf_freq := f64(sdl.GetPerformanceFrequency())
	last_time := sdl.GetPerformanceCounter()

	app := App_State {
		sdl_rend         = sdl_rend,
		list_items       = {"Dashboard", "User Directory", "Settings"},
		list_selected    = 0,
		tab_labels       = {"Controls", "Statistics"},
		active_tab       = 0,
		my_options       = {"Admin", "Developer", "Designer", "Guest"},
		my_selected_idx  = -1,
		my_combo_idx     = -1,
		my_combo_buf     = make([dynamic]u8),
		my_progress      = 0.35,
		accordion_open   = true,
		table_headers    = {"ID", "Name", "Role", "Status"},
		users            = make([dynamic][4]string),
		table_cols       = {Fixed{60}, Grow{1}, Fixed{120}, Fixed{100}},
		form_user_name   = make([dynamic]u8),
		target_user_id   = make([dynamic]u8),
		status_options   = {"Active", "Offline"},
		next_id          = 104,
		my_color         = {0.15, 0.4, 0.8, 1.0},
		carousel_images  = {
			"assets/pictures/carousel/slide1.png",
			"assets/pictures/carousel/slide2.png",
			"assets/pictures/carousel/slide3.png",
		},
		selected_date    = {2026, 9, 20},
		date_picker_open = false,
	}
	defer delete(app.my_combo_buf)
	defer delete(app.users)
	defer delete(app.form_user_name)
	defer delete(app.target_user_id)

	append(&app.users, [4]string{"101", "Alice Doe", "Admin", "Active"})
	append(&app.users, [4]string{"102", "Bob Smith", "Developer", "Offline"})
	append(&app.users, [4]string{"103", "Charlie", "Designer", "Active"})

	my_pages := []Page_Proc{page_dashboard, page_directory, page_settings}
	my_context_x, my_context_y: f32 = 0, 0
	my_context_open := false

	running := true
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last_time) / perf_freq
		last_time = now
		frame_dt := f32(min(dt, 0.1))

		begin_frame(&ev_ctx)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			pump_events(&ev_ctx, &event)
			if event.type == .QUIT do running = false

			if event.type == .KEYDOWN {
				// Cycle Focus
				if event.key.keysym.sym == .TAB {
					has_shift := (transmute(u16)event.key.keysym.mod & 0x0003) != 0
					cycle_focus(&ev_ctx, reverse = has_shift)
				}
				// Toggle Debug Mode
				if event.key.keysym.sym == .F3 {
					app.debug_mode_open = !app.debug_mode_open
				}
			}

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

		// ---------------------------------------------------------
		// --- UI LAYOUT TREE
		// ---------------------------------------------------------
		ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)

		{
			element_open(
				ui_ctx,
				{
					style = {
						direction = .ROW,
						width = ViewPercent{100},
						height = ViewPercent{100},
						bg_color = Color{0.96, 0.96, 0.98, 1},
					},
				},
			)
			defer element_close(ui_ctx)

			{
				element_open(
					ui_ctx,
					{
						style = {
							gap = 24,
							direction = .COLUMN,
							width = Fixed{240},
							height = Percent{100},
							padding = space(24, 16),
							border = space(0, 1, 0, 0),
							bg_color = Color{1, 1, 1, 1},
							border_color = Color{0.85, 0.85, 0.85, 1},
						},
					},
				)
				defer element_close(ui_ctx)

				text(
					ui_ctx,
					&ev_ctx,
					"OVIETAOS",
					user_style = {
						font_size = 30,
						font_name = CAACUPEONE,
						text_color = Color{0.1, 0.1, 0.1, 1},
					},
				)
				list_view(
					ui_ctx,
					&ev_ctx,
					app.list_items,
					&app.list_selected,
					wrapper_style = {
						height = Grow{1},
						direction = .COLUMN,
						width = Percent{100},
						border = space(0),
						bg_color = Color{0, 0, 0, 0},
					},
				)
			}

			router_view(
				ui_ctx,
				&ev_ctx,
				&anim_ctx,
				&app.main_router,
				app.list_selected,
				my_pages,
				&app,
				salt = "main_router",
			)

			{
				element_open(
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
				defer element_close(ui_ctx)
				toast(
					ui_ctx,
					&ev_ctx,
					"Action Successful",
					"Component library integration complete.",
					.SUCCESS,
					&app.my_toast_open,
				)
			}

			if active, target := context_menu_begin(
				ui_ctx,
				&ev_ctx,
				&anim_ctx,
				my_context_x,
				my_context_y,
				&my_context_open,
			); active {
				defer context_menu_end(ui_ctx, true)
				if button(ui_ctx, &ev_ctx, "Copy ID", user_style = {text_align = .LEFT}) do my_context_open = false
				if button(ui_ctx, &ev_ctx, "Inspect Element", user_style = {text_align = .LEFT}) do my_context_open = false
				if button(ui_ctx, &ev_ctx, "Delete Node", user_style = {text_align = .LEFT, text_color = Color{0.9, 0.2, 0.2, 1}}) do my_context_open = false
			}

			if app.debug_mode_open {
				debug_panel(ui_ctx, &ev_ctx, &anim_ctx)
			}
		}

		roots := ui_layout_tree(ui_ctx)
		for root in roots {
			apply_structural(&anim_ctx, root)
		}
		ui_compute(ui_ctx)
		process_lifecycles(&anim_ctx, ui_ctx.layout)
		update(&anim_ctx.engine, frame_dt)

		visual_cb :: proc(user_data: rawptr, state: ^Retained_State) {
			el := (^Element)(user_data)
			if el == nil do return

			el.resolved_opacity = state.opacity

			if state.has_bg_color do el.style.bg_color = transmute(Color)state.bg_color
			if state.has_text_color do el.style.text_color = transmute(Color)state.text_color
			if state.has_border_color do el.style.border_color = transmute(Color)state.border_color
		}
		for root in roots {
			apply_visual(&anim_ctx, root, visual_cb)
		}

		sdl.SetRenderDrawColor(sdl_rend, 240, 240, 245, 255)
		sdl.RenderClear(sdl_rend)
		render_tree(ui_ctx, sdl_rend, roots)
		sdl.RenderPresent(sdl_rend)
	}
}
