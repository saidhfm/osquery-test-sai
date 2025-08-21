#!/bin/bash

echo "🔧 FIX GETLINE SYNTAX ERROR"
echo "==========================="

cd ~/osquery-build/osquery
echo "Working directory: $(pwd)"

# The error is in process_ancestry_cache.cpp
# std::getline(iss, token, " ") should be std::getline(iss, token, ' ')

echo ""
echo "🔍 Finding process_ancestry_cache.cpp..."

ANCESTRY_CPP=$(find . -name "process_ancestry_cache.cpp" -type f | head -1)

if [ -f "$ANCESTRY_CPP" ]; then
    echo "Found: $ANCESTRY_CPP"
    
    # Check for the problematic line
    if grep -q 'getline(iss, token, " ")' "$ANCESTRY_CPP"; then
        echo "📝 Fixing getline syntax error..."
        
        # Make backup
        cp "$ANCESTRY_CPP" "$ANCESTRY_CPP.getline-backup"
        
        # Fix the getline call - change " " to ' '
        sed -i 's/getline(iss, token, " ")/getline(iss, token, '"'"' '"'"')/g' "$ANCESTRY_CPP"
        
        echo "✅ Fixed getline syntax in $ANCESTRY_CPP"
        
        # Show the fix
        echo ""
        echo "🔍 Verification - line with fix:"
        grep -n "getline.*token.*'" "$ANCESTRY_CPP" || echo "Let's check the context:"
        grep -A2 -B2 "getline.*token" "$ANCESTRY_CPP"
    else
        echo "❌ getline error pattern not found"
        echo ""
        echo "🔍 Let's see what getline calls exist:"
        grep -n "getline" "$ANCESTRY_CPP"
    fi
else
    echo "❌ process_ancestry_cache.cpp not found"
    echo ""
    echo "🔍 Let's find ancestry files:"
    find . -name "*ancestry*" -type f
fi

echo ""
echo "🔨 Testing the fix..."
cd build

# Clean the specific object file to force recompilation
rm -f osquery/tables/events/CMakeFiles/osquery_tables_events_eventstable.dir/linux/process_ancestry_cache.cpp.o

# Try building just the events table
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 GETLINE FIX SUCCESSFUL!"
    echo "🔨 Building full osquery..."
    make -j1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉🎉 COMPLETE BUILD SUCCESS! 🎉🎉"
        echo "✅ osquery with process ancestry support built successfully!"
        echo ""
        echo "🚀 Ready for installation and testing!"
        echo ""
        echo "Your osquery binary is ready at: $(pwd)/osquery/osqueryi"
        echo "Your osquery daemon is ready at: $(pwd)/osquery/osqueryd"
    else
        echo ""
        echo "❌ Full build had issues, but events table compiled!"
        echo "The ancestry feature should work when rest builds successfully."
    fi
else
    echo ""
    echo "❌ Still having compilation issues..."
    echo ""
    echo "🔍 Latest error:"
    make osquery_tables_events_eventstable 2>&1 | tail -5
fi
