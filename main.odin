package UI

import "core:fmt"
import sdl "vendor:sdl2"

User_Record :: struct {
	name:   [dynamic]u8,
	email:  [dynamic]u8,
	active: bool,
}

App_State :: struct {
	router:             Router_State,
	nav_index:          int,
	nav_collapsed:      bool,
	users:              [dynamic]User_Record,
	selected_user:      int,
	new_name:           [dynamic]u8,
	new_email:          [dynamic]u8,
	search:             [dynamic]u8,
	carousel_index:     int,
	video_scrubbing:    bool,
	video_scrub_time:   f32,
	video_slider_value: f32,
	video_overlay:      bool,
	video_overlay_anim: f32,
}

main :: proc() {
	app := app_init(
		"Odin UI - CRUD Demo",
		1200,
		760,
		sdl.WINDOW_SHOWN | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_RESIZABLE,
	)
	if app == nil do return
	defer app_destroy(app)

	state := new(App_State)
	defer free(state)
	state.selected_user = -1
	state.users = make([dynamic]User_Record)
	state.new_name = make([dynamic]u8)
	state.new_email = make([dynamic]u8)
	state.search = make([dynamic]u8)
	seed_users(&state.users)

	defer {
		for user in state.users {
			delete(user.name)
			delete(user.email)
		}
		delete(state.users)
		delete(state.new_name)
		delete(state.new_email)
		delete(state.search)
		for _, player in app.ui.videos {
			if player != nil do video_player_destroy(player)
		}
		delete(app.ui.videos)
	}

	pages := []Page_Proc{page_users, page_media}
	for !app.quit {
		app_begin_frame(app)

		element_open(
			app,
			Element {
				style = {
					direction = .ROW,
					width = ViewPercent{100},
					height = ViewPercent{100},
					bg_color = Color{0.96, 0.97, 0.98, 1},
				},
			},
		)
		{
			sidebar_width: f32 = state.nav_collapsed ? 76 : 224
			element_open(
				app,
				Element {
					style = {
						direction = .COLUMN,
						width = Fixed{sidebar_width},
						height = Percent{100},
						padding = space(16),
						gap = 12,
						bg_color = Color{1, 1, 1, 1},
						border = space(0, 1, 0, 0),
						border_color = Color{0.88, 0.9, 0.93, 1},
					},
				},
			)
			text(
				app,
				state.nav_collapsed ? "OD" : "Odin Demo",
				user_style = {font_size = state.nav_collapsed ? 16 : 22},
			)
			if button(
				app,
				state.nav_collapsed ? ">" : "< Collapse",
				user_style = {
					width = Percent{100},
					bg_color = Color{0.94, 0.95, 0.97, 1},
					text_color = Color{0.2, 0.24, 0.3, 1},
				},
				salt = "collapse_nav",
			) {
				state.nav_collapsed = !state.nav_collapsed
			}

			if button(
				app,
				state.nav_collapsed ? "U" : "Users",
				user_style = nav_item_style(state.nav_index == 0),
				salt = "nav_users",
			) {
				state.nav_index = 0
			}
			if button(
				app,
				state.nav_collapsed ? "M" : "Media",
				user_style = nav_item_style(state.nav_index == 1),
				salt = "nav_media",
			) {
				state.nav_index = 1
			}

			element_close(app)
		}

		element_open(
			app,
			Element {
				style = {
					direction = .COLUMN,
					width = Grow{1},
					height = Percent{100},
					padding = space(28),
				},
			},
		)
		router_view(
			app,
			&state.router,
			state.nav_index,
			pages,
			state,
			wrapper_style = {bg_color = COLOR_TRANSPARENT},
			salt = "app_router",
		)
		element_close(app)
		element_close(app)

		app_end_frame(app)
	}
}

@(private = "file")
nav_item_style :: proc(selected: bool) -> Style {
	return {
		width = Percent{100},
		padding = space(12),
		bg_color = selected ? Color{0.88, 0.93, 1, 1} : Color{0.96, 0.97, 0.98, 1},
		text_color = selected ? Color{0.12, 0.34, 0.68, 1} : Color{0.2, 0.24, 0.3, 1},
		text_align = .LEFT,
	}
}

@(private = "file")
seed_users :: proc(users: ^[dynamic]User_Record) {
	append_user(users, "Ada Lovelace", "ada@example.com")
	append_user(users, "Grace Hopper", "grace@example.com")
	append_user(users, "Alan Turing", "alan@example.com")
}

@(private = "file")
append_user :: proc(users: ^[dynamic]User_Record, name, email: string) {
	user := User_Record {
		active = true,
	}
	user.name = make([dynamic]u8, 0, len(name))
	user.email = make([dynamic]u8, 0, len(email))
	for ch in name do append(&user.name, u8(ch))
	for ch in email do append(&user.email, u8(ch))
	append(users, user)
}

@(private = "file")
page_users :: proc(app: ^App, app_state: rawptr) {
	state := (^App_State)(app_state)

	element_open(
		app,
		Element {
			style = {
				direction = .COLUMN,
				gap = 20,
				width = Percent{100},
				height = Percent{100},
				overflow_y = .SCROLL,
			},
		},
	)
	text(app, "Users", user_style = {font_size = 32})
	text(
		app,
		"A small create, read, update, delete example.",
		user_style = {font_size = 14, text_color = Color{0.45, 0.49, 0.55, 1}},
	)

	{
		element_open(
			app,
			Element {
				style = {
					direction = .COLUMN,
					gap = 12,
					width = Percent{100},
					padding = space(20),
					bg_color = Color{1, 1, 1, 1},
					border = space(1),
					border_color = Color{0.88, 0.9, 0.93, 1},
					border_radius = space(8),
				},
			},
		)
		defer element_close(app)
		text(app, "Add a user", user_style = {font_size = 19})
		{
			element_open(app, {style = {direction = .COLUMN, gap = 12, width = Percent{100}}})
			defer element_close(app)
			text_input(app, &state.new_name, placeholder = "Name", salt = "new_name")
			text_input(app, &state.new_email, placeholder = "Email", salt = "new_email")
			if button(app, "Add user", salt = "add_user") {
				if len(state.new_name) > 0 && len(state.new_email) > 0 {
					append_user(
						&state.users,
						string(state.new_name[:]),
						string(state.new_email[:]),
					)
					clear(&state.new_name)
					clear(&state.new_email)
					state.selected_user = len(state.users) - 1
				}
			}
		}
	}

	{
		element_open(
			app,
			Element {
				style = {
					direction = .ROW,
					align_items = .START,
					gap = 20,
					width = Percent{100},
					height = Grow{1},
				},
			},
		)
		{
			element_open(
				app,
				Element {
					style = {
						direction = .COLUMN,
						width = Grow{1},
						height = Percent{100},
						gap = 10,
						padding = space(16),
						bg_color = Color{1, 1, 1, 1},
						border = space(1),
						border_color = Color{0.88, 0.9, 0.93, 1},
						border_radius = space(8),
					},
				},
			)
			text_input(app, &state.search, placeholder = "Search users...", salt = "search_users")
			scroll_id := scroll_begin(
				app,
				scroll_y = true,
				user_style = {width = Percent{100}, height = Grow{1}},
				salt = "user_list_scroll",
			)
			for user, i in state.users {
				name := string(user.name[:])
				if len(state.search) > 0 &&
				   !contains_case_insensitive(name, string(state.search[:])) {
					continue
				}
				if button(
					app,
					fmt.tprintf("%s\n%s", name, string(user.email[:])),
					user_style = {
						width = Percent{100},
						text_align = .LEFT,
						bg_color = state.selected_user == i ? Color{0.88, 0.93, 1, 1} : Color{0.97, 0.98, 0.99, 1},
						text_color = Color{0.16, 0.19, 0.24, 1},
					},
					salt = fmt.tprintf("user_%d", i),
				) {
					state.selected_user = i
				}
			}
			scroll_end(app, scroll_id)
			element_close(app)
		}

		{
			element_open(
				app,
				Element {
					style = {
						direction = .COLUMN,
						width = Grow{1},
						height = Percent{100},
						gap = 12,
						padding = space(20),
						bg_color = Color{1, 1, 1, 1},
						border = space(1),
						border_color = Color{0.88, 0.9, 0.93, 1},
						border_radius = space(8),
					},
				},
			)
			text(app, "Edit user", user_style = {font_size = 19})
			if state.selected_user >= 0 && state.selected_user < len(state.users) {
				user := &state.users[state.selected_user]
				text(app, "Name")
				text_input(app, &user.name, placeholder = "Name", salt = "edit_name")
				text(app, "Email")
				text_input(app, &user.email, placeholder = "Email", salt = "edit_email")
				switch_toggle(app, "Active", &user.active, salt = "edit_active")
				{
					element_open(app, {style = {direction = .ROW, gap = 10}})
					if button(
						app,
						"Delete",
						user_style = {bg_color = Color{0.78, 0.22, 0.22, 1}},
						salt = "delete_user",
					) {
						delete(user.name)
						delete(user.email)
						ordered_remove(&state.users, state.selected_user)
						state.selected_user = len(state.users) > 0 ? 0 : -1
					}
					element_close(app)
				}
			} else {
				text(
					app,
					"Choose a user from the list, or add a new one.",
					user_style = {text_color = Color{0.45, 0.49, 0.55, 1}},
				)
			}
			element_close(app)
		}
		element_close(app)
	}
	element_close(app)
}

@(private = "file")
contains_case_insensitive :: proc(haystack, needle: string) -> bool {
	if len(needle) == 0 do return true
	if len(needle) > len(haystack) do return false
	for i in 0 ..= len(haystack) - len(needle) {
		matches := true
		for j in 0 ..< len(needle) {
			a := haystack[i + j]
			b := needle[j]
			if a >= 'A' && a <= 'Z' do a += 'a' - 'A'
			if b >= 'A' && b <= 'Z' do b += 'a' - 'A'
			if a != b {
				matches = false
				break
			}
		}
		if matches do return true
	}
	return false
}

@(private = "file")
page_media :: proc(app: ^App, app_state: rawptr) {
	state := (^App_State)(app_state)

	element_open(
		app,
		Element {
			style = {
				direction = .COLUMN,
				gap = 20,
				width = Percent{100},
				height = Percent{100},
				overflow_y = .SCROLL,
			},
		},
	)
	text(app, "Media", user_style = {font_size = 32})
	text(
		app,
		"Example image carousel and video player.",
		user_style = {font_size = 14, text_color = Color{0.45, 0.49, 0.55, 1}},
	)

	{
		element_open(
			app,
			Element {
				style = {
					direction = .COLUMN,
					gap = 12,
					padding = space(18),
					width = Percent{100},
					bg_color = Color{1, 1, 1, 1},
					border = space(1),
					border_color = Color{0.88, 0.9, 0.93, 1},
					border_radius = space(8),
				},
			},
		)
		text(app, "Carousel", user_style = {font_size = 19})
		carousel_paths(
			app,
			[]string {
				"assets/pictures/carousel/slide1.png",
				"assets/pictures/carousel/slide2.png",
				"assets/pictures/carousel/slide3.png",
			},
			&state.carousel_index,
			viewport_style = {width = Fixed{680}, height = Fixed{300}},
			salt = "media_carousel",
		)
		element_close(app)
	}

	{
		element_open(
			app,
			Element {
				style = {
					direction = .COLUMN,
					gap = 12,
					padding = space(18),
					width = Percent{100},
					height = Fixed{450},
					bg_color = Color{1, 1, 1, 1},
					border = space(1),
					border_color = Color{0.88, 0.9, 0.93, 1},
					border_radius = space(8),
				},
			},
		)
		text(app, "Video", user_style = {font_size = 19})
		video(
			app,
			"assets/Two 2-minute Rules to Beat Procrastination (in 2 minutes).mp4",
			f64(app.time.delta),
			&state.video_scrubbing,
			&state.video_scrub_time,
			&state.video_slider_value,
			&state.video_overlay,
			&state.video_overlay_anim,
			wrapper_style = {width = Percent{100}, height = Grow{1}},
			salt = "demo_video",
		)
		element_close(app)
	}
	element_close(app)
}
