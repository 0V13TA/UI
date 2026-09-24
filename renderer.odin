package UI

import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

when ODIN_DEBUG {
	g_debug_class_registry: map[Class]string
}

Text_Align :: enum {
	LEFT,
	RIGHT,
	CENTER,
}
Text_Wrap :: enum {
	NONE,
	WORD,
	LETTER,
}
Cached_Texture :: struct {
	texture: ^sdl.Texture,
	width:   i32,
	height:  i32,
}

Object_Fit :: enum {
	STRETCH, // Fills exactly, ignoring aspect ratio (Default)
	CONTAIN, // Fits inside, preserving aspect ratio (Letterboxes)
	COVER, // Fills entirely, preserving aspect ratio (Crops excess)
	NONE, // Native size, centered (Crops if too large)
}

Color :: distinct [4]f32
Class :: distinct u32

Font_Key :: struct {
	path_hash: u32,
	size:      i32,
}


Style :: struct {
	bg_color:        Maybe(Color),
	opacity:         Maybe(f32),

	//
	text_color:      Maybe(Color),
	text_wrap:       Maybe(Text_Wrap),
	text_align:      Maybe(Text_Align),
	selection_start: Maybe(int),
	selection_end:   Maybe(int),
	selection_color: Maybe(Color),

	// Typography
	font_size:       Maybe(f32),
	font_spacing:    Maybe(f32),
	font_name:       Maybe(string),
	font_style:      Maybe(ttf.StyleFlag),

	// Spacing
	gap:             Maybe(f32),
	margin:          Maybe([4]f32),
	padding:         Maybe([4]f32),

	//
	border:          Maybe([4]f32),
	border_color:    Maybe(Color),
	border_radius:   Maybe([4]f32),

	// Flex Alignment
	wrap:            Maybe(bool),
	basis:           Maybe(f32),
	direction:       Maybe(Direction),
	align_items:     Maybe(Align),
	justify_content: Maybe(Align),

	// Position
	top:             Maybe(f32), // Only useful if position != STATIC
	left:            Maybe(f32),
	right:           Maybe(f32),
	bottom:          Maybe(f32),
	position:        Maybe(Position),

	// Scrolling
	overflow_x:      Maybe(Overflow),
	overflow_y:      Maybe(Overflow),

	//
	z_index:         Maybe(i32),

	//
	object_fit:      Maybe(Object_Fit),
	bg_image:        Maybe(^sdl.Texture),

	//
	width:           Maybe(Sizing),
	height:          Maybe(Sizing),
	min_width:       Maybe(Bound_Sizing),
	max_width:       Maybe(Bound_Sizing),
	min_height:      Maybe(Bound_Sizing),
	max_height:      Maybe(Bound_Sizing),
}


Element :: struct {
	classes:                []Class,
	style:                  Style,
	using _box:             Box,

	// Anything not in Box
	// Font
	resolved_font_spacing:  f32,
	resolved_font_size:     f32,
	resolved_font_name:     string,
	resolved_font:          ^ttf.Font,
	resolved_font_style:    ttf.StyleFlag,

	// Text
	resolved_text_wrap:     Text_Wrap,
	resolved_text_color:    Color,
	resolved_text_align:    Text_Align,

	// Border
	resolved_opacity:       f32,
	resolved_border_color:  Color,
	resolved_border_radius: [4]f32,

	// Backgroud
	resolved_bg_color:      Color,
	resolved_object_fit:    Object_Fit,
	resolved_bg_image:      ^sdl.Texture,

	// Canvas Renderer Callback
	custom_render:          proc(renderer: ^sdl.Renderer, bounds: sdl.Rect, data: rawptr),
	custom_render_data:     rawptr,
}

Glyph_Key :: struct {
	font: ^ttf.Font,
	ch:   rune,
}

Glyph :: struct {
	texture:               ^sdl.Texture,
	width, height:         i32,
	min_x, max_y, advance: i32,
}

Text_Key :: struct {
	font:       ^ttf.Font,
	text:       string,
	r, g, b, a: u8,
}

UI_Context :: struct {
	layout:         ^Layout_Context,
	fonts:          map[u32]^ttf.Font, // Hash Font name + Cache name
	videos:         map[string]^Video_Player,
	stylesheet:     map[Class]Style,
	text_cache:     map[Text_Key]Cached_Texture,
	image_cache:    map[u32]^sdl.Texture,
	font_cache:     map[Font_Key]^ttf.Font,
	master_9slice:  ^sdl.Texture,
	mask_texture:   ^sdl.Texture,
	mask_texture_w: i32,
	mask_texture_h: i32,
}

MASTER_CORNER_RADIUS :: 64


// Utility Functions
Class_Name :: proc(id: string) -> Class {
	hash_val := Class(hash.fnv32(transmute([]byte)id))

	when ODIN_DEBUG {
		if hash_val not_in g_debug_class_registry {
			g_debug_class_registry[hash_val] = strings.clone(id)
		}
	}

	return hash_val
}

get_class_name :: proc(c: Class) -> string {
	when ODIN_DEBUG {
		return g_debug_class_registry[c] or_else "UNKNOWN_CLASS"
	} else {
		return ""
	}
}

get_font :: proc(ctx: ^UI_Context, path: string, size: f32) -> ^ttf.Font {
	// Fallback to a default font if none is specified
	actual_path := path != "" ? path : "./assets/font/CaacupeOne-Regular.ttf"
	actual_size := size > 0 ? i32(size) : 16

	key := Font_Key {
		path_hash = hash.fnv32(transmute([]byte)actual_path),
		size      = actual_size,
	}

	// Cache Hit
	if font, ok := ctx.font_cache[key]; ok {
		return font
	}

	// Cache Miss: Load from disk
	c_path := strings.clone_to_cstring(actual_path, context.temp_allocator)
	font := ttf.OpenFont(c_path, actual_size)

	if font == nil {
		fmt.printfln(
			"ERROR: Failed to load font '%s' at size %d: %s",
			actual_path,
			actual_size,
			sdl.GetError(),
		)
	}

	ctx.font_cache[key] = font
	return font
}

@(private)
space_1 :: proc(all: f32) -> [4]f32 {
	return {all, all, all, all}
}
@(private)
space_2 :: proc(vertical, horizontal: f32) -> [4]f32 {
	return {vertical, horizontal, vertical, horizontal}
}
@(private)
space_3 :: proc(top, horizontal, bottom: f32) -> [4]f32 {
	return {top, horizontal, bottom, horizontal}
}
@(private)
space_4 :: proc(top, right, bottom, left: f32) -> [4]f32 {
	return {top, right, bottom, left}
}

space :: proc {
	space_1,
	space_2,
	space_3,
	space_4,
}


// --- Color Helpers ---
@(private)
to_sdl_color :: proc(c: Color) -> (u8, u8, u8, u8) {
	return u8(c[0] * 255), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255)
}

@(private)
set_render_color :: proc(renderer: ^sdl.Renderer, c: Color) {
	r, g, b, a := to_sdl_color(c)
	sdl.SetRenderDrawColor(renderer, r, g, b, a)
}

@(private)
create_9slice_base_texture :: proc(renderer: ^sdl.Renderer, radius: i32) -> ^sdl.Texture {
	size := radius * 2 + 2 // +2 gives a 2px stretchable center

	// Create an RGBA32 surface
	rmask: u32 = 0xff000000
	gmask: u32 = 0x00ff0000
	bmask: u32 = 0x0000ff00
	amask: u32 = 0x000000ff

	surface := sdl.CreateRGBSurface(
		cast(u32)sdl.WINDOW_SHOWN,
		size,
		size,
		32,
		rmask,
		gmask,
		bmask,
		amask,
	)
	defer sdl.FreeSurface(surface)

	pixels := cast([^]u32)surface.pixels
	pitch := surface.pitch / 4 // pitch in u32s

	for y in 0 ..< size {
		for x in 0 ..< size {
			// Map x, y to distance from the nearest corner
			cx := x < radius ? radius - x : (x > radius + 1 ? x - (radius + 1) : 0)
			cy := y < radius ? radius - y : (y > radius + 1 ? y - (radius + 1) : 0)

			dist := math.sqrt(f32(cx * cx + cy * cy))

			alpha: u32 = 255
			if dist > f32(radius) {
				// Smooth anti-aliasing on the outer edge
				diff := dist - f32(radius)
				if diff > 1.0 {
					alpha = 0
				} else {
					alpha = u32(255.0 * (1.0 - diff))
				}
			}

			// Write white pixel with calculated alpha
			pixels[y * pitch + x] = 0xFFFFFF00 | alpha
		}
	}

	// Convert to a hardware texture
	tex := sdl.CreateTextureFromSurface(renderer, surface)
	sdl.SetTextureBlendMode(tex, .BLEND)
	sdl.SetTextureScaleMode(tex, .Linear)
	return tex
}

@(private)
draw_rounded_rect_9slice :: proc(
	renderer: ^sdl.Renderer,
	tex: ^sdl.Texture,
	dest_rect: sdl.Rect,
	corner_radius: i32,
	color: sdl.Color,
) {
	if tex == nil do return

	// Tint the white texture to the target UI color
	sdl.SetTextureColorMod(tex, color.r, color.g, color.b)
	sdl.SetTextureAlphaMod(tex, color.a)

	tex_w, tex_h: i32
	sdl.QueryTexture(tex, nil, nil, &tex_w, &tex_h)

	// The slice margin is the corner radius used when generating the texture
	slice := tex_w / 2 - 1

	// Clamp layout radius to avoid overlapping slices on very small boxes
	r := corner_radius
	if r > dest_rect.w / 2 do r = dest_rect.w / 2
	if r > dest_rect.h / 2 do r = dest_rect.h / 2

	// Define the 9 Source Rectangles (from the base texture)
	src := [9]sdl.Rect {
		{0, 0, slice, slice}, // Top Left
		{slice, 0, tex_w - 2 * slice, slice}, // Top Center
		{tex_w - slice, 0, slice, slice}, // Top Right
		{0, slice, slice, tex_h - 2 * slice}, // Mid Left
		{slice, slice, tex_w - 2 * slice, tex_h - 2 * slice}, // Mid Center
		{tex_w - slice, slice, slice, tex_h - 2 * slice}, // Mid Right
		{0, tex_h - slice, slice, slice}, // Bottom Left
		{slice, tex_h - slice, tex_w - 2 * slice, slice}, // Bottom Center
		{tex_w - slice, tex_h - slice, slice, slice}, // Bottom Right
	}

	// Define the 9 Destination Rectangles (on the screen)
	x, y, w, h := dest_rect.x, dest_rect.y, dest_rect.w, dest_rect.h
	dst := [9]sdl.Rect {
		{x, y, r, r}, // Top Left
		{x + r, y, w - 2 * r, r}, // Top Center
		{x + w - r, y, r, r}, // Top Right
		{x, y + r, r, h - 2 * r}, // Mid Left
		{x + r, y + r, w - 2 * r, h - 2 * r}, // Mid Center
		{x + w - r, y + r, r, h - 2 * r}, // Mid Right
		{x, y + h - r, r, r}, // Bottom Left
		{x + r, y + h - r, w - 2 * r, r}, // Bottom Center
		{x + w - r, y + h - r, r, r}, // Bottom Right
	}

	// Dispatch the 9 draw calls
	for i in 0 ..< 9 {
		// Skip drawing segments that have been squished to 0 width or height
		if dst[i].w > 0 && dst[i].h > 0 {
			sdl.RenderCopy(renderer, tex, &src[i], &dst[i])
		}
	}
}


@(private)
get_9slice_texture :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer) -> ^sdl.Texture {
	if ctx.master_9slice == nil {
		ctx.master_9slice = create_9slice_base_texture(renderer, MASTER_CORNER_RADIUS)
	}
	return ctx.master_9slice
}

@(private)
get_mask_texture :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, w, h: i32) -> ^sdl.Texture {
	// If we already have a texture large enough, just reuse it!
	if ctx.mask_texture != nil && ctx.mask_texture_w >= w && ctx.mask_texture_h >= h {
		return ctx.mask_texture
	}

	if ctx.mask_texture != nil do sdl.DestroyTexture(ctx.mask_texture)

	// Grow the texture in chunks so we aren't reallocating for every 1 pixel change
	new_w := max(ctx.mask_texture_w, w) + 256
	new_h := max(ctx.mask_texture_h, h) + 256

	ctx.mask_texture = sdl.CreateTexture(
		renderer,
		sdl.PixelFormatEnum.RGBA8888,
		sdl.TextureAccess.TARGET,
		new_w,
		new_h,
	)

	sdl.SetTextureBlendMode(ctx.mask_texture, .BLEND)
	ctx.mask_texture_w = new_w
	ctx.mask_texture_h = new_h

	return ctx.mask_texture
}

// --- Master Box Drawing Proc ---
@(private)
draw_ui_box :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	bounds: sdl.Rect,
	bg_color, border_color: Color,
	border: [4]f32, // border: [Top, Right, Bottom, Left]
	radii: [4]f32, // radii:  [TopLeft, TopRight, BottomRight, BottomLeft]
) {
	has_border := border[0] > 0 || border[1] > 0 || border[2] > 0 || border[3] > 0
	corner_radius := i32(radii[0])

	// Fast path for hard corners (No texture overhead needed)
	if corner_radius <= 0 {

		// 1. Draw Inner Background First
		if bg_color[3] > 0 {
			inner_bounds := sdl.Rect {
				x = bounds.x + i32(border[3]),
				y = bounds.y + i32(border[0]),
				w = bounds.w - i32(border[3] + border[1]),
				h = bounds.h - i32(border[0] + border[2]),
			}
			set_render_color(renderer, bg_color)
			sdl.RenderFillRect(renderer, &inner_bounds)
		}

		// 2. Draw Borders as 4 separate lines so transparent backgrounds stay hollow
		if has_border && border_color[3] > 0 {
			set_render_color(renderer, border_color)

			// Top
			if border[0] > 0 {
				r := sdl.Rect{bounds.x, bounds.y, bounds.w, i32(border[0])}
				sdl.RenderFillRect(renderer, &r)
			}
			// Bottom
			if border[2] > 0 {
				r := sdl.Rect {
					bounds.x,
					bounds.y + bounds.h - i32(border[2]),
					bounds.w,
					i32(border[2]),
				}
				sdl.RenderFillRect(renderer, &r)
			}
			// Left
			if border[3] > 0 {
				r := sdl.Rect {
					bounds.x,
					bounds.y + i32(border[0]),
					i32(border[3]),
					bounds.h - i32(border[0] + border[2]),
				}
				sdl.RenderFillRect(renderer, &r)
			}
			// Right
			if border[1] > 0 {
				r := sdl.Rect {
					bounds.x + bounds.w - i32(border[1]),
					bounds.y + i32(border[0]),
					i32(border[1]),
					bounds.h - i32(border[0] + border[2]),
				}
				sdl.RenderFillRect(renderer, &r)
			}
		}
		return
	}

	// Draw Outer Border using 9-Slice
	if has_border && border_color[3] > 0 {
		tex := get_9slice_texture(ctx, renderer)
		r, g, b, a := to_sdl_color(border_color)
		draw_rounded_rect_9slice(renderer, tex, bounds, corner_radius, sdl.Color{r, g, b, a})
	}

	// Draw Inner Background using 9-Slice
	if bg_color[3] > 0 {
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(border[3]),
			y = bounds.y + i32(border[0]),
			w = bounds.w - i32(border[3] + border[1]),
			h = bounds.h - i32(border[0] + border[2]),
		}

		max_border := max(border[0], border[3])
		inner_radius := i32(max(f32(corner_radius) - max_border, 0))

		if inner_radius > 0 {
			inner_tex := get_9slice_texture(ctx, renderer)
			r, g, b, a := to_sdl_color(bg_color)
			draw_rounded_rect_9slice(
				renderer,
				inner_tex,
				inner_bounds,
				inner_radius,
				sdl.Color{r, g, b, a},
			)
		} else {
			set_render_color(renderer, bg_color)
			sdl.RenderFillRect(renderer, &inner_bounds)
		}
	}
}

@(private)
draw_ui_text :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	font: ^ttf.Font,
	text: string,
	x, y: i32,
	color: Color,
) {
	if len(text) == 0 do return

	cached := get_text_texture(ctx, renderer, font, text, color)
	if cached.texture != nil {
		dest := sdl.Rect {
			x = x,
			y = y,
			w = cached.width,
			h = cached.height,
		}
		sdl.RenderCopy(renderer, cached.texture, nil, &dest)
	}
}

@(private)
ui_text_width :: proc(box: ^Box, text: string) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	max_w: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for line in explicit_lines {
		if len(line) == 0 do continue

		c_line := fmt.ctprintf("%s", line)
		w, h: i32
		ttf.SizeUTF8(el.resolved_font, c_line, &w, &h)

		if f32(w) > max_w do max_w = f32(w)
	}

	return max_w
}

@(private)
ui_text_height :: proc(box: ^Box, text: string, max_width: f32) -> f32 {
	el := (^Element)(box.user_data)
	if el == nil || el.resolved_font == nil do return 0

	line_height := f32(ttf.FontHeight(el.resolved_font))

	space_w, space_h: i32
	ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
	space_width := f32(space_w)

	total_lines: f32 = 0.0
	explicit_lines := strings.split(text, "\n", context.temp_allocator)

	for explicit_line in explicit_lines {
		total_lines += 1.0
		cursor_x: f32 = 0.0

		if el.resolved_text_wrap == .LETTER {
			prev_ch: rune = 0
			for r in explicit_line {
				if prev_ch != 0 {
					cursor_x += f32(ttf.GetFontKerningSizeGlyphs32(el.resolved_font, prev_ch, r))
				}

				_, _, _, _, adv: i32
				ttf.GlyphMetrics32(el.resolved_font, r, nil, nil, nil, nil, &adv)
				rune_width := f32(adv)

				if cursor_x + rune_width > max_width && cursor_x > 0 {
					cursor_x = 0
					total_lines += 1.0
					prev_ch = 0
				} else {
					prev_ch = r
				}
				cursor_x += rune_width
			}
		} else {
			words := strings.split(explicit_line, " ", context.temp_allocator)
			for word in words {
				if len(word) == 0 {
					cursor_x += space_width
					continue
				}

				c_word := fmt.ctprintf("%s", word)
				w, h: i32
				ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
				word_width := f32(w)

				if el.resolved_text_wrap == .WORD &&
				   cursor_x + word_width > max_width &&
				   cursor_x > 0 {
					cursor_x = 0
					total_lines += 1.0
				}
				cursor_x += word_width + space_width
			}
		}
	}
	return max(total_lines, 1.0) * line_height
}

@(private)
default_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Non-inherited visual defaults
	// ------------------------------------------------------------

	el.resolved_bg_image = nil
	el.resolved_object_fit = .STRETCH


	el.resolved_bg_color = {0, 0, 0, 0}
	el.resolved_border_color = {0, 0, 0, 0}
	el.resolved_border_radius = {0, 0, 0, 0}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	// Typography is inherited from the parent.
	if el._box.parent != nil && el._box.parent.user_data != nil {
		parent := (^Element)(el._box.parent.user_data)

		el.resolved_text_color = parent.resolved_text_color
		el.resolved_text_align = parent.resolved_text_align

		el.resolved_text_wrap = parent.resolved_text_wrap
		el.resolved_opacity = parent.resolved_opacity

		el.resolved_font_name = parent.resolved_font_name
		el.resolved_font_size = parent.resolved_font_size
		el.resolved_font_spacing = parent.resolved_font_spacing
		el.resolved_font = parent.resolved_font
		el.resolved_font_style = parent.resolved_font_style
	} else {
		// Root defaults.
		el.resolved_text_color = {0, 0, 0, 1}
		el.resolved_text_align = .LEFT

		el.resolved_font_size = 16.0
		el.resolved_font_spacing = 1.0
		el.resolved_font_style = {}

		el.resolved_text_wrap = .WORD
		el.resolved_opacity = 1.0

		el.resolved_font = get_font(ctx, el.resolved_font_name, el.resolved_font_size)
	}
}

@(private)
apply_style_block :: proc(el: ^Element, s: Style, ctx: ^UI_Context) {
	// ------------------------------------------------------------
	// Visuals
	// ------------------------------------------------------------

	if v, ok := s.bg_image.?; ok {
		el.resolved_bg_image = v
	}

	if v, ok := s.object_fit.?; ok {
		el.resolved_object_fit = v
	}

	if v, ok := s.bg_color.?; ok {
		el.resolved_bg_color = v
	}

	if v, ok := s.border_color.?; ok {
		el.resolved_border_color = v
	}

	if v, ok := s.border_radius.?; ok {
		el.resolved_border_radius = v
	}

	if v, ok := s.opacity.?; ok {
		el.resolved_opacity = v
	}

	// ------------------------------------------------------------
	// Typography
	// ------------------------------------------------------------

	if v, ok := s.text_wrap.?; ok {
		el.resolved_text_wrap = v
	}

	if v, ok := s.text_color.?; ok {
		el.resolved_text_color = v
	}

	if v, ok := s.text_align.?; ok {
		el.resolved_text_align = v
	}

	font_changed := false

	if v, ok := s.font_size.?; ok {
		el.resolved_font_size = v
		font_changed = true
	}

	if v, ok := s.font_name.?; ok {
		el.resolved_font_name = v
		font_changed = true
	}

	if font_changed {
		el.resolved_font = get_font(ctx, el.resolved_font_name, el.resolved_font_size)
	}

	if v, ok := s.font_spacing.?; ok {
		el.resolved_font_spacing = v
	}

	if v, ok := s.font_style.?; ok {
		el.resolved_font_style = v
	}

	if v, ok := s.font_name.?; ok {
		// Fetch the font dynamically, inheriting size if omitted
		font_size := s.font_size.? or_else el.resolved_font_size
		el.resolved_font = get_font(ctx, v, font_size)
	}

	// ------------------------------------------------------------
	// Spacing / layout
	// ------------------------------------------------------------

	if v, ok := s.gap.?; ok {
		el._box.gap = v
	}

	if v, ok := s.margin.?; ok {
		el._box.margin = v
	}

	if v, ok := s.padding.?; ok {
		el._box.padding = v
	}

	if v, ok := s.border.?; ok {
		el._box.border = v
	}

	// ------------------------------------------------------------
	// Flex
	// ------------------------------------------------------------

	if v, ok := s.wrap.?; ok {
		el._box.wrap = v
	}

	if v, ok := s.basis.?; ok {
		el._box.basis = v
	}

	if v, ok := s.direction.?; ok {
		el._box.direction = v
	}

	if v, ok := s.align_items.?; ok {
		el._box.align_items = v
	}

	if v, ok := s.justify_content.?; ok {
		el._box.justify_content = v
	}

	// ------------------------------------------------------------
	// Position
	// ------------------------------------------------------------

	if v, ok := s.position.?; ok {
		el._box.position = v
	}

	if v, ok := s.top.?; ok {
		el._box.top = v
	}

	if v, ok := s.left.?; ok {
		el._box.left = v
	}

	if v, ok := s.right.?; ok {
		el._box.right = v
	}

	if v, ok := s.bottom.?; ok {
		el._box.bottom = v
	}

	// ------------------------------------------------------------
	// Scrolling
	// ------------------------------------------------------------

	if v, ok := s.overflow_x.?; ok {
		el._box.overflow_x = v
	}

	if v, ok := s.overflow_y.?; ok {
		el._box.overflow_y = v
	}

	// ------------------------------------------------------------
	// Size
	// ------------------------------------------------------------

	if v, ok := s.width.?; ok {
		el._box.width = v
	}

	if v, ok := s.height.?; ok {
		el._box.height = v
	}

	if v, ok := s.min_width.?; ok {
		el._box.min_width = v
	}

	if v, ok := s.max_width.?; ok {
		el._box.max_width = v
	}

	if v, ok := s.min_height.?; ok {
		el._box.min_height = v
	}

	if v, ok := s.max_height.?; ok {
		el._box.max_height = v
	}

	// ------------------------------------------------------------
	// Stacking
	// ------------------------------------------------------------

	if v, ok := s.z_index.?; ok {
		el._box.z_index = v
	}
}

@(private)
apply_styles :: proc(el: ^Element, ctx: ^UI_Context) {
	default_styles(el, ctx)

	for cls in el.classes {
		if class_style, exists := ctx.stylesheet[cls]; exists {
			apply_style_block(el, class_style, ctx)
		}
	}

	apply_style_block(el, el.style, ctx)
}

// Merges a sparse override style on top of a base default style.
@(private)
merge_styles :: proc(base: Style, override: Style) -> Style {
	result := base

	// Sizing & Bounds
	if override.width != nil do result.width = override.width
	if override.height != nil do result.height = override.height
	if override.min_width != nil do result.min_width = override.min_width
	if override.max_width != nil do result.max_width = override.max_width
	if override.min_height != nil do result.min_height = override.min_height
	if override.max_height != nil do result.max_height = override.max_height

	// Spacing
	if override.padding != nil do result.padding = override.padding
	if override.margin != nil do result.margin = override.margin
	if override.border != nil do result.border = override.border
	if override.gap != nil do result.gap = override.gap

	// Flexbox
	if override.direction != nil do result.direction = override.direction
	if override.justify_content != nil do result.justify_content = override.justify_content
	if override.align_items != nil do result.align_items = override.align_items
	if override.wrap != nil do result.wrap = override.wrap
	if override.basis != nil do result.basis = override.basis

	// Visuals
	if override.bg_color != nil do result.bg_color = override.bg_color
	if override.bg_image != nil do result.bg_image = override.bg_image
	if override.object_fit != nil do result.object_fit = override.object_fit
	if override.border_color != nil do result.border_color = override.border_color
	if override.border_radius != nil do result.border_radius = override.border_radius
	if override.opacity != nil do result.opacity = override.opacity

	// Text & Typography
	if override.text_color != nil do result.text_color = override.text_color
	if override.text_align != nil do result.text_align = override.text_align
	if override.text_wrap != nil do result.text_wrap = override.text_wrap
	if override.font_name != nil do result.font_name = override.font_name
	if override.font_size != nil do result.font_size = override.font_size
	if override.font_spacing != nil do result.font_spacing = override.font_spacing
	if override.font_style != nil do result.font_style = override.font_style
	if override.selection_start != nil do result.selection_start = override.selection_start
	if override.selection_end != nil do result.selection_end = override.selection_end
	if override.selection_color != nil do result.selection_color = override.selection_color

	// Positioning
	if override.position != nil do result.position = override.position
	if override.top != nil do result.top = override.top
	if override.left != nil do result.left = override.left
	if override.right != nil do result.right = override.right
	if override.bottom != nil do result.bottom = override.bottom
	if override.z_index != nil do result.z_index = override.z_index

	// Scrolling
	if override.overflow_x != nil do result.overflow_x = override.overflow_x
	if override.overflow_y != nil do result.overflow_y = override.overflow_y

	return result
}

@(private)
set_clip :: proc(renderer: ^sdl.Renderer, current: ^Maybe(Rect), target: Maybe(Rect)) {
	if current^ == target do return

	if t, ok := target.?; ok {
		clip_rect := sdl.Rect{i32(t.x), i32(t.y), i32(t.width), i32(t.height)}
		sdl.RenderSetClipRect(renderer, &clip_rect)
	} else {
		sdl.RenderSetClipRect(renderer, nil) // Removes the clip
	}
	current^ = target
}

@(private)
render_box :: proc(
	ui_ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	box: ^Box,
	current_clip: ^Maybe(Rect),
) {
	previous_clip := current_clip^

	set_clip(renderer, current_clip, box.clip_rect)

	if box.user_data == nil do return
	el := (^Element)(box.user_data)

	bg_color := el.resolved_bg_color
	bg_color[3] *= el.resolved_opacity

	border_color := el.resolved_border_color
	border_color[3] *= el.resolved_opacity

	bounds := sdl.Rect{i32(box.x), i32(box.y), i32(box.computed_width), i32(box.computed_height)}

	sdl.SetRenderDrawBlendMode(renderer, .BLEND)

	draw_ui_box(
		ui_ctx,
		renderer,
		bounds,
		bg_color,
		border_color,
		box.border,
		el.resolved_border_radius,
	)

	// --- Draw Image/Video Texture ---
	if el.resolved_bg_image != nil {
		sdl.SetTextureAlphaMod(el.resolved_bg_image, u8(el.resolved_opacity * 255.0))

		// Inset the image so it doesn't draw over your borders
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(box.border[3]),
			y = bounds.y + i32(box.border[0]),
			w = bounds.w - i32(box.border[3] + box.border[1]),
			h = bounds.h - i32(box.border[0] + box.border[2]),
		}

		tex_w, tex_h: i32
		sdl.QueryTexture(el.resolved_bg_image, nil, nil, &tex_w, &tex_h)

		src_rect := sdl.Rect{0, 0, tex_w, tex_h}
		dst_rect := inner_bounds

		if tex_w > 0 && tex_h > 0 && inner_bounds.w > 0 && inner_bounds.h > 0 {
			tex_ratio := f32(tex_w) / f32(tex_h)
			box_ratio := f32(inner_bounds.w) / f32(inner_bounds.h)

			#partial switch el.resolved_object_fit {
			case .CONTAIN:
				if tex_ratio > box_ratio {
					dst_rect.w = inner_bounds.w
					dst_rect.h = i32(f32(inner_bounds.w) / tex_ratio)
					dst_rect.y = inner_bounds.y + (inner_bounds.h - dst_rect.h) / 2
				} else {
					dst_rect.h = inner_bounds.h
					dst_rect.w = i32(f32(inner_bounds.h) * tex_ratio)
					dst_rect.x = inner_bounds.x + (inner_bounds.w - dst_rect.w) / 2
				}
			case .COVER:
				if tex_ratio > box_ratio {
					crop_w := i32(f32(tex_h) * box_ratio)
					src_rect.x = (tex_w - crop_w) / 2
					src_rect.w = crop_w
				} else {
					crop_h := i32(f32(tex_w) / box_ratio)
					src_rect.y = (tex_h - crop_h) / 2
					src_rect.h = crop_h
				}
			case .NONE:
				dst_rect.w = min(tex_w, inner_bounds.w)
				dst_rect.h = min(tex_h, inner_bounds.h)
				dst_rect.x = inner_bounds.x + (inner_bounds.w - dst_rect.w) / 2
				dst_rect.y = inner_bounds.y + (inner_bounds.h - dst_rect.h) / 2
				src_rect.w = dst_rect.w
				src_rect.h = dst_rect.h
				src_rect.x = (tex_w - src_rect.w) / 2
				src_rect.y = (tex_h - src_rect.h) / 2
			}
		}

		corner_radius := i32(el.resolved_border_radius[0])

		if corner_radius > 0 {
			// Create a clipping blend mode (Src * DstColor, SrcAlpha * DstAlpha)
			clip_blend := sdl.ComposeCustomBlendMode(
				.DST_COLOR,
				.ZERO,
				.ADD,
				.DST_ALPHA,
				.ZERO,
				.ADD,
			)

			// Grab our shared layout mask

			mask_tex := get_mask_texture(ui_ctx, renderer, dst_rect.w, dst_rect.h)
			prev_target := sdl.GetRenderTarget(renderer)

			// Switch to mask target safely
			sdl.SetRenderTarget(renderer, mask_tex)
			defer sdl.SetRenderTarget(renderer, prev_target)

			// Clear ONLY the portion of the texture we are using this frame
			prev_blend: sdl.BlendMode
			sdl.GetRenderDrawBlendMode(renderer, &prev_blend)
			sdl.SetRenderDrawBlendMode(renderer, .NONE) // Force overwrite pixels (including alpha)

			sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0)

			clear_rect := sdl.Rect{0, 0, dst_rect.w, dst_rect.h}

			sdl.GetRenderDrawBlendMode(renderer, &prev_blend)
			sdl.SetRenderDrawBlendMode(renderer, .NONE)
			sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0)

			// Clear only the active region
			sdl.RenderFillRect(renderer, &clear_rect)

			sdl.SetRenderDrawBlendMode(renderer, prev_blend)

			// Draw an opaque white 9-slice mask at the origin
			tex_9slice := get_9slice_texture(ui_ctx, renderer)
			draw_rounded_rect_9slice(
				renderer,
				tex_9slice,
				clear_rect,
				corner_radius,
				sdl.Color{255, 255, 255, 255},
			)

			// Stamp the image onto the mask using our custom blend
			sdl.SetTextureBlendMode(el.resolved_bg_image, clip_blend)
			sdl.RenderCopy(renderer, el.resolved_bg_image, &src_rect, &clear_rect)

			// Draw the finalized composite to the screen
			sdl.SetTextureBlendMode(el.resolved_bg_image, .BLEND)
			sdl.SetRenderTarget(renderer, prev_target)

			// We only copy the specific `clear_rect` dimensions from the mask!
			sdl.RenderCopy(renderer, mask_tex, &clear_rect, &dst_rect)
		} else {
			// Fallback to standard fast-path for non-rounded images
			sdl.RenderCopy(renderer, el.resolved_bg_image, &src_rect, &dst_rect)
		}
	}

	// --- Custom Canvas Rendering ---
	if el.custom_render != nil {
		// Calculate the inner bounds so custom drawings respect layout padding and borders
		inner_bounds := sdl.Rect {
			x = bounds.x + i32(box.border[3] + box.padding[3]),
			y = bounds.y + i32(box.border[0] + box.padding[0]),
			w = bounds.w - i32(box.border[3] + box.border[1] + box.padding[3] + box.padding[1]),
			h = bounds.h - i32(box.border[0] + box.border[2] + box.padding[0] + box.padding[2]),
		}

		// Ensure raw SDL calls don't bleed outside the component or scroll-view bounds
		current_sdl_clip: sdl.Rect
		sdl.RenderGetClipRect(renderer, &current_sdl_clip)
		has_clip := sdl.RenderIsClipEnabled(renderer)

		canvas_clip := inner_bounds
		if has_clip {
			sdl.IntersectRect(&current_sdl_clip, &canvas_clip, &canvas_clip)
		}
		sdl.RenderSetClipRect(renderer, &canvas_clip)

		// Fire the custom drawing code!
		el.custom_render(renderer, inner_bounds, el.custom_render_data)

		// Restore the previous clipping state
		if has_clip do sdl.RenderSetClipRect(renderer, &current_sdl_clip)
		else do sdl.RenderSetClipRect(renderer, nil)
	}

	// Draw Cached Text
	if text, ok := box.text.?; ok {
		if el.resolved_font != nil {
			text_x := box.x + box.padding[Side.LEFT] + box.border[Side.LEFT]
			text_y := box.y + box.padding[Side.TOP] + box.border[Side.TOP]

			inner_width := max(
				box.computed_width - get_horizontal(box.padding) - get_horizontal(box.border),
				0.0,
			)

			space_w, space_h: i32
			ttf.SizeUTF8(el.resolved_font, " ", &space_w, &space_h)
			space_width := f32(space_w)
			line_height := f32(ttf.FontHeight(el.resolved_font))

			cursor_y := text_y
			global_char_idx := 0
			explicit_lines := strings.split(text, "\n", context.temp_allocator)

			for explicit_line in explicit_lines {
				if el.resolved_text_wrap == .LETTER {
					runes := utf8.string_to_runes(explicit_line, context.temp_allocator)
					start_idx := 0
					for start_idx < len(runes) {
						end_idx := start_idx
						line_width: f32 = 0.0

						for end_idx < len(runes) {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[end_idx])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0

							w, h: i32
							ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)
							rune_width := f32(w)

							if line_width + rune_width > inner_width && end_idx > start_idx {
								break
							}
							line_width += rune_width
							end_idx += 1
						}

						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						for i in start_idx ..< end_idx {
							buf: [5]u8
							bytes, n := utf8.encode_rune(runes[i])
							for j in 0 ..< n do buf[j] = bytes[j]
							buf[n] = 0
							rune_str := string(buf[:n])

							w, h: i32
							ttf.SizeUTF8(el.resolved_font, cstring(&buf[0]), &w, &h)

							if s, ok1 := el.style.selection_start.?; ok1 {
								if e, ok2 := el.style.selection_end.?; ok2 {
									if global_char_idx >= min(s, e) &&
									   global_char_idx < max(s, e) {
										sel_col :=
											el.style.selection_color.? or_else Color {
												0.2,
												0.5,
												0.9,
												0.4,
											}
										set_render_color(renderer, sel_col)

										bg_rect := sdl.Rect {
											i32(cursor_x),
											i32(cursor_y),
											w,
											i32(line_height),
										}
										sdl.RenderFillRect(renderer, &bg_rect)
									}
								}
							}

							text_color := el.resolved_text_color
							text_color[3] *= el.resolved_opacity

							draw_ui_text(
								ui_ctx,
								renderer,
								el.resolved_font,
								rune_str,
								i32(cursor_x),
								i32(cursor_y),
								text_color,
							)

							cursor_x += f32(w)
							global_char_idx += 1
						}
						cursor_y += line_height
						start_idx = end_idx
					}
				} else {
					words := strings.split(explicit_line, " ", context.temp_allocator)
					start_idx := 0
					for start_idx < len(words) {
						end_idx := start_idx
						line_width: f32 = 0.0

						for end_idx < len(words) {
							word_width: f32 = 0.0
							if len(words[end_idx]) > 0 {
								c_word := fmt.ctprintf("%s", words[end_idx])
								w, h: i32
								ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)
								word_width = f32(w)
							}
							if el.resolved_text_wrap == .WORD &&
							   end_idx > start_idx &&
							   line_width + word_width > inner_width {
								break
							}
							line_width += word_width + space_width
							end_idx += 1
						}

						if end_idx > start_idx do line_width -= space_width

						start_x := text_x
						if el.resolved_text_align == .CENTER {
							start_x += max((inner_width - line_width) / 2.0, 0.0)
						} else if el.resolved_text_align == .RIGHT {
							start_x += max(inner_width - line_width, 0.0)
						}
						cursor_x := start_x

						for i in start_idx ..< end_idx {
							if len(words[i]) > 0 {
								word_runes := utf8.string_to_runes(
									words[i],
									context.temp_allocator,
								)
								word_len := len(word_runes)

								c_word := fmt.ctprintf("%s", words[i])
								w, h: i32
								ttf.SizeUTF8(el.resolved_font, c_word, &w, &h)

								if s, ok1 := el.style.selection_start.?; ok1 {
									if e, ok2 := el.style.selection_end.?; ok2 {
										s_idx, e_idx := min(s, e), max(s, e)
										if s_idx < global_char_idx + word_len &&
										   e_idx > global_char_idx {
											overlap_s :=
												max(s_idx, global_char_idx) - global_char_idx
											overlap_e :=
												min(e_idx, global_char_idx + word_len) -
												global_char_idx

											pre_str := utf8.runes_to_string(
												word_runes[:overlap_s],
												context.temp_allocator,
											)
											hl_str := utf8.runes_to_string(
												word_runes[overlap_s:overlap_e],
												context.temp_allocator,
											)

											pre_w, hl_w: i32 = 0, 0
											if len(pre_str) > 0 do ttf.SizeUTF8(el.resolved_font, fmt.ctprintf("%s", pre_str), &pre_w, nil)
											ttf.SizeUTF8(
												el.resolved_font,
												fmt.ctprintf("%s", hl_str),
												&hl_w,
												nil,
											)

											// ---> FIX 1: Extend highlight to cover the trailing space
											if e_idx > global_char_idx + word_len {
												hl_w += i32(space_width)
											}

											sel_col :=
												el.style.selection_color.? or_else Color {
													0.2,
													0.5,
													0.9,
													0.4,
												}
											set_render_color(renderer, sel_col)

											bg_rect := sdl.Rect {
												i32(cursor_x) + pre_w,
												i32(cursor_y),
												hl_w,
												i32(line_height),
											}
											sdl.RenderFillRect(renderer, &bg_rect)
										}
									}
								}

								text_color := el.resolved_text_color
								text_color[3] *= el.resolved_opacity

								draw_ui_text(
									ui_ctx,
									renderer,
									el.resolved_font,
									words[i],
									i32(cursor_x),
									i32(cursor_y),
									text_color,
								)

								cursor_x += f32(w) + space_width
								global_char_idx += word_len + 1
							} else {
								// ---> FIX 2: Highlight standalone consecutive spaces
								if s, ok1 := el.style.selection_start.?; ok1 {
									if e, ok2 := el.style.selection_end.?; ok2 {
										s_idx, e_idx := min(s, e), max(s, e)
										if s_idx <= global_char_idx && e_idx > global_char_idx {
											sel_col :=
												el.style.selection_color.? or_else Color {
													0.2,
													0.5,
													0.9,
													0.4,
												}
											set_render_color(renderer, sel_col)
											bg_rect := sdl.Rect {
												i32(cursor_x),
												i32(cursor_y),
												i32(space_width),
												i32(line_height),
											}
											sdl.RenderFillRect(renderer, &bg_rect)
										}
									}
								}

								cursor_x += space_width
								global_char_idx += 1
							}
						}
						cursor_y += line_height
						start_idx = end_idx
					}
					global_char_idx += 1
				}
			}
		}
	}

	for child in box.children {
		render_box(ui_ctx, renderer, child, current_clip)
	}

	// RESTORE the caller's clip state before returning
	set_clip(renderer, current_clip, previous_clip)
}

@(private)
render_tree :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, root_boxes: []^Box) {
	current_clip: Maybe(Rect) = nil
	for root_box in root_boxes {
		render_box(ctx, renderer, root_box, &current_clip)
	}

	if current_clip != nil {
		sdl.RenderSetClipRect(renderer, nil)
	}
}

@(private)
get_text_texture :: proc(
	ctx: ^UI_Context,
	renderer: ^sdl.Renderer,
	font: ^ttf.Font,
	text: string,
	color: Color,
) -> Cached_Texture {
	r, g, b, a := to_sdl_color(color)
	key := Text_Key {
		font = font,
		text = text,
		r    = r,
		g    = g,
		b    = b,
		a    = a,
	}

	if cached, exists := ctx.text_cache[key]; exists {
		return cached
	}

	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	sdl_col := sdl.Color{r, g, b, a}

	surface := ttf.RenderUTF8_Blended(font, c_text, sdl_col)

	cached := Cached_Texture{}
	if surface != nil {
		cached.texture = sdl.CreateTextureFromSurface(renderer, surface)
		cached.width = surface.w
		cached.height = surface.h
		sdl.SetTextureBlendMode(cached.texture, .BLEND)
		sdl.FreeSurface(surface)
	}

	// Clone into a stable allocator before storing — `text` is very often a
	// temp-allocated fmt.tprintf() result that will be invalidated/reused
	// once the temp arena resets, which would corrupt this key on future lookups.
	key.text = strings.clone(text)
	ctx.text_cache[key] = cached
	return cached
}

@(private)
clear_text_cache :: proc(ctx: ^UI_Context) {
	for key, cached in ctx.text_cache {
		if cached.texture != nil do sdl.DestroyTexture(cached.texture)
		delete(key.text)
	}
	clear(&ctx.text_cache)
}

ui_context_create :: proc(screen_width, screen_height: f32) -> ^UI_Context {
	ctx := new(UI_Context)

	// Pass the SDL text measurement functions to the layout core
	ctx.layout = layout_context_create(ui_text_width, ui_text_height, screen_width, screen_height)

	ctx.stylesheet = make(map[Class]Style)
	ctx.fonts = make(map[u32]^ttf.Font)
	ctx.videos = make(map[string]^Video_Player)
	ctx.font_cache = make(map[Font_Key]^ttf.Font)
	ctx.text_cache = make(map[Text_Key]Cached_Texture)
	ctx.image_cache = make(map[u32]^sdl.Texture)

	return ctx
}

ui_context_destroy :: proc(ctx: ^UI_Context) {
	layout_context_destroy(ctx.layout)
	clear_text_cache(ctx)
	delete(ctx.text_cache)

	// Purge GPU textures before destroying the map
	// clear_texture_cache(ctx)
	if ctx.mask_texture != nil do sdl.DestroyTexture(ctx.mask_texture)
	for _, tex in ctx.image_cache {
		if tex != nil do sdl.DestroyTexture(tex)
	}
	delete(ctx.image_cache)
	for key, font in ctx.font_cache do ttf.CloseFont(font)
	delete(ctx.font_cache)

	delete(ctx.stylesheet)
	delete(ctx.fonts)
	delete(ctx.videos)
	free(ctx)

	when ODIN_DEBUG {
		for _, name in g_debug_id_registry do delete(name)
		delete(g_debug_id_registry)

		for _, name in g_debug_class_registry do delete(name)
		delete(g_debug_class_registry)
	}
}

ui_begin_frame :: proc(ctx: ^UI_Context, renderer: ^sdl.Renderer, screen_w, screen_h: i32) {
	// Note: Event processing and pointer state updates will go here next

	ctx.layout.screen_width = f32(screen_w)
	ctx.layout.screen_height = f32(screen_h)
	begin_layout(ctx.layout)
}

ui_layout_tree :: proc(ctx: ^UI_Context) -> []^Box {
	return ctx.layout.root_boxes[:]
}

ui_compute :: proc(ctx: ^UI_Context) {
	end_layout(ctx.layout)
}


element_open :: proc(app: ^App, el_val: Element, loc := #caller_location) -> ^Element {
	ctx := app.ui
	el := new(Element, frame_allocator(ctx.layout))
	el^ = el_val

	// Auto-generate an ID if omitted, natively tracking it in layout_calc
	if el._box.id == 0 {
		el._box.id = ID(loc)
	}

	apply_styles(el, ctx)
	el._box.user_data = el
	box_open(ctx.layout, el._box, loc)

	return el
}

element_close :: proc(app: ^App) {
	box_close(app.ui.layout)
}

COLOR_WHITE :: Color{1.0, 1.0, 1.0, 1.0}
COLOR_BLACK :: Color{0.0, 0.0, 0.0, 1.0}
COLOR_TRANSPARENT :: Color{0.0, 0.0, 0.0, 0.0}
COLOR_RED :: Color{1.0, 0.0, 0.0, 1.0}

// Assuming standard 0xRRGGBBAA format
hex :: proc(val: u32) -> Color {
	return Color {
		f32((val >> 24) & 0xFF) / 255.0,
		f32((val >> 16) & 0xFF) / 255.0,
		f32((val >> 8) & 0xFF) / 255.0,
		f32(val & 0xFF) / 255.0,
	}
}

// For standard 6-character web hex where alpha is assumed 1.0 (0xRRGGBB)
hex_rgb :: proc(val: u32) -> Color {
	return Color {
		f32((val >> 16) & 0xFF) / 255.0,
		f32((val >> 8) & 0xFF) / 255.0,
		f32(val & 0xFF) / 255.0,
		1.0,
	}
}

with_alpha :: proc(c: Color, alpha: f32) -> Color {
	return Color{c[0], c[1], c[2], alpha}
}

// h: 0..360, s: 0.0..1.0, l: 0.0..1.0
hsl :: proc(h, s, l: f32, a: f32 = 1.0) -> Color {
	// Wrap hue to ensure it stays strictly within 0-360
	hue := math.mod_f32(h, 360.0)
	if hue < 0.0 do hue += 360.0

	c := (1.0 - math.abs(2.0 * l - 1.0)) * s
	h_prime := hue / 60.0
	x := c * (1.0 - math.abs(math.mod_f32(h_prime, 2.0) - 1.0))
	m := l - c / 2.0

	r, g, b: f32
	if h_prime <
	   1.0 {r, g, b = c, x, 0} else if h_prime < 2.0 {r, g, b = x, c, 0} else if h_prime < 3.0 {r, g, b = 0, c, x} else if h_prime < 4.0 {r, g, b = 0, x, c} else if h_prime < 5.0 {r, g, b = x, 0, c} else {r, g, b = c, 0, x}

	return Color{r + m, g + m, b + m, a}
}

// h: 0..360, s: 0.0..1.0, v: 0.0..1.0
hsv :: proc(h, s, v: f32, a: f32 = 1.0) -> Color {
	hue := math.mod_f32(h, 360.0)
	if hue < 0.0 do hue += 360.0

	c := v * s
	h_prime := hue / 60.0
	x := c * (1.0 - math.abs(math.mod_f32(h_prime, 2.0) - 1.0))
	m := v - c

	r, g, b: f32
	if h_prime <
	   1.0 {r, g, b = c, x, 0} else if h_prime < 2.0 {r, g, b = x, c, 0} else if h_prime < 3.0 {r, g, b = 0, c, x} else if h_prime < 4.0 {r, g, b = 0, x, c} else if h_prime < 5.0 {r, g, b = x, 0, c} else {r, g, b = c, 0, x}

	return Color{r + m, g + m, b + m, a}
}
