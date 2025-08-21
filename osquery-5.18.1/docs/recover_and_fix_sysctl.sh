#!/bin/bash

echo "🔧 RECOVER AND MINIMAL SYSCTL FIX"
echo "================================="
echo ""

echo "Recovering from aggressive fixes and applying minimal changes"
echo "Issues being addressed:"
echo "  - Missing function declarations (genControlInfo, etc.)"
echo "  - sys/sysctl.h header compatibility"
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

# Find all sysctl_utils.h files
echo "🔍 Finding all sysctl_utils.h files..."
SYSCTL_FILES=$(find . -name "sysctl_utils.h" -type f)

if [ -z "$SYSCTL_FILES" ]; then
    echo "❌ No sysctl_utils.h files found!"
    exit 1
fi

echo "Found sysctl files:"
echo "$SYSCTL_FILES"
echo ""

# Step 1: Try to restore from backups
echo "📦 Step 1: Attempting to restore from backups..."
for SYSCTL_FILE in $SYSCTL_FILES; do
    BACKUP_FILE="${SYSCTL_FILE}.backup"
    if [ -f "$BACKUP_FILE" ]; then
        echo "  ↳ Restoring $SYSCTL_FILE from backup"
        cp "$BACKUP_FILE" "$SYSCTL_FILE"
        echo "  ↳ ✅ Restored from backup"
    else
        echo "  ↳ No backup found for $SYSCTL_FILE"
    fi
done

# Step 2: Check if function declarations exist
echo ""
echo "🔍 Step 2: Checking for required function declarations..."
MISSING_FUNCTIONS=0
for SYSCTL_FILE in $SYSCTL_FILES; do
    echo "Checking: $SYSCTL_FILE"
    
    if ! grep -q "genControlInfo" "$SYSCTL_FILE"; then
        echo "  ↳ Missing: genControlInfo declaration"
        MISSING_FUNCTIONS=1
    fi
    
    if ! grep -q "genControlInfoFromName" "$SYSCTL_FILE"; then
        echo "  ↳ Missing: genControlInfoFromName declaration"
        MISSING_FUNCTIONS=1
    fi
    
    if ! grep -q "genAllControls" "$SYSCTL_FILE"; then
        echo "  ↳ Missing: genAllControls declaration"
        MISSING_FUNCTIONS=1
    fi
done

# Step 3: Add missing function declarations if needed
if [ $MISSING_FUNCTIONS -eq 1 ]; then
    echo ""
    echo "🔧 Step 3: Adding missing function declarations..."
    
    for SYSCTL_FILE in $SYSCTL_FILES; do
        echo "Adding declarations to: $SYSCTL_FILE"
        
        # Add the missing function declarations
        cat >> "$SYSCTL_FILE" << 'EOF'

// Function declarations for system_controls.cpp
#include <osquery/tables/events/linux/process_ancestry_cache.h>

namespace osquery {
namespace tables {

void genControlInfo(int* request, size_t request_size, QueryData& results, QueryContext& context);
void genControlInfoFromName(const std::string& name, QueryData& results, QueryContext& context);
void genAllControls(QueryData& results, QueryContext& context, const std::string& subsystem);

} // namespace tables
} // namespace osquery
EOF
        echo "  ↳ ✅ Added function declarations"
    done
fi

# Step 4: Apply minimal header fix (only if sys/sysctl.h exists)
echo ""
echo "🔧 Step 4: Applying minimal header compatibility fix..."
for SYSCTL_FILE in $SYSCTL_FILES; do
    if grep -q "#include <sys/sysctl.h>" "$SYSCTL_FILE"; then
        echo "Fixing sys/sysctl.h include in: $SYSCTL_FILE"
        
        # Create new backup before this fix
        cp "$SYSCTL_FILE" "${SYSCTL_FILE}.pre-header-fix"
        
        # Replace only the problematic include
        sed -i 's|#include <sys/sysctl.h>|#ifdef __linux__\
// Linux compatibility layer\
#include <unistd.h>\
#ifndef CTL_MAXNAME\
#define CTL_MAXNAME 24\
#endif\
#ifndef CTL_DEBUG\
#define CTL_DEBUG 5\
#endif\
#else\
#include <sys/sysctl.h>\
#endif|' "$SYSCTL_FILE"
        
        echo "  ↳ ✅ Header include fixed"
    else
        echo "No sys/sysctl.h include found in: $SYSCTL_FILE"
    fi
done

echo ""
echo "🎯 Recovery Summary:"
echo "- Attempted backup restoration"
echo "- Added missing function declarations" 
echo "- Applied minimal header compatibility fixes"
echo ""

echo "🔨 Attempting build..."
cd build
make -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build completed successfully!"
else
    echo ""
    echo "❌ Build failed. Checking file contents for debugging..."
    echo ""
    echo "📋 Current sysctl_utils.h content preview:"
    for SYSCTL_FILE in $SYSCTL_FILES; do
        echo "=== $SYSCTL_FILE ==="
        head -20 "$SYSCTL_FILE"
        echo "..."
        tail -10 "$SYSCTL_FILE"
        echo ""
    done
fi
