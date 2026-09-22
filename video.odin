package UI

import avcodec "./ffmpeg-bindings/avcodec"
import avformat "./ffmpeg-bindings/avformat"
import avutil "./ffmpeg-bindings/avutil"
import swresample "./ffmpeg-bindings/swresample"
import types "./ffmpeg-bindings/types"
import "core:c"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import sdl "vendor:sdl2"

Video_Frame :: struct {
	y_plane, u_plane, v_plane: []u8,
	y_pitch, u_pitch, v_pitch: i32,
	pts:                       f64,
}

Video_Player :: struct {
	texture:                  ^sdl.Texture,
	width:                    i32,
	height:                   i32,
	is_playing:               bool,
	playback_time:            f64,
	duration:                 f64,
	audio_clock_offset:       f64,
	seek_req:                 bool,
	seek_target:              f64,

	// --- Video State ---
	file_path:                string,
	fmt_ctx:                  ^types.Format_Context,
	codec_ctx:                ^types.Codec_Context,
	video_stream_idx:         i32,

	// --- Audio State ---
	audio_stream_idx:         i32,
	audio_codec_ctx:          ^types.Codec_Context,
	swr_ctx:                  ^types.Software_Resample_Context,
	audio_dev:                sdl.AudioDeviceID,
	audio_channels:           i32,
	audio_sample_rate:        i32,
	total_audio_bytes_queued: u64,

	// --- Threading ---
	decoder_thread:           ^thread.Thread,
	frame_queue:              [dynamic]Video_Frame,
	queue_mutex:              sync.Mutex,
	quit_flag:                bool,
}

video_player_init :: proc(renderer: ^sdl.Renderer, path: string) -> ^Video_Player {
	// Ensure the SDL Audio subsystem is awake
	sdl.InitSubSystem({.AUDIO})

	player := new(Video_Player)
	player.file_path = path
	player.is_playing = true
	player.frame_queue = make([dynamic]Video_Frame)

	c_path := strings.clone_to_cstring(path)
	defer delete(c_path)

	if avformat.open_input(&player.fmt_ctx, c_path, nil, nil) < 0 {
		fmt.printfln("FFMPEG ERROR: Could not open file: %s", path)
		return nil
	}

	if avformat.find_stream_info(player.fmt_ctx, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not find stream info")
		return nil
	}

	player.video_stream_idx = -1
	player.audio_stream_idx = -1
	video_codec: ^types.Codec = nil
	audio_codec: ^types.Codec = nil

	streams := slice.from_ptr(player.fmt_ctx.streams, int(player.fmt_ctx.nb_streams))

	// Find the first Video and Audio streams
	for stream, i in streams {
		if stream.codecpar.codec_type == .Video && player.video_stream_idx == -1 {
			player.video_stream_idx = i32(i)
			video_codec = avcodec.find_decoder(stream.codecpar.codec_id)
		} else if stream.codecpar.codec_type == .Audio && player.audio_stream_idx == -1 {
			player.audio_stream_idx = i32(i)
			audio_codec = avcodec.find_decoder(stream.codecpar.codec_id)
		}
	}

	if player.video_stream_idx == -1 || video_codec == nil {
		fmt.println("FFMPEG ERROR: No video stream or unsupported codec found")
		return nil
	}

	v_stream := streams[player.video_stream_idx]

	if v_stream.duration > 0 {
		// Stream duration uses its own time_base (e.g., 1/90000 or 1/24)
		tb := f64(v_stream.time_base.numerator) / f64(v_stream.time_base.denominator)
		player.duration = f64(v_stream.duration) * tb
	} else if player.fmt_ctx.duration > 0 {
		// Fallback to global format context (in AV_TIME_BASE microsecond units)
		player.duration = f64(player.fmt_ctx.duration) / 1000000.0
	} else {
		player.duration = 0.0
	}

	// ---------------------------------------------------------
	// Video Setup
	// ---------------------------------------------------------
	player.codec_ctx = avcodec.alloc_context3(video_codec)
	avcodec.parameters_to_context(player.codec_ctx, streams[player.video_stream_idx].codecpar)

	if avcodec.open2(player.codec_ctx, video_codec, nil) < 0 {
		fmt.println("FFMPEG ERROR: Could not open video codec")
		return nil
	}

	player.width = player.codec_ctx.width
	player.height = player.codec_ctx.height

	player.texture = sdl.CreateTexture(
		renderer,
		sdl.PixelFormatEnum.IYUV,
		sdl.TextureAccess.STREAMING,
		player.width,
		player.height,
	)

	// ---------------------------------------------------------
	// Audio Setup
	// ---------------------------------------------------------
	if player.audio_stream_idx != -1 && audio_codec != nil {
		player.audio_codec_ctx = avcodec.alloc_context3(audio_codec)
		avcodec.parameters_to_context(
			player.audio_codec_ctx,
			streams[player.audio_stream_idx].codecpar,
		)

		if avcodec.open2(player.audio_codec_ctx, audio_codec, nil) >= 0 {

			// Seed defaults from codecpar (which may be correct if the ABI hasn't shifted these specific fields)
			sample_rate_64: i64 = i64(streams[player.audio_stream_idx].codecpar.sample_rate)
			channels_64: i64 = 2 // Safe default, old channels field is notoriously shifted in Odin bindings
			sample_fmt: types.Sample_Format = .FLTP

			// Overwrite with reflection (Using the correct FFmpeg AVOption shortcodes!)
			avutil.opt_get_int(player.audio_codec_ctx, "ar", 0, &sample_rate_64)
			avutil.opt_get_int(player.audio_codec_ctx, "ac", 0, &channels_64)
			avutil.opt_get_sample_fmt(player.audio_codec_ctx, "sample_fmt", 0, &sample_fmt)

			sample_rate := i32(sample_rate_64)
			channels := i32(channels_64)

			// Failsafe bounds
			if sample_rate <= 0 do sample_rate = 44100
			if channels <= 0 do channels = 2

			// Store the true channel count for the worker thread
			player.audio_channels = channels
			player.audio_channels = channels
			player.audio_sample_rate = sample_rate

			player.swr_ctx = swresample.alloc()

			if player.swr_ctx != nil {
				TARGET_FMT := cast(types.Sample_Format)c.int(3) // AV_SAMPLE_FMT_FLT

				layout_str: cstring = "stereo"
				if channels == 1 do layout_str = "mono"
				else if channels == 6 do layout_str = "5.1"

				avutil.opt_set(player.swr_ctx, "in_chlayout", layout_str, 0)
				avutil.opt_set(player.swr_ctx, "out_chlayout", layout_str, 0)
				avutil.opt_set_int(player.swr_ctx, "in_sample_rate", sample_rate_64, 0)
				avutil.opt_set_int(player.swr_ctx, "out_sample_rate", sample_rate_64, 0)
				avutil.opt_set_sample_fmt(player.swr_ctx, "in_sample_fmt", sample_fmt, 0)
				avutil.opt_set_sample_fmt(player.swr_ctx, "out_sample_fmt", TARGET_FMT, 0)

				if swresample.init(player.swr_ctx) < 0 {
					fmt.println("FFMPEG ERROR: swr_init failed - disabling audio")
					swresample.free(&player.swr_ctx)
					player.swr_ctx = nil
				}
			}

			// Only open the audio device if the resampler is fully initialized
			if player.swr_ctx != nil {
				want := sdl.AudioSpec {
					freq     = sample_rate,
					format   = sdl.AUDIO_F32,
					channels = u8(channels),
					samples  = 4096,
				}
				have: sdl.AudioSpec

				player.audio_dev = sdl.OpenAudioDevice(nil, false, &want, &have, {.FREQUENCY})
				if player.audio_dev > 0 {
					sdl.PauseAudioDevice(player.audio_dev, false) // Unpause immediately
				}
			}
		}
	}

	player.decoder_thread = thread.create_and_start_with_data(player, ffmpeg_worker_thread)
	return player
}

video_player_update :: proc(player: ^Video_Player, dt: f64) {
	if !player.is_playing do return


	// --- MASTER AUDIO CLOCK ---
	if player.audio_dev > 0 && player.audio_sample_rate > 0 {
		sync.lock(&player.queue_mutex)
		total_queued := player.total_audio_bytes_queued
		sync.unlock(&player.queue_mutex)

		// Current true time = (Lifetime Bytes - Bytes Still Waiting to Play) / Bytes Per Second
		unplayed_bytes := u64(sdl.GetQueuedAudioSize(player.audio_dev))
		played_bytes := total_queued - unplayed_bytes

		bytes_per_sec := u64(player.audio_channels * player.audio_sample_rate * 4)
		player.playback_time = player.audio_clock_offset + (f64(played_bytes) / f64(bytes_per_sec))
	} else {
		// Fallback for silent video streams
		player.playback_time += dt
	}

	valid_frame: Maybe(Video_Frame) = nil

	sync.lock(&player.queue_mutex)
	for len(player.frame_queue) > 0 {
		// If the frame's presentation timestamp is in the past, it's ready to play
		if player.playback_time >= player.frame_queue[0].pts {
			// If we ALREADY extracted a frame this tick, we are dropping it to catch up
			if prev_frame, ok := valid_frame.?; ok {
				delete(prev_frame.y_plane)
				delete(prev_frame.u_plane)
				delete(prev_frame.v_plane)
			}

			valid_frame = player.frame_queue[0]
			ordered_remove(&player.frame_queue, 0)
		} else {
			// The frame at the front of the queue is in the future. Stop seeking.
			break
		}
	}
	sync.unlock(&player.queue_mutex)

	if frame, ok := valid_frame.?; ok {
		sdl.UpdateYUVTexture(
			player.texture,
			nil,
			raw_data(frame.y_plane),
			frame.y_pitch,
			raw_data(frame.u_plane),
			frame.u_pitch,
			raw_data(frame.v_plane),
			frame.v_pitch,
		)

		// Clean up the memory for the frame we just rendered
		delete(frame.y_plane)
		delete(frame.u_plane)
		delete(frame.v_plane)
	}
}

video_player_destroy :: proc(player: ^Video_Player) {
	player.quit_flag = true
	thread.join(player.decoder_thread)
	thread.destroy(player.decoder_thread)

	sdl.DestroyTexture(player.texture)

	if player.audio_dev > 0 {
		sdl.CloseAudioDevice(player.audio_dev)
	}

	if player.swr_ctx != nil {
		swresample.free(&player.swr_ctx)
	}

	if player.audio_codec_ctx != nil {
		avcodec.free_context(&player.audio_codec_ctx)
	}

	// Clean up any remaining unplayed frames
	for f in player.frame_queue {
		delete(f.y_plane)
		delete(f.u_plane)
		delete(f.v_plane)
	}
	delete(player.frame_queue)
	free(player)
}

video_player_seek :: proc(player: ^Video_Player, time_sec: f64) {
	sync.lock(&player.queue_mutex)
	player.seek_target = time_sec
	player.seek_req = true
	sync.unlock(&player.queue_mutex)
}

@(private = "file")
ffmpeg_worker_thread :: proc(data: rawptr) {
	player := cast(^Video_Player)data

	pkt: ^types.Packet = avcodec.packet_alloc()
	frame: ^types.Frame = avutil.frame_alloc()
	defer {
		avcodec.packet_free(&pkt)
		avutil.frame_free(&frame)
	}

	MAX_BUFFERED_FRAMES :: 30
	stream := player.fmt_ctx.streams[player.video_stream_idx]
	time_base := f64(stream.time_base.numerator) / f64(stream.time_base.denominator)

	just_sought := false

	for player.is_playing {
		sync.lock(&player.queue_mutex)
		if player.seek_req {
			target_ts := i64(player.seek_target * 1000000.0) // AV_TIME_BASE
			avformat.seek_frame(player.fmt_ctx, -1, target_ts, {.Backward}) // 1 = AVSEEK_FLAG_BACKWARD

			avcodec.flush_buffers(player.codec_ctx)
			if player.audio_codec_ctx != nil do avcodec.flush_buffers(player.audio_codec_ctx)

			clear(&player.frame_queue)

			if player.audio_dev > 0 {
				sdl.ClearQueuedAudio(player.audio_dev)
			}
			player.total_audio_bytes_queued = 0

			player.seek_req = false
			just_sought = true
		}
		sync.unlock(&player.queue_mutex)

		for !player.quit_flag {
			sync.lock(&player.queue_mutex)
			if player.seek_req {
				sync.unlock(&player.queue_mutex)
				break
			}
			queue_len := len(player.frame_queue)
			sync.unlock(&player.queue_mutex)

			if queue_len >= MAX_BUFFERED_FRAMES {
				time.sleep(time.Millisecond * 5)
				continue
			}

			if avformat.read_frame(player.fmt_ctx, pkt) < 0 do break
			defer avcodec.packet_unref(pkt)

			// --- SYNC MASTER CLOCK TO THE EXACT KEYFRAME WE LANDED ON ---
			if just_sought {
				if pkt.stream_index == player.audio_stream_idx && player.audio_dev > 0 {
					// Check for valid PTS (AV_NOPTS_VALUE is minimum i64)
					if pkt.pts != -9223372036854775808 {
						a_stream := player.fmt_ctx.streams[player.audio_stream_idx]
						a_tb :=
							f64(a_stream.time_base.numerator) / f64(a_stream.time_base.denominator)

						sync.lock(&player.queue_mutex)
						player.audio_clock_offset = f64(pkt.pts) * a_tb
						sync.unlock(&player.queue_mutex)
						just_sought = false
					}
				} else if pkt.stream_index == player.video_stream_idx &&
				   player.audio_stream_idx == -1 {
					// Fallback clock sync for silent video tracks
					if pkt.pts != -9223372036854775808 {
						sync.lock(&player.queue_mutex)
						player.playback_time = f64(pkt.pts) * time_base
						sync.unlock(&player.queue_mutex)
						just_sought = false
					}
				}
			}

			if pkt.stream_index == player.video_stream_idx {
				if avcodec.send_packet(player.codec_ctx, pkt) == 0 {
					for avcodec.receive_frame(player.codec_ctx, frame) == 0 {
						pts_seconds := f64(frame.best_effort_timestamp) * time_base

						y_pitch := player.width
						u_pitch := player.width / 2
						v_pitch := player.width / 2

						new_frame := Video_Frame {
							y_plane = make([]u8, y_pitch * player.height),
							u_plane = make([]u8, u_pitch * (player.height / 2)),
							v_plane = make([]u8, v_pitch * (player.height / 2)),
							y_pitch = y_pitch,
							u_pitch = u_pitch,
							v_pitch = v_pitch,
							pts     = pts_seconds,
						}

						src_y := cast([^]u8)frame.data[0]
						src_u := cast([^]u8)frame.data[1]
						src_v := cast([^]u8)frame.data[2]

						for y: i32 = 0; y < player.height; y += 1 {
							src_idx := y * frame.linesize[0]
							dst_idx := y * new_frame.y_pitch
							copy(
								new_frame.y_plane[dst_idx:dst_idx + player.width],
								src_y[src_idx:src_idx + player.width],
							)
						}

						half_w := player.width / 2
						half_h := player.height / 2

						for y: i32 = 0; y < half_h; y += 1 {
							src_idx_u := y * frame.linesize[1]
							src_idx_v := y * frame.linesize[2]
							dst_idx_u := y * new_frame.u_pitch
							dst_idx_v := y * new_frame.v_pitch
							copy(
								new_frame.u_plane[dst_idx_u:dst_idx_u + half_w],
								src_u[src_idx_u:src_idx_u + half_w],
							)
							copy(
								new_frame.v_plane[dst_idx_v:dst_idx_v + half_w],
								src_v[src_idx_v:src_idx_v + half_w],
							)
						}

						sync.lock(&player.queue_mutex)
						append(&player.frame_queue, new_frame)
						sync.unlock(&player.queue_mutex)

						avutil.frame_unref(frame)
					}
				}
			} else if pkt.stream_index == player.audio_stream_idx && player.audio_dev > 0 {

				// --- Audio Decoding & Resampling ---
				if avcodec.send_packet(player.audio_codec_ctx, pkt) == 0 {
					for avcodec.receive_frame(player.audio_codec_ctx, frame) == 0 {

						out_samples := swresample.get_out_samples(player.swr_ctx, frame.nb_samples)

						// Pull the guaranteed channel count from our state
						channels := player.audio_channels

						// Allocate enough memory for interleaved 32-bit floats
						out_buf := make([]f32, out_samples * channels)

						out_arr := [1][^]u8{cast([^]u8)raw_data(out_buf)}
						in_arr: [8][^]u8
						for i in 0 ..< 8 do in_arr[i] = cast([^]u8)frame.data[i]

						// Perform the resampling conversion
						converted := swresample.convert(
							player.swr_ctx,
							cast([^][^]u8)&out_arr[0],
							out_samples,
							cast([^][^]u8)&in_arr[0],
							frame.nb_samples,
						)

						// Push to SDL and track the Master Audio Clock
						if converted > 0 {
							byte_size := u32(converted * channels * 4) // 4 bytes per 32-bit float
							sdl.QueueAudio(player.audio_dev, raw_data(out_buf), byte_size)

							// Accumulate the lifetime byte count for A/V sync
							sync.lock(&player.queue_mutex)
							player.total_audio_bytes_queued += u64(byte_size)
							sync.unlock(&player.queue_mutex)
						}

						// Cleanup
						delete(out_buf)
						avutil.frame_unref(frame)
					}
				}
			}
		}
	}
}
