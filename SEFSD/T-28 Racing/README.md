# T-28 Pylon Racing

Complete documentation for autonomous pylon racing using ArduPilot Lua scripting and AUTO mode.

## Table of Contents

- [Overview](#overview)
- [Pylon Locations](#pylon-locations)
- [Quick Start](#quick-start)
- [Mission Files](#mission-files)
- [Installation & Setup](#installation--setup)
- [Mission Configuration](#mission-configuration)
- [Operation Guide](#operation-guide)
- [Tuning & Performance](#tuning--performance)
- [Troubleshooting](#troubleshooting)
- [Safety Notes](#safety-notes)

---

## Overview

This racing system uses ArduPilot's **NAV_SCRIPT_TIME** waypoint command to enable scripted pylon racing within AUTO mode missions. The script takes control during the race section, then returns control to AUTO mode to continue the mission.

🛑 **<span style="color:red">You must use an H7 series autopilot that supports scripting. Such as the Matek H743-WLITE.</span>**

### Key Files

| File | Description |
|------|--------------|
| `pylon_race_auto_mode.lua` | The racing script — copy to `/APM/scripts/` |
| `pylon_race_mission.waypoints` | Standard 5-lap race mission |
| `pylon_race_full_mission.waypoints` | Complete mission with approach waypoints |
| `pylon_race_5laps_competition.waypoints` | Competition-ready with precision landing |
| `pylon_race_test_2laps.waypoints` | Quick test mission (2 laps only) |

### How It Works

1. **Upload script** to SD card: `/APM/scripts/pylon_race_auto_mode.lua`
2. **Create mission** with a NAV_SCRIPT_TIME waypoint (or use provided mission files)
3. **Switch to AUTO** — aircraft follows mission waypoints normally
4. **When AUTO reaches NAV_SCRIPT_TIME** → script takes control and runs the race
5. **Race completes** → AUTO resumes and continues to the next waypoint

### Quick Setup (Mission Layout)

```
WP1: Takeoff
WP2: Navigate to start gate
WP3: NAV_SCRIPT_TIME (timeout=600s, arg1=5 laps)  ← Race happens here
WP4: RTL
```

---

## Pylon Locations

The oval race course uses the following coordinates:

| Location      | Latitude    | Longitude    |
| :------------ | :---------- | :----------- |
| Course Start  | 32.76300740 | -117.21375030 |
| West Pylon    | 32.76314830 | -117.21414310 |
| East Pylon    | 32.76326200 | -117.21341080 |

---

## Quick Start

### Pre-Flight Checklist

✅ Script uploaded to `/APM/scripts/pylon_race_auto_mode.lua`  
✅ Script enabled: `SCR_ENABLE = 1`  
✅ Heap size sufficient: `SCR_HEAP_SIZE = 80000` minimum  
✅ Mission uploaded and verified  
✅ Home position set correctly  
✅ Battery fully charged  
✅ Wind conditions acceptable (< 15mph recommended)  
✅ GCS connected and receiving telemetry  

### First Test Flight

1. Use `pylon_race_test_2laps.waypoints` for initial testing
2. Manually position aircraft near race start area
3. Switch to AUTO mode
4. Monitor GCS messages for race progress
5. Be ready to switch modes if needed

---

## Mission Files

### 1. **pylon_race_test_2laps.waypoints** (RECOMMENDED FOR FIRST TEST)

**Purpose**: Quick initial test with minimal mission complexity

**Waypoints**:
- WP0: Home location (auto-set)
- WP1: NAV_SCRIPT_TIME (2 laps, 600s timeout) - Race starts immediately
- WP2: RTL (Return to launch)

**Use when**:
- First time testing the script
- Quick validation of script functionality
- Testing in new wind conditions
- You're already airborne and positioned near the course

**Notes**:
- Assumes you'll manually fly to the start area before switching to AUTO
- Very short mission - just race then return home
- arg1 = 2 laps for quick test

---

### 2. **pylon_race_full_mission.waypoints** (STANDARD MISSION)

**Purpose**: Complete mission including approach to race area

**Waypoints**:
- WP0: Home location (auto-set)
- WP1: TAKEOFF to 15m (49ft)
- WP2: Navigate to south of start gate (pre-race positioning)
- WP3: NAV_SCRIPT_TIME (5 laps, 600s timeout) - RACE STARTS HERE
- WP4: Navigate away from race area  
- WP5: RTL (Return to launch)

**Use when**:
- Standard operations
- Want automated approach to race start
- Running multiple missions back-to-back
- Need consistent pre-race positioning

**Notes**:
- WP2 positions aircraft ~11m south of start gate before race
- WP4 exits race area before RTL for clean separation
- arg1 = 5 laps (full race)

---

### 3. **pylon_race_5laps_competition.waypoints** (COMPETITION)

**Purpose**: Competition-ready mission with precision landing

**Waypoints**:
- WP0: Home location (auto-set)
- WP1: TAKEOFF to 15m
- WP2: Navigate to south of start gate (lower approach at 12m)
- WP3: NAV_SCRIPT_TIME (5 laps, 600s timeout) - RACE
- WP4: Exit race area
- WP5: LAND at home location

**Use when**:
- Competition day
- Need automated land vs RTL
- Want tighter altitude control
- Running timed events

**Notes**:
- Uses LAND command instead of RTL for precision
- Slightly lower approach altitude (12m vs 15m)
- arg1 = 5 laps (competition standard)

---

## Installation & Setup

### Step 1: Enable Lua Scripting

Set these parameters:
```
SCR_ENABLE = 1
SCR_HEAP_SIZE = 80000      # 80KB minimum for this script
SCR_VM_I_COUNT = 100000
```

**⚠️ Reboot flight controller after changing these!**

### Step 2: Upload Script

1. Copy `pylon_race_auto_mode.lua` to SD card: `/APM/scripts/`
2. Reboot flight controller
3. Check for message: "PYLON RACE: Loaded v3.0 (AUTO mode)"

---

## Mission Configuration

### Creating NAV_SCRIPT_TIME Waypoint in Mission Planner

1. Open Flight Plan screen
2. Right-click on map → Add Waypoint
3. Change waypoint type to **"NAV_SCRIPT_TIME"** (or use command ID 42702)
4. Set parameters:
   - **Delay**: 600 (timeout in seconds - max time for race)
   - **Command**: 0 (not used by our script)
   - **Arg1**: 5 (number of laps - YOU CAN CHANGE THIS)
   - **Arg2**: 0 (not used)

### Mission File Format (QGC WPL 110)

```
Line: WP#  Cur  Frame  Cmd  P1  P2  P3  P4  Lat  Lon  Alt  AutoContinue
```

### Key Commands Used

**Command 16 (WAYPOINT)**:
- Standard navigation waypoint
- Aircraft flies to lat/lon/alt

**Command 22 (TAKEOFF)**:
- Automatic takeoff
- P4 parameter = altitude in meters

**Command 20 (RTL - Return to Launch)**:
- Returns to home position
- Lands automatically

**Command 21 (LAND)**:
- Land at specified location
- More precise than RTL

**Command 42702 (NAV_SCRIPT_TIME)**:
- Hands control to Lua script
- **P1 (Delay)**: Timeout in seconds (600 = 10 minutes max)
- **P2 (Command)**: Script command ID (not used, set to 0)
- **P3 (arg1)**: Number of laps (2, 5, 10, etc.)
- **P4 (arg2)**: Additional parameter (not used, set to 0)

### Example Mission File

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

### Modifying Missions

#### Change Number of Laps

Find the NAV_SCRIPT_TIME line and change **arg1** (parameter 3):

```
Original (5 laps):
3  0  3  42702  600.0  0.0  5.0  0.0  0.0  0.0  0.0  1
                              ^^^
                            Change this

Modified (10 laps):
3  0  3  42702  600.0  0.0  10.0  0.0  0.0  0.0  0.0  1
```

#### Change Race Timeout

Increase timeout if races take longer (headwind, slower aircraft):

```
Original (600s = 10 minutes):
3  0  3  42702  600.0  0.0  5.0  0.0  0.0  0.0  0.0  1
                 ^^^^^
              Change this

Modified (900s = 15 minutes):
3  0  3  42702  900.0  0.0  5.0  0.0  0.0  0.0  0.0  1
```

#### Change Approach Altitude

Modify WP2's altitude parameter (last number before AutoContinue):

```
Original (12m altitude):
2  0  3  16  0.0  0.0  0.0  0.0  32.76280000  -117.21375030  12.0  1
                                                               ^^^^
Modified (15m altitude):
2  0  3  16  0.0  0.0  0.0  0.0  32.76280000  -117.21375030  15.0  1
```

### Uploading Missions

#### Using Mission Planner
1. Connect to flight controller
2. Go to "Flight Plan" tab
3. Right-click → "File Load/Save" → "Load WP File"
4. Select your .waypoints file
5. Click "Write WPs" to upload to aircraft

#### Using QGroundControl
1. Connect to vehicle
2. Go to "Plan" view
3. Click folder icon → "Load from file"
4. Select your .waypoints file
5. Click "Upload" to send to vehicle

---

## Operation Guide

### Script Configuration

In `pylon_race_auto_mode.lua`:

```lua
local CRUISE_SPEED = 15.0        -- Airspeed in m/s (TUNE THIS)
local DEFAULT_LAP_COUNT = 5      -- Default laps (overridden by arg1)
local TARGET_ALTITUDE = 9.13     -- Racing altitude in meters (30ft)
local TURN_RADIUS = 15.0         -- Distance to corners before advancing
local MIN_TURN_RADIUS = 12.0     -- Must get within this to validate
```

### Changing Number of Laps

**Method 1: In the mission (recommended)**
- Set arg1 of NAV_SCRIPT_TIME waypoint to desired lap count
- Example: arg1 = 3 for 3 laps, arg1 = 10 for 10 laps

**Method 2: In the script**
- Change `DEFAULT_LAP_COUNT = 5` to your desired number
- This is used if arg1 is 0 or not set

### Running the Race

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

### During Race - GCS Messages

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

### Expected Timeline (5 lap race)

```
T+0:00  Arm and switch to AUTO
T+0:05  TAKEOFF complete
T+0:15  Navigate to race start (WP2)
T+0:25  Reach NAV_SCRIPT_TIME (WP3) - RACE STARTS
T+0:26  Cross start gate - Lap 1 begins
T+0:58  Lap 1 complete (32s)
T+1:30  Lap 2 complete (32s)
T+2:02  Lap 3 complete (32s)
T+2:34  Lap 4 complete (32s)
T+3:06  Lap 5 complete (32s)
T+3:06  RACE COMPLETE - Script done
T+3:10  Navigate to exit point (WP4)
T+3:20  RTL/LAND
T+3:45  Mission complete
```

Times will vary based on wind, aircraft speed, and course conditions.

### Stopping the Race

- **Switch out of AUTO mode** → Script stops immediately, race aborts
- **Race timeout** → If race takes longer than NAV_SCRIPT_TIME timeout (600s), AUTO resumes
- **Normal completion** → Script finishes race, AUTO continues mission

---

## Tuning & Performance

### Initial Test (Conservative)

```lua
local CRUISE_SPEED = 12.0
local TURN_RADIUS = 20.0
local MIN_TURN_RADIUS = 15.0
```
**Mission**: 2 laps (arg1 = 2)

### After Successful Test

```lua
local CRUISE_SPEED = 15.0        # Increase speed
local TURN_RADIUS = 15.0         # Tighter turns
local MIN_TURN_RADIUS = 12.0
```
**Mission**: 5 laps (arg1 = 5)

### Competition Settings

```lua
local CRUISE_SPEED = 18.0        # Maximum safe speed
local TURN_RADIUS = 12.0         # Aggressive turns
local MIN_TURN_RADIUS = 10.0
```
**Mission**: 5 laps (arg1 = 5)

### Wind Compensation

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

### Expected Performance vs Current Waypoints

| Metric | Current (Waypoints) | With Script |
|--------|---------------------|-------------|
| Drift at gate | 10-22m south | < 5m |
| Turn consistency | 25-50m radius | 12-20m radius |
| Lap time variation | ±10-15s | ±2-3s |
| Wind handling | Poor | Good |

### Advanced Features

#### Lap Timing
- Each lap completion shows time
- Total race time shown at end
- Times logged to dataflash

#### Corner Validation
- Script validates you got within MIN_TURN_RADIUS of each corner
- "OK" message when validated
- Can review logs to check racing line

#### Gate Crossing Direction
- Shows "Gate crossed N" or "Gate crossed S"
- Helps verify proper oval direction

---

## Troubleshooting

### "Scripting: out of memory"
- Increase `SCR_HEAP_SIZE` to 100000 (100KB)
- Disable unused features (TERRAIN_ENABLE, SRTL_POINTS)

### Script doesn't start when reaching NAV_SCRIPT_TIME
1. Check script is in `/APM/scripts/` folder
2. Verify `SCR_ENABLE = 1`
3. Look for "PYLON RACE: Loaded" message at boot
4. Check NAV_SCRIPT_TIME timeout isn't zero
5. Ensure NAV_SCRIPT_TIME command ID is 42702
6. Verify script is loaded (check GCS messages at boot)
7. Ensure AUTO mode is active when reaching NAV_SCRIPT_TIME

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

### Race runs past timeout / Race times out
- Increase NAV_SCRIPT_TIME timeout (default 600s = 10min)
- Increase P1 parameter (timeout) in NAV_SCRIPT_TIME
- Check if laps are taking too long (wind, speed too slow)
- Verify CRUISE_SPEED in script matches aircraft capability
- For 5 laps at 15m/s: ~3 minutes typical

### Aircraft doesn't follow mission
- Verify mission uploaded successfully
- Check AUTO mode is selected
- Ensure no failsafes are active
- Verify GPS lock is good

---

## Safety Notes

- ✅ Always test in light wind first
- ✅ Have manual takeover ready (mode switch)
- ✅ Set conservative timeout (600s recommended)
- ✅ Check geofence is active
- ✅ Ensure battery sufficient for full race + reserves
- ✅ Test with 1-2 laps before full 5-lap race
- ✅ Geofence configured (if used)

---

## Recommended Testing Sequence

1. **First test**: Use `pylon_race_test_2laps.waypoints` (2 laps, minimal mission)
2. **Second test**: Use `pylon_race_full_mission.waypoints` (5 laps, full mission)
3. **Tune and optimize**: Adjust CRUISE_SPEED and TURN_RADIUS in script
4. **Competition**: Use `pylon_race_5laps_competition.waypoints` (optimized settings)

---

## File Locations

- **Script**: `/APM/scripts/pylon_race_auto_mode.lua`
- **Mission files**: Located in this directory (upload via GCS)
- **Logs**: `/APM/LOGS/` (review after flight)

---

Good luck with your pylon racing!
