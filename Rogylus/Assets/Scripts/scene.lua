-- Components
PlayerComponent = {}
EnemyComponent = {}
WeaponComponent = {}
ProjectileComponent = {}

-- Assets
player_model_asset = {}
enemy_model_asset = {}
weapon_model_asset = {}
projectile_model_asset = {}

-- Scene stuff
screen_size = vec2.new(0, 0)
player_query = {}
enemy_query = {}
player_log = create_string_vector(); -- debug action log

function load_assets()
  local vfs = App:get_vfs();
  local asset_man = App:get_asset_manager();

  local models_dir = vfs:resolve_physical_dir(vfs:PROJECT_DIR(), "Models");

  enemy_model_asset = asset_man:import_asset(models_dir .. "/enemy.glb.oxasset");
  player_model_asset = asset_man:import_asset(models_dir .. "/player.glb.oxasset");
  weapon_model_asset = asset_man:import_asset(models_dir .. "/weapon.glb.oxasset");
  projectile_model_asset = asset_man:import_asset(models_dir .. "/projectile.glb.oxasset");
  asset_man:load_asset(projectile_model_asset); -- pre load projectile model
end

function create_projectile(scene, damage, position_at)
  local projectile = scene:create_entity();
  projectile:add(ProjectileComponent);

  local pc = projectile:get_mut(ProjectileComponent);
  pc:set_damage(damage);

  local projectile_model_root = scene:create_mesh_entity(projectile_model_asset);

  projectile_model_root:child_of(projectile);

  local projectile_tc = projectile:get_mut(Core.TransformComponent);
  projectile_tc:set_position(position_at);

  projectile:add(Core.BoxColliderComponent);
  local projectile_bc = projectile:get_mut(Core.BoxColliderComponent);
  projectile_bc:set_size(vec3.new(0.1, 0.1, 0.1));
  projectile_bc:set_offset(vec3.new(0, 0.0, 0));

  projectile:add(Core.RigidBodyComponent);
  local projectile_rb = projectile:get_mut(Core.RigidBodyComponent);
  projectile_rb:set_type(1);
  projectile_rb:set_is_sensor(true);
  projectile:modified(Core.RigidBodyComponent);
end

function create_weapon(player, scene)
  local weapon = scene:create_entity("weapon", true);
  local weapon_model_root = scene:create_mesh_entity(weapon_model_asset);

  weapon_model_root:child_of(weapon);
  weapon_model_root:set_name("weapon_model", true);

  local weapon_tc = weapon:get_mut(Core.TransformComponent);
  weapon_tc:set_position(vec3.new(0.4, 0.5, 0));

  weapon:child_of(player);

  weapon:add(WeaponComponent);
end

function create_enemy(scene, starting_point)
  local enemy = scene:create_entity("enemy", true);
  local enemy_model_root = scene:create_mesh_entity(enemy_model_asset);

  enemy_model_root:child_of(enemy);
  enemy_model_root:set_name("enemy_model", true);

  local enemy_tc = enemy:get_mut(Core.TransformComponent);
  enemy_tc:set_position(starting_point);
  enemy:modified(Core.TransformComponent);

  enemy:add(EnemyComponent);

  enemy:add(Core.BoxColliderComponent);
  local enemy_bc = enemy:get_mut(Core.BoxColliderComponent);
  enemy_bc:set_size(vec3.new(0.3, 0.3, 0.3));
  enemy_bc:set_offset(vec3.new(0, 0.5, 0));

  enemy:add(Core.RigidBodyComponent);
  local enemy_rb = enemy:get_mut(Core.RigidBodyComponent);
  enemy_rb:set_type(1);
  enemy:modified(Core.RigidBodyComponent);
end

function create_player(scene, starting_point)
  local player = scene:create_entity("player", true);
  local player_model_root = scene:create_mesh_entity(player_model_asset);

  player_model_root:child_of(player);
  player_model_root:set_name("player_model", true);

  local player_tc = player:get_mut(Core.TransformComponent);
  player_tc:set_position(starting_point);
  player:modified(Core.TransformComponent);

  player:add(PlayerComponent):add(Core.CharacterControllerComponent);
  local ch = player:get_mut(Core.CharacterControllerComponent);
  ch:set_character_height_standing(0.35);
  player:modified(Core.CharacterControllerComponent);

  local player_camera_entity = scene:create_entity("player_camera", true);
  player_camera_entity:add(CameraComponent);
  local player_camera_tc = player_camera_entity:get_mut(Core.TransformComponent);
  player_camera_tc:set_position(vec3.new(0, 6.0, 3.5));
  player_camera_tc:set_rotation(vec3.new(glm.radians(-60), glm.radians(-90), 0));

  return player, player_camera_entity;
end

function remove_player(scene)
  local player = scene:world():entity("player");
  player:destruct();
end

function on_add(scene)
  PlayerComponent = Component.define(scene, "PlayerComponent", { speed = 3.0 });
  EnemyComponent = Component.define(scene, "EnemyComponent", { speed = 0.5, health = 10.0, damage = 3.0 });
  WeaponComponent = Component.define(scene, "WeaponComponent", { damage = 5.0, cooldown = 3.0, current_cooldown = 3.0 });
  ProjectileComponent = Component.define(scene, "ProjectileComponent",
    { damage = 0.0, speed = 5.0, fired = false, lifetime = 5.0, current_lifetime = 0.0 })
end

function on_remove(scene)
  Component.undefine(scene, PlayerComponent);
end

function on_scene_start(scene)
  load_assets();

  local player, player_camera = create_player(scene, vec3.new(0, 1.0, 0));
  create_weapon(player, scene);

  create_enemy(scene, vec3.new(-1.0, 1.0, -1.0));

  scene:world():system("player_system", { Core.TransformComponent, PlayerComponent }, { flecs.OnUpdate }, function(it)
    local tc = it:field(0, Core.TransformComponent);
    local pc = it:field(1, PlayerComponent);

    for i = 1, it:count(), 1 do
      local tc_data = tc:at(i - 1);
      local pc_data = pc:at(i - 1);

      local entity = it:entity(i - 1);

      local character = Physics.get_character(entity);

      local mouse_position = Input.get_mouse_position();
      local ray = Physics.get_screen_ray_from_camera(player_camera, mouse_position, screen_size);
      -- Debug.draw_ray(ray, vec3.new(1, 1, 1));
      local ray_origin = ray:get_origin();
      local ray_direction = ray:get_direction();

      -- intersection with horizontal plane at player's height
      local t = (tc_data.position.y - ray_origin.y) / ray_direction.y;

      if t > 0 then
        local world_point = ray_origin + ray_direction * t;

        local look_direction = world_point - tc_data.position;
        look_direction.y = 0.0;
        if glm.length(look_direction) > 0 then
          look_direction = glm.normalize(look_direction);
          local target_yaw = glm.atan2(look_direction.x, look_direction.z);
          local rotation = glm.angle_axis(target_yaw, vec3.new(0, 1, 0));
          character:set_rotation(rotation);
        end
      end

      local new_velocity = vec3.new(0, 0, 0);

      if Input.get_key_held(KeyCode.D) then
        new_velocity.x = 1;
      end
      if Input.get_key_held(KeyCode.A) then
        new_velocity.x = -1;
      end
      if Input.get_key_held(KeyCode.S) then
        new_velocity.z = 1;
      end
      if Input.get_key_held(KeyCode.W) then
        new_velocity.z = -1;
      end

      if glm.length(new_velocity) > 0 then
        new_velocity = glm.normalize(new_velocity) * pc_data.speed;
      end

      character:set_linear_velocity(new_velocity);
    end
  end);

  player_query = scene:world():query({ Core.TransformComponent, PlayerComponent });

  scene:world():system("enemy_system", { Core.TransformComponent, EnemyComponent }, { flecs.OnUpdate }, function(it)
    local tc = it:field(0, Core.TransformComponent);
    local ec = it:field(1, EnemyComponent);

    for i = 1, it:count(), 1 do
      local tc_data = tc:at(i - 1);
      local ec_data = ec:at(i - 1);

      local entity = it:entity(i - 1);

      if ec_data.health < 1 then
        scene:world():defer_begin();
        entity:destruct();
        player_log:add("Enemy died!");
        scene:world():defer_end();
      end

      local body = Physics.get_body(entity);

      local player_it = flecs.iter(player_query);
      while player_it:query_next() do
        local player_tc = player_it:field(0, Core.TransformComponent);

        -- TODO: Use only the nearest player
        for player_iter_index = 1, player_it:count(), 1 do
          local player_tc_data = player_tc:at(player_iter_index - 1);

          local look_direction = player_tc_data.position - tc_data.position;
          look_direction.y = 0.0;
          if glm.length(look_direction) > 0 then
            look_direction = glm.normalize(look_direction);
            local target_yaw = glm.atan2(look_direction.x, look_direction.z);
            local rotation = glm.angle_axis(target_yaw, vec3.new(0, 1, 0));
            body:move_kinematic(player_tc_data.position, rotation, ec_data.speed);
          end
        end
      end
    end
  end);

  enemy_query = scene:world():query({ Core.TransformComponent, EnemyComponent });

  scene:world():system("weapon_system", { Core.TransformComponent, WeaponComponent }, { flecs.OnUpdate }, function(it)
    local wc = it:field(1, WeaponComponent);

    for i = 1, it:count(), 1 do
      local wc_data = wc:at(i - 1);

      local entity = it:entity(i - 1);
      local world_pos = scene:get_world_position(entity);

      if wc_data.current_cooldown > 0.0 then
        wc_data:set_current_cooldown(wc_data.current_cooldown - App:get_timestep():get_seconds());
      elseif wc_data.current_cooldown == 0.0 or wc_data.current_cooldown < 0.0 then
        wc_data:set_current_cooldown(wc_data.cooldown);

        scene:defer(function(s)
          local enemy_it = flecs.iter(enemy_query);
          if enemy_it:query_next() then
            create_projectile(s, wc_data.damage, world_pos);
          end
        end);
      end
    end
  end);

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
      local tc = it:field(0, Core.TransformComponent);
      local pc = it:field(1, ProjectileComponent);

      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1);
        local pc_data = pc:at(i - 1);

        local entity = it:entity(i - 1);

        if pc_data.lifetime < 1 then
          scene:world():defer_begin();
          entity:destruct();
          scene:world():defer_end();
          return;
        else
          pc_data:set_lifetime(pc_data.lifetime - App:get_timestep():get_seconds());
        end

        if not pc_data.fired then
          pc_data:set_fired(true);
          local nearest_enemy_position = find_nearest_enemy(tc_data.position);
          if nearest_enemy_position then
            local enemy_direction = nearest_enemy_position - tc_data.position;
            enemy_direction.y = 0.0;
            if glm.length(enemy_direction) > 0 then
              enemy_direction = glm.normalize(enemy_direction) * pc_data.speed;
              local body = Physics.get_body(entity);
              body:add_linear_velocity(enemy_direction);
            end
          end
        end
      end
    end);
end

function on_scene_update(scene, delta_time)
  if ImGui.Begin("DebugView") then
    for k = 1, #player_log do
      v = player_log[k]
      ImGui.Text(v);
    end
  end
  ImGui.End();
end

function on_scene_render(scene, extent, format)
  screen_size = vec2.new(extent.x, extent.y);
end

function on_contact_added(scene, body1, body2)
  if body1:is_sensor() or body2:is_sensor() then
    local body1_entity = Physics.get_entity_from_body(body1, scene:world());
    local body2_entity = Physics.get_entity_from_body(body2, scene:world());
    if body1_entity and body2_entity then
      local function handle_projectile_hit(projectile, enemy)
        enemy:set_health(enemy.health - projectile.damage);
        player_log:add("Player damaged enemy: -5");
      end

      if body1_entity:has(ProjectileComponent) and body2_entity:has(EnemyComponent) then
        local projectile = body1_entity:get(ProjectileComponent);
        local enemy = body2_entity:get_mut(EnemyComponent);
        handle_projectile_hit(projectile, enemy);
      end
      if body2_entity:has(ProjectileComponent) and body1_entity:has(EnemyComponent) then
        local projectile = body2_entity:get(ProjectileComponent);
        local enemy = body1_entity:get_mut(EnemyComponent);
        handle_projectile_hit(projectile, enemy);
      end
    end
  end
end
