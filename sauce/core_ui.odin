package main

// #todo, add in the button helpers

import "bald:utils"
import "bald:utils/shape"

import "bald:draw"
import "bald:input"

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"

screen_pivot_v2 :: proc(pivot: Pivot) -> v2 {
	x,y := screen_pivot(pivot)
	return v2{x,y}
}

screen_pivot :: proc(pivot: Pivot) -> (x, y: f32) {
	#partial switch(pivot) {
		case .top_left:
		x = 0
		y = f32(window_h)
		
		case .top_center:
		x = f32(window_w) / 2
		y = f32(window_h)
		
		case .bottom_left:
		x = 0
		y = 0
		
		case .center_center:
		x = f32(window_w) / 2
		y = f32(window_h) / 2
		
		case .top_right:
		x = f32(window_w)
		y = f32(window_h)
		
		case .bottom_center:
		x = f32(window_w) / 2
		y = 0
		
		case:
		utils.crash_when_debug(pivot, "TODO")
	}
	
	ndc_x := (x / (f32(window_w) * 0.5)) - 1.0;
	ndc_y := (y / (f32(window_h) * 0.5)) - 1.0;
	
	mouse_ndc := v2{ndc_x, ndc_y}
	
	mouse_world :v4= v4{mouse_ndc.x, mouse_ndc.y, 0, 1}
	
	mouse_world = linalg.inverse(get_screen_space_proj()) * mouse_world
	x = mouse_world.x
	y = mouse_world.y
	
	return
}

raw_button :: proc(rect: Rect) -> (hover, pressed: bool) {
	mouse_pos := mouse_pos_in_current_space()
	hover = shape.rect_contains(rect, mouse_pos)
	if hover && input.key_pressed(.LEFT_MOUSE) {
		input.consume_key_pressed(.LEFT_MOUSE)
		pressed = true
	}
	return
}