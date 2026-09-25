-- Keyboard driving controls: raw digital intent, the vehicle controller does the shaping

local DriverInput = {}

DriverInput.BINDINGS = {
  throttle = { ScanCode.W, ScanCode.Up },
  reverse = { ScanCode.S, ScanCode.Down },
  left = { ScanCode.A, ScanCode.Left },
  right = { ScanCode.D, ScanCode.Right },
  handbrake = { ScanCode.Space },
  reset = { ScanCode.R },
}

local NEUTRAL = { throttle = false, reverse = false, steer = 0.0, handbrake = false, reset = false }

local function any_held(input, keys)
  for _, key in ipairs(keys) do
    if input:get_key_held(key) then
      return true
    end
  end
  return false
end

local function any_pressed(input, keys)
  for _, key in ipairs(keys) do
    if input:get_key_pressed(key) then
      return true
    end
  end
  return false
end

-- neutral while the viewport is unfocused so typing elsewhere in the editor doesn't drive
function DriverInput.read(scene)
  if not scene.input_focused then
    return NEUTRAL
  end

  local input = App.mod.Input
  local b = DriverInput.BINDINGS
  local steer = 0.0
  if any_held(input, b.right) then steer = steer + 1.0 end
  if any_held(input, b.left) then steer = steer - 1.0 end

  return {
    throttle = any_held(input, b.throttle),
    reverse = any_held(input, b.reverse),
    steer = steer,
    handbrake = any_held(input, b.handbrake),
    reset = any_pressed(input, b.reset),
  }
end

return DriverInput
