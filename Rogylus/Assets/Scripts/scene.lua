local vfs = App:get_vfs()
WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

local Components = require_script(WORKING_DIR, "Scripts/components.lua")

local components = nil

function on_add(scene)
  components = Components.new(scene)
end

function on_scene_update(scene, dt)
end

function on_scene_start(scene)
  Oxlog.info("scene started")
end
