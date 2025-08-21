#!/bin/bash

echo "🔧 FINAL SYSCTL DECLARATIONS: Header Only (No Inline Implementations)"
echo "===================================================================="
echo ""

echo "ISSUE IDENTIFIED: Function redefinition!"
echo "  ❌ My header provided inline implementations"
echo "  ❌ But system_controls.cpp already has the real implementations"
echo "  ✅ Solution: Only declare functions, don't implement them"
echo ""

# Handle sudo execution
if [ -n "$SUDO_USER" ]; then
    OSQUERY_PATH="/home/$SUDO_USER/osquery-build/osquery"
    cd "$OSQUERY_PATH"
else
    cd ~/osquery-build/osquery
fi

echo "Working directory: $(pwd)"
echo ""

# Find the source files
SYSCTL_HEADER=$(find . -name "sysctl_utils.h" -not -path "./build/*" | head -1)
SYSCTL_SOURCE=$(find . -name "sysctl_utils.cpp" -not -path "./build/*" | head -1)

echo "🔍 Found files:"
echo "Header: $SYSCTL_HEADER"
echo "Source: $SYSCTL_SOURCE"
echo ""

# Fix the source file (sysctl_utils.cpp) for sys/sysctl.h compatibility
if [ -n "$SYSCTL_SOURCE" ] && [ -f "$SYSCTL_SOURCE" ]; then
    echo "🔧 Fixing $SYSCTL_SOURCE for Linux compatibility..."
    
    # Backup
    cp "$SYSCTL_SOURCE" "$SYSCTL_SOURCE.backup"
    
    # Apply Linux compatibility fix
    sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\
// Linux compatibility - sys/sysctl.h not available\
#include <unistd.h>\
#include <fcntl.h>\
#else\
#include <sys/sysctl.h>\
#endif|' "$SYSCTL_SOURCE"
    
    echo "✅ Fixed sys/sysctl.h include in source file"
fi

# Create header with DECLARATIONS ONLY (no inline implementations)
if [ -n "$SYSCTL_HEADER" ] && [ -f "$SYSCTL_HEADER" ]; then
    echo ""
    echo "🔧 Creating $SYSCTL_HEADER with declarations only..."
    
    # Backup
    cp "$SYSCTL_HEADER" "$SYSCTL_HEADER.redefinition-backup"
    
    # Create header with ONLY declarations
    cat > "$SYSCTL_HEADER" << 'EOF'
#pragma once

#include <osquery/core/tables.h>
#include <osquery/logger/logger.h>

#ifdef __linux__
// Linux compatibility layer for BSD sysctl
#include <unistd.h>
#include <fcntl.h>
#include <map>

// Define missing BSD constants
#ifndef CTL_MAXNAME
#define CTL_MAXNAME 24
#endif

#ifndef CTL_DEBUG
#define CTL_DEBUG 5
#endif

#ifndef CTL_KERN
#define CTL_KERN 1
#endif

#ifndef CTL_VM
#define CTL_VM 2
#endif

#ifndef CTL_NET
#define CTL_NET 4
#endif

#ifndef CTL_HW
#define CTL_HW 6
#endif

#else
// Non-Linux systems use system sysctl
#include <sys/sysctl.h>
#endif

// Define the macro used in system_controls.cpp
#ifndef CTL_DEBUG_MAXID
#define CTL_DEBUG_MAXID (CTL_MAXNAME * 2)
#endif

namespace osquery {
namespace tables {

// DECLARATIONS ONLY - implementations are in system_controls.cpp
void genControlInfo(int* request, size_t request_size, QueryData& results, const std::map<std::string, std::string>& config);
void genControlInfoFromName(const std::string& name, QueryData& results, std::map<std::string, std::string>& config);
void genAllControls(QueryData& results, std::map<std::string, std::string>& config, const std::string& subsystem);
void genControlInfoFromOIDString(const std::string& oid_string, QueryData& results, std::map<std::string, std::string>& config);
void genControlConfigFromPath(const std::string& path, std::map<std::string, std::string>& config);

} // namespace tables
} // namespace osquery
EOF

    echo "✅ Created header with declarations only (no inline implementations)"
fi

# Fix generated files in build directory
echo ""
echo "🔧 Updating generated files..."
find build -name "sysctl_utils.*" -type f 2>/dev/null | while read BUILD_FILE; do
    if [[ "$BUILD_FILE" == *.h ]]; then
        echo "Copying header to: $BUILD_FILE"
        cp "$SYSCTL_HEADER" "$BUILD_FILE"
    elif [[ "$BUILD_FILE" == *.cpp ]] && [ -n "$SYSCTL_SOURCE" ]; then
        echo "Copying source to: $BUILD_FILE"
        cp "$SYSCTL_SOURCE" "$BUILD_FILE"
    fi
done

echo ""
echo "🎯 Final Declarations Fix Summary:"
echo "- ✅ Header contains ONLY function declarations"
echo "- ✅ NO inline implementations (avoids redefinition)"
echo "- ✅ Implementations remain in system_controls.cpp"
echo "- ✅ Fixed sys/sysctl.h compatibility in source files"
echo "- ✅ All BSD constants defined for Linux"
echo ""

echo "🔨 Testing build with declarations-only approach..."
cd build
make -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "✅ Function redefinition issue resolved!"
    echo "✅ osquery with process ancestry support built successfully!"
    echo ""
    echo "🚀 Your ancestry implementation is ready for testing!"
else
    echo ""
    echo "❌ Build failed. Checking for remaining issues..."
    echo ""
    echo "Debug: Let's see what functions are actually implemented in system_controls.cpp:"
    grep -n "^void gen" ../osquery/tables/system/posix/system_controls.cpp || echo "No functions found with that pattern"
fi
