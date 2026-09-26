package UI

import "core:fmt"
import "core:math"
import "core:math/rand"
import sdl "vendor:sdl2"

// --- APPLICATION STATE ---

User_Record :: struct {
	id:          int,
	name_buf:    [dynamic]u8,
	role_idx:    int,
	is_active:   bool,
	theme_color: [4]f32,
	join_date:   [3]int,
}

Showcase_State :: struct {
	// Navigation
	router:            Router_State,
	nav_items:         []string,
	nav_idx:           int,

	// CRUD State (User Directory)
	users:             [dynamic]User_Record,
	selected_user_idx: int,
	role_options:      []string,
	search_buf:        [dynamic]u8,
	combo_open:        bool,
	color_picker_open: bool,
	date_picker_open:  bool,
	modal_open:        bool,

	// Widget Lab State
	lab_tab_idx:       int,
	volume_val:        f32,
	brightness_val:    f32,
	wifi_enabled:      bool,
	bt_enabled:        bool,
	notes_buffer:      Gap_Buffer,
	toast_open:        bool,

	// Overlays
	context_x:         f32,
	context_y:         f32,
	context_open:      bool,
	show_debug:        bool,
}

main :: proc() {
	app := app_init("UI Toolkit Showcase", 1280, 800, {.SHOWN, .ALLOW_HIGHDPI})
	if app == nil do return
	defer app_destroy(app)

	state := Showcase_State {
		nav_items         = {"Dashboard", "User Directory", "Widget Lab"},
		role_options      = {"Administrator", "Editor", "Viewer", "Guest"},
		selected_user_idx = -1,
		volume_val        = 0.65,
		brightness_val    = .8,
		wifi_enabled      = true,
		nav_idx           = 1,
	}
	seed_initial_users(&state)

	gap_buffer_init(&state.notes_buffer)
	defer gap_buffer_destroy(&state.notes_buffer)

	defer {
		for u in state.users {
			delete(u.name_buf)
		}
		delete(state.users)
	}

	for !app.quit {
		app_begin_frame(app)
		defer app_end_frame(app)

		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						bg_color = COLOR_WHITE,
						width = ViewPercent{100},
						height = ViewPercent{100},
					},
				},
			)
			defer element_close(app)

			{
				element_open(
					app,
					{
						style = {
							gap       = 32,
							z_index   = 50,
							width     = Fixed{260},
							direction = .COLUMN,
							height    = Percent{100},
							bg_color  = COLOR_WHITE, //
							padding   = space(32, 24),
							border    = space(0, 1, 0, 0),
						},
					},
				)
				defer element_close(app)

				text(app, "UI Built", user_style = {font_size = 24, text_color = COLOR_BLACK})
				list_view(
					app,
					state.nav_items,
					&state.nav_idx,
					item_style = {border_radius = space(6), padding = space(12, 16)},
					wrapper_style = {border = space(0), bg_color = COLOR_TRANSPARENT},
				)

				spacer(app)

				switch_toggle(app, "Debug Mode", &state.show_debug)
			}

			pages := []Page_Proc{page_dashboard, page_directory}
			router_view(
				app,
				&state.router,
				state.nav_idx,
				pages,
				&state,
				wrapper_style = {padding = space(48), bg_color = COLOR_TRANSPARENT},
			)
		}

		// ---------------------------------------------------------
		// FLOATING OVERLAYS (Rendered last to sit on top)
		// ---------------------------------------------------------

		if state.toast_open {
			element_open(
				app,
				{style = {position = .FIXED, right = 32.0, bottom = 32.0, z_index = 4000}},
			)
			defer element_close(app)

			toast(
				app,
				"System Notification",
				"Your changes have been saved successfully.",
				.SUCCESS,
				&state.toast_open,
			)
		}

		if active, _ := context_menu_begin(
			app,
			state.context_x,
			state.context_y,
			&state.context_open,
		); active {
			defer context_menu_end(app)

			if button(app, "Refresh View", user_style = {text_align = .LEFT}) do state.context_open = false
			if button(app, "System Settings", user_style = {text_align = .LEFT}) do state.context_open = false
		}

		if state.show_debug do debug_panel(app, &state.show_debug)
	}
}

// ==============================================================================
// PAGE 1: DASHBOARD
// ==============================================================================
page_dashboard :: proc(app: ^App, app_state: rawptr) {
	state := (^Showcase_State)(app_state)

	{
		element_open(
			app,
			{style = {gap = 24, direction = .COLUMN, width = Percent{100}, height = Percent{100}}},
		)
		defer element_close(app)

		text(app, "Dashboard Overview", {font_size = 36})
		text(
			app,
			"Welcome to the UI Built showcase. This app demonstrate immediate mode routine, robust data binding, and hardware-accelerated layouts.",
			user_style = {text_color = Color{.4, .4, .4, 1}},
		)

		{
			element_open(app, {style = {direction = .ROW, gap = 24, width = Percent{100}}})
			defer element_close(app)

			_stat_card(
				app,
				"Total Users",
				fmt.tprintf("%d", len(state.users)),
				Color{0.2, 0.5, 0.9, 1.0},
			)

			active_count: u8 = 0
			for u in state.users do if u.is_active do active_count += 1
			_stat_card(
				app,
				"Active Accounts",
				fmt.tprintf("%d", active_count),
				Color{0.2, 0.8, 0.4, 1.0},
			)
		}

		element_open(
			app,
			{
				style = {
					width = Percent{100},
					height = Fixed{1},
					bg_color = Color{0.8, 0.8, 0.8, 1.0},
					margin = space(24, 0),
				},
			},
		); element_close(app)

		@(static) acc_1, acc_2: bool
		if accordion_begin(app, "What is Immediate Mode?", &acc_1) {
			defer accordion_end(app, acc_1)
			text(
				app,
				"Unlike retained-mode interfaces where the UI tree persists in memory and you mutate it via objects, an immediate-mode GUI rebuilds the layout every frame. This completely eliminates state-syncing bugs between your data and your UI.",
				user_style = {font_size = 15, text_color = Color{0.3, 0.3, 0.3, 1.0}},
			)
		}

		if accordion_begin(app, "How does routing work here?", &acc_2) {
			defer accordion_end(app, acc_2)
			text(
				app,
				"The router uses structural animations. When the navigation index changes, the engine fires a tween on the container's X-axis and Opacity. Once the fade-out completes, it swaps the active procedure pointer and slides the new view in.",
				user_style = {font_size = 15, text_color = Color{0.3, 0.3, 0.3, 1.0}},
			)
		}
	}
}

_stat_card :: proc(app: ^App, label, val: string, accent: Color, loc := #caller_location) {
	element_open(
		app,
		{
			style = {
				width = Grow{1},
				padding = space(24),
				direction = .COLUMN,
				bg_color = COLOR_WHITE,
				border_radius = space(8),
				border = space(1, 4, 1, 1),
			},
		},
		loc = loc,
	)
	defer element_close(app)


	text(app, label, {font_size = 14, text_color = Color{0.5, 0.5, 0.5, 1.0}})
	text(app, val, {font_size = 32, text_color = accent})
}

seed_initial_users :: proc(state: ^Showcase_State) {
	names := []string{"Ada Lovelace", "Alan Turing", "Grace Hopper", "John von Neumann"}
	colors := [][4]f32 {
		{0.9, 0.3, 0.4, 1.0},
		{0.2, 0.6, 0.9, 1.0},
		{0.8, 0.4, 0.8, 1.0},
		{0.2, 0.8, 0.5, 1.0},
	}

	for i in 0 ..< 4 {
		u := User_Record {
			id          = 1000 + i,
			role_idx    = i % 2,
			is_active   = i != 3,
			theme_color = colors[i],
			join_date   = {2024, i + 1, 15},
		}
		u.name_buf = make([dynamic]u8, 0, len(names[i]))
		for c in names[i] do append(&u.name_buf, u8(c))
		append(&state.users, u)
	}
}

// ==============================================================================
// PAGE 2: USER DIRECTORY (Master-Detail CRUD)
// ==============================================================================
page_directory :: proc(app: ^App, app_state: rawptr) {
	state := (^Showcase_State)(app_state)

	{
		element_open(
			app,
			{
				style = {
					gap = 24,
					direction = .COLUMN,
					overflow_y = .HIDDEN,
					width = Percent{100},
					height = Percent{100},
				},
			},
		)
		defer element_close(app)

		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						width = Percent{100},
						align_items = .CENTER,
						justify_content = .SPACE_BETWEEN,
					},
				},
			)
			defer element_close(app)

			text(app, "Directory", {font_size = 36})

			if button(app, "Add User", {bg_color = Color{0.15, 0.4, 0.8, 1.0}}) {
				new_user := User_Record {
					id          = rand.int_max(9999),
					role_idx    = 2,
					is_active   = true,
					theme_color = {0.2, 0.8, 0.4, 1.0},
					join_date   = {2026, 9, 23},
				}
				new_user.name_buf = make([dynamic]u8)
				for c in "New Employee" do append(&new_user.name_buf, u8(c))
				append(&state.users, new_user)
				state.selected_user_idx = len(state.users) - 1
			}
		}

		{
			element_open(
				app,
				{
					style = {
						gap = 24,
						direction = .ROW,
						height = Grow{1},
						width = Percent{100},
						overflow_y = .HIDDEN,
					},
				},
			)
			defer element_close(app)

			{
				element_open(
					app,
					{
						style = {
							border = space(1),
							border_radius = space(8),
							width = Percent{20},
							height = Percent{100},
							direction = .COLUMN,
							overflow_y = .HIDDEN,
							bg_color = COLOR_WHITE,
							border_color = Color{0.8, 0.8, 0.8, 1},
						},
					},
				)
				defer element_close(app)

				{
					scroll_id := scroll_begin(
						app,
						ID("scroller"),
						scroll_y = true,
						user_style = {width = Percent{100}, height = Percent{100}},
					)
					defer scroll_end(app, scroll_id)

					for u, i in state.users {
						is_sel := state.selected_user_idx == i
						bg := is_sel ? Color{0.15, 0.4, 0.8, 0.1} : Color{0, 0, 0, 0}
						border_col :=
							is_sel ? Color{0.15, 0.4, 0.8, 1.0} : Color{0.9, 0.9, 0.9, 1.0}

						{
							element_open(
								app,
								{
									id = ID(fmt.tprintf("usr_row_%d", u.id)),
									style = {
										width = Percent{100},
										height = Fit(true),
										direction = .COLUMN,
									},
								},
							)
							defer element_close(app)

							if button(
								app,
								id = CASCADE_ID,
								user_style = {
									width = Percent{100},
									height = Fixed{60},
									padding = space(12),
									bg_color = bg,
									border = space(0, 0, 1, 0),
									border_color = border_col,
									border_radius = space(0),
								},
							) {state.selected_user_idx = i}

							{
								element_open(
									app,
									{
										id = CASCADE_ID,
										style = {
											position = .ABSOLUTE,
											left = 12,
											top = 12,
											direction = .ROW,
											gap = 12,
											align_items = .CENTER,
										},
									},
								)
								defer element_close(app)

								// Avatar Circle
								element_open(
									app,
									{
										id = CASCADE_ID,
										style = {
											width = Fixed{36},
											height = Fixed{36},
											border_radius = space(18),
											bg_color = transmute(Color)u.theme_color,
										},
									},
								); element_close(app)

								{
									element_open(
										app,
										{
											id = CASCADE_ID,
											style = {
												direction = .COLUMN,
												justify_content = .CENTER,
											},
										},
									)
									defer element_close(app)

									text(
										app,
										id = CASCADE_ID,
										text = string(u.name_buf[:]),
										user_style = {
											font_size = 16,
											text_color = Color{0.1, 0.1, 0.1, 1},
										},
									)
									text(
										app,
										id = CASCADE_ID,
										text = state.role_options[u.role_idx],
										user_style = {
											font_size = 12,
											text_color = Color{0.5, 0.5, 0.5, 1},
										},
									)
								}
							}
						}
					}
				}
			}
		}
	}
}
