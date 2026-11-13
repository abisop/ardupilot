local PARAM_TABLE_KEY = 97

assert(param:add_table(PARAM_TABLE_KEY, "TEST_", 1), 'could not add param table')
assert(param:add_param(PARAM_TABLE_KEY, 1, 'ENABLE', 1), 'could not add TEST_ENABLE param')
local enable = Parameter("TEST_ENABLE")

local wind_direction = 0
local start_ms = millis()
local displaced = {0,0}
local home_yaw = 0

function wind_compensation(home_direction)
  local now_ms = millis()
  local dt = (now_ms - start_ms) * 0.001  -- seconds

  -- wind_estimate() - Returns a Vector3f containing the current wind estimate for the vehicle
  local wind = ahrs:wind_estimate()
  local wind_speed = math.sqrt(wind:x()^2 + wind:y()^2)
  wind_direction = math.deg(math.atan(wind:y(), wind:x())) + 360

  if(gps:num_sats(gps:primary_sensor()) < 9) then
    -- print calculating displacemant since last update
    gcs:send_text(6, tostring(displaced[1]) .. " " .. tostring(displaced[2]))
    displaced = {displaced[1] + wind_speed * math.cos(wind_direction - home_direction) * dt, displaced[2] + wind_speed * math.sin(wind_direction - home_direction) * dt}
  else
    displaced[1] = 0
    displaced[2] = 0
  end
  return displaced
end


function update()
    if not enable or enable:get() < 1 then
        return update, 1000
    end

    if(gps:num_sats(gps:primary_sensor()) < 9) then
        displaced = wind_compensation(home_yaw)
    else
        local home = ahrs:get_home()
        local curr_loc = gps:location(gps:primary_sensor())
        home_yaw = math.deg(curr_loc:get_bearing(home))
    end
    return update, 200
end

return update()