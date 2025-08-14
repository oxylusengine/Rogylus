PlayerComponent = {}

function on_add(scene)
  PlayerComponent = Component.define(scene, "PlayerComponent", { speed = 1.0 });
end

function on_scene_start(scene, entity)
  entity:add(PlayerComponent);
end

function on_scene_update(scene, entity, delta_time)
  local player_tc = entity:get_mut(Core.TransformComponent);
  local player_c = entity:get(PlayerComponent);
  local new_position = player_tc.position;
  if Input.get_key_held(KeyCode.A) then
    new_position.x = new_position.x - player_c.speed * delta_time;
    player_tc:set_position(new_position);
    entity:modified(Core.TransformComponent);
  end
  if Input.get_key_held(KeyCode.D) then
    new_position.x = new_position.x + player_c.speed * delta_time;
    player_tc:set_position(new_position);
    entity:modified(Core.TransformComponent);
  end
  if Input.get_key_held(KeyCode.W) then
    new_position.z = new_position.z - player_c.speed * delta_time;
    player_tc:set_position(new_position);
    entity:modified(Core.TransformComponent);
  end
  if Input.get_key_held(KeyCode.S) then
    new_position.z = new_position.z + player_c.speed * delta_time;
    player_tc:set_position(new_position);
    entity:modified(Core.TransformComponent);
  end
end
