#!/bin/bash
# 🧪 Test script for the PRODUCTION osquery ancestry package
# This demonstrates the "install and go" experience

set -e

PACKAGE_NAME="osquery-ancestry-sensor_5.18.1-ancestry-production_amd64.deb"

echo "🧪 Testing Production osquery Ancestry Package"
echo "=============================================="
echo ""

# Check if package exists
if [ ! -f "$PACKAGE_NAME" ]; then
    echo "❌ Package not found: $PACKAGE_NAME"
    echo "   Run ./create_production_deb.sh first"
    exit 1
fi

echo "📦 Found package: $PACKAGE_NAME"
echo "📊 Package size: $(du -h "$PACKAGE_NAME" | cut -f1)"
echo ""

# Install the package (this should do EVERYTHING automatically)
echo "🚀 Installing package (should be automatic)..."
sudo dpkg -i "$PACKAGE_NAME"

echo ""
echo "⏱️  Waiting 10 seconds for service to initialize..."
sleep 10

echo ""
echo "🔍 Checking service status..."
sudo systemctl status osqueryd --no-pager

echo ""
echo "🧪 Testing ancestry functionality..."

# Test 1: Basic connectivity
echo "📋 Test 1: Basic osquery connectivity"
sudo osqueryi "SELECT version FROM osquery_info;" || echo "❌ Basic connectivity failed"

# Test 2: Process events table exists
echo ""
echo "📋 Test 2: Process events table availability"
sudo osqueryi "SELECT COUNT(*) as events FROM process_events;" || echo "❌ Process events table failed"

# Test 3: Ancestry column exists
echo ""
echo "📋 Test 3: Ancestry column in schema"
sudo osqueryi "PRAGMA table_info(process_events);" | grep ancestry || echo "❌ Ancestry column not found"

# Test 4: Generate some process events and check ancestry
echo ""
echo "📋 Test 4: Generate events and check ancestry data"
# Generate some activity
ls /tmp > /dev/null
date > /dev/null
echo "Generated some process activity..."

sleep 5

# Check for ancestry data
echo "🔍 Checking for ancestry data..."
ANCESTRY_RESULTS=$(sudo osqueryi "SELECT COUNT(*) as ancestry_events FROM process_events WHERE ancestry != '[]';" 2>/dev/null || echo "0")
echo "📊 Events with ancestry data: $ANCESTRY_RESULTS"

# Show sample ancestry data
echo ""
echo "📋 Sample ancestry data:"
sudo osqueryi "SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 2;" 2>/dev/null || echo "No ancestry data yet (may need more time)"

echo ""
echo "🎉 PRODUCTION PACKAGE TEST COMPLETE!"
echo ""
echo "✅ Expected Results:"
echo "   - Service should be running automatically"
echo "   - Process events table should be accessible"
echo "   - Ancestry column should exist"
echo "   - Ancestry data should populate over time"
echo ""
echo "📋 Monitoring commands:"
echo "   sudo systemctl status osqueryd"
echo "   sudo journalctl -u osqueryd -f"
echo "   sudo tail -f /var/log/osquery/osqueryd.results.log"
echo ""
echo "🗑️  To remove: sudo apt remove osquery-ancestry-sensor"
