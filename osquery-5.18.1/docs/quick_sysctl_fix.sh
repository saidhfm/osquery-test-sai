#!/bin/bash

echo "🔧 QUICK FIX: Missing sys/sysctl.h Header & Constants"
echo "=================================================="
echo ""

echo "Fixing missing header and constants issue that causes:"
echo "  fatal error: 'sys/sysctl.h' file not found"
echo "  use of undeclared identifier 'CTL_MAXNAME'"
echo ""

# Handle sudo execution
if [ -n "$SUDO_USER" ]; then
    OSQUERY_PATH="/home/$SUDO_USER/osquery-build/osquery"
    echo "Detected sudo execution, using: $OSQUERY_PATH"
    cd "$OSQUERY_PATH"
else
    cd ~/osquery-build/osquery
fi

echo "Working directory: $(pwd)"
echo ""

# Find the problematic header file
SYSCTL_HEADER="build/ns_osquery_tables_system_systemtable/osquery/tables/system/posix/sysctl_utils.h"
echo "🔍 Fixing file: $SYSCTL_HEADER"

if [ ! -f "$SYSCTL_HEADER" ]; then
    echo "❌ File not found: $SYSCTL_HEADER"
    echo "Trying alternative location..."
    SYSCTL_HEADER=$(find . -name "sysctl_utils.h" -path "*/posix/*" | head -1)
    echo "Found: $SYSCTL_HEADER"
fi

if [ ! -f "$SYSCTL_HEADER" ]; then
    echo "❌ sysctl_utils.h not found anywhere"
    exit 1
fi

echo ""
echo "🔧 Adding conditional header inclusion..."

# Backup and fix the file
cp "$SYSCTL_HEADER" "$SYSCTL_HEADER.backup"

# Replace the problematic include with conditional inclusion and missing constants
sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\n// Linux systems no longer provide sys/sysctl.h\n// Define missing constants for Linux compatibility\n#include <unistd.h>\n#include <fcntl.h>\n#ifndef CTL_MAXNAME\n#define CTL_MAXNAME 24\n#endif\n#ifndef CTL_DEBUG\n#define CTL_DEBUG 5\n#endif\n#else\n#include <sys/sysctl.h>\n#endif|' "$SYSCTL_HEADER"

echo "✅ Header and constants fixed with conditional inclusion!"
echo ""
echo "🔨 Continuing build..."
cd build
make -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build completed successfully!"
else
    echo ""
    echo "❌ Build failed. Check output above for errors."
fi
