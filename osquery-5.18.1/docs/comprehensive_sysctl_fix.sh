#!/bin/bash

echo "🔧 COMPREHENSIVE SYSCTL FIX: Source + Build Files"
echo "================================================"
echo ""

echo "Fixing both source and generated sysctl files that cause:"
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

# Find ALL sysctl_utils.h files (source and build)
echo "🔍 Finding all sysctl_utils.h files..."
SYSCTL_FILES=$(find . -name "sysctl_utils.h" -type f)

if [ -z "$SYSCTL_FILES" ]; then
    echo "❌ No sysctl_utils.h files found!"
    exit 1
fi

echo "Found sysctl files:"
echo "$SYSCTL_FILES"
echo ""

# Fix each file
for SYSCTL_FILE in $SYSCTL_FILES; do
    echo "🔧 Fixing: $SYSCTL_FILE"
    
    # Backup
    cp "$SYSCTL_FILE" "$SYSCTL_FILE.backup"
    
    # Apply comprehensive fix
    cat > "$SYSCTL_FILE" << 'EOF'
#pragma once

#ifdef __linux__
// Linux systems no longer provide sys/sysctl.h
// Define all missing BSD sysctl constants for Linux compatibility
#include <unistd.h>
#include <fcntl.h>

// Core sysctl constants
#ifndef CTL_MAXNAME
#define CTL_MAXNAME 24
#endif

#ifndef CTL_DEBUG
#define CTL_DEBUG 5
#endif

// Additional constants that may be needed
#ifndef CTL_KERN
#define CTL_KERN 1
#endif

#ifndef CTL_VM
#define CTL_VM 2
#endif

#ifndef CTL_VFS
#define CTL_VFS 3
#endif

#ifndef CTL_NET
#define CTL_NET 4
#endif

#ifndef CTL_HW
#define CTL_HW 6
#endif

#ifndef CTL_MACHDEP
#define CTL_MACHDEP 7
#endif

#ifndef CTL_USER
#define CTL_USER 8
#endif

#else
// Non-Linux systems (BSD, macOS) - use system header
#include <sys/sysctl.h>
#endif

// Define the macro that was causing issues
#ifndef CTL_DEBUG_MAXID
#define CTL_DEBUG_MAXID (CTL_MAXNAME * 2)
#endif
EOF
    
    echo "✅ Fixed: $SYSCTL_FILE"
done

echo ""
echo "🎯 Summary:"
echo "- Fixed $(echo "$SYSCTL_FILES" | wc -l) sysctl header files"
echo "- Added comprehensive Linux compatibility layer"
echo "- Defined all missing BSD constants"
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
