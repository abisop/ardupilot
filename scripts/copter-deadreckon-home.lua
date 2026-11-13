-- Copter attempts to fly home using dead reckoning if the GPS quality deteriorates or an EKF failsafe triggers

---@diagnostic disable: param-type-mismatch
---@diagnostic disable: cast-local-type

-- create and initialise parameters
local PARAM_TABLE_KEY = 95  -- parameter table key must be used by only one script on a particular flight controller
assert(param:add_table(PARAM_TABLE_KEY, "DR_", 14), 'could not add param table')
assert(param:add_param(PARAM_TABLE_KEY, 1, 'ENABLE', 1), 'could not add DR_ENABLE param')   -- 1 = enabled, 0 = disabled
assert(param:add_param(PARAM_TABLE_KEY, 2, 'ENABLE_DIST', 50), 'could not add DR_ENABLE_DIST param')   -- distance from home (in meters) beyond which the dead reckoning will be enabled
assert(param:add_param(PARAM_TABLE_KEY, 3, 'GPS_SACC_MAX', 0.8), 'could not add DR_GPS_SACC_MAX param') -- GPS speed accuracy max threshold
assert(param:add_param(PARAM_TABLE_KEY, 4, 'GPS_SAT_MIN', 6), 'could not add DR_GPS_SAT_MIN param')  -- GPS satellite count min threshold
assert(param:add_param(PARAM_TABLE_KEY, 5, 'GPS_TRIGG_SEC', 3), 'could not add DR_GPS_TRIGG_SEC parameter') -- GPS checks must fail for this many seconds before dead reckoning will be triggered

assert(param:add_param(PARAM_TABLE_KEY, 6, 'FLY_ANGLE', 10), 'could not add DR_FLY_ANGLE param')    -- lean angle (in degrees) during deadreckoning
assert(param:add_param(PARAM_TABLE_KEY, 7, 'FLY_ALT_MIN', 0), 'could not add DR_FLY_ALT_MIN param') -- min alt above home (in meters) during deadreckoning. zero to return at current alt
assert(param:add_param(PARAM_TABLE_KEY, 8, 'FLY_TIMEOUT', 30), 'could not add DR_FLY_TIMEOUT param')-- deadreckoning timeout (in seconds)
assert(param:add_param(PARAM_TABLE_KEY, 9, 'NEXT_MODE', 6), 'could not add DR_NEXT_MODE param')     -- mode to switch to after GPS recovers or timeout elapses
assert(param:add_param(PARAM_TABLE_KEY, 10, 'DYNPOS_ENABLE', 0), 'could not add DR_DYNAMIC_POSITION_UPDATE_ENABLE param') -- enable dynamic position update
assert(param:add_param(PARAM_TABLE_KEY, 11, 'LEVELTIME', 1000), 'could not add DR_DYNAMIC_POSITION_UPDATE_ENABLE param') -- enable dynamic position update
assert(param:add_param(PARAM_TABLE_KEY, 12, 'TEST_OCT16', 0), 'could not add DR_TEST_OCT16 param') -- temporary test parameter
local test = Parameter("DR_TEST_OCT16") -- temporary test parameter 
assert(param:add_param(PARAM_TABLE_KEY, 13, 'ROLLTIME', 1000), 'could not add DR_ROLLTIME param') -- roll time in milliseconds
assert(param:add_param(PARAM_TABLE_KEY, 14, 'ROLLANGLE', 10), 'could not add DR_ROLLANGLE param') -- roll angle in degrees

local roll_angle = Parameter("DR_ROLLANGLE") -- roll angle in degrees
local roll_time = Parameter("DR_ROLLTIME") -- roll time in milliseconds

-- ROLL -> level -> deadreckon home

-- bind parameters to variables
--[[
  // @Param: DR_ENABLE
  // @DisplayName: Deadreckoning Enable
  // @Description: Deadreckoning Enable
  // @Values: 0:Disabled,1:Enabled
  // @User: Standard
--]]
local enable = Parameter("DR_ENABLE")                  -- 1 = enabled, 0 = disabled

--[[
  // @Param: DR_ENABLE_DIST
  // @DisplayName: Deadreckoning Enable Distance
  // @Description: Distance from home (in meters) beyond which the dead reckoning will be enabled
  // @Units: m
  // @User: Standard
--]]
local enable_dist = Parameter("DR_ENABLE_DIST")        -- distance from home (in meters) beyond which the dead reckoning will be enabled

--[[
  // @Param: DR_GPS_SACC_MAX
  // @DisplayName: Deadreckoning GPS speed accuracy maximum threshold
  // @Description: GPS speed accuracy maximum, above which deadreckoning home will begin (default is 0.8).  Lower values trigger with good GPS quality, higher values will allow poorer GPS before triggering. Set to 0 to disable use of GPS speed accuracy
  // @Range: 0 10
  // @User: Standard
--]]
local gps_speed_acc_max = Parameter("DR_GPS_SACC_MAX") -- GPS speed accuracy max threshold

--[[
  // @Param: DR_GPS_SAT_MIN
  // @DisplayName: Deadreckoning GPS satellite count min threshold
  // @Description: GPS satellite count threshold below which deadreckoning home will begin (default is 6).  Higher values trigger with good GPS quality, Lower values trigger with worse GPS quality. Set to 0 to disable use of GPS satellite count
  // @Range: 0 30
  // @User: Standard
--]]
local gps_sat_count_min = Parameter("DR_GPS_SAT_MIN")  -- GPS satellite count min threshold

--[[
  // @Param: DR_GPS_TRIGG_SEC
  // @DisplayName: Deadreckoning GPS check trigger seconds
  // @Description: GPS checks must fail for this many seconds before dead reckoning will be triggered
  // @Units: s
  // @User: Standard
--]]
local gps_trigger_sec = Parameter("DR_GPS_TRIGG_SEC")  -- GPS checks must fail for this many seconds before dead reckoning will be triggered

--[[
  // @Param: DR_FLY_ANGLE
  // @DisplayName: Deadreckoning Lean Angle
  // @Description: lean angle (in degrees) during deadreckoning
  // @Units: deg
  // @Range: 0 45
  // @User: Standard
--]]
local fly_angle = Parameter("DR_FLY_ANGLE")            -- lean angle (in degrees) during deadreckoning

--[[
  // @Param: DR_FLY_ALT_MIN
  // @DisplayName: Deadreckoning Altitude Min
  // @Description: Copter will fly at at least this altitude (in meters) above home during deadreckoning
  // @Units: m
  // @Range: 0 1000
  // @User: Standard
--]]
local fly_alt_min = Parameter("DR_FLY_ALT_MIN")        -- min alt above home (in meters) during deadreckoning

--[[
  // @Param: DR_FLY_TIMEOUT
  // @DisplayName: Deadreckoning flight timeout
  // @Description: Copter will attempt to switch to NEXT_MODE after this many seconds of deadreckoning.  If it cannot switch modes it will continue in Guided_NoGPS.  Set to 0 to disable timeout
  // @Units: s
  // @User: Standard
--]]
local fly_timeoout = Parameter("DR_FLY_TIMEOUT")       -- deadreckoning timeout (in seconds)

--[[
  // @Param: DR_DYNAMIC_POSITION_UPDATE_ENABLE
  // @DisplayName: Deadreckoning Dynamic Position Update Enable
  // @Description: Enable dynamic position update during deadreckoning
  // @Values: 0:Disabled,1:Enabled
  // @User: Standard
--]]
local dynpos_enable = Parameter("DR_DYNPOS_ENABLE") -- enable dynamic position update
local levelTime = Parameter("DR_LEVELTIME") -- level time in milliseconds
local rollTime = Parameter("DR_ROLLTIME") -- roll time in milliseconds
local rollAngle = Parameter("DR_ROLLANGLE") -- roll angle in degrees

--[[
  // @Param: DR_NEXT_MODE
  // @DisplayName: Deadreckoning Next Mode
  // @Description: Copter switch to this mode after GPS recovers or DR_FLY_TIMEOUT has elapsed.  Default is 6/RTL.  Set to -1 to return to mode used before deadreckoning was triggered
  // @Values: 2:AltHold,3:Auto,4:Guided,5:Loiter,6:RTL,7:Circle,9:Land,16:PosHold,17:Brake,20:Guided_NoGPS,21:Smart_RTL,27:Auto RTL
  // @User: Standard
--]]

local next_mode = Parameter("DR_NEXT_MODE")            -- mode to switch to after GPS recovers or timeout elapses
local wp_speed_up = Parameter("WP_SPD_UP")             -- maximum climb rate in m/s from WP_SPD_UP
local wp_accel_z = Parameter("WP_ACC_Z")               -- maximum vertical acceleration in m/s from WP_ACC_Z


-- modes deadreckoning may be activated from
-- comment out lines below to remove protection from these modes
local protected_mode_array = {
         3, -- AUTO
         4, -- GUIDED
         5, -- LOITER
         6, -- RTL
         7, -- CIRCLE
         9, -- LAND
         --11, -- DRIFT
         --16, -- POSHOLD
         17, -- BRAKE
         21, -- SMART_RTL
         27, -- AUTO_RTL
        }
function is_protected_mode()
   local curr_mode = vehicle:get_mode()
   for i = 1, #protected_mode_array do
     if curr_mode == protected_mode_array[i] then
       return true
     end
   end
   return false
end

local copter_guided_nogps_mode = 20 -- Guided_NoGPS is mode 20 on Copter
local copter_RTL_mode = 6           -- RTL is mode 6 on Copter

-- Copter mode numbers used when announcing a mode change
local mode_names = {
  [0] = "STABILIZE",
  [1] = "ACRO",
  [2] = "ALT_HOLD",
  [3] = "AUTO",
  [4] = "GUIDED",
  [5] = "LOITER",
  [6] = "RTL",
  [7] = "CIRCLE",
  [9] = "LAND",
  [11] = "DRIFT",
  [13] = "SPORT",
  [16] = "POSHOLD",
  [17] = "BRAKE",
  [20] = "GUIDED_NOGPS",
  [21] = "SMART_RTL",
  [27] = "AUTO_RTL",
}
local last_mode = nil

-- flight stage names used when announcing a stage change
-- 0 wait for good GPS and distance from home, 1 wait for bad GPS or EKF,
-- 2 level vehicle, 3 dead reckon home
local stage_names = {
  [0] = "WAIT_GPS_DIST",
  [1] = "WAIT_GPS_EKF_FAIL",
  [2] = "LEVEL_VEHICLE",
  [3] = "DEADRECKON_HOME",
}
local last_flight_stage = nil
local recovery_delay_ms = 2000      -- switch to NEXT_MODE happens this many milliseconds after GPS and EKF failsafe recover

local gps_bad = false               -- true if GPS is failing checks
local ekf_bad = false               -- true if EKF failsafe has triggered
local gps_or_ekf_bad = true         -- true if GPS and/or EKF is bad, true once both have recovered

local flight_stage = 0  -- 0. wait for good-gps and dist-from-home, 1=wait for bad gps or ekf, 2=level vehicle, 3=deadreckon home
local gps_bad_start_time_ms = 0 -- system time GPS quality went bad (0 if not bad)
local recovery_start_time_ms = 0-- system time GPS quality and EKF failsafe recovered (0 if not recovered)

local home_dist = 0     -- distance to home in meters
local home_yaw = 0      -- direction to home in degrees

local target_yaw = 0    -- deg
local climb_rate = 0    -- m/s

local stage1_flight_mode = nil  -- flight mode vehicle was in during stage1 (may be used during recovery)
local stage2_start_time_ms  -- system time stage2 started (level vehicle)
local stage3_start_time_ms  -- system time stage3 started (deadreckon home)
local last_print_ms = 0     -- pilot update timer
local interval_ms = 100     -- update at 10hz


-- wind related globals
local curr_loc = nil
local home = nil

local last_vehicle_vel = 0
local last_wind_vel = 0

local wind_direction = 0
local start_ms = millis()
local displaced = {0, 0}
function wind_compensation(home_direction)
  local now_ms = millis()
  local dt = (now_ms - start_ms) * 0.001  -- seconds

  -- wind_estimate() - Returns a Vector3f containing the current wind estimate for the vehicle
  local wind = ahrs:wind_estimate()
  local wind_speed = math.sqrt(wind:x()^2 + wind:y()^2)
  wind_direction = math.deg(math.atan(wind:y(), wind:x())) + 360

  if(gps_or_ekf_bad) then
    -- print calculating displacemant since last update
    gcs:send_text(6, "DR: calculating displacement since last update")
    displaced = {displaced[1] + wind_speed * math.cos(wind_direction - home_direction) * dt, displaced[2] + wind_speed * math.sin(wind_direction - home_direction) * dt}
  else
    displaced[0] = 0
    displaced[1] = 0
  end
  return displaced
end

function update()


  -- exit immediately if not enabled
  if (enable:get() < 1) then
    return update, 1000
  end

  -- announce flight mode whenever it changes
  local curr_mode = vehicle:get_mode()
  if curr_mode ~= last_mode then
    local mode_name = mode_names[curr_mode] or tostring(curr_mode)
    gcs:send_text(6, "DR: flight mode " .. mode_name)
    last_mode = curr_mode
  end

  -- announce flight stage whenever it changes
  if flight_stage ~= last_flight_stage then
    local stage_name = stage_names[flight_stage] or tostring(flight_stage)
    gcs:send_text(6, "DR: flight stage " .. tostring(flight_stage) .. " " .. stage_name)
    last_flight_stage = flight_stage
  end


  -- determine if progress update should be sent to user
  local now_ms = millis()
  local update_user = false
  if (now_ms - last_print_ms > 5000) then
    last_print_ms = now_ms
    update_user = true
  end

  -- local displaced = wind_compensation(wind, home_yaw)
  -- if(update_user) then
  --   gcs:send_text(5, "displaced: HOME_DIR:" .. tostring(displaced[0]) .. " WIND_DIR:" .. tostring(displaced[1]) )
  -- end  

  -- check GPS
  local gps_speed_acc = gps:speed_accuracy(gps:primary_sensor())
  if gps_speed_acc == nil then
    gps_speed_acc = 99
  end
  local gps_speed_acc_bad = ((gps_speed_acc_max:get() > 0) and (gps_speed_acc > gps_speed_acc_max:get()))
  local gps_num_sat = gps:num_sats(gps:primary_sensor())
  local gps_num_sat_bad = (gps_sat_count_min:get() > 0) and ((gps_num_sat == nil) or (gps:num_sats(gps:primary_sensor()) < gps_sat_count_min:get()))
  if gps_bad then
    -- GPS is bad, check for recovery
    if (not gps_speed_acc_bad and not gps_num_sat_bad) then
      gps_bad = false
    end
  else
    -- GPS is good, check for GPS going bad
    if (gps_speed_acc_bad or gps_num_sat_bad) then
      if (gps_bad_start_time_ms == 0) then
        -- start gps bad timer
        gps_bad_start_time_ms = now_ms
      elseif (now_ms - gps_bad_start_time_ms > gps_trigger_sec:get()) then
        gps_bad = true
      end
    end
  end

  -- check EKF failsafe
  local fs_ekf = vehicle:has_ekf_failsafed()
  if ekf_bad ~= fs_ekf then
    ekf_bad = fs_ekf
  end

  -- check for GPS and/or EKF going bad
  if not gps_or_ekf_bad and (gps_bad or ekf_bad) then
    gps_or_ekf_bad = true
    gcs:send_text(0, "DR: GPS or EKF bad")
  end

  -- check for GPS and/or EKF recovery
  if (gps_or_ekf_bad and (not gps_bad and not ekf_bad)) then
    -- start recovery timer
    if recovery_start_time_ms == 0 then
      recovery_start_time_ms = now_ms
    end
    if (now_ms - recovery_start_time_ms > recovery_delay_ms) then
      gps_or_ekf_bad = false
      recovery_start_time_ms = 0
      gcs:send_text(0, "DR: GPS and EKF recovered")
    end
  end

  -- update distance and direction home while GPS and EKF are good
  if (not gps_or_ekf_bad) then
    home = ahrs:get_home()
    -- local curr_loc = gps:location(gps:primary_sensor()) 
    curr_loc = ahrs:get_location()
    if home and curr_loc then
      home_dist = curr_loc:get_distance(home)
      home_yaw = math.deg(curr_loc:get_bearing(home))
      -- local vel = ahrs:get_velocity_NED()
      -- local vn = vel:x()
      -- local ve = vel:y()
      -- last_vehicle_vel = math.sqrt(vn * vn + ve * ve)
      -- local wind_estimate = ahrs:wind_estimate()
      -- last_wind_vel = math.sqrt(wind_estimate:x()^2 + wind_estimate:y()^2)
    elseif (update_user) then
      -- warn user of unexpected failure
      gcs:send_text(0, "DR: could not get home or vehicle location")
    end
  end





  -- reset flight_stage when disarmed
  if not arming:is_armed() then 
    flight_stage = 0
    transition_start_time_ms = 0
    return update, interval_ms
  end

  -- flight_stage 0: wait for good gps and dist-from-home
  if (flight_stage == 0) then

    -- wait for GPS and EKF to be good
    if (gps_or_ekf_bad) then
      return update, interval_ms
    end

    -- wait for distance from home to pass DR_ENABLE_DIST
    if ((home_dist > 0) and (home_dist >= enable_dist:get())) then
      gcs:send_text(5, "DR: enabled")
      flight_stage = 1
    elseif (update_user) then
      gcs:send_text(5, "DR: waiting for dist:" .. tostring(math.floor(home_dist)) .. " need:" .. tostring(math.floor(enable_dist:get())))
    end
    return update, interval_ms
  end

  -- flight_stage 1: wait for bad gps or ekf
  if (flight_stage == 1) then
    if (gps_or_ekf_bad and is_protected_mode()) then
      --send last vehicle velocity and wind velocity
      gcs:send_text(5, "DR: last vehicle velocity:" .. tostring(last_vehicle_vel) .. " last wind velocity:" .. tostring(last_wind_vel))
      -- change to Guided_NoGPS and initialise stage2
      if (vehicle:set_mode(copter_guided_nogps_mode)) then
        flight_stage = 2
        target_yaw = math.deg(ahrs:get_yaw_rad())
        stage2_start_time_ms = now_ms
      else
        -- warn user of unexpected failure
        if (update_user) then
          gcs:send_text(5, "DR: failed to change to Guided_NoGPS mode")
        end
      end
    else
      -- store flight mode (may be used during recovery)
      stage1_flight_mode = vehicle:get_mode()
    end
    return update, interval_ms
  end





  -- flight_stage 2:     -- level vehicle for time given by the user in parameter DR_LEVELTIME
  if (flight_stage == 2) then
    -- allow pilot to retake control
    if (vehicle:get_mode() ~= copter_guided_nogps_mode) then
      gcs:send_text(5, "DR: pilot retook control")
      flight_stage = 1
      return update, interval_ms
    end

    -- level vehicle for time given by the user in parameter DR_LEVELTIME
    climb_rate = 0

    if(test:get() > 0) then
      if ((now_ms - stage2_start_time_ms) <= rollTime:get()) then
        gcs:send_text(5, "DR: stopping")
        vehicle:set_target_angle_and_climbrate(20, 0, target_yaw, climb_rate, false, 0)
      end    
      if ((now_ms - stage2_start_time_ms) >= rollTime:get() + levelTime:get() - 500) then
        gcs:send_text(5, "DR: rolling")
        vehicle:set_target_angle_and_climbrate(0, roll_angle:get(), target_yaw, climb_rate, false, 0)
      end
    else
      vehicle:set_target_angle_and_climbrate(0, 0, target_yaw, climb_rate, false, 0)
    end

    if ((now_ms - stage2_start_time_ms) >= levelTime:get()) then
      flight_stage = 3
      stage3_start_time_ms = now_ms
      gcs:send_text(5, "DR: flying home")
    end
    if (update_user) then
      gcs:send_text(5, "DR: leveling vehicle")
    end
    return update, interval_ms
  end



  -- flight_stage 3: deadreckon towards home
  if (flight_stage == 3) then

    -- allow pilot to retake control
    if (vehicle:get_mode() ~= copter_guided_nogps_mode) then
      gcs:send_text(5, "DR: pilot retook control")
      flight_stage = 1
      return update, interval_ms
    end

    -- check for timeout
    local time_elapsed_ms = now_ms - stage3_start_time_ms
    local timeout = (fly_timeoout:get() > 0) and (time_elapsed_ms >= (fly_timeoout:get() * 1000))

    -- calculate climb rate in m/s
    if (fly_alt_min:get() > 0) then
      local curr_alt_below_home = ahrs:get_relative_position_D_home()
      if curr_alt_below_home then
        local target_alt_above_vehicle = fly_alt_min:get() + curr_alt_below_home
        if target_alt_above_vehicle > 0 then
          -- climb at up to 1m/s towards target above vehicle.  climb rate change is limited by WP_ACC_Z
          local climb_rate_chg_max = interval_ms * 0.001 * wp_accel_z:get()
          climb_rate = math.min(target_alt_above_vehicle * 0.1, wp_speed_up:get(), climb_rate + climb_rate_chg_max)
        end
      end
    end
    
    if (dynpos_enable:get() > 0) then
      curr_loc = ahrs:get_location()
      if curr_loc and home then
        home_yaw = math.deg(curr_loc:get_bearing(home))
      end
    end

    -- set angle target to roll 0, pitch to lean angle (note: negative is forward), yaw towards home
    if (vehicle:set_target_angle_and_climbrate(0, -math.abs(fly_angle:get()), home_yaw, climb_rate, false, 0)) then
      if (update_user) then
        local time_left_str = ""
        if (not timeout and (fly_timeoout:get() > 0)) then
          time_left_str = " t:" .. tostring(math.max(0, ((fly_timeoout:get() * 1000) - time_elapsed_ms) / 1000))
        end
        gcs:send_text(5, "DR: fly home yaw:" .. tostring(math.floor(home_yaw)) .. " pit:" .. tostring(math.floor(fly_angle:get())) .. " cr:" .. tostring(math.floor(climb_rate*10)/10) .. time_left_str)
      end
    elseif (update_user) then
      gcs:send_text(0, "DR: failed to set attitude target")
    end

    -- if GPS and EKF recover or timeout switch to next mode
    if (not gps_or_ekf_bad) or timeout then
      local recovery_mode = stage1_flight_mode
      if (next_mode:get() >= 0) then
        recovery_mode = next_mode:get()
      end
      if (recovery_mode == nil) then
        recovery_mode = copter_RTL_mode
        gcs:send_text(0, "DR: NEXT_MODE=-1 but fallingback to RTL")
      end
      -- change to DR_NEXT_MODE
      if (vehicle:set_mode(recovery_mode)) then
        flight_stage = 0
      elseif (update_user) then
        -- warn user of unexpected failure        
        gcs:send_text(0, "DR: failed to change to mode " .. tostring(recovery_mode))
      end
    end
    return update, interval_ms
  end

  -- we should never get here but just in case
  return update, interval_ms
end

if(enable:get() > 0) then
  gcs:send_text(5, "LOADED Return Towards Home Script")
end

return update()

----------------------------------------------------------------------------------------------------------------------------------------------------

-- TO DO:


--                      ** calculate distance to home left based on battery level and current consumption rate **
-- Battery (battery:)¶
-- The battery library provides access to information about the currently connected batteries on the vehicle.
--     num_instances() - Returns the number of battery instances currently available.
--     healthy( instance ) - Returns true if the requested battery instance is healthy. Healthy is considered to be ArduPilot is currently able to monitor the battery.
--     voltage( instance ) - Returns the voltage of the selected battery instance.
--     voltage_resting( instance ) - Returns the estimated battery voltage if it was not under load.
--     current_amps( instance ) - Returns the current (in Amps) that is currently being consumed by the battery, or nil if current monitoring is not available.
--     consumed_mah( instance ) - Returns the capacity (in milliamp hours) used from the battery, or nil if current monitoring is not available.
--     consumed_wh( instance ) - Returns the used watt hours from the battery, or nil if energy monitoring is not available.
--     capacity_remaining_pct( instance ) - Returns the remaining percentage of battery (from 0 to 100)
--     pack_capacity_mah( instance ) - Returns the full pack capacity (in milliamp hours) from the battery.
--     has_failsafed() - Returns true if any of the batteries being monitored have triggered a failsafe.
--     overpower_detected( instance ) - Returns true if too much power is being drawn from the battery being monitored.
--     get_temperature( instance ) - Returns the temperature of the battery in degrees Celsius if the battery supports temperature monitoring.
--     get_cycle_count( instance ) - Returns cycle count of the battery or nil if not available.

--                      ** Wind based pitch and direction compensation **
