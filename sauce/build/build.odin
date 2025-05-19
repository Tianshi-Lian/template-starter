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
import "core:log"
import "core:reflect"
import "core:time"

import logger "../utils/logger"
import utils "../utils"

EXE_NAME :: "game"

Target :: enum {
	windows,
	mac,
}

main :: proc() {
	context.logger = logger.logger()
	context.assertion_failure_proc = logger.assertion_failure_proc

	//fmt.println(os2.args)

	start_time := time.now()

	// note, ODIN_OS is built in, but we're being explicit
	assert(ODIN_OS == .Windows || ODIN_OS == .Darwin, "unsupported OS target")

	target: Target
	#partial switch ODIN_OS {
		case .Windows: target = .windows
		case .Darwin: target = .mac
		case: {
			log.error("Unsupported os:", ODIN_OS)
			return
		}
	}
	fmt.println("Building for", target)

	// gen the generated.odin
	{
		file := "sauce/generated.odin"

		f, err := os.open(file, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
		if err != nil {
			fmt.eprintln("Error:", err)
		}
		defer os.close(f)
		
		using fmt
		fprintln(f, "//")
		fprintln(f, "// MACHINE GENERATED via build.odin")
		fprintln(f, "// do not edit by hand!")
		fprintln(f, "//")
		fprintln(f, "")
		fprintln(f, "package main")
		fprintln(f, "")
		fprintln(f, "Platform :: enum {")
		fprintln(f, "	windows,")
		fprintln(f, "	mac,")
		fprintln(f, "}")
		fprintln(f, tprintf("PLATFORM :: Platform.%v", target))
	}
	
	// generate the shader
	// docs: https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
	utils.fire("sokol-shdc", "-i", "sauce/shader.glsl", "-o", "sauce/generated_shader.odin", "-l", "hlsl5:metal_macos", "-f", "sokol_odin")
	
	out_dir := "build/windows_debug"

	utils.make_directory_if_not_exist(out_dir)

	c: [dynamic]string = {
		"odin",
		"build",
		"sauce",
		"-debug",
		fmt.tprintf("-out:%v/%v.exe", out_dir, EXE_NAME),
	}
	// not needed, it's easier to just generate code into generated.odin
	//append(&c, fmt.tprintf("-define:TARGET_STRING=%v", target))

	utils.fire(..c[:])

	fmt.println("DONE in", time.diff(start_time, time.now()))
}


// value extraction example:
/*
target: Target
found: bool
for arg in os2.args {
	if strings.starts_with(arg, "target:") {
		target_string := strings.trim_left(arg, "target:")
		value, ok := reflect.enum_from_name(Target, target_string)
		if ok {
			target = value
			found = true
			break
		} else {
			log.error("Unsupported target:", target_string)
		}
	}
}
*/