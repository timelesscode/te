package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math/rand"
import "core:slice"
import "core:path/filepath"
import "os"
import "strings"
import "core:time"

// ===================================================================
// Constants
// ===================================================================

WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE  :: "StarQuest - Space RPG"

TARGET_FPS :: 60
PLAYER_SPEED :: 15.0
PLAYER_START_HEALTH :: 100
PLAYER_START_CREDITS :: 1000

// World generation
WORLD_SIZE :: 2000
TREE_DENSITY :: 500
ASTEROID_COUNT :: 150
RESOURCE_COUNT :: 75
NPC_COUNT :: 20

// ===================================================================
// Game State Management
// ===================================================================

GamePhase :: enum {
    TITLE,
    DIALOGUE,
    FLYING,
    AT_HOUSE,
    IN_BATTLE,
    MINING,
    SHIP_MENU,
    GAME_OVER,
}

WeaponType :: enum {
    LASER,
    PLASMA,
    RAILGUN,
    MISSILE,
    BEAM,
    SHOTGUN,
}

Weapon :: struct {
    type: WeaponType,
    name: string,
    damage: i32,
    level: i32,
    xp: i32,
    xp_to_next: i32,
    uses: i32,
    accuracy: f32,
    fire_rate: f32,
    color: rl.Color,
}

ResourceType :: enum {
    MINERALS,
    GAS,
    CRYSTALS,
    ARTIFACT,
}

Resource :: struct {
    type: ResourceType,
    position: rl.Vector3,
    value: i32,
    collected: bool,
}

NPC :: struct {
    name: string,
    position: rl.Vector3,
    dialog: [4]string,
    quest_giver: bool,
    quest_complete: bool,
}

PowerUpType :: enum {
    HEALTH,
    DAMAGE,
    SPEED,
    SHIELD,
    CREDITS,
    XP_BOOST,
}

PowerUp :: struct {
    type: PowerUpType,
    position: rl.Vector3,
    value: i32,
    duration: f32,
    active: bool,
}

ShipUpgrade :: struct {
    name: string,
    level: i32,
    cost: i32,
    stat_bonus: i32,
    owned: bool,
}

// ===================================================================
// Main Game Structures
// ===================================================================

Player :: struct {
    model: rl.Model,
    position: rl.Vector3,
    rotation: f32,
    target_rotation: f32,
    speed: f32,
    health: i32,
    max_health: i32,
    shields: i32,
    max_shields: i32,
    credits: i32,
    xp: i32,
    level: i32,
    
    weapons: [6]Weapon,
    active_weapon: int,
    
    power_ups: [dynamic]PowerUp,
    
    // Ship upgrades
    hull_upgrade: ShipUpgrade,
    engine_upgrade: ShipUpgrade,
    scanner_upgrade: ShipUpgrade,
}

Minigame :: struct {
    active: bool,
    charge: f32,
    perfect_zone: f32,
    score: f32,
    last_score: f32,
}

Battle :: struct {
    active: bool,
    state: BattleState,
    enemy_type: EnemyType,
    enemy: EnemyData,
    player_health: i32,
    enemy_health: i32,
    battle_log: [8]string,
    log_index: int,
    minigame: Minigame,
}

EnemyType :: enum {
    SCOUT,
    FIGHTER,
    BOMBER,
    INTERCEPTOR,
    ELITE,
    BOSS,
}

EnemyData :: struct {
    name: string,
    health: i32,
    max_health: i32,
    damage: i32,
    credits_reward: i32,
    xp_reward: i32,
    color: rl.Color,
    is_boss: bool,
}

BattleState :: enum {
    IDLE,
    PLAYER_TURN,
    ENEMY_TURN,
    MINIGAME,
    VICTORY,
    DEFEAT,
}

Dialogue :: struct {
    active: bool,
    speaker: string,
    lines: [dynamic]string,
    current_line: int,
    on_complete: proc(),
}

Game :: struct {
    phase: GamePhase,
    player: Player,
    
    // World objects
    trees: [dynamic]rl.Vector3,
    asteroids: [dynamic]rl.Vector3,
    resources: [dynamic]Resource,
    npcs: [dynamic]NPC,
    powerups: [dynamic]PowerUp,
    
    // Models
    house_model: rl.Model,
    tree_model: rl.Model,
    asteroid_model: rl.Model,
    enemy_model: rl.Model,
    resource_models: [4]rl.Model,
    
    house_pos: rl.Vector3,
    house_collision: rl.BoundingBox,
    
    // Camera
    camera: rl.Camera3D,
    camera_offset: rl.Vector3,
    
    // Music & Audio
    music: [5]rl.Music,
    current_track: int,
    music_enabled: bool,
    
    // Battle system
    battle: Battle,
    battle_timer: f32,
    battle_cooldown: f32,
    
    // UI states
    show_shop: bool,
    show_upgrades: bool,
    show_ship_menu: bool,
    selected_weapon: int,
    
    // Dialogue
    dialogue: Dialogue,
    
    // Quest tracking
    main_quest_progress: int,
    boss_defeated: bool,
    
    // Time system
    game_time: f32,
    day_night: f32,
    
    assets_loaded: bool,
    game_over: bool,
}

// ===================================================================
// Game Data
// ===================================================================

weapon_data := []Weapon{
    {type = .LASER, name = "Laser Cannon", damage = 15, level = 1, xp = 0, xp_to_next = 100, uses = 0, accuracy = 0.95, fire_rate = 1.0, color = {255, 50, 50, 255}},
    {type = .PLASMA, name = "Plasma Thrower", damage = 25, level = 1, xp = 0, xp_to_next = 150, uses = 0, accuracy = 0.85, fire_rate = 0.7, color = {50, 255, 50, 255}},
    {type = .RAILGUN, name = "Railgun", damage = 40, level = 1, xp = 0, xp_to_next = 200, uses = 0, accuracy = 0.90, fire_rate = 0.5, color = {255, 255, 50, 255}},
    {type = .MISSILE, name = "Missile Launcher", damage = 35, level = 1, xp = 0, xp_to_next = 180, uses = 0, accuracy = 0.75, fire_rate = 0.6, color = {255, 150, 50, 255}},
    {type = .BEAM, name = "Beam Laser", damage = 20, level = 1, xp = 0, xp_to_next = 120, uses = 0, accuracy = 1.00, fire_rate = 1.2, color = {50, 255, 255, 255}},
    {type = .SHOTGUN, name = "Scatter Cannon", damage = 30, level = 1, xp = 0, xp_to_next = 160, uses = 0, accuracy = 0.70, fire_rate = 0.8, color = {255, 100, 255, 255}},
}

enemies := []EnemyData{
    {name = "Scout", health = 30, max_health = 30, damage = 8, credits_reward = 50, xp_reward = 20, color = {255, 100, 100, 255}, is_boss = false},
    {name = "Fighter", health = 50, max_health = 50, damage = 12, credits_reward = 100, xp_reward = 40, color = {255, 50, 50, 255}, is_boss = false},
    {name = "Bomber", health = 80, max_health = 80, damage = 20, credits_reward = 150, xp_reward = 60, color = {200, 50, 50, 255}, is_boss = false},
    {name = "Interceptor", health = 40, max_health = 40, damage = 15, credits_reward = 75, xp_reward = 30, color = {255, 150, 150, 255}, is_boss = false},
    {name = "Elite", health = 120, max_health = 120, damage = 25, credits_reward = 300, xp_reward = 100, color = {255, 200, 50, 255}, is_boss = false},
    {name = "Void Reaver", health = 500, max_health = 500, damage = 40, credits_reward = 2000, xp_reward = 500, color = {150, 50, 150, 255}, is_boss = true},
}

resource_data := []struct{ name: string, base_value: i32, color: rl.Color }{
    {name = "Minerals", base_value = 50, color = {139, 69, 19, 255}},
    {name = "Gas Cloud", base_value = 75, color = {0, 255, 255, 100}},
    {name = "Crystals", base_value = 100, color = {255, 0, 255, 255}},
    {name = "Ancient Artifact", base_value = 500, color = {255, 215, 0, 255}},
}

npc_data := []struct{ name, dialog1, dialog2, dialog3, dialog4 string; is_quest_giver bool }{
    {"Captain Reynolds", "Welcome to Starbase Alpha!", "I need help with some pirates.", "They've been raiding our supply lines.", "Can you assist us?", true},
    {"Engineer T'Vell", "Your ship needs tuning?", "I can upgrade your weapons.", "Bring me rare crystals.", "They improve performance greatly.", false},
    {"Miner Joe", "The asteroid belt is rich!", "I've found valuable minerals there.", "Watch out for space creatures though.", "Good luck out there!", false},
    {"Mystic Oracle", "I sense a great evil approaching.", "The Void Reaver threatens us all.", "You must become stronger.", "Defeat it to save the sector!", true},
}

// ===================================================================
// Main Entry Point
// ===================================================================

main :: proc() {
    game: Game
    if !init_game(&game) {
        fmt.eprintln("Failed to initialize game!")
        return
    }
    defer unload_game(&game)
    
    rl.SetTargetFPS(TARGET_FPS)
    rl.SetTraceLogLevel(.WARNING)
    
    for !rl.WindowShouldClose() && !game.game_over {
        update(&game)
        draw(&game)
    }
}

// ===================================================================
// Initialization
// ===================================================================

init_game :: proc(game: ^Game) -> bool {
    // Initialize window
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
    if !rl.IsWindowReady() { return false }
    
    // Initialize audio
    rl.InitAudioDevice()
    game.music_enabled = rl.IsAudioDeviceReady()
    
    // Initialize player
    game.phase = .TITLE
    game.player = Player{
        position = {0, 0, 0},
        speed = PLAYER_SPEED,
        health = PLAYER_START_HEALTH,
        max_health = PLAYER_START_HEALTH,
        shields = 50,
        max_shields = 50,
        credits = PLAYER_START_CREDITS,
        xp = 0,
        level = 1,
        active_weapon = 0,
        hull_upgrade = {name = "Hull", level = 1, cost = 500, stat_bonus = 0, owned = true},
        engine_upgrade = {name = "Engine", level = 1, cost = 500, stat_bonus = 0, owned = true},
        scanner_upgrade = {name = "Scanner", level = 1, cost = 500, stat_bonus = 0, owned = true},
    }
    
    // Initialize weapons
    for i in 0..<6 {
        game.player.weapons[i] = weapon_data[i]
    }
    
    // World setup
    game.house_pos = {0, 0, -1500}
    game.house_collision = rl.BoundingBox{min = {-30, -10, -1525}, max = {30, 20, -1475}}
    
    game.camera = rl.Camera3D{
        position = {0, 30, 50},
        target = {0, 0, 0},
        up = {0, 1, 0},
        fovy = 45,
        projection = .PERSPECTIVE,
    }
    
    // Load assets
    load_assets(game)
    
    // Generate world
    generate_world(game)
    
    // Start title music
    if game.music_enabled {
        rl.PlayMusicStream(game.music[0])
    }
    
    game.assets_loaded = true
    return true
}

load_assets :: proc(game: ^Game) {
    paths := get_asset_paths()
    
    // Load models (with fallbacks)
    game.house_model = rl.LoadModel("art/house1.glb")
    game.tree_model = rl.LoadModel("art/tree1.glb")
    game.asteroid_model = rl.LoadModel("art/asteroid.glb")
    game.enemy_model = rl.LoadModel("art/ship2.glb")
    game.player.model = rl.LoadModel("art/ship2.glb")
    
    // Load music
    if game.music_enabled {
        music_paths := []string{"sounds/title.wav", "sounds/explore.wav", "sounds/battle.wav", "sounds/house.wav", "sounds/boss.wav"}
        for i, path in music_paths {
            game.music[i] = rl.LoadMusicStream(strings.clone_to_cstring(path))
        }
    }
}

get_asset_paths :: proc() -> struct{ models: struct{ house, tree, asteroid, ship: string }, music: [5]string } {
    // Simplified path handling
    return {models = {house = "art/house1.glb", tree = "art/tree1.glb", asteroid = "art/asteroid.glb", ship = "art/ship2.glb"},
            music = {"sounds/title.wav", "sounds/explore.wav", "sounds/battle.wav", "sounds/house.wav", "sounds/boss.wav"}}
}

generate_world :: proc(game: ^Game) {
    // Generate trees in a winding path
    for i := 0; i < TREE_DENSITY; i += 1 {
        t := f32(i) / f32(TREE_DENSITY)
        angle := t * 2 * math.PI * 3
        radius := 200.0 + t * 300
        x := math.cos(angle) * radius
        z := -t * WORLD_SIZE
        
        // Add random offset
        x += f32(rand.int31_max(60) - 30)
        z += f32(rand.int31_max(40) - 20)
        
        append(&game.trees, rl.Vector3{x, 0, z})
    }
    
    // Generate asteroids
    for i := 0; i < ASTEROID_COUNT; i += 1 {
        x := f32(rand.int31_max(WORLD_SIZE) - WORLD_SIZE/2)
        z := f32(rand.int31_max(WORLD_SIZE) - WORLD_SIZE/2)
        append(&game.asteroids, rl.Vector3{x, f32(rand.int31_max(20) - 10), z})
    }
    
    // Generate resources
    for i := 0; i < RESOURCE_COUNT; i += 1 {
        res_type := ResourceType(rand.int31_max(4))
        x := f32(rand.int31_max(WORLD_SIZE) - WORLD_SIZE/2)
        z := f32(rand.int31_max(WORLD_SIZE) - WORLD_SIZE/2)
        value := resource_data[res_type].base_value + rand.int31_max(50)
        append(&game.resources, Resource{type = res_type, position = {x, 1, z}, value = value, collected = false})
    }
    
    // Generate NPCs
    for i := 0; i < NPC_COUNT; i += 1 {
        npc := npc_data[rand.int31_max(len(npc_data))]
        x := f32(rand.int31_max(800) - 400)
        z := f32(rand.int31_max(WORLD_SIZE) - WORLD_SIZE/2)
        dialog_lines := [4]string{npc.dialog1, npc.dialog2, npc.dialog3, npc.dialog4}
        append(&game.npcs, NPC{name = npc.name, position = {x, 0, z}, dialog = dialog_lines, quest_giver = npc.is_quest_giver, quest_complete = false})
    }
}

// ===================================================================
// Update Logic
// ===================================================================

update :: proc(game: ^Game) {
    dt := rl.GetFrameTime()
    game.game_time += dt
    game.day_night = math.sin(game.game_time * 0.05)
    
    // Update music
    if game.music_enabled {
        rl.UpdateMusicStream(game.music[game.current_track])
        if !rl.IsMusicStreamPlaying(game.music[game.current_track]) {
            next_track(game)
        }
    }
    
    if game.game_over {
        if rl.IsKeyPressed(.ENTER) {
            reset_game(game)
        }
        return
    }
    
    #partial switch game.phase {
    case .TITLE:
        update_title(game)
    case .DIALOGUE:
        update_dialogue(game)
    case .FLYING:
        update_flying(game, dt)
    case .AT_HOUSE:
        update_house(game, dt)
    case .IN_BATTLE:
        update_battle(game, dt)
    case .MINING:
        update_mining(game)
    case .SHIP_MENU:
        update_ship_menu(game)
    }
}

update_title :: proc(game: ^Game) {
    if rl.IsKeyPressed(.ENTER) {
        game.phase = .DIALOGUE
        start_dialogue(game, "Captain Reynolds", &game.dialogue, proc() {
            game.phase = .FLYING
            game.current_track = 1
            if game.music_enabled { rl.PlayMusicStream(game.music[1]) }
        })
    }
}

update_flying :: proc(game: ^Game, dt: f32) {
    // 8-directional movement with smooth rotation
    move_dir := rl.Vector3{}
    
    if rl.IsKeyDown(.W) { move_dir.z -= 1 }
    if rl.IsKeyDown(.S) { move_dir.z += 1 }
    if rl.IsKeyDown(.A) { move_dir.x -= 1 }
    if rl.IsKeyDown(.D) { move_dir.x += 1 }
    
    if rl.Vector3Length(move_dir) > 0.01 {
        move_dir = rl.Vector3Normalize(move_dir)
        game.player.position += move_dir * game.player.speed * dt
        
        // Calculate rotation angle
        angle := math.atan2(move_dir.x, move_dir.z) * 180 / math.PI
        game.player.target_rotation = angle
        game.player.rotation += (game.player.target_rotation - game.player.rotation) * 0.2
    }
    
    // Boundary limits
    game.player.position.x = clamp(game.player.position.x, -WORLD_SIZE/2, WORLD_SIZE/2)
    game.player.position.z = clamp(game.player.position.z, -WORLD_SIZE, WORLD_SIZE/4)
    
    // Check house collision
    player_bounds := rl.BoundingBox{min = game.player.position - {5, 2, 5}, max = game.player.position + {5, 5, 5}}
    if rl.CheckCollisionBoxes(player_bounds, game.house_collision) {
        game.phase = .AT_HOUSE
        game.current_track = 3
        if game.music_enabled { rl.PlayMusicStream(game.music[3]) }
        return
    }
    
    // Check NPC collisions
    for i := 0; i < len(game.npcs); i += 1 {
        npc := &game.npcs[i]
        dist := rl.Vector3Distance(game.player.position, npc.position)
        if dist < 10.0 {
            start_dialogue(game, npc.name, &game.dialogue, nil)
            game.phase = .DIALOGUE
            return
        }
    }
    
    // Check resource collisions
    for i := 0; i < len(game.resources); i += 1 {
        res := &game.resources[i]
        if !res.collected && rl.Vector3Distance(game.player.position, res.position) < 8.0 {
            game.player.credits += res.value
            res.collected = true
            add_floating_text(fmt.tprintf("+%d %s", res.value, resource_data[res.type].name), res.position)
            
            // Chance to spawn powerup
            if rand.int31_max(100) < 20 {
                spawn_powerup(game, res.position)
            }
        }
    }
    
    // Check powerup collisions
    for i := 0; i < len(game.powerups); i += 1 {
        p := &game.powerups[i]
        if p.active && rl.Vector3Distance(game.player.position, p.position) < 6.0 {
            apply_powerup(game, p)
            p.active = false
        }
    }
    
    // Random battle encounters
    game.battle_timer += dt
    if game.battle_timer >= game.battle_cooldown {
        encounter_chance := 15 + (game.boss_defeated ? 5 : 0)
        if rand.int31_max(100) < encounter_chance {
            start_battle(game)
        }
        game.battle_timer = 0
        game.battle_cooldown = f32(rand.int31_range(30, 90)) / 10.0
    }
    
    // Camera follow with smooth lag
    target_cam_pos := game.player.position + rl.Vector3{0, 25, 45}
    game.camera.position = rl.Vector3Lerp(game.camera.position, target_cam_pos, 0.1)
    game.camera.target = game.player.position
    
    // Day/night lighting
    bg_color := rl.Color{uint8(8 + game.day_night * 20), uint8(8 + game.day_night * 10), uint8(28 + game.day_night * 30), 255}
    rl.ClearBackground(bg_color)
}

update_house :: proc(game: ^Game, dt: f32) {
    if rl.IsKeyPressed(.E) {
        game.phase = .FLYING
        game.current_track = 1
        if game.music_enabled { rl.PlayMusicStream(game.music[1]) }
        game.player.position = {0, 0, -1200}
    }
    
    if rl.IsKeyPressed(.S) { game.show_shop = !game.show_shop; game.show_upgrades = false }
    if rl.IsKeyPressed(.U) { game.show_upgrades = !game.show_upgrades; game.show_shop = false }
    if rl.IsKeyPressed(.M) { game.show_ship_menu = !game.show_ship_menu }
    
    // Shop system
    if game.show_shop {
        if rl.IsKeyPressed(.ONE) && game.player.credits >= 100 {
            game.player.credits -= 100
            game.player.health = min(game.player.max_health, game.player.health + 50)
        }
        if rl.IsKeyPressed(.TWO) && game.player.credits >= 300 {
            game.player.credits -= 300
            game.player.shields = min(game.player.max_shields, game.player.shields + 75)
        }
        if rl.IsKeyPressed(.THREE) && game.player.credits >= 500 {
            game.player.credits -= 500
            game.player.max_shields += 25
            game.player.shields = game.player.max_shields
        }
    }
    
    // Upgrade system
    if game.show_upgrades {
        if rl.IsKeyPressed(.ONE) {
            cost := game.player.weapons[game.player.active_weapon].level * 200
            if game.player.credits >= cost {
                game.player.credits -= cost
                upgrade_weapon(&game.player.weapons[game.player.active_weapon])
            }
        }
        if rl.IsKeyPressed(.TWO) && game.player.credits >= 300 {
            game.player.credits -= 300
            game.player.max_health += 25
            game.player.health = game.player.max_health
        }
    }
    
    if rl.IsKeyPressed(.F5) { save_game(game) }
}

update_battle :: proc(game: ^Game, dt: f32) {
    #partial switch game.battle.state {
    case .PLAYER_TURN:
        if rl.IsKeyPressed(.SPACE) {
            game.battle.state = .MINIGAME
            game.battle.minigame.active = true
            game.battle.minigame.charge = 0
            game.battle.minigame.perfect_zone = f32(rand.int31_range(40, 60)) / 100.0
        }
        if rl.IsKeyPressed(.D) {
            damage_reduction := 50
            add_battle_log(game, fmt.tprintf("You defend, reducing damage by %d%%", damage_reduction))
            game.battle.state = .ENEMY_TURN
        }
        if rl.IsKeyPressed(.R) {
            if rand.int31_max(100) < 40 {
                add_battle_log(game, "You escaped!")
                exit_battle(game)
            } else {
                add_battle_log(game, "Failed to escape!")
                game.battle.state = .ENEMY_TURN
            }
        }
        if rl.IsKeyPressed(.Q) {
            cycle_weapon(game, -1)
        }
        if rl.IsKeyPressed(.E) {
            cycle_weapon(game, 1)
        }
        
    case .MINIGAME:
        update_minigame(game, dt)
        
    case .ENEMY_TURN:
        damage := game.battle.enemy.damage + rand.int31_range(-5, 10)
        damage -= game.player.shields / 10
        if damage < 1 { damage = 1 }
        
        game.battle.player_health -= damage
        add_battle_log(game, fmt.tprintf("%s dealt %d damage!", game.battle.enemy.name, damage))
        
        if game.battle.player_health <= 0 {
            game.battle.state = .DEFEAT
            add_battle_log(game, "DEFEAT! Game Over!")
        } else {
            game.battle.state = .PLAYER_TURN
        }
        
    case .VICTORY:
        if rl.IsKeyPressed(.SPACE) {
            reward_xp := game.battle.enemy.xp_reward
            add_xp(game, reward_xp)
            game.player.credits += game.battle.enemy.credits_reward
            game.player.health = game.battle.player_health
            
            // Boss defeated check
            if game.battle.enemy.is_boss {
                game.boss_defeated = true
                add_battle_log(game, "You defeated the Void Reaver! The sector is saved!")
            }
            
            exit_battle(game)
        }
        
    case .DEFEAT:
        if rl.IsKeyPressed(.SPACE) {
            game.game_over = true
        }
    }
}

update_minigame :: proc(game: ^Game, dt: f32) {
    game.battle.minigame.charge += dt * 3.0
    if game.battle.minigame.charge > 1.0 {
        game.battle.minigame.charge = 0
    }
    
    // Draw power meter
    meter_width := 400
    meter_x := WINDOW_WIDTH/2 - meter_width/2
    meter_y := WINDOW_HEIGHT/2 - 50
    
    charge_pos := meter_x + i32(f32(meter_width) * game.battle.minigame.charge)
    perfect_pos := meter_x + i32(f32(meter_width) * game.battle.minigame.perfect_zone)
    
    if rl.IsKeyPressed(.SPACE) {
        damage_multiplier := 1.0 - abs(game.battle.minigame.charge - game.battle.minigame.perfect_zone) * 2
        if damage_multiplier < 0.2 { damage_multiplier = 0.2 }
        
        base_damage := game.player.weapons[game.player.active_weapon].damage
        damage := i32(f32(base_damage) * damage_multiplier) + rand.int31_range(-5, 10)
        if damage < 1 { damage = 1 }
        
        game.battle.enemy_health -= damage
        add_battle_log(game, fmt.tprintf("%s dealt %d damage! (%.0f%% power)", 
            game.player.weapons[game.player.active_weapon].name, damage, damage_multiplier * 100))
        
        // Weapon XP gain
        weapon := &game.player.weapons[game.player.active_weapon]
        weapon.xp += i32(damage_multiplier * 100)
        weapon.uses += 1
        
        if weapon.xp >= weapon.xp_to_next {
            weapon.level += 1
            weapon.damage += 5
            weapon.xp -= weapon.xp_to_next
            weapon.xp_to_next += 50
            add_battle_log(game, fmt.tprintf("%s upgraded to level %d!", weapon.name, weapon.level))
        }
        
        game.battle.minigame.active = false
        
        if game.battle.enemy_health <= 0 {
            game.battle.state = .VICTORY
        } else {
            game.battle.state = .ENEMY_TURN
        }
    }
}

update_mining :: proc(game: ^Game) {
    // Simple mining minigame - press space to mine
    if rl.IsKeyPressed(.SPACE) {
        if len(game.resources) > 0 {
            res := &game.resources[0]
            if !res.collected {
                value := res.value + rand.int31_range(-20, 50)
                if value < 0 { value = 10 }
                game.player.credits += value
                res.collected = true
                add_floating_text(fmt.tprintf("Mined %d credits!", value), game.player.position)
                
                if rand.int31_max(100) < 15 {
                    spawn_powerup(game, game.player.position)
                }
            }
        }
    }
    
    if rl.IsKeyPressed(.ESCAPE) {
        game.phase = .FLYING
    }
}

update_ship_menu :: proc(game: ^Game) {
    if rl.IsKeyPressed(.ESCAPE) {
        game.show_ship_menu = false
        game.phase = .AT_HOUSE
    }
    
    // Weapon selection with number keys
    for i := 0; i < 6; i += 1 {
        key := rl.KeyboardKey(i32(rl.KEY_ONE) + i32(i))
        if rl.IsKeyPressed(key) {
            game.selected_weapon = i
            game.player.active_weapon = i
        }
    }
}

// ===================================================================
// Drawing
// ===================================================================

draw :: proc(game: ^Game) {
    rl.BeginDrawing()
    
    #partial switch game.phase {
    case .TITLE:
        draw_title(game)
    case .DIALOGUE:
        draw_flying_dialogue(game)
    case .FLYING, .AT_HOUSE, .MINING:
        draw_3d_world(game)
        draw_ui(game)
    case .IN_BATTLE:
        draw_battle(game)
    case .SHIP_MENU:
        draw_ship_menu(game)
    }
    
    rl.EndDrawing()
}

draw_title :: proc(game: ^Game) {
    rl.ClearBackground({0, 0, 0, 255})
    
    title_text := "STARQUEST"
    title_width := rl.MeasureText(title_text, 80)
    rl.DrawText(title_text, WINDOW_WIDTH/2 - title_width/2, 200, 80, rl.GOLD)
    
    subtitle := "A Space RPG Adventure"
    sub_width := rl.MeasureText(subtitle, 30)
    rl.DrawText(subtitle, WINDOW_WIDTH/2 - sub_width/2, 290, 30, rl.CYAN)
    
    rl.DrawText("Press ENTER to begin", WINDOW_WIDTH/2 - 100, 400, 20, rl.WHITE)
    rl.DrawText("WASD - Move | E - Interact | SPACE - Attack", WINDOW_WIDTH/2 - 200, 500, 16, rl.GRAY)
    rl.DrawText("S - Shop | U - Upgrades | M - Ship Menu | F5 - Save", WINDOW_WIDTH/2 - 200, 530, 16, rl.GRAY)
}

draw_3d_world :: proc(game: ^Game) {
    rl.BeginMode3D(game.camera)
    
    // Draw trees
    for tree_pos in game.trees {
        if game.tree_model != 0 {
            rl.DrawModel(game.tree_model, tree_pos, 1.0, rl.WHITE)
        } else {
            rl.DrawCube(tree_pos, 2, 5, 2, {101, 67, 33, 255})
            rl.DrawCube(tree_pos + {0, 2.5, 0}, 1.5, 4, 1.5, {34, 139, 34, 255})
        }
    }
    
    // Draw asteroids
    for ast_pos in game.asteroids {
        if game.asteroid_model != 0 {
            rl.DrawModel(game.asteroid_model, ast_pos, 1.0, rl.GRAY)
        } else {
            rl.DrawSphere(ast_pos, 2, rl.GRAY)
        }
    }
    
    // Draw resources
    for res in game.resources {
        if !res.collected {
            color := resource_data[res.type].color
            rl.DrawCube(res.position, 1.5, 1.5, 1.5, color)
            rl.DrawCubeWires(res.position, 1.5, 1.5, 1.5, rl.WHITE)
        }
    }
    
    // Draw NPCs
    for npc in game.npcs {
        rl.DrawCube(npc.position, 1, 2, 1, {100, 100, 200, 255})
        rl.DrawCubeWires(npc.position, 1, 2, 1, rl.WHITE)
        // Draw name tag
        rl.DrawBillboard(game.camera, get_texture("npc_tag"), npc.position + {0, 2, 0}, 2, rl.WHITE)
    }
    
    // Draw powerups
    for p in game.powerups {
        if p.active {
            color := get_powerup_color(p.type)
            rl.DrawCube(p.position, 1, 1, 1, color)
            rl.DrawCubeWires(p.position, 1.1, 1.1, 1.1, rl.WHITE)
        }
    }
    
    // Draw house
    if game.house_model != 0 {
        rl.DrawModel(game.house_model, game.house_pos, 1.0, rl.WHITE)
    } else {
        rl.DrawCube(game.house_pos, 25, 20, 25, {128, 128, 128, 255})
        rl.DrawCube(game.house_pos + {0, 10, 0}, 20, 10, 20, {139, 69, 19, 255})
    }
    
    // Draw player ship
    if game.player.model != 0 {
        rl.DrawModelEx(game.player.model, game.player.position, {0, 1, 0}, 
                      game.player.rotation, {1, 1, 1}, rl.WHITE)
    } else {
        rl.DrawCube(game.player.position, 3, 1, 5, {0, 100, 255, 255})
    }
    
    // Draw engine trail
    trail_pos := game.player.position - rl.Vector3RotateByQuaternion({2, 0, 0}, rl.QuaternionFromEuler(0, game.player.rotation * math.PI / 180, 0))
    rl.DrawSphere(trail_pos, 0.5, {255, 100, 50, 200})
    
    rl.EndMode3D()
}

draw_battle :: proc(game: ^Game) {
    rl.ClearBackground({0, 0, 0, 255})
    
    rl.BeginMode3D(game.camera)
    
    // Draw enemy ship
    enemy_pos := rl.Vector3{0, 0, -40}
    if game.enemy_model != 0 {
        rl.DrawModelEx(game.enemy_model, enemy_pos, {0, 1, 0}, 180, {1, 1, 1}, game.battle.enemy.color)
    } else {
        rl.DrawCube(enemy_pos, 4, 2, 6, game.battle.enemy.color)
    }
    
    // Draw player ship
    player_pos := rl.Vector3{0, 0, 40}
    if game.player.model != 0 {
        rl.DrawModelEx(game.player.model, player_pos, {0, 1, 0}, 0, {1, 1, 1}, rl.WHITE)
    } else {
        rl.DrawCube(player_pos, 3, 1, 5, {0, 100, 255, 255})
    }
    
    rl.EndMode3D()
    
    // Draw UI
    rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {0, 0, 0, 150})
    
    // Enemy info
    rl.DrawText(game.battle.enemy.name, 900, 50, 40, game.battle.enemy.color)
    draw_health_bar(850, 100, 300, 30, f32(game.battle.enemy_health) / f32(game.battle.enemy.max_health))
    rl.DrawText(fmt.ctprintf("HP: %d/%d", game.battle.enemy_health, game.battle.enemy.max_health), 850, 105, 20, rl.WHITE)
    
    // Player info
    rl.DrawText("YOUR SHIP", 100, 500, 30, rl.GREEN)
    draw_health_bar(100, 540, 300, 30, f32(game.battle.player_health) / f32(game.player.max_health))
    rl.DrawText(fmt.ctprintf("HP: %d/%d", game.battle.player_health, game.player.max_health), 100, 545, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("Shields: %d/%d", game.player.shields, game.player.max_shields), 100, 575, 20, rl.CYAN)
    
    // Weapon info
    weapon := game.player.weapons[game.player.active_weapon]
    rl.DrawText(fmt.ctprintf("Active: %s Lv.%d (Dmg: %d)", weapon.name, weapon.level, weapon.damage), 500, 20, 20, weapon.color)
    rl.DrawText("Press Q/E to switch weapons", 500, 50, 16, rl.YELLOW)
    
    // Battle log
    rl.DrawRectangle(100, 620, 1080, 90, {0, 0, 0, 200})
    for i := 0; i < len(game.battle.battle_log); i += 1 {
        if game.battle.battle_log[i] != "" {
            rl.DrawText(game.battle.battle_log[i], 110, 628 + i32(i) * 18, 16, rl.WHITE)
        }
    }
    
    // Minigame display
    if game.battle.state == .MINIGAME {
        draw_minigame(game)
    }
    
    // Battle state text
    #partial switch game.battle.state {
    case .PLAYER_TURN:
        rl.DrawText("YOUR TURN", WINDOW_WIDTH/2 - 100, 200, 40, rl.GREEN)
        rl.DrawText("[SPACE] Attack  [D] Defend  [R] Run", WINDOW_WIDTH/2 - 200, 260, 20, rl.YELLOW)
    case .ENEMY_TURN:
        rl.DrawText("ENEMY TURN...", WINDOW_WIDTH/2 - 100, 200, 40, rl.RED)
    case .VICTORY:
        rl.DrawText("VICTORY!", WINDOW_WIDTH/2 - 80, 200, 50, rl.GREEN)
        rl.DrawText(fmt.ctprintf("Earned %d XP and %d credits", game.battle.enemy.xp_reward, game.battle.enemy.credits_reward), 
                   WINDOW_WIDTH/2 - 200, 270, 20, rl.YELLOW)
        rl.DrawText("Press SPACE to continue", WINDOW_WIDTH/2 - 100, 340, 20, rl.WHITE)
    case .DEFEAT:
        rl.DrawText("DEFEAT!", WINDOW_WIDTH/2 - 70, 200, 50, rl.RED)
        rl.DrawText("Press SPACE to continue", WINDOW_WIDTH/2 - 100, 340, 20, rl.WHITE)
    }
}

draw_minigame :: proc(game: ^Game) {
    meter_width := 500
    meter_x := WINDOW_WIDTH/2 - meter_width/2
    meter_y := WINDOW_HEIGHT/2 - 30
    
    rl.DrawRectangle(meter_x, meter_y, meter_width, 40, rl.DARKGRAY)
    
    // Perfect zone
    perfect_start := meter_x + i32(f32(meter_width) * (game.battle.minigame.perfect_zone - 0.1))
    perfect_end := meter_x + i32(f32(meter_width) * (game.battle.minigame.perfect_zone + 0.1))
    rl.DrawRectangle(perfect_start, meter_y, perfect_end - perfect_start, 40, rl.GREEN)
    
    // Charging bar
    charge_pos := meter_x + i32(f32(meter_width) * game.battle.minigame.charge)
    rl.DrawRectangle(charge_pos - 5, meter_y, 10, 40, rl.YELLOW)
    
    rl.DrawText("TIMING MINIGAME - Press SPACE at the green zone!", WINDOW_WIDTH/2 - 200, meter_y - 30, 20, rl.YELLOW)
    rl.DrawText(fmt.ctprintf("Perfect Zone: %.0f%%", game.battle.minigame.perfect_zone * 100), 
               WINDOW_WIDTH/2 + meter_width/2 - 100, meter_y - 30, 16, rl.WHITE)
}

draw_ui :: proc(game: ^Game) {
    #partial switch game.phase {
    case .FLYING:
        draw_minimap(game)
        draw_player_stats(game, 15, 15)
        
        // Quest tracking
        rl.DrawText("MAIN QUEST: Defeat the Void Reaver", WINDOW_WIDTH - 350, 15, 16, game.boss_defeated ? {0, 255, 0, 255} : {255, 255, 0, 255})
        if !game.boss_defeated {
            rl.DrawText("Find allies and gather power!", WINDOW_WIDTH - 350, 40, 14, rl.GRAY)
        }
        
        // NPC indicator
        if rl.Vector3LengthSqr(game.player.position) > 0 {
            nearest_npc_dist := f32(INF)
            for npc in game.npcs {
                dist := rl.Vector3Distance(game.player.position, npc.position)
                if dist < 50 && dist < nearest_npc_dist {
                    nearest_npc_dist = dist
                }
            }
            if nearest_npc_dist < 20 {
                rl.DrawText("NPC nearby! Fly closer to interact", WINDOW_WIDTH/2 - 150, 50, 16, rl.YELLOW)
            }
        }
        
    case .AT_HOUSE:
        draw_player_stats(game, 15, 15)
        rl.DrawText("SPACE STATION HUB", WINDOW_WIDTH/2 - 150, 15, 30, rl.GREEN)
        rl.DrawText("E - Exit | S - Shop | U - Upgrades | M - Ship Menu | F5 - Save", 15, 50, 16, rl.WHITE)
        
        if game.show_shop { draw_shop(game) }
        if game.show_upgrades { draw_upgrades(game) }
        
    case .MINING:
        rl.DrawText("MINING MODE", WINDOW_WIDTH/2 - 100, 15, 30, rl.YELLOW)
        rl.DrawText("Press SPACE to mine | ESC to exit", WINDOW_WIDTH/2 - 150, 50, 20, rl.WHITE)
        rl.DrawText(fmt.ctprintf("Resources remaining: %d", count_remaining_resources(game)), 15, 15, 20, rl.CYAN)
    }
}

draw_minimap :: proc(game: ^Game) {
    minimap_size := 200
    minimap_x := WINDOW_WIDTH - minimap_size - 10
    minimap_y := 10
    
    rl.DrawRectangle(minimap_x, minimap_y, minimap_size, minimap_size, {0, 0, 0, 150})
    rl.DrawRectangleLines(minimap_x, minimap_y, minimap_size, minimap_size, rl.WHITE)
    
    // Scale world coordinates to minimap
    scale := f32(minimap_size) / WORLD_SIZE
    
    // Draw resources
    for res in game.resources {
        if !res.collected {
            map_x := minimap_x + i32((res.position.x + WORLD_SIZE/2) * scale)
            map_y := minimap_y + i32((res.position.z + WORLD_SIZE/2) * scale)
            rl.DrawCircle(map_x, map_y, 2, resource_data[res.type].color)
        }
    }
    
    // Draw NPCs
    for npc in game.npcs {
        map_x := minimap_x + i32((npc.position.x + WORLD_SIZE/2) * scale)
        map_y := minimap_y + i32((npc.position.z + WORLD_SIZE/2) * scale)
        rl.DrawCircle(map_x, map_y, 2, rl.BLUE)
    }
    
    // Draw player
    player_x := minimap_x + i32((game.player.position.x + WORLD_SIZE/2) * scale)
    player_y := minimap_y + i32((game.player.position.z + WORLD_SIZE/2) * scale)
    rl.DrawCircle(player_x, player_y, 4, rl.GREEN)
    
    // Draw house
    house_x := minimap_x + i32((game.house_pos.x + WORLD_SIZE/2) * scale)
    house_y := minimap_y + i32((game.house_pos.z + WORLD_SIZE/2) * scale)
    rl.DrawCircle(house_x, house_y, 3, rl.GRAY)
}

draw_player_stats :: proc(game: ^Game, x: i32, y: i32) {
    rl.DrawText(fmt.ctprintf("❤ %d/%d", game.player.health, game.player.max_health), x, y, 20, rl.RED)
    draw_health_bar(x + 100, y + 4, 150, 16, f32(game.player.health) / f32(game.player.max_health))
    
    rl.DrawText(fmt.ctprintf("🛡 %d/%d", game.player.shields, game.player.max_shields), x, y + 25, 20, rl.CYAN)
    draw_health_bar(x + 100, y + 29, 150, 16, f32(game.player.shields) / f32(game.player.max_shields))
    
    rl.DrawText(fmt.ctprintf("💰 %d", game.player.credits), x, y + 50, 20, rl.GOLD)
    rl.DrawText(fmt.ctprintf("⭐ Lv.%d (%d XP)", game.player.level, game.player.xp), x, y + 75, 20, rl.PURPLE)
    
    weapon := game.player.weapons[game.player.active_weapon]
    rl.DrawText(fmt.ctprintf("🔫 %s Lv.%d (Dmg: %d)", weapon.name, weapon.level, weapon.damage), x, y + 100, 20, weapon.color)
}

draw_health_bar :: proc(x, y, width, height: i32, percent: f32) {
    rl.DrawRectangle(x, y, width, height, rl.DARKGRAY)
    rl.DrawRectangle(x, y, i32(f32(width) * percent), height, rl.RED)
}

draw_shop :: proc(game: ^Game) {
    rl.DrawRectangle(300, 100, 680, 400, {0, 0, 0, 230})
    rl.DrawRectangleLines(300, 100, 680, 400, rl.GOLD)
    
    rl.DrawText("🛒 SHOP", WINDOW_WIDTH/2 - 50, 120, 30, rl.GOLD)
    
    items := []struct{ key: string; cost: i32; desc: string }{
        {"1", 100, "Med Pack - Restores 50 HP"},
        {"2", 300, "Shield Restore - Restores 75 Shields"},
        {"3", 500, "Shield Upgrade - +25 Max Shields"},
    }
    
    for i, item in items {
        y := 180 + i32(i) * 60
        rl.DrawText(fmt.ctprintf("%s. %s (%d credits)", item.key, item.desc, item.cost), 330, y, 20, rl.WHITE)
    }
    
    rl.DrawText(fmt.ctprintf("Your Credits: %d", game.player.credits), 330, 420, 20, rl.GOLD)
    rl.DrawText("Press number key to purchase", 330, 460, 16, rl.YELLOW)
}

draw_upgrades :: proc(game: ^Game) {
    rl.DrawRectangle(300, 100, 680, 400, {0, 0, 0, 230})
    rl.DrawRectangleLines(300, 100, 680, 400, rl.BLUE)
    
    rl.DrawText("🔧 UPGRADES", WINDOW_WIDTH/2 - 60, 120, 30, rl.BLUE)
    
    weapon := &game.player.weapons[game.player.active_weapon]
    weapon_cost := weapon.level * 200
    health_cost := game.player.max_health / 10 * 300
    
    rl.DrawText(fmt.ctprintf("1. %s Upgrade - Lv.%d -> Lv.%d (%d credits)", 
               weapon.name, weapon.level, weapon.level + 1, weapon_cost), 330, 180, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("   +5 Damage, XP: %d/%d", weapon.xp, weapon.xp_to_next), 340, 205, 16, rl.GRAY)
    
    rl.DrawText(fmt.ctprintf("2. Hull Upgrade - +25 Max HP (%d credits)", health_cost), 330, 260, 20, rl.WHITE)
    rl.DrawText(fmt.ctprintf("   Current HP: %d", game.player.max_health), 340, 285, 16, rl.GRAY)
    
    rl.DrawText(fmt.ctprintf("Your Credits: %d", game.player.credits), 330, 420, 20, rl.GOLD)
    rl.DrawText("Press 1 or 2 to upgrade | Q/E to switch weapon", 330, 460, 16, rl.YELLOW)
}

draw_ship_menu :: proc(game: ^Game) {
    rl.ClearBackground({0, 0, 0, 230})
    
    rl.DrawText("SHIP STATUS", WINDOW_WIDTH/2 - 100, 30, 40, rl.CYAN)
    rl.DrawText("Press ESC to return", WINDOW_WIDTH/2 - 80, 80, 20, rl.GRAY)
    
    // Weapon stats
    rl.DrawText("WEAPONS", 100, 130, 30, rl.YELLOW)
    for i := 0; i < 6; i += 1 {
        w := game.player.weapons[i]
        color := rl.GRAY
        if i == game.player.active_weapon { color = rl.GREEN }
        
        rl.DrawText(fmt.ctprintf("%d. %s Lv.%d - Damage: %d - XP: %d/%d", 
                   i + 1, w.name, w.level, w.damage, w.xp, w.xp_to_next), 
                   120, 170 + i32(i) * 50, 20, color)
    }
    
    // Ship stats
    rl.DrawText("SHIP STATS", WINDOW_WIDTH - 400, 130, 30, rl.YELLOW)
    rl.DrawText(fmt.ctprintf("Health: %d/%d", game.player.health, game.player.max_health), WINDOW_WIDTH - 380, 170, 20, rl.RED)
    rl.DrawText(fmt.ctprintf("Shields: %d/%d", game.player.shields, game.player.max_shields), WINDOW_WIDTH - 380, 200, 20, rl.CYAN)
    rl.DrawText(fmt.ctprintf("Speed: %.0f", game.player.speed), WINDOW_WIDTH - 380, 230, 20, rl.GREEN)
    rl.DrawText(fmt.ctprintf("Credits: %d", game.player.credits), WINDOW_WIDTH - 380, 260, 20, rl.GOLD)
    rl.DrawText(fmt.ctprintf("Level: %d (XP: %d)", game.player.level, game.player.xp), WINDOW_WIDTH - 380, 290, 20, rl.PURPLE)
    
    // Quests
    rl.DrawText("QUESTS", WINDOW_WIDTH - 400, 340, 30, rl.YELLOW)
    if !game.boss_defeated {
        rl.DrawText("Main: Defeat the Void Reaver", WINDOW_WIDTH - 380, 380, 20, rl.WHITE)
        rl.DrawText("- Upgrade your weapons", WINDOW_WIDTH - 360, 410, 16, rl.GRAY)
        rl.DrawText("- Gather resources for upgrades", WINDOW_WIDTH - 360, 430, 16, rl.GRAY)
        rl.DrawText("- Find allies in the sector", WINDOW_WIDTH - 360, 450, 16, rl.GRAY)
    } else {
        rl.DrawText("Main: COMPLETED", WINDOW_WIDTH - 380, 380, 20, rl.GREEN)
    }
}

// ===================================================================
// Dialogue System
// ===================================================================

start_dialogue :: proc(game: ^Game, speaker: string, dialogue: ^Dialogue, on_complete: proc()) {
    dialogue.active = true
    dialogue.speaker = speaker
    dialogue.current_line = 0
    dialogue.on_complete = on_complete
    game.phase = .DIALOGUE
}

update_dialogue :: proc(game: ^Game) {
    if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) {
        game.dialogue.current_line += 1
        if game.dialogue.current_line >= len(game.dialogue.lines) {
            game.dialogue.active = false
            if game.dialogue.on_complete != nil {
                game.dialogue.on_complete()
            }
            game.phase = .FLYING
        }
    }
}

draw_dialogue :: proc(game: ^Game) {
    rl.DrawRectangle(100, WINDOW_HEIGHT - 200, WINDOW_WIDTH - 200, 150, {0, 0, 0, 200})
    rl.DrawRectangleLines(100, WINDOW_HEIGHT - 200, WINDOW_WIDTH - 200, 150, rl.WHITE)
    
    rl.DrawText(fmt.ctprintf("%s:", game.dialogue.speaker), 120, WINDOW_HEIGHT - 180, 20, rl.YELLOW)
    rl.DrawText(game.dialogue.lines[game.dialogue.current_line], 120, WINDOW_HEIGHT - 140, 16, rl.WHITE)
    rl.DrawText("Press SPACE to continue", WINDOW_WIDTH - 250, WINDOW_HEIGHT - 100, 14, rl.GRAY)
}

// ===================================================================
// Helper Functions
// ===================================================================

start_battle :: proc(game: ^Game) {
    enemy_index := rand.int31_max(i32(len(enemies)))
    
    // Boss spawn logic
    if !game.boss_defeated && game.player.level >= 5 && rand.int31_max(100) < 10 {
        enemy_index = len(enemies) - 1 // Boss
        game.current_track = 4
        if game.music_enabled { rl.PlayMusicStream(game.music[4]) }
    } else {
        game.current_track = 2
        if game.music_enabled { rl.PlayMusicStream(game.music[2]) }
    }
    
    game.battle.enemy = enemies[enemy_index]
    game.battle.active = true
    game.battle.state = .PLAYER_TURN
    game.battle.player_health = game.player.health
    game.battle.enemy_health = game.battle.enemy.health
    game.battle.log_index = 0
    game.battle.minigame = Minigame{active = false}
    slice.fill(game.battle.battle_log[:], "")
    
    add_battle_log(game, fmt.tprintf("⚔ Battle started vs %s!", game.battle.enemy.name))
    add_battle_log(game, fmt.tprintf("Active weapon: %s", game.player.weapons[game.player.active_weapon].name))
    add_battle_log(game, "Your turn! [SPACE] Attack, [D] Defend, [R] Run")
    add_battle_log(game, "Press Q/E to switch weapons")
    
    game.phase = .IN_BATTLE
}

exit_battle :: proc(game: ^Game) {
    game.battle.active = false
    game.phase = .FLYING
    game.current_track = 1
    if game.music_enabled { rl.PlayMusicStream(game.music[1]) }
}

add_battle_log :: proc(game: ^Game, message: string) {
    if game.battle.log_index >= len(game.battle.battle_log) {
        for i := 1; i < len(game.battle.battle_log); i += 1 {
            game.battle.battle_log[i-1] = game.battle.battle_log[i]
        }
        game.battle.log_index = len(game.battle.battle_log) - 1
    }
    game.battle.battle_log[game.battle.log_index] = message
    game.battle.log_index += 1
}

add_xp :: proc(game: ^Game, amount: i32) {
    game.player.xp += amount
    xp_needed := game.player.level * 100
    
    for game.player.xp >= xp_needed {
        game.player.level += 1
        game.player.xp -= xp_needed
        game.player.max_health += 10
        game.player.health = game.player.max_health
        game.player.max_shields += 5
        game.player.shields = game.player.max_shields
        xp_needed = game.player.level * 100
        
        add_floating_text(fmt.tprintf("LEVEL UP! Lv.%d", game.player.level), game.player.position)
    }
}

upgrade_weapon :: proc(weapon: ^Weapon) {
    weapon.level += 1
    weapon.damage += 5
    weapon.xp_to_next += 50
}

cycle_weapon :: proc(game: ^Game, direction: int) {
    new_index := game.player.active_weapon + direction
    if new_index < 0 { new_index = 5 }
    if new_index > 5 { new_index = 0 }
    game.player.active_weapon = new_index
    add_battle_log(game, fmt.tprintf("Switched to %s", game.player.weapons[game.player.active_weapon].name))
}

spawn_powerup :: proc(game: ^Game, pos: rl.Vector3) {
    power_type := PowerUpType(rand.int31_max(6))
    value := 25 + rand.int31_max(75)
    append(&game.powerups, PowerUp{type = power_type, position = pos, value = value, duration = 30, active = true})
}

apply_powerup :: proc(game: ^Game, powerup: ^PowerUp) {
    #partial switch powerup.type {
    case .HEALTH:
        game.player.health = min(game.player.max_health, game.player.health + powerup.value)
        add_floating_text(fmt.tprintf("+%d HP", powerup.value), game.player.position)
    case .DAMAGE:
        game.player.weapons[game.player.active_weapon].damage += powerup.value
        add_floating_text(fmt.tprintf("+%d Damage (Temp)", powerup.value), game.player.position)
    case .SPEED:
        game.player.speed += f32(powerup.value) / 10
        add_floating_text("Speed Boost!", game.player.position)
    case .SHIELD:
        game.player.shields = min(game.player.max_shields, game.player.shields + powerup.value)
        add_floating_text(fmt.tprintf("+%d Shields", powerup.value), game.player.position)
    case .CREDITS:
        game.player.credits += powerup.value
        add_floating_text(fmt.tprintf("+%d Credits", powerup.value), game.player.position)
    case .XP_BOOST:
        add_xp(game, powerup.value)
        add_floating_text(fmt.tprintf("+%d XP", powerup.value), game.player.position)
    }
}

get_powerup_color :: proc(type: PowerUpType) -> rl.Color {
    #partial switch type {
    case .HEALTH: return {255, 50, 50, 255}
    case .DAMAGE: return {255, 100, 50, 255}
    case .SPEED: return {50, 255, 50, 255}
    case .SHIELD: return {50, 100, 255, 255}
    case .CREDITS: return {255, 215, 0, 255}
    case .XP_BOOST: return {150, 50, 255, 255}
    }
    return rl.WHITE
}

count_remaining_resources :: proc(game: ^Game) -> int {
    count := 0
    for res in game.resources {
        if !res.collected { count += 1 }
    }
    return count
}

add_floating_text :: proc(text: string, pos: rl.Vector3) {
    // Simplified floating text
    fmt.println(text)
}

next_track :: proc(game: ^Game) {
    game.current_track = (game.current_track + 1) % 3
    if game.music_enabled && game.current_track < len(game.music) {
        rl.PlayMusicStream(game.music[game.current_track])
    }
}

reset_game :: proc(game: ^Game) {
    init_game(game)
}

save_game :: proc(game: ^Game) {
    fmt.println("\n=== GAME SAVED ===")
    fmt.printf("Player Level: %d\n", game.player.level)
    fmt.printf("Health: %d/%d\n", game.player.health, game.player.max_health)
    fmt.printf("Credits: %d\n", game.player.credits)
    fmt.printf("Boss Defeated: %t\n", game.boss_defeated)
    fmt.println("=================")
}

draw_flying_dialogue :: proc(game: ^Game) {
    draw_3d_world(game)
    draw_ui(game)
    draw_dialogue(game)
}

get_texture :: proc(name: string) -> rl.Texture2D {
    // Simplified texture system
    return rl.Texture2D{}
}

clamp :: proc(value, min_val, max_val: f32) -> f32 {
    return max(min_val, min(value, max_val))
}

// Define missing math functions
math :: struct {
    PI: f32,
}

math_cos :: proc(radians: f32) -> f32 {
    return f32(rl.cos(f32(radians)))
}

math_sin :: proc(radians: f32) -> f32 {
    return f32(rl.sin(f32(radians)))
}

math_atan2 :: proc(y, x: f32) -> f32 {
    return f32(rl.atan2(f32(y), f32(x)))
}

unload_game :: proc(game: ^Game) {
    if game.house_model != 0 { rl.UnloadModel(game.house_model) }
    if game.tree_model != 0 { rl.UnloadModel(game.tree_model) }
    if game.asteroid_model != 0 { rl.UnloadModel(game.asteroid_model) }
    if game.enemy_model != 0 { rl.UnloadModel(game.enemy_model) }
    if game.player.model != 0 { rl.UnloadModel(game.player.model) }
    
    if game.music_enabled {
        for &music in game.music {
            if music != 0 { rl.UnloadMusicStream(music) }
        }
    }
    
    delete(game.trees)
    delete(game.asteroids)
    delete(game.resources)
    delete(game.npcs)
    delete(game.powerups)
    delete(game.dialogue.lines)
    
    rl.CloseAudioDevice()
    rl.CloseWindow()
}