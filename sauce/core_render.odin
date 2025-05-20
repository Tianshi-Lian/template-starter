package main

//
// Assumes ZLayer & Quad_Flags are defined elsewhere in user code
//

import "utils"
import shape "utils/shape"

import "core:prof/spall"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:log"
import "core:os"
import "core:fmt"

import sapp "external/sokol/app"
import sg "external/sokol/gfx"
import sglue "external/sokol/glue"
import slog "external/sokol/log"
import stbi "vendor:stb/image"
import tt "vendor:stb/truetype"
import stbrp "vendor:stb/rect_pack"

Render_State :: struct {
	pass_action: sg.Pass_Action,
	pip: sg.Pipeline,
	bind: sg.Bindings,
}
render_state: Render_State

MAX_QUADS :: 8192
MAX_VERTS :: MAX_QUADS * 4

actual_quad_data: [MAX_QUADS * size_of(Quad)]u8

DEFAULT_UV :: v4{0, 0, 1, 1}
COLOR_WHITE :: Vector4 {1,1,1,1}
COLOR_BLACK :: Vector4 {0,0,0,1}
COLOR_RED :: Vector4 {1,0,0,1}
COLOR_GREEN :: Vector4 {0,1,0,1}
COLOR_BLUE :: Vector4 {0,0,1,1}
COLOR_GRAY :: v4{0.5,0.5,0.5,1.0}


Quad :: [4]Vertex;
Vertex :: struct {
	pos: Vector2,
	col: Vector4,
	uv: Vector2,
	local_uv: Vector2,
	size: Vector2,
	tex_index: u8,
	z_layer: u8,
	quad_flags: Quad_Flags,
	_: [1]u8,
	col_override: Vector4,
	params: Vector4,
}

render_init :: proc() {
	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
		d3d11_shader_debugging = ODIN_DEBUG,
	})

	load_sprites_into_atlas()
	load_font()
	const_shader_data_setup(&const_shader_data)

	// make the vertex buffer
	render_state.bind.vertex_buffers[0] = sg.make_buffer({
		usage = .DYNAMIC,
		size = size_of(actual_quad_data),
	})
	
	// make & fill the index buffer
	index_buffer_count :: MAX_QUADS*6
	indices,_ := mem.make([]u16, index_buffer_count, allocator=context.allocator)
	i := 0;
	for i < index_buffer_count {
		// vertex offset pattern to draw a quad
		// { 0, 1, 2,  0, 2, 3 }
		indices[i + 0] = auto_cast ((i/6)*4 + 0)
		indices[i + 1] = auto_cast ((i/6)*4 + 1)
		indices[i + 2] = auto_cast ((i/6)*4 + 2)
		indices[i + 3] = auto_cast ((i/6)*4 + 0)
		indices[i + 4] = auto_cast ((i/6)*4 + 2)
		indices[i + 5] = auto_cast ((i/6)*4 + 3)
		i += 6;
	}
	render_state.bind.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(indices), size = size_of(u16) * index_buffer_count },
	})
	
	// image stuff
	render_state.bind.samplers[SMP_default_sampler] = sg.make_sampler({})
	
	// setup pipeline
	// :vertex layout
	pipeline_desc : sg.Pipeline_Desc = {
		shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				ATTR_quad_position = { format = .FLOAT2 },
				ATTR_quad_color0 = { format = .FLOAT4 },
				ATTR_quad_uv0 = { format = .FLOAT2 },
				ATTR_quad_local_uv0 = { format = .FLOAT2 },
				ATTR_quad_size0 = { format = .FLOAT2 },
				ATTR_quad_bytes0 = { format = .UBYTE4N },
				ATTR_quad_color_override0 = { format = .FLOAT4 },
				ATTR_quad_params0 = { format = .FLOAT4 },
			},
		}
	}
	blend_state : sg.Blend_State = {
		enabled = true,
		src_factor_rgb = .SRC_ALPHA,
		dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
		op_rgb = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha = .ADD,
	}
	pipeline_desc.colors[0] = { blend = blend_state }
	render_state.pip = sg.make_pipeline(pipeline_desc)

	clear_col = utils.hex_to_rgba(0x090a14ff)
	
	// default pass action
	render_state.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = transmute(sg.Color)(clear_col)},
		},
	}
}

core_render_frame_start :: proc() {
	reset_draw_frame()
}

core_render_frame_end :: proc() {
	// merge all the layers into a big ol' array to draw
	total_quad_count := 0
	{
		for quads_in_layer, layer in draw_frame.quads {
			total_quad_count += len(quads_in_layer)
		}
		assert(total_quad_count <= MAX_QUADS)
		offset := 0
		for quads_in_layer, layer in draw_frame.quads {
			size := size_of(Quad) * len(quads_in_layer)
			mem.copy(mem.ptr_offset(raw_data(actual_quad_data[:]), offset), raw_data(quads_in_layer), size)
			offset += size
		}
	}
	
	render_state.bind.images[IMG_tex0] = atlas.sg_image
	render_state.bind.images[IMG_font_tex] = font.sg_image

	{
		sg.update_buffer(
			render_state.bind.vertex_buffers[0],
			{ ptr = raw_data(actual_quad_data[:]), size = len(actual_quad_data) }
		)
		sg.begin_pass({ action = render_state.pass_action, swapchain = sglue.swapchain() })
		sg.apply_pipeline(render_state.pip)
		sg.apply_bindings(render_state.bind)
		sg.apply_uniforms(UB_CBuff, {ptr=&draw_frame.cbuff, size=size_of(Cbuff)})
		sg.apply_uniforms(UB_Const_Shader_Data, {ptr=&const_shader_data, size=size_of(Const_Shader_Data)})
		sg.draw(0, 6*total_quad_count, 1)
		sg.end_pass()
	}

	sg.commit()
}

reset_draw_frame :: proc() {
	draw_frame.reset = {}

	// TODO, do something about this monstrosity
	draw_frame.quads[.background] = make([dynamic]Quad, 0, 512, allocator=context.temp_allocator)
	draw_frame.quads[.shadow] = make([dynamic]Quad, 0, 128, allocator=context.temp_allocator)
	draw_frame.quads[.playspace] = make([dynamic]Quad, 0, 256, allocator=context.temp_allocator)
	draw_frame.quads[.tooltip] = make([dynamic]Quad, 0, 256, allocator=context.temp_allocator)
}

Draw_Frame :: struct {

	using reset: struct {
		quads: [ZLayer][dynamic]Quad, // this is super scuffed, but I did this to optimise the sort, I'm sure there's a better fix.
		coord_space: Coord_Space,
		active_z_layer: ZLayer,
		active_scissor: Rect,
		active_flags: Quad_Flags,
		using cbuff: Cbuff,
	}

}
draw_frame: Draw_Frame
const_shader_data: Const_Shader_Data




Sprite :: struct {
	width, height: i32,
	tex_index: u8,
	sg_img: sg.Image,
	data: [^]byte,
	atlas_uvs: Vector4,
}
sprites: [Sprite_Name]Sprite

load_sprites_into_atlas :: proc() {
	img_dir := "res/images/"
	
	for img_name in Sprite_Name {
		if img_name == .nil do continue
		
		path := fmt.tprint(img_dir, img_name, ".png", sep="")
		png_data, succ := os.read_entire_file(path)
		assert(succ, fmt.tprint(path, "not found"))
		
		stbi.set_flip_vertically_on_load(1)
		width, height, channels: i32
		img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
		assert(img_data != nil, "stbi load failed, invalid image?")
			
		img : Sprite;
		img.width = width
		img.height = height
		img.data = img_data
		
		sprites[img_name] = img
	}
	
	// pack sprites into atlas
	{
		using stbrp

		// the larger we make this, the longer startup time takes
		LENGTH :: 1024
		atlas.w = LENGTH
		atlas.h = LENGTH
		
		cont : stbrp.Context
		nodes : [LENGTH]stbrp.Node
		stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, &nodes[0], auto_cast atlas.w)
		
		rects : [dynamic]stbrp.Rect
		rects.allocator = context.temp_allocator
		for img, id in sprites {
			if img.width == 0 {
				continue
			}
			append(&rects, stbrp.Rect{ id=auto_cast id, w=Coord(img.width+2), h=Coord(img.height+2) })
		}
		
		succ := stbrp.pack_rects(&cont, &rects[0], auto_cast len(rects))
		if succ == 0 {
			assert(false, "failed to pack all the rects, ran out of space?")
		}
		
		// allocate big atlas
		raw_data, err := mem.alloc(atlas.w * atlas.h * 4, allocator=context.temp_allocator)
		assert(err == .None)
		//mem.set(raw_data, 255, atlas.w*atlas.h*4)
		
		// copy rect row-by-row into destination atlas
		for rect in rects {
			img := &sprites[Sprite_Name(rect.id)]
			
			rect_w := int(rect.w) - 2
			rect_h := int(rect.h) - 2
			
			// copy row by row into atlas
			for row in 0..<rect_h {
				src_row := mem.ptr_offset(&img.data[0], int(row) * rect_w * 4)
				dest_row := mem.ptr_offset(cast(^u8)raw_data, ((int(rect.y+1) + row) * int(atlas.w) + int(rect.x+1)) * 4)
				mem.copy(dest_row, src_row, rect_w * 4)
			}
			
			// yeet old data
			stbi.image_free(img.data)
			img.data = nil;

			img.atlas_uvs.x = (cast(f32)rect.x+1) / (cast(f32)atlas.w)
			img.atlas_uvs.y = (cast(f32)rect.y+1) / (cast(f32)atlas.h)
			img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / (cast(f32)atlas.w)
			img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / (cast(f32)atlas.h)
		}
		
		when ODIN_OS == .Windows {
		stbi.write_png("atlas.png", auto_cast atlas.w, auto_cast atlas.h, 4, raw_data, 4 * auto_cast atlas.w)
		}
		
		// setup image for GPU
		desc : sg.Image_Desc
		desc.width = auto_cast atlas.w
		desc.height = auto_cast atlas.h
		desc.pixel_format = .RGBA8
		desc.data.subimage[0][0] = {ptr=raw_data, size=auto_cast (atlas.w*atlas.h*4)}
		atlas.sg_image = sg.make_image(desc)
		if atlas.sg_image.id == sg.INVALID_ID {
			log.error("failed to make image")
		}
	}
}
// We're hardcoded to use just 1 atlas now since I don't think we'll need more
// It would be easy enough to extend though. Just add in more texture slots in the shader
Atlas :: struct {
	w, h: int,
	sg_image: sg.Image,
}
atlas: Atlas


font_bitmap_w :: 256
font_bitmap_h :: 256
char_count :: 96
Font :: struct {
	char_data: [char_count]tt.bakedchar,
	sg_image: sg.Image,
}
font: Font
// note, this is hardcoded to just be a single font for now. I haven't had the need for multiple fonts yet.
// that'll probs change when we do localisation stuff. But that's farrrrr away. No need to complicate things now.
load_font :: proc() {
	using tt
	
	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 15 // for some reason this only bakes properly at 15 ? it's a 16px font dou...
	path := "res/fonts/alagard.ttf" // #user
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil, "failed to read font")
	
	ret := BakeFontBitmap(raw_data(ttf_data), 0, auto_cast font_height, auto_cast bitmap, font_bitmap_w, font_bitmap_h, 32, char_count, &font.char_data[0])
	assert(ret > 0, "not enough space in bitmap")
	
	when ODIN_OS == .Windows {
		//stbi.write_png("font.png", auto_cast font_bitmap_w, auto_cast font_bitmap_h, 1, bitmap, auto_cast font_bitmap_w)
	}
	
	// setup sg image so we can use it in the shader
	desc : sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {ptr=bitmap, size=auto_cast (font_bitmap_w*font_bitmap_h)}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log.error("failed to make image")
	}

	font.sg_image = sg_img
}




Coord_Space :: struct {
	proj: Matrix4,
	camera: Matrix4,
}

set_coord_space :: proc(coord: Coord_Space) {
	draw_frame.coord_space = coord
}

@(deferred_out=set_coord_space)
push_coord_space :: proc(coord: Coord_Space) -> Coord_Space {
	og := draw_frame.coord_space
	draw_frame.coord_space = coord
	return og
}

get_world_space_proj :: proc() -> Matrix4 {
	return linalg.matrix_ortho3d_f32(f32(window_w) * -0.5, f32(window_w) * 0.5, f32(window_h) * -0.5, f32(window_h) * 0.5, -1, 1)
}
get_world_space_camera :: proc() -> Matrix4 {
	cam := Matrix4(1)
	cam *= utils.xform_translate(ctx.gs.cam_pos)
	cam *= utils.xform_scale(get_camera_zoom())
	return cam
}

get_screen_space_proj :: proc() -> Matrix4 {
	scale := f32(GAME_RES_HEIGHT) / f32(window_h) // same res as standard world zoom
	
	w := f32(window_w) * scale
	h := f32(window_h) * scale
	
	// this centers things
	offset := GAME_RES_WIDTH*0.5 - w*0.5

	return linalg.matrix_ortho3d_f32(0+offset, w+offset, 0, h, -1, 1)
}

get_camera_zoom :: proc() -> f32 {
	return f32(GAME_RES_HEIGHT) / f32(window_h)
}



set_z_layer :: proc(zlayer: ZLayer) {
	draw_frame.active_z_layer = zlayer
}

@(deferred_out=set_z_layer)
push_z_layer :: proc(zlayer: ZLayer) -> ZLayer {
	og := draw_frame.active_z_layer
	draw_frame.active_z_layer = zlayer
	return og
}


draw_sprite_in_rect :: proc(sprite: Sprite_Name, pos: Vector2, size: Vector2, xform := Matrix4(1), col := COLOR_WHITE, col_override:= v4{0,0,0,0}, z_layer:=ZLayer.nil, flags:=Quad_Flags(0), pad_pct :f32= 0.1) {
	img_size := get_sprite_size(sprite)
	
	rect := rect_make(pos, size)
	
	// make it smoller (padding)
	{
		rect = shape.rect_shift(rect, -rect.xy)
		rect.xy += size * pad_pct * 0.5
		rect.zw -= size * pad_pct * 0.5
		rect = shape.rect_shift(rect, pos)
	}
	
	// this shrinks the rect if the sprite is too smol
	{
		rect_size := rect_size(rect)
		size_diff_x := rect_size.x - img_size.x
		if size_diff_x < 0 {
			size_diff_x = 0
		}
		
		size_diff_y := rect_size.y - img_size.y
		if size_diff_y < 0 {
			size_diff_y = 0
		}
		size_diff := v2{size_diff_x, size_diff_y}
		
		offset := rect.xy
		rect = shape.rect_shift(rect, -rect.xy)
		rect.xy += size_diff * 0.5
		rect.zw -= size_diff * 0.5
		rect = shape.rect_shift(rect, offset)
	}

	// TODO, there's a buggie wuggie in here somewhere...
	
	// ratio render lock
	if img_size.x > img_size.y { // long boi
		rect_size := rect_size(rect)
		rect.w = rect.y + (rect_size.x * (img_size.y/img_size.x))
		// center along y
		new_height := rect.w - rect.y
		rect = shape.rect_shift(rect, v2{0, (rect_size.y - new_height) * 0.5})
	} else if img_size.y > img_size.x { // tall boi
		rect_size := rect_size(rect)
		rect.z = rect.x + (rect_size.y * (img_size.x/img_size.y))
		// center along x
		new_width := rect.z - rect.x
		rect = shape.rect_shift(rect, v2{0, (rect_size.x - new_width) * 0.5})
	}
	
	draw_rect(rect, col=col, sprite=sprite, col_override=col_override, z_layer=z_layer, flags=flags)
}


draw_text_wrapped :: proc(pos: Vector2, text: string, wrap_width: f32, col:=COLOR_WHITE, scale:= 1.0, pivot:=Pivot.bottom_left, z_layer:= ZLayer.nil, col_override:=v4{0,0,0,0}) -> Vector2 {
	// TODO
	return draw_text_no_drop_shadow(pos, text, col, scale, pivot, z_layer, col_override)
}

draw_text_with_drop_shadow :: proc(pos: Vector2, text: string, drop_shadow_col:=COLOR_BLACK, col:=COLOR_WHITE, scale:= 1.0, pivot:=Pivot.bottom_left, z_layer:= ZLayer.nil, col_override:=v4{0,0,0,0}) -> Vector2 {
	
	offset := v2{1,-1} * f32(scale)
	draw_text_no_drop_shadow(pos+offset, text, col=drop_shadow_col*col,scale=scale,pivot=pivot,z_layer=z_layer,col_override=col_override)
	dim := draw_text_no_drop_shadow(pos, text, col=col,scale=scale,pivot=pivot,z_layer=z_layer,col_override=col_override)
	
	return dim
}
draw_text :: draw_text_with_drop_shadow

draw_text_no_drop_shadow :: proc(pos: Vec2, text: string, col:=COLOR_WHITE, scale:= 1.0, pivot:=Pivot.bottom_left, z_layer:= ZLayer.nil, col_override:=v4{0,0,0,0}) -> (text_bounds: Vector2) {
	using tt

	push_z_layer(z_layer != .nil ? z_layer : draw_frame.active_z_layer)

	// loop thru and find the text size box thingo
	total_size : v2
	for char, i in text {
		
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right
		
		size := v2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }
		
		bottom_left := v2{ q.x0, -q.y1 }
		top_right := v2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)
		
		if i == len(text)-1 {
			total_size.x += size.x
		} else {
			total_size.x += advance_x
		}
		
		total_size.y = max(total_size.y, top_right.y)
	}
	
	pivot_offset := total_size * -scale_from_pivot(pivot)
	
	debug_text := false
	if debug_text {
		draw_rect(rect_make(pos + pivot_offset, total_size), col=COLOR_BLACK)
	}
	
	// draw glyphs one by one
	x: f32
	y: f32
	for char in text {
		
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right
		
		size := v2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }
		
		bottom_left := v2{ q.x0, -q.y1 }
		top_right := v2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)
		
		offset_to_render_at := v2{x,y} + bottom_left
		
		offset_to_render_at += pivot_offset
		
		uv := v4{
			q.s0, q.t1,
			q.s1, q.t0
		}
							
		xform := Matrix4(1)
		xform *= utils.xform_translate(pos)
		xform *= utils.xform_scale(v2{auto_cast scale, auto_cast scale})
		xform *= utils.xform_translate(offset_to_render_at)
		
		if debug_text {
			draw_rect_xform(xform, size, col=v4{1,1,1,0.8})
		}
		
		draw_rect_xform(xform, size, uv=uv, tex_index=1, col_override=col_override, col=col)
		
		x += advance_x
		y += -advance_y
	}

	return total_size * f32(scale)
}

draw_sprite :: proc(
	pos: Vec2,

	// the rect drawn will auto-size based on this
	sprite: Sprite_Name,

	// pivot of the sprite drawn
	pivot:=Pivot.center_center,

	flip_x:=false,
	draw_offset:=Vec2{},

	// useful for more complex transforms. Could technically leave the pos blank on this + set
	// the pivot to bottom_left to fully control the transform of the sprite
	xform:=Matrix4(1),

	// used to offset the UV to the next frame
	anim_index:=0,

	// classic tint that gets multiplied with the sprite
	col:=COLOR_WHITE,

	// overrides (mixes) the colour of the sprite
	// rgba = color to mix with + alpha component for strength
	// useful for doing a white flash
	col_override:Vec4={},

	// leave blank and it'll take the currently active layer
	z_layer:ZLayer={},

	// can do anything in the shader with these two things
	flags:Quad_Flags={},
	params:Vec4={},

	// useful for having some stuff like col_override come from the entity
	entity:^Entity=nil,

	// crop
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,

	// this is used to scuffed insert the quad at an earlier draw spot
	z_layer_queue:=-1,
) {

	rect_size := get_sprite_size(sprite)
	frame_count := get_frame_count(sprite)
	rect_size.x /= f32(frame_count)

	/* this was the old one
	
	// todo, incorporate this via sprite data
	offset, pivot := get_sprite_offset(img_id)
	
	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform // we slide in here because rotations + scales work nicely at this point
	xform0 *= xform_translate(offset + frame_size * -scale_from_pivot(pivot))
	*/

	xform0 := Matrix4(1)
	xform0 *= utils.xform_translate(pos)
	xform0 *= utils.xform_scale(Vec2{flip_x ? -1.0 : 1.0, 1.0})
	xform0 *= xform
	xform0 *= utils.xform_translate(rect_size * -scale_from_pivot(pivot)) // pivot offset
	xform0 *= utils.xform_translate(-draw_offset) // extra draw offset for nudging into the desired pivot

	/*
	xform := xform
	if slight_overdraw {
		xform *= xform_translate(size / 2)
		xform *= xform_scale(v2(1.001))
		xform *= xform_translate(-size / 2)
	}
	*/

	draw_rect_xform(xform0, rect_size, sprite, anim_index=anim_index, col=col, col_override=col_override, z_layer=z_layer, flags=flags, params=params, entity=entity, crop_top=crop_top, crop_left=crop_left, crop_bottom=crop_bottom, crop_right=crop_right, z_layer_queue=z_layer_queue)
}

// draw a pre-positioned rect
draw_rect :: proc(
	rect: Rect,

	// these are explained below
	sprite:= Sprite_Name.nil,
	uv:= DEFAULT_UV,

	// draws an outline
	outline_col:=Vec4{},

	// I leave this out because I don't usually use it. I mainly use this function for UI drawing.
	// If needed, could add this in tho.
	//xform := Matrix4(1),

	// same as above
	col:=COLOR_WHITE,
	col_override:Vec4={},
	z_layer:ZLayer={},
	flags:Quad_Flags={},
	params:Vec4={},
	entity:^Entity=nil,
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	z_layer_queue:=-1,
) {
	// extract the transform from the rect
	xform := utils.xform_translate(rect.xy)
	size := rect_size(rect)

	// draw outline if we have one
	if outline_col != {} {
		size := size
		xform := xform
		size += v2(2)
		xform *= utils.xform_translate(v2(-1))
		draw_rect_xform(xform, size, col=outline_col, uv=uv, col_override=col_override, z_layer=z_layer, flags=flags, params=params)
	}

	draw_rect_xform(xform, size, sprite, uv, 0, 0, col, col_override, z_layer, flags, params, entity, crop_top, crop_left, crop_bottom, crop_right, z_layer_queue)
}

draw_rect_xform :: proc(
	xform: Matrix4,
	size: Vec2,
	
	// defaults to no sprite (blank color)
	sprite:= Sprite_Name.nil,

	// defaults to auto-grab the correct UV based on the sprite
	uv:= DEFAULT_UV,

	// by default this'll be the main texture atlas
	// can override though and use something else (like for the fonts)
	tex_index:u8=0,
	
	// same as above
	anim_index:=0,
	col:=COLOR_WHITE,
	col_override:Vec4={},
	z_layer:ZLayer={},
	flags:Quad_Flags={},
	params:Vec4={},
	entity:^Entity=nil,
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	z_layer_queue:=-1,

) {

	// apply ui alpha override
	col := col
	//col *= ui_state.alpha_mask
	
	// entity-specific drawing alterations
	// useful for setting and forgetting certain visual systems like the hit flash
	col_override := col_override
	if entity != nil {
		col_override = entity.scratch.col_override
		if entity.hit_flash.a != 0 {
			col_override.xyz = entity.hit_flash.xyz
			col_override.a = max(col_override.a, entity.hit_flash.a)
		}
	}

	uv := uv
	if uv == DEFAULT_UV {
		uv = atlas_uv_from_sprite(sprite)

		// animation UV hack
		// we assume all animations are just a long strip
		frame_count := get_frame_count(sprite)
		frame_size := size
		frame_size.x /= f32(frame_count)
		uv_size := rect_size(uv)
		uv_frame_size := uv_size * v2{frame_size.x/size.x, 1.0}
		uv.zw = uv.xy + uv_frame_size
		uv = shape.rect_shift(uv, v2{f32(anim_index)*uv_frame_size.x, 0})
	}

	//
	// create a simple AABB rect
	// and transform it into clipspace, ready for the GPU
	// see: https://learnopengl.com/img/getting-started/coordinate_systems.png
	if draw_frame.coord_space == {} {
		log.error("no coord space set!")
	}
	model := xform
	view := linalg.inverse(draw_frame.coord_space.camera)
	projection := draw_frame.coord_space.proj
	local_to_clip_space := projection * view * model

	// crop stuff
	size := size
	{
		if crop_top != 0.0 {
			utils.crash_when_debug("todo")
		}
		if crop_left != 0.0 {
			utils.crash_when_debug("todo")
		}
		if crop_bottom != 0.0 {
		
			crop := size.y * (1.0-crop_bottom)
			diff :f32= crop - size.y
			size.y = crop
			uv_size := rect_size(uv)
			
			uv.y += uv_size.y * crop_bottom
			local_to_clip_space *= utils.xform_translate(v2{0, -diff})
		}
		if crop_right != 0.0 {
			size.x *= 1.0-crop_right
			
			uv_size := rect_size(uv)
			uv.z -= uv_size.x * crop_right
		}
	}

	bl := v2{ 0, 0 }
	tl := v2{ 0, size.y }
	tr := v2{ size.x, size.y }
	br := v2{ size.x, 0 }

	tex_index := tex_index
	if tex_index == 0 && sprite == .nil {
		// make it not use a texture if we're blank
		tex_index = 255
	}

	draw_quad_projected(local_to_clip_space, {bl, tl, tr, br}, {col, col, col, col}, {uv.xy, uv.xw, uv.zw, uv.zy}, tex_index, size, col_override, z_layer, flags, params, z_layer_queue)
}

draw_quad_projected :: proc(
	world_to_clip:   Matrix4, 

	// for each corner of the quad
	positions:       [4]Vector2,
	colors:          [4]Vector4,
	uvs:             [4]Vector2,

	tex_index: u8,

	// we've lost the original sprite by this point, but it can be useful to
	// preserve it for some stuff in the shader
	sprite_size: Vector2,

	// same as above
	col_override: Vector4,
	z_layer: ZLayer=.nil,
	flags: Quad_Flags,
	params:= v4{},
	z_layer_queue:=-1,
) {
	z_layer0 := z_layer
	if z_layer0 == .nil {
		z_layer0 = draw_frame.active_z_layer
	}

	verts : [4]Vertex
	defer {
		quad_array := &draw_frame.quads[z_layer0]
		quad_array.allocator = context.temp_allocator

		if z_layer_queue == -1 {
			append(quad_array, verts)
		} else {

			assert(z_layer_queue < len(quad_array), "no elements pushed after the z_layer_queue")

			// I'm just kinda praying that this works lol, seems good
			
			// This is an array insert example
			resize_dynamic_array(quad_array, len(quad_array)+1)
			
			og_range := quad_array[z_layer_queue:len(quad_array)-1]
			new_range := quad_array[z_layer_queue+1:len(quad_array)]
			copy(new_range, og_range)

			quad_array[z_layer_queue] = verts
		}

	}
	
	verts[0].pos = (world_to_clip * Vector4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vector4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vector4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vector4{positions[3].x, positions[3].y, 0.0, 1.0}).xy
	
	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

	verts[0].uv = uvs[0]
	verts[1].uv = uvs[1]
	verts[2].uv = uvs[2]
	verts[3].uv = uvs[3]
	
	verts[0].local_uv = {0, 0}
	verts[1].local_uv = {0, 1}
	verts[2].local_uv = {1, 1}
	verts[3].local_uv = {1, 0}

	verts[0].tex_index = tex_index
	verts[1].tex_index = tex_index
	verts[2].tex_index = tex_index
	verts[3].tex_index = tex_index
	
	verts[0].size = sprite_size
	verts[1].size = sprite_size
	verts[2].size = sprite_size
	verts[3].size = sprite_size
	
	verts[0].col_override = col_override
	verts[1].col_override = col_override
	verts[2].col_override = col_override
	verts[3].col_override = col_override
	
	verts[0].z_layer = u8(z_layer0)
	verts[1].z_layer = u8(z_layer0)
	verts[2].z_layer = u8(z_layer0)
	verts[3].z_layer = u8(z_layer0)
	
	flags0 := flags | draw_frame.active_flags	
	verts[0].quad_flags = flags0
	verts[1].quad_flags = flags0
	verts[2].quad_flags = flags0
	verts[3].quad_flags = flags0
	
	verts[0].params = params
	verts[1].params = params
	verts[2].params = params
	verts[3].params = params
}

atlas_uv_from_sprite :: proc(sprite: Sprite_Name) -> Vec4 {
	return sprites[sprite].atlas_uvs
}

get_sprite_size :: proc(sprite: Sprite_Name) -> Vec2 {
	return {f32(sprites[sprite].width), f32(sprites[sprite].height)}
}