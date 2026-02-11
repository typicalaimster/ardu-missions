# Pylon Racing Dataflash Logging

## Overview

The pylon racing script v4.2 now logs race data directly to the ArduPilot dataflash for detailed post-flight analysis. This is in addition to GCS text messages and provides permanent record in the .bin log file.

## Log Messages

### PYLR - Pylon Race Start
Logged once at race start, contains race configuration.

**Format:** `PYLR,LapC,Speed,Bank,iff`

| Field | Type | Description |
|-------|------|-------------|
| LapC | int | Number of laps configured |
| Speed | float | Cruise speed (m/s) |
| Bank | float | Maximum bank angle (degrees) from ROLL_LIMIT_DEG |

**Example:**
```
PYLR: LapC=5, Speed=18.0, Bank=45.0
```

### PYLL - Pylon Lap Completion
Logged every time a lap is completed (gate crossing detected).

**Format:** `PYLL,Lap,Time,NavSucc,NavFail,ifII`

| Field | Type | Description |
|-------|------|-------------|
| Lap | int | Lap number just completed |
| Time | float | Lap time in seconds |
| NavSucc | uint32 | Total successful navigation updates so far |
| NavFail | uint32 | Total failed navigation updates so far |

**Example:**
```
PYLL: Lap=1, Time=63.2, NavSucc=150, NavFail=0
PYLL: Lap=2, Time=61.8, NavSucc=305, NavFail=2
PYLL: Lap=3, Time=62.5, NavSucc=458, NavFail=5
```

## Analyzing the Logs

### Using MAVExplorer

```bash
# Load the log
mavexplorer.py flight.bin

# Show race start info
print msg.PYLR

# Show lap times
print msg.PYLL.Lap, msg.PYLL.Time

# Plot navigation success rate over laps
graph msg.PYLL.Lap msg.PYLL.NavSucc msg.PYLL.NavFail
```

### Using Python (pymavlink)

```python
from pymavlink import mavutil

mlog = mavutil.mavlink_connection('flight.bin')

# Find race start
while True:
    msg = mlog.recv_match(type='PYLR', blocking=False)
    if msg:
        print(f"Race Config: {msg.LapC} laps at {msg.Speed}m/s, {msg.Bank}° bank")
        break

# Find all lap completions
laps = []
while True:
    msg = mlog.recv_match(type='PYLL', blocking=False)
    if msg is None:
        break
    if msg:
        laps.append({
            'lap': msg.Lap,
            'time': msg.Time,
            'nav_success_rate': msg.NavSucc / (msg.NavSucc + msg.NavFail) * 100
        })

# Analyze
for lap in laps:
    print(f"Lap {lap['lap']}: {lap['time']:.1f}s, Nav: {lap['nav_success_rate']:.1f}%")
```

### Using analyze_bin_telemetry.py

The existing analysis script will show these messages:

```bash
cd /home/coder/ardu-missions
source venv/bin/activate
python3 scripts/analyze_bin_telemetry.py logs/flight.bin | grep -E "PYLR|PYLL"
```

## What You Can Analyze

### 1. Race Configuration Validation
- Verify cruise speed matches expectations
- Check bank angle being used
- Confirm lap count

### 2. Lap Time Consistency
- Compare lap times across race
- Identify slow laps (navigation issues?)
- Find fastest lap

### 3. Navigation Health Trends
- Track NavSucc/NavFail ratio per lap
- Identify laps with navigation problems
- Correlate nav failures with lap times

### 4. Race-to-Race Comparison
Compare multiple flights:
- Did script changes improve lap times?
- Is navigation success rate improving?
- Are lap times more consistent?

## Example Analysis Workflow

### 1. Extract Race Data
```bash
# Get all pylon race logs from flight
python3 -c "
from pymavlink import mavutil
mlog = mavutil.mavlink_connection('flight.bin')

# Race config
msg = mlog.recv_match(type='PYLR')
if msg:
    print(f'Config: {msg.LapC} laps, {msg.Speed}m/s, {msg.Bank}°')

# Lap times
mlog.rewind()
while True:
    msg = mlog.recv_match(type='PYLL', blocking=False)
    if msg is None: break
    if msg:
        succ_rate = msg.NavSucc / (msg.NavSucc + msg.NavFail) * 100 if (msg.NavSucc + msg.NavFail) > 0 else 0
        print(f'Lap {msg.Lap}: {msg.Time:.2f}s (Nav: {succ_rate:.0f}%)')
"
```

**Output:**
```
Config: 5 laps, 18.0m/s, 45°
Lap 1: 63.24s (Nav: 100%)
Lap 2: 61.87s (Nav: 99%)
Lap 3: 62.53s (Nav: 99%)
Lap 4: 61.22s (Nav: 100%)
Lap 5: 62.01s (Nav: 100%)
```

### 2. Compare Multiple Races
```bash
# Compare two flights
echo "Flight 1 (v4.1):"
python3 analyze_race.py flight_v41.bin

echo "Flight 2 (v4.2):"
python3 analyze_race.py flight_v42.bin
```

### 3. Plot Navigation Success Rate
```python
import matplotlib.pyplot as plt
from pymavlink import mavutil

# Load log
mlog = mavutil.mavlink_connection('flight.bin')

laps = []
nav_rates = []

while True:
    msg = mlog.recv_match(type='PYLL', blocking=False)
    if msg is None:
        break
    if msg:
        rate = msg.NavSucc / (msg.NavSucc + msg.NavFail) * 100
        laps.append(msg.Lap)
        nav_rates.append(rate)

plt.plot(laps, nav_rates, 'o-')
plt.xlabel('Lap Number')
plt.ylabel('Navigation Success Rate (%)')
plt.title('Pylon Racing Navigation Health')
plt.grid(True)
plt.ylim(0, 105)
plt.show()
```

## Integration with Existing Tools

### 1. MAVExplorer
Dataflash messages appear automatically in MAVExplorer:
- Browse to `msg.PYLR` and `msg.PYLL` 
- Plot fields like any other message
- Export to CSV for external analysis

### 2. Mission Planner
View in "Data Flash Logs" screen:
- Messages show up in message list
- Can filter by message type
- Export to CSV

### 3. Custom Analysis Scripts
Use the `analyze_bin_telemetry.py` script as template:
- Add PYLR/PYLL parsing
- Generate race statistics
- Create comparison reports

## Benefits Over GCS Text Messages

| Feature | GCS Text | Dataflash |
|---------|----------|-----------|
| **Permanent** | Lost if not logged | Always in .bin file |
| **Structured** | Free text | Typed fields |
| **Analyzable** | Manual parsing | Direct access |
| **Graphable** | Difficult | Easy with MAVExplorer |
| **Exportable** | No | CSV export |
| **Post-flight** | May be incomplete | Complete record |

## Advanced: Create Custom Analysis Tool

```python
#!/usr/bin/env python3
"""Analyze pylon racing performance from dataflash logs."""

from pymavlink import mavutil
import sys

def analyze_race(binfile):
    mlog = mavutil.mavlink_connection(binfile)
    
    # Get race config
    msg = mlog.recv_match(type='PYLR')
    if not msg:
        print("No race found in log")
        return
    
    print(f"\n{'=' * 60}")
    print(f"PYLON RACE ANALYSIS: {binfile}")
    print(f"{'=' * 60}\n")
    print(f"Configuration:")
    print(f"  Laps: {msg.LapC}")
    print(f"  Cruise Speed: {msg.Speed:.1f} m/s")
    print(f"  Bank Angle: {msg.Bank:.0f}°")
    
    # Get all laps
    mlog.rewind()
    laps = []
    while True:
        msg = mlog.recv_match(type='PYLL', blocking=False)
        if msg is None:
            break
        if msg:
            laps.append(msg)
    
    if not laps:
        print("\nNo laps completed")
        return
    
    print(f"\n{'Lap':<5} | {'Time (s)':<10} | {'Nav Success':<12} | {'Nav Fail':<10} | {'Rate %':<8}")
    print("-" * 70)
    
    total_time = 0
    for lap in laps:
        rate = lap.NavSucc / (lap.NavSucc + lap.NavFail) * 100 if (lap.NavSucc + lap.NavFail) > 0 else 0
        print(f"{lap.Lap:<5} | {lap.Time:<10.2f} | {lap.NavSucc:<12} | {lap.NavFail:<10} | {rate:<8.1f}")
        total_time += lap.Time
    
    print("-" * 70)
    avg_time = total_time / len(laps) if laps else 0
    print(f"Average lap time: {avg_time:.2f}s")
    print(f"Total race time: {total_time:.2f}s")
    
    # Find best/worst laps
    best = min(laps, key=lambda x: x.Time)
    worst = max(laps, key=lambda x: x.Time)
    print(f"\nBest lap: #{best.Lap} - {best.Time:.2f}s")
    print(f"Worst lap: #{worst.Lap} - {worst.Time:.2f}s")
    print(f"Difference: {worst.Time - best.Time:.2f}s")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_race.py <flight.bin>")
        sys.exit(1)
    
    analyze_race(sys.argv[1])
```

Save as `scripts/analyze_race.py` and run:
```bash
python3 scripts/analyze_race.py logs/flight.bin
```

## Summary

Dataflash logging provides:
- ✅ Permanent race data in .bin files
- ✅ Structured data for easy analysis
- ✅ Navigation health tracking per lap
- ✅ Race configuration verification
- ✅ Post-flight performance analysis
- ✅ Race-to-race comparisons

This complements GCS text messages and KMZ tracks for complete race analysis!
