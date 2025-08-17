PlayerComponent = {}

function create_player(scene)
  local vfs = App:get_vfs();
  local asset_man = App:get_asset_manager();

  local models_dir = vfs:resolve_physical_dir(vfs:PROJECT_DIR(), "Models");

  local player_model_asset = asset_man:import_asset(models_dir .. "/player.glb.oxasset");

  local player = scene:create_entity(scene:safe_entity_name("player"));
  local player_model_root = scene:create_mesh_entity(player_model_asset);

  player_model_root:child_of(player);
  player_model_root:set_name(scene:safe_entity_name("player_model"));

  player:add(PlayerComponent);
end

function remove_player(scene)
  local player = scene:world():entity("player");
  player:destruct();
end

function on_add(scene)
  PlayerComponent = Component.define(scene, "PlayerComponent", { speed = 1.0 });
end

function on_remove(scene)
  Component.undefine(scene, PlayerComponent);
end

function on_scene_start(scene)
  create_player(scene);

  scene:world():system("player_system", { Core.TransformComponent, PlayerComponent }, { flecs.OnUpdate }, function(it)
    local tc = it:field(0, Core.TransformComponent); -- All matched TransformComponent's of the system
    local pc = it:field(1, PlayerComponent);         -- All matched PlayerComponent's of the system

    for i = 1, it:count(), 1 do
      local tc_data = tc:at(i - 1); -- TransformComponent data of the (i-1)'th matched entity
      local pc_data = pc:at(i - 1); -- PlayerComponent data of the (i-1)'th matched entity

      local entity = it:entity(i - 1);

      local delta_time = App:get_timestep():get_seconds();

      local new_position = tc_data.position;
      if Input.get_key_held(KeyCode.A) then
        new_position.x = new_position.x - pc_data.speed * delta_time;
        tc_data:set_position(new_position);
        entity:modified(Core.TransformComponent);
      end
      if Input.get_key_held(KeyCode.D) then
        new_position.x = new_position.x + pc_data.speed * delta_time;
        tc_data:set_position(new_position);
        entity:modified(Core.TransformComponent);
      end
      if Input.get_key_held(KeyCode.W) then
        new_position.z = new_position.z - pc_data.speed * delta_time;
        tc_data:set_position(new_position);
        entity:modified(Core.TransformComponent);
      end
      if Input.get_key_held(KeyCode.S) then
        new_position.z = new_position.z + pc_data.speed * delta_time;
        tc_data:set_position(new_position);
        entity:modified(Core.TransformComponent);
      end
    end
  end);
end

function on_scene_update(scene, delta_time)
end
