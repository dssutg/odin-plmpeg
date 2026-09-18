// PL_MPEG - MPEG1 Video decoder, MP2 Audio decoder, MPEG-PS demuxer
// Odin bindings for https://github.com/phoboslab/pl_mpeg
//
// SPDX-License-Identifier: MIT
//
// This file declares the C interface of `pl_mpeg.h` for use from Odin.
// The `plm_` prefix and `_t` suffix of the C names are dropped because the
// package name already provides a unique namespace (e.g. C `plm_decode`,
// `plm_buffer_t`, `plm_frame_t` become `decode`, `Buffer`, `Frame`).
//
// ----------------------------- Building the C side ---------------------------
//
// 1. Compile the implementation into a static library. A ready-to-use
//    translation unit (`pl_mpeg_odin.c`) ships next to this file and simply
//    defines `PL_MPEG_IMPLEMENTATION` before including `pl_mpeg.h`:
//
//			make lib            # produces libplmpeg.a (or use any C compiler)
//
// 2. Link it into your Odin program. The `system:` foreign import below makes
//    the linker look for `libplmpeg.a` (or `libplmpeg.so`) in the standard
//    library paths. If the archive lives elsewhere, point at it directly:
//
//			odin build my_app.odin -extra-linker-flags:"<path>/libplmpeg.a"
//
// -------------------------------- Usage -------------------------------------
//
// Load a .mpg (MPEG Program Stream) file and decode it with the high-level
// interface:
//
//	video_cb :: proc "c" (self: ^plmpeg.Plm, frame: ^plmpeg.Frame, user: rawptr) {
//		plmpeg.frame_to_rgb(frame, rgb_buffer, i32(frame.width * 3))
//	}
//
//	main :: proc() {
//		plm := plmpeg.create_with_filename("video.mpg")
//		defer plmpeg.destroy(plm)
//
//		plmpeg.set_video_decode_callback(plm, video_cb, nil)
//
//		for plmpeg.has_ended(plm) == 0 {
//			plmpeg.decode(plm, 1.0 / 60.0)
//		}
//	}
//
// See the README for how to prepare a compatible video with ffmpeg.
//
// The stdio-dependent entry points (`create_with_filename`,
// `create_with_file`, `buffer_create_with_filename`, `buffer_create_with_file`)
// only exist if the C library was compiled *without* `PLM_NO_STDIO` (which is
// the default).

package plmpeg

import "core:c"

// -----------------------------------------------------------------------------
// Public constants

// PTS value used for packets that have no presentation time stamp.
Packet_Invalid_Ts :: -1

// Number of samples per decoded audio frame.
Audio_Samples_Per_Frame :: 1152

// Default size (in bytes) of buffers created from files / by the high-level API.
Buffer_Default_Size :: 128 * 1024

// Demuxed MPEG-PS packet types (MPEG-PES start codes).
Packet_Private :: 0xBD
Packet_Audio_1 :: 0xC0
Packet_Audio_2 :: 0xC1
Packet_Audio_3 :: 0xC2
Packet_Audio_4 :: 0xC3
Packet_Video_1 :: 0xE0

// -----------------------------------------------------------------------------
// Opaque object types

// High-level interface combining demuxer and decoders.
Plm :: struct {}

// Data source used by all other interfaces.
Buffer :: struct {}

// MPEG-PS demuxer.
Demux :: struct {}

// MPEG1 Video ("mpeg1") decoder.
Video :: struct {}

// MPEG1 Audio Layer II ("mp2") decoder.
Audio :: struct {}

// -----------------------------------------------------------------------------
// Callback proc types

// Called by decode() for each decoded video frame.
Video_Decode_Callback :: #type proc "c" (self: ^Plm, frame: ^Frame, user: rawptr)

// Called by decode() for each decoded audio frame.
Audio_Decode_Callback :: #type proc "c" (self: ^Plm, samples: ^Samples, user: rawptr)

// Called whenever the buffer needs more data.
Buffer_Load_Callback :: #type proc "c" (self: ^Buffer, user: rawptr)

// Called whenever the buffer needs to seek.
Buffer_Seek_Callback :: #type proc "c" (self: ^Buffer, offset: c.size_t, user: rawptr)

// Called whenever the buffer needs to know its position.
Buffer_Tell_Callback :: #type proc "c" (self: ^Buffer, user: rawptr) -> c.size_t

// -----------------------------------------------------------------------------
// Public data types

// Demuxed MPEG-PS packet. Maps directly to the MPEG-PES start codes.
Packet :: struct {
	type:   c.int, // Packet_* constant
	pts:    f64, // presentation time stamp in seconds (Packet_Invalid_Ts if none)
	length: c.size_t,
	data:   ^u8,
}

// Decoded video plane. The byte length of the data is width * height. The luma
// plane (y) is double the size of each chroma plane (cr, cb), i.e. 4 times the
// byte length. Plane sizes are always rounded up to the nearest macroblock
// (16px) and may differ from the displayed frame size.
Plane :: struct {
	width:  c.uint,
	height: c.uint,
	data:   ^u8,
}

// Decoded video frame. `width`/`height` denote the desired display size.
Frame :: struct {
	time:   f64,
	width:  c.uint,
	height: c.uint,
	y:      Plane,
	cr:     Plane,
	cb:     Plane,
}

// Decoded audio samples as normalized (-1, 1) floats, interleaved (L, R, L, R,
// ...). `count` is always Audio_Samples_Per_Frame. If the C library is built
// with `PLM_AUDIO_SEPARATE_CHANNELS`, this struct instead holds two separate
// `left`/`right` arrays (see Samples_Separate).
Samples :: struct {
	time:        f64,
	count:       c.uint,
	interleaved: [Audio_Samples_Per_Frame * 2]f32,
}

// Layout of Samples when the C library is compiled with
// `PLM_AUDIO_SEPARATE_CHANNELS`. *Not* the ABI used by Samples.
Samples_Separate :: struct {
	time:  f64,
	count: c.uint,
	left:  [Audio_Samples_Per_Frame]f32,
	right: [Audio_Samples_Per_Frame]f32,
}

// -----------------------------------------------------------------------------
// plm_* public API
// High-level interface: load, demux and decode MPEG-PS data.

foreign import lib "system:plmpeg"

@(link_prefix = "plm_")
foreign lib {
	// Create a plmpeg instance with a filename. Returns nil if the file could
	// not be opened. [requires no PLM_NO_STDIO]
	create_with_filename :: proc(filename: cstring) -> ^Plm ---

	// Create a plmpeg instance with a file handle. Pass true to
	// close_when_done to make plmpeg call fclose() on the handle during
	// destroy(). [requires no PLM_NO_STDIO]
	create_with_file :: proc(fh: rawptr, close_when_done: c.int) -> ^Plm ---

	// Create a plmpeg instance from memory. Assumes the whole file is in
	// memory. The memory is *not* copied. Pass true to free_when_done to let
	// plmpeg call free() on the pointer during destroy().
	create_with_memory :: proc(bytes: ^u8, length: c.size_t, free_when_done: c.int) -> ^Plm ---

	// Create a plmpeg instance with a Buffer as source. Pass true to
	// destroy_when_done to let plmpeg take ownership of the buffer.
	create_with_buffer :: proc(buffer: ^Buffer, destroy_when_done: c.int) -> ^Plm ---

	// Destroy a plmpeg instance and free all data.
	destroy :: proc(self: ^Plm) ---

	// Whether headers are available on all streams so dimensions, framerate
	// and samplerate can be reported.
	has_headers :: proc(self: ^Plm) -> c.int ---

	// Probe the data for the actual number of video/audio streams. Only for
	// seekable buffers (file, fixed memory or _for_appending).
	probe :: proc(self: ^Plm, probesize: c.size_t) -> c.int ---

	// Get whether video decoding is enabled. Default true.
	get_video_enabled :: proc(self: ^Plm) -> c.int ---

	// Set whether video decoding is enabled.
	set_video_enabled :: proc(self: ^Plm, enabled: c.int) ---

	// Number of video streams (0--1) reported in the system header.
	get_num_video_streams :: proc(self: ^Plm) -> c.int ---

	// Display width of the video stream.
	get_width :: proc(self: ^Plm) -> c.int ---

	// Display height of the video stream.
	get_height :: proc(self: ^Plm) -> c.int ---

	// Pixel aspect ratio of the video stream.
	get_pixel_aspect_ratio :: proc(self: ^Plm) -> f64 ---

	// Framerate of the video stream in frames per second.
	get_framerate :: proc(self: ^Plm) -> f64 ---

	// Get whether audio decoding is enabled. Default true.
	get_audio_enabled :: proc(self: ^Plm) -> c.int ---

	// Set whether audio decoding is enabled.
	set_audio_enabled :: proc(self: ^Plm, enabled: c.int) ---

	// Number of audio streams (0--4) reported in the system header.
	get_num_audio_streams :: proc(self: ^Plm) -> c.int ---

	// Select the desired audio stream (0--3). Default 0.
	set_audio_stream :: proc(self: ^Plm, stream_index: c.int) ---

	// Samplerate of the audio stream in samples per second.
	get_samplerate :: proc(self: ^Plm) -> c.int ---

	// Audio lead time in seconds.
	get_audio_lead_time :: proc(self: ^Plm) -> f64 ---

	// Set the audio lead time in seconds.
	set_audio_lead_time :: proc(self: ^Plm, lead_time: f64) ---

	// Current internal time in seconds.
	get_time :: proc(self: ^Plm) -> f64 ---

	// Video duration of the underlying source in seconds.
	get_duration :: proc(self: ^Plm) -> f64 ---

	// Rewind all buffers back to the beginning.
	rewind :: proc(self: ^Plm) ---

	// Get whether looping is enabled. Default false.
	get_loop :: proc(self: ^Plm) -> c.int ---

	// Set looping. When enabled, has_ended() always returns false.
	set_loop :: proc(self: ^Plm, loop: c.int) ---

	// Whether the file has ended.
	has_ended :: proc(self: ^Plm) -> c.int ---

	// Set the callback for decoded video frames used with decode().
	set_video_decode_callback :: proc(self: ^Plm, fp: Video_Decode_Callback, user: rawptr) ---

	// Set the callback for decoded audio samples used with decode().
	set_audio_decode_callback :: proc(self: ^Plm, fp: Audio_Decode_Callback, user: rawptr) ---

	// Advance the internal timer by seconds and decode video/audio up to this
	// time, invoking the installed callbacks any number of times.
	decode :: proc(self: ^Plm, seconds: f64) ---

	// Decode and return one video frame. Returns nil if no frame could be
	// decoded. Valid until the next call to decode_video() or destroy().
	decode_video :: proc(self: ^Plm) -> ^Frame ---

	// Decode and return one audio frame. Returns nil if no frame could be
	// decoded. Valid until the next call to decode_audio() or destroy().
	decode_audio :: proc(self: ^Plm) -> ^Samples ---

	// Seek to the specified time (clamped to 0 -- duration). Only for seekable
	// buffers. Returns true if seeking succeeded.
	seek :: proc(self: ^Plm, time: f64, seek_exact: c.int) -> c.int ---

	// Like seek(), but without invoking callbacks or syncing audio. Returns
	// the found frame or nil.
	seek_frame :: proc(self: ^Plm, time: f64, seek_exact: c.int) -> ^Frame ---
}

// -----------------------------------------------------------------------------
// plm_buffer public API
// Provides the data source for all other plm_* interfaces.

@(link_prefix = "plm_")
foreign lib {
	// Create a buffer instance from a filename. Returns nil if the file could
	// not be opened. [requires no PLM_NO_STDIO]
	buffer_create_with_filename :: proc(filename: cstring) -> ^Buffer ---

	// Create a buffer instance from a file handle. Pass true to close_when_done
	// to let plmpeg call fclose() on it. [requires no PLM_NO_STDIO]
	buffer_create_with_file :: proc(fh: rawptr, close_when_done: c.int) -> ^Buffer ---

	// Create a buffer instance with custom load/seek/tell callbacks, useful for
	// file handles that don't use the standard FILE API. Setting the length and
	// closing/freeing has to be done manually.
	buffer_create_with_callbacks :: proc(load_callback: Buffer_Load_Callback, seek_callback: Buffer_Seek_Callback, tell_callback: Buffer_Tell_Callback, length: c.size_t, user: rawptr) -> ^Buffer ---

	// Create a buffer instance from memory. The bytes are *not* copied. Pass
	// true to free_when_done to let plmpeg take ownership of the memory.
	buffer_create_with_memory :: proc(bytes: ^u8, length: c.size_t, free_when_done: c.int) -> ^Buffer ---

	// Create an empty buffer with an initial capacity. Grows as needed; data
	// that has already been read is discarded (ring buffer).
	buffer_create_with_capacity :: proc(capacity: c.size_t) -> ^Buffer ---

	// Create an empty buffer for appending. Grows as needed; decoded data is
	// *not* discarded, allowing seeking in already loaded data.
	buffer_create_for_appending :: proc(initial_capacity: c.size_t) -> ^Buffer ---

	// Destroy a buffer instance and free all data.
	buffer_destroy :: proc(self: ^Buffer) ---

	// Copy data into the buffer, realloc()ing if needed. Returns the number of
	// bytes written (always length, except for _with_memory() buffers for which
	// writing is forbidden).
	buffer_write :: proc(self: ^Buffer, bytes: ^u8, length: c.size_t) -> c.size_t ---

	// Mark the current byte length as the end of the buffer and signal that no
	// more data is expected. Call just after the last buffer_write().
	buffer_signal_end :: proc(self: ^Buffer) ---

	// Set a callback that is called whenever the buffer needs more data.
	buffer_set_load_callback :: proc(self: ^Buffer, fp: Buffer_Load_Callback, user: rawptr) ---

	// Rewind the buffer back to the beginning.
	buffer_rewind :: proc(self: ^Buffer) ---

	// Total size. For files: the file size. Otherwise the number of bytes
	// currently in the buffer.
	buffer_get_size :: proc(self: ^Buffer) -> c.size_t ---

	// Number of remaining (yet unread) bytes in the buffer.
	buffer_get_remaining :: proc(self: ^Buffer) -> c.size_t ---

	// Whether the read position is at the end and no more data is expected.
	buffer_has_ended :: proc(self: ^Buffer) -> c.int ---
}

// -----------------------------------------------------------------------------
// plm_demux public API
// Demux an MPEG Program Stream (PS) into separate packets.

@(link_prefix = "plm_")
foreign lib {
	// Create a demuxer with a Buffer as source. Attempts to read the pack
	// and system headers.
	demux_create :: proc(buffer: ^Buffer, destroy_when_done: c.int) -> ^Demux ---

	// Destroy a demuxer and free all data.
	demux_destroy :: proc(self: ^Demux) ---

	// Whether pack and system headers have been found.
	demux_has_headers :: proc(self: ^Demux) -> c.int ---

	// Probe for the actual number of video/audio streams. See probe().
	demux_probe :: proc(self: ^Demux, probesize: c.size_t) -> c.int ---

	// Number of video streams found in the system header.
	demux_get_num_video_streams :: proc(self: ^Demux) -> c.int ---

	// Number of audio streams found in the system header.
	demux_get_num_audio_streams :: proc(self: ^Demux) -> c.int ---

	// Rewind the internal buffer.
	demux_rewind :: proc(self: ^Demux) ---

	// Whether the file has ended. Cleared on seeking or rewind.
	demux_has_ended :: proc(self: ^Demux) -> c.int ---

	// Seek to a packet of the given type with a PTS just before the specified
	// time. If force_intra is true, only packets containing an intra frame are
	// considered (only meaningful for Packet_Video_1).
	demux_seek :: proc(self: ^Demux, time: f64, type: c.int, force_intra: c.int) -> ^Packet ---

	// PTS of the first packet of this type, or Packet_Invalid_Ts if none.
	demux_get_start_time :: proc(self: ^Demux, type: c.int) -> f64 ---

	// Duration (span between first and last PTS) for the given packet type.
	demux_get_duration :: proc(self: ^Demux, type: c.int) -> f64 ---

	// Decode and return the next packet. Valid until the next call or until the
	// demuxer is destroyed.
	demux_decode :: proc(self: ^Demux) -> ^Packet ---
}

// -----------------------------------------------------------------------------
// plm_video public API
// Decode MPEG1 Video ("mpeg1") data into raw YCrCb frames.

@(link_prefix = "plm_")
foreign lib {
	// Create a video decoder with a Buffer as source.
	video_create_with_buffer :: proc(buffer: ^Buffer, destroy_when_done: c.int) -> ^Video ---

	// Destroy a video decoder and free all data.
	video_destroy :: proc(self: ^Video) ---

	// Whether a sequence header was found and dimensions/framerate are accurate.
	video_has_header :: proc(self: ^Video) -> c.int ---

	// Framerate in frames per second.
	video_get_framerate :: proc(self: ^Video) -> f64 ---

	// Pixel aspect ratio.
	video_get_pixel_aspect_ratio :: proc(self: ^Video) -> f64 ---

	// Display width.
	video_get_width :: proc(self: ^Video) -> c.int ---

	// Display height.
	video_get_height :: proc(self: ^Video) -> c.int ---

	// Enable "no delay" mode, assuming the video does *not* contain B-Frames.
	// Useful for reducing lag when streaming. Default false.
	video_set_no_delay :: proc(self: ^Video, no_delay: c.int) ---

	// Current internal time in seconds.
	video_get_time :: proc(self: ^Video) -> f64 ---

	// Set the current internal time in seconds.
	video_set_time :: proc(self: ^Video, time: f64) ---

	// Rewind the internal buffer.
	video_rewind :: proc(self: ^Video) ---

	// Whether the file has ended. Cleared on rewind.
	video_has_ended :: proc(self: ^Video) -> c.int ---

	// Decode and return one frame of video, advancing the internal time by
	// 1/framerate seconds. Valid until the next call or until destroyed.
	video_decode :: proc(self: ^Video) -> ^Frame ---

	// Convert the YCrCb data of a frame into interleaved R G B data. `stride`
	// is the width in bytes of the destination buffer and must be at least
	// frame->width * bytes_per_pixel. `dest` must be stride * frame->height
	// bytes. Alpha components (if any) are left untouched.
	frame_to_rgb :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
	frame_to_bgr :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
	frame_to_rgba :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
	frame_to_bgra :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
	frame_to_argb :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
	frame_to_abgr :: proc(frame: ^Frame, dest: ^u8, stride: c.int) ---
}

// -----------------------------------------------------------------------------
// plm_audio public API
// Decode MPEG-1 Audio Layer II ("mp2") data into raw samples.

@(link_prefix = "plm_")
foreign lib {
	// Create an audio decoder with a Buffer as source.
	audio_create_with_buffer :: proc(buffer: ^Buffer, destroy_when_done: c.int) -> ^Audio ---

	// Destroy an audio decoder and free all data.
	audio_destroy :: proc(self: ^Audio) ---

	// Whether a frame header was found and the samplerate is accurate.
	audio_has_header :: proc(self: ^Audio) -> c.int ---

	// Samplerate in samples per second.
	audio_get_samplerate :: proc(self: ^Audio) -> c.int ---

	// Current internal time in seconds.
	audio_get_time :: proc(self: ^Audio) -> f64 ---

	// Set the current internal time in seconds.
	audio_set_time :: proc(self: ^Audio, time: f64) ---

	// Rewind the internal buffer.
	audio_rewind :: proc(self: ^Audio) ---

	// Whether the file has ended. Cleared on rewind.
	audio_has_ended :: proc(self: ^Audio) -> c.int ---

	// Decode and return one frame of audio, advancing the internal time by
	// (Audio_Samples_Per_Frame/samplerate) seconds. Valid until the next call
	// or until destroyed.
	audio_decode :: proc(self: ^Audio) -> ^Samples ---
}
