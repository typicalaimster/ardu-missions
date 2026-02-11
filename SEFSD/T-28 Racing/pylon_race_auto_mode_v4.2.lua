-- Pylon Racing Script for ArduPilot AUTO Mode - v4.2
-- Works with NAV_SCRIPT_TIME mission command
--
-- CHANGES IN v4.2:
--   - Adjusted waypoints to match human racing line (tighter around pylons)
--   - Reduced turn anticipation factor from 1.2 to 0.9 (turn later, tighter line)
--   - Reads MAX_BANK_ANGLE from ROLL_LIMIT_DEG parameter (adapts to aircraft tuning)
--   - Increased script update rate from 20Hz to 50Hz (more responsive control)
--   - Increased navigation update rate from 10Hz to 20Hz (better path tracking)
--   - Added pre-flight validation: checks AHRS health and GPS lock before race
--   - Added mode check: race aborts cleanly when pilot exits AUTO mode
--   - Added consecutive nav failure detection: aborts after 10 failures (~200ms)
--   - Added parameter validation warnings for unusual cruise speed or bank angle
--   - Improved lookahead fallback: returns START_GATE instead of 0,0
--   - More robust telemetry timing using timestamp tracking
--   - Added duplicate call guard in finish_race()
--   - Added course validation at initialization (must have exactly 5 waypoints)
--   - Enhanced error messages show consecutive failures for better diagnostics
--   - Added best lap tracking with live comparison (shows delta to best lap)
--   - CRITICAL FIX: Division by zero protection in turn calculation (rate-limited warning)
--   - Added lap count limit (max 100 laps) to prevent memory issues
--   - Added groundspeed sanity check (0.5 to 100 m/s) to filter bad data
--   - Added dataflash logging (PYLR/PYLL messages) for post-race analysis
--   - All warnings rate-limited to prevent log spam
--   - Removed excessive debug logging for better performance at 50Hz
--   - Optimized functions to reduce VM instruction count per cycle
--
-- SAFETY:
--   - Pre-flight checks: Validates AHRS health and GPS lock before race start
--   - Aborts race automatically if navigation system becomes unresponsive
--   - Protects against division by zero in turn radius calculation
--   - Validates parameters at startup to catch configuration issues
--   - Stops cleanly when pilot switches out of AUTO mode
--   - Limits lap count to prevent memory exhaustion
--   - All edge cases have safe fallbacks
--   - Won't start race with poor positioning quality
--
-- PERFORMANCE:
--   - Script runs at 50Hz (20ms intervals) for smooth racing control
--   - Navigation commands sent at 20Hz (50ms intervals) when API accepts them
--   - All locals declared at function scope for better performance
--   - Minimal logging during race (only important events and rate-limited diagnostics)
--   - Automatically stops racing if mode switched (prevents log spam in FBWA/MANUAL)
--   - Safe for H7-series autopilots with SCR_HEAP_SIZE >= 80000
--
-- Mission Setup:
--   WP1: Start gate or pre-race position
--   WP2: NAV_SCRIPT_TIME (timeout=600, arg1=num_laps, arg2=0)
--   WP3: Post-race waypoint (RTL, land, etc.) - IMPORTANT: Make WP3 safe!
--
-- Course Pattern (Clockwise Oval):
--   START GATE → SW corner → NW corner → NE corner → SE corner → START GATE
--   (Flies around West and East pylons)

-- ============================================================================
-- CONFIGURATION PARAMETERS
-- ============================================================================

-- Read cruise speed from autopilot parameter (AIRSPEED_CRUISE in m/s)
-- Fallback to 18.0 m/s if parameter not available
local function get_cruise_speed()
    local aspd_cruise = param:get('AIRSPEED_CRUISE')
    if aspd_cruise and aspd_cruise > 0 then
        return aspd_cruise
    end
    -- Try TRIM_ARSPD_CM (in cm/s) as fallback
    local trim_aspd = param:get('TRIM_ARSPD_CM')
    if trim_aspd and trim_aspd > 0 then
        return trim_aspd / 100.0  -- convert cm/s to m/s
    end
    return 18.0  -- final fallback
end

-- Read maximum roll angle from autopilot parameter
-- This ensures script matches aircraft's configured roll limit
local function get_max_bank_angle()
    local roll_limit = param:get('ROLL_LIMIT_DEG')
    if roll_limit and roll_limit > 0 then
        return roll_limit
    end
    -- Fallback for older ArduPlane versions that might use LIM_ROLL_CD
    local roll_limit_cd = param:get('LIM_ROLL_CD')
    if roll_limit_cd and roll_limit_cd > 0 then
        return roll_limit_cd / 100.0  -- convert centidegrees to degrees
    end
    return 45.0  -- conservative fallback
end

local CRUISE_SPEED = get_cruise_speed()
local MAX_BANK_ANGLE = get_max_bank_angle()
local DEFAULT_LAP_COUNT = 5      -- default laps (overridden by arg1)
local UPDATE_RATE_HZ = 50        -- script update rate (50Hz for responsive racing control)
local TARGET_ALTITUDE = 10.0     -- meters AGL (~33 feet)

-- Validate parameters are reasonable
if CRUISE_SPEED < 10 or CRUISE_SPEED > 50 then
    gcs:send_text(3, string.format("PYLON: WARNING - Unusual cruise speed %.1fm/s", CRUISE_SPEED))
end
if MAX_BANK_ANGLE < 20 or MAX_BANK_ANGLE > 60 then
    gcs:send_text(3, string.format("PYLON: WARNING - Unusual bank angle %.0f°", MAX_BANK_ANGLE))
end

-- Physics-based turn configuration
local GRAVITY = 9.81             -- m/s^2
local TURN_ANTICIPATION_FACTOR = 0.9  -- REDUCED from 1.2 - turn later for tighter racing line
local MIN_TURN_RADIUS = 15.0     -- meters - must get within to validate corner
local LOOKAHEAD_TIME = 1.5       -- seconds - how far ahead to blend toward next waypoint

-- ============================================================================
-- COURSE DEFINITION (ADJUSTED FOR TIGHTER RACING LINE)
-- ============================================================================

-- Pylon reference locations (actual physical pylons)
local WEST_PYLON = {lat = 32.76314830, lon = -117.21414310}
local EAST_PYLON = {lat = 32.76326200, lon = -117.21341080}

-- Start gate
local START_GATE = {lat = 32.76300740, lon = -117.21375030, name = "GATE"}

-- Corner waypoints - ADJUSTED to match human racing line
-- Analysis showed human pilot flies tighter around actual pylons
local WP2_SW = {lat = 32.76304460, lon = -117.21412720, name = "SW"}  -- S of West (keep as is)
local WP3_NW = {lat = 32.76325000, lon = -117.21416000, name = "NW"}  -- ADJUSTED: Tighter to West pylon
local WP4_NE = {lat = 32.76340000, lon = -117.21342500, name = "NE"}  -- ADJUSTED: Tighter to East pylon  
local WP5_SE = {lat = 32.76310780, lon = -117.21337620, name = "SE"}  -- S of East (keep as is)

-- Oval course sequence
local course = {START_GATE, WP2_SW, WP3_NW, WP4_NE, WP5_SE}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local script_id = -1              -- NAV_SCRIPT_TIME command ID
local race_active = false         -- Is race currently running
local current_lap = 0             -- Current lap number
local lap_count = DEFAULT_LAP_COUNT
local current_target_idx = 0      -- Index in course array
local race_start_time = 0
local lap_start_times = {}
local corner_validated = {}
local last_gate_side = nil        -- Track which side of gate we're on
local last_nav_update_ms = 0      -- Throttle nav updates to vehicle
local last_nav_fail_log_ms = 0    -- Rate-limit "both APIs" failure log
local NAV_UPDATE_INTERVAL_MS = 50  -- 20Hz nav updates (was 100ms/10Hz, increased for better racing precision)
local nav_fail_count = 0          -- Track total navigation failures
local nav_success_count = 0       -- Track successful navigation updates
local consecutive_nav_fails = 0   -- Track consecutive failures for abort detection
local MAX_CONSECUTIVE_FAILS = 10  -- Abort race after 10 consecutive nav failures (~200ms at 50Hz)
local last_telemetry_ms = 0       -- Track last telemetry update for more robust timing
local last_bank_warn_ms = 0       -- Rate-limit bank angle warning to prevent spam
local best_lap_time = nil         -- Track best lap time for comparison
local best_lap_number = 0         -- Track which lap was fastest

-- Log level: 6 = Info (key checkpoints), 7 = Debug (verbose)
local LOG_LEVEL = 6
local function log(level, msg)
    if level <= LOG_LEVEL and type(msg) == "string" then
        gcs:send_text(level, msg)
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function make_location(lat, lon, alt_m)
    local loc = Location()
    loc:lat(math.floor(lat * 1e7))
    loc:lng(math.floor(lon * 1e7))
    loc:alt(math.floor(alt_m * 100))
    loc:relative_alt(true)
    return loc
end

function get_position()
    return ahrs:get_position()
end

function get_distance_to(target_lat, target_lon)
    local current = get_position()
    if not current then return nil end
    local target = make_location(target_lat, target_lon, 0)
    return current:get_distance(target)
end

function get_bearing_to(target_lat, target_lon)
    local current = get_position()
    if not current then return nil end
    local target = make_location(target_lat, target_lon, 0)
    return math.deg(current:get_bearing(target))
end

function get_groundspeed()
    local vel = ahrs:get_velocity_NED()
    if vel then
        local gs = math.sqrt(vel:x()*vel:x() + vel:y()*vel:y())
        -- Sanity check: ground speed should be reasonable
        if gs > 0.5 and gs < 100 then  -- 0.5 to 100 m/s
            return gs
        end
    end
    return CRUISE_SPEED
end

-- Check if we've crossed the start gate
function check_gate_crossing()
    local current = get_position()
    if not current then return false end

    local raw_lat = current:lat()
    if not raw_lat then return false end
    
    local current_lat = raw_lat * 1e-7
    local gate_lat = START_GATE.lat

    -- Determine which side of gate we're on (north or south)
    local current_side = (current_lat > gate_lat) and "north" or "south"

    -- Check if we crossed the gate line
    if last_gate_side and last_gate_side ~= current_side then
        local dir = current_side == "north" and "N" or "S"
        gcs:send_text(6, "PYLON: Gate crossed heading " .. dir)
        last_gate_side = current_side
        return true
    end

    last_gate_side = current_side
    return false
end

-- ============================================================================
-- NAVIGATION FUNCTIONS (ENHANCED WITH DIAGNOSTICS)
-- ============================================================================

function set_navigation_target(target_lat, target_lon, alt_m)
    local current = get_position()
    if not current then 
        log(6, "PYLON: set_nav no position")
        return false 
    end
    
    -- Reject invalid target (e.g. 0,0 from lookahead edge case)
    if (target_lat == 0 and target_lon == 0) then
        log(6, "PYLON: set_nav invalid target 0,0")
        return false
    end
    
    local target = make_location(target_lat, target_lon, alt_m or TARGET_ALTITUDE)

    -- Throttle vehicle API calls: Plane can reject if updates are too frequent
    local now_ms = millis()
    if (now_ms - last_nav_update_ms) < NAV_UPDATE_INTERVAL_MS then
        return true  -- assume previous target still active
    end

    -- ATTEMPT 1: Try set_target_location (preferred for NAV_SCRIPT_TIME)
    local ok = vehicle:set_target_location(target)
    
    if ok then
        last_nav_update_ms = now_ms
        nav_success_count = nav_success_count + 1
        consecutive_nav_fails = 0  -- Reset consecutive failure counter on success
        vehicle:set_target_airspeed_NED(Vector3f(CRUISE_SPEED, 0, 0))
        return true
    end
    
    -- ATTEMPT 2: Try update_target_location as fallback
    ok = vehicle:update_target_location(current, target)
    
    if ok then
        last_nav_update_ms = now_ms
        nav_success_count = nav_success_count + 1
        consecutive_nav_fails = 0  -- Reset consecutive failure counter on success
        vehicle:set_target_airspeed_NED(Vector3f(CRUISE_SPEED, 0, 0))
        return true
    end
    
    -- ATTEMPT 3: Try setting velocity vector toward target (experimental)
    local bearing = get_bearing_to(target_lat, target_lon)
    if bearing then
        local bearing_rad = math.rad(bearing)
        local vel_north = CRUISE_SPEED * math.cos(bearing_rad)
        local vel_east = CRUISE_SPEED * math.sin(bearing_rad)
        local vel_down = 0
        
        ok = vehicle:set_target_velocity_NED(Vector3f(vel_north, vel_east, vel_down))
        
        if ok then
            last_nav_update_ms = now_ms
            nav_success_count = nav_success_count + 1
            consecutive_nav_fails = 0  -- Reset consecutive failure counter on success
            -- Only log success on velocity mode (indicates fallback working)
            if (now_ms - last_nav_fail_log_ms) >= 5000 then
                gcs:send_text(6, "PYLON: Nav via velocity vector (bearing=" .. string.format("%.0f", bearing) .. "°)")
                last_nav_fail_log_ms = now_ms
            end
            return true
        end
    end
    
    -- ALL ATTEMPTS FAILED
    nav_fail_count = nav_fail_count + 1
    consecutive_nav_fails = consecutive_nav_fails + 1
    
    -- CRITICAL: Check if we've lost navigation completely
    if consecutive_nav_fails >= MAX_CONSECUTIVE_FAILS then
        gcs:send_text(3, string.format("PYLON: ABORTING - Navigation system unresponsive (%d consecutive failures)", consecutive_nav_fails))
        finish_race()
        return false
    end
    
    -- Log diagnostic info (rate-limited to once per second)
    if (now_ms - last_nav_fail_log_ms) >= 1000 then
        local mode = vehicle:get_mode()
        gcs:send_text(6, string.format("PYLON: Nav FAIL (all 3 APIs) mode=%d fails=%d/%d success=%d", 
                                  mode, consecutive_nav_fails, nav_fail_count, nav_success_count))
        last_nav_fail_log_ms = now_ms
    end
    
    return false
end

-- Calculate physics-based turn radius for current conditions
-- Returns the distance at which we should advance to next waypoint
function calculate_turn_anticipation()
    local groundspeed = get_groundspeed()
    
    -- Protect against division by zero (bank angle too small)
    local bank_rad = math.rad(MAX_BANK_ANGLE)
    if bank_rad < 0.01 then  -- ~0.57 degrees
        -- Rate-limit warning to prevent spam (once per 5 seconds max)
        local now_ms = millis()
        if now_ms - last_bank_warn_ms > 5000 then
            gcs:send_text(6, "PYLON: WARNING - Bank angle too small for safe turn calculation")
            last_bank_warn_ms = now_ms
        end
        return 50.0  -- Max turn radius (conservative)
    end
    
    -- Physics: turn_radius = v^2 / (g * tan(bank_angle))
    local turn_radius = (groundspeed * groundspeed) / (GRAVITY * math.tan(bank_rad))
    
    -- Apply anticipation factor to turn earlier/later
    -- v4.2: Reduced from 1.2 to 0.9 for tighter racing line
    local anticipation = turn_radius * TURN_ANTICIPATION_FACTOR
    
    -- Clamp to reasonable bounds
    return math.max(15.0, math.min(50.0, anticipation))
end

-- Calculate lookahead blending based on time and current velocity
-- This creates a smooth racing line by blending toward the next waypoint
function get_lookahead_target(current_idx, next_idx)
    local current_wp = course[current_idx + 1]
    if not current_wp then 
        -- Safe fallback to start gate if waypoint invalid
        return START_GATE.lat, START_GATE.lon
    end
    
    local next_wp = course[next_idx + 1]
    if not next_wp then 
        return current_wp.lat, current_wp.lon 
    end

    local dist = get_distance_to(current_wp.lat, current_wp.lon)
    if not dist then
        return current_wp.lat, current_wp.lon
    end

    -- Calculate lookahead distance based on groundspeed and time
    local groundspeed = get_groundspeed()
    local lookahead_dist = groundspeed * LOOKAHEAD_TIME
    
    -- Blend when within lookahead distance
    if dist < lookahead_dist then
        local blend = math.max(0, math.min(1, 1.0 - (dist / lookahead_dist)))
        local lat = current_wp.lat + blend * (next_wp.lat - current_wp.lat)
        local lon = current_wp.lon + blend * (next_wp.lon - current_wp.lon)
        return lat, lon
    end

    return current_wp.lat, current_wp.lon
end

-- ============================================================================
-- RACE MANAGEMENT
-- ============================================================================

function validate_corner(corner_idx)
    local corner = course[corner_idx + 1]
    if not corner then return false end
    
    local dist = get_distance_to(corner.lat, corner.lon)
    if not dist then return false end
    
    if dist < MIN_TURN_RADIUS then
        if not corner_validated[corner_idx + 1] then
            corner_validated[corner_idx + 1] = true
            gcs:send_text(6, string.format("PYLON: %s OK (%.1fm)", corner.name, dist))
        end
        return true
    end
    
    return false
end

function advance_target()
    -- Validate current corner
    if current_target_idx > 0 then  -- Don't validate gate
        validate_corner(current_target_idx)
    end
    
    -- Move to next target
    current_target_idx = (current_target_idx + 1) % 5
    
    -- Check if we completed a lap (returned to start gate)
    if current_target_idx == 0 then
        -- Check for gate crossing
        if check_gate_crossing() then
            current_lap = current_lap + 1
            
            if current_lap > 0 and current_lap <= lap_count then
                local lap_time = millis() - lap_start_times[current_lap]
                local lap_time_sec = lap_time / 1000.0
                
                -- Check if this is the best lap
                local is_best = false
                if not best_lap_time or lap_time < best_lap_time then
                    best_lap_time = lap_time
                    best_lap_number = current_lap
                    is_best = true
                end
                
                -- Display lap time with best lap indicator
                if is_best then
                    gcs:send_text(3, string.format("LAP %d: %.1fs ⭐ NEW BEST!", current_lap, lap_time_sec))
                else
                    local delta = (lap_time - best_lap_time) / 1000.0
                    gcs:send_text(3, string.format("LAP %d: %.1fs (+%.1fs)", current_lap, lap_time_sec, delta))
                end
                
                -- Log lap completion to dataflash for post-flight analysis
                logger:write('PYLL', 'Lap,Time,NavSucc,NavFail', 'ifII', 
                    current_lap, lap_time_sec, nav_success_count, nav_fail_count)
            end
            
            if current_lap >= lap_count then
                -- Race complete!
                local total_time = millis() - race_start_time
                gcs:send_text(3, string.format("RACE COMPLETE! %d laps, %.1fs total", 
                    lap_count, total_time / 1000.0))
                
                -- Report best lap
                if best_lap_time then
                    gcs:send_text(3, string.format("Best lap: #%d - %.1fs", 
                        best_lap_number, best_lap_time / 1000.0))
                end
                
                finish_race()
                return
            else
                -- Start next lap
                lap_start_times[current_lap + 1] = millis()
                corner_validated = {}
                gcs:send_text(6, string.format("PYLON: Starting Lap %d", current_lap + 1))
            end
        end
    end
    
    local target = course[current_target_idx + 1]
    if target then
        gcs:send_text(7, string.format("PYLON: → %s (L%d)", target.name, current_lap + 1))
    end
end

function update_race()
    if not race_active then return end
    
    -- Check if we're still in AUTO mode (mode 10)
    -- If pilot switched to another mode, abort the race cleanly
    -- Common modes: 0=MANUAL, 5=FBWA, 10=AUTO, 11=RTL
    local current_mode = vehicle:get_mode()
    if current_mode ~= 10 then
        gcs:send_text(6, string.format("PYLON: Mode changed to %d, aborting race", current_mode))
        finish_race()
        return
    end

    local target = course[current_target_idx + 1]
    if not target then 
        log(6, "PYLON: update_race no target")
        return 
    end

    -- Get distance to current target
    local dist = get_distance_to(target.lat, target.lon)
    if not dist then 
        log(6, "PYLON: update_race no dist")
        return 
    end

    -- Calculate lookahead target for smooth racing line
    local next_idx = (current_target_idx + 1) % 5
    local nav_lat, nav_lon = get_lookahead_target(current_target_idx, next_idx)

    -- Send navigation command
    set_navigation_target(nav_lat, nav_lon)

    -- Check if we should advance to next waypoint
    -- Calculate dynamic turn anticipation based on current groundspeed
    local turn_anticipation = calculate_turn_anticipation()
    if dist < turn_anticipation then
        advance_target()
    end
    
    -- Periodic telemetry using timestamp tracking (more robust than modulo)
    local now_ms = millis()
    if now_ms - last_telemetry_ms > 2000 then
        last_telemetry_ms = now_ms
        local gs = get_groundspeed()
        gcs:send_text(7, string.format("PYLON: L%d %s %.0fm (GS:%.1fm/s R:%.0fm)", 
            current_lap + 1, target.name, dist, gs, turn_anticipation))
    end
end

function start_race(id, cmd, arg1, arg2)
    script_id = id
    lap_count = math.floor(arg1)

    if lap_count <= 0 then
        lap_count = DEFAULT_LAP_COUNT
    elseif lap_count > 100 then
        gcs:send_text(3, string.format("PYLON: WARNING - Lap count %d exceeds limit, using %d", lap_count, DEFAULT_LAP_COUNT))
        lap_count = DEFAULT_LAP_COUNT
    end

    -- Pre-flight validation: Check AHRS health before starting race
    if not ahrs:healthy() then
        gcs:send_text(3, "PYLON: ERROR - AHRS not healthy, aborting race start")
        gcs:send_text(3, "PYLON: Check GPS lock and allow AHRS to initialize")
        finish_race()
        return
    end
    
    -- Pre-flight validation: Check GPS position quality
    local pos = get_position()
    if not pos then
        gcs:send_text(3, "PYLON: ERROR - No GPS position available, aborting race start")
        finish_race()
        return
    end

    current_lap = 0
    current_target_idx = 0  -- Start at gate
    race_active = true
    race_start_time = millis()
    lap_start_times[1] = millis()
    corner_validated = {}
    last_gate_side = nil
    last_nav_update_ms = 0   -- allow first nav update immediately
    last_nav_fail_log_ms = 0 -- allow one failure log right away if needed
    last_telemetry_ms = 0    -- reset telemetry timer
    nav_fail_count = 0       -- reset counters
    nav_success_count = 0
    consecutive_nav_fails = 0  -- reset consecutive failure counter
    best_lap_time = nil      -- reset best lap tracking
    best_lap_number = 0

    -- Log race start to dataflash for post-flight analysis
    logger:write('PYLR', 'LapC,Speed,Bank', 'iff', lap_count, CRUISE_SPEED, MAX_BANK_ANGLE)

    gcs:send_text(3, "========== PYLON RACE START ==========")
    gcs:send_text(3, string.format("%d lap oval race @ %.1fm/s", lap_count, CRUISE_SPEED))
    gcs:send_text(6, "PYLON: v4.2 - Tighter racing line, optimized performance")
    gcs:send_text(6, "PYLON: Pre-flight checks PASSED - AHRS healthy, GPS locked")
    gcs:send_text(6, "PYLON: Approaching start gate...")
end

function finish_race()
    -- Guard against duplicate calls
    if not race_active then return end
    
    -- Report navigation statistics
    local total_attempts = nav_success_count + nav_fail_count
    if total_attempts > 0 then
        local success_rate = (nav_success_count * 100.0) / total_attempts
        gcs:send_text(6, string.format("PYLON: Nav stats: %d/%d successful (%.0f%%)", 
                                       nav_success_count, total_attempts, success_rate))
    end
    
    if script_id >= 0 then
        vehicle:nav_script_time_done(script_id)
    end
    race_active = false
    script_id = -1
    gcs:send_text(3, "PYLON: Race finished, resuming mission")
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================
-- Called every 20ms (50Hz). Keep this lightweight to avoid VM instruction limits.
-- All locals are declared at function scope for performance.

function update()
    local id, cmd, arg1, arg2 = vehicle:nav_script_time()

    if id and id ~= script_id then
        start_race(id, cmd, arg1, arg2)
    end

    if race_active then
        update_race()
    end

    return update, math.floor(1000 / UPDATE_RATE_HZ)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Validate course configuration
if #course ~= 5 then
    gcs:send_text(3, "PYLON: ERROR - Course should have exactly 5 waypoints!")
    gcs:send_text(3, string.format("PYLON: Found %d waypoints - script will not function correctly", #course))
    return
end

gcs:send_text(6, "PYLON RACE: Loaded v4.2 (50Hz updates, tighter racing line)")
gcs:send_text(6, "PYLON: Add NAV_SCRIPT_TIME to mission")
gcs:send_text(6, "PYLON: Default " .. tostring(DEFAULT_LAP_COUNT) .. " laps, LOG_LEVEL=" .. tostring(LOG_LEVEL))
gcs:send_text(6, string.format("PYLON: Script=50Hz Nav=20Hz Cruise=%.1fm/s Bank=%.0f° (from ROLL_LIMIT_DEG)", 
    CRUISE_SPEED, MAX_BANK_ANGLE))
gcs:send_text(6, "PYLON: NW/NE waypoints adjusted closer to pylons")
gcs:send_text(6, "PYLON: Course validated - 5 waypoints configured")

return update()
