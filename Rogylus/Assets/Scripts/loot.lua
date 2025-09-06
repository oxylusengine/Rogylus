Loot = {
  Components = {}
}

function Loot.create_physical_loot(scene, position, type, value)
  local loot = scene:create_entity()
  loot:add(Loot.Components.LootComponent)
  loot:add(type)
  loot:add(Loot.Components.ValueComponent, { value = value })

  local loot_model_root = scene:create_mesh_entity(Assets.loot_model_asset)

  loot_model_root:child_of(loot)
  loot_model_root:set_name("loot_model")

  local tc = loot:get_mut(Core.TransformComponent)
  tc:set_position(position)

  loot:add(Core.BoxColliderComponent)
  local loot_bc = loot:get_mut(Core.BoxColliderComponent)
  loot_bc:set_size(vec3.new(0.3, 0.3, 0.3))
  loot_bc:set_offset(vec3.new(0, 0.0, 0))

  loot:add(Core.RigidBodyComponent)
  local loot_rb = loot:get_mut(Core.RigidBodyComponent)
  loot_rb:set_type(1)
  loot_rb:set_is_sensor(true)
  loot:modified(Core.RigidBodyComponent)

  return loot
end

return Loot
