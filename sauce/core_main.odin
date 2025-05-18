package main

//
// main entrypoint
//

import "sound"

import "utils"
Pivot :: utils.Pivot
scale_from_pivot :: utils.scale_from_pivot

import shape "utils/shape"
Rect :: shape.Rect
rect_make :: shape.rect_make
rect_size :: shape.rect_size

import "utils/logger"

import "core:sync"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import "core:log"
import "core:time"
import "base:runtime"
import "base:builtin"

import sapp "external/sokol/app"
import sg "external/sokol/gfx"
import sglue "external/sokol/glue"
import slog "external/sokol/log"

import win32 "core:sys/windows"

GAME_RES_WIDTH :: 480
GAME_RES_HEIGHT :: 270

GENERATE_DEBUG_SYMBOLS :: ODIN_DEBUG
RELEASE :: #config(RELEASE, !ODIN_DEBUG) // by default, make it not release on -debug
NOT_RELEASE :: !RELEASE
DEMO :: #config(DEMO, false)
DEV :: #config(DEV, NOT_RELEASE)
PLATFORM :: #config(PLATFORM, "undefined")

// inital params, these are resized in the event callback
window_w :i32= 1280
window_h :i32= 720

clear_col: Vector4

TICKS_PER_SECOND :: 60
SIM_RATE :: 1.0 / TICKS_PER_SECOND

// shorthand definitions
Vector2 :: [2]f32
Vector3 :: [3]f32
Vector4 :: [4]f32
v2 :: Vector2
v3 :: Vector3
v4 :: Vector4
Vec2 :: v2
Vec3 :: v4
Vec4 :: v4
Matrix4 :: linalg.Matrix4f32;
Vector2i :: [2]int

//
// custom global context
//

// this is basically just Odin's context, but our own so it's easy to
// access global data deep in the callstack.
// (it'll also help later on with more complicated games)

Core_Context :: struct {
	gs: ^Game_State,
	input: ^Input,
	delta_t: f32,
}
ctx: Core_Context

// useful for doing a push_ctx and setting values for a scope
// and having it auto-pop to the original once the scope ends
set_ctx :: proc(_ctx: Core_Context) {
	ctx = _ctx
}
@(deferred_out=set_ctx)
push_ctx :: proc() -> Core_Context {
	return ctx
}

//
// MAIN
//

our_context: runtime.Context
main :: proc() {
	context = runtime.default_context()
	context.logger = logger.logger()
	context.assertion_failure_proc = logger.assertion_failure_proc
	our_context = context

	sapp.run({
		init_cb = core_app_init,
		frame_cb = core_app_frame,
		cleanup_cb = core_app_shutdown,
		event_cb = core_app_event,
		width = window_w,
		height = window_h,
		window_title = WINDOW_TITLE,
		icon = { sokol_default = true },
		logger = { func = slog.func },
	})
}

// don't directly access this global, use the ctx.gs instead.
// (this will help later when you upgrade to a fixed timestep, don't worry about it now tho)
_actual_game_state: ^Game_State

core_app_init :: proc "c" () { // these sokol callbacks are c procs
	context = our_context // so we need to add the odin context in

	// we call the utility here so it can mark the start time of the program
	s := utils.seconds_since_init()
	assert(s == 0)

	win32.FreeConsole()
	sound.init()

	_actual_game_state = new(Game_State)

	render_init()
}

app_ticks: u64
frame_time: f64
last_frame_time: f64

core_app_frame :: proc "c" () {
	context = our_context

	// calculate time since last frame
	{
		current_time := utils.seconds_since_init()
		frame_time = current_time-last_frame_time
		last_frame_time = current_time 

		// clamp frame time so it doesn't go to an insane number
		MIN_FRAME_TIME :: 1.0 / 20.0
		if frame_time > MIN_FRAME_TIME {
			frame_time = MIN_FRAME_TIME
		}
	}

	// this is our delta_t for the frame
	ctx.delta_t = f32(frame_time)
	ctx.gs = _actual_game_state
	ctx.input = &_input

	if key_pressed(.ENTER) && key_down(.LEFT_ALT) {
		sapp.toggle_fullscreen()
	}

	core_render_frame_start()
	app_frame()
	core_render_frame_end()

	reset_input_state(ctx.input)
	free_all(context.temp_allocator)

	app_ticks += 1
}

core_app_shutdown :: proc "c" () {
	context = our_context

	app_shutdown()
	sg.shutdown()
}

app_now :: utils.seconds_since_init

now :: proc() -> f64 {
	return ctx.gs.game_time_elapsed
}
end_time_up :: proc(end_time: f64) -> bool {
	return end_time == -1 ? false : now() >= end_time 
}
time_since :: proc(time: f64) -> f32 {
	if time == 0 {
		return 99999999.0
	}
	return f32(now()-time)
}