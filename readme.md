# Ardu-Missions

ArduPilot mission files and Lua scripts for autonomous flight at **Silent Electric Flyers of San Diego** (SEFSD).

https://www.sefsd.org/

---

## Project Structure

```
ardu-missions/
└── SEFSD/
    └── T-28 Racing/
        ├── pylon_race_auto_mode.lua   # Main racing script
        ├── pylon_race_mission.waypoints
        ├── Pylon Locations.md
        └── AUTO_MODE_SETUP_GUIDE.md
```

---

## T-28 Pylon Racing

Lua script for automated pylon racing in ArduPilot **AUTO** mode. Uses `NAV_SCRIPT_TIME` to take control during a mission and fly a clockwise oval pattern around West and East pylons.

**Flow:** Start gate → SW corner → NW corner → NE corner → SE corner → repeat

| File | Description |
|------|-------------|
| `pylon_race_auto_mode.lua` | Main script — configurable laps, altitude, turn radius |
| `pylon_race_mission.waypoints` | Sample mission waypoints |
| `Pylon Locations.md` | Course coordinates (start gate, West/East pylons) |
| `AUTO_MODE_SETUP_GUIDE.md` | Installation, mission setup, parameters |

---

## References

- [ArduPilot Lua Scripts](https://ardupilot.org/plane/docs/common-lua-scripts.html)
