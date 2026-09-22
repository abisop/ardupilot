local PARAM_TABLE_KEY = 93

assert(param:add_table(PARAM_TABLE_KEY, "WIND_", 1), 'could not add param table')
assert(param:add_param(PARAM_TABLE_KEY, 1, 'ENABLE', 1), 'could not add WIND_ENABLE param')
local enable = Parameter("WIND_ENABLE")

function update()
    if not enable or enable:get() < 1 then
        return update, 1000
    end

    -- Fetch 3D wind vector from AHRS (returns Vector3f or nil)
    local wind = ahrs:wind_estimate()

    if wind then
        local wind_x = wind:x() -- North component (m/s)
        local wind_y = wind:y() -- East component (m/s)

        -- Calculate wind speed (magnitude)
        local wind_speed = math.sqrt(wind_x^2 + wind_y^2)

        -- Direction wind is blowing TOWARDS (0-360 deg)
        local dir_towards = math.deg(math.atan(wind_y, wind_x))
        if dir_towards < 0 then
            dir_towards = dir_towards + 360
        end

        -- Convert to standard aviation format: direction wind is blowing FROM
        local wind_dir_from = (dir_towards + 180) % 360

        gcs:send_text(6, string.format("Wind Speed: %.1fm/s, From: %.0f deg", wind_speed, wind_dir_from))
    end

    return update, 1000 
end

return update()