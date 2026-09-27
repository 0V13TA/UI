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

RSS_Article :: struct {
	title:   string,
	date:    string,
	content: string,
	is_read: bool,
}

RSS_Feed :: struct {
	title:    string,
	articles: [dynamic]RSS_Article,
}

Showcase_State :: struct {
	// Navigation
	router:                   Router_State,
	nav_items:                []string,
	nav_idx:                  int,

	// CRUD State (User Directory)
	users:                    [dynamic]User_Record,
	selected_user_idx:        int,
	role_options:             []string,
	search_buf:               [dynamic]u8,
	combo_open:               bool,
	color_picker_open:        bool,
	date_picker_open:         bool,
	modal_open:               bool,

	// Widget Lab State
	lab_tab_idx:              int,
	volume_val:               f32,
	brightness_val:           f32,
	wifi_enabled:             bool,
	bt_enabled:               bool,
	notes_buffer:             Gap_Buffer,
	toast_open:               bool,

	// Dashboard State
	dashboard_range_idx:      int,
	dashboard_paused:         bool,
	dashboard_clock_ms:       u32,
	dashboard_refresh_count:  int,

	// RSS Reader State
	rss_feeds:                [dynamic]RSS_Feed,
	rss_feed_names:           [dynamic]string,
	rss_selected_feed_idx:    int,
	rss_selected_article_idx: int,
	rss_feed_dropdown_open:   bool,

	// Overlays
	context_x:                f32,
	context_y:                f32,
	context_open:             bool,
	show_debug:               bool,

	// Interaction demo state
	interaction_touch_count:  int,
	interaction_drop_count:   int,
	interaction_dragging:     bool,
}

main :: proc() {
	app := app_init(
		"Ovieta OS - UI Toolkit Showcase",
		1280,
		800,
		sdl.WINDOW_SHOWN | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_RESIZABLE,
	)
	if app == nil do return
	defer app_destroy(app)

	state := new(Showcase_State)
	defer free(state)
	state.nav_items = []string{"Dashboard", "User Directory", "Widget Lab", "RSS Reader", "Interactions"}
	state.role_options = []string{"Administrator", "Editor", "Viewer", "Guest"}
	state.selected_user_idx = -1
	state.volume_val = 0.65
	state.brightness_val = 0.8
	state.wifi_enabled = true
	state.rss_selected_feed_idx = 0
	state.rss_selected_article_idx = -1

	gap_buffer_init(&state.notes_buffer)
	defer gap_buffer_destroy(&state.notes_buffer)

	seed_initial_users(state)
	seed_initial_rss(state)

	defer {
		for user in state.users do delete(user.name_buf)
		delete(state.users)
		for f in state.rss_feeds do delete(f.articles)
		delete(state.rss_feeds)
		delete(state.rss_feed_names)
	}

	for !app.quit {
		app_begin_frame(app)
		if !state.dashboard_paused do state.dashboard_clock_ms = sdl.GetTicks()

		// ---------------------------------------------------------
		// ROOT LAYOUT (Horizontal Split: Sidebar + Main Content)
		// ---------------------------------------------------------
		{
			element_open(
				app,
				Element {
					style = {
						direction = .ROW,
						width = ViewPercent{100},
						height = ViewPercent{100},
						bg_color = Color{0.96, 0.96, 0.98, 1.0},
					},
				},
			)
			defer element_close(app)

			{
				element_open(
					app,
					Element {
						style = {
							direction    = .COLUMN,
							width        = Fixed{260},
							height       = Percent{100},
							bg_color     = Color{1.0, 1.0, 1.0, 1.0},
							border       = space(0, 1, 0, 0),
							border_color = Color{0.85, 0.85, 0.85, 1.0},
							padding      = space(32, 24),
							gap          = 32,
							z_index      = 50, // Keep shadow/borders above content
						},
					},
				)
				defer element_close(app)

				text(
					app,
					"Ovieta OS",
					user_style = {font_size = 24, text_color = Color{0.1, 0.1, 0.1, 1.0}},
				)

				list_view(
					app,
					state.nav_items,
					&state.nav_idx,
					wrapper_style = {border = space(0), bg_color = COLOR_TRANSPARENT},
					item_style = {border_radius = space(6), padding = space(12, 16)},
				)

				{
					element_open(app, {style = {height = Grow{1}}})
					defer element_close(app) // Spacer
				}

				switch_toggle(app, "Debug Mode", &state.show_debug)

			} // End Sidebar

			// --- 2. MAIN CONTENT ROUTER ---
			pages := []Page_Proc{page_dashboard, page_directory, page_widget_lab, page_rss_reader, page_interactions}
			router_view(
				app,
				&state.router,
				state.nav_idx,
				pages,
				state,
				wrapper_style = {padding = space(48), bg_color = COLOR_TRANSPARENT},
			)

		} // End Root Layout

		// ---------------------------------------------------------
		// FLOATING OVERLAYS (Rendered last to sit on top)
		// ---------------------------------------------------------
		if state.toast_open {
			{
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
		}

		if active, _ := context_menu_begin(
			app,
			state.context_x,
			state.context_y,
			&state.context_open,
		); active {
			if button(app, "Refresh View", user_style = {text_align = .LEFT}) do state.context_open = false
			if button(app, "System Settings", user_style = {text_align = .LEFT}) do state.context_open = false
			context_menu_end(app, true)
		}

		if state.show_debug do debug_panel(app, &state.show_debug)

		app_end_frame(app)
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
			{
				style = {
					direction = .COLUMN,
					gap = 20,
					width = Percent{100},
					height = Percent{100},
					overflow_y = .SCROLL,
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
						align_items = .CENTER,
						justify_content = .SPACE_BETWEEN,
						width = Percent{100},
					},
				},
			)
			defer element_close(app)

			{
				element_open(app, {style = {direction = .COLUMN, gap = 4}})
				defer element_close(app)
				text(app, "System Overview", user_style = {font_size = 32})
				text(
					app,
					"Demo environment · animated sample telemetry",
					user_style = {font_size = 14, text_color = Color{0.45, 0.48, 0.54, 1}},
				)
			}

			{
				element_open(app, {style = {direction = .ROW, gap = 10, align_items = .CENTER}})
				defer element_close(app)
				if button(
					app,
					state.dashboard_paused ? "Resume Live" : "Pause Live",
					user_style = {
						bg_color = state.dashboard_paused ? Color{0.92, 0.93, 0.95, 1} :
							Color{0.88, 0.95, 0.91, 1},
						text_color = Color{0.14, 0.35, 0.24, 1},
					},
				) {
					state.dashboard_paused = !state.dashboard_paused
					if !state.dashboard_paused do state.dashboard_clock_ms = sdl.GetTicks()
				}
				if button(app, "Refresh", user_style = {bg_color = Color{0.16, 0.38, 0.78, 1}}) {
					state.dashboard_refresh_count += 1
					state.dashboard_clock_ms = sdl.GetTicks()
				}
			}
		}

		{
			element_open(app, {style = {direction = .ROW, gap = 16, width = Percent{100}}})
			defer element_close(app)
			_stat_card(app, "Requests / min", "2,481", Color{0.16, 0.38, 0.78, 1})
			_stat_card(app, "Avg. latency", "84 ms", Color{0.53, 0.34, 0.78, 1})
			_stat_card(app, "Error rate", "0.12%", Color{0.13, 0.62, 0.38, 1})
			_stat_card(app, "Active sessions", "1,204", Color{0.86, 0.52, 0.12, 1})
		}

		{
			element_open(app, {style = {direction = .ROW, gap = 16, width = Percent{100}}})
			defer element_close(app)

			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							width = Grow{1},
							height = Fixed{310},
							gap = 12,
							padding = space(20),
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.88, 0.89, 0.92, 1},
							border_radius = space(8),
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
								align_items = .CENTER,
								justify_content = .SPACE_BETWEEN,
								width = Percent{100},
							},
						},
					)
					defer element_close(app)
					{
						element_open(app, {style = {direction = .COLUMN, gap = 3}})
						defer element_close(app)
						text(app, "Traffic & resource usage", user_style = {font_size = 18})
						text(
							app,
							"CPU utilization and inbound requests",
							user_style = {font_size = 12, text_color = Color{0.5, 0.52, 0.57, 1}},
						)
					}
					tabs(
						app,
						[]string{"1 hour", "6 hours", "24 hours"},
						&state.dashboard_range_idx,
						salt = "dashboard_range",
					)
				}

				canvas(
					app,
					_dashboard_chart,
					state,
					user_style = {
						width = Percent{100},
						height = Grow{1},
						bg_color = Color{0.99, 0.99, 1, 1},
						border_radius = space(4),
					},
					salt = "dashboard_traffic_chart",
				)
				{
					element_open(app, {style = {direction = .ROW, gap = 18, align_items = .CENTER}})
					defer element_close(app)
					_dashboard_legend(app, "CPU", Color{0.16, 0.38, 0.78, 1})
					_dashboard_legend(app, "Requests", Color{0.13, 0.68, 0.55, 1})
					text(
						app,
						fmt.tprintf(
							"Manual refreshes: %d",
							state.dashboard_refresh_count,
						),
						user_style = {font_size = 12, text_color = Color{0.55, 0.57, 0.61, 1}},
					)
				}
			}

			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							width = Fixed{230},
							gap = 12,
							padding = space(20),
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.88, 0.89, 0.92, 1},
							border_radius = space(8),
						},
					},
				)
				defer element_close(app)
				text(app, "Service health", user_style = {font_size = 18})
				_dashboard_service(app, "API Gateway", "Operational", Color{0.12, 0.66, 0.38, 1})
				_dashboard_service(app, "Auth Service", "Operational", Color{0.12, 0.66, 0.38, 1})
				_dashboard_service(app, "Media Worker", "Degraded", Color{0.88, 0.55, 0.12, 1})
				_dashboard_service(app, "Database", "Operational", Color{0.12, 0.66, 0.38, 1})
				{
					element_open(app, {style = {height = Fixed{1}, bg_color = Color{0.91, 0.92, 0.94, 1}}})
					defer element_close(app)
				}
				text(app, "99.98%", user_style = {font_size = 28, text_color = Color{0.12, 0.55, 0.34, 1}})
				text(
					app,
					"30-day availability",
					user_style = {font_size = 12, text_color = Color{0.5, 0.52, 0.57, 1}},
				)
			}
		}

		{
			element_open(
				app,
				{
					style = {
						direction = .COLUMN,
						width = Percent{100},
						gap = 12,
						padding = space(18, 20),
						bg_color = Color{1, 1, 1, 1},
						border = space(1),
						border_color = Color{0.88, 0.89, 0.92, 1},
						border_radius = space(8),
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
							justify_content = .SPACE_BETWEEN,
							align_items = .CENTER,
							width = Percent{100},
						},
					},
				)
				defer element_close(app)
				text(app, "Recent activity", user_style = {font_size = 18})
				text(app, "View all", user_style = {font_size = 13, text_color = Color{0.16, 0.38, 0.78, 1}})
			}
			_dashboard_activity(app, "Deployment completed", "api-gateway · v2.8.1 deployed to production", "2 min ago", Color{0.12, 0.66, 0.38, 1})
			_dashboard_activity(app, "Elevated latency detected", "media-worker · p95 latency above 400 ms", "18 min ago", Color{0.88, 0.55, 0.12, 1})
			_dashboard_activity(app, "Database backup finished", "primary-db · snapshot verified successfully", "42 min ago", Color{0.16, 0.38, 0.78, 1})
		}
	}
}

@(private = "file")
_dashboard_chart :: proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
	state := (^Showcase_State)(data)
	left := bounds.x + 42
	right := bounds.x + bounds.w - 12
	top := bounds.y + 10
	bottom := bounds.y + bounds.h - 25
	if right <= left || bottom <= top do return

	sdl.SetRenderDrawColor(renderer, 229, 232, 238, 255)
	for row in 0 ..< 4 {
		y := top + (bottom - top) * i32(row) / 3
		sdl.RenderDrawLine(renderer, left, y, right, y)
	}

	for label in 0 ..< 4 {
		y := top + (bottom - top) * i32(label) / 3
		sdl.SetRenderDrawColor(renderer, 175, 180, 190, 255)
		sdl.RenderDrawLine(renderer, left - 4, y, left, y)
	}

	seconds := f32(state.dashboard_clock_ms) / 1000.0
	range_scale := f32(state.dashboard_range_idx + 1)
	sdl.SetRenderDrawColor(renderer, 31, 92, 190, 255)
	for sample in 0 ..< 63 {
		x0 := left + (right - left) * i32(sample) / 63
		x1 := left + (right - left) * i32(sample + 1) / 63
		t0 := f32(sample) / 63
		t1 := f32(sample + 1) / 63
		v0 := 0.54 + 0.19 * math.sin(t0 * 11 * range_scale + seconds * 0.9) +
		      0.08 * math.sin(t0 * 31 + seconds * 0.27)
		v1 := 0.54 + 0.19 * math.sin(t1 * 11 * range_scale + seconds * 0.9) +
		      0.08 * math.sin(t1 * 31 + seconds * 0.27)
		y0 := bottom - i32(v0 * f32(bottom - top))
		y1 := bottom - i32(v1 * f32(bottom - top))
		sdl.RenderDrawLine(renderer, x0, y0, x1, y1)
	}

	sdl.SetRenderDrawColor(renderer, 20, 166, 132, 255)
	for sample in 0 ..< 63 {
		x0 := left + (right - left) * i32(sample) / 63
		x1 := left + (right - left) * i32(sample + 1) / 63
		t0 := f32(sample) / 63
		t1 := f32(sample + 1) / 63
		v0 := 0.28 + 0.12 * math.sin(t0 * 8 * range_scale + seconds * 0.62 + 1.3) +
		      0.05 * math.sin(t0 * 24 + seconds * 0.4)
		v1 := 0.28 + 0.12 * math.sin(t1 * 8 * range_scale + seconds * 0.62 + 1.3) +
		      0.05 * math.sin(t1 * 24 + seconds * 0.4)
		y0 := bottom - i32(v0 * f32(bottom - top))
		y1 := bottom - i32(v1 * f32(bottom - top))
		sdl.RenderDrawLine(renderer, x0, y0, x1, y1)
	}
}

@(private = "file")
_dashboard_legend :: proc(app: ^App, label: string, color: Color) {
	element_open(app, {style = {direction = .ROW, gap = 7, align_items = .CENTER}})
	defer element_close(app)
	element_open(
		app,
		{
			style = {
				width = Fixed{9},
				height = Fixed{9},
				border_radius = space(5),
				bg_color = color,
			},
		},
	)
	element_close(app)
	text(app, label, user_style = {font_size = 12, text_color = Color{0.35, 0.37, 0.42, 1}})
}

@(private = "file")
_dashboard_service :: proc(app: ^App, name, status: string, color: Color) {
	element_open(app, {style = {direction = .ROW, gap = 8, align_items = .CENTER}})
	defer element_close(app)
	element_open(
		app,
		{
			style = {
				width = Fixed{8},
				height = Fixed{8},
				border_radius = space(4),
				bg_color = color,
			},
		},
	)
	element_close(app)
	element_open(app, {style = {direction = .COLUMN, gap = 2}})
	defer element_close(app)
	text(app, name, user_style = {font_size = 13})
	text(app, status, user_style = {font_size = 11, text_color = Color{0.48, 0.5, 0.55, 1}})
}

@(private = "file")
_dashboard_activity :: proc(app: ^App, title, detail, time: string, color: Color) {
	element_open(
		app,
		{
			style = {
				direction = .ROW,
				gap = 12,
				align_items = .CENTER,
				width = Percent{100},
			},
		},
	)
	defer element_close(app)
	element_open(
		app,
		{
			style = {
				width = Fixed{8},
				height = Fixed{8},
				border_radius = space(4),
				bg_color = color,
			},
		},
	)
	element_close(app)
	{
		element_open(app, {style = {direction = .COLUMN, gap = 2, width = Grow{1}}})
		defer element_close(app)
		text(app, title, user_style = {font_size = 13})
		text(app, detail, user_style = {font_size = 11, text_color = Color{0.48, 0.5, 0.55, 1}})
	}
	text(app, time, user_style = {font_size = 11, text_color = Color{0.55, 0.57, 0.61, 1}})
}

@(private = "file")
_stat_card :: proc(app: ^App, label, val: string, accent: Color) {

	{
		element_open(
			app,
			{
				style = {
					direction = .COLUMN,
					width = Grow{1},
					padding = space(24),
					bg_color = Color{1, 1, 1, 1},
					border_color = Color{0.9, 0.9, 0.9, 1},
					border_radius = space(8),
					border = space(1, 4, 1, 1),
				},
			},
		)
		defer element_close(app)

		text(app, label, user_style = {font_size = 14, text_color = Color{0.5, 0.5, 0.5, 1.0}})
		text(app, val, user_style = {font_size = 32, text_color = accent})

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
					direction = .COLUMN,
					gap = 24,
					width = Percent{100},
					height = Percent{100},
					overflow_y = .HIDDEN,
				},
			},
		)
		defer element_close(app)

		// Page Header & Actions
		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						justify_content = .SPACE_BETWEEN,
						align_items = .CENTER,
						width = Percent{100},
					},
				},
			)
			defer element_close(app)
			text(app, "Directory", user_style = {font_size = 36})
			if button(app, "+ Add User", user_style = {bg_color = Color{0.15, 0.4, 0.8, 1.0}}) {
				new_user := User_Record {
					id          = rand.int_max(9999),
					role_idx    = 2,
					is_active   = true,
					theme_color = {0.2, 0.8, 0.4, 1.0},
					join_date   = {2026, 9, 23},
				}
				new_user.name_buf = make([dynamic]u8, 0, len("New Employee"))
				for c in "New Employee" do append(&new_user.name_buf, u8(c))
				append(&state.users, new_user)
				state.selected_user_idx = len(state.users) - 1
			}
		}

		// Master-Detail Split Layout
		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						gap = 24,
						width = Percent{100},
						height = Grow{1},
						overflow_y = .HIDDEN,
					},
				},
			)
			defer element_close(app)

			// LEFT: Master List
			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							width = Fixed{300},
							height = Percent{100},
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.8, 0.8, 0.8, 1},
							border_radius = space(8),
							overflow_y = .HIDDEN,
						},
					},
				)
				defer element_close(app)

				{
					scroll_id := scroll_begin(
						app,
						scroll_y = true,
						user_style = {width = Percent{100}, height = Percent{100}},
					)
					defer scroll_end(app, scroll_id)

					for u, i in state.users {
						is_sel := state.selected_user_idx == i
						bg := is_sel ? Color{0.15, 0.4, 0.8, 0.1} : Color{0, 0, 0, 0}
						border_col :=
							is_sel ? Color{0.15, 0.4, 0.8, 1.0} : Color{0.9, 0.9, 0.9, 1.0}

						if button(
							app,
							id = ID(ID("user_row"), fmt.tprintf("%d", u.id)),
							user_style = {
								width = Percent{100},
								height = Fixed{60},
								padding = space(12),
								bg_color = bg,
								border = space(0, 0, 1, 0),
								border_color = border_col,
								border_radius = space(0),
							},
						) {
							state.selected_user_idx = i
						}

						if prev, ok :=
							   app.ui.layout.prev_all_boxes[ID(ID("user_row"), fmt.tprintf("%d", u.id))];
						   ok {
							overlay_offset := list_item_overlay_offset(prev, 12, 12)
							{
								element_open(
									app,
									{
										style = {
											position = .ABSOLUTE,
											left = overlay_offset[0],
											top = overlay_offset[1],
											direction = .ROW,
											gap = 12,
											align_items = .CENTER,
										},
									},
								)
								defer element_close(app)

								// Avatar Circle
								{
									element_open(
										app,
										{
											style = {
												width = Fixed{36},
												height = Fixed{36},
												border_radius = space(18),
												bg_color = transmute(Color)u.theme_color,
											},
										},
									)
									defer element_close(app)
								}

								{
									element_open(
										app,
										{style = {direction = .COLUMN, justify_content = .CENTER}},
									)
									defer element_close(app)
									text(
										app,
										string(u.name_buf[:]),
										user_style = {
											font_size = 16,
											text_color = Color{0.1, 0.1, 0.1, 1},
										},
									)
									text(
										app,
										state.role_options[u.role_idx],
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
			} // End Left Panel

			// RIGHT: Detail Form
			if state.selected_user_idx >= 0 && state.selected_user_idx < len(state.users) {
				u := &state.users[state.selected_user_idx]

				{
					element_open(
						app,
						{
							style = {
								direction = .COLUMN,
								width = Grow{1},
								height = Percent{100},
								bg_color = Color{1, 1, 1, 1},
								border = space(1),
								border_color = Color{0.8, 0.8, 0.8, 1},
								border_radius = space(8),
								padding = space(32),
								gap = 24,
								overflow_y = .SCROLL,
							},
						},
					)
					defer element_close(app)

					text(app, "Edit User", user_style = {font_size = 24})

					text(
						app,
						"Full Name",
						user_style = {font_size = 14, text_color = Color{0.4, 0.4, 0.4, 1.0}},
					)
					text_input(
						app,
						&u.name_buf,
						placeholder = "Enter name...",
						salt = "detail_name",
					)

					text(
						app,
						"Role Assignment",
						user_style = {font_size = 14, text_color = Color{0.4, 0.4, 0.4, 1.0}},
					)
					combobox(
						app,
						"Search roles...",
						state.role_options,
						&state.search_buf,
						&u.role_idx,
						&state.combo_open,
						salt = "detail_role",
					)

					{
						element_open(
							app,
							{
								style = {
									direction = .ROW,
									justify_content = .SPACE_BETWEEN,
									align_items = .CENTER,
									width = Percent{100},
									margin = space(12, 0),
								},
							},
						)
						defer element_close(app)
						text(app, "Account Active", user_style = {font_size = 16})
						switch_toggle(app, "", &u.is_active, salt = "detail_active")
					}

					{
						element_open(
							app,
							{style = {direction = .ROW, gap = 48, width = Percent{100}}},
						)
						defer element_close(app)
						color_picker(
							app,
							"Profile Accent",
							&u.theme_color,
							&state.color_picker_open,
							salt = "detail_color",
						)
						date_picker(
							app,
							"Start Date",
							&u.join_date,
							&state.date_picker_open,
							salt = "detail_date",
						)
					}

					// Delete Button at the bottom
					{
						element_open(app, {style = {height = Grow{1}}})
						defer element_close(app) // Pushes delete to bottom
					}

					{
						element_open(
							app,
							{
								style = {
									direction = .ROW,
									justify_content = .END,
									width = Percent{100},
								},
							},
						)
						defer element_close(app)
						if button(
							app,
							"Delete User",
							user_style = {
								bg_color = Color{0.9, 0.2, 0.2, 1.0},
								text_color = Color{1, 1, 1, 1},
							},
						) {
							state.modal_open = true
						}
					}

				} // End Right Panel
			} else {
				// Empty State
				{
					element_open(
						app,
						{
							style = {
								direction = .COLUMN,
								justify_content = .CENTER,
								align_items = .CENTER,
								width = Grow{1},
								height = Percent{100},
								bg_color = Color{1, 1, 1, 1},
								border = space(1),
								border_color = Color{0.8, 0.8, 0.8, 1},
								border_radius = space(8),
							},
						},
					)
					defer element_close(app)
					text(
						app,
						"Select a user to view details.",
						user_style = {text_color = Color{0.5, 0.5, 0.5, 1.0}},
					)
				}
			}

		} // End Split

		// --- DELETE CONFIRMATION MODAL ---
		if modal_begin(app, &state.modal_open) {
			text(
				app,
				"Confirm Deletion",
				user_style = {font_size = 24, text_color = Color{0.9, 0.2, 0.2, 1.0}},
			)
			text(
				app,
				"Are you sure you want to delete this user? This action cannot be undone.",
				user_style = {text_color = Color{0.3, 0.3, 0.3, 1.0}},
			)

			{
				element_open(
					app,
					{
						style = {
							direction = .ROW,
							gap = 16,
							justify_content = .END,
							width = Percent{100},
							margin = space(16, 0, 0, 0),
						},
					},
				)
				defer element_close(app)
				if button(
					app,
					"Cancel",
					user_style = {
						bg_color = Color{0.9, 0.9, 0.9, 1.0},
						text_color = Color{0.1, 0.1, 0.1, 1.0},
					},
				) {state.modal_open = false}

				if button(
					app,
					"Delete Forever",
					user_style = {bg_color = Color{0.9, 0.2, 0.2, 1.0}},
				) {
					delete(state.users[state.selected_user_idx].name_buf)
					ordered_remove(&state.users, state.selected_user_idx)
					state.selected_user_idx = -1
					state.modal_open = false
					state.toast_open = true
				}
			}
			modal_end(app, true)
		}

	} // End Page
}

// ==============================================================================
// PAGE 3: WIDGET LAB
// ==============================================================================
page_widget_lab :: proc(app: ^App, app_state: rawptr) {
	state := (^Showcase_State)(app_state)


	{
		element_open(
			app,
			{style = {direction = .COLUMN, gap = 24, width = Percent{100}, height = Percent{100}}},
		)
		defer element_close(app)

		text(app, "Widget Laboratory", user_style = {font_size = 36})

		tabs(
			app,
			[]string{"Gap Buffer Textarea", "Sliders & Progress", "Canvas Demo"},
			&state.lab_tab_idx,
		)

		{
			element_open(
				app,
				{
					style = {
						direction = .COLUMN,
						width = Percent{100},
						height = Grow{1},
						bg_color = Color{1, 1, 1, 1},
						border = space(1),
						border_color = Color{0.8, 0.8, 0.8, 1},
						border_radius = space(0, 8, 8, 8),
						padding = space(32),
						gap = 24,
					},
				},
			)
			defer element_close(app)

			if state.lab_tab_idx == 0 {
				text(app, "Layout-Aware Text Area", user_style = {font_size = 20})
				text(
					app,
					"This textarea binds to a Gap_Buffer, handling visual text wrapping, text selection, and mouse-click-to-seek natively. Try typing a very long paragraph.",
					user_style = {text_color = Color{0.5, 0.5, 0.5, 1.0}},
				)

				textarea(
					app,
					&state.notes_buffer,
					placeholder = "Start typing your notes here...",
					wrapper_style = {height = Grow{1}},
				)
			} else if state.lab_tab_idx == 1 {
				text(app, "Hardware Controls", user_style = {font_size = 20})

				// Volume Slider
				{
					element_open(
						app,
						{
							style = {
								direction = .ROW,
								gap = 16,
								align_items = .CENTER,
								width = Percent{100},
							},
						},
					)
					defer element_close(app)
					text(app, "Vol", user_style = {width = Fixed{40}})
					slider(app, &state.volume_val, 0.0, 1.0, wrapper_style = {width = Grow{1}})
					text(
						app,
						fmt.tprintf("%d%%", int(state.volume_val * 100)),
						user_style = {width = Fixed{50}, text_align = .RIGHT},
					)
				}

				// Brightness Slider
				{
					element_open(
						app,
						{
							style = {
								direction = .ROW,
								gap = 16,
								align_items = .CENTER,
								width = Percent{100},
							},
						},
					)
					defer element_close(app)
					text(app, "Lux", user_style = {width = Fixed{40}})
					slider(
						app,
						&state.brightness_val,
						0.0,
						1.0,
						wrapper_style = {width = Grow{1}},
						fill_style = {bg_color = Color{0.9, 0.7, 0.1, 1.0}},
						thumb_style = {bg_color = Color{0.9, 0.8, 0.2, 1.0}},
						salt = "lux_slider",
					)
					text(
						app,
						fmt.tprintf("%d%%", int(state.brightness_val * 100)),
						user_style = {width = Fixed{50}, text_align = .RIGHT},
					)
				}

				{
					element_open(
						app,
						{
							style = {
								width = Percent{100},
								height = Fixed{1},
								bg_color = Color{0.9, 0.9, 0.9, 1.0},
								margin = space(16, 0),
							},
						},
					)
					defer element_close(app)
				}

				// Progress & Spinner
				text(app, "Background Task Progress")
				progress_bar(
					app,
					state.brightness_val,
					wrapper_style = {height = Fixed{12}, border_radius = space(6)},
					fill_style = {bg_color = Color{0.2, 0.8, 0.4, 1.0}},
				)

				{
					element_open(
						app,
						{
							style = {
								direction = .ROW,
								gap = 12,
								align_items = .CENTER,
								margin = space(16, 0),
							},
						},
					)
					defer element_close(app)
					spinner(app)
					text(
						app,
						"Syncing to cloud...",
						user_style = {text_color = Color{0.5, 0.5, 0.5, 1.0}},
					)
				}

			} else if state.lab_tab_idx == 2 {
				text(app, "Custom Canvas API", user_style = {font_size = 20})
				text(
					app,
					"The canvas element passes the layout-resolved SDL.Rect to your custom draw procedure, automatically handling clipping.",
					user_style = {text_color = Color{0.5, 0.5, 0.5, 1.0}},
				)

				canvas(app, proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr) {
						time_s := f32(sdl.GetTicks()) / 1000.0
						cx := bounds.x + bounds.w / 2
						cy := bounds.y + bounds.h / 2

						for i in 0 ..< 20 {
							offset := f32(i) * 0.2
							r := i32(math.sin(time_s + offset) * 100.0 + 150.0)
							sdl.SetRenderDrawColor(renderer, u8(100 + i * 5), 150, 255, 255)
							rect := sdl.Rect{cx - r / 2, cy - r / 2, r, r}
							sdl.RenderDrawRect(renderer, &rect)
						}
					}, user_style = {
						width = Percent{100},
						height = Grow{1},
						border = space(1),
						border_color = Color{0.8, 0.8, 0.8, 1},
					})
			}

		} // End Tab Content
	} // End Page
}

// ==============================================================================
// PAGE 4: RSS READER
// ==============================================================================
page_rss_reader :: proc(app: ^App, app_state: rawptr) {
	state := (^Showcase_State)(app_state)

	{
		element_open(
			app,
			{
				style = {
					direction = .COLUMN,
					gap = 24,
					width = Percent{100},
					height = Percent{100},
					overflow_y = .HIDDEN,
				},
			},
		)
		defer element_close(app)

		// Header
		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						justify_content = .SPACE_BETWEEN,
						align_items = .CENTER,
						width = Percent{100},
					},
				},
			)
			defer element_close(app)
			text(app, "RSS Reader", user_style = {font_size = 36})
		}

		// Split Layout
		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						gap = 24,
						width = Percent{100},
						height = Grow{1},
						overflow_y = .HIDDEN,
					},
				},
			)
			defer element_close(app)

			// Left Panel (Feeds & Articles)
			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							width = Fixed{350},
							height = Percent{100},
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.8, 0.8, 0.8, 1},
							border_radius = space(8),
							overflow_y = .HIDDEN,
						},
					},
				)
				defer element_close(app)

				// Feed Selector
				{
					element_open(
						app,
						{
							style = {
								width   = Percent{100},
								padding = space(16),
								border = space(0, 0, 1, 0),
								border_color = Color{0.9, 0.9, 0.9, 1},
							},
						},
					)
					defer element_close(app)
					dropdown(
						app,
						"Select Feed",
						state.rss_feed_names[:],
						&state.rss_selected_feed_idx,
						&state.rss_feed_dropdown_open,
						wrapper_style = {width = Percent{100}},
					)
				}

				// Article List
				{
					scroll_id := scroll_begin(
						app,
						scroll_y = true,
						user_style = {width = Percent{100}, height = Grow{1}},
					)
					defer scroll_end(app, scroll_id)
					if state.rss_selected_feed_idx >= 0 &&
					   state.rss_selected_feed_idx < len(state.rss_feeds) {
						feed := &state.rss_feeds[state.rss_selected_feed_idx]
						for &art, i in feed.articles {
							is_sel := state.rss_selected_article_idx == i
							bg := is_sel ? Color{0.15, 0.4, 0.8, 0.1} : Color{0, 0, 0, 0}
							border_col :=
								is_sel ? Color{0.15, 0.4, 0.8, 1.0} : Color{0.9, 0.9, 0.9, 1.0}

							if button(
								app,
								id = ID(
									ID("rss_article"),
									fmt.tprintf("%d:%d", state.rss_selected_feed_idx, i),
								),
								user_style = {
									width = Percent{100},
									height = Fit(true),
									padding = space(16),
									bg_color = bg,
									border = space(0, 0, 1, 0),
									border_color = border_col,
									border_radius = space(0),
									text_align = .LEFT,
								},
							) {
								state.rss_selected_article_idx = i
								art.is_read = true
							}

							// Overlay the title and date cleanly over the structural button
							if prev, ok :=
								   app.ui.layout.prev_all_boxes[ID(
									   ID("rss_article"),
									   fmt.tprintf("%d:%d", state.rss_selected_feed_idx, i),
								   )];
							   ok {
								overlay_offset := list_item_overlay_offset(prev, 16, 12)
								{
									element_open(
										app,
										{
											style = {
												position = .ABSOLUTE,
												left = overlay_offset[0],
												top = overlay_offset[1],
												direction = .COLUMN,
												gap = 4,
												width = Fixed{prev.computed_width - 32},
											},
										},
									)
									defer element_close(app)
									title_col :=
										art.is_read ? Color{0.4, 0.4, 0.4, 1} : Color{0.1, 0.1, 0.1, 1}
									text(
										app,
										art.title,
										user_style = {
											font_size = 16,
											text_color = title_col,
											text_wrap = .NONE,
										},
									)
									text(
										app,
										art.date,
										user_style = {
											font_size = 12,
											text_color = Color{0.6, 0.6, 0.6, 1},
										},
									)
								}
							}
						}
					}
				}
			} // End Left Panel

			// Right Panel (Article Content)
			if state.rss_selected_feed_idx >= 0 && state.rss_selected_article_idx >= 0 {
				feed := &state.rss_feeds[state.rss_selected_feed_idx]
				if state.rss_selected_article_idx < len(feed.articles) {
					art := &feed.articles[state.rss_selected_article_idx]

					{
						element_open(
							app,
							{
								style = {
									direction     = .COLUMN,
									width         = Grow{1},
									height        = Percent{100},
									bg_color      = Color{1, 1, 1, 1},
									border        = space(1),
									border_color  = Color{0.8, 0.8, 0.8, 1},
									border_radius = space(8),
									padding       = space(32),
									gap           = 16,
									overflow_y    = .HIDDEN, // Inner scroll handling bounds
								},
							},
						)
						defer element_close(app)

						{
							content_scroll := scroll_begin(
								app,
								scroll_y = true,
								user_style = {
									width = Percent{100},
									height = Percent{100},
									direction = .COLUMN,
									gap = 16,
								},
							)
							defer scroll_end(app, content_scroll)

							text(
								app,
								art.title,
								user_style = {
									font_size = 28,
									text_color = Color{0.1, 0.1, 0.1, 1},
								},
							)
							text(
								app,
								fmt.tprintf("Published: %s", art.date),
								user_style = {
									font_size = 14,
									text_color = Color{0.5, 0.5, 0.5, 1},
								},
							)

							{
								element_open(
									app,
									{
										style = {
											width = Percent{100},
											height = Fixed{1},
											bg_color = Color{0.9, 0.9, 0.9, 1},
											margin = space(8, 0),
										},
									},
								)
								defer element_close(app)
							}

							text(
								app,
								art.content,
								user_style = {
									font_size = 16,
									text_color = Color{0.2, 0.2, 0.2, 1},
									text_wrap = .WORD,
								},
							)

						}
					}
				}
			} else {
				// Empty State
				{
					element_open(
						app,
						{
							style = {
								direction = .COLUMN,
								justify_content = .CENTER,
								align_items = .CENTER,
								width = Grow{1},
								height = Percent{100},
								bg_color = Color{1, 1, 1, 1},
								border = space(1),
								border_color = Color{0.8, 0.8, 0.8, 1},
								border_radius = space(8),
							},
						},
					)
					defer element_close(app)
					text(
						app,
						"Select an article to read.",
						user_style = {text_color = Color{0.5, 0.5, 0.5, 1.0}},
					)
				}
			}

		} // End Split Layout
	} // End Page
}


// ==============================================================================
// HELPERS
// ==============================================================================

@(private = "file")
list_item_overlay_offset :: proc(target: ^Box, inset_x, inset_y: f32) -> [2]f32 {
	assert(target.parent != nil)
	parent := target.parent
	content_x := parent.x + parent.padding[Side.LEFT] + parent.border[Side.LEFT] -
	             parent.offset_x
	content_y := parent.y + parent.padding[Side.TOP] + parent.border[Side.TOP] -
	             parent.offset_y
	return {target.x - content_x + inset_x, target.y - content_y + inset_y}
}

@(private = "file")
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

@(private = "file")
seed_initial_rss :: proc(state: ^Showcase_State) {
	state.rss_feeds = make([dynamic]RSS_Feed)
	state.rss_feed_names = make([dynamic]string)

	feed1 := RSS_Feed {
		title = "Tech News & Web",
	}
	feed1.articles = make([dynamic]RSS_Article)
	append(
		&feed1.articles,
		RSS_Article {
			"SvelteKit & Astro: Next Generation Web",
			"Sep 25, 2026",
			"Frontend architecture continues to shift away from heavy abstractions. SvelteKit and Astro have become frontrunners by pushing vanilla CSS and HTML methodologies, minimizing framework overhead while still offering powerful tooling...",
			false,
		},
	)
	append(
		&feed1.articles,
		RSS_Article {
			"Raw SQL vs ORMs in Complex Systems",
			"Sep 20, 2026",
			"While Object-Relational Mapping libraries provide quick scaffolding, they often obscure the boundary between database schemas and API responses. Leveraging raw SQL queries maintains clear boundaries and allows for highly optimized data extraction.",
			false,
		},
	)

	feed2 := RSS_Feed {
		title = "Low-Level & Graphics",
	}
	feed2.articles = make([dynamic]RSS_Article)
	append(
		&feed2.articles,
		RSS_Article {
			"Graphics Programming in C: Beyond the Framework",
			"Sep 22, 2026",
			"High-level game engines mask the beauty of graphics programming and physical simulations. By embracing Data-Oriented Design, custom engine mechanics, and raw C with manual memory allocation strategies, developers can achieve unparalleled control over hardware systems.",
			false,
		},
	)
	append(
		&feed2.articles,
		RSS_Article {
			"Arch Linux Hyprland Setup Tips",
			"Sep 18, 2026",
			"Tiling window managers like Hyprland transform the Linux desktop experience. Paired with Neovim, Kitty, and custom dotfile management, this setup offers developers a streamlined, highly personalized workstation without bureaucratic UI fluff.",
			false,
		},
	)

	append(&state.rss_feeds, feed1)
	append(&state.rss_feeds, feed2)

	for f in state.rss_feeds do append(&state.rss_feed_names, f.title)
}

@(private = "file")
interaction_touch_start :: proc(e: ^UI_Event, data: rawptr) {
	state := (^Showcase_State)(data)
	state.interaction_touch_count += 1
}

@(private = "file")
interaction_drag_start :: proc(e: ^UI_Event, data: rawptr) {
	(^Showcase_State)(data).interaction_dragging = true
}

@(private = "file")
interaction_drag_end :: proc(e: ^UI_Event, data: rawptr) {
	(^Showcase_State)(data).interaction_dragging = false
}

@(private = "file")
interaction_drop :: proc(e: ^UI_Event, data: rawptr) {
	state := (^Showcase_State)(data)
	state.interaction_drop_count += 1
}

page_interactions :: proc(app: ^App, app_state: rawptr) {
	state := (^Showcase_State)(app_state)

	{
		element_open(
			app,
			{
				style = {
					direction = .COLUMN,
					gap = 20,
					width = Percent{100},
					height = Percent{100},
					overflow_y = .SCROLL,
				},
			},
		)
		defer element_close(app)

		text(app, "Interactions", user_style = {font_size = 32})
		text(
			app,
			"Pointer, touch, keyboard focus, selection, and drag-and-drop events work through the same element tree.",
			user_style = {font_size = 14, text_color = Color{0.45, 0.48, 0.54, 1}},
		)

		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						gap = 16,
						width = Percent{100},
					},
				},
			)
			defer element_close(app)

			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							gap = 12,
							width = Grow{1},
							padding = space(20),
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.88, 0.89, 0.92, 1},
							border_radius = space(8),
						},
					},
				)
				defer element_close(app)
				text(app, "Focus and disabled states", user_style = {font_size = 18})
				text(
					app,
					"Use Tab to move focus. The first control has a custom focus ring; the second is disabled.",
					user_style = {font_size = 13, text_color = Color{0.45, 0.48, 0.54, 1}},
				)
				button(
					app,
					"Custom focus style",
					user_style = {
						focus_color = Color{0.72, 0.24, 0.82, 1},
						focus_width = 3,
					},
				)
				button(
					app,
					"Disabled control",
					user_style = {disabled = true, bg_color = Color{0.45, 0.48, 0.54, 1}},
				)
				button(
					app,
					"Pointer only (not focusable)",
					user_style = {
						focusable = false,
						bg_color = Color{0.38, 0.42, 0.5, 1},
					},
				)
			}

			{
				element_open(
					app,
					{
						style = {
							direction = .COLUMN,
							gap = 12,
							width = Grow{1},
							padding = space(20),
							bg_color = Color{1, 1, 1, 1},
							border = space(1),
							border_color = Color{0.88, 0.89, 0.92, 1},
							border_radius = space(8),
						},
					},
				)
				defer element_close(app)
				text(app, "Text selection", user_style = {font_size = 18})
				text(
					app,
					"Drag across this text to select it with a purple highlight.",
					user_style = {
						selectable = true,
						selection_color = Color{0.63, 0.25, 0.82, 0.42},
					},
				)
				text(
					app,
					"This text is not selectable.",
					user_style = {selectable = false, text_color = Color{0.5, 0.52, 0.57, 1}},
				)
			}
		}

		{
			element_open(
				app,
				{
					style = {
						direction = .ROW,
						gap = 16,
						width = Percent{100},
					},
				},
			)
			defer element_close(app)

			{
				drag_id := ID("interaction_drag_source")
				register(
					app.ev,
					drag_id,
					Event_Callbacks {
						draggable      = true,
						on_drag_start  = interaction_drag_start,
						on_drag_end    = interaction_drag_end,
						user_data      = state,
					},
				)
				element_open(
					app,
					Element {
						_box = {id = drag_id},
						text = "Drag this tile",
						style = {
							width = Grow{1},
							height = Fixed{120},
							padding = space(20),
							bg_color = state.interaction_dragging ? Color{0.76, 0.85, 1, 1} :
								Color{1, 1, 1, 1},
							border = space(2),
							border_color = Color{0.16, 0.38, 0.78, 1},
							border_radius = space(8),
							focusable = true,
							draggable = true,
						},
					},
				)
				defer element_close(app)
				text(app, "Mouse or touch drag", user_style = {font_size = 18})
				text(
					app,
					fmt.tprintf(
						"Drag state: %s",
						state.interaction_dragging ? "active" : "idle",
					),
					user_style = {font_size = 13, text_color = Color{0.45, 0.48, 0.54, 1}},
				)
			}

			{
				drop_id := ID("interaction_drop_target")
				register(
					app.ev,
					drop_id,
					Event_Callbacks {
						drop_target = true,
						on_drop     = interaction_drop,
						user_data   = state,
					},
				)
				element_open(
					app,
					Element {
						_box = {id = drop_id},
						style = {
							width = Grow{1},
							height = Fixed{120},
							padding = space(20),
							bg_color = Color{0.94, 0.97, 0.94, 1},
							border = space(2),
							border_color = Color{0.18, 0.62, 0.38, 1},
							border_radius = space(8),
							drop_target = true,
						},
					},
				)
				defer element_close(app)
				text(app, "Drop target", user_style = {font_size = 18})
				text(
					app,
					fmt.tprintf("Successful drops: %d", state.interaction_drop_count),
					user_style = {font_size = 13, text_color = Color{0.35, 0.46, 0.38, 1}},
				)
			}
		}

		{
			touch_id := ID("interaction_touch_target")
			register(
				app.ev,
				touch_id,
				Event_Callbacks {
					on_touch_start = interaction_touch_start,
					user_data      = state,
				},
			)
			element_open(
				app,
				Element {
					_box = {id = touch_id},
					style = {
						width = Percent{100},
						padding = space(18),
						bg_color = Color{0.9, 0.94, 1, 1},
						border_radius = space(8),
					},
				},
			)
			defer element_close(app)
			text(
				app,
				fmt.tprintf(
					"Touch this panel to send Touch_Start (%d touches so far)",
					state.interaction_touch_count,
				),
				user_style = {font_size = 15},
			)
		}
	}
}
