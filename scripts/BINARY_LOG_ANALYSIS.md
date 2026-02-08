# Binary Log Analysis - New Capabilities

## Overview

Added comprehensive binary log (.bin) analysis tools to work directly with ArduPilot dataflash logs, eliminating the need for pre-generated KMZ files.

## New Scripts

### 1. `bin_to_kmz.py` - KMZ Generator
**Purpose:** Convert binary logs to KMZ files for GPS track visualization

**What it does:**
- Reads ArduPilot dataflash logs directly
- Extracts GPS position data (lat, lon, alt)
- Filters for valid GPS fixes (3D or better)
- Generates KMZ files compatible with Google Earth
- Batch processing support for multiple logs

**Usage:**
```bash
python3 bin_to_kmz.py logs/flight.bin
# Creates: logs/flight.kmz

# Batch convert
python3 bin_to_kmz.py logs/*.bin
```

**Requirements:**
- Python 3.7+
- pymavlink

### 2. `analyze_bin_telemetry.py` - Deep Telemetry Analysis
**Purpose:** Extract detailed flight data for debugging navigation issues

**What it analyzes:**

1. **Script Messages**
   - All PYLON script output (lap starts, corner validation, gate crossings)
   - Shows exact timing of script decisions
   - Critical for debugging race logic

2. **Flight Mode Changes**
   - When autopilot switched modes
   - Helps identify manual intervention or mode failures

3. **Navigation Targets**
   - Where autopilot was trying to navigate
   - Waypoint distances over time
   - Bearing errors (how far off course)
   - Altitude errors

4. **Errors and Warnings**
   - System errors from autopilot
   - Warning messages
   - Failed operations

5. **GPS Quality**
   - Fix type distribution (2D, 3D, RTK, etc.)
   - Satellite count statistics
   - HDOP (horizontal dilution of precision)
   - Helps rule out GPS as cause of navigation issues

**Usage:**
```bash
python3 analyze_bin_telemetry.py logs/flight.bin

# Save to file
python3 analyze_bin_telemetry.py logs/flight.bin > logs/telemetry_report.txt
```

**Example Output:**
```
================================================================================
SCRIPT MESSAGES (PYLON)
================================================================================
Found 42 PYLON-related messages:

  [42.1s] PYLON RACE: Loaded v3.3 (AUTO mode, NE corner fix)
  [45.2s] PYLON: Starting Lap 1
  [52.1s] PYLON: → SW (L1)
  [58.3s] PYLON: SW OK (5.8m)
  [65.7s] PYLON: → NW (L1)
  [73.2s] PYLON: NW OK (10.1m)
  [81.5s] PYLON: → NE (L1)
  [89.8s] PYLON: NE OK (8.2m)  ← SUCCESS! (was 21m in v3.2)
  [95.3s] PYLON: → SE (L1)
  [101.7s] PYLON: SE OK (1.9m)
  [108.2s] PYLON: Gate crossed heading S
  [108.2s] LAP 1: 63.0s

================================================================================
FLIGHT MODE CHANGES
================================================================================
Found 3 mode changes:

  [12.3s] MANUAL
  [42.1s] AUTO  ← Race start
  [195.7s] RTL

================================================================================
ERRORS AND WARNINGS
================================================================================
✅ No errors or warnings found

================================================================================
GPS QUALITY SUMMARY
================================================================================
Total GPS samples: 1547

Fix type distribution:
  No fix:          0 (  0.0%)
  2D fix:          0 (  0.0%)
  3D fix:       1547 (100.0%) ✅
  DGPS:            0 (  0.0%)
  RTK float:       0 (  0.0%)
  RTK fixed:       0 (  0.0%)

Satellites: 12.3 avg (min: 10, max: 14) ✅
HDOP: 0.85 avg (lower is better, <2 is good) ✅
```

**Requirements:**
- Python 3.7+
- pymavlink

## Why This Matters

### Problem: Missing KMZ Files
When KMZ files are deleted or not generated, we can't analyze GPS tracks.

### Solution: Work Directly with .bin Files
1. **bin_to_kmz.py** regenerates KMZ files on demand
2. **analyze_bin_telemetry.py** provides deeper insights than KMZ alone

### Benefits

1. **Script Debug Messages**
   - See exactly what the PYLON script was doing
   - Verify corner validation ("NE OK" messages)
   - Confirm lap timing and gate crossings
   - **Critical for understanding if the fix worked**

2. **Navigation State**
   - Waypoint distances over time
   - Bearing errors (how far off course)
   - Helps identify if autopilot was targeting correct location

3. **Root Cause Analysis**
   - GPS quality issues? Check satellite count and HDOP
   - Mode switching problems? Check flight modes
   - Script errors? Check error messages
   - Navigation tuning? Check bearing/altitude errors

4. **Before/After Comparison**
   - Compare v3.2 vs v3.3 script messages
   - Look for "NE OK" with distance <15m in v3.3
   - Verify no new errors introduced

## Installation

```bash
cd scripts/
python3 -m venv .venv
source .venv/bin/activate
pip install pymavlink
pip freeze > requirements.txt
```

On first run without pymavlink, scripts show helpful install instructions.

## Updated requirements.txt

Now includes pymavlink:
```
# Required for binary log analysis (.bin files)
pymavlink>=2.4.0
```

## Integration with Existing Scripts

The workflow now becomes:

```bash
# 1. Have binary logs
logs/2026-02-09_test.bin

# 2. Generate KMZ (if needed)
python3 scripts/bin_to_kmz.py logs/2026-02-09_test.bin
# → Creates: logs/2026-02-09_test.kmz

# 3. GPS analysis
python3 scripts/analyze_flight_logs.py logs/2026-02-09_test.kmz
# → Shows waypoint distances

# 4. Deep telemetry (this is KEY for debugging!)
python3 scripts/analyze_bin_telemetry.py logs/2026-02-09_test.bin
# → Shows PYLON script messages, errors, GPS quality

# 5. Detailed corner analysis
python3 scripts/analyze_ne_corner.py logs/2026-02-09_test.kmz
# → Shows bearing errors, overshoots
```

## What to Look For in Next Flight

After flying with v3.3 script, analyze telemetry for:

### Success Indicators (v3.3 working):
```
✅ "PYLON: NE OK (X.Xm)" messages with X < 15m
✅ No errors or warnings
✅ GPS: 100% 3D fix, >10 satellites, HDOP <1.5
✅ Navigation bearing errors <15° at NE corner
```

### Failure Indicators (still broken):
```
⚠️ No "NE OK" messages (never validated corner)
⚠️ "NE OK" but distance >15m (still overshooting)
⚠️ Mode changes during race (unexpected RTL, MANUAL)
⚠️ Script error messages
⚠️ Poor GPS (HDOP >2, <8 satellites)
```

## Example Analysis Session

```bash
# Activate venv
cd scripts/
source .venv/bin/activate

# Convert all new logs to KMZ
python3 bin_to_kmz.py ../logs/2026-02-09*.bin

# Quick GPS check
python3 analyze_flight_logs.py ../logs/2026-02-09*.kmz

# Deep dive on each flight
for log in ../logs/2026-02-09*.bin; do
    echo "============================================"
    echo "Analyzing: $log"
    echo "============================================"
    python3 analyze_bin_telemetry.py "$log"
done > ../logs/full_analysis_2026-02-09.txt

# Review report
less ../logs/full_analysis_2026-02-09.txt
```

## Files Updated

- `scripts/bin_to_kmz.py` - NEW
- `scripts/analyze_bin_telemetry.py` - NEW
- `scripts/requirements.txt` - Updated (added pymavlink)
- `scripts/README.md` - Updated (new scripts documented)

## Files to Create (on venv setup)

- `scripts/.venv/` - Virtual environment directory (gitignored)

## Testing

Scripts include helpful error messages if pymavlink is missing:
```
ERROR: This script requires pymavlink

Install instructions:
  1. Activate virtual environment:
     cd scripts/
     source .venv/bin/activate

  2. Install pymavlink:
     pip install pymavlink

  3. Update requirements.txt:
     pip freeze > requirements.txt
```

## Status

✅ Scripts created and made executable
✅ README updated with usage examples
✅ requirements.txt updated with pymavlink
✅ Integration workflow documented
✅ Ready for use (after `pip install pymavlink`)

## Next Steps

1. **First flight with v3.3:**
   - Download .bin log from autopilot
   - Run `analyze_bin_telemetry.py` to see script messages
   - Look for "NE OK" messages with distance <15m
   - Check for any errors or warnings

2. **Compare with v3.2 logs:**
   - Run analysis on old logs (2026-02-08)
   - Compare NE corner distances
   - Look for differences in script messages

3. **If still having issues:**
   - Check GPS quality in telemetry
   - Look at bearing errors
   - Analyze navigation targets
   - May need further tuning
