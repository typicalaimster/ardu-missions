# Pylon Racing Script - AUTO Mode Setup Guide

## How It Works

This script uses the **NAV_SCRIPT_TIME** waypoint command to take control during your AUTO mode mission. This is the same method used by ArduPilot's scripted aerobatics feature.

### Workflow:
1. Upload script to SD card
2. Create mission with NAV_SCRIPT_TIME waypoint
3. Switch to AUTO mode
4. When AUTO reaches NAV_SCRIPT_TIME → Script takes control
5. Script runs the race (5 laps by default)
6. When race completes → AUTO mode resumes mission

## Installation

### Step 1: Enable Lua Scripting

Set these parameters:
```
SCR_ENABLE = 1
SCR_HEAP_SIZE = 80000      # 80KB minimum for this script
SCR_VM_I_COUNT = 100000
```

**Reboot flight controller after changing these!**

### Step 2: Upload Script

1. Copy `pylon_race_auto_mode.lua` to SD card: `/APM/scripts/`
2. Reboot flight controller
3. Check for message: "PYLON RACE: Loaded v3.0 (AUTO mode)"

## Mission Setup

### Option 1: Race-Only Mission (Recommended for Testing)

```
WP 1: HOME (or takeoff point)
WP 2: Navigate to start gate area
WP 3: NAV_SCRIPT_TIME
       - Timeout: 600 seconds (10 minutes max)
       - arg1: 5 (number of laps)
       - arg2: 0 (unused)
WP 4: RTL or LAND
```

### Option 2: Full Mission with Race Section

```
WP 1: TAKEOFF (altitude 15m)
WP 2: Climb to racing altitude
WP 3: Navigate to race course
WP 4: NAV_SCRIPT_TIME (race starts here)
       - Timeout: 600
       - arg1: 5
       - arg2: 0
WP 5: Exit race area
WP 6: LAND
```

### Creating NAV_SCRIPT_TIME Waypoint in Mission Planner:

1. Open Flight Plan screen
2. Right-click on map → Add Waypoint
3. Change waypoint type to **"NAV_SCRIPT_TIME"** (or use command ID 42702)
4. Set parameters:
   - **Delay**: 600 (timeout in seconds - max time for race)
   - **Command**: 0 (not used by our script)
   - **Arg1**: 5 (number of laps - YOU CAN CHANGE THIS)
   - **Arg2**: 0 (not used)

### Example Mission File (QGC WPL format):

```
QGC WPL 110
0	1	0	16	0	0	0	0	32.7627903	-117.2136567	3.206496	1
1	0	3	22	0.00000000	0.00000000	0.00000000	0.00000000	0.00000000	0.00000000	15.000000	1
2	0	3	16	0.00000000	0.00000000	0.00000000	0.00000000	32.76300740	-117.21375030	12.000000	1
3	0	3	42702	600.00000000	0.00000000	5.00000000	0.00000000	0.00000000	0.00000000	0.000000	1
4	0	3	20	0.00000000	0.00000000	0.00000000	0.00000000	0.00000000	0.00000000	0.000000	1
```

Explanation:
- WP1: Takeoff to 15m
- WP2: Navigate to start gate
- WP3: NAV_SCRIPT_TIME (race happens here - 5 laps, 600s timeout)
- WP4: RTL home

## Configuration

### In the Script (`pylon_race_auto_mode.lua`):

```lua
local CRUISE_SPEED = 15.0        -- Airspeed in m/s (TUNE THIS)
local DEFAULT_LAP_COUNT = 5      -- Default laps (overridden by arg1)
local TARGET_ALTITUDE = 9.13     -- Racing altitude in meters (30ft)
local TURN_RADIUS = 15.0         -- Distance to corners before advancing
local MIN_TURN_RADIUS = 12.0     -- Must get within this to validate
```

### Changing Number of Laps:

**Method 1: In the mission (recommended)**
- Set arg1 of NAV_SCRIPT_TIME waypoint to desired lap count
- Example: arg1 = 3 for 3 laps, arg1 = 10 for 10 laps

**Method 2: In the script**
- Change `DEFAULT_LAP_COUNT = 5` to your desired number
- This is used if arg1 is 0 or not set

## Operation

### Pre-Flight:
1. ✅ Script loaded (check GCS messages)
2. ✅ Mission uploaded with NAV_SCRIPT_TIME
3. ✅ Aircraft positioned for mission start
4. ✅ Weather check (wind < 15mph recommended for first test)

### Running the Race:

1. **Arm and switch to AUTO mode**
2. Aircraft follows mission waypoints
3. When reaching NAV_SCRIPT_TIME:
   ```
   GCS Message: ========== PYLON RACE START ==========
   GCS Message: 5 lap oval race @ 15.0m/s
   GCS Message: PYLON: Approaching start gate...
   ```
4. Script navigates the oval course
5. After completing laps:
   ```
   GCS Message: RACE COMPLETE! 5 laps, 153.2s total
   GCS Message: PYLON: Race finished, resuming mission
   ```
6. AUTO mode continues to next waypoint

### During Race - GCS Messages:

```
PYLON: → SW (L1)           # Heading to Southwest corner, Lap 1
PYLON: L1 SW 45m           # Lap 1, 45m from SW corner
PYLON: SW OK (11.2m)       # Southwest corner validated at 11.2m
PYLON: → NW (L1)           # Heading to Northwest corner
PYLON: Gate crossed N      # Crossed start gate heading North
LAP 1: 32.4s               # Lap 1 completed in 32.4 seconds
PYLON: Starting Lap 2      # Beginning lap 2
...
RACE COMPLETE! 5 laps, 153.2s total
```

### Stopping the Race:

- **Switch out of AUTO mode** → Script stops immediately, race aborts
- **Race timeout** → If race takes longer than NAV_SCRIPT_TIME timeout (600s), AUTO resumes
- **Normal completion** → Script finishes race, AUTO continues mission

## Tuning Guide

### Initial Test (Conservative):
```lua
local CRUISE_SPEED = 12.0
local TURN_RADIUS = 20.0
local MIN_TURN_RADIUS = 15.0
```
**Mission**: 2 laps (arg1 = 2)

### After Successful Test:
```lua
local CRUISE_SPEED = 15.0        # Increase speed
local TURN_RADIUS = 15.0         # Tighter turns
local MIN_TURN_RADIUS = 12.0
```
**Mission**: 5 laps (arg1 = 5)

### Competition Settings:
```lua
local CRUISE_SPEED = 18.0        # Maximum safe speed
local TURN_RADIUS = 12.0         # Aggressive turns
local MIN_TURN_RADIUS = 10.0
```
**Mission**: 5 laps (arg1 = 5)

## Wind Compensation

The script provides automatic wind compensation through:

1. **Continuous navigation updates** (20Hz)
   - Updates target every 50ms
   - ArduPilot's L1 controller adjusts for wind constantly

2. **Lookahead blending**
   - Starts blending to next corner when 30m away
   - Smooths turn entry/exit
   - Reduces overshoot in crosswinds

3. **Gate crossing detection**
   - Doesn't require hitting exact gate position
   - Just needs to cross the lat/lon line
   - Works regardless of crosswind approach angle

### Expected Performance vs Current Waypoints:

| Metric | Current (Waypoints) | With Script |
|--------|---------------------|-------------|
| Drift at gate | 10-22m south | < 5m |
| Turn consistency | 25-50m radius | 12-20m radius |
| Lap time variation | ±10-15s | ±2-3s |
| Wind handling | Poor | Good |

## Troubleshooting

### "Scripting: out of memory"
- Increase `SCR_HEAP_SIZE` to 100000 (100KB)
- Disable unused features (TERRAIN_ENABLE, SRTL_POINTS)

### Script doesn't start when reaching NAV_SCRIPT_TIME
1. Check script is in `/APM/scripts/` folder
2. Verify `SCR_ENABLE = 1`
3. Look for "PYLON RACE: Loaded" message at boot
4. Check NAV_SCRIPT_TIME timeout isn't zero

### "PYLON: Nav update failed"
- Script can't control vehicle
- May need to enable scripting control (should be automatic)
- Check no other scripts are conflicting

### Aircraft cuts corners / "SW cut! Too far"
- Increase `TURN_RADIUS` in script
- Or decrease `MIN_TURN_RADIUS` (but this allows sloppier racing)
- Check wind isn't too strong for current settings

### Lap not detected / gate crossing missed
- Check `START_GATE` coordinates in script match your actual gate
- Gate detection uses lat/lon line crossing
- Aircraft must actually cross the gate line (not just approach it)

### Race runs past timeout
- Increase NAV_SCRIPT_TIME timeout (default 600s = 10min)
- Check if laps are taking too long (wind, speed too slow)
- For 5 laps at 15m/s: ~3 minutes typical

## Advanced Features

### Lap Timing
- Each lap completion shows time
- Total race time shown at end
- Times logged to dataflash

### Corner Validation
- Script validates you got within MIN_TURN_RADIUS of each corner
- "OK" message when validated
- Can review logs to check racing line

### Gate Crossing Direction
- Shows "Gate crossed N" or "Gate crossed S"
- Helps verify proper oval direction

## Safety Notes

- ✅ Always test in light wind first
- ✅ Have manual takeover ready (mode switch)
- ✅ Set conservative timeout (600s recommended)
- ✅ Check geofence is active
- ✅ Ensure battery sufficient for full race + reserves
- ✅ Test with 1-2 laps before full 5-lap race

## File Locations

- **Script**: `/APM/scripts/pylon_race_auto_mode.lua`
- **Mission**: Upload via GCS (Mission Planner / QGC)
- **Logs**: `/APM/LOGS/` (review after flight)

Good luck with your pylon racing!
