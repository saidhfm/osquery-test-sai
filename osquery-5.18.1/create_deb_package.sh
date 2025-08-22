#!/bin/bash

# osquery Process Ancestry Sensor DEB Package Builder
# This script creates a complete DEB package for Ubuntu distribution

set -e

# Configuration
PACKAGE_NAME="osquery-ancestry-sensor"
VERSION="5.18.1-ancestry-1.0"
ARCHITECTURE="amd64"
MAINTAINER="Your Organization <admin@company.com>"
DESCRIPTION="Enhanced osquery with process ancestry tracking for Linux"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PACKAGE_DIR="$SCRIPT_DIR/packaging"
DEB_DIR="$PACKAGE_DIR/${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}"

echo "🚀 Building osquery Process Ancestry Sensor DEB Package"
echo "======================================================="

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

# Create DEB package structure
echo "📁 Creating package structure..."
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/osquery"
mkdir -p "$DEB_DIR/etc/osquery"
mkdir -p "$DEB_DIR/etc/systemd/system"
mkdir -p "$DEB_DIR/var/log/osquery"
mkdir -p "$DEB_DIR/var/osquery"
mkdir -p "$DEB_DIR/usr/share/doc/osquery-ancestry-sensor"

# Check if binaries exist
if [ ! -f "$BUILD_DIR/osquery/osqueryd" ]; then
    echo "❌ Error: osqueryd binary not found in $BUILD_DIR/osquery/"
    echo "Please build osquery first using the build instructions"
    exit 1
fi

# Copy binaries
echo "📦 Copying binaries..."
cp "$BUILD_DIR/osquery/osqueryd" "$DEB_DIR/usr/bin/"
cp "$BUILD_DIR/osquery/osqueryi" "$DEB_DIR/usr/bin/"
chmod +x "$DEB_DIR/usr/bin/osqueryd"
chmod +x "$DEB_DIR/usr/bin/osqueryi"

# Create control file
echo "📋 Creating control file..."
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCHITECTURE
Depends: libc6 (>= 2.17), libssl1.1 | libssl3, libbz2-1.0, zlib1g
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 Enhanced osquery build with process ancestry tracking capability designed
 for security monitoring and forensic analysis. Provides complete parent-child
 process relationship tracking with rich JSON output and high-performance
 LRU caching.
 .
 Key Features:
  - Complete ancestry chains for process relationships
  - High-performance LRU cache with configurable size and TTL
  - Race condition handling for short-lived processes
  - Production-ready with minimal syscalls and memory usage
  - Integration with FleetDM and other osquery management platforms
Homepage: https://github.com/saidhfm/osquery-test-sai
EOF

# Create postinst script
echo "🔧 Creating post-installation script..."
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# Create osquery user if it doesn't exist
if ! id "osquery" &>/dev/null; then
    useradd --system --user-group --shell /bin/false --home-dir /var/osquery osquery
fi

# Create directories and set permissions
mkdir -p /var/log/osquery /var/osquery /etc/osquery
chown -R osquery:osquery /var/log/osquery /var/osquery
chmod 755 /var/log/osquery /var/osquery /etc/osquery

# Set binary permissions
chmod +x /usr/bin/osqueryd
chmod +x /usr/bin/osqueryi

# Reload systemd to recognize new service
systemctl daemon-reload

echo "✅ osquery Process Ancestry Sensor installed successfully!"
echo ""
echo "Next steps:"
echo "1. Configure /etc/osquery/osquery.conf with your settings"
echo "2. Enable the service: sudo systemctl enable osqueryd"
echo "3. Start the service: sudo systemctl start osqueryd"
echo ""
echo "For documentation and examples, visit:"
echo "https://github.com/saidhfm/osquery-test-sai"
EOF

chmod +x "$DEB_DIR/DEBIAN/postinst"

# Create prerm script
echo "🗑️ Creating pre-removal script..."
cat > "$DEB_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

# Stop and disable service if running
if systemctl is-active osqueryd >/dev/null 2>&1; then
    systemctl stop osqueryd
fi

if systemctl is-enabled osqueryd >/dev/null 2>&1; then
    systemctl disable osqueryd
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/prerm"

# Create postrm script
echo "🧹 Creating post-removal script..."
cat > "$DEB_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

if [ "$1" = "purge" ]; then
    # Remove configuration files and data on purge
    rm -rf /etc/osquery
    rm -rf /var/osquery
    rm -rf /var/log/osquery
    
    # Remove osquery user
    if id "osquery" &>/dev/null; then
        userdel osquery 2>/dev/null || true
    fi
    
    echo "✅ osquery Process Ancestry Sensor purged completely"
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/postrm"

# Create systemd service file
echo "🔄 Creating systemd service..."
cat > "$DEB_DIR/etc/systemd/system/osqueryd.service" << 'EOF'
[Unit]
Description=osquery Process Ancestry Sensor
Documentation=https://github.com/saidhfm/osquery-test-sai
After=network.target syslog.service
ConditionPathExists=/etc/osquery/osquery.conf

[Service]
Type=simple
User=osquery
Group=osquery
ExecStart=/usr/bin/osqueryd --flagfile=/etc/osquery/osquery.flags --config_path=/etc/osquery/osquery.conf
Restart=always
RestartSec=5
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/osquery /var/log/osquery /tmp
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

# Create example configuration
echo "⚙️ Creating example configuration..."
cat > "$DEB_DIR/etc/osquery/osquery.conf.example" << 'EOF'
{
  "options": {
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem",
    "logger_path": "/var/log/osquery",
    "database_path": "/var/osquery/osquery.db",
    "pidfile": "/var/osquery/osqueryd.pidfile",
    "host_identifier": "hostname",
    "utc": "true",
    "audit_allow_process_events": "true",
    "audit_allow_config": "true", 
    "disable_audit": "false",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "32",
    "process_ancestry_cache_ttl": "300",
    "verbose": "false"
  },
  "events": {
    "disable_publishers": [],
    "disable_subscribers": [],
    "enable_subscribers": ["process_events"],
    "enable_publishers": ["auditeventpublisher"]
  },
  "schedule": {
    "process_ancestry_monitor": {
      "query": "SELECT pid, parent, path, cmdline, ancestry FROM process_events WHERE ancestry != '[]';",
      "interval": 300,
      "description": "Monitor process events with ancestry information"
    }
  }
}
EOF

# Create example flags file
cat > "$DEB_DIR/etc/osquery/osquery.flags.example" << 'EOF'
--config_path=/etc/osquery/osquery.conf
--logger_path=/var/log/osquery
--database_path=/var/osquery/osquery.db
--pidfile=/var/osquery/osqueryd.pidfile
--disable_watchdog=false
--utc=true
EOF

# Create documentation
echo "📚 Creating documentation..."
cat > "$DEB_DIR/usr/share/doc/osquery-ancestry-sensor/README.md" << 'EOF'
# osquery Process Ancestry Sensor

This package provides an enhanced version of osquery with process ancestry tracking capabilities.

## Quick Start

1. Copy the example configuration:
   ```bash
   sudo cp /etc/osquery/osquery.conf.example /etc/osquery/osquery.conf
   sudo cp /etc/osquery/osquery.flags.example /etc/osquery/osquery.flags
   ```

2. Enable and start the service:
   ```bash
   sudo systemctl enable osqueryd
   sudo systemctl start osqueryd
   ```

3. Test the ancestry feature:
   ```bash
   sudo osqueryi "SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 3;"
   ```

## Configuration

Edit `/etc/osquery/osquery.conf` to customize:
- `process_ancestry_cache_size`: Number of entries to cache (default: 1000)
- `process_ancestry_max_depth`: Maximum ancestry depth (default: 32)
- `process_ancestry_cache_ttl`: Cache TTL in seconds (default: 300)

## Support

- Documentation: https://github.com/saidhfm/osquery-test-sai
- Issues: https://github.com/saidhfm/osquery-test-sai/issues
EOF

# Copy additional documentation
cp README.md "$DEB_DIR/usr/share/doc/osquery-ancestry-sensor/"

# Create copyright file
cat > "$DEB_DIR/usr/share/doc/osquery-ancestry-sensor/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: osquery-ancestry-sensor
Upstream-Contact: $MAINTAINER
Source: https://github.com/saidhfm/osquery-test-sai

Files: *
Copyright: 2025 Your Organization
License: Apache-2.0 or GPL-2.0

License: Apache-2.0
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 .
 http://www.apache.org/licenses/LICENSE-2.0
 .
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.

License: GPL-2.0
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 dated June, 1991.
EOF

# Calculate installed size
INSTALLED_SIZE=$(du -s "$DEB_DIR" | cut -f1)
echo "Installed-Size: $INSTALLED_SIZE" >> "$DEB_DIR/DEBIAN/control"

# Build the package
echo "🔨 Building DEB package..."
cd "$PACKAGE_DIR"
dpkg-deb --build "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}"

# Verify the package
echo "🔍 Verifying package..."
dpkg-deb --info "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"
dpkg-deb --contents "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

# Create checksums
echo "🔐 Creating checksums..."
md5sum "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb" > "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb.md5"
sha256sum "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb" > "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb.sha256"

echo "✅ DEB Package created successfully!"
echo ""
echo "📦 Package Details:"
echo "   File: $PACKAGE_DIR/${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"
echo "   Size: $(du -h "$PACKAGE_DIR/${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb" | cut -f1)"
echo ""
echo "🚀 Installation Instructions:"
echo "   sudo dpkg -i ${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"
echo "   sudo apt-get install -f  # Fix dependencies if needed"
echo ""
echo "🧪 Testing Instructions:"
echo "   sudo systemctl start osqueryd"
echo "   sudo osqueryi \"SELECT * FROM osquery_info;\""
echo "   sudo osqueryi \"SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';\""
echo ""
echo "📤 Distribution:"
echo "   Upload the .deb file to your package repository or"
echo "   distribute directly to target systems"
