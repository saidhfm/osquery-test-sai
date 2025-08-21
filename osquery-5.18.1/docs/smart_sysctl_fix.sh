#!/bin/bash

echo "🔧 SMART SYSCTL FIX: Preserve Functions, Fix Headers"
echo "=================================================="
echo ""

echo "Fixing sysctl headers while preserving function declarations"
echo "Errors being fixed:"
echo "  fatal error: 'sys/sysctl.h' file not found"
echo "  use of undeclared identifier 'CTL_MAXNAME'"
echo "  use of undeclared identifier 'genControlInfo'"
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
    echo "🔧 Smart fixing: $SYSCTL_FILE"
    
    # Backup
    cp "$SYSCTL_FILE" "$SYSCTL_FILE.backup"
    
    # Read the original file and apply smart fixes
    if grep -q "#include <sys/sysctl.h>" "$SYSCTL_FILE"; then
        echo "  ↳ Replacing sys/sysctl.h include..."
        
        # Replace just the problematic include
        sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\
// Linux compatibility layer for BSD sysctl\
#include <unistd.h>\
#include <fcntl.h>\
#ifndef CTL_MAXNAME\
#define CTL_MAXNAME 24\
#endif\
#ifndef CTL_DEBUG\
#define CTL_DEBUG 5\
#endif\
#ifndef CTL_KERN\
#define CTL_KERN 1\
#endif\
#ifndef CTL_VM\
#define CTL_VM 2\
#endif\
#ifndef CTL_NET\
#define CTL_NET 4\
#endif\
#ifndef CTL_HW\
#define CTL_HW 6\
#endif\
#else\
#include <sys/sysctl.h>\
#endif|' "$SYSCTL_FILE"
        
        echo "  ↳ ✅ Header include fixed"
    else
        echo "  ↳ No sys/sysctl.h include found, checking for missing constants..."
    fi
    
    # Ensure CTL_DEBUG_MAXID is defined if not already
    if ! grep -q "CTL_DEBUG_MAXID" "$SYSCTL_FILE"; then
        echo "  ↳ Adding CTL_DEBUG_MAXID definition..."
        echo "" >> "$SYSCTL_FILE"
        echo "// Define missing macro for Linux compatibility" >> "$SYSCTL_FILE"
        echo "#ifndef CTL_DEBUG_MAXID" >> "$SYSCTL_FILE"
        echo "#define CTL_DEBUG_MAXID (CTL_MAXNAME * 2)" >> "$SYSCTL_FILE"
        echo "#endif" >> "$SYSCTL_FILE"
        echo "  ↳ ✅ CTL_DEBUG_MAXID added"
    fi
    
    echo "✅ Smart fix completed for: $SYSCTL_FILE"
done

echo ""
echo "🎯 Summary:"
echo "- Processed $(echo "$SYSCTL_FILES" | wc -l) sysctl header files"
echo "- Preserved existing function declarations"
echo "- Added Linux compatibility layer"
echo "- Defined missing BSD constants"
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
