# ArduPilot Flight Log Analysis Scripts

Python scripts for analyzing ArduPilot flight logs, specifically designed for pylon racing missions.

## 🚀 Quick Start

### Basic Analysis (No Setup Required)

```bash
# Analyze a single flight
python3 scripts/analyze_flight_data.py logs/flight.kmz

# Compare multiple flights
python3 scripts/analyze_flight_data.py logs/*.kmz

# Detailed corner analysis
python3 scripts/analyze_flight_data.py logs/flight.kmz --detailed-corner NE

# With visualization charts
python3 scripts/analyze_flight_data.py logs/*.kmz --visualize
```

## 📁 Scripts Overview

### 1. `analyze_flight_data.py` - **Unified Analysis Tool** ⭐

**The main tool** - consolidates all waypoint and GPS analysis functionality.

**Features:**
- Auto-detects file types (.bin, .kmz, .kml)
- Calculates closest approach to each waypoint
- Validates waypoint hits (15m threshold)
- Multi-file comparison
- Detailed corner analysis with bearing calculations
- Optional visualization charts
- Works with KML/KMZ (no dependencies) or .bin files (requires pymavlink)

**Usage:**
```bash
# Basic analysis
python3 analyze_flight_data.py logs/flight.kmz

# Detailed corner analysis
python3 analyze_flight_data.py logs/flight.kmz --detailed-corner NE

# Multiple files with visualization
python3 analyze_flight_data.py logs/*.kmz --visualize --output results/

# Binary log analysis (requires pymavlink)
python3 analyze_flight_data.py logs/flight.bin
```

**Options:**
- `--detailed-corner <CORNER>` - In-depth analysis of specific corner (GATE, SW, NW, NE, SE)
- `--visualize` - Generate comparison charts (requires matplotlib)
- `--output <DIR>` - Output directory for visualizations

### 2. `analyze_bin_telemetry.py` - **Deep Telemetry Analysis**

Extracts detailed telemetry from binary logs for debugging.

**Features:**
- PYLON script messages (GCS output)
- Flight mode changes
- Navigation targets and waypoint distances
- Errors and warnings
- GPS quality analysis
- **Requires:** pymavlink

**Usage:**
```bash
python3 analyze_bin_telemetry.py logs/flight.bin
```

### 3. `bin_to_kmz.py` - **Binary Log Converter**

Converts ArduPilot .bin files to KMZ format for GPS visualization.

**Features:**
- Extracts GPS tracks from binary logs
- Generates Google Earth compatible KMZ files
- Batch processing support
- **Requires:** pymavlink

**Usage:**
```bash
# Convert single file
python3 bin_to_kmz.py logs/flight.bin

# Batch convert
python3 bin_to_kmz.py logs/*.bin
```

## 🛠️ Setup

### Option 1: Basic Analysis Only (No Setup Required)

The unified analysis tool works with KML/KMZ files using only Python standard library:

```bash
# Just run it!
python3 scripts/analyze_flight_data.py logs/*.kmz
```

**Note:** You'll need KMZ files. If you only have .bin files, use Option 2.

### Option 2: Full Feature Set (With Virtual Environment)

For binary log analysis and advanced features:

```bash
# Navigate to scripts directory
cd scripts/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # Linux/Mac
# or: .venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt

# Now you can use all features:
python3 analyze_flight_data.py ../logs/flight.bin
python3 analyze_bin_telemetry.py ../logs/flight.bin
python3 bin_to_kmz.py ../logs/*.bin

# With visualization support
pip install matplotlib
python3 analyze_flight_data.py ../logs/*.kmz --visualize

# Deactivate when done
deactivate
```

### Quick Setup Script

```bash
cd scripts/
./setup.sh
```

## 📊 Input File Types

### Binary Logs (.bin) - Native ArduPilot Format
- **Used by:** `analyze_flight_data.py`, `analyze_bin_telemetry.py`, `bin_to_kmz.py`
- **Source:** Directly from autopilot (SD card or telemetry download)
- **Contains:** Full telemetry (GPS, IMU, RC, messages, parameters, etc.)
- **Requires:** pymavlink

**How to get .bin logs:**
- **From SD card:** Remove SD card, copy .bin files
- **Mission Planner:** Flight Data → DataFlash Logs → Download
- **MAVProxy:** `log download <lognum>`

### KMZ/KML Files - GPS Track Only
- **Used by:** `analyze_flight_data.py`
- **Source:** Generated from .bin logs or exported from Mission Planner
- **Contains:** GPS track data only (lat, lon, alt)
- **Requires:** No dependencies (standard library only)

**How to generate KMZ:**
```bash
# Using this toolkit
python3 bin_to_kmz.py logs/flight.bin

# Using Mission Planner
# Flight Data → Telemetry Logs → Create KML/GPX
```

## 📝 Recommended Workflow

```bash
# 1. Start with .bin log from flight
logs/2026-02-09_race.bin

# 2. Generate KMZ for GPS analysis
python3 scripts/bin_to_kmz.py logs/2026-02-09_race.bin
# Creates: logs/2026-02-09_race.kmz

# 3. Quick GPS track analysis
python3 scripts/analyze_flight_data.py logs/2026-02-09_race.kmz

# 4. If issues found, deep telemetry dive
python3 scripts/analyze_bin_telemetry.py logs/2026-02-09_race.bin

# 5. Detailed corner investigation
python3 scripts/analyze_flight_data.py logs/2026-02-09_race.kmz --detailed-corner NE

# 6. Compare multiple flights with charts
python3 scripts/analyze_flight_data.py logs/*.kmz --visualize --output results/
```

## 📦 Requirements

**Minimum (basic GPS analysis):**
- Python 3.7+
- Standard library only

**For binary log analysis:**
- `pymavlink` - ArduPilot MAVLink library

**For visualization:**
- `matplotlib` - Charts and plotting

See `requirements.txt` for complete list.

## ⚙️ Waypoint Configuration

Current scripts are configured for the SEFSD T-28 Racing course:

```python
WAYPOINTS = {
    'GATE': {'lat': 32.76300740, 'lon': -117.21375030},
    'SW': {'lat': 32.76304460, 'lon': -117.21412720},
    'NW': {'lat': 32.76338970, 'lon': -117.21420500},
    'NE': {'lat': 32.76351600, 'lon': -117.21344860},
    'SE': {'lat': 32.76310780, 'lon': -117.21337620}
}
```

To use with different courses, edit the `WAYPOINTS` dictionary in `analyze_flight_data.py` or pass as command-line arguments (future enhancement).

## 🔍 Examples

### Basic GPS Analysis
```bash
# Single flight
python3 analyze_flight_data.py logs/2026-02-09_race.kmz

# Output:
# ================================================================================
# Analyzing: 2026-02-09_race.kmz
# ================================================================================
# Loaded 1247 GPS points
# 
# Closest approach to each waypoint:
# Waypoint     Distance (m)    Status
# ---------------------------------------------
# GATE               1.3       ✅ Good
# SW                 5.2       ✅ Good
# NW                12.4       ✅ Good
# NE                21.8       ⚠️ Wide
# SE                 2.1       ✅ Good
```

### Detailed Corner Analysis
```bash
python3 analyze_flight_data.py logs/race.kmz --detailed-corner NE

# Output shows:
# - Course geometry (distances, bearings, turn angles)
# - Pass-by-pass breakdown
# - Entry/exit bearing analysis
# - Overshoot detection
```

### Multi-Flight Comparison
```bash
python3 analyze_flight_data.py logs/flight1.kmz logs/flight2.kmz logs/flight3.kmz

# Output:
# ================================================================================
# SUMMARY ACROSS ALL FLIGHTS
# ================================================================================
# 
# Waypoint     flight1.kmz        flight2.kmz        flight3.kmz
# --------------------------------------------------------------------
# GATE               1.3m               0.9m               1.7m
# SW                 5.2m               3.1m               8.2m
# NW                12.4m               8.2m              13.9m
# NE                21.8m              31.4m              20.4m
# SE                 2.1m               1.5m               2.3m
```

### With Visualization
```bash
python3 analyze_flight_data.py logs/*.kmz --visualize --output results/

# Creates: results/waypoint_comparison.png
```

### Complete Analysis Workflow
```bash
# Activate venv (for binary log support)
cd scripts/
source .venv/bin/activate

# 1. Convert binary to KMZ
python3 bin_to_kmz.py ../logs/2026-02-09*.bin

# 2. Quick GPS analysis
python3 analyze_flight_data.py ../logs/2026-02-09*.kmz

# 3. Deep telemetry analysis
python3 analyze_bin_telemetry.py ../logs/2026-02-09_12-31-02.bin > ../logs/telemetry_report.txt

# 4. Detailed corner analysis
python3 analyze_flight_data.py ../logs/2026-02-09_12-31-02.kmz --detailed-corner NE

# 5. Generate comparison charts
python3 analyze_flight_data.py ../logs/2026-02-09*.kmz --visualize --output ../results/
```

## 🐛 Troubleshooting

### "No module named 'pymavlink'"
Binary log features require pymavlink:
```bash
cd scripts/
source .venv/bin/activate
pip install pymavlink
```

### "No module named 'matplotlib'"
Visualization features require matplotlib:
```bash
pip install matplotlib
```

### "File not found" errors
Use absolute paths or run from the correct directory:
```bash
python3 scripts/analyze_flight_data.py /full/path/to/logs/flight.kmz
```

### KMZ extraction errors
Try manual extraction:
```bash
unzip flight.kmz
python3 scripts/analyze_flight_data.py doc.kml
```

## 🗑️ Removed Scripts (Consolidated)

The following scripts have been **consolidated** into `analyze_flight_data.py`:
- ~~`analyze_logs.py`~~ - Merged into unified tool
- ~~`analyze_flight_logs.py`~~ - Merged into unified tool  
- ~~`analyze_ne_corner.py`~~ - Now `--detailed-corner` option
- ~~`visualize_track_errors.py`~~ - Now `--visualize` option

**Migration guide:**
```bash
# Old way:
python3 analyze_flight_logs.py logs/flight.kmz
python3 analyze_ne_corner.py logs/flight.kmz

# New way:
python3 analyze_flight_data.py logs/flight.kmz --detailed-corner NE
```

## 🔮 Future Enhancements

- [ ] Configuration file support (JSON/YAML)
- [ ] Command-line arguments for custom waypoints
- [ ] Interactive plots with folium (map overlay)
- [ ] CSV export for further analysis
- [ ] Automatic report generation (Markdown/PDF)
- [ ] Wind analysis and compensation metrics

## 📚 Related Files

- `../logs/` - Flight log storage
- `../SEFSD/T-28 Racing/pylon_race_auto_mode.lua` - Racing script
- `BINARY_LOG_ANALYSIS.md` - Binary log analysis documentation

## 🤝 Contributing

When adding new features:
1. Add docstring with usage examples
2. Use standard library when possible
3. Update this README
4. Update requirements.txt if adding dependencies
5. Add error handling for file operations
6. Make scripts executable with shebang line

## 📄 License

These scripts are part of the ardu-missions project.
