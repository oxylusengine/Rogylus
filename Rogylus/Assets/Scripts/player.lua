Player = {
  Config = {},
  Components = {},
  screen_size = vec2.new(0, 0)
}

function Player.get_xp_for_level(level)
  if level <= 1 then
    return 0
  end

  -- Exponential + linear growth curve
  -- Formula: base * (multiplier ^ (level-2)) + additive * (level-1)
  local exponential_part = Player.Config.BaseXP * (Player.Config.XPMultiplier ^ (level - 2))
  local linear_part = Player.Config.XPAdditive * (level - 1)

  return math.floor(exponential_part + linear_part)
end

-- Calculate total XP needed from level 1 to target level
function Player.get_total_xp_for_level(level)
  local total = 0
  for i = 2, level do
    total = total + Player.get_xp_for_level(i)
  end
  return total
end

-- Get current level based on total XP
function Player.get_level_from_xp(total_xp)
  local level = 1
  local xp_used = 0

  while true do
    local xp_needed = Player.get_xp_for_level(level + 1)
    if xp_used + xp_needed > total_xp then
      break
    end
    xp_used = xp_used + xp_needed
    level = level + 1
  end

  return level, total_xp - xp_used, Player.get_xp_for_level(level + 1)
end

function Player.level_up(player, current_xp, new_level)
  local xp_needed = Player.get_xp_for_level(new_level)
  local new_xp = current_xp - xp_needed
  player:set_xp(new_xp)
  player:set_level(new_level)

  --player_log:add("Player leveled up: " .. tostring(new_level))
  --ui_state = UIState.LevelUp

  -- multiple level ups
  if new_xp >= Player.get_xp_for_level(player.level + 1) then
    Player.level_up(player, player.level + 1)
  end
end

function Player.gain_xp(player, xp)
  local new_xp = player.xp + xp
  player:set_xp(new_xp)
  --player_log:add("Added xp to player: " .. tostring(xp))
  local xp_needed = Player.get_xp_for_level(player.level + 1)
  if new_xp >= xp_needed then
    Player.level_up(player, new_xp, player.level + 1)
  end
end

function Player.gain_gold(player, gold)
  player:set_gold(player.gold + gold)
  --player_log:add("Added gold to player: " .. tostring(gold))
end

function Player.take_damage(scene, player, damage)
  if player:has(Player.Components.InvulnerableComponent) then
    Log.info("Player invulnerable!")
    return
  end

  scene:defer(function()
    player:add(Player.Components.InvulnerableComponent)
  end)
  local pc = player:get_mut(Player.Components.PlayerComponent)
  pc:set_health(pc.health - damage)

  if pc.health <= damage then -- dead
    Log.info("You died!")
  end
end

function Player.create_player(scene, starting_point)
  local player = scene:create_entity("player", true)
  local player_model_root = scene:create_mesh_entity(Assets.player_model_asset)

  player_model_root:child_of(player)
  player_model_root:set_name("player_model", true)

  local player_tc = player:get_mut(Core.TransformComponent)
  player_tc:set_position(starting_point)
  player:modified(Core.TransformComponent)

  player:add(Player.Components.PlayerComponent):add(Core.CharacterControllerComponent)
  local ch = player:get_mut(Core.CharacterControllerComponent)
  ch:set_character_height_standing(0.35)
  player:modified(Core.CharacterControllerComponent)

  local player_inventory_container = scene:world():entity():add(Player.Components.ContainerComponent)
  player:add_pair(Player.Components.InventoryComponent, player_inventory_container)

  local player_camera_entity = scene:create_entity("player_camera", true)
  player_camera_entity:add(Core.CameraComponent)
  local player_camera_tc = player_camera_entity:get_mut(Core.TransformComponent)
  player_camera_tc:set_position(vec3.new(0, 4.5, 3.5))
  player_camera_tc:set_rotation(vec3.new(glm.radians(-60), glm.radians(-90), 0))

  return player, player_camera_entity, player_inventory_container
end

function Player.create_player_system(world, player_camera)
  world:system("player_system", { Core.TransformComponent, Player.Components.PlayerComponent }, { flecs.OnUpdate },
    function(it)
      local tc = it:field(0, Core.TransformComponent)
      local pc = it:field(1, Player.Components.PlayerComponent)

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        local pc_data = pc:at(i - 1)

        local entity = it:entity(i - 1)

        local ivc = entity:get_mut(Player.Components.InvulnerableComponent)
        if ivc then
          local am = App:get_asset_manager()
          local model = am:get_model(Assets.player_model_asset)

          if ivc.cooldown > 0.0 then
            ivc:set_cooldown(ivc.cooldown - App:get_timestep():get_seconds())

            -- NOTE: Since this mesh with it's materials are shared across every player this will apply to all players as well.

            -- flash intensity using sine wave
            local flash_frequency = 1.0
            local time = App:get_timestep():get_elapsed_seconds()
            local flash_intensity = math.abs(math.sin(time * flash_frequency * math.pi * 2))

            -- lerp between white and red based on flash intensity
            local red = vec4.new(1, 0, 0, 1)
            local white = vec4.new(1, 1, 1, 1)
            local flash_color = vec4.new(
              white.x + (red.x - white.x) * flash_intensity,
              white.y + (red.y - white.y) * flash_intensity,
              white.z + (red.z - white.z) * flash_intensity,
              1
            )

            for mat_i = 1, #model.materials, 1 do
              local material = am:get_material(model.materials[mat_i])
              material:set_albedo_color(flash_color)
              am:set_material_dirty(model.materials[mat_i])
            end
          elseif ivc.cooldown == 0.0 or ivc.cooldown < 0.0 then
            world:defer_begin()
            entity:remove(Player.Components.InvulnerableComponent)
            world:defer_end()

            for mat_i = 1, #model.materials, 1 do
              local material = am:get_material(model.materials[mat_i])
              material:set_albedo_color(vec4.new(1, 1, 1, 1))
              am:set_material_dirty(model.materials[mat_i])
            end
          end
        end

        local character = Physics.get_character(entity)

        local mouse_position = Input.get_mouse_position()
        local ray = Physics.get_screen_ray_from_camera(player_camera, mouse_position, Player.screen_size)
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
end

return Player;
