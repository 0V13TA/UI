package UI

import "core:testing"
import "core:unicode/utf8"

@(test)
test_text_cursor_uses_utf8_rune_offsets :: proc(t: ^testing.T) {
	text := "Aé🙂Z"

	testing.expect_value(t, utf8_rune_count(text), 4)
	testing.expect_value(t, utf8_byte_offset(text, 0), 0)
	testing.expect_value(t, utf8_byte_offset(text, 1), 1)
	testing.expect_value(t, utf8_byte_offset(text, 2), 3)
	testing.expect_value(t, utf8_byte_offset(text, 3), 7)
	testing.expect_value(t, utf8_byte_offset(text, 4), len(text))
	testing.expect_value(t, utf8_byte_offset(text, 20), len(text))
}

@(test)
test_text_input_backspace_removes_one_utf8_rune :: proc(t: ^testing.T) {
	buffer := make([dynamic]u8, context.temp_allocator)
	append(&buffer, "Aé🙂Z")

	input_id := Box_ID(1)
	ctx := Event_Context {
		text_cursors = make(map[Box_ID]int, context.temp_allocator),
		text_selection = make(map[Box_ID]int, context.temp_allocator),
		focused_buffer = &buffer,
	}
	ctx.text_cursors[input_id] = 3
	ctx.text_selection[input_id] = 3

	event := UI_Event{current_target = input_id, keycode = .BACKSPACE}
	_key_down_cb(&event, &ctx)

	testing.expect_value(t, string(buffer[:]), "AéZ")
	testing.expect_value(t, ctx.text_cursors[input_id], 2)
	testing.expect_value(t, ctx.text_selection[input_id], 2)
}

@(test)
test_text_input_deletes_utf8_selection_without_corrupting_buffer :: proc(t: ^testing.T) {
	buffer := make([dynamic]u8, context.temp_allocator)
	append(&buffer, "Aé🙂Z")

	input_id := Box_ID(2)
	ctx := Event_Context {
		text_cursors = make(map[Box_ID]int, context.temp_allocator),
		text_selection = make(map[Box_ID]int, context.temp_allocator),
		focused_buffer = &buffer,
	}
	ctx.text_cursors[input_id] = 3
	ctx.text_selection[input_id] = 1

	event := UI_Event{current_target = input_id, keycode = .BACKSPACE}
	_key_down_cb(&event, &ctx)

	testing.expect_value(t, string(buffer[:]), "AZ")
	testing.expect_value(t, ctx.text_cursors[input_id], 1)
	testing.expect_value(t, ctx.text_selection[input_id], 1)
}
