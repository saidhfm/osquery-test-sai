#!/bin/bash

echo "🔧 FIX DOUBLE NAMESPACE ERROR"
echo "============================="

cd ~/osquery-build/osquery
echo "Working directory: $(pwd)"

# The error shows: tables::tables::ProcessAncestryManager
# Should be: tables::ProcessAncestryManager (single namespace)

echo ""
echo "🔍 Finding process_events.cpp with double namespace..."

EVENTS_CPP=$(find . -name "process_events.cpp" -path "*/linux/*" | head -1)

if [ -f "$EVENTS_CPP" ]; then
    echo "Found: $EVENTS_CPP"
    
    # Check for the double namespace
    if grep -q "tables::tables::" "$EVENTS_CPP"; then
        echo "📝 Fixing double namespace in $EVENTS_CPP..."
        
        # Make backup
        cp "$EVENTS_CPP" "$EVENTS_CPP.double-namespace-backup"
        
        # Fix double namespace - remove the extra tables::
        sed -i 's/tables::tables::/tables::/g' "$EVENTS_CPP"
        
        echo "✅ Fixed double namespace"
        
        # Show the fix
        echo ""
        echo "🔍 Verification - line with fix:"
        grep -n "tables::ProcessAncestryManager" "$EVENTS_CPP" || echo "Let's check for any remaining issues:"
        grep -n "ProcessAncestryManager" "$EVENTS_CPP"
    else
        echo "🔍 No double namespace found, let's check what's there:"
        grep -n "ProcessAncestryManager" "$EVENTS_CPP"
        
        # Check if we need to add the namespace
        if grep -q "ProcessAncestryManager::getInstance" "$EVENTS_CPP" && ! grep -q "tables::ProcessAncestryManager" "$EVENTS_CPP"; then
            echo "📝 Adding missing namespace..."
            sed -i 's/ProcessAncestryManager::getInstance/tables::ProcessAncestryManager::getInstance/g' "$EVENTS_CPP"
            echo "✅ Added namespace"
        fi
    fi
else
    echo "❌ process_events.cpp not found"
    echo ""
    echo "🔍 Let's find all files with ProcessAncestryManager:"
    find . -name "*.cpp" -exec grep -l "ProcessAncestryManager" {} \; 2>/dev/null
fi

echo ""
echo "📝 Also checking for the same issue in any build directory files..."

# Check build directory files too
BUILD_EVENTS=$(find build -name "process_events.cpp" -type f 2>/dev/null)

for BUILD_FILE in $BUILD_EVENTS; do
    if [ -f "$BUILD_FILE" ]; then
        echo "Checking build file: $BUILD_FILE"
        
        if grep -q "tables::tables::" "$BUILD_FILE"; then
            echo "📝 Fixing double namespace in build file..."
            sed -i 's/tables::tables::/tables::/g' "$BUILD_FILE"
            echo "✅ Fixed build file"
        fi
    fi
done

echo ""
echo "🔨 Testing the fix..."
cd build

# Clean the object file to force recompilation
rm -f osquery/tables/events/CMakeFiles/osquery_tables_events_eventstable.dir/linux/process_events.cpp.o

# Try building just the events table
echo "📦 Building events table..."
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 NAMESPACE FIX SUCCESSFUL!"
    echo "🔨 Building full osquery..."
    make -j1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉🎉🎉 COMPLETE BUILD SUCCESS! 🎉🎉🎉"
        echo "✅ osquery with process ancestry support built successfully!"
        echo ""
        echo "🚀 Ready for installation and testing!"
        echo ""
        echo "📍 Your enhanced osquery binaries are ready:"
        echo "   - osqueryi: $(pwd)/osquery/osqueryi"
        echo "   - osqueryd: $(pwd)/osquery/osqueryd"
        echo ""
        echo "🧪 Quick test:"
        echo "   sudo $(pwd)/osquery/osqueryi"
        echo "   SELECT name FROM sqlite_master WHERE type='table' AND name='process_events';"
    else
        echo ""
        echo "❌ Full build had issues, but events table compiled!"
        echo "The ancestry feature should work when the rest builds successfully."
    fi
else
    echo ""
    echo "❌ Still having compilation issues..."
    echo ""
    echo "🔍 Latest compilation error:"
    make osquery_tables_events_eventstable 2>&1 | grep -A5 -B5 "error:"
    echo ""
    echo "🔍 Let's check the actual file content around line 218:"
    if [ -f "$EVENTS_CPP" ]; then
        echo "Lines around 218 in $EVENTS_CPP:"
        sed -n '215,225p' "$EVENTS_CPP" 2>/dev/null || echo "Could not read lines"
    fi
fi
