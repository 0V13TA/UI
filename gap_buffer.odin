package UI

import "core:strings"
import "core:unicode/utf8"

Gap_Buffer :: struct {
	buffer:    [dynamic]u8,
	gap_start: int,
	gap_end:   int,
	anchor:    int,
}

gap_buffer_init :: proc(gb: ^Gap_Buffer, initial_capacity: int = 1024) {
	gb.buffer = make([dynamic]u8, initial_capacity)
	gb.gap_start = 0
	gb.gap_end = initial_capacity
	gb.anchor = 0
}

gap_buffer_has_selection :: proc(gb: ^Gap_Buffer) -> bool {
	return gb.gap_start != gb.anchor
}

gap_buffer_delete_selection :: proc(gb: ^Gap_Buffer) -> bool {
	if !gap_buffer_has_selection(gb) do return false

	start_idx := min(gb.gap_start, gb.anchor)
	end_idx := max(gb.gap_start, gb.anchor)

	// 1. Move the gap to the end of the selection
	gap_buffer_move_cursor(gb, end_idx, true)

	// 2. Swallow the text before the gap by simply pulling gap_start backward
	shift := end_idx - start_idx
	gb.gap_start -= shift

	// 3. Collapse the anchor
	gb.anchor = gb.gap_start
	return true
}

gap_buffer_get_substring :: proc(
	gb: ^Gap_Buffer,
	start_idx, end_idx: int,
	allocator := context.temp_allocator,
) -> string {
	length := end_idx - start_idx
	if length <= 0 do return ""

	res := make([]u8, length, allocator)

	for i in 0 ..< length {
		logical := start_idx + i
		if logical < gb.gap_start {
			res[i] = gb.buffer[logical] // Before gap
		} else {
			res[i] = gb.buffer[gb.gap_end + (logical - gb.gap_start)] // After gap
		}
	}
	return string(res)
}

gap_buffer_destroy :: proc(gb: ^Gap_Buffer) {
	delete(gb.buffer)
}

gap_buffer_length :: proc(gb: ^Gap_Buffer) -> int {
	return gb.gap_start + (len(gb.buffer) - gb.gap_end)
}

// Expands the gap if the required space exceeds current gap capacity
@(private = "file")
gap_buffer_expand :: proc(gb: ^Gap_Buffer, min_space: int) {
	current_space := gb.gap_end - gb.gap_start
	if current_space >= min_space do return

	old_capacity := len(gb.buffer)
	new_capacity := max(old_capacity * 2, old_capacity + min_space)
	resize(&gb.buffer, new_capacity)

	tail_len := old_capacity - gb.gap_end
	new_gap_end := new_capacity - tail_len

	// Shift the text after the gap to the end of the newly resized buffer
	if tail_len > 0 {
		copy(gb.buffer[new_gap_end:], gb.buffer[gb.gap_end:old_capacity])
	}
	gb.gap_end = new_gap_end
}


// --- UTF-8 Aware Operations ---

gap_buffer_insert_rune :: proc(gb: ^Gap_Buffer, r: rune) {
	buf: [4]u8
	bytes, w := utf8.encode_rune(r)
	for i in 0 ..< w do buf[i] = bytes[i]
	gap_buffer_insert_string(gb, string(buf[:w]))
}

gap_buffer_insert_string :: proc(gb: ^Gap_Buffer, text: string) {
	if len(text) == 0 do return
	gap_buffer_expand(gb, len(text))

	copy(gb.buffer[gb.gap_start:], transmute([]u8)text)
	gb.gap_start += len(text)
	gb.anchor = gb.gap_start // Force anchor to follow the cursor
}

gap_buffer_backspace :: proc(gb: ^Gap_Buffer) {
	if gb.gap_start == 0 do return
	_, w := utf8.decode_last_rune(gb.buffer[:gb.gap_start])
	gb.gap_start -= w
	gb.anchor = gb.gap_start // Collapse selection state
}

gap_buffer_delete :: proc(gb: ^Gap_Buffer) {
	if gb.gap_end == len(gb.buffer) do return
	_, w := utf8.decode_rune(gb.buffer[gb.gap_end:])
	gb.gap_end += w
	gb.anchor = gb.gap_start // Collapse selection state
}

// Generates a contiguous string for rendering
gap_buffer_to_string :: proc(gb: ^Gap_Buffer, allocator := context.temp_allocator) -> string {
	res := make([]u8, gap_buffer_length(gb), allocator)

	// Copy left side
	copy(res[:gb.gap_start], gb.buffer[:gb.gap_start])
	// Copy right side
	if len(gb.buffer) > gb.gap_end {
		copy(res[gb.gap_start:], gb.buffer[gb.gap_end:])
	}

	return string(res)
}

gap_buffer_move_cursor :: proc(gb: ^Gap_Buffer, logical_pos: int, keep_anchor: bool = false) {
	pos := clamp(logical_pos, 0, gap_buffer_length(gb))

	if pos < gb.gap_start {
		shift := gb.gap_start - pos
		copy(gb.buffer[gb.gap_end - shift:gb.gap_end], gb.buffer[pos:gb.gap_start])
		gb.gap_start -= shift
		gb.gap_end -= shift
	} else if pos > gb.gap_start {
		shift := pos - gb.gap_start
		copy(
			gb.buffer[gb.gap_start:gb.gap_start + shift],
			gb.buffer[gb.gap_end:gb.gap_end + shift],
		)
		gb.gap_start += shift
		gb.gap_end += shift
	}

	if !keep_anchor do gb.anchor = gb.gap_start
}

gap_buffer_move_left :: proc(gb: ^Gap_Buffer, keep_anchor: bool = false) {
	if gb.gap_start == 0 {
		if !keep_anchor do gb.anchor = 0
		return
	}
	_, w := utf8.decode_last_rune(gb.buffer[:gb.gap_start])
	gap_buffer_move_cursor(gb, gb.gap_start - w, keep_anchor)
}

gap_buffer_move_right :: proc(gb: ^Gap_Buffer, keep_anchor: bool = false) {
	if gb.gap_end == len(gb.buffer) {
		if !keep_anchor do gb.anchor = gap_buffer_length(gb)
		return
	}
	_, w := utf8.decode_rune(gb.buffer[gb.gap_end:])
	gap_buffer_move_cursor(gb, gb.gap_start + w, keep_anchor)
}

gap_buffer_move_up :: proc(gb: ^Gap_Buffer, keep_anchor: bool) {
	str := gap_buffer_to_string(gb, context.temp_allocator)
	cursor := gb.gap_start

	line_start := strings.last_index_byte(str[:cursor], '\n')
	if line_start == -1 {
		gap_buffer_move_cursor(gb, 0, keep_anchor)
		return
	}

	col := cursor - (line_start + 1)
	prev_line_start := strings.last_index_byte(str[:line_start], '\n')

	target := (prev_line_start + 1) + col
	if target > line_start {
		target = line_start
	}

	gap_buffer_move_cursor(gb, target, keep_anchor)
}

gap_buffer_move_down :: proc(gb: ^Gap_Buffer, keep_anchor: bool) {
	str := gap_buffer_to_string(gb, context.temp_allocator)
	cursor := gb.gap_start

	line_start := strings.last_index_byte(str[:cursor], '\n')
	col := cursor - (line_start + 1)

	next_line_end := strings.index_byte(str[cursor:], '\n')
	if next_line_end == -1 {
		gap_buffer_move_cursor(gb, len(str), keep_anchor)
		return
	}

	next_line_start := cursor + next_line_end + 1
	target := next_line_start + col

	next_next_line_end := strings.index_byte(str[next_line_start:], '\n')
	max_target := next_next_line_end == -1 ? len(str) : next_line_start + next_next_line_end

	if target > max_target {
		target = max_target
	}

	gap_buffer_move_cursor(gb, target, keep_anchor)
}
