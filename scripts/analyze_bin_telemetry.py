#!/usr/bin/env python3
"""
Analyze ArduPilot binary logs for detailed telemetry and debugging.

This script extracts and analyzes key telemetry data from ArduPilot .bin logs:
- Script execution messages (PYLON script output)
- Navigation state (mode, waypoint, target location)
- Performance metrics (airspeed, groundspeed, altitude)
- Control surface activity
- GPS accuracy

Requirements:
    - pymavlink (pip install pymavlink)

Usage:
    python3 analyze_bin_telemetry.py <logfile.bin>
    python3 analyze_bin_telemetry.py logs/*.bin

Example:
    python3 analyze_bin_telemetry.py ../logs/2026-02-08_12-47-58.bin
"""

import sys
import os
from pathlib import Path
from collections import defaultdict

try:
    from pymavlink import mavutil
    PYMAVLINK_AVAILABLE = True
except ImportError:
    PYMAVLINK_AVAILABLE = False


def analyze_script_messages(mlog):
    """Extract all script (GCS) messages - these show PYLON script output."""
    print("\n" + "="*80)
    print("SCRIPT MESSAGES (PYLON)")
    print("="*80)
    
    mlog.rewind()
    script_messages = []
    
    while True:
        msg = mlog.recv_match(type='MSG', blocking=False)
        if msg is None:
            break
        
        try:
            text = msg.Message
            timestamp = msg._timestamp
            
            # Filter for PYLON-related messages
            if 'PYLON' in text or 'LAP' in text or 'RACE' in text or 'GATE' in text:
                script_messages.append({
                    'time': timestamp,
                    'message': text
                })
        except AttributeError:
            continue
    
    if not script_messages:
        print("⚠️  No PYLON script messages found")
        print("   (Script may not have been running during this flight)")
        return []
    
    print(f"Found {len(script_messages)} PYLON-related messages:\n")
    
    for i, msg in enumerate(script_messages[:50]):  # Limit output
        print(f"  [{msg['time']:.1f}s] {msg['message']}")
    
    if len(script_messages) > 50:
        print(f"\n  ... {len(script_messages) - 50} more messages not shown")
    
    return script_messages


def analyze_mode_changes(mlog):
    """Track flight mode changes."""
    print("\n" + "="*80)
    print("FLIGHT MODE CHANGES")
    print("="*80)
    
    mlog.rewind()
    modes = []
    
    while True:
        msg = mlog.recv_match(type='MODE', blocking=False)
        if msg is None:
            break
        
        try:
            mode_name = msg.Mode
            timestamp = msg._timestamp
            modes.append({
                'time': timestamp,
                'mode': mode_name
            })
        except AttributeError:
            continue
    
    if not modes:
        print("⚠️  No mode change data found")
        return []
    
    print(f"Found {len(modes)} mode changes:\n")
    for mode in modes:
        print(f"  [{mode['time']:.1f}s] {mode['mode']}")
    
    return modes


def analyze_navigation_target(mlog):
    """Analyze where the autopilot was trying to navigate."""
    print("\n" + "="*80)
    print("NAVIGATION TARGETS (Sample)")
    print("="*80)
    
    mlog.rewind()
    targets = []
    sample_interval = 2.0  # seconds
    last_sample_time = 0
    
    while True:
        msg = mlog.recv_match(type=['NTUN', 'TECS'], blocking=False)
        if msg is None:
            break
        
        try:
            timestamp = msg._timestamp
            
            # Sample at regular intervals
            if timestamp - last_sample_time < sample_interval:
                continue
            
            last_sample_time = timestamp
            
            if msg.get_type() == 'NTUN':
                # ArduPilot dataflash uses Dist/AltE/TBrg/NavBrg; some logs use WpDist/BrErr/AltErr
                wp_dist = getattr(msg, 'WpDist', None) or getattr(msg, 'Dist', None)
                bearing_err = getattr(msg, 'BrErr', None)
                if bearing_err is None and hasattr(msg, 'NavBrg') and hasattr(msg, 'TBrg'):
                    try:
                        bearing_err = getattr(msg, 'NavBrg', 0) - getattr(msg, 'TBrg', 0)
                    except (TypeError, AttributeError):
                        pass
                alt_err = getattr(msg, 'AltErr', None) or getattr(msg, 'AltE', None)
                targets.append({
                    'time': timestamp,
                    'wp_dist': wp_dist,
                    'bearing_error': bearing_err,
                    'altitude_error': alt_err,
                })
        except AttributeError:
            continue
    
    if not targets:
        print("⚠️  No navigation target data found")
        return []
    
    print(f"Sampled {len(targets)} navigation points (every {sample_interval}s):\n")
    print("  Time(s)  | WP Dist(m) | Bearing Err(deg) | Alt Err(m)")
    print("  " + "-"*60)
    
    for target in targets[:20]:  # Show first 20 samples
        wp_dist = f"{target['wp_dist']:.1f}" if target['wp_dist'] is not None else "N/A"
        brg_err = f"{target['bearing_error']:.1f}" if target['bearing_error'] is not None else "N/A"
        alt_err = f"{target['altitude_error']:.1f}" if target['altitude_error'] is not None else "N/A"
        print(f"  {target['time']:7.1f} | {wp_dist:>10s} | {brg_err:>16s} | {alt_err:>10s}")
    
    if len(targets) > 20:
        print(f"\n  ... {len(targets) - 20} more samples not shown")
    
    return targets


def analyze_errors_and_warnings(mlog):
    """Find error and warning messages."""
    print("\n" + "="*80)
    print("ERRORS AND WARNINGS")
    print("="*80)
    
    mlog.rewind()
    issues = []
    
    while True:
        msg = mlog.recv_match(type=['ERR', 'MSG'], blocking=False)
        if msg is None:
            break
        
        try:
            timestamp = msg._timestamp
            
            if msg.get_type() == 'ERR':
                issues.append({
                    'time': timestamp,
                    'type': 'ERROR',
                    'message': f"Subsys={msg.Subsys}, ECode={msg.ECode}"
                })
            elif msg.get_type() == 'MSG':
                text = msg.Message
                if any(keyword in text.upper() for keyword in ['ERROR', 'FAIL', 'WARNING', 'ERR']):
                    issues.append({
                        'time': timestamp,
                        'type': 'WARNING',
                        'message': text
                    })
        except AttributeError:
            continue
    
    if not issues:
        print("✅ No errors or warnings found")
        return []
    
    print(f"⚠️  Found {len(issues)} issues:\n")
    for issue in issues:
        print(f"  [{issue['time']:.1f}s] {issue['type']}: {issue['message']}")
    
    return issues


def analyze_gps_quality(mlog):
    """Analyze GPS signal quality and accuracy."""
    print("\n" + "="*80)
    print("GPS QUALITY SUMMARY")
    print("="*80)
    
    mlog.rewind()
    gps_stats = {
        'no_fix': 0,
        '2d_fix': 0,
        '3d_fix': 0,
        'dgps': 0,
        'rtk_float': 0,
        'rtk_fixed': 0,
        'num_sats': [],
        'hdop': []
    }
    
    while True:
        msg = mlog.recv_match(type='GPS', blocking=False)
        if msg is None:
            break
        
        try:
            status = msg.Status
            num_sats = msg.NSats if hasattr(msg, 'NSats') else 0
            hdop = msg.HDop if hasattr(msg, 'HDop') else 0
            
            # Count fix types
            if status == 0:
                gps_stats['no_fix'] += 1
            elif status == 2:
                gps_stats['2d_fix'] += 1
            elif status == 3:
                gps_stats['3d_fix'] += 1
            elif status == 4:
                gps_stats['dgps'] += 1
            elif status == 5:
                gps_stats['rtk_float'] += 1
            elif status == 6:
                gps_stats['rtk_fixed'] += 1
            
            if num_sats > 0:
                gps_stats['num_sats'].append(num_sats)
            if hdop > 0:
                gps_stats['hdop'].append(hdop)
        
        except AttributeError:
            continue
    
    total_samples = sum([
        gps_stats['no_fix'],
        gps_stats['2d_fix'],
        gps_stats['3d_fix'],
        gps_stats['dgps'],
        gps_stats['rtk_float'],
        gps_stats['rtk_fixed']
    ])
    
    if total_samples == 0:
        print("⚠️  No GPS data found")
        return gps_stats
    
    print(f"Total GPS samples: {total_samples}\n")
    print("Fix type distribution:")
    print(f"  No fix:     {gps_stats['no_fix']:6d} ({100*gps_stats['no_fix']/total_samples:5.1f}%)")
    print(f"  2D fix:     {gps_stats['2d_fix']:6d} ({100*gps_stats['2d_fix']/total_samples:5.1f}%)")
    print(f"  3D fix:     {gps_stats['3d_fix']:6d} ({100*gps_stats['3d_fix']/total_samples:5.1f}%)")
    print(f"  DGPS:       {gps_stats['dgps']:6d} ({100*gps_stats['dgps']/total_samples:5.1f}%)")
    print(f"  RTK float:  {gps_stats['rtk_float']:6d} ({100*gps_stats['rtk_float']/total_samples:5.1f}%)")
    print(f"  RTK fixed:  {gps_stats['rtk_fixed']:6d} ({100*gps_stats['rtk_fixed']/total_samples:5.1f}%)")
    
    if gps_stats['num_sats']:
        avg_sats = sum(gps_stats['num_sats']) / len(gps_stats['num_sats'])
        min_sats = min(gps_stats['num_sats'])
        max_sats = max(gps_stats['num_sats'])
        print(f"\nSatellites: {avg_sats:.1f} avg (min: {min_sats}, max: {max_sats})")
    
    if gps_stats['hdop']:
        avg_hdop = sum(gps_stats['hdop']) / len(gps_stats['hdop'])
        print(f"HDOP: {avg_hdop:.2f} avg (lower is better, <2 is good)")
    
    return gps_stats


def main():
    if not PYMAVLINK_AVAILABLE:
        print("ERROR: This script requires pymavlink")
        print("")
        print("Install instructions:")
        print("  1. Activate virtual environment:")
        print("     cd scripts/")
        print("     source .venv/bin/activate")
        print("")
        print("  2. Install pymavlink:")
        print("     pip install pymavlink")
        print("")
        print("  3. Update requirements.txt:")
        print("     pip freeze > requirements.txt")
        print("")
        sys.exit(1)
    
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_bin_telemetry.py <logfile.bin>")
        print("")
        print("Examples:")
        print("  python3 analyze_bin_telemetry.py ../logs/flight.bin")
        print("  python3 analyze_bin_telemetry.py ../logs/2026-02-08*.bin")
        sys.exit(1)
    
    for log_file in sys.argv[1:]:
        if not os.path.exists(log_file):
            print(f"ERROR: File not found: {log_file}")
            continue
        
        print("\n" + "="*80)
        print(f"ANALYZING: {log_file}")
        print("="*80)
        print(f"File size: {os.path.getsize(log_file) / 1024 / 1024:.1f} MB")
        
        try:
            mlog = mavutil.mavlink_connection(log_file)
        except Exception as e:
            print(f"ERROR: Failed to open log file: {e}")
            continue
        
        # Run analyses
        script_msgs = analyze_script_messages(mlog)
        modes = analyze_mode_changes(mlog)
        errors = analyze_errors_and_warnings(mlog)
        gps = analyze_gps_quality(mlog)
        nav = analyze_navigation_target(mlog)
        
        print("\n" + "="*80)
        print("ANALYSIS COMPLETE")
        print("="*80)
        print(f"✓ {len(script_msgs)} script messages")
        print(f"✓ {len(modes)} mode changes")
        print(f"✓ {len(errors)} errors/warnings")
        print(f"✓ GPS: {sum(gps.get('num_sats', [0])) // max(len(gps.get('num_sats', [1])), 1)} avg satellites")
        print(f"✓ {len(nav)} navigation samples")


if __name__ == '__main__':
    main()
