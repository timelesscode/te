package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math/rand"
import "core:slice"

// ===================================================================
// Game Structures
// ===================================================================

Player :: struct {
    model: rl.Model,
    position: rl.Vector3,
    rotation: f32,
    speed: f32,
    health: i32,
    max_health: i32,
    credits: i32,
    
    // Upgrades
    weapons: struct {
        damage: i32,
        level: i32,
    },
    shields: struct {
        protection: i32,
        level: i32,
    },
}

ShipData :: struct {
    name: string,
    health: i32,
    damage: i32,
    credits_reward: i32,
    shader_color: rl.Color,
}

BattleState :: enum {
    IDLE,
    ACTIVE,
    PLAYER_TURN,
    ENEMY_TURN,
    VICTORY,
    DEFEAT,
}

Battle :: struct {
    active: bool,
    state: BattleState,
    enemy: ShipData,
    player_health: i32,
    enemy_health: i32,
    battle_log: [5]string,
    log_index: int,
}

GameState :: enum {
    FLYING,
    AT_HOUSE,
    IN_BATTLE,
}

Game :: struct {
    state:           GameState,
    player:          Player,
    house_model:     rl.Model,
    tree_model:      rl.Model,
    enemy_model:     rl.Model,
    
    trees:           [100]rl.Vector3,
    house_pos:       rl.Vector3,
    house_collision: rl.BoundingBox,
    
    music:           [4]rl.Music,
    current_track:   int,
    
    camera:          rl.Camera3D,
    game_over:       bool,
    
    battle:          Battle,
    
    // House UI
    show_shop:       bool,
    show_upgrades:   bool,
    
    // Enemy spawn timer
    battle_timer:    f32,
    battle_cooldown: f32,
}

// ===================================================================
// Enemy Ship Data
// ===================================================================

enemies := []ShipData{
    {name = "Scout", health = 30, damage = 8, credits_reward = 50, shader_color = {255, 100, 100, 255}},
    {name = "Fighter", health = 50, damage = 12, credits_reward = 100, shader_color = {255, 50, 50, 255}},
    {name = "Bomber", health = 80, damage = 20, credits_reward = 150, shader_color = {200, 50, 50, 255}},
    {name = "Interceptor", health = 40, damage = 15, credits_reward = 75, shader_color = {255, 150, 150, 255}},
}

// ===================================================================
// Main
// ===================================================================

main :: proc() {
    rl.InitWindow(1280, 720, "TE Games - Space RPG Prototype")
    defer rl.CloseWindow()

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

    game := init_game()

    rl.SetTargetFPS(60)
    rl.SetTraceLogLevel(.WARNING)

    for !rl.WindowShouldClose() && !game.game_over {
        update(&game)
        draw(&game)
    }

    unload_game(&game)
}

// ===================================================================
// Initialization
// ===================================================================

init_game :: proc() -> Game {
    game := Game{
        state = .FLYING,
        player = Player{
            speed = 18.0,
            health = 100,
            max_health = 100,
            credits = 500,
            weapons = {damage = 15, level = 1},
            shields = {protection = 10, level = 1},
        },
        house_pos = {0, 0, -1250},
        house_collision = rl.BoundingBox{min = {-25, -5, -1275}, max = {25, 15, -1225}},
        camera = rl.Camera3D{
            position   = {0, 25, 40},
            target     = {0, 0, 0},
            up         = {0, 1, 0},
            fovy       = 45,
            projection = .PERSPECTIVE,
        },
        battle_cooldown = 3.0,
        battle = Battle{active = false, state = .IDLE},
    }

    // Load Models
    game.house_model   = rl.LoadModel("../art/house1.glb")
    game.tree_model    = rl.LoadModel("../art/tree1.glb")
    game.player.model  = rl.LoadModel("../art/ship2.glb")
    game.enemy_model   = rl.LoadModel("../art/ship2.glb")

    // Load Music
    track_paths := [?]cstring{
        "../sounds/intro.wav",
        "../sounds/maintheme.wav",
        "../sounds/song1.wav",
        "../sounds/gameover.wav",
    }

    for i := 0; i < len(track_paths); i += 1 {
        game.music[i] = rl.LoadMusicStream(track_paths[i])
    }

    // Start music
    game.current_track = 1
    rl.PlayMusicStream(game.music[game.current_track])

    generate_tree_path(&game)

    return game
}

generate_tree_path :: proc(game: ^Game) {
    for i := 0; i < 100; i += 1 {
        x := f32(i % 10 - 5) * 9.0 + f32(rand.int31_max(9) - 4)
        z := f32(i) * -13.0 + f32(rand.int31_max(10) - 5)
        game.trees[i] = {x, 0, z}
    }
}

// ===================================================================
// Update
// ===================================================================

update :: proc(game: ^Game) {
    dt := rl.GetFrameTime()
    
    // Update music
    rl.UpdateMusicStream(game.music[game.current_track])
    if !rl.IsMusicStreamPlaying(game.music[game.current_track]) {
        game.current_track = (game.current_track + 1) % 3
        rl.PlayMusicStream(game.music[game.current_track])
    }

    if game.game_over { return }
    
    switch game.state {
    case .FLYING:
        update_flying(game, dt)
    case .AT_HOUSE:
        update_house(game, dt)
    case .IN_BATTLE:
        update_battle(game, dt)
    }
}

update_flying :: proc(game: ^Game, dt: f32) {
    // Player Movement
    move := rl.Vector3{}
    if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    { move.z -= 1 }
    if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  { move.z += 1 }
    if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  { move.x -= 1; game.player.rotation = 90 }
    if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { move.x += 1; game.player.rotation = -90 }

    if rl.Vector3Length(move) > 0.01 {
        move = rl.Vector3Normalize(move)
        game.player.position += move * game.player.speed * dt
    }
    
    // Check house collision
    player_bounds := rl.BoundingBox{
        min = game.player.position - {5, 2, 5},
        max = game.player.position + {5, 5, 5},
    }
    
    if rl.CheckCollisionBoxes(player_bounds, game.house_collision) {
        game.state = .AT_HOUSE
        game.show_shop = false
        game.show_upgrades = false
        game.player.position = {0, 0, -1000}
    }
    
    // Random battle encounters
    game.battle_timer += dt
    if game.battle_timer >= game.battle_cooldown {
        if rand.int31_max(100) < 15 {
            start_battle(game)
        }
        game.battle_timer = 0
        game.battle_cooldown = f32(rand.int31_max(60) + 30) / 10.0
    }
    
    // Camera follow
    game.camera.target = game.player.position
    game.camera.position = game.player.position + rl.Vector3{0, 28, 45}
}

update_house :: proc(game: ^Game, dt: f32) {
    // Press E to exit house
    if rl.IsKeyPressed(.E) {
        game.state = .FLYING
        game.player.position = {0, 0, -1000}
    }
    
    // Shop UI (Press S)
    if rl.IsKeyPressed(.S) {
        game.show_shop = !game.show_shop
        game.show_upgrades = false
    }
    
    // Upgrades UI (Press U)
    if rl.IsKeyPressed(.U) {
        game.show_upgrades = !game.show_upgrades
        game.show_shop = false
    }
    
    // Handle shop purchases
    if game.show_shop && rl.IsKeyPressed(.ONE) {
        if game.player.credits >= 100 {
            game.player.credits -= 100
            add_battle_log(&game.battle, "Bought Med Pack!")
            game.player.health = min(game.player.max_health, game.player.health + 50)
        } else {
            add_battle_log(&game.battle, "Not enough credits!")
        }
    }
    
    if game.show_shop && rl.IsKeyPressed(.TWO) {
        if game.player.credits >= 200 {
            game.player.credits -= 200
            add_battle_log(&game.battle, "Bought Shield Booster!")
            game.player.shields.protection += 5
        }
    }
    
    // Handle upgrades
    if game.show_upgrades && rl.IsKeyPressed(.ONE) {
        upgrade_cost := game.player.weapons.level * 150
        if game.player.credits >= upgrade_cost {
            game.player.credits -= upgrade_cost
            game.player.weapons.level += 1
            game.player.weapons.damage += 10
            add_battle_log(&game.battle, fmt.tprintf("Weapon upgraded to level %d!", game.player.weapons.level))
        }
    }
    
    if game.show_upgrades && rl.IsKeyPressed(.TWO) {
        upgrade_cost := game.player.shields.level * 120
        if game.player.credits >= upgrade_cost {
            game.player.credits -= upgrade_cost
            game.player.shields.level += 1
            game.player.shields.protection += 8
            add_battle_log(&game.battle, fmt.tprintf("Shields upgraded to level %d!", game.player.shields.level))
        }
    }
    
    // Save game (Press F5)
    if rl.IsKeyPressed(.F5) {
        save_game(game)
        add_battle_log(&game.battle, "Game Saved!")
    }
}

update_battle :: proc(game: ^Game, dt: f32) {
    #partial switch game.battle.state {
    case .PLAYER_TURN:
        if rl.IsKeyPressed(.SPACE) {
            damage := game.player.weapons.damage + rand.int31_max(11) - 5
            game.battle.enemy_health -= damage
            add_battle_log(&game.battle, fmt.tprintf("You dealt %d damage!", damage))
            
            if game.battle.enemy_health <= 0 {
                game.battle.state = .VICTORY
                add_battle_log(&game.battle, fmt.tprintf("Victory! Earned %d credits!", game.battle.enemy.credits_reward))
                game.player.credits += game.battle.enemy.credits_reward
            } else {
                game.battle.state = .ENEMY_TURN
            }
        }
        
        if rl.IsKeyPressed(.D) {
            add_battle_log(&game.battle, "You defend, reducing damage by 50%")
            game.battle.state = .ENEMY_TURN
        }
        
        if rl.IsKeyPressed(.R) {
            if rand.int31_max(100) < 50 {
                add_battle_log(&game.battle, "You escaped!")
                game.battle.active = false
                game.state = .FLYING
            } else {
                add_battle_log(&game.battle, "Failed to escape!")
                game.battle.state = .ENEMY_TURN
            }
        }
        
    case .ENEMY_TURN:
        damage := game.battle.enemy.damage + rand.int31_max(7) - 3
        damage -= game.player.shields.protection
        if damage < 0 { damage = 0 }
        
        game.battle.player_health -= damage
        add_battle_log(&game.battle, fmt.tprintf("Enemy dealt %d damage!", damage))
        
        if game.battle.player_health <= 0 {
            game.battle.state = .DEFEAT
            add_battle_log(&game.battle, "DEFEAT! Game Over!")
        } else {
            game.battle.state = .PLAYER_TURN
        }
        
    case .VICTORY:
        if rl.IsKeyPressed(.SPACE) {
            game.battle.active = false
            game.state = .FLYING
            game.player.health = game.battle.player_health
        }
        
    case .DEFEAT:
        if rl.IsKeyPressed(.SPACE) {
            game.game_over = true
        }
    }
}

start_battle :: proc(game: ^Game) {
    enemy_index := rand.int31_max(i32(len(enemies)))
    game.battle.enemy = enemies[enemy_index]
    game.battle.active = true
    game.battle.state = .PLAYER_TURN
    game.battle.player_health = game.player.health
    game.battle.enemy_health = game.battle.enemy.health
    game.battle.log_index = 0
    slice.fill(game.battle.battle_log[:], "")
    
    add_battle_log(&game.battle, fmt.tprintf("⚔ Battle started vs %s!", game.battle.enemy.name))
    add_battle_log(&game.battle, "Your turn! [SPACE] Attack, [D] Defend, [R] Run")
    
    game.state = .IN_BATTLE
}

add_battle_log :: proc(battle: ^Battle, message: string) {
    if battle.log_index >= len(battle.battle_log) {
        for i := 1; i < len(battle.battle_log); i += 1 {
            battle.battle_log[i-1] = battle.battle_log[i]
        }
        battle.log_index = len(battle.battle_log) - 1
    }
    battle.battle_log[battle.log_index] = message
    battle.log_index += 1
}

save_game :: proc(game: ^Game) {
    fmt.println("\n=== GAME SAVED ===")
    fmt.println("Player Stats:")
    fmt.printf("  Health: %d/%d\n", game.player.health, game.player.max_health)
    fmt.printf("  Credits: %d\n", game.player.credits)
    fmt.printf("  Weapon Level: %d (Damage: %d)\n", game.player.weapons.level, game.player.weapons.damage)
    fmt.printf("  Shield Level: %d (Protection: %d)\n", game.player.shields.level, game.player.shields.protection)
    fmt.println("=================")
}

// ===================================================================
// Draw
// ===================================================================

draw :: proc(game: ^Game) {
    rl.BeginDrawing()
    rl.ClearBackground(rl.Color{8, 8, 28, 255})

    rl.BeginMode3D(game.camera)

    // Draw Trees
    for tree_pos in game.trees {
        rl.DrawModel(game.tree_model, tree_pos, 1.0, rl.WHITE)
    }

    // Draw House
    rl.DrawModel(game.house_model, game.house_pos, 1.0, rl.WHITE)

    // Draw Player Ship
    if game.state != .IN_BATTLE {
        rl.DrawModelEx(
            game.player.model,
            game.player.position,
            rl.Vector3{0, 1, 0},
            game.player.rotation,
            rl.Vector3{1, 1, 1},
            rl.WHITE,
        )
    }
    
    // Draw enemy ship in battle
    if game.state == .IN_BATTLE && game.battle.state != .DEFEAT {
        enemy_pos := rl.Vector3{0, 0, -30}
        rl.DrawModelEx(
            game.enemy_model,
            enemy_pos,
            rl.Vector3{0, 1, 0},
            180,
            rl.Vector3{1, 1, 1},
            game.battle.enemy.shader_color,
        )
    }

    rl.EndMode3D()

    // UI
    draw_ui(game)
    
    rl.EndDrawing()
}

draw_ui :: proc(game: ^Game) {
    switch game.state {
    case .FLYING:
        rl.DrawText("WASD / Arrow Keys - Move Ship", 15, 15, 20, rl.WHITE)
        rl.DrawText("Fly to House to Upgrade (Press E when near)", 15, 45, 20, rl.YELLOW)
        draw_player_stats(game, 15, 75)
        
        // Show battle cooldown indicator
        cooldown_percent := 1.0 - (game.battle_timer / game.battle_cooldown)
        rl.DrawRectangle(15, 140, i32(200 * cooldown_percent), 10, {255, 0, 0, 100})
        
    case .AT_HOUSE:
        rl.DrawText("=== SPACE STATION HUB ===", 400, 15, 30, rl.GREEN)
        rl.DrawText("Press E to Exit | S:Shop | U:Upgrades | F5:Save", 15, 15, 20, rl.WHITE)
        draw_player_stats(game, 15, 75)
        
        if game.show_shop {
            draw_shop(game)
        }
        if game.show_upgrades {
            draw_upgrades(game)
        }
        
    case .IN_BATTLE:
        draw_battle_ui(game)
    }
    
    if game.game_over {
        draw_game_over()
    }
}

draw_player_stats :: proc(game: ^Game, x: i32, y: i32) {
    rl.DrawText(fmt.ctprintf("❤ Health: %d/%d", game.player.health, game.player.max_health), x, y, 20, rl.RED)
    rl.DrawText(fmt.ctprintf("💰 Credits: %d", game.player.credits), x, y + 25, 20, rl.GOLD)
    rl.DrawText(fmt.ctprintf("⚔ Weapon Lv.%d (Dmg: %d)", game.player.weapons.level, game.player.weapons.damage), x, y + 50, 20, rl.BLUE)
    rl.DrawText(fmt.ctprintf("🛡 Shield Lv.%d (Prot: %d)", game.player.shields.level, game.player.shields.protection), x, y + 75, 20, rl.SKYBLUE)
}

draw_shop :: proc(game: ^Game) {
    rl.DrawRectangle(400, 100, 480, 250, rl.Color{0, 0, 0, 200})
    rl.DrawRectangleLines(400, 100, 480, 250, rl.GOLD)
    
    rl.DrawText("🛒 SHOP", 580, 110, 30, rl.GOLD)
    rl.DrawText("1. Med Pack - 100 credits (Restores 50 HP)", 420, 160, 20, rl.WHITE)
    rl.DrawText("2. Shield Booster - 200 credits (+5 Protection)", 420, 190, 20, rl.WHITE)
    rl.DrawText("Press 1 or 2 to purchase", 420, 230, 20, rl.YELLOW)
    rl.DrawText(fmt.ctprintf("Your Credits: %d", game.player.credits), 420, 270, 20, rl.GOLD)
}

draw_upgrades :: proc(game: ^Game) {
    rl.DrawRectangle(400, 100, 480, 250, rl.Color{0, 0, 0, 200})
    rl.DrawRectangleLines(400, 100, 480, 250, rl.BLUE)
    
    rl.DrawText("🔧 UPGRADES", 560, 110, 30, rl.BLUE)
    weapon_cost := game.player.weapons.level * 150
    shield_cost := game.player.shields.level * 120
    
    rl.DrawText(fmt.ctprintf("1. Weapon Lv.%d → Lv.%d - %d credits (+10 Dmg)", 
        game.player.weapons.level, game.player.weapons.level + 1, weapon_cost), 
        420, 160, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("2. Shield Lv.%d → Lv.%d - %d credits (+8 Prot)", 
        game.player.shields.level, game.player.shields.level + 1, shield_cost), 
        420, 190, 20, rl.WHITE)
    rl.DrawText("Press 1 or 2 to upgrade", 420, 230, 20, rl.YELLOW)
    rl.DrawText(fmt.ctprintf("Your Credits: %d", game.player.credits), 420, 270, 20, rl.GOLD)
}

draw_battle_ui :: proc(game: ^Game) {
    // Dark overlay
    rl.DrawRectangle(0, 0, 1280, 720, rl.Color{0, 0, 0, 180})
    
    // Enemy info
    rl.DrawText(fmt.ctprintf("VS %s", game.battle.enemy.name), 900, 50, 30, game.battle.enemy.shader_color)
    rl.DrawRectangle(850, 90, 300, 30, rl.DARKGRAY)
    enemy_percent := f32(game.battle.enemy_health) / f32(game.battle.enemy.health)
    rl.DrawRectangle(850, 90, i32(f32(300) * enemy_percent), 30, rl.RED)
    rl.DrawText(fmt.ctprintf("❤ %d/%d", game.battle.enemy_health, game.battle.enemy.health), 850, 95, 20, rl.WHITE)
    
    // Player info
    rl.DrawText("YOUR SHIP", 100, 500, 30, rl.GREEN)
    rl.DrawRectangle(100, 540, 300, 30, rl.DARKGRAY)
    player_percent := f32(game.battle.player_health) / f32(game.player.max_health)
    rl.DrawRectangle(100, 540, i32(f32(300) * player_percent), 30, rl.RED)
    rl.DrawText(fmt.ctprintf("❤ %d/%d", game.battle.player_health, game.player.max_health), 100, 545, 20, rl.WHITE)
    
    // Battle log
    rl.DrawRectangle(100, 600, 1080, 100, rl.Color{0, 0, 0, 200})
    rl.DrawRectangleLines(100, 600, 1080, 100, rl.GRAY)
    
    for i := 0; i < len(game.battle.battle_log); i += 1 {
        if game.battle.battle_log[i] != "" {
            text := fmt.ctprintf("%s", game.battle.battle_log[i])
            rl.DrawText(text, 110, 610 + i32(i) * 20, 18, rl.WHITE)
        }
    }
    
    // Battle state prompt
    #partial switch game.battle.state {
    case .PLAYER_TURN:
        rl.DrawText("⚔ YOUR TURN ⚔", 480, 300, 30, rl.GREEN)
        rl.DrawText("[SPACE] Attack  [D] Defend  [R] Run", 400, 350, 20, rl.YELLOW)
    case .ENEMY_TURN:
        rl.DrawText("ENEMY TURN...", 520, 300, 30, rl.RED)
    case .VICTORY:
        rl.DrawText("✨ VICTORY! ✨", 480, 300, 40, rl.GREEN)
        rl.DrawText("Press SPACE to continue", 460, 360, 20, rl.WHITE)
    case .DEFEAT:
        rl.DrawText("💀 DEFEAT! 💀", 480, 300, 40, rl.RED)
        rl.DrawText("Press SPACE to end", 480, 360, 20, rl.WHITE)
    }
}

draw_game_over :: proc() {
    rl.DrawRectangle(0, 0, 1280, 720, rl.Color{0, 0, 0, 200})
    rl.DrawText("GAME OVER", 480, 300, 50, rl.RED)
    rl.DrawText("Press ESC to exit", 520, 400, 20, rl.WHITE)
}

// ===================================================================
// Cleanup
// ===================================================================

unload_game :: proc(game: ^Game) {
    rl.UnloadModel(game.house_model)
    rl.UnloadModel(game.tree_model)
    rl.UnloadModel(game.player.model)
    rl.UnloadModel(game.enemy_model)

    for i := 0; i < len(game.music); i += 1 {
        rl.UnloadMusicStream(game.music[i])
    }

    rl.CloseAudioDevice()
    rl.CloseWindow()
    
    fmt.println("Game cleanup complete!")
}
