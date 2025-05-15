/*

This is a program we run to build the game.

Instead of writing this in .bat (or .sh or whatever) you can imagine how much
easier it is to write a build script natively in Odin, especially as you scale
things up and it becomes more complicated.

Writing a script like this now becomes fun, because you're just using & getting better
at the native language you use every day.

The only downside right now is the build.exe gets left behind, we have no way of auto-deleting
it on windows after execution yet.

*/

#+feature dynamic-literals
package build

import "core:fmt"
import "core:os/os2"
import "core:os"
import "core:strings"

import utils "../utils"

EXE_NAME :: "game"

main :: proc() {
	fmt.println(os2.args)
	
	// generate the shader
	// docs: https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
	utils.fire("sokol-shdc", "-i", "sauce/shader.glsl", "-o", "sauce/generated_shader.odin", "-l", "hlsl5", "-f", "sokol_odin")
	
	out_dir := "build/windows_debug"

	utils.make_directory_if_not_exist(out_dir)

	c: [dynamic]string = {
		"odin",
		"build",
		"sauce",
		"-debug",
		fmt.tprintf("-out:%v/%v.exe", out_dir, EXE_NAME),
	}
	utils.fire(..c[:])
}