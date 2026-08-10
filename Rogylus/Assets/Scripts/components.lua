local Components = {}
Components.__index = Components

local vfs = App:get_vfs()
local WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

function Components.new(scene)
  local self = setmetatable({}, Components)

  self.PlayerComponent = Component.define(scene, "PlayerComponent", {
    id = { type = "u32", default = 0 },
  })

  return self
end

return Components
