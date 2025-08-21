#!/bin/bash

echo "🔧 QUICK NAMESPACE FIX"
echo "====================="

cd ~/osquery-build/osquery
echo "Working directory: $(pwd)"

# The error shows the files exist but wrong namespace usage
# Error: ProcessAncestryManager should be tables::ProcessAncestryManager

echo ""
echo "🔍 Looking for process_events.cpp with the namespace issue..."

# Find the file with the error
EVENTS_CPP=$(find . -name "process_events.cpp" -path "*/linux/*" | head -1)

if [ -f "$EVENTS_CPP" ]; then
    echo "Found: $EVENTS_CPP"
    
    # Check if it has the problematic line
    if grep -q "ProcessAncestryManager::getInstance" "$EVENTS_CPP"; then
        echo "📝 Fixing namespace in $EVENTS_CPP..."
        
        # Make backup
        cp "$EVENTS_CPP" "$EVENTS_CPP.namespace-backup"
        
        # Fix the namespace - add tables:: prefix
        sed -i 's/ProcessAncestryManager::getInstance/tables::ProcessAncestryManager::getInstance/g' "$EVENTS_CPP"
        
        echo "✅ Fixed namespace in source file"
        
        # Show the fix
        echo ""
        echo "🔍 Verification - line with fix:"
        grep -n "tables::ProcessAncestryManager" "$EVENTS_CPP" || echo "Pattern not found"
    else
        echo "✅ No namespace issue found in source file"
    fi
else
    echo "❌ process_events.cpp not found"
    echo ""
    echo "🔍 Let's find all process_events.cpp files:"
    find . -name "process_events.cpp" -type f
    echo ""
    echo "🔍 Let's find files with ProcessAncestryManager:"
    find . -name "*.cpp" -exec grep -l "ProcessAncestryManager" {} \; 2>/dev/null
fi

echo ""
echo "📝 Also checking for any files in build directory that need fixing..."

# Also check build directory files
BUILD_CPP=$(find build -name "process_events.cpp" -path "*/linux/*" 2>/dev/null | head -1)

if [ -f "$BUILD_CPP" ]; then
    echo "Found build file: $BUILD_CPP"
    
    if grep -q "ProcessAncestryManager::getInstance" "$BUILD_CPP"; then
        echo "📝 Fixing namespace in build file..."
        sed -i 's/ProcessAncestryManager::getInstance/tables::ProcessAncestryManager::getInstance/g' "$BUILD_CPP"
        echo "✅ Fixed namespace in build file"
    fi
fi

echo ""
echo "🔨 Testing the fix..."
cd build

# Try building just the events table
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 NAMESPACE FIX SUCCESSFUL!"
    echo "🔨 Building full osquery..."
    make -j1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉🎉 COMPLETE BUILD SUCCESS! 🎉🎉"
        echo "✅ osquery with process ancestry support built successfully!"
        echo ""
        echo "🚀 Ready for installation and testing!"
    else
        echo ""
        echo "❌ Full build had issues, but events table compiled!"
    fi
else
    echo ""
    echo "❌ Still failing. Let's debug further..."
    echo ""
    echo "🔍 Current error output:"
    make osquery_tables_events_eventstable 2>&1 | tail -10
    echo ""
    echo "🔍 Let's check what files actually exist:"
    find . -name "*ancestry*" -type f 2>/dev/null | head -10
fi
