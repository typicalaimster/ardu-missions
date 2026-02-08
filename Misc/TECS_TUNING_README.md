# TECS Tuning Analyzer

A read-only Lua script for analyzing ArduPilot TECS (Total Energy Control System) performance and providing tuning recommendations during flight.

## Overview

This script implements automated flight testing based on the [ArduPilot TECS Tuning Guide](https://ardupilot.org/plane/docs/tecs-total-energy-control-system-for-speed-height-tuning-guide.html). It monitors your aircraft's performance during climbs, descents, and level flight, then provides specific parameter tuning recommendations.

**Key Features:**
- ✅ **Read-only**: Never modifies any parameters
- ✅ **Safe**: Only operates above 50 feet (15.24m) AGL
- ✅ **Automatic**: Detects and analyzes climb/descent/level flight automatically
- ✅ **Real-time**: Provides recommendations via GCS messages during flight
- ✅ **Comprehensive**: Checks all major TECS parameters

## Installation

1. Copy `tecs_tuning_analyzer.lua` to your SD card's `APM/scripts/` directory
2. Set `SCR_ENABLE = 1` and reboot the autopilot
3. Set `SCR_HEAP_SIZE` to at least 100000 (100KB)
4. Verify script loaded by checking GCS messages

## Usage

### Pre-Flight Setup

1. Ensure your pitch loop is already tuned (use AUTOTUNE first)
2. Have an airspeed sensor calibrated (recommended) or set `ARSPD_USE = 0`
3. Load the script and verify it reports "TECS TUNING ANALYZER v1.0"

### Flight Test Procedure

The script automatically detects and analyzes different flight phases. You don't need to do anything special - just fly normally and command altitude changes.

#### 1. Climb Test
**What it tests:** `THR_MAX`, `PTCH_LIM_MAX_DEG`, `TECS_CLMB_MAX`

**How to perform:**
- In AUTO, LOITER, RTL, or GUIDED mode
- Command a positive altitude change of 50+ meters
- Maintain the climb for at least 10 seconds

**What the script analyzes:**
- Is throttle reaching `THR_MAX` limit?
- Is pitch reaching `PTCH_LIM_MAX_DEG` limit?
- Is airspeed being maintained during climb?
- Is actual climb rate matching `TECS_CLMB_MAX`?

#### 2. Descent Test
**What it tests:** `PTCH_LIM_MIN_DEG`, `TECS_SINK_MAX`, airspeed limits

**How to perform:**
- Command a negative altitude change of 50+ meters
- Maintain the descent for at least 10 seconds

**What the script analyzes:**
- Is pitch reaching `PTCH_LIM_MIN_DEG` limit?
- Is airspeed exceeding `AIRSPEED_MAX`?
- Is actual sink rate matching `TECS_SINK_MAX`?

#### 3. Level Flight Test
**What it tests:** `TRIM_THROTTLE`

**How to perform:**
- Fly level at cruise speed for 30+ seconds
- Can be during loiter or straight-and-level flight

**What the script analyzes:**
- Average throttle vs `TRIM_THROTTLE` setting
- Throttle stability (detects oscillations)

#### 4. Oscillation Detection
**What it tests:** `TECS_TIME_CONST`, `TECS_PTCH_DAMP`

**Automatic monitoring:**
- Detects altitude oscillations in any flight mode
- Detects speed/height coupling issues

### Reading Results

Results are sent to GCS messages at three severity levels:

- **INFO (level 6)**: Status updates and measurements
- **WARNING (level 5)**: Suggestions for improvement
- **CRITICAL (level 4)**: Important recommendations
- **ALERT (level 3)**: Test results headers

Example output:
```
========== CLIMB TEST RESULTS ==========
TECS: Avg climb rate: 4.2 m/s (max param: 5.0)
TECS: Avg throttle: 82% (max: 95%, limit: 75%)
TECS: Avg pitch: 18.5° (max: 19.8°, limit: 20.0°)
TECS: Avg airspeed: 14.2 m/s (min: 13.8, cruise: 15.0)
RECOMMEND: Increase THR_MAX to 100
REASON: Throttle at limit, using more than configured
========================================
```

## Parameters Monitored

### Throttle Parameters
- `THR_MAX`: Maximum throttle percentage
- `THR_MIN`: Minimum throttle percentage
- `TRIM_THROTTLE`: Cruise throttle percentage

### Pitch Limits
- `PTCH_LIM_MAX_DEG`: Maximum pitch angle (degrees)
- `PTCH_LIM_MIN_DEG`: Minimum pitch angle (degrees)

### Airspeed Parameters
- `AIRSPEED_CRUISE`: Target cruise airspeed (m/s)
- `ARSPD_FBW_MIN`: Minimum airspeed (m/s)
- `ARSPD_FBW_MAX`: Maximum airspeed (m/s)
- `ARSPD_USE`: Enable/disable airspeed sensor

### TECS Parameters
- `TECS_CLMB_MAX`: Maximum climb rate (m/s)
- `TECS_SINK_MIN`: Minimum sink rate at idle (m/s)
- `TECS_SINK_MAX`: Maximum sink rate (m/s)
- `TECS_TIME_CONST`: Controller time constant (seconds)
- `TECS_THR_DAMP`: Throttle damping gain
- `TECS_INTEG_GAIN`: Integrator gain
- `TECS_PTCH_DAMP`: Pitch damping gain
- `TECS_SPDWEIGHT`: Speed vs height weighting (0-2)
- `TECS_RLL2THR`: Roll to throttle compensation

## Common Recommendations

### "Reduce TECS_CLMB_MAX or increase THR_MAX"
**Cause:** Aircraft can't maintain airspeed during max climb
**Fix:** Either reduce climb rate demand or increase available throttle

### "Increase PTCH_LIM_MAX_DEG or reduce TECS_CLMB_MAX"
**Cause:** Pitch angle hitting limit during climb
**Fix:** Allow steeper climbs or reduce climb rate demand

### "Set TRIM_THROTTLE to XX"
**Cause:** Average level-flight throttle differs from parameter
**Fix:** Update `TRIM_THROTTLE` to match actual cruise throttle

### "Reduce TECS_SINK_MAX"
**Cause:** Aircraft overspeeding during descents
**Fix:** Limit maximum descent rate

### "Increase TECS_TIME_CONST by 1"
**Cause:** Altitude oscillations detected
**Fix:** Make controller respond more slowly (increases damping)

### "Increase TECS_PTCH_DAMP by 0.1"
**Cause:** Pitch/altitude oscillations
**Fix:** Add damping to pitch control loop

## Flight Without Airspeed Sensor

If `ARSPD_USE = 0`, the script still works but:
- Airspeed analysis is based on groundspeed (less accurate in wind)
- `TECS_SPDWEIGHT` is automatically 0 (height control only)
- Focus on pitch limits and climb/sink rates
- `TRIM_THROTTLE` tuning becomes more critical

## Safety Notes

⚠️ **Minimum Altitude**: Script only operates above 50 feet (15.24m) AGL. Below this altitude, all analysis pauses.

⚠️ **Supported Modes**: Only active in AUTO (10), RTL (11), LOITER (12), or GUIDED (15) modes.

⚠️ **No Auto-Tuning**: This script NEVER changes parameters. You must manually apply recommendations.

⚠️ **Pitch Loop First**: Tune your pitch loop with AUTOTUNE before using this script. TECS tuning assumes good pitch response.

⚠️ **Test Area**: Perform tests in a safe area with adequate altitude for climbs and descents (recommend 200+ feet).

⚠️ **Wind Effects**: Strong winds can affect results, especially without an airspeed sensor. Test in light wind conditions when possible.

## Troubleshooting

### Script not loading
- Check `SCR_ENABLE = 1`
- Check `SCR_HEAP_SIZE >= 100000`
- Check script in correct directory (`APM/scripts/`)
- Check GCS messages for Lua errors

### No recommendations appearing
- Verify altitude above 50 feet
- Verify in supported flight mode (AUTO/RTL/LOITER/GUIDED)
- Perform larger altitude changes (50m minimum)
- Check GCS message filtering (enable INFO level messages)

### Conflicting recommendations
- Perform tests in calm conditions
- Allow tests to complete (10+ seconds each)
- Focus on consistent patterns across multiple tests
- Review full log files for detailed data

## Advanced: Log File Analysis

For detailed analysis, review the onboard logs. Key data fields:

- **TECS.h**: Demanded height
- **TECS.dh**: Height error
- **TECS.s**: Demanded speed
- **TECS.ds**: Speed error
- **TECS.pth**: Demanded throttle
- **TECS.ptch**: Demanded pitch
- **TECS.dsp**: Speed rate error
- **TECS.dhp**: Height rate error
- **TECS.iph**: Pitch integrator
- **TECS.ith**: Throttle integrator

## References

- [ArduPilot TECS Tuning Guide](https://ardupilot.org/plane/docs/tecs-total-energy-control-system-for-speed-height-tuning-guide.html)
- [ArduPilot Lua Scripting Documentation](https://ardupilot.org/plane/docs/common-lua-scripts.html)
- [ArduPilot Plane Tuning Guide](https://ardupilot.org/plane/docs/tuning-quickstart.html)

## Version History

**v1.0** (2026-02-08)
- Initial release
- Automatic climb/descent/level flight detection
- Real-time parameter recommendations
- Oscillation detection
- Read-only safety features

## License

This script is released under the same license as ArduPilot (GPLv3).
