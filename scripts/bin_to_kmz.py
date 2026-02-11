#!/usr/bin/env python3
"""
Convert ArduPilot binary logs (.bin) to KMZ files for analysis.

This script reads ArduPilot dataflash logs and generates KMZ files containing
GPS track data. It can be used when KMZ files are not available or need to be
regenerated.

Requirements:
    - pymavlink (pip install pymavlink)

Usage:
    python3 bin_to_kmz.py <logfile.bin> [output.kmz]
    python3 bin_to_kmz.py logs/*.bin  # Convert all

Installation:
    # Activate venv first
    source .venv/bin/activate
    pip install pymavlink
    pip freeze > requirements.txt

Example:
    python3 bin_to_kmz.py ../logs/2026-02-08_12-47-58.bin
    # Creates: ../logs/2026-02-08_12-47-58.kmz
"""

import sys
import os
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from pymavlink import mavutil
    PYMAVLINK_AVAILABLE = True
except ImportError:
    PYMAVLINK_AVAILABLE = False
    print("WARNING: pymavlink not installed")
    print("Install with: pip install pymavlink")
    print("")


def create_kml_from_gps_data(gps_points, output_name="FlightTrack", include_waypoints=True):
    """Create KML XML from GPS data points with optional waypoints and pylons."""
    
    # Pylon racing course waypoints (from pylon_race_auto_mode.lua)
    waypoints = [
        {'name': 'Start Gate', 'lat': 32.76300740, 'lon': -117.21375030, 'color': 'ff00ff00', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/grn-square.png'},
        {'name': 'SW Corner', 'lat': 32.76304460, 'lon': -117.21412720, 'color': 'ffffff00', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png'},
        {'name': 'NW Corner', 'lat': 32.76338970, 'lon': -117.21420500, 'color': 'ffffff00', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png'},
        {'name': 'NE Corner', 'lat': 32.76351600, 'lon': -117.21344860, 'color': 'ffffff00', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png'},
        {'name': 'SE Corner', 'lat': 32.76310780, 'lon': -117.21337620, 'color': 'ffffff00', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png'},
    ]
    
    # Actual pylons
    pylons = [
        {'name': 'West Pylon', 'lat': 32.76314830, 'lon': -117.21414310, 'color': 'ff0000ff', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/red-diamond.png'},
        {'name': 'East Pylon', 'lat': 32.76326200, 'lon': -117.21341080, 'color': 'ff0000ff', 'icon': 'http://maps.google.com/mapfiles/kml/paddle/red-diamond.png'},
    ]
    
    # Create KML structure
    kml = ET.Element('kml', xmlns="http://www.opengis.net/kml/2.2")
    kml.set('xmlns:gx', "http://www.google.com/kml/ext/2.2")
    
    document = ET.SubElement(kml, 'Document')
    name_elem = ET.SubElement(document, 'name')
    name_elem.text = output_name
    
    # Create style for the track line
    style = ET.SubElement(document, 'Style', id='trackStyle')
    line_style = ET.SubElement(style, 'LineStyle')
    color = ET.SubElement(line_style, 'color')
    color.text = 'ff0000ff'  # Red line
    width = ET.SubElement(line_style, 'width')
    width.text = '3'
    
    # Create folder for pylons
    if include_waypoints:
        pylon_folder = ET.SubElement(document, 'Folder')
        pylon_folder_name = ET.SubElement(pylon_folder, 'name')
        pylon_folder_name.text = 'Pylons'
        
        for pylon in pylons:
            # Create style for pylon
            style_id = f"style_{pylon['name'].replace(' ', '_')}"
            pylon_style = ET.SubElement(document, 'Style', id=style_id)
            icon_style = ET.SubElement(pylon_style, 'IconStyle')
            pylon_color = ET.SubElement(icon_style, 'color')
            pylon_color.text = pylon['color']
            pylon_scale = ET.SubElement(icon_style, 'scale')
            pylon_scale.text = '1.5'
            icon = ET.SubElement(icon_style, 'Icon')
            href = ET.SubElement(icon, 'href')
            href.text = pylon['icon']
            
            # Create placemark for pylon
            pylon_pm = ET.SubElement(pylon_folder, 'Placemark')
            pylon_pm_name = ET.SubElement(pylon_pm, 'name')
            pylon_pm_name.text = pylon['name']
            pylon_style_url = ET.SubElement(pylon_pm, 'styleUrl')
            pylon_style_url.text = f'#{style_id}'
            pylon_point = ET.SubElement(pylon_pm, 'Point')
            pylon_coords = ET.SubElement(pylon_point, 'coordinates')
            pylon_coords.text = f"{pylon['lon']:.8f},{pylon['lat']:.8f},0"
        
        # Create folder for waypoints
        wp_folder = ET.SubElement(document, 'Folder')
        wp_folder_name = ET.SubElement(wp_folder, 'name')
        wp_folder_name.text = 'Course Waypoints'
        
        for wp in waypoints:
            # Create style for waypoint
            style_id = f"style_{wp['name'].replace(' ', '_')}"
            wp_style = ET.SubElement(document, 'Style', id=style_id)
            icon_style = ET.SubElement(wp_style, 'IconStyle')
            wp_color = ET.SubElement(icon_style, 'color')
            wp_color.text = wp['color']
            wp_scale = ET.SubElement(icon_style, 'scale')
            wp_scale.text = '1.2'
            icon = ET.SubElement(icon_style, 'Icon')
            href = ET.SubElement(icon, 'href')
            href.text = wp['icon']
            
            # Create placemark for waypoint
            wp_pm = ET.SubElement(wp_folder, 'Placemark')
            wp_pm_name = ET.SubElement(wp_pm, 'name')
            wp_pm_name.text = wp['name']
            wp_style_url = ET.SubElement(wp_pm, 'styleUrl')
            wp_style_url.text = f'#{style_id}'
            wp_point = ET.SubElement(wp_pm, 'Point')
            wp_coords = ET.SubElement(wp_point, 'coordinates')
            wp_coords.text = f"{wp['lon']:.8f},{wp['lat']:.8f},0"
    
    # Create placemark with track
    placemark = ET.SubElement(document, 'Placemark')
    pm_name = ET.SubElement(placemark, 'name')
    pm_name.text = 'GPS Track'
    style_url = ET.SubElement(placemark, 'styleUrl')
    style_url.text = '#trackStyle'
    
    # Create line string with coordinates
    line_string = ET.SubElement(placemark, 'LineString')
    coords = ET.SubElement(line_string, 'coordinates')
    
    # Format: lon,lat,alt (one per line)
    coord_text = '\n'
    for point in gps_points:
        coord_text += f"{point['lon']:.8f},{point['lat']:.8f},{point['alt']:.2f}\n"
    coords.text = coord_text
    
    # Convert to string
    tree = ET.ElementTree(kml)
    ET.indent(tree, space='    ')
    
    import io
    output = io.BytesIO()
    tree.write(output, encoding='utf-8', xml_declaration=True)
    return output.getvalue()


def extract_gps_from_bin(bin_path):
    """Extract GPS data from ArduPilot binary log using pymavlink."""
    if not PYMAVLINK_AVAILABLE:
        print("ERROR: pymavlink is required to parse .bin files")
        print("Install with: pip install pymavlink")
        return None
    
    print(f"Parsing binary log: {bin_path}")
    
    try:
        mlog = mavutil.mavlink_connection(bin_path)
    except Exception as e:
        print(f"ERROR: Failed to open log file: {e}")
        return None
    
    gps_points = []
    msg_count = 0
    
    # Read through the log looking for GPS messages
    while True:
        msg = mlog.recv_match(type=['GPS', 'GPS2', 'POS'], blocking=False)
        if msg is None:
            break
        
        msg_count += 1
        
        # Extract position data (format varies by message type)
        try:
            if msg.get_type() == 'GPS':
                lat = msg.Lat
                lon = msg.Lng
                alt = msg.Alt
                status = msg.Status
                
                # Only include valid GPS fixes
                if status >= 3:  # 3D fix or better
                    gps_points.append({
                        'lat': lat,
                        'lon': lon,
                        'alt': alt
                    })
            
            elif msg.get_type() == 'POS':
                lat = msg.Lat
                lon = msg.Lng
                alt = msg.Alt
                gps_points.append({
                    'lat': lat,
                    'lon': lon,
                    'alt': alt
                })
        
        except AttributeError:
            # Message doesn't have expected fields
            continue
        
        # Progress indicator
        if msg_count % 1000 == 0:
            print(f"  Processed {msg_count} messages, found {len(gps_points)} GPS points...")
    
    print(f"✓ Extracted {len(gps_points)} GPS points from {msg_count} messages")
    return gps_points


def create_kmz(gps_points, output_path, name="FlightTrack", include_waypoints=True):
    """Create KMZ file (zipped KML) from GPS points."""
    
    # Generate KML content
    kml_content = create_kml_from_gps_data(gps_points, name, include_waypoints)
    
    # Create KMZ (ZIP archive with doc.kml inside)
    try:
        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as kmz:
            kmz.writestr('doc.kml', kml_content)
        print(f"✓ Created KMZ: {output_path}")
        if include_waypoints:
            print(f"  Includes: 2 pylons + 5 course waypoints")
        return True
    except Exception as e:
        print(f"ERROR: Failed to create KMZ: {e}")
        return False


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
        print("Usage: python3 bin_to_kmz.py <logfile.bin> [output.kmz]")
        print("")
        print("Examples:")
        print("  python3 bin_to_kmz.py ../logs/flight.bin")
        print("  python3 bin_to_kmz.py ../logs/flight.bin ../logs/flight.kmz")
        print("  python3 bin_to_kmz.py ../logs/*.bin  # Convert all")
        sys.exit(1)
    
    # Process each input file
    for bin_path in sys.argv[1:]:
        if not os.path.exists(bin_path):
            print(f"ERROR: File not found: {bin_path}")
            continue
        
        if not bin_path.endswith('.bin'):
            print(f"WARNING: Skipping non-.bin file: {bin_path}")
            continue
        
        print(f"\n{'='*60}")
        print(f"Converting: {bin_path}")
        print(f"{'='*60}")
        
        # Determine output path
        if len(sys.argv) == 3 and not sys.argv[2].endswith('.bin'):
            # Explicit output file provided
            output_path = sys.argv[2]
        else:
            # Auto-generate output filename
            output_path = bin_path.replace('.bin', '.kmz')
        
        # Extract GPS data from binary log
        gps_points = extract_gps_from_bin(bin_path)
        
        if not gps_points:
            print("ERROR: No GPS data extracted from log")
            continue
        
        if len(gps_points) < 10:
            print(f"WARNING: Only {len(gps_points)} GPS points found - log may be incomplete")
        
        # Create KMZ file
        log_name = Path(bin_path).stem
        success = create_kmz(gps_points, output_path, log_name)
        
        if success:
            # Print file size
            size_kb = os.path.getsize(output_path) / 1024
            print(f"  File size: {size_kb:.1f} KB")
            print(f"  GPS points: {len(gps_points)}")


if __name__ == '__main__':
    main()
