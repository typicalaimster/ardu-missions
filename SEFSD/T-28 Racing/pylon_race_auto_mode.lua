-- Pylon Racing Script for ArduPilot AUTO Mode
-- Works with NAV_SCRIPT_TIME mission command
--
-- Mission Setup:
--   WP1: Start gate or pre-race position
--   WP2: NAV_SCRIPT_TIME (timeout=600, arg1=num_laps, arg2=0)
--   WP3: Post-race waypoint (RTL, land, etc.)
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

local CRUISE_SPEED = get_cruise_speed()
local DEFAULT_LAP_COUNT = 5      -- default laps (overridden by arg1)
local UPDATE_RATE_HZ = 20        -- script update rate
local TARGET_ALTITUDE = 9.13     -- meters AGL (30 feet)

-- Turn point configuration
local TURN_RADIUS = 20.0         -- meters - advance when within this distance
local MIN_TURN_RADIUS = 15.0     -- meters - must get within to validate
local LOOKAHEAD_DIST = 35.0      -- meters - start blending to next corner

-- ============================================================================
-- COURSE DEFINITION
-- ============================================================================

-- Pylon reference locations
local WEST_PYLON = {lat = 32.76314830, lon = -117.21414310}
local EAST_PYLON = {lat = 32.76326200, lon = -117.21341080}

-- Start gate
local START_GATE = {lat = 32.76300740, lon = -117.21375030, name = "GATE"}

-- Corner waypoints (from your current mission)
local WP2_SW = {lat = 32.76304460, lon = -117.21412720, name = "SW"}  -- S of West
local WP3_NW = {lat = 32.76338970, lon = -117.21420500, name = "NW"}  -- N of West  
local WP4_NE = {lat = 32.76351600, lon = -117.21344860, name = "NE"}  -- N of East
local WP6_SE = {lat = 32.76310780, lon = -117.21337620, name = "SE"}  -- S of East

-- Oval course sequence
local course = {START_GATE, WP2_SW, WP3_NW, WP4_NE, WP6_SE}

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
        return math.sqrt(vel:x()*vel:x() + vel:y()*vel:y())
    end
    return CRUISE_SPEED
end

-- Check if we've crossed the start gate
function check_gate_crossing()
    local current = get_position()
    if not current then return false end
    
    local current_lat = current:lat() * 1e-7
    local gate_lat = START_GATE.lat
    
    -- Determine which side of gate we're on (north or south)
    local current_side = (current_lat > gate_lat) and "north" or "south"
    
    -- Check if we crossed the gate line
    if last_gate_side and last_gate_side ~= current_side then
        local crossing_direction = (current_side == "north") and "N" or "S"
        gcs:send_text(6, string.format("PYLON: Gate crossed heading %s", crossing_direction))
        last_gate_side = current_side
        return true
    end
    
    last_gate_side = current_side
    return false
end

-- ============================================================================
-- NAVIGATION FUNCTIONS
-- ============================================================================

function set_navigation_target(target_lat, target_lon, alt_m)
    local target = make_location(target_lat, target_lon, alt_m or TARGET_ALTITUDE)
    
    if not vehicle:update_target_location(target) then
        gcs:send_text(6, "PYLON: Nav update failed")
        return false
    end
    
    vehicle:set_target_airspeed_NED(Vector3f(CRUISE_SPEED, 0, 0))
    return true
end

-- Calculate lookahead blending
function get_lookahead_target(current_idx, next_idx)
    local current_wp = course[current_idx + 1]
    local next_wp = course[next_idx + 1]
    
    if not current_wp or not next_wp then
        return current_wp.lat, current_wp.lon
    end
    
    local dist = get_distance_to(current_wp.lat, current_wp.lon)
    if not dist then
        return current_wp.lat, current_wp.lon
    end
    
    -- Blend when within lookahead distance
    if dist < LOOKAHEAD_DIST then
        local blend = math.max(0, math.min(1, 1.0 - (dist / LOOKAHEAD_DIST)))
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
    local prev_idx = current_target_idx
    current_target_idx = (current_target_idx + 1) % 5
    
    -- Check if we completed a lap (returned to start gate)
    if current_target_idx == 0 then
        -- Check for gate crossing
        if check_gate_crossing() then
            current_lap = current_lap + 1
            
            if current_lap > 0 and current_lap <= lap_count then
                local lap_time = millis() - lap_start_times[current_lap]
                gcs:send_text(3, string.format("LAP %d: %.1fs", current_lap, lap_time / 1000.0))
            end
            
            if current_lap >= lap_count then
                -- Race complete!
                local total_time = millis() - race_start_time
                gcs:send_text(3, string.format("RACE COMPLETE! %d laps, %.1fs total", 
                    lap_count, total_time / 1000.0))
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
    
    local target = course[current_target_idx + 1]
    if not target then return end
    
    -- Get distance to current target
    local dist = get_distance_to(target.lat, target.lon)
    if not dist then return end
    
    -- Calculate lookahead navigation point
    local next_idx = (current_target_idx + 1) % 5
    local nav_lat, nav_lon = get_lookahead_target(current_target_idx, next_idx)
    
    -- Update navigation
    set_navigation_target(nav_lat, nav_lon)
    
    -- Check if reached target
    if dist < TURN_RADIUS then
        advance_target()
    end
    
    -- Periodic telemetry
    if millis() % 2000 < 100 then
        gcs:send_text(7, string.format("PYLON: L%d %s %.0fm", 
            current_lap + 1, target.name, dist))
    end
end

function start_race(id, cmd, arg1, arg2)
    script_id = id
    lap_count = math.floor(arg1)
    
    if lap_count <= 0 then
        lap_count = DEFAULT_LAP_COUNT
    end
    
    current_lap = 0
    current_target_idx = 0  -- Start at gate
    race_active = true
    race_start_time = millis()
    lap_start_times[1] = millis()
    corner_validated = {}
    last_gate_side = nil
    
    gcs:send_text(3, "========== PYLON RACE START ==========")
    gcs:send_text(3, string.format("%d lap oval race @ %.1fm/s", lap_count, CRUISE_SPEED))
    gcs:send_text(6, "PYLON: Approaching start gate...")
end

function finish_race()
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

function update()
    -- Check if AUTO mode has a NAV_SCRIPT_TIME command for us
    local id, cmd, arg1, arg2 = vehicle:nav_script_time()
    
    if id and id ~= script_id then
        -- New NAV_SCRIPT_TIME command detected
        start_race(id, cmd, arg1, arg2)
    end
    
    -- Update race if active
    if race_active then
        update_race()
    end
    
    return update, math.floor(1000 / UPDATE_RATE_HZ)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

gcs:send_text(6, "PYLON RACE: Loaded v3.1 (AUTO mode)")
gcs:send_text(6, "PYLON: Add NAV_SCRIPT_TIME to mission")
gcs:send_text(6, string.format("PYLON: Default %d laps @ %.1fm/s (cruise from param)", DEFAULT_LAP_COUNT, CRUISE_SPEED))

return update()
