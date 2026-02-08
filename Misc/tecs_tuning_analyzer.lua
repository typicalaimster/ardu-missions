-- TECS Tuning Analyzer for ArduPilot
-- Based on: https://ardupilot.org/plane/docs/tecs-total-energy-control-system-for-speed-height-tuning-guide.html
--
-- SAFETY: Only operates at 50+ feet altitude
-- READ-ONLY: Monitors performance and logs suggestions, does not change parameters
--
-- Usage:
--   1. Load script and fly in AUTO, LOITER, RTL, or GUIDED mode
--   2. Script will analyze TECS performance during altitude changes
--   3. Check GCS messages and log file for recommendations
--
-- Tests Performed:
--   - Climb test (verify THR_MAX, PTCH_LIM_MAX_DEG, TECS_CLMB_MAX)
--   - Descent test (verify PTCH_LIM_MIN_DEG, TECS_SINK_MAX)
--   - Level flight (verify TRIM_THROTTLE)
--   - Height/speed oscillation detection

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local MIN_SAFE_ALTITUDE_M = 15.24   -- 50 feet minimum for testing
local UPDATE_RATE_HZ = 4            -- 4Hz update rate
local TEST_INTERVAL_MS = 5000       -- Log status every 5 seconds
local CLIMB_THRESHOLD_M = 50        -- Minimum altitude change to analyze
local DESCENT_THRESHOLD_M = -50     -- Minimum descent to analyze

-- ============================================================================
-- PARAMETER CACHE
-- ============================================================================

local params = {}
local params_loaded = false

function load_parameters()
    -- Throttle parameters
    params.THR_MAX = param:get('THR_MAX') or 75
    params.THR_MIN = param:get('THR_MIN') or 0
    params.TRIM_THROTTLE = param:get('TRIM_THROTTLE') or 45
    
    -- Pitch limits
    params.PTCH_LIM_MAX_DEG = param:get('PTCH_LIM_MAX_DEG') or 20
    params.PTCH_LIM_MIN_DEG = param:get('PTCH_LIM_MIN_DEG') or -25
    
    -- Airspeed parameters
    params.AIRSPEED_CRUISE = param:get('AIRSPEED_CRUISE') or 15
    params.AIRSPEED_MIN = param:get('ARSPD_FBW_MIN') or 10
    params.AIRSPEED_MAX = param:get('ARSPD_FBW_MAX') or 20
    params.ARSPD_USE = param:get('ARSPD_USE') or 0
    
    -- TECS parameters
    params.TECS_CLMB_MAX = param:get('TECS_CLMB_MAX') or 5
    params.TECS_SINK_MIN = param:get('TECS_SINK_MIN') or 2
    params.TECS_SINK_MAX = param:get('TECS_SINK_MAX') or 5
    params.TECS_TIME_CONST = param:get('TECS_TIME_CONST') or 5
    params.TECS_THR_DAMP = param:get('TECS_THR_DAMP') or 0.5
    params.TECS_INTEG_GAIN = param:get('TECS_INTEG_GAIN') or 0.3
    params.TECS_VERT_ACC = param:get('TECS_VERT_ACC') or 7
    params.TECS_RLL2THR = param:get('TECS_RLL2THR') or 10
    params.TECS_SPDWEIGHT = param:get('TECS_SPDWEIGHT') or 1.0
    params.TECS_PTCH_DAMP = param:get('TECS_PTCH_DAMP') or 0
    params.TECS_PITCH_MAX = param:get('TECS_PITCH_MAX') or 15
    params.TECS_PITCH_MIN = param:get('TECS_PITCH_MIN') or -5
    
    params_loaded = true
    
    gcs:send_text(6, "TECS: Parameters loaded")
    gcs:send_text(6, string.format("TECS: Airspeed sensor: %s", 
        params.ARSPD_USE > 0 and "YES" or "NO"))
end

-- ============================================================================
-- STATE TRACKING
-- ============================================================================

local test_state = {
    active = false,
    last_status_time = 0,
    
    -- Altitude tracking
    start_alt = 0,
    min_alt = 0,
    max_alt = 0,
    target_alt = 0,
    last_alt = 0,
    
    -- Climb test data
    climb_samples = {},
    climb_test_active = false,
    climb_start_time = 0,
    
    -- Descent test data
    descent_samples = {},
    descent_test_active = false,
    descent_start_time = 0,
    
    -- Level flight tracking
    level_samples = {},
    level_test_active = false,
    
    -- Oscillation detection
    alt_history = {},
    spd_history = {},
    oscillation_count = 0
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function get_altitude_agl()
    local terrain_alt = terrain:height_above_terrain()
    if terrain_alt then
        return terrain_alt
    end
    -- Fallback to relative altitude
    local pos = ahrs:get_position()
    if pos then
        return pos:alt() * 0.01  -- cm to meters
    end
    return 0
end

function get_altitude_target()
    -- Get target altitude from navigation controller
    local target_alt_cm = vehicle:get_target_location()
    if target_alt_cm then
        local pos = ahrs:get_position()
        if pos then
            return target_alt_cm:alt() * 0.01  -- cm to meters
        end
    end
    return nil
end

function get_airspeed()
    local aspd = ahrs:get_airspeed()
    if aspd and params.ARSPD_USE > 0 then
        return aspd
    end
    -- Return groundspeed as fallback
    local vel = ahrs:get_velocity_NED()
    if vel then
        return math.sqrt(vel:x()*vel:x() + vel:y()*vel:y())
    end
    return nil
end

function get_pitch_deg()
    local pitch, roll, yaw = ahrs:get_euler_angles()
    if pitch then
        return math.deg(pitch)
    end
    return nil
end

function get_throttle_pct()
    return SRV_Channels:get_output_scaled(70)  -- Channel 70 is throttle
end

function get_climb_rate()
    local vel = ahrs:get_velocity_NED()
    if vel then
        return -vel:z()  -- NED: negative Z is up
    end
    return nil
end

function is_mode_supported()
    local mode = vehicle:get_mode()
    -- AUTO=10, RTL=11, LOITER=12, GUIDED=15
    return mode == 10 or mode == 11 or mode == 12 or mode == 15
end

-- ============================================================================
-- ANALYSIS FUNCTIONS
-- ============================================================================

function analyze_climb_performance()
    if #test_state.climb_samples < 10 then
        return  -- Need more samples
    end
    
    local avg_throttle = 0
    local avg_pitch = 0
    local avg_airspeed = 0
    local avg_climb_rate = 0
    local max_throttle = 0
    local max_pitch = 0
    local min_airspeed = 999
    
    for _, sample in ipairs(test_state.climb_samples) do
        avg_throttle = avg_throttle + sample.throttle
        avg_pitch = avg_pitch + sample.pitch
        avg_airspeed = avg_airspeed + sample.airspeed
        avg_climb_rate = avg_climb_rate + sample.climb_rate
        
        max_throttle = math.max(max_throttle, sample.throttle)
        max_pitch = math.max(max_pitch, sample.pitch)
        min_airspeed = math.min(min_airspeed, sample.airspeed)
    end
    
    local n = #test_state.climb_samples
    avg_throttle = avg_throttle / n
    avg_pitch = avg_pitch / n
    avg_airspeed = avg_airspeed / n
    avg_climb_rate = avg_climb_rate / n
    
    -- Generate recommendations
    gcs:send_text(3, "========== CLIMB TEST RESULTS ==========")
    gcs:send_text(6, string.format("TECS: Avg climb rate: %.1f m/s (max param: %.1f)", 
        avg_climb_rate, params.TECS_CLMB_MAX))
    gcs:send_text(6, string.format("TECS: Avg throttle: %.0f%% (max: %.0f%%, limit: %.0f%%)", 
        avg_throttle, max_throttle, params.THR_MAX))
    gcs:send_text(6, string.format("TECS: Avg pitch: %.1f° (max: %.1f°, limit: %.1f°)", 
        avg_pitch, max_pitch, params.PTCH_LIM_MAX_DEG))
    gcs:send_text(6, string.format("TECS: Avg airspeed: %.1f m/s (min: %.1f, cruise: %.1f)", 
        avg_airspeed, min_airspeed, params.AIRSPEED_CRUISE))
    
    -- Analyze and recommend
    if max_throttle >= params.THR_MAX - 5 then
        if min_airspeed < params.AIRSPEED_CRUISE - 2 then
            gcs:send_text(4, "RECOMMEND: Reduce TECS_CLMB_MAX or increase THR_MAX")
            gcs:send_text(6, "REASON: Throttle at limit, airspeed dropping")
        end
    end
    
    if max_pitch >= params.PTCH_LIM_MAX_DEG - 2 then
        gcs:send_text(4, "RECOMMEND: Increase PTCH_LIM_MAX_DEG or reduce TECS_CLMB_MAX")
        gcs:send_text(6, "REASON: Pitch angle at limit")
    end
    
    if avg_throttle < params.THR_MAX * 0.7 then
        gcs:send_text(5, "SUGGEST: Could increase TECS_CLMB_MAX")
        gcs:send_text(6, "REASON: Throttle well below limit, climb performance available")
    end
    
    if avg_climb_rate > params.TECS_CLMB_MAX * 1.1 then
        gcs:send_text(4, "RECOMMEND: Increase TECS_CLMB_MAX to %.1f", avg_climb_rate * 0.9)
        gcs:send_text(6, "REASON: Achieving higher climb rate than parameter")
    end
    
    gcs:send_text(3, "========================================")
end

function analyze_descent_performance()
    if #test_state.descent_samples < 10 then
        return
    end
    
    local avg_throttle = 0
    local avg_pitch = 0
    local avg_airspeed = 0
    local avg_sink_rate = 0
    local min_throttle = 999
    local min_pitch = 999
    local max_airspeed = 0
    
    for _, sample in ipairs(test_state.descent_samples) do
        avg_throttle = avg_throttle + sample.throttle
        avg_pitch = avg_pitch + sample.pitch
        avg_airspeed = avg_airspeed + sample.airspeed
        avg_sink_rate = avg_sink_rate + math.abs(sample.climb_rate)
        
        min_throttle = math.min(min_throttle, sample.throttle)
        min_pitch = math.min(min_pitch, sample.pitch)
        max_airspeed = math.max(max_airspeed, sample.airspeed)
    end
    
    local n = #test_state.descent_samples
    avg_throttle = avg_throttle / n
    avg_pitch = avg_pitch / n
    avg_airspeed = avg_airspeed / n
    avg_sink_rate = avg_sink_rate / n
    
    gcs:send_text(3, "========== DESCENT TEST RESULTS ==========")
    gcs:send_text(6, string.format("TECS: Avg sink rate: %.1f m/s (max param: %.1f)", 
        avg_sink_rate, params.TECS_SINK_MAX))
    gcs:send_text(6, string.format("TECS: Avg throttle: %.0f%% (min: %.0f%%, limit: %.0f%%)", 
        avg_throttle, min_throttle, params.THR_MIN))
    gcs:send_text(6, string.format("TECS: Avg pitch: %.1f° (min: %.1f°, limit: %.1f°)", 
        avg_pitch, min_pitch, params.PTCH_LIM_MIN_DEG))
    gcs:send_text(6, string.format("TECS: Avg airspeed: %.1f m/s (max: %.1f, limit: %.1f)", 
        avg_airspeed, max_airspeed, params.AIRSPEED_MAX))
    
    if max_airspeed > params.AIRSPEED_MAX - 2 then
        gcs:send_text(4, "RECOMMEND: Reduce TECS_SINK_MAX")
        gcs:send_text(6, "REASON: Airspeed approaching limit during descent")
    end
    
    if min_pitch <= params.PTCH_LIM_MIN_DEG + 2 then
        gcs:send_text(4, "RECOMMEND: Increase PTCH_LIM_MIN_DEG (less negative) or reduce TECS_SINK_MAX")
        gcs:send_text(6, "REASON: Pitch angle at limit")
    end
    
    if avg_sink_rate > params.TECS_SINK_MAX * 1.1 then
        gcs:send_text(4, "RECOMMEND: Increase TECS_SINK_MAX to %.1f", avg_sink_rate * 0.9)
        gcs:send_text(6, "REASON: Achieving higher sink rate than parameter")
    end
    
    gcs:send_text(3, "==========================================")
end

function analyze_level_flight()
    if #test_state.level_samples < 20 then
        return
    end
    
    local avg_throttle = 0
    local throttle_variance = 0
    
    for _, sample in ipairs(test_state.level_samples) do
        avg_throttle = avg_throttle + sample.throttle
    end
    avg_throttle = avg_throttle / #test_state.level_samples
    
    for _, sample in ipairs(test_state.level_samples) do
        local diff = sample.throttle - avg_throttle
        throttle_variance = throttle_variance + (diff * diff)
    end
    throttle_variance = math.sqrt(throttle_variance / #test_state.level_samples)
    
    gcs:send_text(3, "========== LEVEL FLIGHT RESULTS ==========")
    gcs:send_text(6, string.format("TECS: Avg throttle: %.1f%% (param: %.1f%%)", 
        avg_throttle, params.TRIM_THROTTLE))
    gcs:send_text(6, string.format("TECS: Throttle std dev: %.1f%%", throttle_variance))
    
    local diff = math.abs(avg_throttle - params.TRIM_THROTTLE)
    if diff > 5 then
        gcs:send_text(4, string.format("RECOMMEND: Set TRIM_THROTTLE to %.0f", avg_throttle))
        gcs:send_text(6, "REASON: Average throttle differs from trim setting")
    end
    
    if throttle_variance > 10 then
        gcs:send_text(5, "SUGGEST: Check TECS_TIME_CONST and TECS_INTEG_GAIN")
        gcs:send_text(6, "REASON: High throttle variation in level flight")
    end
    
    gcs:send_text(3, "==========================================")
end

function check_oscillations()
    -- Check for altitude oscillations
    if #test_state.alt_history >= 8 then
        local oscillating = true
        for i = 1, #test_state.alt_history - 2, 2 do
            if not ((test_state.alt_history[i] < test_state.alt_history[i+1] and 
                    test_state.alt_history[i+1] > test_state.alt_history[i+2]) or
                   (test_state.alt_history[i] > test_state.alt_history[i+1] and 
                    test_state.alt_history[i+1] < test_state.alt_history[i+2])) then
                oscillating = false
                break
            end
        end
        
        if oscillating then
            test_state.oscillation_count = test_state.oscillation_count + 1
            if test_state.oscillation_count > 3 then
                gcs:send_text(4, "WARNING: Height oscillation detected")
                gcs:send_text(6, "SUGGEST: Increase TECS_TIME_CONST by 1")
                gcs:send_text(6, "OR: Increase TECS_PTCH_DAMP by 0.1")
                test_state.oscillation_count = 0  -- Don't spam
            end
        else
            test_state.oscillation_count = 0
        end
    end
end

-- ============================================================================
-- DATA COLLECTION
-- ============================================================================

function collect_sample()
    local alt = get_altitude_agl()
    local airspeed = get_airspeed()
    local pitch = get_pitch_deg()
    local throttle = get_throttle_pct()
    local climb_rate = get_climb_rate()
    local target_alt = get_altitude_target()
    
    if not (alt and airspeed and pitch and throttle and climb_rate) then
        return false
    end
    
    local sample = {
        timestamp = millis(),
        altitude = alt,
        airspeed = airspeed,
        pitch = pitch,
        throttle = throttle,
        climb_rate = climb_rate,
        target_alt = target_alt or test_state.target_alt
    }
    
    -- Track altitude history for oscillation detection
    table.insert(test_state.alt_history, alt)
    if #test_state.alt_history > 10 then
        table.remove(test_state.alt_history, 1)
    end
    
    -- Update min/max
    test_state.min_alt = math.min(test_state.min_alt, alt)
    test_state.max_alt = math.max(test_state.max_alt, alt)
    
    -- Detect climb test
    if climb_rate > 2.0 and alt > MIN_SAFE_ALTITUDE_M then
        if not test_state.climb_test_active then
            test_state.climb_test_active = true
            test_state.climb_start_time = millis()
            test_state.climb_samples = {}
            gcs:send_text(6, "TECS: Climb test started")
        end
        table.insert(test_state.climb_samples, sample)
    elseif test_state.climb_test_active and climb_rate < 1.0 then
        test_state.climb_test_active = false
        gcs:send_text(6, "TECS: Climb test ended")
        analyze_climb_performance()
        test_state.climb_samples = {}
    end
    
    -- Detect descent test
    if climb_rate < -2.0 and alt > MIN_SAFE_ALTITUDE_M then
        if not test_state.descent_test_active then
            test_state.descent_test_active = true
            test_state.descent_start_time = millis()
            test_state.descent_samples = {}
            gcs:send_text(6, "TECS: Descent test started")
        end
        table.insert(test_state.descent_samples, sample)
    elseif test_state.descent_test_active and climb_rate > -1.0 then
        test_state.descent_test_active = false
        gcs:send_text(6, "TECS: Descent test ended")
        analyze_descent_performance()
        test_state.descent_samples = {}
    end
    
    -- Collect level flight data
    if math.abs(climb_rate) < 0.5 and alt > MIN_SAFE_ALTITUDE_M then
        if not test_state.level_test_active then
            test_state.level_test_active = true
            test_state.level_samples = {}
            gcs:send_text(6, "TECS: Level flight monitoring started")
        end
        table.insert(test_state.level_samples, sample)
        if #test_state.level_samples > 100 then
            table.remove(test_state.level_samples, 1)  -- Keep last 100
        end
    elseif test_state.level_test_active and math.abs(climb_rate) > 1.0 then
        test_state.level_test_active = false
        if #test_state.level_samples > 20 then
            analyze_level_flight()
        end
    end
    
    test_state.last_alt = alt
    return true
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================

function update()
    local now = millis()
    
    -- Load parameters on first run
    if not params_loaded then
        load_parameters()
        return update, 1000
    end
    
    -- Check if we're in a supported mode
    if not is_mode_supported() then
        if test_state.active then
            test_state.active = false
            gcs:send_text(6, "TECS: Analysis paused (unsupported mode)")
        end
        return update, 1000
    end
    
    -- Check altitude safety
    local alt = get_altitude_agl()
    if not alt or alt < MIN_SAFE_ALTITUDE_M then
        if test_state.active then
            test_state.active = false
            gcs:send_text(5, string.format("TECS: Analysis paused (below %.0fm)", MIN_SAFE_ALTITUDE_M))
        end
        return update, 1000
    end
    
    -- Start analysis if not active
    if not test_state.active then
        test_state.active = true
        test_state.start_alt = alt
        test_state.min_alt = alt
        test_state.max_alt = alt
        gcs:send_text(6, "TECS: Analysis active")
    end
    
    -- Collect data sample
    collect_sample()
    
    -- Check for oscillations
    check_oscillations()
    
    -- Periodic status update
    if now - test_state.last_status_time > TEST_INTERVAL_MS then
        test_state.last_status_time = now
        
        local climb_rate = get_climb_rate()
        local airspeed = get_airspeed()
        
        if climb_rate and airspeed then
            gcs:send_text(7, string.format("TECS: Alt=%.0fm Spd=%.1fm/s Clmb=%.1fm/s", 
                alt, airspeed, climb_rate))
        end
        
        -- Provide summary if we have level flight data
        if test_state.level_test_active and #test_state.level_samples > 20 then
            local throttle_sum = 0
            for _, s in ipairs(test_state.level_samples) do
                throttle_sum = throttle_sum + s.throttle
            end
            local avg_thr = throttle_sum / #test_state.level_samples
            gcs:send_text(7, string.format("TECS: Level flight throttle avg=%.0f%% (trim=%.0f%%)", 
                avg_thr, params.TRIM_THROTTLE))
        end
    end
    
    return update, math.floor(1000 / UPDATE_RATE_HZ)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

gcs:send_text(6, "========================================")
gcs:send_text(6, "TECS TUNING ANALYZER v1.0")
gcs:send_text(6, "READ-ONLY: Monitors and recommends only")
gcs:send_text(6, string.format("Safety: Min altitude %.0fm (%.0fft)", 
    MIN_SAFE_ALTITUDE_M, MIN_SAFE_ALTITUDE_M * 3.28084))
gcs:send_text(6, "Fly altitude changes in AUTO/LOITER/RTL")
gcs:send_text(6, "========================================")

return update()
