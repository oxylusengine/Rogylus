-- Chase camera behind a vehicle: right mouse drag orbits, scroll zooms, recenters when idle

local OrbitCamera = {}
OrbitCamera.__index = OrbitCamera

local TWO_PI = math.pi * 2.0

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

-- frame rate independent blend factor for exponential smoothing
local function damp(sharpness, dt)
  return 1.0 - math.exp(-sharpness * dt)
end

-- shortest signed difference between two angles
local function angle_delta(from, to)
  return (to - from + math.pi) % TWO_PI - math.pi
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- yaw of a rotation's +Z axis around world up, nil when the axis is (nearly) vertical
local function heading_yaw(q)
  local fx = 2.0 * (q.x * q.z + q.w * q.y)
  local fz = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
  if fx * fx + fz * fz < 1e-4 then
    return nil
  end
  return math.atan(fx, fz)
end

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
  self.last_mouse = nil
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

      local dt = math.min(App.get_timestep():get_seconds(), 0.1)
      self:update_controls(dt)
      local position, rotation = self:solve(dt)

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

  local scroll = input:get_mouse_scroll_offset_y()
  if scroll ~= 0.0 then
    self.zoom = clamp(self.zoom - scroll * s.zoom_step, s.min_distance, s.max_distance)
  end

  if input:get_mouse_held(s.orbit_button) then
    local mouse = input:get_mouse_position()
    if self.last_mouse ~= nil then
      local dx = mouse.x - self.last_mouse.x
      local dy = mouse.y - self.last_mouse.y
      self.orbit_yaw = self.orbit_yaw - dx * s.mouse_sensitivity
      self.pitch = clamp(self.pitch + dy * s.mouse_sensitivity, s.min_pitch, s.max_pitch)
    end
    self.last_mouse = mouse
    self.idle_time = 0.0
  else
    self.last_mouse = nil
    self.idle_time = self.idle_time + dt
    if self.idle_time > s.recenter_delay then
      local t = damp(s.recenter_sharpness, dt)
      self.orbit_yaw = self.orbit_yaw + angle_delta(self.orbit_yaw, 0.0) * t
      self.pitch = self.pitch + (s.pitch - self.pitch) * t
    end
  end
end

-- returns the camera world position and rotation for this frame
function OrbitCamera:solve(dt)
  local s = self.settings
  local body = Physics.get_body(self.target)

  local car_yaw = heading_yaw(body:get_rotation()) or self.yaw
  local velocity = body:get_linear_velocity()
  local speed = glm.length(velocity)

  if not self.initialized then
    self.yaw = car_yaw
    self.initialized = true
  else
    self.yaw = self.yaw + angle_delta(self.yaw, car_yaw) * damp(s.follow_sharpness, dt)
  end

  local blend = damp(s.zoom_sharpness, dt)
  local target_distance = self.zoom + math.min(speed * s.speed_distance, s.max_speed_distance)
  local target_fov = s.fov + math.min(speed * s.speed_fov, s.max_speed_fov)
  self.distance = self.distance + (target_distance - self.distance) * blend
  self.fov = self.fov + (target_fov - self.fov) * blend

  -- pivot is rigidly attached to the car, smoothing it would jitter against the fixed physics step
  local pivot = self.scene:get_world_position(self.target) + vec3.new(0.0, s.pivot_height, 0.0)

  local yaw = self.yaw + self.orbit_yaw
  local pitch = self.pitch
  local cos_pitch = math.cos(pitch)
  local look_dir = vec3.new(math.sin(yaw) * cos_pitch, -math.sin(pitch), math.cos(yaw) * cos_pitch)
  local position = pivot - look_dir * self.distance

  -- camera looks down -Z, so yaw by an extra half turn, then pitch down: q = Ry(yaw + pi) * Rx(-pitch)
  local hy = (yaw + math.pi) * 0.5
  local hp = -pitch * 0.5
  local sy, cy = math.sin(hy), math.cos(hy)
  local sp, cp = math.sin(hp), math.cos(hp)

  -- quat has no usable constructor from Lua, so fill in an identity one
  local rotation = glm.angle_axis(0.0, vec3.new(0.0, 1.0, 0.0))
  rotation.w = cy * cp
  rotation.x = cy * sp
  rotation.y = sy * cp
  rotation.z = -sy * sp

  return position, rotation
end

return OrbitCamera
