local Components = {}
Components.__index = Components

function Components.new(scene)
  local self = setmetatable({}, Components)

  self.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
  })

  return self
end

return Components
