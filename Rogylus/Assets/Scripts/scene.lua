local vfs = App:get_vfs()
WORKING_DIR = vfs:is_mounted_dir(vfs:PROJECT_DIR()) and vfs:PROJECT_DIR() or vfs:APP_DIR()

local Components = require_script(WORKING_DIR, "Scripts/components.lua")
local OrbitCamera = require_script(WORKING_DIR, "Scripts/orbit_camera.lua")

local components = nil
local camera = nil

local current_steer = 0.0

local STEER_SPEED = 4.0        -- Rate at which wheels turn toward input
local STEER_RETURN_SPEED = 6.0 -- Rate at which wheels center when released
local STOP_THRESHOLD = 0.15    -- Linear speed threshold (m/s) to trigger reverse

function on_add(scene)
  components = Components.new(scene)
  camera = OrbitCamera.new(scene)
end

function on_scene_start(scene)
  scene
      :world()
      :system("player_system", { Core.TransformComponent, components.PlayerComponent, Core.VehicleComponent },
        { flecs.OnUpdate }, function(it)
          local vc = it:field(2, Core.VehicleComponent)

          for i = 1, it:count(), 1 do
            local entity = it:entity(i - 1)
            local vc_data = vc:at(i - 1)
            camera:set_target(entity)
            local input = App.mod.Input

            local w_held = input:get_key_held(ScanCode.W)
            local s_held = input:get_key_held(ScanCode.S)
            local a_held = input:get_key_held(ScanCode.A)
            local d_held = input:get_key_held(ScanCode.D)

            local target_steer = 0.0
            if d_held then target_steer = target_steer + 1.0 end
            if a_held then target_steer = target_steer - 1.0 end

            local delta_time = App.get_timestep():get_seconds()
            local steer_rate = (target_steer == 0.0) and STEER_RETURN_SPEED or STEER_SPEED
            local diff = target_steer - current_steer
            local max_step = steer_rate * delta_time

            if math.abs(diff) <= max_step then
              current_steer = target_steer
            else
              current_steer = current_steer + (diff > 0 and max_step or -max_step)
            end

            vc_data:set_input_right(current_steer)

            local forward_speed = Physics.get_vehicle_angular_velocity(entity)

            local forward_input = 0.0
            local brake_input = 0.0

            if w_held then
              if forward_speed < -STOP_THRESHOLD then
                brake_input = 1.0
              else
                forward_input = 1.0
              end
            elseif s_held then
              if forward_speed > STOP_THRESHOLD then
                brake_input = 1.0
              else
                forward_input = -1.0
              end
            end

            vc_data:set_input_forward(forward_input)
            vc_data:set_input_brake(brake_input)
          end
        end)

  camera:register(scene:world())
end

function on_scene_update(scene, dt)
end
