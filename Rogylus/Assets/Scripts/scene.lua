local vfs = App:get_vfs()
WORKING_DIR = vfs:PROJECT_DIR()

Components = {
  PlayerComponent,
  ItemComponent,
  InventoryComponent,
  ContainerComponent,
  ContainedByComponent,
  WeaponComponent,
  EnemyComponent,
  ProjectileComponent,
  InvulnerableComponent,
  ConsumableComponent,
  OneTimeComponent,
  CooldownComponent,
  HealComponent,
  MaxHealthComponent,
  DamageComponent,
  AttackSpeedComponent,
  MoveSpeedComponent,
  LuckComponent,
  ValueComponent,
  ValueRangeComponent,
  LootComponent,
}

Config = require_script(WORKING_DIR, 'Scripts/config.lua')
Assets = require_script(WORKING_DIR, 'Scripts/assets.lua')
Player = require_script(WORKING_DIR, 'Scripts/player.lua')
Player.Config = Config
Player.Components = Components
Loot = require_script(WORKING_DIR, 'Scripts/loot.lua')
Loot.Components = Components

local UIState = {
  Gameplay = 1,
  LevelUp = 2,
  Death = 3,
}

local ui_state = UIState.Gameplay

function on_add(scene)
  Components.PlayerComponent = Component.define(scene, "PlayerComponent", {
    health = 4,
    speed = 3.0,
    level = 1,
    xp = 100,
    gold = 0,

    -- stats
    max_health = 100,
    move_speed_multiplier = 1.0,
    luck = 0.0,
    damage_multiplier = 1.0,
    attack_speed_multiplier = 1.0,
  })

  Components.EnemyComponent = Component.define(scene, "EnemyComponent", {
    speed = 1.0, health = 10.0, damage = 3.0, gold_reward = 5
  })

  Components.ItemComponent = Component.define(scene, "ItemComponent", {
    in_use = false,
  })
  Components.InventoryComponent = Component.define(scene, "InventoryComponent")
  Components.ContainerComponent = Component.define(scene, "ContainerComponent")
  Components.ContainedByComponent = Component.define(scene, "ContainedByComponent")
  scene:world():component(Components.ContainedByComponent):add(flecs.Exclusive)

  Components.WeaponComponent = Component.define(scene, "WeaponComponent")
  scene:world():component(WeaponComponent):is_a(Components.ItemComponent)

  Components.ConsumableComponent = Component.define(scene, "ConsumableComponent")
  Components.OneTimeComponent = Component.define(scene, "OneTimeComponent")
  Components.CooldownComponent = Component.define(scene, "CooldownComponent", {
    cooldown = 1.0, current_cooldown = 0.0
  })
  Components.HealComponent = Component.define(scene, "HealComponent")
  Components.MaxHealthComponent = Component.define(scene, "MaxHealthComponent")
  Components.DamageComponent = Component.define(scene, "DamageComponent")
  Components.AttackSpeedComponent = Component.define(scene, "AttackSpeedComponent")
  Components.MoveSpeedComponent = Component.define(scene, "MoveSpeedComponent")
  Components.LuckComponent = Component.define(scene, "LuckComponent")
  Components.ValueComponent = Component.define(scene, "ValueComponent", {
    value = 0
  })
  Components.ValueRangeComponent = Component.define(scene, "ValueRangeComponent", {
    min = 0, max = 0
  })

  Components.ProjectileComponent = Component.define(scene, "ProjectileComponent", {
    damage = 0.0, speed = 5.0, fired = false, lifetime = 5.0, current_lifetime = 0.0
  })

  Components.InvulnerableComponent = Component.define(scene, "InvulnerableComponent", {
    cooldown = 3.0
  })

  Components.LootComponent = Component.define(scene, "LootComponent")
end

-- Scene stuff
players = {}
enemy_query = {}

function calculate_value_dice(min_value, max_value, luck_stat)
  if min_value >= max_value then
    return min_value
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

  return math.floor(min_value + chosen_roll * (max_value - min_value))
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

function create_projectile(scene, damage, position_at)
  local projectile = scene:create_entity()
  projectile:add(Components.ProjectileComponent)

  local pc = projectile:get_mut(Components.ProjectileComponent)
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

function create_weapon(name, player, inventory, scene)
  local weapon = scene:create_entity(name)
  weapon:add(Components.WeaponComponent)
  weapon:add(Components.ItemComponent)
  weapon:add(Components.DamageComponent)
  -- just random values for every weapon for now
  weapon:add(Components.ValueRangeComponent, { min = 3.0, max = 10.0 })
  weapon:add(Components.CooldownComponent, { cooldown = 1.0, current_cooldown = 1.0 })
  weapon:add_pair(Components.ContainedByComponent, inventory)
  local weapon_model_root = scene:create_mesh_entity(Assets.weapon_model_asset)

  weapon_model_root:set_name(scene:safe_entity_name("weapon_model"))
  weapon_model_root:child_of(weapon)

  local weapon_tc = weapon:get_mut(Core.TransformComponent)
  weapon_tc:set_position(vec3.new(0.4, 0.5, 0))

  weapon:child_of(player)

  return weapon
end

function create_enemy(scene, starting_point)
  local enemy = scene:create_entity("enemy", true)
  local enemy_model_root = scene:create_mesh_entity(Assets.enemy_model_asset)

  enemy_model_root:child_of(enemy)
  enemy_model_root:set_name("enemy_model", true)

  local enemy_tc = enemy:get_mut(Core.TransformComponent)
  enemy_tc:set_position(starting_point)
  enemy:modified(Core.TransformComponent)

  enemy:add(Components.EnemyComponent)

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

function spawn_enemies(scene, count)
  for i = 1, count, 1 do
    create_enemy(scene, vec3.new(math.random(-5, 5), 0.0, math.random(-5, 5)))
  end
end

function create_loot(scene, position, type, value)
  local loot = scene:create_entity()
  loot:add(Components.LootComponent)
  loot:add(type)
  loot:add(Components.ValueComponent, { value = value })

  local loot_model_root = scene:create_mesh_entity(Assets.loot_model_asset)

  loot_model_root:child_of(loot)
  loot_model_root:set_name("loot_model")

  local tc = loot:get_mut(Core.TransformComponent)
  tc:set_position(position)

  loot:add(Core.BoxColliderComponent)
  local loot_bc = loot:get_mut(Core.BoxColliderComponent)
  loot_bc:set_size(vec3.new(0.3, 0.3, 0.3))
  loot_bc:set_offset(vec3.new(0, 0.5, 0))

  loot:add(Core.RigidBodyComponent)
  local loot_rb = loot:get_mut(Core.RigidBodyComponent)
  loot_rb:set_type(1)
  loot_rb:set_is_sensor(true)
  loot_rb:set_allowed_dofs(AllowedDOFs.TranslationX + AllowedDOFs.TranslationZ + AllowedDOFs.RotationY)
  loot:modified(Core.RigidBodyComponent)

  return loot
end

function on_scene_start(scene)
  Assets.load_assets(WORKING_DIR)

  local player, player_camera, player_inventory = Player.create_player(scene, vec3.new(0, 0.0, 0))
  players[1] = player
  local weapon1 = create_weapon("weapon1", player, player_inventory, scene)
  local weapon_ic = weapon1:get_mut(ItemComponent)
  weapon_ic:set_in_use(true)

  local weapon2 = create_weapon("weapon2", player, player_inventory, scene)

  spawn_enemies(scene, 1)
  create_projectile(scene, 0, vec3.new(100, -100, 100)) -- cook

  Player.create_player_system(scene:world(), player_camera);

  scene:world():system("enemy_system", { Core.TransformComponent, Components.EnemyComponent }, { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local ec = it:field(1, Components.EnemyComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local ec_data = ec:at(i - 1)

        local entity = it:entity(i - 1)

        local enemy_died = false

        if ec_data.health < 1 then
          enemy_died = true
          scene:world():defer_begin()
          entity:destruct()
          scene:world():defer_end()
        end

        local body = Physics.get_body(entity)

        -- TODO: use the nearest player
        if #players > 0 then
          local player_tc = players[1]:get(Core.TransformComponent)
          local player_c = players[1]:get_mut(Components.PlayerComponent)

          if enemy_died then
            local xp_reward = calculate_enemy_xp(player_c.level, "normal")
            Player.add_xp(player_c, xp_reward)
            Player.add_gold(player_c, ec_data.gold_reward)
            scene:defer(function(s)
              create_loot(s, tc_data.position, HealComponent, 1)
            end)
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

  enemy_query = scene:world():query({ Core.TransformComponent, Components.EnemyComponent })

  scene:world():system("weapon_system", { Core.TransformComponent, Components.WeaponComponent }, { flecs.OnUpdate },
    function(it)
      local wc = it:field(1, Components.WeaponComponent)

      for i = 1, it:count(), 1 do
        local wc_data = wc:at(i - 1)

        local entity = it:entity(i - 1)
        local in_use = entity:get(ItemComponent).in_use

        if in_use then
          local player_component = players[1]:get(Components.PlayerComponent)

          local can_shoot = true;

          local cooldown_component = entity:get_mut(Components.CooldownComponent)
          if cooldown_component then
            if cooldown_component.current_cooldown > 0.0 then
              cooldown_component:set_current_cooldown(
                cooldown_component.current_cooldown -
                App:get_timestep():get_millis() / 1000
              )

              can_shoot = false
            elseif cooldown_component.current_cooldown == 0.0 or cooldown_component.current_cooldown < 0.0 then
              local cooldown = cooldown_component.cooldown
              cooldown = cooldown / player_component.attack_speed_multiplier

              cooldown_component:set_current_cooldown(cooldown)

              can_shoot = true
            end
          end

          if can_shoot then
            local damage_value = 0

            local damage_component = entity:get(Components.DamageComponent)
            if damage_component then
              local value_range_component = entity:get(Components.ValueRangeComponent)
              if value_range_component then
                damage_value = calculate_value_dice(
                  value_range_component.min, value_range_component.max,
                  player_component.luck
                )
              end

              local value_component = entity:get(Components.ValueComponent)
              if value_component then
                damage_value = value_component.value
              end

              if value_component and value_range_component then
                Log.error("Weapons can't have ValueComponent & ValueRangeComponent at the same time!")
              end

              damage_value = damage_value * player_component.damage_multiplier
            end

            scene:defer(function(s)
              local enemy_it = flecs.iter(enemy_query)
              if enemy_it:query_next() then
                local world_pos = scene:get_world_position(entity)
                create_projectile(s, damage_value, world_pos)
              end
            end)
          end
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

  scene:world():system("projectile_system",
    { Core.TransformComponent, Components.ProjectileComponent, Components.RigidBodyComponent },
    { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local pc = it:field(1, Components.ProjectileComponent)

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

function on_viewport_render(scene)
  local renderer_instance = scene:get_renderer_instance()
  local viewport_offset = renderer_instance:get_viewport_offset()

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
  end
  ImGui.End()

  local player_stats_pos = viewport_offset
  player_stats_pos.x = player_stats_pos.x + 80
  player_stats_pos.y = player_stats_pos.y + 60
  if #players > 0 then
    local player_component = players[1]:get_mut(Components.PlayerComponent)

    local heart_size = 22
    local heart_gaps = 3
    local health_bar_size = (player_component.health + 1) * heart_size + player_component.health * heart_gaps

    ImGui.SetNextWindowPos(player_stats_pos.x, player_stats_pos.y)
    ImGui.SetNextWindowSize(health_bar_size, 40)
    if ImGui.Begin("HealthBar", true, ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.NoDocking + ImGuiWindowFlags.NoBackground) then
      local p_x, p_y = ImGui.GetCursorScreenPos()
      local x = p_x + 4.0
      local y = p_y + 4.0

      local draw_list = ImGui.GetWindowDrawList()
      local col = ImGui.GetColorU32(1, 0, 0, 1)
      local ngon_sides = 4
      for i = 1, player_component.health, 1 do
        draw_list:AddNgonFilled(vec2.new(x + heart_size * 0.5, y + heart_size * 0.5), heart_size * 0.5, col, ngon_sides)
        x = x + heart_size + heart_gaps;
      end
    end
    ImGui.End()

    local item_size = 36
    local inventory_pos = player_stats_pos
    inventory_pos.y = inventory_pos.y + 50
    ImGui.SetNextWindowPos(inventory_pos.x, inventory_pos.y)
    ImGui.SetNextWindowSize(120, 120)
    if ImGui.Begin("Inventory", true, ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.NoDocking) then
      local inv = players[1]:target(Components.InventoryComponent)
      local items_query = scene:world():query({ { ContainedByComponent, inv } })
      local item_it = flecs.iter(items_query)
      while item_it:query_next() do
        for i = 1, item_it:count() do
          local entity = item_it:entity(i - 1)

          if entity:has(Components.WeaponComponent) then
            local wc = entity:get(Components.WeaponComponent)
            ImGui.Button(entity:name(), item_size, item_size)
            ImGui.SameLine()
            -- ImGui.Text("Weapon")
            -- ImGui.Text("Damage Range: " .. tostring(wc.min_damage) .. "-" .. tostring(wc.max_damage))
            -- ImGui.Text("Cooldown: " .. tostring(wc.cooldown))
          end
        end
      end
    end
    ImGui.End()

    if ImGui.Begin("PlayerStats", true, ImGuiWindowFlags.AlwaysAutoResize) then
      ImGui.Text("health: " .. tostring(player_component.health))
      ImGui.Text("speed: " .. tostring(player_component.speed))
      ImGui.Text("level: " .. tostring(player_component.level))
      ImGui.Text("xp: " .. tostring(player_component.xp))
      ImGui.Text("total xp: " .. Player.get_total_xp_for_level(player_component.level))
      ImGui.Text("next level xp: " .. Player.get_xp_for_level(player_component.level + 1))
      ImGui.Text("gold: " .. tostring(player_component.gold))
      ImGui.Text("max health: " .. tostring(player_component.max_health))
      ImGui.Text("move speed multiplier: " .. tostring(player_component.move_speed_multiplier))
      ImGui.Text("luck: " .. tostring(player_component.luck))
      ImGui.Text("damage multiplier: " .. tostring(player_component.damage_multiplier))
      ImGui.Text("attack speed multiplier: " .. tostring(player_component.attack_speed_multiplier))

      ImGui.SeparatorText("Inventory")

      local inv = players[1]:target(Components.InventoryComponent)
      local items_query = scene:world():query({ { ContainedByComponent, inv } })
      local item_it = flecs.iter(items_query)
      while item_it:query_next() do
        for i = 1, item_it:count() do
          local entity = item_it:entity(i - 1)

          if entity:has(Components.WeaponComponent) then
            local wc = entity:get(Components.WeaponComponent)
            ImGui.Text(entity:path())
            local value_component = entity:get(Components.ValueComponent)
            local value_range_component = entity:get(Components.ValueRangeComponent)
            if value_range_component then
              ImGui.Text("Damage Range: " ..
                tostring(value_range_component.min) .. "-" .. tostring(value_range_component.max))
            end
            if value_component then
              ImGui.Text("Damage: " .. tostring(value_component.value))
            end
            local cooldown_component = entity:get(Components.CooldownComponent)
            if cooldown_component then
              ImGui.Text("Cooldown: " .. tostring(cooldown_component.cooldown))
            end
          end
        end
      end
    end
  end
  ImGui.End()
end

function on_scene_render(scene, extent, format)
  local screen_size = vec2.new(extent.x, extent.y)
  Player.screen_size = screen_size;
end

function on_contact_added(scene, body1, body2)
  local body1_entity = Physics.get_entity_from_body(body1, scene:world())
  local body2_entity = Physics.get_entity_from_body(body2, scene:world())

  if body1_entity and body2_entity then
    -- Player hit
    local function handle_player_hit(player, enemy)
      Player.take_damage(scene, player, enemy.damage)
    end
    if body1_entity:has(Components.PlayerComponent) and body2_entity:has(Components.EnemyComponent) then
      local ec = body2_entity:get(Components.EnemyComponent)
      handle_player_hit(body1_entity, ec)
    end
    if body2_entity:has(Components.PlayerComponent) and body1_entity:has(Components.EnemyComponent) then
      local ec = body1_entity:get(Components.EnemyComponent)
      handle_player_hit(body2_entity, ec)
    end

    if body1:is_sensor() or body2:is_sensor() then
      -- Enemy hit
      local function handle_projectile_hit(projectile, enemy)
        enemy:set_health(enemy.health - projectile.damage)
      end
      if body1_entity:has(Components.ProjectileComponent) and body2_entity:has(Components.EnemyComponent) then
        local projectile = body1_entity:get(Components.ProjectileComponent)
        local enemy = body2_entity:get_mut(Components.EnemyComponent)
        handle_projectile_hit(projectile, enemy)
      end
      if body2_entity:has(Components.ProjectileComponent) and body1_entity:has(Components.EnemyComponent) then
        local projectile = body2_entity:get(Components.ProjectileComponent)
        local enemy = body1_entity:get_mut(Components.EnemyComponent)
        handle_projectile_hit(projectile, enemy)
      end

      -- Loot hit
      local function handle_loot_hit(loot_entity, player_entity)
        local value = 0
        local player_mut = player_entity:get_mut(Components.PlayerComponent)
        if loot_entity:has(Components.ValueComponent) then
          value = loot_entity:get(Components.ValueComponent).value
        end
        if loot_entity:has(Components.HealComponent) then
          Player.add_health(player_mut, value)
        end
        if loot_entity:has(Components.MaxHealthComponent) then
          Player.add_max_health(player_mut, value)
        end
        if loot_entity:has(Components.MoveSpeedComponent) then
          Player.add_move_speed_multiplier(player_mut, value)
        end
        if loot_entity:has(Components.LuckComponent) then
          Player.add_luck(player_mut, value)
        end
        if loot_entity:has(Components.DamageComponent) then
          player.add_damage_multiplier(player_mut, value)
        end
        if loot_entity:has(Components.AttackSpeedComponent) then
          Player.add_attack_speed(player_mut, value)
        end

        scene:defer(function(s)
          loot_entity:destruct()
        end)
      end
      if body1_entity:has(Components.LootComponent) and body2_entity:has(Components.PlayerComponent) then
        handle_loot_hit(body1_entity, body2_entity)
      end
      if body2_entity:has(Components.LootComponent) and body1_entity:has(Components.PlayerComponent) then
        handle_loot_hit(body2_entity, body1_entity)
      end
    end
  end
end
