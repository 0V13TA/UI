package main

import anim "./animations"
import ev "./events"
import lc "./layout_calc"
import "./renderer"
import "core:fmt"
import "core:hash"
import "core:strings"
import sdl "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

// Define our Data Model
User :: struct {
	id:       int,
	name:     string,
	role:     string,
	deleting: bool,
	is_new:   bool,
}

main :: proc() {
	sdl.Init({.VIDEO})
	defer sdl.Quit()
	ttf.Init()
	defer ttf.Quit()
	img.Init({.PNG, .JPG})
	defer img.Quit()

	window := sdl.CreateWindow(
		"Odin UI Engine - CRUD App",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1184,
		768,
		{.SHOWN},
	)
	defer sdl.DestroyWindow(window)

	sdl_rend := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	defer sdl.DestroyRenderer(sdl_rend)

	sdl.SetRenderDrawBlendMode(sdl_rend, .BLEND)

	font := ttf.OpenFont("assets/font/CaacupeOne-Regular.ttf", 24)
	defer ttf.CloseFont(font)

	ui_ctx := renderer.ui_context_create(1024, 768)
	defer renderer.ui_context_destroy(ui_ctx)
	ui_ctx.fonts[hash.fnv32(transmute([]byte)string("default_font"))] = font

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

	// --- CRUD App State ---
	users := make([dynamic]User)
	defer {
		for u in users {
			delete(u.name)
			delete(u.role)
		}
		delete(users)
	}

	next_id := 1
	edit_id := 0

	name_buf := make([dynamic]u8)
	role_buf := make([dynamic]u8)
	defer {
		delete(name_buf)
		delete(role_buf)
	}

	// Seed some initial data to see the stagger effect
	append(
		&users,
		User{id = next_id, name = strings.clone("Alice Admin"), role = strings.clone("Sysadmin")},
	); next_id += 1
	append(
		&users,
		User{id = next_id, name = strings.clone("Bob Builder"), role = strings.clone("Engineer")},
	); next_id += 1
	append(
		&users,
		User {
			id = next_id,
			name = strings.clone("Charlie Code"),
			role = strings.clone("Developer"),
		},
	); next_id += 1

	play_intro := true
	is_scrubbing := false
	scrub_time := f32(0)
	slider_val := f32(0)
	overlay_active := false
	overlay_anim := f32(0.0)

	USER_CARD_CLASS := renderer.Class_Name("user_card")

	cursor_arrow := sdl.CreateSystemCursor(.ARROW)
	cursor_hand := sdl.CreateSystemCursor(.HAND)
	cursor_ibeam := sdl.CreateSystemCursor(.IBEAM)
	defer sdl.FreeCursor(cursor_arrow)
	defer sdl.FreeCursor(cursor_hand)
	defer sdl.FreeCursor(cursor_ibeam)

	perf_freq := f64(sdl.GetPerformanceFrequency())
	last_time := sdl.GetPerformanceCounter()

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

		// Only push to SDL if the cursor actually changed
		if sdl.GetCursor() != target_cursor {
			sdl.SetCursor(target_cursor)
		}

		win_w, win_h: i32
		sdl.GetWindowSize(window, &win_w, &win_h)

		renderer.ui_begin_frame(ui_ctx, sdl_rend, win_w, win_h)
		tl := renderer.timeline(ui_ctx, &anim_ctx)

		// Main Layout Wrapper
		renderer.element_open(
			ui_ctx,
			{
				style = {
					width = lc.ViewPercent{100},
					height = lc.ViewPercent{100},
					direction = .ROW,
					bg_color = renderer.Color{0.95, 0.95, 0.97, 1},
				},
			},
		)

		// ---------------------------------------------------------
		// LEFT PANEL: Form
		// ---------------------------------------------------------
		renderer.element_open(
			ui_ctx,
			{
				id = lc.ID("left_panel"),
				style = {
					gap = 20,
					direction = .COLUMN,
					width = lc.Fixed{300},
					height = lc.Percent{100},
					padding = renderer.space(30),
					bg_color = renderer.Color{1, 1, 1, 1},
					border = renderer.space(0, 8, 0, 0),
					border_color = renderer.Color{0.8, 0.8, 0.8, 1},
				},
			},
		)

		form_title := edit_id == 0 ? "Add New User" : "Edit User"
		renderer.text(
			ui_ctx,
			&ev_ctx,
			form_title,
			{font_size = 24, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
		)

		renderer.text(
			ui_ctx,
			&ev_ctx,
			"Full Name",
			{font_size = 14, text_color = renderer.Color{0.5, 0.5, 0.5, 1}},
		)
		renderer.text_input(ui_ctx, &ev_ctx, &name_buf, "e.g. Jane Doe")

		renderer.text(
			ui_ctx,
			&ev_ctx,
			"Role",
			{font_size = 14, text_color = renderer.Color{0.5, 0.5, 0.5, 1}},
		)
		renderer.text_input(ui_ctx, &ev_ctx, &role_buf, "e.g. Engineer")

		// Action Buttons
		renderer.element_open(
			ui_ctx,
			{style = {direction = .ROW, gap = 10, margin = renderer.space(10, 0, 0, 0)}},
		)

		btn_text := edit_id == 0 ? "Create" : "Save Changes"
		if renderer.button(ui_ctx, &ev_ctx, btn_text) {
			if len(name_buf) > 0 {
				if edit_id == 0 {
					// CREATE
					append(
						&users,
						User {
							id     = next_id,
							name   = strings.clone(string(name_buf[:])),
							role   = strings.clone(string(role_buf[:])),
							is_new = true, // <-- Flag it here
						},
					)
					next_id += 1
				} else {
					// UPDATE
					for &u in users {
						if u.id == edit_id {
							delete(u.name)
							delete(u.role)
							u.name = strings.clone(string(name_buf[:]))
							u.role = strings.clone(string(role_buf[:]))
							break
						}
					}
					edit_id = 0
				}
				clear(&name_buf)
				clear(&role_buf)
			}
		}

		if edit_id != 0 {
			if renderer.button(
				ui_ctx,
				&ev_ctx,
				"Cancel",
				{bg_color = renderer.Color{0.6, 0.6, 0.6, 1}},
			) {
				edit_id = 0
				clear(&name_buf)
				clear(&role_buf)
			}
		}
		renderer.element_close(ui_ctx) // Close Buttons
		renderer.element_close(ui_ctx) // Close Left Panel


		// ---------------------------------------------------------
		// RIGHT PANEL: User List
		// ---------------------------------------------------------
		renderer.scroll_begin(
			ui_ctx,
			&ev_ctx,
			lc.ID("user_list_scroll"),
			scroll_y = true,
			user_style = {
				direction = .COLUMN,
				gap = 15,
				width = lc.Grow{1},
				height = lc.Percent{100},
				padding = renderer.space(40),
			},
		)

		// Fetch the player from the cache
		video_path := "assets/Two 2-minute Rules to Beat Procrastination (in 2 minutes).mp4"

		renderer.video(
			ui_ctx,
			&ev_ctx,
			&anim_ctx,
			sdl_rend,
			video_path,
			dt,
			&is_scrubbing,
			&scrub_time,
			&slider_val,
			&overlay_active,
			&overlay_anim,
			wrapper_style = {
				width = lc.Percent{100},
				height = lc.Fixed{250},
				object_fit = .COVER,
				border_radius = renderer.space(8),
			},
		)

		if len(users) == 0 {
			renderer.text(
				ui_ctx,
				&ev_ctx,
				"No users found. Create one to get started!",
				{font_size = 18, text_color = renderer.Color{0.6, 0.6, 0.6, 1}},
			)
		}

		to_delete_idx := -1

		for &u, i in users {
			// Create a stable ID for the animation engine to target
			card_id := lc.ID(fmt.tprintf("user_card_%d", u.id))

			if u.is_new {
				// Fade in from 0 over 0.5 seconds
				renderer.tl_from(
					&tl,
					card_id,
					{duration = 0.5, ease = anim.ease_out_exp, opacity = 0.0},
				)
				u.is_new = false
			}
			// If it is deleting, wait for the opacity tween to finish before removing memory
			if u.deleting {
				state := anim.get_state(&anim_ctx, card_id)
				if state.opacity <= 0.01 {
					to_delete_idx = i
					continue
				}
			}

			renderer.element_open(
				ui_ctx,
				{
					_box = {id = card_id}, // <-- Bind the ID
					classes = []renderer.Class{USER_CARD_CLASS},
					style = {
						direction     = .ROW,
						align_items   = .CENTER,
						width         = lc.Percent{100},
						// Strip padding and borders during deletion so it can collapse to 0
						padding       = u.deleting ? renderer.space(0) : renderer.space(20),
						border        = u.deleting ? renderer.space(0) : renderer.space(1),
						bg_color      = renderer.Color{1, 1, 1, 1},
						border_radius = renderer.space(8),
						border_color  = renderer.Color{0.8, 0.8, 0.8, 1},
						overflow_y    = .HIDDEN, // <-- Prevent text from spilling out while shrinking
					},
				},
			)

			// Info
			renderer.element_open(
				ui_ctx,
				{style = {direction = .COLUMN, width = lc.Grow{1}, gap = 5}},
			)
			renderer.text(
				ui_ctx,
				&ev_ctx,
				u.name,
				{font_size = 20, text_color = renderer.Color{0.1, 0.1, 0.1, 1}},
			)
			renderer.text(
				ui_ctx,
				&ev_ctx,
				u.role,
				{font_size = 14, text_color = renderer.Color{0.5, 0.5, 0.6, 1}},
			)
			renderer.element_close(ui_ctx)

			// Actions
			edit_salt := fmt.tprintf("edit_%d", u.id)
			if renderer.button(ui_ctx, &ev_ctx, "Edit", salt = edit_salt) {
				edit_id = u.id
				clear(&name_buf)
				clear(&role_buf)
				for b in transmute([]u8)u.name do append(&name_buf, b)
				for b in transmute([]u8)u.role do append(&role_buf, b)
			}
			del_id := lc.ID(fmt.tprintf("del_btn_%d", u.id))

			del_salt := fmt.tprintf("del_%d", u.id)
			if renderer.button(
				ui_ctx,
				&ev_ctx,
				"Delete",
				{
					bg_color = renderer.Color{0.9, 0.3, 0.3, 1},
					margin = renderer.space(0, 0, 0, 10),
				},
				id = del_id,
			) {
				// Mark as deleting and trigger the exit timeline
				if !u.deleting {
					u.deleting = true
					renderer.tl_to(
						&tl,
						card_id,
						{duration = 0.4, ease = anim.ease_out_exp, height = 0.0, opacity = 0.0},
					)
				}
			}

			if renderer.tooltip_begin(ui_ctx, &ev_ctx, del_id) {
				renderer.text(
					ui_ctx,
					&ev_ctx,
					"Warning:",
					{font_size = 14, text_color = renderer.Color{0.9, 0.4, 0.4, 1}},
				)
				renderer.text(
					ui_ctx,
					&ev_ctx,
					"Permanently remove this user",
					{font_size = 12, text_color = renderer.Color{0.7, 0.7, 0.7, 1}},
				)
				renderer.tooltip_end(ui_ctx, true)
			}

			renderer.element_close(ui_ctx) // Close User Card
		}

		renderer.scroll_end(ui_ctx) // Close Right Panel
		renderer.element_close(ui_ctx) // Close Main Wrapper

		// Perform deletion outside the rendering loop
		if to_delete_idx != -1 {
			if edit_id == users[to_delete_idx].id {
				edit_id = 0
				clear(&name_buf)
				clear(&role_buf)
			}
			delete(users[to_delete_idx].name)
			delete(users[to_delete_idx].role)
			ordered_remove(&users, to_delete_idx)
		}

		// Get the uncomputed tree and apply structural animations FIRST
		roots := renderer.ui_layout_tree(ui_ctx)
		for root in roots {
			anim.apply_structural(&anim_ctx, root)
		}

		// NOW run the layout math
		renderer.ui_compute(ui_ctx)

		// Queue Intro Animation
		if play_intro {
			renderer.tl_from(
				&tl,
				lc.ID("left_panel"),
				{duration = 0.6, ease = anim.ease_out_exp, width = 0.0},
			)
			renderer.tl_from(
				&tl,
				USER_CARD_CLASS,
				{
					duration = 1.2,
					stagger  = 0.1,
					// An aggressive overshoot cubic-bezier!
					ease     = anim.Bezier{0.175, 0.885, 0.32, 1.275},
					opacity  = 0.0,
				},
			)
			play_intro = false
		}

		renderer.tl_play(&tl)
		anim.update(&anim_ctx.engine, 0.016)

		// Apply visual animations (opacity/color) right before rendering
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
