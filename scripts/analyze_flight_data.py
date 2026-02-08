#!/usr/bin/env python3
"""
Unified ArduPilot Flight Log Analysis Tool

Analyzes both binary (.bin) and GPS track (.kmz/.kml) files for pylon racing missions.
Provides waypoint proximity analysis, detailed corner analysis, and optional visualization.

Requirements:
    - Python 3.7+ (standard library for KML/KMZ analysis)
    - pymavlink (optional, for .bin file analysis)
    - matplotlib (optional, for --visualize flag)

Usage:
    # Basic waypoint analysis
    python3 analyze_flight_data.py logs/flight.kmz
    python3 analyze_flight_data.py logs/flight.bin
    
    # Detailed corner analysis
    python3 analyze_flight_data.py logs/flight.kmz --detailed-corner NE
    
    # Multiple files comparison
    python3 analyze_flight_data.py logs/flight1.kmz logs/flight2.kmz
    
    # With visualization
    python3 analyze_flight_data.py logs/*.kmz --visualize

Examples:
    python3 analyze_flight_data.py ../logs/2026-02-08*.kmz
    python3 analyze_flight_data.py ../logs/race.bin --detailed-corner NE
    python3 analyze_flight_data.py ../logs/*.kmz --visualize --output results/
"""

import sys
import os
import argparse
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from math import radians, sin, cos, sqrt, atan2, degrees
from pathlib import Path
from collections import defaultdict

# Optional dependencies
try:
    from pymavlink import mavutil
    PYMAVLINK_AVAILABLE = True
except ImportError:
    PYMAVLINK_AVAILABLE = False

try:
    import matplotlib.pyplot as plt
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False

# Course waypoints for SEFSD T-28 Racing
WAYPOINTS = {
    'GATE': {'lat': 32.76300740, 'lon': -117.21375030, 'name': 'START_GATE'},
    'SW': {'lat': 32.76304460, 'lon': -117.21412720, 'name': 'SW'},
    'NW': {'lat': 32.76338970, 'lon': -117.21420500, 'name': 'NW'},
    'NE': {'lat': 32.76351600, 'lon': -117.21344860, 'name': 'NE'},
    'SE': {'lat': 32.76310780, 'lon': -117.21337620, 'name': 'SE'}
}


# ============================================================================
# GEOMETRY UTILITIES
# ============================================================================

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two lat/lon points in meters."""
    R = 6371000  # Earth radius in meters
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c


def bearing(lat1, lon1, lat2, lon2):
    """Calculate bearing from point 1 to point 2 in degrees."""
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlon = lon2 - lon1
    x = sin(dlon) * cos(lat2)
    y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
    initial_bearing = atan2(x, y)
    return (degrees(initial_bearing) + 360) % 360


# ============================================================================
# FILE PARSERS
# ============================================================================

def extract_kml_from_kmz(kmz_path):
    """Extract KML content from KMZ file."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.kml', delete=False) as tmp:
        with zipfile.ZipFile(kmz_path, 'r') as kmz:
            kml_content = kmz.read('doc.kml').decode('utf-8')
            tmp.write(kml_content)
            return tmp.name


def parse_kml(filename):
    """Extract GPS coordinates from KML file."""
    tree = ET.parse(filename)
    root = tree.getroot()
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    coords_list = []
    for placemark in root.findall('.//kml:Placemark', ns):
        coords_elem = placemark.find('.//kml:coordinates', ns)
        if coords_elem is not None and coords_elem.text:
            coords_text = coords_elem.text.strip()
            for line in coords_text.split():
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        coords_list.append({
                            'lat': float(parts[1]),
                            'lon': float(parts[0]),
                            'alt': float(parts[2]) if len(parts) > 2 else 0
                        })
                    except ValueError:
                        pass
    return coords_list


def extract_gps_from_bin(bin_path):
    """Extract GPS data from ArduPilot binary log using pymavlink."""
    if not PYMAVLINK_AVAILABLE:
        print("ERROR: pymavlink is required to parse .bin files")
        print("Install with: pip install pymavlink")
        return None
    
    try:
        mlog = mavutil.mavlink_connection(bin_path)
    except Exception as e:
        print(f"ERROR: Failed to open log file: {e}")
        return None
    
    gps_points = []
    while True:
        msg = mlog.recv_match(type=['GPS'], blocking=False)
        if msg is None:
            break
        
        try:
            if msg.get_type() == 'GPS' and msg.Status >= 3:  # 3D fix or better
                gps_points.append({
                    'lat': msg.Lat,
                    'lon': msg.Lng,
                    'alt': msg.Alt
                })
        except AttributeError:
            continue
    
    return gps_points


def load_gps_data(file_path):
    """Auto-detect file type and load GPS data."""
    if not os.path.exists(file_path):
        print(f"ERROR: File not found: {file_path}")
        return None
    
    file_ext = file_path.lower().split('.')[-1]
    
    if file_ext == 'kmz':
        temp_file = extract_kml_from_kmz(file_path)
        coords = parse_kml(temp_file)
        os.unlink(temp_file)
        return coords
    elif file_ext == 'kml':
        return parse_kml(file_path)
    elif file_ext == 'bin':
        return extract_gps_from_bin(file_path)
    else:
        print(f"ERROR: Unsupported file type: {file_ext}")
        return None


# ============================================================================
# WAYPOINT ANALYSIS
# ============================================================================

def analyze_waypoint_proximity(coords, waypoints=WAYPOINTS):
    """Analyze how close the flight path got to each waypoint."""
    results = {}
    for wp_name, wp_data in waypoints.items():
        min_dist = float('inf')
        closest_idx = None
        
        for i, point in enumerate(coords):
            dist = haversine_distance(point['lat'], point['lon'], 
                                     wp_data['lat'], wp_data['lon'])
            if dist < min_dist:
                min_dist = dist
                closest_idx = i
        
        results[wp_name] = {
            'min_distance': min_dist,
            'point_index': closest_idx
        }
    
    return results


def find_corner_passes(coords, corner_wp, search_radius=50):
    """
    Find all passes through a corner (points within search_radius).
    Groups consecutive points into distinct passes.
    """
    corner_points = []
    for i, point in enumerate(coords):
        dist = haversine_distance(point['lat'], point['lon'], 
                                 corner_wp['lat'], corner_wp['lon'])
        if dist < search_radius:
            corner_points.append({
                'index': i,
                'lat': point['lat'],
                'lon': point['lon'],
                'dist': dist
            })
    
    if not corner_points:
        return []
    
    # Group consecutive points into passes
    passes = []
    current_pass = [corner_points[0]]
    for i in range(1, len(corner_points)):
        if corner_points[i]['index'] - corner_points[i-1]['index'] < 10:
            current_pass.append(corner_points[i])
        else:
            passes.append(current_pass)
            current_pass = [corner_points[i]]
    passes.append(current_pass)
    
    return passes


def analyze_corner_detail(coords, corner_name, waypoints=WAYPOINTS):
    """Detailed analysis of a specific corner including bearing analysis."""
    if corner_name not in waypoints:
        print(f"ERROR: Unknown corner '{corner_name}'")
        return None
    
    corner_wp = waypoints[corner_name]
    
    # Find adjacent waypoints for bearing calculations
    corner_order = ['GATE', 'SW', 'NW', 'NE', 'SE']
    if corner_name not in corner_order:
        print(f"WARNING: Cannot determine adjacent waypoints for {corner_name}")
        prev_wp = next_wp = None
    else:
        idx = corner_order.index(corner_name)
        prev_wp = waypoints[corner_order[idx - 1]] if idx > 0 else None
        next_wp = waypoints[corner_order[(idx + 1) % len(corner_order)]]
    
    # Find all points near the corner
    passes = find_corner_passes(coords, corner_wp, search_radius=50)
    
    print(f"\n{'='*80}")
    print(f"DETAILED {corner_name} CORNER ANALYSIS")
    print(f"{'='*80}")
    
    if prev_wp and next_wp:
        dist_prev = haversine_distance(prev_wp['lat'], prev_wp['lon'],
                                      corner_wp['lat'], corner_wp['lon'])
        dist_next = haversine_distance(corner_wp['lat'], corner_wp['lon'],
                                      next_wp['lat'], next_wp['lon'])
        brg_in = bearing(prev_wp['lat'], prev_wp['lon'],
                        corner_wp['lat'], corner_wp['lon'])
        brg_out = bearing(corner_wp['lat'], corner_wp['lon'],
                         next_wp['lat'], next_wp['lon'])
        turn_angle = abs(brg_out - brg_in)
        
        print(f"\nCourse Geometry:")
        print(f"  Inbound: {dist_prev:.1f}m @ {brg_in:.0f}°")
        print(f"  Outbound: {dist_next:.1f}m @ {brg_out:.0f}°")
        print(f"  Turn angle: {turn_angle:.0f}°")
    
    print(f"\nTotal passes detected: {len(passes)}")
    
    for i, pass_points in enumerate(passes[:8], 1):  # Limit to first 8
        closest = min(pass_points, key=lambda x: x['dist'])
        
        print(f"\n  Pass {i}: {len(pass_points)} points")
        print(f"    Closest approach: {closest['dist']:.1f}m", end="")
        if closest['dist'] < 15:
            print(" ✅")
        else:
            print(" ⚠️ WIDE")
        
        if prev_wp:
            entry_brg = bearing(prev_wp['lat'], prev_wp['lon'],
                              pass_points[0]['lat'], pass_points[0]['lon'])
            ideal_brg = bearing(prev_wp['lat'], prev_wp['lon'],
                              corner_wp['lat'], corner_wp['lon'])
            brg_error = abs(entry_brg - ideal_brg)
            print(f"    Entry bearing: {entry_brg:.0f}° (ideal: {ideal_brg:.0f}°, error: {brg_error:.0f}°)")
        
        if next_wp:
            exit_brg = bearing(pass_points[-1]['lat'], pass_points[-1]['lon'],
                             next_wp['lat'], next_wp['lon'])
            ideal_exit_brg = bearing(corner_wp['lat'], corner_wp['lon'],
                                    next_wp['lat'], next_wp['lon'])
            exit_error = abs(exit_brg - ideal_exit_brg)
            print(f"    Exit bearing: {exit_brg:.0f}° (ideal: {ideal_exit_brg:.0f}°, error: {exit_error:.0f}°)")
    
    if len(passes) > 8:
        print(f"\n  ... {len(passes) - 8} more passes not shown")
    
    return passes


# ============================================================================
# VISUALIZATION
# ============================================================================

def create_visualization(results_by_file, output_dir='.'):
    """Create comparative visualization charts."""
    if not MATPLOTLIB_AVAILABLE:
        print("ERROR: matplotlib is required for --visualize")
        print("Install with: pip install matplotlib")
        return False
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Prepare data
    waypoint_names = ['GATE', 'SW', 'NW', 'NE', 'SE']
    flights = {}
    for filename, result in results_by_file.items():
        short_name = os.path.basename(filename)[:15]
        distances = [result['waypoints'][wp]['min_distance'] for wp in waypoint_names]
        flights[short_name] = distances
    
    # Create comparison chart
    fig, ax = plt.subplots(figsize=(14, 7))
    
    x = range(len(waypoint_names))
    width = 0.8 / len(flights)
    colors = plt.cm.tab10(range(len(flights)))
    
    for i, (flight_name, distances) in enumerate(flights.items()):
        offset = width * (i - len(flights) / 2 + 0.5)
        bars = ax.bar([p + offset for p in x], distances, width, 
                     label=flight_name, color=colors[i], alpha=0.8)
        
        # Add value labels
        for bar in bars:
            height = bar.get_height()
            label_color = 'red' if height > 15 else 'black'
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{height:.1f}', ha='center', va='bottom', 
                   fontsize=8, color=label_color)
    
    # Add threshold line
    ax.axhline(y=15.0, color='red', linestyle='--', linewidth=2, 
              label='Validation Threshold (15m)')
    
    ax.set_xlabel('Waypoint', fontsize=12, fontweight='bold')
    ax.set_ylabel('Minimum Distance (meters)', fontsize=12, fontweight='bold')
    ax.set_title('Track Error by Waypoint - Flight Comparison\n(Lower is Better)', 
                fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(waypoint_names)
    ax.legend(loc='upper left', fontsize=9)
    ax.grid(True, alpha=0.3, axis='y')
    
    output_path = os.path.join(output_dir, 'waypoint_comparison.png')
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"\n✅ Visualization saved: {output_path}")
    plt.close()
    
    return True


# ============================================================================
# MAIN ANALYSIS LOGIC
# ============================================================================

def analyze_file(file_path, args):
    """Analyze a single flight log file."""
    print(f"\n{'='*80}")
    print(f"Analyzing: {os.path.basename(file_path)}")
    print(f"{'='*80}")
    
    # Load GPS data
    coords = load_gps_data(file_path)
    if not coords:
        return None
    
    print(f"Loaded {len(coords)} GPS points")
    
    # Waypoint proximity analysis
    waypoint_results = analyze_waypoint_proximity(coords)
    
    print(f"\nClosest approach to each waypoint:")
    print(f"{'Waypoint':<12} {'Distance (m)':<15} {'Status'}")
    print("-" * 45)
    
    for wp_name in ['GATE', 'SW', 'NW', 'NE', 'SE']:
        dist = waypoint_results[wp_name]['min_distance']
        status = "✅ Good" if dist < 15 else "⚠️ Wide"
        print(f"{wp_name:<12} {dist:>13.1f}  {status}")
    
    # Detailed corner analysis if requested
    if args.detailed_corner:
        analyze_corner_detail(coords, args.detailed_corner.upper())
    
    return {
        'filename': file_path,
        'coords': coords,
        'waypoints': waypoint_results
    }


def main():
    parser = argparse.ArgumentParser(
        description='Unified ArduPilot flight log analysis for pylon racing',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s logs/flight.kmz
  %(prog)s logs/flight1.kmz logs/flight2.kmz --visualize
  %(prog)s logs/flight.bin --detailed-corner NE
  %(prog)s logs/*.kmz --output results/
        """
    )
    
    parser.add_argument('files', nargs='+', help='Log files to analyze (.bin, .kmz, or .kml)')
    parser.add_argument('--detailed-corner', metavar='CORNER',
                       help='Detailed analysis of specific corner (GATE, SW, NW, NE, SE)')
    parser.add_argument('--visualize', action='store_true',
                       help='Generate comparison charts (requires matplotlib)')
    parser.add_argument('--output', '-o', default='.',
                       help='Output directory for visualizations (default: current dir)')
    
    args = parser.parse_args()
    
    # Analyze all files
    results = {}
    for file_path in args.files:
        result = analyze_file(file_path, args)
        if result:
            results[file_path] = result
    
    # Summary across all files
    if len(results) > 1:
        print(f"\n\n{'='*80}")
        print("SUMMARY ACROSS ALL FLIGHTS")
        print(f"{'='*80}\n")
        
        print(f"{'Waypoint':<12} ", end='')
        for filename in results.keys():
            print(f"{os.path.basename(filename)[:15]:<18}", end='')
        print()
        print("-" * (12 + 18 * len(results)))
        
        for wp_name in ['GATE', 'SW', 'NW', 'NE', 'SE']:
            print(f"{wp_name:<12} ", end='')
            for result in results.values():
                dist = result['waypoints'][wp_name]['min_distance']
                print(f"{dist:>16.1f}m ", end='')
            print()
    
    # Generate visualizations if requested
    if args.visualize and len(results) > 0:
        create_visualization(results, args.output)
    
    print(f"\n{'='*80}")
    print("ANALYSIS COMPLETE")
    print(f"{'='*80}")
    print(f"✓ Analyzed {len(results)} file(s)")


if __name__ == '__main__':
    main()
