-- Scalar helpers shared by gameplay scripts, kept in Lua to avoid a C++ call per operation

local mathx = {}

function mathx.clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

function mathx.lerp(a, b, t)
  return a + (b - a) * t
end

-- frame rate independent blend factor for exponential smoothing
function mathx.damp(sharpness, dt)
  return 1.0 - math.exp(-sharpness * dt)
end

-- moves current toward target by at most max_step
function mathx.approach(current, target, max_step)
  local diff = target - current
  if math.abs(diff) <= max_step then
    return target
  end
  return current + (diff > 0.0 and max_step or -max_step)
end

-- shortest signed difference between two angles in radians
function mathx.angle_delta(from, to)
  return (to - from + math.pi) % (math.pi * 2.0) - math.pi
end

-- yaw of a direction around world up, 0 along +Z, nil when the direction is (nearly) vertical
function mathx.yaw_of(dir)
  if dir.x * dir.x + dir.z * dir.z < 1e-4 then
    return nil
  end
  return math.atan(dir.x, dir.z)
end

return mathx
