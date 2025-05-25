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

import path "core:path/filepath"
import "core:fmt"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:log"
import "core:reflect"
import "core:time"

import logger "bald:utils/logger"
import utils "bald:utils"

EXE_NAME :: "game"

Target :: enum {
	windows,
	mac,
	linux,
}

main :: proc() {
	context.logger = logger.logger()
	context.assertion_failure_proc = logger.assertion_failure_proc

	//fmt.println(os2.args)

	start_time := time.now()

	// note, ODIN_OS is built in, but we're being explicit
	assert(ODIN_OS == .Windows || ODIN_OS == .Darwin || ODIN_OS == .Linux, "unsupported OS target")

	target: Target
	#partial switch ODIN_OS {
		case .Windows: target = .windows
		case .Darwin: target = .mac
		case .Linux: target = .linux
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
		fprintln(f, "	linux,")
		fprintln(f, "}")
		fprintln(f, tprintf("PLATFORM :: Platform.%v", target))
	}

	// generate the shader
	// docs: https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
	utils.fire("sokol-shdc", "-i", "sauce/bald/draw/shader_core.glsl", "-o", "sauce/bald/draw/generated_shader.odin", "-l", "hlsl5:glsl430", "-f", "sokol_odin")

	wd := os.get_current_directory()

	//utils.make_directory_if_not_exist("build")

	out_dir : string
	switch target {
		case .windows: out_dir = "build/windows_debug"
		case .mac: out_dir = "build/mac_debug"
		case .linux: out_dir = "build/linux_debug"
	}

	full_out_dir_path := fmt.tprintf("%v/%v", wd, out_dir)
	log.info(full_out_dir_path)
	utils.make_directory_if_not_exist(full_out_dir_path)

	// build command
	{
		c: [dynamic]string = {
			"odin",
			"build",
			"sauce",
			"-debug",
			"-collection:bald=sauce/bald",
			"-collection:user=sauce",
			fmt.tprintf("-out:%v/%v", out_dir, EXE_NAME),
		}
		// not needed, it's easier to just generate code into generated.odin
		//append(&c, fmt.tprintf("-define:TARGET_STRING=%v", target))
		utils.fire(..c[:])
	}

	// copy stuff into folder
	{
		// NOTE, if it already exists, it won't copy (to save build time)
		files_to_copy: [dynamic]string

		switch target {
			case .windows:
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/windows/x64/fmodstudio.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/windows/x64/fmodstudioL.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/windows/x64/fmod.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/windows/x64/fmodL.dll")

			case .mac:
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/darwin/libfmodstudio.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/darwin/libfmodstudioL.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/darwin/libfmod.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/darwin/libfmodL.dylib")

			case .linux:
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudio.so")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudio.so.13")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudio.so.13.28")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudioL.so")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudioL.so.13")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/linux/libfmodstudioL.so.13.28")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmod.so")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmod.so.13")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmod.so.13.28")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmodL.so")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmodL.so.13")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/linux/libfmodL.so.13.28")
		}

		for src in files_to_copy {
			dir, file_name := path.split(src)
			assert(os.exists(dir), fmt.tprint("directory doesn't exist:", dir))
			dest := fmt.tprintf("%v/%v", out_dir, file_name)
			if !os.exists(dest) {
				os2.copy_file(dest, src)
			}
		}
	}

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
