#+feature dynamic-literals
package main

/*

Basic action abstraction system. Will be useful for key rebinding later on.

*/

import "bald:input"

import "core:log"
import "core:math/linalg"

action_map: map[Input_Action]input.Key_Code = {
	.left = .A,
	.right = .D,
	.up = .W,
	.down = .S,
	.click = .LEFT_MOUSE,
	.use = .RIGHT_MOUSE,
	.interact = .E,
}

Input_Action :: enum u8 {
	left,
	right,
	up,
	down,
	click,
	use,
	interact,
}

is_action_pressed :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return input.key_pressed(key)
}
is_action_released :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return input.key_released(key)
}
is_action_down :: proc(action: Input_Action) -> bool {
	key := key_from_action(action)
	return input.key_down(key)
}

consume_action_pressed :: proc(action: Input_Action) {
	key := key_from_action(action)
	input.consume_key_pressed(key)
}
consume_action_released :: proc(action: Input_Action) {
	key := key_from_action(action)
	input.consume_key_released(key)
}

key_from_action :: proc(action: Input_Action) -> input.Key_Code {
	key, found := action_map[action]
	if !found {
		log.debugf("action %v not bound to any key", action)
	}
	return key
}

get_input_vector :: proc() -> Vec2 {
	input: Vec2
	if is_action_down(.left) do input.x -= 1.0
	if is_action_down(.right) do input.x += 1.0
	if is_action_down(.down) do input.y -= 1.0
	if is_action_down(.up) do input.y += 1.0
	if input == {} {
		return {}
	} else {
		return linalg.normalize(input)
	}
}