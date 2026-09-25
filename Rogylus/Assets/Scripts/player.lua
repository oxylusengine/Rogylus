-- Turns driver input into vehicle input for one player car: speed sensitive steering, pedal ramps,
-- auto reverse, traction control, handbrake, tire smoke and a reset for when the car gets stuck

local mathx = require_script("mathx.lua")
local DriverInput = require_script("driver_input.lua")
local TireEffects = require_script("tire_effects.lua")

local Player = {}
Player.__index = Player

local UP = vec3.new(0.0, 1.0, 0.0)

local DEFAULTS = {
  steer_speed = 4.0,          -- steering lock per second while turning in
  steer_return_speed = 6.0,   -- steering lock per second while centering or counter steering
  high_speed_steer = 0.35,    -- fraction of steering lock left at steer_falloff_speed
  steer_falloff_speed = 30.0, -- m/s

  throttle_rise = 3.0,        -- per second, ramping in keeps RWD launches from lighting up the tires
  throttle_fall = 8.0,
  brake_rise = 6.0,
  brake_fall = 10.0,

  stop_threshold = 0.5,       -- m/s, below this the opposite pedal drives instead of braking

  traction_control = true,
  tc_min_speed = 3.0,         -- m/s, slip ratios are meaningless near standstill
  tc_slip = 0.25,             -- longitudinal slip where throttle starts getting cut
  tc_gain = 2.0,              -- throttle cut per unit of slip over tc_slip
  tc_min_throttle = 0.3,

  reset_height = 1.0,         -- m lifted when resetting
}

function Player.new(scene, settings)
  local self = setmetatable({}, Player)
  self.scene = scene
  self.settings = setmetatable(settings or {}, { __index = DEFAULTS })
  self.wheels = nil
  self.tire_effects = nil
  self.steer = 0.0
  self.throttle = 0.0 -- signed, negative drives in reverse
  self.brake = 0.0
  self.speed = 0.0    -- m/s along the car's forward axis
  return self
end

function Player:setup(entity)
  self.wheels = {}
  local emitters = {}
  for _, child in ipairs(entity:children()) do
    if child:has(Core.VehicleWheelComponent) then
      table.insert(self.wheels, child)
    elseif child:has(Core.ParticleSystemComponent) then
      table.insert(emitters, child)
    end
  end
  self.tire_effects = TireEffects.new(self.scene, self.wheels, emitters)
end

function Player:max_longitudinal_slip()
  local max_slip = 0.0
  for _, wheel in ipairs(self.wheels) do
    local longitudinal = Physics.get_vehicle_wheel_slip(wheel)
    max_slip = math.max(max_slip, math.abs(longitudinal))
  end
  return max_slip
end

-- puts the car back on its wheels facing the same way, with all motion killed
function Player:reset(body, vc)
  local world_forward = body:get_rotation() * vc.forward
  local yaw = (mathx.yaw_of(world_forward) or 0.0) - (mathx.yaw_of(vc.forward) or 0.0)

  body:set_position(self.scene, body:get_position() + UP * self.settings.reset_height)
  body:set_rotation(self.scene, glm.angle_axis(yaw, UP))
  body:set_linear_velocity(vec3.new(0.0, 0.0, 0.0))
  body:set_angular_velocity(vec3.new(0.0, 0.0, 0.0))

  self.steer = 0.0
  self.throttle = 0.0
  self.brake = 0.0
end

function Player:update_steering(input, dt)
  local s = self.settings
  local falloff = mathx.clamp(math.abs(self.speed) / s.steer_falloff_speed, 0.0, 1.0)
  local target = input.steer * mathx.lerp(1.0, s.high_speed_steer, falloff)

  local centering = target == 0.0 or target * self.steer < 0.0
  local rate = centering and s.steer_return_speed or s.steer_speed
  self.steer = mathx.approach(self.steer, target, rate * dt)
end

function Player:update_pedals(input, dt)
  local s = self.settings

  -- pressing against the direction of travel brakes first, then drives once nearly stopped
  local drive, brake = 0.0, 0.0
  if input.throttle then
    if self.speed < -s.stop_threshold then brake = 1.0 else drive = 1.0 end
  elseif input.reverse then
    if self.speed > s.stop_threshold then brake = 1.0 else drive = -1.0 end
  end

  if drive * self.throttle < 0.0 then
    self.throttle = 0.0
  end
  local throttle_rate = drive ~= 0.0 and s.throttle_rise or s.throttle_fall
  self.throttle = mathx.approach(self.throttle, drive, throttle_rate * dt)

  local brake_rate = brake > self.brake and s.brake_rise or s.brake_fall
  self.brake = mathx.approach(self.brake, brake, brake_rate * dt)
end

-- cut applied on top of the ramped throttle, skipped under handbrake so slides can be held
function Player:traction_limit(input)
  local s = self.settings
  if not s.traction_control or input.handbrake or self.throttle == 0.0 or math.abs(self.speed) < s.tc_min_speed then
    return 1.0
  end

  local excess = self:max_longitudinal_slip() - s.tc_slip
  if excess <= 0.0 then
    return 1.0
  end
  return mathx.clamp(1.0 - excess * s.tc_gain, s.tc_min_throttle, 1.0)
end

function Player:update(entity, vc, dt)
  local body = Physics.get_body(entity)
  if body == nil then
    return
  end
  if self.wheels == nil then
    self:setup(entity)
  end

  local input = DriverInput.read(self.scene)
  self.speed = Physics.get_vehicle_forward_speed(entity)

  if input.reset then
    self:reset(body, vc)
  end

  self:update_steering(input, dt)
  self:update_pedals(input, dt)

  vc:set_input_right(self.steer)
  vc:set_input_forward(self.throttle * self:traction_limit(input))
  vc:set_input_brake(self.brake)
  vc:set_input_hand_brake(input.handbrake and 1.0 or 0.0)

  self.tire_effects:update(self.speed, dt)
end

return Player
