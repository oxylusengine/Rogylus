local vfs = App:get_vfs()
WORKING_DIR = vfs:PROJECT_DIR()

Config = require_script(WORKING_DIR, 'Scripts/config.lua')
Assets = require_script(WORKING_DIR, 'Scripts/assets.lua')

local UIState = {
  Gameplay = 1,
  LevelUp = 2,
  Death = 3,
}

local ui_state = UIState.Gameplay

-- Components
PlayerComponent = {}
ItemComponent = {}
InventoryComponent = {}
ContainerComponent = {}
ContainedByComponent = {}
WeaponComponent = {}
EnemyComponent = {}
ProjectileComponent = {}

function on_add(scene)
  PlayerComponent = Component.define(scene, "PlayerComponent", {
    health = 100,
    speed = 3.0,
    level = 1,
    xp = 100,
    gold = 0,

    -- stats
    max_health = 100,
    move_speed_multiplier = 1.0,
    luck = 1.0,
    damage_multiplier = 1.0,
    attack_speed_multiplier = 1.0,
  })

  EnemyComponent = Component.define(scene, "EnemyComponent", {
    speed = 1.0, health = 10.0, damage = 3.0, gold_reward = 5
  })

  ItemComponent = Component.define(scene, "ItemComponent")
  InventoryComponent = Component.define(scene, "InventoryComponent")
  ContainerComponent = Component.define(scene, "ContainerComponent")
  ContainedByComponent = Component.define(scene, "ContainedByComponent")
  scene:world():component(ContainedByComponent):add(flecs.Exclusive)

  WeaponComponent = Component.define(scene, "WeaponComponent", {
    min_damage = 3.0, max_damage = 10.0, cooldown = 1.0, current_cooldown = 3.0
  })
  scene:world():component(WeaponComponent):is_a(ItemComponent)

  ProjectileComponent = Component.define(scene, "ProjectileComponent", {
    damage = 0.0, speed = 5.0, fired = false, lifetime = 5.0, current_lifetime = 0.0
  })
end

-- Scene stuff
players = {}
screen_size = vec2.new(0, 0)
enemy_query = {}
player_log = create_string_vector() -- debug action log

-- Calculate XP required for a specific level
function get_xp_for_level(level)
  if level <= 1 then
    return 0
  end

  -- Exponential + linear growth curve
  -- Formula: base * (multiplier ^ (level-2)) + additive * (level-1)
  local exponential_part = Config.BaseXP * (Config.XPMultiplier ^ (level - 2))
  local linear_part = Config.XPAdditive * (level - 1)

  return math.floor(exponential_part + linear_part)
end

-- Calculate total XP needed from level 1 to target level
function get_total_xp_for_level(level)
  local total = 0
  for i = 2, level do
    total = total + get_xp_for_level(i)
  end
  return total
end

-- Get current level based on total XP
function get_level_from_xp(total_xp)
  local level = 1
  local xp_used = 0

  while true do
    local xp_needed = LevelSystem.get_xp_for_level(level + 1)
    if xp_used + xp_needed > total_xp then
      break
    end
    xp_used = xp_used + xp_needed
    level = level + 1
  end

  return level, total_xp - xp_used, LevelSystem.get_xp_for_level(level + 1)
end

-- Calculate XP an enemy should drop based on player level and enemy type
function calculate_enemy_xp(player_level, enemy_type)
  enemy_type = enemy_type or "normal"

  -- Base XP scales with player level
  local base_xp = Config.BaseEnemyXP * (Config.EnemyXPScaling ^ (player_level - 1))

  -- Apply multipliers based on enemy type
  local multiplier = 1.0
  if enemy_type == "elite" then
    multiplier = Config.EliteXPMultiplier
  elseif enemy_type == "boss" then
    multiplier = Config.BossXPMultiplier
  end

  -- Add some randomization (±20%)
  local random_factor = 0.8 + (math.random() * 0.4)

  return math.floor(base_xp * multiplier * random_factor)
end

function player_level_up(player, current_xp, new_level)
  local xp_needed = get_xp_for_level(new_level)
  local new_xp = current_xp - xp_needed
  player:set_xp(new_xp)
  player:set_level(new_level)

  player_log:add("Player leveled up: " .. tostring(new_level))
  ui_state = UIState.LevelUp

  -- multiple level ups
  if new_xp >= get_xp_for_level(player.level + 1) then
    player_level_up(player, player.level + 1)
  end
end

function player_gain_xp(player, xp)
  local new_xp = player.xp + xp
  player:set_xp(new_xp)
  player_log:add("Added xp to player: " .. tostring(xp))
  local xp_needed = get_xp_for_level(player.level + 1)
  if new_xp >= xp_needed then
    player_level_up(player, new_xp, player.level + 1)
  end
end

function player_gain_gold(player, gold)
  player:set_gold(player.gold + gold)
  player_log:add("Added gold to player: " .. tostring(gold))
end

function calculate_damage_dice(min_damage, max_damage, luck_stat)
  if min_damage >= max_damage then
    return min_damage
  end

  -- Number of dice to roll based on absolute luck value
  local abs_luck = math.abs(luck_stat)
  --local dice_count = 1 + math.floor(abs_luck / 50) -- 0-49 = 1 die, 50-99 = 2 dice, 100+ = 3 dice
  local dice_count = 1 + math.floor(abs_luck) -- 1 luck = 1 dice
  dice_count = math.min(dice_count, 30)       -- the limit is 30 now

  local rolls = {}
  for i = 1, dice_count do
    rolls[i] = math.random()
  end

  local chosen_roll
  if luck_stat >= 0 then
    -- Positive luck: keep the best roll
    chosen_roll = math.max(table.unpack(rolls))
  else
    -- Negative luck: keep the worst roll
    chosen_roll = math.min(table.unpack(rolls))
  end

  return math.floor(min_damage + chosen_roll * (max_damage - min_damage))
end

function create_projectile(scene, damage, position_at)
  local projectile = scene:create_entity()
  projectile:add(ProjectileComponent)

  local pc = projectile:get_mut(ProjectileComponent)
  pc:set_damage(damage)

  local projectile_model_root = scene:create_mesh_entity(Assets.projectile_model_asset)

  projectile_model_root:child_of(projectile)

  local projectile_tc = projectile:get_mut(Core.TransformComponent)
  projectile_tc:set_position(position_at)

  projectile:add(Core.BoxColliderComponent)
  local projectile_bc = projectile:get_mut(Core.BoxColliderComponent)
  projectile_bc:set_size(vec3.new(0.1, 0.1, 0.1))
  projectile_bc:set_offset(vec3.new(0, 0.0, 0))

  projectile:add(Core.RigidBodyComponent)
  local projectile_rb = projectile:get_mut(Core.RigidBodyComponent)
  projectile_rb:set_type(1)
  projectile_rb:set_is_sensor(true)
  projectile:modified(Core.RigidBodyComponent)
end

function create_weapon(player, inventory, scene, component)
  local weapon = scene:create_entity("weapon", true)
  weapon:add(component)
  weapon:add_pair(ContainedByComponent, inventory)
  local weapon_model_root = scene:create_mesh_entity(Assets.weapon_model_asset)

  weapon_model_root:child_of(weapon)
  weapon_model_root:set_name("weapon_model", true)

  local weapon_tc = weapon:get_mut(Core.TransformComponent)
  weapon_tc:set_position(vec3.new(0.4, 0.5, 0))

  weapon:child_of(player)
end

function create_enemy(scene, starting_point)
  local enemy = scene:create_entity("enemy", true)
  local enemy_model_root = scene:create_mesh_entity(Assets.enemy_model_asset)

  enemy_model_root:child_of(enemy)
  enemy_model_root:set_name("enemy_model", true)

  local enemy_tc = enemy:get_mut(Core.TransformComponent)
  enemy_tc:set_position(starting_point)
  enemy:modified(Core.TransformComponent)

  enemy:add(EnemyComponent)

  enemy:add(Core.BoxColliderComponent)
  local enemy_bc = enemy:get_mut(Core.BoxColliderComponent)
  enemy_bc:set_size(vec3.new(0.3, 0.3, 0.3))
  enemy_bc:set_offset(vec3.new(0, 0.5, 0))

  enemy:add(Core.RigidBodyComponent)
  local enemy_rb = enemy:get_mut(Core.RigidBodyComponent)
  enemy_rb:set_type(2)
  enemy_rb:set_allowed_dofs(AllowedDOFs.TranslationX + AllowedDOFs.TranslationZ + AllowedDOFs.RotationY)
  enemy:modified(Core.RigidBodyComponent)
end

function create_player(scene, starting_point)
  local player = scene:create_entity("player", true)
  local player_model_root = scene:create_mesh_entity(Assets.player_model_asset)

  player_model_root:child_of(player)
  player_model_root:set_name("player_model", true)

  local player_tc = player:get_mut(Core.TransformComponent)
  player_tc:set_position(starting_point)
  player:modified(Core.TransformComponent)

  player:add(PlayerComponent):add(Core.CharacterControllerComponent)
  local ch = player:get_mut(Core.CharacterControllerComponent)
  ch:set_character_height_standing(0.35)
  player:modified(Core.CharacterControllerComponent)

  local player_inventory_container = scene:world():entity():add(ContainerComponent)
  player:add_pair(InventoryComponent, player_inventory_container)

  local player_camera_entity = scene:create_entity("player_camera", true)
  player_camera_entity:add(CameraComponent)
  local player_camera_tc = player_camera_entity:get_mut(Core.TransformComponent)
  player_camera_tc:set_position(vec3.new(0, 6.0, 3.5))
  player_camera_tc:set_rotation(vec3.new(glm.radians(-60), glm.radians(-90), 0))

  return player, player_camera_entity, player_inventory_container
end

function remove_player(scene)
  local player = scene:world():entity("player")
  player:destruct()
end

function spawn_enemies(scene, count)
  for i = 1, count, 1 do
    create_enemy(scene, vec3.new(-i / 2, 0.0, -1.0))
  end
end

function on_scene_start(scene)
  Assets.load_assets(WORKING_DIR)

  local player, player_camera, player_inventory = create_player(scene, vec3.new(0, 0.0, 0))
  players[1] = player
  create_weapon(player, player_inventory, scene, WeaponComponent)

  spawn_enemies(scene, 1)

  scene:world():system("player_system", { Core.TransformComponent, PlayerComponent }, { flecs.OnUpdate }, function(it)
    local tc = it:field(0, Core.TransformComponent)
    local pc = it:field(1, PlayerComponent)

    for i = 1, it:count(), 1 do
      local tc_data = tc:at(i - 1)
      local pc_data = pc:at(i - 1)

      local entity = it:entity(i - 1)

      local character = Physics.get_character(entity)

      local mouse_position = Input.get_mouse_position()
      local ray = Physics.get_screen_ray_from_camera(player_camera, mouse_position, screen_size)
      -- Debug.draw_ray(ray, vec3.new(1, 1, 1))
      local ray_origin = ray:get_origin()
      local ray_direction = ray:get_direction()

      -- intersection with horizontal plane at player's height
      local t = (tc_data.position.y - ray_origin.y) / ray_direction.y

      if t > 0 then
        local world_point = ray_origin + ray_direction * t

        local look_direction = world_point - tc_data.position
        look_direction.y = 0.0
        if glm.length(look_direction) > 0 then
          look_direction = glm.normalize(look_direction)
          local target_yaw = glm.atan2(look_direction.x, look_direction.z)
          local rotation = glm.angle_axis(target_yaw, vec3.new(0, 1, 0))
          character:set_rotation(rotation)
        end
      end

      local new_velocity = vec3.new(0, 0, 0)

      if Input.get_key_held(KeyCode.D) then
        new_velocity.x = 1
      end
      if Input.get_key_held(KeyCode.A) then
        new_velocity.x = -1
      end
      if Input.get_key_held(KeyCode.S) then
        new_velocity.z = 1
      end
      if Input.get_key_held(KeyCode.W) then
        new_velocity.z = -1
      end

      if glm.length(new_velocity) > 0 then
        local player_speed = pc_data.speed * pc_data.move_speed_multiplier
        new_velocity = glm.normalize(new_velocity) * player_speed
      end

      new_velocity.y = 0.0

      character:set_linear_velocity(new_velocity)
    end
  end)

  scene:world():system("enemy_system", { Core.TransformComponent, EnemyComponent }, { flecs.OnUpdate }, function(it)
    local tc = it:field(0, Core.TransformComponent)
    local ec = it:field(1, EnemyComponent)

    for i = 1, it:count(), 1 do
      local tc_data = tc:at(i - 1)
      local ec_data = ec:at(i - 1)

      local entity = it:entity(i - 1)

      local enemy_died = false

      if ec_data.health < 1 then
        enemy_died = true
        scene:world():defer_begin()
        entity:destruct()
        player_log:add("Enemy died!")
        scene:world():defer_end()
      end

      local body = Physics.get_body(entity)

      -- TODO: use the nearest player
      if #players > 0 then
        local player_tc = players[1]:get(Core.TransformComponent)
        local player_c = players[1]:get_mut(PlayerComponent)

        if enemy_died then
          local xp_reward = calculate_enemy_xp(player_c.level, "normal")
          player_gain_xp(player_c, xp_reward)
          player_gain_gold(player_c, ec_data.gold_reward)
        end

        local look_direction = player_tc.position - tc_data.position
        look_direction.y = 0.0
        if glm.length(look_direction) > 0 then
          look_direction = glm.normalize(look_direction)
          local target_yaw = glm.atan2(look_direction.x, look_direction.z)
          local rotation = glm.angle_axis(target_yaw, vec3.new(0, 1, 0))
          body:move_kinematic(player_tc.position, rotation, ec_data.speed)
        end
      end
    end
  end)

  enemy_query = scene:world():query({ Core.TransformComponent, EnemyComponent })

  scene:world():system("weapon_system", { Core.TransformComponent, WeaponComponent }, { flecs.OnUpdate }, function(it)
    local wc = it:field(1, WeaponComponent)

    for i = 1, it:count(), 1 do
      local wc_data = wc:at(i - 1)

      local entity = it:entity(i - 1)
      local world_pos = scene:get_world_position(entity)
      if wc_data.current_cooldown > 0.0 then
        wc_data:set_current_cooldown(wc_data.current_cooldown - App:get_timestep():get_seconds())
      elseif wc_data.current_cooldown == 0.0 or wc_data.current_cooldown < 0.0 then
        local weapon_damage = calculate_damage_dice(wc_data.min_damage, wc_data.max_damage, 1)
        local weapon_cooldown = wc_data.cooldown

        -- add player(owner of this weapon)'s stats
        --local container = entity:target(ContainedByComponent)
        --local p = container:target(InventoryComponent)
        local player_component = players[1]:get(PlayerComponent)
        weapon_damage = weapon_damage * player_component.damage_multiplier
        weapon_cooldown = weapon_cooldown / player_component.attack_speed_multiplier

        wc_data:set_current_cooldown(weapon_cooldown)

        scene:defer(function(s)
          local enemy_it = flecs.iter(enemy_query)
          if enemy_it:query_next() then
            create_projectile(s, weapon_damage, world_pos)
          end
        end)
      end
    end
  end)

  local function find_nearest_enemy(from_position)
    local nearest_position = nil
    local min_distance = math.huge

    local enemy_it = flecs.iter(enemy_query)
    while enemy_it:query_next() do
      local enemy_tc = enemy_it:field(0, Core.TransformComponent)
      for i = 1, enemy_it:count() do
        local enemy_pos = enemy_tc:at(i - 1).position
        local distance = glm.length(enemy_pos - from_position)

        if distance < min_distance then
          min_distance = distance
          nearest_position = enemy_pos
        end
      end
    end

    return nearest_position
  end

  scene:world():system("projectile_system", { Core.TransformComponent, ProjectileComponent, RigidBodyComponent },
    { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local pc = it:field(1, ProjectileComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local pc_data = pc:at(i - 1)

        local entity = it:entity(i - 1)

        if pc_data.lifetime < 1 then
          scene:world():defer_begin()
          entity:destruct()
          scene:world():defer_end()
          return
        else
          pc_data:set_lifetime(pc_data.lifetime - App:get_timestep():get_seconds())
        end

        if not pc_data.fired then
          pc_data:set_fired(true)
          local nearest_enemy_position = find_nearest_enemy(tc_data.position)
          if nearest_enemy_position then
            local enemy_direction = nearest_enemy_position - tc_data.position
            enemy_direction.y = 0.0
            if glm.length(enemy_direction) > 0 then
              enemy_direction = glm.normalize(enemy_direction) * pc_data.speed
              local body = Physics.get_body(entity)
              body:add_linear_velocity(enemy_direction)
            end
          end
        end
      end
    end)
end

function on_scene_update(scene, delta_time)
  if ui_state == UIState.LevelUp then
    if ImGui.Begin("LevelUp!", true, ImGuiWindowFlags.AlwaysAutoResize) then
      if #players > 0 then
        -- local player_component = players[1]:get_mut(PlayerComponent)
        --local random_stat1 = get_random_upgrade(player_component.level)
        --local random_stat2 = get_random_upgrade(player_component.level)
        --local random_stat3 = get_random_upgrade(player_component.level)
        --ImGui.Button(random_stat1.text)
        --ImGui.Button(random_stat2.text)
        --ImGui.Button(random_stat3.text)
        if ImGui.Button("Ok") then
          ui_state = UIState.Gameplay
        end
      end
    end
    ImGui.End()
  end

  if ImGui.Begin("LevelDebugger", true, ImGuiWindowFlags.AlwaysAutoResize) then
    if ImGui.Button("Spawn enemies") then
      spawn_enemies(scene, 6)
    end
    if ImGui.Button("Clear player action log") then
      player_log:clear()
    end
  end
  ImGui.End()

  if ImGui.Begin("ActionLog", true, ImGuiWindowFlags.AlwaysAutoResize) then
    for k = 1, #player_log do
      v = player_log[k]
      ImGui.Text(v)
    end
  end
  ImGui.End()

  if ImGui.Begin("PlayerStats", true, ImGuiWindowFlags.AlwaysAutoResize) then
    if #players > 0 then
      local player_component = players[1]:get_mut(PlayerComponent)
      ImGui.Text("health: " .. tostring(player_component.health))
      ImGui.Text("speed: " .. tostring(player_component.speed))
      ImGui.Text("level: " .. tostring(player_component.level))
      ImGui.Text("xp: " .. tostring(player_component.xp))
      ImGui.Text("total xp: " .. get_total_xp_for_level(player_component.level))
      ImGui.Text("next level xp: " .. get_xp_for_level(player_component.level + 1))
      ImGui.Text("gold: " .. tostring(player_component.gold))
      ImGui.Text("max health: " .. tostring(player_component.max_health))
      ImGui.Text("move speed multiplier: " .. tostring(player_component.move_speed_multiplier))
      ImGui.Text("luck: " .. tostring(player_component.luck))
      ImGui.Text("damage multiplier: " .. tostring(player_component.damage_multiplier))
      ImGui.Text("attack speed multiplier: " .. tostring(player_component.attack_speed_multiplier))

      ImGui.SeparatorText("Inventory")

      local inv = players[1]:target(InventoryComponent)
      local items_query = scene:world():query({ { ContainedByComponent, inv } })
      local item_it = flecs.iter(items_query)
      while item_it:query_next() do
        for i = 1, item_it:count() do
          local entity = item_it:entity(i - 1)

          if entity:has(WeaponComponent) then
            local wc = entity:get(WeaponComponent)
            ImGui.Text("Weapon")
            ImGui.Text("Damage Range: " .. tostring(wc.min_damage) .. "-" .. tostring(wc.max_damage))
            ImGui.Text("Cooldown: " .. tostring(wc.cooldown))
          end
        end
      end
    end
  end
  ImGui.End()
end

function on_scene_render(scene, extent, format)
  screen_size = vec2.new(extent.x, extent.y)
end

function on_contact_added(scene, body1, body2)
  if body1:is_sensor() or body2:is_sensor() then
    local body1_entity = Physics.get_entity_from_body(body1, scene:world())
    local body2_entity = Physics.get_entity_from_body(body2, scene:world())
    if body1_entity and body2_entity then
      local function handle_projectile_hit(projectile, enemy)
        enemy:set_health(enemy.health - projectile.damage)
        player_log:add("Player damaged enemy: -" .. projectile.damage)
      end

      if body1_entity:has(ProjectileComponent) and body2_entity:has(EnemyComponent) then
        local projectile = body1_entity:get(ProjectileComponent)
        local enemy = body2_entity:get_mut(EnemyComponent)
        handle_projectile_hit(projectile, enemy)
      end
      if body2_entity:has(ProjectileComponent) and body1_entity:has(EnemyComponent) then
        local projectile = body2_entity:get(ProjectileComponent)
        local enemy = body1_entity:get_mut(EnemyComponent)
        handle_projectile_hit(projectile, enemy)
      end
    end
  end
end
