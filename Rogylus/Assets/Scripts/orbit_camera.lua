-- Chase camera behind a vehicle: right mouse drag orbits, scroll zooms, recenters when idle

local mathx = require_script("mathx.lua")

local OrbitCamera = {}
OrbitCamera.__index = OrbitCamera

local UP = vec3.new(0.0, 1.0, 0.0)
local FORWARD = vec3.new(0.0, 0.0, 1.0)

local DEFAULTS = {
  distance = 9.0,           -- orbit radius at rest (m)
  min_distance = 3.0,       -- scroll zoom limits (m)
  max_distance = 15.0,
  zoom_step = 0.75,         -- distance change per scroll notch (m)
  speed_distance = 0.04,    -- extra distance per m/s of speed
  max_speed_distance = 2.5, -- cap on the speed-based pull back (m)

  pivot_height = 1.2,       -- look-at point above the car origin (m)
  pitch = math.rad(12.0),   -- resting angle above the horizon
  min_pitch = math.rad(-5.0),
  max_pitch = math.rad(70.0),

  follow_sharpness = 4.0,   -- how quickly yaw catches up with the car heading
  zoom_sharpness = 6.0,     -- smoothing for distance and fov changes
  recenter_delay = 1.5,     -- seconds after a mouse orbit before swinging back
  recenter_sharpness = 2.5,
  mouse_sensitivity = 0.005, -- radians per pixel of drag
  orbit_button = MouseButton.Right,

  fov = 60.0,
  speed_fov = 0.25,         -- extra fov degrees per m/s of speed
  max_speed_fov = 15.0,
}

function OrbitCamera.new(scene, settings)
  local self = setmetatable({}, OrbitCamera)

  self.scene = scene
  self.settings = setmetatable(settings or {}, { __index = DEFAULTS })
  self:reset()

  return self
end

function OrbitCamera:reset()
  self.target = nil
  self.initialized = false
  self.yaw = 0.0
  self.pitch = self.settings.pitch
  self.orbit_yaw = 0.0 -- user offset on top of the car heading
  self.zoom = self.settings.distance
  self.distance = self.settings.distance
  self.fov = self.settings.fov
  self.idle_time = 0.0
end

function OrbitCamera:set_target(entity)
  self.target = entity
end

-- Drives every CameraComponent entity; register after the player system to see this frame's pose
function OrbitCamera:register(world)
  self:reset()
  world:system("orbit_camera_system", { Core.TransformComponent, Core.CameraComponent }, { flecs.OnUpdate },
    function(it)
      if self.target == nil then
        return
      end
      local body = Physics.get_body(self.target)
      if body == nil then
        return
      end

      local dt = math.min(it:delta_time(), 0.1)
      self:update_controls(dt)
      local position, rotation = self:solve(body, dt)

      local tc = it:field(0, Core.TransformComponent)
      local cc = it:field(1, Core.CameraComponent)
      for i = 1, it:count(), 1 do
        local tc_data = tc:at(i - 1)
        tc_data:set_position(position)
        tc_data:set_rotation(rotation)
        cc:at(i - 1):set_fov(self.fov)
      end
    end)
end

function OrbitCamera:update_controls(dt)
  local s = self.settings
  local input = App.mod.Input
  local focused = self.scene.input_focused

  local scroll = focused and input:get_mouse_scroll_offset_y() or 0.0
  if scroll ~= 0.0 then
    self.zoom = mathx.clamp(self.zoom - scroll * s.zoom_step, s.min_distance, s.max_distance)
  end

  if focused and input:get_mouse_held(s.orbit_button) then
    local delta = input:get_mouse_position_rel()
    self.orbit_yaw = self.orbit_yaw - delta.x * s.mouse_sensitivity
    self.pitch = mathx.clamp(self.pitch + delta.y * s.mouse_sensitivity, s.min_pitch, s.max_pitch)
    self.idle_time = 0.0
  else
    self.idle_time = self.idle_time + dt
    if self.idle_time > s.recenter_delay then
      local t = mathx.damp(s.recenter_sharpness, dt)
      self.orbit_yaw = self.orbit_yaw + mathx.angle_delta(self.orbit_yaw, 0.0) * t
      self.pitch = mathx.lerp(self.pitch, s.pitch, t)
    end
  end
end

-- returns the camera world position and rotation for this frame
function OrbitCamera:solve(body, dt)
  local s = self.settings

  local car_yaw = mathx.yaw_of(body:get_rotation() * FORWARD) or self.yaw
  local velocity = body:get_linear_velocity()
  local speed = glm.length(velocity)

  if not self.initialized then
    self.yaw = car_yaw
    self.initialized = true
  else
    self.yaw = self.yaw + mathx.angle_delta(self.yaw, car_yaw) * mathx.damp(s.follow_sharpness, dt)
  end

  local blend = mathx.damp(s.zoom_sharpness, dt)
  local target_distance = self.zoom + math.min(speed * s.speed_distance, s.max_speed_distance)
  local target_fov = s.fov + math.min(speed * s.speed_fov, s.max_speed_fov)
  self.distance = mathx.lerp(self.distance, target_distance, blend)
  self.fov = mathx.lerp(self.fov, target_fov, blend)

  -- pivot is rigidly attached to the car, smoothing it would jitter against the fixed physics step
  local pivot = self.scene:get_world_position(self.target) + UP * s.pivot_height

  local yaw = self.yaw + self.orbit_yaw
  local pitch = self.pitch
  local cos_pitch = math.cos(pitch)
  local look_dir = vec3.new(math.sin(yaw) * cos_pitch, -math.sin(pitch), math.cos(yaw) * cos_pitch)
  local position = pivot - look_dir * self.distance

  return position, glm.quat_look_at(look_dir, UP)
end

return OrbitCamera
