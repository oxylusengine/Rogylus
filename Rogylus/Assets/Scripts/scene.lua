local Components = require_script("components.lua")
local Player = require_script("player.lua")
local OrbitCamera = require_script("orbit_camera.lua")

local CAMERA_PLAYER_ID = 0 -- PlayerComponent id the camera follows

local components = nil
local camera = nil
local players = {} -- Player controllers keyed by entity path

function on_add(scene)
  components = Components.new(scene)
  camera = OrbitCamera.new(scene)
end

function on_scene_start(scene)
  players = {}

  scene
      :world()
      :system("player_system", { components.PlayerComponent, Core.VehicleComponent }, { flecs.OnUpdate },
        function(it)
          local pc = it:field(0, components.PlayerComponent)
          local vc = it:field(1, Core.VehicleComponent)
          local dt = math.min(it:delta_time(), 0.1)

          for i = 1, it:count(), 1 do
            local entity = it:entity(i - 1)
            local key = entity:path()
            local player = players[key]
            if player == nil then
              player = Player.new(scene)
              players[key] = player
            end

            player:update(entity, vc:at(i - 1), dt)

            if pc:at(i - 1).id == CAMERA_PLAYER_ID then
              camera:set_target(entity)
            end
          end
        end)

  -- after player_system so the camera sees this frame's car pose
  camera:register(scene:world())
end

function on_scene_update(scene, dt)
end
