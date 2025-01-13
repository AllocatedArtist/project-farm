package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import rl "vendor:raylib"
import "vendor:raylib/rlgl"


get_tile_coordinates_from_index :: proc(index, map_width: i32) -> (x: i32, y: i32) {
	y = math.floor_div(index, map_width)
	x = index % map_width
	return
}

get_index_from_tile_coordinates :: proc(x, y, map_width: i32) -> i32 {
	return x + y * map_width
}

is_grass :: proc(index: i32, map_width: i32, map_data: []u8) -> b32 {
	if is_out_of_bounds(index, map_width) do return true
	return map_data[index] == 0
}

is_out_of_bounds :: proc(index: i32, map_width: i32) -> b32 {
	return index < 0 || index >= (map_width * map_width)
}

auto_tile_update :: proc(map_data: []u8, bitmask: []u8) {

	index: i32 = 0
	map_width: i32 = 40

	for tile in map_data {
		if tile == 0 {
			index += 1
			continue
		}

		pos_x, pos_y := get_tile_coordinates_from_index(index, map_width)

		top := get_index_from_tile_coordinates(pos_x, pos_y - 1, map_width)
		bottom := get_index_from_tile_coordinates(pos_x, pos_y + 1, map_width)
		left := get_index_from_tile_coordinates(pos_x - 1, pos_y, map_width)
		right := get_index_from_tile_coordinates(pos_x + 1, pos_y, map_width)

		top_is_grass := is_grass(top, map_width, map_data)
		bottom_is_grass := is_grass(bottom, map_width, map_data)
		left_is_grass := is_grass(left, map_width, map_data)
		right_is_grass := is_grass(right, map_width, map_data)

		bitmask_val: u8
		if !top_is_grass do bitmask_val += 1
		if !bottom_is_grass do bitmask_val += 4
		if !left_is_grass do bitmask_val += 8
		if !right_is_grass do bitmask_val += 2

		bitmask[index] = bitmask_val

		index += 1
	}
}

camera_restrain_border :: proc(
	camera: ^rl.Camera2D,
	grid_size: f32,
	map_size: i32,
	viewport_size: [2]i32,
) {
	viewport_width, viewport_height := viewport_size.x, viewport_size.y

	render_width := cast(f32)viewport_width
	render_height := cast(f32)viewport_height

	top_left := rl.GetScreenToWorld2D(rl.Vector2(0), camera^)
	top_left.x += 0.1
	top_left.y += 0.1

	bottom_right := rl.GetScreenToWorld2D(rl.Vector2{render_width, render_height}, camera^)
	bottom_right.x += grid_size - 0.1
	bottom_right.y += grid_size - 0.1

	map_bounds := rl.Rectangle{}
	map_bounds.x = grid_size
	map_bounds.y = grid_size

	map_bounds.width = cast(f32)map_size * grid_size
	map_bounds.height = cast(f32)map_size * grid_size


	if !rl.CheckCollisionPointRec(top_left, map_bounds) {
		if top_left.x < grid_size do camera.offset.x = -grid_size
		if top_left.y < grid_size do camera.offset.y = -grid_size
	}

	if !rl.CheckCollisionPointRec(bottom_right, map_bounds) {
		if bottom_right.x - grid_size > map_bounds.width do camera.offset.x = render_width - map_bounds.width
		if bottom_right.y - grid_size > map_bounds.height do camera.offset.y = render_height - map_bounds.height
	}
}

update_sprite_size :: proc(sprite: ^rl.Rectangle, grid_size: f32) {
	sprite.width = grid_size
	sprite.height = grid_size
}

DEFAULT_FONT_SIZE: f32 : 46.0

text :: proc(
	font: rl.Font,
	text: string,
	y: f32,
	viewport_width: i32,
	padding: f32,
	color: rl.Color,
) {
	ctext := strings.clone_to_cstring(text)

	default_monitor_width: f32 = 3456
	ratio := cast(f32)rl.GetScreenWidth() / default_monitor_width
	font_size: f32 = DEFAULT_FONT_SIZE * ratio

	padding := padding * ratio

	rl.DrawTextEx(
		font,
		ctext,
		rl.Vector2{cast(f32)viewport_width + padding, y * font_size + padding},
		font_size,
		1.0,
		color,
	)
}

grid_pos_from_world :: proc(pos: rl.Vector2, grid_size: f32) -> (grid_x: i32, grid_y: i32) {
	grid_x = cast(i32)math.floor(pos.x / grid_size)
	grid_y = cast(i32)math.floor(pos.y / grid_size)
	return
}

main :: proc() {

	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE})

	rl.InitWindow(800, 800, "Farming game")
	defer rl.CloseWindow()

	rl.MaximizeWindow()

	rl.SetTargetFPS(60)

	main_font := rl.LoadFont("assets/font/MajorMonoDisplay-Regular.ttf")
	defer rl.UnloadFont(main_font)

	// font_atlas := rl.GenImageFontAtlas(
	// 	main_font.glyphs,
	// 	&main_font.recs,
	// 	main_font.glyphCount,
	// 	main_font.baseSize,
	// 	main_font.glyphPadding,
	// 	1,
	// )
	// main_font.texture = rl.LoadTextureFromImage(font_atlas)
	// rl.UnloadImage(font_atlas)
	tileset_texture := rl.LoadTexture("assets/ts1.png")
	defer rl.UnloadTexture(tileset_texture)

	rl.SetTextureFilter(main_font.texture, .TRILINEAR)

	tileset_width: i32 = 17
	tileset_height: i32 = 1
	tile_size: f32 = 32
	grid_size: f32 = 64

	default_grid_size: f32 = 64
	initial_screen_width: f32 = 1600

	sprite := rl.Rectangle{}
	sprite.width = grid_size
	sprite.height = grid_size

	grass := rl.Rectangle{}
	grass.x = 0
	grass.y = 0
	grass.width = tile_size
	grass.height = tile_size

	map_size: i32 : 40

	seeds: map[[2]i32]b32
	defer delete(seeds)

	map_data: [map_size * map_size]u8
	bitmask: [map_size * map_size]u8

	prev_grid_pos: [2]i32 = {-1, -1}
	prev_place: bool = false

	camera: rl.Camera2D
	camera.zoom = 1.0
	camera.target = rl.Vector2(0)
	camera.rotation = 0.0
	camera.offset = rl.Vector2(0)

	ratio_x: f32 : 1250.0 / 1600.0
	ratio_y: f32 : 1200.0 / 1400.0

	viewport_width: i32 = cast(i32)math.ceil(cast(f32)rl.GetScreenWidth() * ratio_x)
	viewport_height: i32 = cast(i32)math.ceil(cast(f32)rl.GetScreenHeight() * ratio_y)

	game_screen := rl.LoadRenderTexture(viewport_width, viewport_height)
	defer rl.UnloadRenderTexture(game_screen)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

		viewport := rl.Rectangle{}
		viewport.x = 0
		viewport.y = 0
		viewport.width = cast(f32)viewport_width
		viewport.height = cast(f32)viewport_height

		intersect_viewport := rl.CheckCollisionPointRec(rl.GetMousePosition(), viewport)

		if rl.IsWindowResized() {
			viewport_width = cast(i32)math.ceil(cast(f32)rl.GetScreenWidth() * ratio_x)
			viewport_height = cast(i32)math.ceil(cast(f32)rl.GetScreenHeight() * ratio_y)

			rl.UnloadRenderTexture(game_screen)
			game_screen = rl.LoadRenderTexture(viewport_width, viewport_height)
			grid_size = default_grid_size * cast(f32)rl.GetScreenWidth() / initial_screen_width

			update_sprite_size(&sprite, grid_size)

			camera_restrain_border(
				&camera,
				grid_size,
				map_size,
				[2]i32{viewport_width, viewport_height},
			)
		}

		if rl.IsMouseButtonDown(.MIDDLE) {
			camera_move_speed: f32 = 0.3
			camera.offset += rl.GetMouseDelta() * camera_move_speed
			camera_restrain_border(
				&camera,
				grid_size,
				map_size,
				[2]i32{viewport_width, cast(i32)viewport_height},
			)
		}

		mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

		place := rl.IsMouseButtonDown(rl.MouseButton.LEFT)
		destroy := rl.IsMouseButtonDown(rl.MouseButton.RIGHT)

		if (place || destroy) && intersect_viewport && !(place && destroy) {
			grid_x, grid_y := grid_pos_from_world(mouse_pos, grid_size)
			index := get_index_from_tile_coordinates(grid_x, grid_y, map_size)

			grid_x_valid := grid_x >= 0 && grid_x < map_size
			grid_y_valid := grid_y >= 0 && grid_y < map_size
			if !is_out_of_bounds(index, map_size) && grid_x_valid && grid_y_valid {
				if (prev_grid_pos.x != grid_x || prev_grid_pos.y != grid_y) ||
				   (prev_place != place) {
					prev_place = place
					map_data[index] = place ? 1 : 0

					auto_tile_update(map_data[:], bitmask[:])
					prev_grid_pos = [2]i32{grid_x, grid_y}
				}
			}
		}

		rl.BeginTextureMode(game_screen)
		rl.BeginMode2D(camera)

		rl.ClearBackground(rl.BLACK)

		for x in 0 ..< map_size {
			for y in 0 ..< map_size {
				sprite.x = cast(f32)x * grid_size
				sprite.y = cast(f32)y * grid_size

				index := get_index_from_tile_coordinates(x, y, map_size)
				tile := b32(map_data[index])

				if !tile {
					rl.DrawTexturePro(tileset_texture, grass, sprite, rl.Vector2(0), 0, rl.WHITE)
				} else {
					dirt_tile := rl.Rectangle{}
					dirt_tile.x = cast(f32)(bitmask[index] + 1) * tile_size
					dirt_tile.y = 0
					dirt_tile.width = tile_size
					dirt_tile.height = tile_size

					rl.DrawTexturePro(
						tileset_texture,
						dirt_tile,
						sprite,
						rl.Vector2(0),
						0,
						rl.WHITE,
					)
				}

				rl.DrawRectangleLines(
					cast(i32)sprite.x,
					cast(i32)sprite.y,
					cast(i32)grid_size,
					cast(i32)grid_size,
					rl.BLACK,
				)
			}
		}
		rl.EndTextureMode()

		rl.EndMode2D()

		custom_dark := rl.Color{}
		custom_dark.r = 29
		custom_dark.g = 22
		custom_dark.b = 22
		custom_dark.a = 255

		rl.ClearBackground(custom_dark)
		source_game := rl.Rectangle{}
		source_game.x = 0
		source_game.y = 0
		source_game.width = cast(f32)viewport_width
		source_game.height = -cast(f32)viewport_height


		rl.DrawTexturePro(game_screen.texture, source_game, viewport, rl.Vector2(0), 0, rl.WHITE)

		padding: f32 = 10
		text(main_font, "todo:", 0, viewport_width, padding, rl.WHITE)
		text(main_font, "- galaxy stride 3", 1, viewport_width, padding, rl.WHITE)
		text(main_font, "- synthslayer", 2, viewport_width, padding, rl.WHITE)
		text(main_font, "- bloodfarme", 3, viewport_width, padding, rl.WHITE)
		text(main_font, "beets: 69", 5, viewport_width, padding, rl.WHITE)
		text(main_font, "dirt: 32", 6, viewport_width, padding, rl.WHITE)
		text(main_font, "money: $100", 8, viewport_width, padding, rl.WHITE)
		text(main_font, "quota: 200 beets", 10, viewport_width, padding, rl.RED)

		text(main_font, "your god commands", 12, viewport_width, 80, rl.PINK)


	}


}

