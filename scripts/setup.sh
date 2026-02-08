#!/bin/bash
# Quick setup script for ArduPilot flight log analysis

echo "=========================================="
echo "ArduPilot Log Analysis - Quick Setup"
echo "=========================================="
echo ""

# Check Python version
python_version=$(python3 --version 2>&1)
echo "✓ Found: $python_version"

# Create virtual environment
echo ""
echo "Creating virtual environment..."
if [ -d ".venv" ]; then
    echo "⚠️  Virtual environment already exists (.venv/)"
    read -p "Delete and recreate? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -rf .venv
        python3 -m venv .venv
        echo "✓ Virtual environment recreated"
    else
        echo "✓ Using existing virtual environment"
    fi
else
    python3 -m venv .venv
    echo "✓ Virtual environment created"
fi

# Activate instructions
echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "To start working:"
echo "  1. Activate virtual environment:"
echo "     source .venv/bin/activate"
echo ""
echo "  2. Run analysis scripts:"
echo "     python3 analyze_flight_logs.py ../logs/*.kmz"
echo "     python3 analyze_ne_corner.py ../logs/flight.kmz"
echo ""
echo "  3. When done:"
echo "     deactivate"
echo ""
echo "See README.md for detailed usage instructions"
echo ""
