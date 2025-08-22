#!/bin/bash
# 🚀 Production DEB Package Creator for osquery Ancestry Sensor
# This creates a COMPLETE package that works out of the box

set -e

PACKAGE_NAME="osquery-ancestry-sensor"
VERSION="5.18.1-ancestry-production"
ARCH="amd64"
DEB_TEMP_DIR="/tmp/${PACKAGE_NAME}_${VERSION}_${ARCH}"
BUILD_ROOT="${DEB_TEMP_DIR}"
OUTPUT_DIR="./production_packages"

echo "🏗️  Creating PRODUCTION DEB package with complete automation..."

# Clean and create directories
rm -rf "${DEB_TEMP_DIR}"
mkdir -p "${BUILD_ROOT}"
mkdir -p "${OUTPUT_DIR}"

# Verify source binaries exist
OSQUERY_BUILD_DIR="$1"
if [ -z "$OSQUERY_BUILD_DIR" ]; then
    echo "❌ Usage: $0 <path_to_osquery_build_directory>"
    echo "   Example: $0 /home/ubuntu/osquery-build/osquery/build"
    exit 1
fi

if [ ! -f "${OSQUERY_BUILD_DIR}/osquery/osqueryd" ]; then
    echo "❌ Error: osqueryd not found in ${OSQUERY_BUILD_DIR}/osquery/"
    exit 1
fi

echo "✅ Found osquery binaries in ${OSQUERY_BUILD_DIR}"

# Create DEBIAN control directory
mkdir -p "${BUILD_ROOT}/DEBIAN"

# Create control file
cat > "${BUILD_ROOT}/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libc6 (>= 2.17), libaudit1, libssl1.1 | libssl3, libsqlite3-0
Maintainer: Process Ancestry Team <admin@company.com>
Description: osquery with automated process ancestry support
 Complete osquery build with process ancestry tracking functionality.
 .
 This package includes:
 - Compiled ancestry functionality in osqueryd/osqueryi
 - Pre-configured systemd service with audit support
 - Automatic directory and user setup
 - Working configuration file
 - No manual configuration required
EOF

# Create post-installation script with COMPLETE automation
cat > "${BUILD_ROOT}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

echo "🚀 Setting up osquery Process Ancestry Sensor..."

# Create osquery user and group if they don't exist
if ! id osquery >/dev/null 2>&1; then
    useradd --system --user-group --shell /bin/false --home-dir /var/osquery osquery
    echo "✅ Created osquery user"
fi

# Create all necessary directories
mkdir -p /etc/osquery /var/log/osquery /var/osquery
chown -R osquery:osquery /var/log/osquery /var/osquery
chown root:osquery /etc/osquery
chmod 755 /var/log/osquery /var/osquery /etc/osquery
echo "✅ Created directories with proper permissions"

# Install working osquery configuration
cat > /etc/osquery/osquery.conf << 'OSQUERY_EOF'
{
  "options": {
    "utc": "true",
    "verbose": "true",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "32",
    "process_ancestry_cache_ttl": "300"
  },
  "events": {
    "disable_publishers": [],
    "disable_subscribers": [],
    "enable_subscribers": ["process_events"],
    "enable_publishers": ["auditeventpublisher"]
  },
  "schedule": {
    "process_snapshot": {
      "query": "SELECT pid, parent, path, cmdline FROM processes;",
      "interval": 300
    }
  }
}
OSQUERY_EOF

chown root:osquery /etc/osquery/osquery.conf
chmod 640 /etc/osquery/osquery.conf
echo "✅ Installed working osquery configuration"

# Install systemd service with ALL required audit flags
cat > /etc/systemd/system/osqueryd.service << 'SERVICE_EOF'
[Unit]
Description=osquery Process Ancestry Sensor (Production)
Documentation=https://github.com/saidhfm/osquery-test-sai
After=network.target
Wants=network.target

[Service]
Type=simple
User=osquery
Group=osquery
ExecStart=/usr/bin/osqueryd --config_path=/etc/osquery/osquery.conf --disable_watchdog --verbose --audit_allow_process_events=true --audit_allow_config=true --disable_audit=false --logger_plugin=filesystem --database_path=/var/osquery/osquery.db --pidfile=/var/osquery/osquery.pid --extensions_socket=/var/osquery/osquery.em
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=osqueryd

# Working directory and environment
WorkingDirectory=/var/osquery
Environment=OSQUERY_CONFIG_PATH=/etc/osquery/osquery.conf

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
SERVICE_EOF

chmod 644 /etc/systemd/system/osqueryd.service
echo "✅ Installed systemd service with audit support"

# Stop any existing auditd that might conflict
if systemctl is-active --quiet auditd; then
    systemctl stop auditd || true
    systemctl disable auditd || true
    echo "✅ Disabled conflicting auditd service"
fi

# Clean up any existing osquery processes
pkill -f osqueryd || true
sleep 2

# Remove old pidfiles
rm -f /var/osquery/osquery.pid /var/osquery/osquery.em

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable osqueryd
echo "✅ Enabled osqueryd service"

# Start the service
if systemctl start osqueryd; then
    echo "✅ Started osqueryd service successfully"
    sleep 3
    
    # Verify service is running
    if systemctl is-active --quiet osqueryd; then
        echo "🎉 osquery Process Ancestry Sensor is running!"
        echo ""
        echo "📋 Quick test commands:"
        echo "   sudo systemctl status osqueryd"
        echo "   sudo osqueryi \"SELECT COUNT(*) FROM process_events;\""
        echo "   sudo osqueryi \"SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 3;\""
        echo ""
        echo "📁 Log files:"
        echo "   Service logs: journalctl -u osqueryd -f"
        echo "   Query results: tail -f /var/log/osquery/osqueryd.results.log"
        echo ""
    else
        echo "⚠️  Service started but may need a moment to initialize"
        echo "   Check status: sudo systemctl status osqueryd"
    fi
else
    echo "⚠️  Service failed to start - check logs: journalctl -u osqueryd"
fi

echo "✅ osquery Process Ancestry Sensor installation complete!"
EOF
chmod 755 "${BUILD_ROOT}/DEBIAN/postinst"

# Create pre-removal script
cat > "${BUILD_ROOT}/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

if [ "$1" = "remove" ] || [ "$1" = "deconfigure" ]; then
    echo "🛑 Stopping osquery Process Ancestry Sensor..."
    systemctl stop osqueryd || true
    systemctl disable osqueryd || true
    pkill -f osqueryd || true
    echo "✅ Stopped osqueryd service"
fi
EOF
chmod 755 "${BUILD_ROOT}/DEBIAN/prerm"

# Create post-removal script
cat > "${BUILD_ROOT}/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

if [ "$1" = "purge" ]; then
    echo "🧹 Purging osquery Process Ancestry Sensor..."
    rm -rf /etc/osquery /var/log/osquery /var/osquery
    rm -f /etc/systemd/system/osqueryd.service
    systemctl daemon-reload
    userdel osquery 2>/dev/null || true
    groupdel osquery 2>/dev/null || true
    echo "✅ Purged osquery Process Ancestry Sensor"
fi
EOF
chmod 755 "${BUILD_ROOT}/DEBIAN/postrm"

# Copy binaries to the package
mkdir -p "${BUILD_ROOT}/usr/bin"
cp "${OSQUERY_BUILD_DIR}/osquery/osqueryd" "${BUILD_ROOT}/usr/bin/"
cp "${OSQUERY_BUILD_DIR}/osquery/osqueryi" "${BUILD_ROOT}/usr/bin/"
chmod 755 "${BUILD_ROOT}/usr/bin/osqueryd"
chmod 755 "${BUILD_ROOT}/usr/bin/osqueryi"

echo "✅ Copied osquery binaries with ancestry support"

# Create documentation directory
mkdir -p "${BUILD_ROOT}/usr/share/doc/${PACKAGE_NAME}"
cat > "${BUILD_ROOT}/usr/share/doc/${PACKAGE_NAME}/README" << 'DOC_EOF'
osquery Process Ancestry Sensor - Production Package

This package provides osquery with compiled process ancestry functionality.

FEATURES:
- Process ancestry tracking with JSON output
- LRU cache for performance optimization  
- Automated systemd service configuration
- Security hardening enabled
- No manual configuration required

USAGE:
After installation, the service starts automatically. Test with:
  sudo osqueryi "SELECT pid, parent, ancestry FROM process_events LIMIT 3;"

CONFIGURATION:
Main config: /etc/osquery/osquery.conf
Service config: /etc/systemd/system/osqueryd.service
Logs: /var/log/osquery/

For support: https://github.com/saidhfm/osquery-test-sai
DOC_EOF

# Create changelog
cat > "${BUILD_ROOT}/usr/share/doc/${PACKAGE_NAME}/changelog" << 'CHANGELOG_EOF'
osquery-ancestry-sensor (5.18.1-ancestry-production) stable; urgency=medium

  * Complete automation of installation and configuration
  * Pre-configured systemd service with audit support
  * Automatic user and directory setup
  * Working configuration file included
  * No manual steps required after installation
  * Process ancestry functionality compiled and ready

 -- Process Ancestry Team <admin@company.com>  $(date -R)
CHANGELOG_EOF

gzip "${BUILD_ROOT}/usr/share/doc/${PACKAGE_NAME}/changelog"

# Set final permissions
find "${BUILD_ROOT}" -type f -exec chmod 644 {} \;
find "${BUILD_ROOT}" -type d -exec chmod 755 {} \;
chmod 755 "${BUILD_ROOT}/usr/bin/osqueryd"
chmod 755 "${BUILD_ROOT}/usr/bin/osqueryi"
chmod 755 "${BUILD_ROOT}/DEBIAN/postinst"
chmod 755 "${BUILD_ROOT}/DEBIAN/prerm"
chmod 755 "${BUILD_ROOT}/DEBIAN/postrm"

# Build the DEB package
echo "🔨 Building production DEB package..."
DEB_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build "${BUILD_ROOT}" "${DEB_FILE}"

# Generate checksums
cd "${OUTPUT_DIR}"
sha256sum "${PACKAGE_NAME}_${VERSION}_${ARCH}.deb" > "${PACKAGE_NAME}_${VERSION}_${ARCH}.deb.sha256"
md5sum "${PACKAGE_NAME}_${VERSION}_${ARCH}.deb" > "${PACKAGE_NAME}_${VERSION}_${ARCH}.deb.md5"

echo ""
echo "🎉 SUCCESS! Production DEB package created:"
echo "   📦 File: ${DEB_FILE}"
echo "   📊 Size: $(du -h "${DEB_FILE}" | cut -f1)"
echo "   🔒 SHA256: $(cat "${PACKAGE_NAME}_${VERSION}_${ARCH}.deb.sha256")"
echo ""
echo "🚀 This package includes EVERYTHING needed:"
echo "   ✅ Compiled ancestry functionality"
echo "   ✅ Complete automated setup"
echo "   ✅ Working configuration"
echo "   ✅ Systemd service with audit support"
echo "   ✅ No manual configuration required"
echo ""
echo "📋 Installation command:"
echo "   sudo dpkg -i ${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "🧪 Test command after installation:"
echo "   sudo osqueryi \"SELECT pid, parent, ancestry FROM process_events LIMIT 3;\""

# Clean up
rm -rf "${DEB_TEMP_DIR}"
cd - > /dev/null

echo "✅ Production packaging complete!"
