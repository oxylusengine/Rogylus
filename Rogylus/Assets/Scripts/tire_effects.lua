-- Plays the car's tire particle emitters while any wheel is sliding, spinning or locked up

local TireEffects = {}
TireEffects.__index = TireEffects

local DEFAULTS = {
  lateral_slip = math.rad(12.0), -- slip angle that counts as sliding
  longitudinal_slip = 0.4,       -- wheelspin or lockup ratio that counts as sliding
  min_speed = 2.0,               -- m/s, slip ratios blow up near standstill
  hold_time = 0.2,               -- keeps smoke on briefly so it doesn't flicker
}

function TireEffects.new(scene, wheels, emitters, settings)
  local self = setmetatable({}, TireEffects)
  self.scene = scene
  self.wheels = wheels
  self.emitters = emitters
  self.settings = setmetatable(settings or {}, { __index = DEFAULTS })
  self.hold = 0.0
  self.active = nil -- unknown until the first update, emitters may play on awake
  return self
end

function TireEffects:is_sliding(speed)
  local s = self.settings
  if math.abs(speed) < s.min_speed then
    return false
  end

  for _, wheel in ipairs(self.wheels) do
    local longitudinal, lateral = Physics.get_vehicle_wheel_slip(wheel)
    if math.abs(lateral) > s.lateral_slip or math.abs(longitudinal) > s.longitudinal_slip then
      return true
    end
  end
  return false
end

function TireEffects:update(speed, dt)
  if self:is_sliding(speed) then
    self.hold = self.settings.hold_time
  else
    self.hold = math.max(0.0, self.hold - dt)
  end
  self:set_active(self.hold > 0.0)
end

function TireEffects:set_active(active)
  if active == self.active then
    return
  end
  self.active = active

  for _, emitter in ipairs(self.emitters) do
    if active then
      self.scene:play_particles(emitter)
    else
      self.scene:stop_particles(emitter)
    end
  end
end

return TireEffects
