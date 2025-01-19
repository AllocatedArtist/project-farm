package beets

import "core:fmt"
import "core:math"
import "core:math/linalg"
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
LARGEST_FONT_SIZE: f32 : 92.0

DEFAULT_MONITOR_WIDTH: f32 : 3456

horizontal_ratio_get :: proc() -> f32 {
	return cast(f32)rl.GetScreenWidth() / DEFAULT_MONITOR_WIDTH
}

text :: proc(
	font: rl.Font,
	text: string,
	pos: [2]f32,
	padding: f32,
	color: rl.Color,
	size: f32 = DEFAULT_FONT_SIZE,
) {
	ctext := strings.clone_to_cstring(text)

	ratio := horizontal_ratio_get()
	font_size: f32 = size * ratio

	padding := padding * ratio

	rl.DrawTextEx(
		font,
		ctext,
		rl.Vector2{cast(f32)pos.x + padding, pos.y * DEFAULT_FONT_SIZE * ratio},
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

Player :: struct {
	//what's earned from resources
	money:    i32,
	beets:    i32,

	//resources
	dirt:     i32,
	seeds:    i32,
	turrets:  i32,
	selected: ItemCategory,
}

INITIAL_MONEY: i32 : 100

//laissez-faire is not a thing
MAX_MONEY: i32 : 10_000_000

player_pay_money :: proc(player: ^Player, amount: i32) -> b32 {
	if player.money >= amount {
		player.money -= amount
		player.money = clamp(player.money, 0, MAX_MONEY)
		return true
	}
	return false
}

player_earn_money :: proc(player: ^Player, amount: i32) {
	player.money += amount
	player.money = min(player.money, MAX_MONEY)
}

player_balance_check :: proc(player: ^Player, required: i32) -> b32 {
	return player.money >= required
}

ItemCategory :: enum {
	Dirt,
	Seed,
	Ballista,
}

ItemType :: union {
	ShopItemButton,
	InventoryItemButton,
	TurretUpgradeItemButton,
}

ShopItemButton :: struct {
	price:    i32,
	category: ItemCategory,
	timer:    f32,
	pressed:  b32,
}

InventoryItemButton :: ItemCategory


TurretUpgradeItemButton :: struct {
	nothing: f32,
}


ItemButton :: struct {
	thumbnail: rl.Texture2D,
	on_click:  proc(user_data: rawptr, item_data: rawptr),
	name:      string,
	item_type: ItemType,
}

BUTTON_IDLE_COLOR: rl.Color : rl.WHITE
BUTTON_HOVER_COLOR: rl.Color : rl.GRAY
BUTTON_CLICK_COLOR: rl.Color : rl.SKYBLUE

item_button_update :: proc(
	font: rl.Font,
	item_button: ^ItemButton,
	bounds: rl.Rectangle,
	user_data: rawptr,
	padding: f32,
) {

	bounds := bounds
	bounds.x += padding * horizontal_ratio_get()
	bounds.y *= horizontal_ratio_get()
	bounds.width *= horizontal_ratio_get()
	bounds.height *= horizontal_ratio_get()

	hovering := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
	left_pressed := rl.IsMouseButtonPressed(.LEFT)
	left_down := rl.IsMouseButtonDown(.LEFT)
	left_released := rl.IsMouseButtonReleased(.LEFT)


	color := hovering ? BUTTON_HOVER_COLOR : BUTTON_IDLE_COLOR
	border_color := rl.GREEN

	switch &type in item_button.item_type {
	case ShopItemButton:
		{
			TIME_LIMIT: f32 : 0.85
			if left_pressed && hovering {
				type.pressed = true
				item_button.on_click(user_data, &type)
				color = BUTTON_CLICK_COLOR
			}

			if left_down && hovering {
				type.timer += rl.GetFrameTime()
				if type.timer >= TIME_LIMIT do type.timer = TIME_LIMIT
			}

			if left_released || !hovering {
				type.timer = 0
				type.pressed = false
			}

			if type.timer >= TIME_LIMIT && hovering && type.pressed {
				item_button.on_click(user_data, &type)
				color = BUTTON_CLICK_COLOR
			}

			y := (bounds.y + bounds.height * 0.5) / DEFAULT_FONT_SIZE / horizontal_ratio_get()
			text(
				font,
				string(rl.TextFormat("%s - $%d", item_button.name, type.price)),
				[2]f32{bounds.x + bounds.width, y},
				30,
				rl.WHITE,
				DEFAULT_FONT_SIZE,
			)
		}
	case ItemCategory:
		{
			player := cast(^Player)user_data
			assert(player != nil)
			y := (bounds.y + bounds.height * 0.5) / DEFAULT_FONT_SIZE / horizontal_ratio_get()
			quantity: i32 = 0
			switch type {
			case .Dirt:
				quantity = player.dirt
			case .Seed:
				quantity = player.seeds
			case .Ballista:
				quantity = player.turrets
			}
			if left_pressed && hovering do player.selected = type

			if player.selected == type {
				color = rl.GRAY
				border_color = rl.RED
			}

			text(
				font,
				string(rl.TextFormat("%s (%d)", item_button.name, quantity)),
				[2]f32{bounds.x + bounds.width, y},
				30,
				rl.WHITE,
				DEFAULT_FONT_SIZE - 2,
			)
		}
	case TurretUpgradeItemButton:
	}

	rl.DrawRectangleRoundedLinesEx(bounds, 0.2, 10, 5.0, border_color)
	rl.DrawRectangleRounded(bounds, 0.2, 10, color)
	rl.DrawTexturePro(
		item_button.thumbnail,
		rl.Rectangle {
			0,
			0,
			cast(f32)item_button.thumbnail.width,
			cast(f32)item_button.thumbnail.height,
		},
		bounds,
		rl.Vector2(0),
		0.0,
		color,
	)
}

shop_buy :: proc(data: rawptr, item_type: rawptr) {
	player := cast(^Player)data
	item := cast(^ShopItemButton)item_type

	assert(item != nil)
	assert(player != nil)

	if player_pay_money(player, item.price) {
		switch (item.category) {
		case .Seed:
			player.seeds += 1
		case .Dirt:
			player.dirt += 1
		case .Ballista:
			player.turrets += 1

		}
	}
}

inventory_item_select :: proc(data: rawptr, item_type: rawptr) {
	player := cast(^Player)data
	item_type := cast(^ItemCategory)item_type

	assert(item_type != nil)
	assert(player != nil)

	player.selected = item_type^
}

shop_make_item_button :: proc(item_type: ItemCategory) -> ShopItemButton {
	BALLISTA_PRICE: i32 : 200
	SEED_PRICE: i32 : 150
	DIRT_PRICE: i32 : 100
	switch (item_type) {
	case .Seed:
		return ShopItemButton{SEED_PRICE, item_type, 0, false}
	case .Dirt:
		return ShopItemButton{DIRT_PRICE, item_type, 0, false}
	case .Ballista:
		return ShopItemButton{BALLISTA_PRICE, item_type, 0, false}
	}
	panic("Invalid item type?")
}

tile_place :: proc(player: ^Player, world: ^World, index: i32) {
	dirt_check := player.dirt > 0 && world.map_data[index] == 0

	//this is a crazy line
	seed_check := player.seeds > 0 && world.objects[index] == 0 && world.map_data[index] == 1

	ballista_check := player.turrets > 0 && world.map_data[index] == 0

	switch player.selected {
	case .Dirt:
		if dirt_check {
			player.dirt -= 1
			world.map_data[index] = 1
			auto_tile_update(world.map_data[:], world.bitmask[:])
		}
	case .Seed:
		if seed_check {
			world.objects[index] = SEED_PLACE_INDEX
			player.seeds -= 1
		}
	case .Ballista:
		if ballista_check {
			world.objects[index] = TURRET_PLACE_INDEX
			player.turrets -= 1
		}
	}
}

tile_erase :: proc(player: ^Player, world: ^World, index: i32) {
	object_index := world.objects[index]
	if world.map_data[index] == 0 && object_index == 0 do return

	defer auto_tile_update(world.map_data[:], world.bitmask[:])

	if object_index != 0 {
		world.objects[index] = 0
		if object_index == SEED_PLACE_INDEX do player.seeds += 1
		if object_index == TURRET_PLACE_INDEX do player.turrets += 1
		return
	}

	player.dirt += 1
	world.map_data[index] = 0
}


MAP_SIZE: i32 : 40

//indices for object array
SEED_PLACE_INDEX: u8 : 1
TURRET_PLACE_INDEX: u8 : 2
GROWN_BEET: u8 : 3

World :: struct {
	map_data:       [MAP_SIZE * MAP_SIZE]u8,
	bitmask:        [MAP_SIZE * MAP_SIZE]u8,
	objects:        [MAP_SIZE * MAP_SIZE]u8,
	beet_collector: [MAP_SIZE * MAP_SIZE][2]f32,
	beet_count:     i32,
}

world_grow_beets :: proc(world: ^World) {
	for x in 0 ..< MAP_SIZE {
		for y in 0 ..< MAP_SIZE {
			index := get_index_from_tile_coordinates(x, y, MAP_SIZE)
			if world.objects[index] == SEED_PLACE_INDEX do world.objects[index] = GROWN_BEET
		}
	}
}

world_collect_beets :: proc(world: ^World, camera: rl.Camera2D, grid_size: f32) {
	@(static) beet_screen: [MAP_SIZE * MAP_SIZE][2]f32
	counter := 0
	for x in 0 ..< MAP_SIZE {
		for y in 0 ..< MAP_SIZE {
			index := get_index_from_tile_coordinates(x, y, MAP_SIZE)
			if world.objects[index] == GROWN_BEET {
				world.objects[index] = 0
				coords_x, coords_y := get_tile_coordinates_from_index(index, MAP_SIZE)
				half_size := grid_size * 0.5
				world.beet_collector[counter] = [2]f32 {
					cast(f32)coords_x * grid_size - half_size,
					cast(f32)coords_y * grid_size - half_size,
				}
				world.beet_collector[counter] = rl.GetWorldToScreen2D(
					world.beet_collector[counter],
					camera,
				)
				counter += 1
				world.beet_count += 1
			}
		}
	}
}

ease_in :: proc(x: f32) -> f32 {
	return x * x
}

main :: proc() {

	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE, .MSAA_4X_HINT})

	rl.InitWindow(800, 800, "Blood Beets")
	defer rl.CloseWindow()

	rl.MaximizeWindow()

	rl.SetTargetFPS(60)

	main_font := rl.LoadFontEx(
		"assets/font/MajorMonoDisplay-Regular.ttf",
		cast(i32)LARGEST_FONT_SIZE,
		nil,
		150,
	)
	defer rl.UnloadFont(main_font)

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

	player := Player {
		money    = INITIAL_MONEY,
		beets    = 0,
		dirt     = 0,
		seeds    = 0,
		selected = .Dirt,
	}

	//rich!
	player.money = 10_000

	seed_texture := rl.LoadTexture("assets/seed.png")
	defer rl.UnloadTexture(seed_texture)

	ballista_texture := rl.LoadTexture("assets/balista.png")
	defer rl.UnloadTexture(ballista_texture)

	dirt_texture := rl.LoadTexture("assets/dirt.png")
	defer rl.UnloadTexture(dirt_texture)

	beet_ground_texture := rl.LoadTexture("assets/BeetGround.png")
	defer rl.UnloadTexture(beet_ground_texture)

	beet_grown_texture := rl.LoadTexture("assets/Beet.png")
	defer rl.UnloadTexture(beet_grown_texture)

	icon_bounds := rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = 128,
		height = 128,
	}

	seed_shop_button := ItemButton{seed_texture, shop_buy, "seed", shop_make_item_button(.Seed)}
	dirt_shop_button := ItemButton{dirt_texture, shop_buy, "dirt", shop_make_item_button(.Dirt)}
	ballista_shop_button := ItemButton {
		ballista_texture,
		shop_buy,
		"turret",
		shop_make_item_button(.Ballista),
	}

	seed_inventory_button := ItemButton{seed_texture, inventory_item_select, "seed", .Seed}
	dirt_inventory_button := ItemButton{dirt_texture, inventory_item_select, "dirt", .Dirt}
	ballista_inventory_button := ItemButton {
		ballista_texture,
		inventory_item_select,
		"ballista",
		.Ballista,
	}

	world := World{}
	BEET_PROFIT: i32 : 200


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
				MAP_SIZE,
				[2]i32{viewport_width, viewport_height},
			)
		}

		if rl.IsMouseButtonDown(.MIDDLE) {
			camera_move_speed: f32 = 0.3
			camera.offset += rl.GetMouseDelta() * camera_move_speed
			camera_restrain_border(
				&camera,
				grid_size,
				MAP_SIZE,
				[2]i32{viewport_width, cast(i32)viewport_height},
			)
		}

		mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

		place := rl.IsMouseButtonDown(rl.MouseButton.LEFT)
		destroy := rl.IsMouseButtonDown(rl.MouseButton.RIGHT)

		if rl.IsMouseButtonReleased(rl.MouseButton.RIGHT) {
			prev_grid_pos = [2]i32{-1, -1}
		}

		if (place || destroy) && intersect_viewport && !(place && destroy) {
			grid_x, grid_y := grid_pos_from_world(mouse_pos, grid_size)
			index := get_index_from_tile_coordinates(grid_x, grid_y, MAP_SIZE)

			grid_x_valid := grid_x >= 0 && grid_x < MAP_SIZE
			grid_y_valid := grid_y >= 0 && grid_y < MAP_SIZE
			if !is_out_of_bounds(index, MAP_SIZE) && grid_x_valid && grid_y_valid {
				cursor_different_place := (prev_grid_pos.x != grid_x || prev_grid_pos.y != grid_y)
				action_different := (prev_place != place)

				valid_cursor_loc := cursor_different_place || action_different

				if valid_cursor_loc {
					prev_place = place

					filled_space := b32(world.map_data[index]) || world.objects[index] > 0

					if place {
						tile_place(&player, &world, index)
					} else if filled_space {
						tile_erase(&player, &world, index)
					}

					prev_grid_pos = [2]i32{grid_x, grid_y}
				}
			}
		}

		if !intersect_viewport {
			prev_grid_pos.x = -1
			prev_grid_pos.y = -1
		}

		rl.BeginTextureMode(game_screen)
		rl.BeginMode2D(camera)

		rl.ClearBackground(rl.BLACK)

		for x in 0 ..< MAP_SIZE {
			for y in 0 ..< MAP_SIZE {
				sprite.x = cast(f32)x * grid_size
				sprite.y = cast(f32)y * grid_size

				index := get_index_from_tile_coordinates(x, y, MAP_SIZE)
				tile := b32(world.map_data[index])

				if !tile {
					rl.DrawTexturePro(tileset_texture, grass, sprite, rl.Vector2(0), 0, rl.WHITE)
				} else {
					dirt_tile := rl.Rectangle{}
					dirt_tile.x = cast(f32)(world.bitmask[index] + 1) * tile_size
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

		for x in 0 ..< MAP_SIZE {
			for y in 0 ..< MAP_SIZE {
				sprite.x = cast(f32)x * grid_size
				sprite.y = cast(f32)y * grid_size

				index := get_index_from_tile_coordinates(x, y, MAP_SIZE)
				tile := world.objects[index]

				current_texture: rl.Texture2D
				current_bounds: rl.Rectangle
				current_bounds.x = 0
				current_bounds.y = 0

				switch (tile) {
				case SEED_PLACE_INDEX:
					current_texture = seed_texture
					current_bounds.width = cast(f32)seed_texture.width
					current_bounds.height = cast(f32)seed_texture.height
				case TURRET_PLACE_INDEX:
					current_texture = ballista_texture
					current_bounds.width = cast(f32)ballista_texture.width
					current_bounds.height = cast(f32)ballista_texture.height
				case GROWN_BEET:
					current_texture = beet_ground_texture
					current_bounds.width = cast(f32)beet_ground_texture.width
					current_bounds.height = cast(f32)beet_ground_texture.height
				}

				rl.DrawTexturePro(
					current_texture,
					current_bounds,
					sprite,
					rl.Vector2(0),
					0,
					rl.WHITE,
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

		padding: f32 = 50
		money_pos := [2]f32{cast(f32)viewport_width, 36}
		text(
			main_font,
			string(rl.TextFormat("money: $%d", player.money)),
			[2]f32{cast(f32)viewport_width, 36},
			padding,
			rl.WHITE,
			DEFAULT_FONT_SIZE,
		)

		money_pos.x += padding
		money_pos.y *= horizontal_ratio_get() * DEFAULT_FONT_SIZE


		CENTER_ALIGNMENT: f32 : 200

		icon_bounds.x = cast(f32)viewport_width

		text(
			main_font,
			"inventory",
			[2]f32{cast(f32)viewport_width, 1},
			100,
			rl.PINK,
			LARGEST_FONT_SIZE * 0.9,
		)

		icon_bounds.y = 200
		item_button_update(main_font, &seed_inventory_button, icon_bounds, &player, padding)

		icon_bounds.y = 400
		item_button_update(main_font, &dirt_inventory_button, icon_bounds, &player, padding)

		icon_bounds.y = 600
		item_button_update(main_font, &ballista_inventory_button, icon_bounds, &player, padding)

		text(
			main_font,
			"shop",
			[2]f32{cast(f32)viewport_width, 18},
			CENTER_ALIGNMENT,
			rl.PINK,
			LARGEST_FONT_SIZE,
		)

		icon_bounds.y = 1000
		item_button_update(main_font, &seed_shop_button, icon_bounds, &player, padding)

		icon_bounds.y = 1200
		item_button_update(main_font, &dirt_shop_button, icon_bounds, &player, padding)

		icon_bounds.y = 1400
		item_button_update(main_font, &ballista_shop_button, icon_bounds, &player, padding)

		text(
			main_font,
			string(rl.TextFormat("beets (%d)", player.beets)),
			[2]f32{cast(f32)viewport_width, 38},
			padding,
			rl.RED,
		)

		text(
			main_font,
			string(rl.TextFormat("quota (%d)", 100)),
			[2]f32{cast(f32)viewport_width, 40},
			padding,
			rl.RED,
		)

		lerp_duration: f32 = 14.0
		start_time: f32 = 2.1
		for i in 0 ..< world.beet_count {
			world.beet_collector[i] = linalg.lerp(
				world.beet_collector[i],
				money_pos,
				ease_in(start_time / lerp_duration),
			)
		}

		for i in 0 ..< world.beet_count {
			pos := world.beet_collector[i]
			sprite.x = pos.x
			sprite.y = pos.y
			rl.DrawTexturePro(
				beet_grown_texture,
				rl.Rectangle {
					0,
					0,
					cast(f32)beet_grown_texture.width,
					cast(f32)beet_grown_texture.height,
				},
				sprite,
				rl.Vector2(0),
				0.0,
				rl.WHITE,
			)

			money_text_bounds: rl.Rectangle
			money_text_bounds.x = money_pos.x
			money_text_bounds.y = money_pos.y
			money_text_bounds.width = DEFAULT_FONT_SIZE
			money_text_bounds.height = DEFAULT_FONT_SIZE

			if rl.CheckCollisionRecs(sprite, money_text_bounds) {
				world.beet_count -= 1
				player.beets += 1
				player.money += BEET_PROFIT
			}
		}

	}
}

