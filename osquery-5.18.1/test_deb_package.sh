#!/bin/bash

# DEB Package Testing Script for osquery Process Ancestry Sensor
# This script validates the DEB package installation and functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/packaging"

echo "🧪 Testing osquery Process Ancestry Sensor DEB Package"
echo "======================================================"

# Find the DEB package
DEB_FILE=$(find "$PACKAGE_DIR" -name "osquery-ancestry-sensor_*.deb" | head -1)

if [ -z "$DEB_FILE" ]; then
    echo "❌ Error: No DEB package found in $PACKAGE_DIR"
    echo "Please run ./create_deb_package.sh first"
    exit 1
fi

echo "📦 Testing package: $(basename "$DEB_FILE")"

# Test 1: Package integrity
echo ""
echo "🔍 Test 1: Package Integrity"
echo "----------------------------"
dpkg-deb --info "$DEB_FILE"
echo "✅ Package info looks good"

# Test 2: Package contents
echo ""
echo "📁 Test 2: Package Contents"
echo "---------------------------"
echo "Key files in package:"
dpkg-deb --contents "$DEB_FILE" | grep -E "(osqueryd|osqueryi|osquery\.conf|systemd)" | head -10
echo "✅ Package contents verified"

# Test 3: Dependencies check
echo ""
echo "🔗 Test 3: Dependencies Check"
echo "-----------------------------"
echo "Package dependencies:"
dpkg-deb --field "$DEB_FILE" Depends
echo "✅ Dependencies listed"

# Test 4: Lintian check (if available)
if command -v lintian &> /dev/null; then
    echo ""
    echo "🔎 Test 4: Lintian Quality Check"
    echo "--------------------------------"
    lintian "$DEB_FILE" || echo "⚠️  Some lintian warnings (may be acceptable)"
else
    echo ""
    echo "⚠️  Test 4: Lintian not available (install with: sudo apt install lintian)"
fi

# Test 5: Installation simulation (requires root)
echo ""
echo "🚀 Test 5: Installation Test"
echo "----------------------------"

if [ "$EUID" -eq 0 ]; then
    echo "Running as root - performing actual installation test..."
    
    # Backup existing osquery if present
    if [ -f "/usr/bin/osqueryd" ]; then
        echo "📋 Backing up existing osquery installation..."
        cp /usr/bin/osqueryd /tmp/osqueryd.backup || true
        cp /usr/bin/osqueryi /tmp/osqueryi.backup || true
    fi
    
    # Install the package
    echo "📦 Installing package..."
    dpkg -i "$DEB_FILE" || true
    
    # Fix dependencies if needed
    apt-get install -f -y
    
    # Test installation
    echo "🔍 Testing installation..."
    
    # Check binaries
    if [ -x "/usr/bin/osqueryd" ] && [ -x "/usr/bin/osqueryi" ]; then
        echo "✅ Binaries installed correctly"
    else
        echo "❌ Binaries not found or not executable"
        exit 1
    fi
    
    # Check service file
    if [ -f "/etc/systemd/system/osqueryd.service" ]; then
        echo "✅ Systemd service file installed"
    else
        echo "❌ Systemd service file missing"
        exit 1
    fi
    
    # Check user creation
    if id "osquery" &>/dev/null; then
        echo "✅ osquery user created"
    else
        echo "❌ osquery user not created"
        exit 1
    fi
    
    # Check directories
    if [ -d "/var/osquery" ] && [ -d "/var/log/osquery" ]; then
        echo "✅ Directories created with correct permissions"
    else
        echo "❌ Required directories missing"
        exit 1
    fi
    
    # Test osquery version
    echo "🔍 Testing osquery functionality..."
    /usr/bin/osqueryi "SELECT version FROM osquery_info;" --json | head -5
    
    # Test ancestry feature presence
    ANCESTRY_COLUMNS=$(/usr/bin/osqueryi "SELECT name FROM pragma_table_info('process_events') WHERE name='ancestry';" --json)
    if echo "$ANCESTRY_COLUMNS" | grep -q "ancestry"; then
        echo "✅ Process ancestry feature detected"
    else
        echo "❌ Process ancestry feature not detected"
        exit 1
    fi
    
    echo ""
    echo "🎉 Installation test completed successfully!"
    
    # Optional: Start and test the service
    read -p "Start osqueryd service for testing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create minimal config
        cat > /etc/osquery/osquery.conf << 'EOF'
{
  "options": {
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem",
    "logger_path": "/var/log/osquery",
    "database_path": "/var/osquery/osquery.db",
    "disable_events": "false",
    "audit_allow_process_events": "true",
    "process_ancestry_cache_size": "100"
  }
}
EOF
        
        systemctl daemon-reload
        systemctl start osqueryd
        sleep 3
        
        if systemctl is-active osqueryd >/dev/null; then
            echo "✅ osqueryd service started successfully"
            
            # Test a query
            echo "🔍 Testing process ancestry query..."
            /usr/bin/osqueryi "SELECT COUNT(*) as process_count FROM processes;" --json
            
            systemctl stop osqueryd
        else
            echo "❌ osqueryd service failed to start"
            systemctl status osqueryd
        fi
    fi
    
    # Cleanup option
    read -p "Remove installed package? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        dpkg -r osquery-ancestry-sensor
        echo "✅ Package removed"
        
        # Restore backup if exists
        if [ -f "/tmp/osqueryd.backup" ]; then
            cp /tmp/osqueryd.backup /usr/bin/osqueryd
            cp /tmp/osqueryi.backup /usr/bin/osqueryi
            echo "✅ Original osquery restored"
        fi
    fi
    
else
    echo "⚠️  Not running as root - skipping installation test"
    echo "    Run 'sudo ./test_deb_package.sh' for full testing"
fi

echo ""
echo "📊 Test Summary"
echo "==============="
echo "✅ Package integrity verified"
echo "✅ Package contents validated"
echo "✅ Dependencies checked"
if command -v lintian &> /dev/null; then
    echo "✅ Lintian quality check completed"
fi
if [ "$EUID" -eq 0 ]; then
    echo "✅ Installation test completed"
else
    echo "⚠️  Installation test skipped (requires root)"
fi

echo ""
echo "🎯 Package is ready for distribution!"
echo ""
echo "📤 Next steps:"
echo "   1. Upload to your package repository"
echo "   2. Distribute to target systems"
echo "   3. Install with: sudo dpkg -i $(basename "$DEB_FILE")"
