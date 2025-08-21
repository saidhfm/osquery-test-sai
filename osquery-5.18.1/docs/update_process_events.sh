#!/bin/bash

echo "🔧 UPDATING PROCESS_EVENTS FILES"
echo "================================="
echo ""

echo "Updating process_events.h and process_events.cpp to integrate ancestry..."
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

EVENTS_DIR="osquery/tables/events/linux"
PROCESS_EVENTS_H="$EVENTS_DIR/process_events.h"
PROCESS_EVENTS_CPP="$EVENTS_DIR/process_events.cpp"

echo "🔍 Updating files:"
echo "Header: $PROCESS_EVENTS_H"
echo "Source: $PROCESS_EVENTS_CPP"
echo ""

# Update process_events.h to include ancestry cache
if [ -f "$PROCESS_EVENTS_H" ]; then
    echo "📝 Adding ancestry include to process_events.h..."
    
    # Backup
    cp "$PROCESS_EVENTS_H" "$PROCESS_EVENTS_H.ancestry-backup"
    
    # Check if include is already present
    if ! grep -q "process_ancestry_cache.h" "$PROCESS_EVENTS_H"; then
        # Add the include after the existing includes
        sed -i '/^#include.*auditeventpublisher.h/a #include <osquery/tables/events/linux/process_ancestry_cache.h>' "$PROCESS_EVENTS_H"
        echo "✅ Added ancestry cache include to header"
    else
        echo "✅ Ancestry include already present in header"
    fi
fi

# Update process_events.cpp to integrate ancestry
if [ -f "$PROCESS_EVENTS_CPP" ]; then
    echo "📝 Adding ancestry integration to process_events.cpp..."
    
    # Backup
    cp "$PROCESS_EVENTS_CPP" "$PROCESS_EVENTS_CPP.ancestry-backup"
    
    # Check if ancestry integration is already present
    if ! grep -q "ProcessAncestryManager" "$PROCESS_EVENTS_CPP"; then
        # Find the location where we set row["pid"] and add ancestry after it
        sed -i '/row\["pid"\] = std::to_string(process_id);/a \
\
  // Get process ancestry information (Linux only)\
  try {\
    auto& ancestry_manager = ProcessAncestryManager::getInstance();\
    row["ancestry"] = ancestry_manager.getProcessAncestry(process_id);\
  } catch (const std::exception& e) {\
    VLOG(1) << "Failed to get ancestry for PID " << process_id << ": " << e.what();\
    row["ancestry"] = "[]"; // Empty JSON array on error\
  }' "$PROCESS_EVENTS_CPP"
        echo "✅ Added ancestry integration to source"
    else
        echo "✅ Ancestry integration already present in source"
    fi
fi

echo ""
echo "🎯 Process Events Files Updated Successfully!"
echo ""
echo "Changes made:"
echo "  ✅ Added ancestry cache include to process_events.h"
echo "  ✅ Added ancestry integration to process_events.cpp"
echo "  ✅ Ancestry data will be added to each process event row"
echo ""
echo "🔨 Testing compilation..."
cd build
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 PROCESS EVENTS COMPILATION SUCCESSFUL!"
    echo "✅ Process events with ancestry support compiled successfully!"
    echo ""
    echo "🔨 Building full osquery..."
    make -j1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 FULL BUILD SUCCESSFUL!"
        echo "✅ osquery with process ancestry support built successfully!"
        echo ""
        echo "🚀 Your ancestry implementation is ready for testing!"
    else
        echo ""
        echo "❌ Full build failed. Some components still need fixes."
    fi
else
    echo ""
    echo "❌ Process events compilation failed."
    echo "Check for missing includes or compilation errors."
fi
EOF

echo "✅ Created update_process_events.sh"
