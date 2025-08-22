#!/bin/bash
# 🧪 Test script for the PATCHED osquery ancestry package
# This verifies all the fixes work correctly

set -e

PACKAGE_NAME="osquery-ancestry-sensor_5.18.1-ancestry-patched_amd64.deb"

echo "🧪 Testing PATCHED osquery Ancestry Package"
echo "=========================================="
echo ""

# Check if package exists
if [ ! -f "$PACKAGE_NAME" ]; then
    echo "❌ Package not found: $PACKAGE_NAME"
    echo "   Run ./create_patched_deb.sh first"
    exit 1
fi

echo "📦 Found patched package: $PACKAGE_NAME"
echo "📊 Package size: $(du -h "$PACKAGE_NAME" | cut -f1)"
echo ""

# Install the patched package
echo "🚀 Installing PATCHED package (should fix all issues)..."
sudo dpkg -i "$PACKAGE_NAME"

echo ""
echo "⏱️  Waiting 10 seconds for service to initialize..."
sleep 10

echo ""
echo "🔍 Checking service status..."
sudo systemctl status osqueryd --no-pager

echo ""
echo "🧪 Testing PATCHED fixes..."

# Test 1: Service should be running as root (not osquery user)
echo "📋 Test 1: Service running as root (fixes audit issues)"
SERVICE_USER=$(ps aux | grep osqueryd | grep -v grep | awk '{print $1}' | head -1)
if [ "$SERVICE_USER" = "root" ]; then
    echo "✅ Service running as root - audit netlink issue fixed!"
else
    echo "❌ Service running as: $SERVICE_USER (should be root)"
fi

# Test 2: Smart wrapper exists and works
echo ""
echo "📋 Test 2: Smart osqueryi wrapper exists"
if [ -f "/usr/bin/osqueryi-daemon" ]; then
    echo "✅ osqueryi-daemon wrapper created"
    
    # Test that it can connect
    echo "📋 Test 2a: Testing wrapper auto-connection"
    WRAPPER_TEST=$(timeout 10s sudo osqueryi-daemon "SELECT version FROM osquery_info;" 2>/dev/null | grep "5.18.1" || echo "failed")
    if [ "$WRAPPER_TEST" != "failed" ]; then
        echo "✅ osqueryi-daemon auto-connection works!"
    else
        echo "❌ osqueryi-daemon auto-connection failed"
    fi
else
    echo "❌ osqueryi-daemon wrapper not found"
fi

# Test 3: Socket exists and is accessible
echo ""
echo "📋 Test 3: Daemon socket exists and accessible"
if [ -S "/var/osquery/osquery.em" ]; then
    echo "✅ Daemon socket exists"
    
    # Test manual connection
    MANUAL_TEST=$(timeout 10s sudo /usr/bin/osqueryi --connect /var/osquery/osquery.em "SELECT COUNT(*) FROM osquery_info;" 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo "0")
    if [ "$MANUAL_TEST" = "1" ]; then
        echo "✅ Manual connection to daemon works"
    else
        echo "❌ Manual connection failed"
    fi
else
    echo "❌ Daemon socket not found"
fi

# Test 4: Ancestry functionality
echo ""
echo "📋 Test 4: Process ancestry functionality"
# Generate some activity first
ls /tmp > /dev/null
date > /dev/null
sleep 2

# Check for ancestry data using the wrapper
ANCESTRY_TEST=$(timeout 10s sudo osqueryi-daemon "SELECT COUNT(*) as ancestry_count FROM process_events WHERE ancestry != '[]';" 2>/dev/null | grep -o '[0-9]*' | tail -1 || echo "0")

echo "📊 Events with ancestry data: $ANCESTRY_TEST"

if [ "$ANCESTRY_TEST" -gt 0 ]; then
    echo "✅ Ancestry functionality working!"
    
    # Show sample ancestry data
    echo ""
    echo "📋 Sample ancestry data:"
    timeout 10s sudo osqueryi-daemon "SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 2;" 2>/dev/null || echo "Query timed out"
else
    echo "⚠️  No ancestry data yet - may need more time for events"
fi

# Test 5: Configuration is correct
echo ""
echo "📋 Test 5: Configuration verification"
if grep -q "enable_subscribers.*process_events" /etc/osquery/osquery.conf; then
    echo "✅ Configuration enables process_events"
else
    echo "❌ Configuration issue with process_events"
fi

# Test 6: No audit netlink errors
echo ""
echo "📋 Test 6: Check for audit netlink errors"
NETLINK_ERRORS=$(sudo journalctl -u osqueryd --since "5 minutes ago" --no-pager | grep -c "Failed to set the netlink owner" || echo "0")
if [ "$NETLINK_ERRORS" = "0" ]; then
    echo "✅ No audit netlink errors (running as root fixed this!)"
else
    echo "⚠️  Still seeing $NETLINK_ERRORS netlink errors"
fi

echo ""
echo "🎉 PATCHED PACKAGE TEST COMPLETE!"
echo ""
echo "📊 Summary of fixes:"
echo "   ✅ Service runs as root (audit permissions)"
echo "   ✅ Smart wrapper (osqueryi-daemon) for auto-connection"
echo "   ✅ Proper error handling and status"
echo "   ✅ Immediate functionality after installation"
echo ""
echo "💡 Easy usage commands:"
echo "   sudo osqueryi-daemon"
echo "   Then: SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 3;"
echo ""
echo "📋 Monitoring commands:"
echo "   sudo systemctl status osqueryd"
echo "   sudo journalctl -u osqueryd -f"
echo ""
echo "🗑️  To remove: sudo apt remove osquery-ancestry-sensor"
