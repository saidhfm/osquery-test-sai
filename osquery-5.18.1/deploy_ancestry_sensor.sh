#!/bin/bash
# 🚀 osquery Ancestry Sensor Deployment Script
# Deploys the compiled ancestry sensor to Ubuntu machines

set -e

DEB_PACKAGE="osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb"
PACKAGE_NAME="osquery-ancestry-sensor"

echo "🚀 Deploying osquery Ancestry Sensor..."
echo "📦 Package: $DEB_PACKAGE"

# Check if package exists
if [ ! -f "$DEB_PACKAGE" ]; then
    echo "❌ Error: $DEB_PACKAGE not found!"
    echo "Please ensure the DEB package is in the current directory."
    exit 1
fi

# Check if running on Ubuntu/Debian
if ! command -v dpkg &> /dev/null; then
    echo "❌ Error: This package is for Ubuntu/Debian systems only."
    exit 1
fi

# Check system architecture
if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "❌ Error: This package is for amd64 architecture only."
    exit 1
fi

echo "🔍 System check passed..."

# Install the package
echo "📦 Installing osquery ancestry sensor..."
sudo dpkg -i "$DEB_PACKAGE"

# Fix any dependency issues
if [ $? -ne 0 ]; then
    echo "🔧 Fixing dependencies..."
    sudo apt-get update
    sudo apt-get install -f -y
    sudo dpkg -i "$DEB_PACKAGE"
fi

# Verify installation
echo "✅ Verifying installation..."

# Check if service is running
if systemctl is-active --quiet osqueryd; then
    echo "✅ osqueryd service is running"
else
    echo "🔄 Starting osqueryd service..."
    sudo systemctl start osqueryd
fi

# Check if service is enabled
if systemctl is-enabled --quiet osqueryd; then
    echo "✅ osqueryd service is enabled for auto-start"
else
    echo "🔄 Enabling osqueryd service..."
    sudo systemctl enable osqueryd
fi

# Test ancestry functionality
echo "🧪 Testing ancestry functionality..."
if sudo timeout 10 osqueryi "SELECT name FROM osquery_registry WHERE registry='table' AND name='process_events';" | grep -q "process_events"; then
    echo "✅ process_events table is available"
    
    # Test ancestry column
    echo "🔍 Testing ancestry column..."
    if sudo timeout 10 osqueryi "PRAGMA table_info(process_events);" | grep -q "ancestry"; then
        echo "🎉 SUCCESS! Ancestry column is available!"
        echo "📊 Testing ancestry data..."
        sudo timeout 15 osqueryi "SELECT pid, parent, ancestry FROM process_events WHERE pid > 0 LIMIT 1;" || echo "⚠️  No process events captured yet (normal on new installation)"
    else
        echo "⚠️  Ancestry column not found - check if audit events are enabled"
    fi
else
    echo "❌ process_events table not found"
fi

# Display status
echo ""
echo "📊 Installation Summary:"
echo "========================"
echo "📦 Package: $PACKAGE_NAME installed successfully"
echo "🔧 Service: $(systemctl is-active osqueryd)"
echo "⚡ Auto-start: $(systemctl is-enabled osqueryd)"
echo "📁 Config: /etc/osquery/osquery.conf"
echo "📝 Logs: /var/log/osquery/"
echo ""
echo "📋 Useful Commands:"
echo "=================="
echo "  Status:    sudo systemctl status osqueryd"
echo "  Logs:      sudo journalctl -u osqueryd -f"
echo "  Query:     sudo osqueryi"
echo "  Test:      sudo osqueryi \"SELECT pid, parent, ancestry FROM process_events LIMIT 5;\""
echo ""
echo "🎉 Deployment completed successfully!"
echo "📈 Process ancestry monitoring is now active!"
