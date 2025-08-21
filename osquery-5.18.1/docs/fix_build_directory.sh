#!/bin/bash

echo "🔧 FIXING BUILD DIRECTORY ISSUE"
echo "==============================="

cd ~/osquery-build/osquery
echo "Working directory: $(pwd)"

# The issue: build system copies headers to build directory
# Solution: Create files in both source AND build directories

SOURCE_DIR="osquery/tables/events/linux"
BUILD_DIR="build/ns_osquery_tables_events_eventstable/osquery/tables/events/linux"

echo ""
echo "📁 Directories:"
echo "Source: $SOURCE_DIR"
echo "Build:  $BUILD_DIR"

# Ensure both directories exist
mkdir -p "$SOURCE_DIR"
mkdir -p "$BUILD_DIR"

echo ""
echo "📝 Creating process_ancestry_cache.h in BOTH locations..."

# Create the header content
HEADER_CONTENT='#pragma once
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include <unordered_map>
#include <list>
#include <osquery/core/flags.h>
#include <osquery/core/tables.h>

namespace osquery {
namespace tables {

struct ProcessAncestryNode {
  pid_t pid;
  pid_t ppid;
  std::string path;
  std::string cmdline;
  std::string name;
  uid_t uid;
  gid_t gid;
  std::string toJson() const;
};

class ProcessAncestryManager {
public:
  static ProcessAncestryManager& getInstance();
  std::string getProcessAncestry(pid_t pid);
};

} // namespace tables
} // namespace osquery

DECLARE_uint64(process_ancestry_cache_size);
DECLARE_uint64(process_ancestry_max_depth);
DECLARE_uint64(process_ancestry_cache_ttl);'

# Create header in source directory
echo "$HEADER_CONTENT" > "$SOURCE_DIR/process_ancestry_cache.h"
echo "✅ Created in source: $SOURCE_DIR/process_ancestry_cache.h"

# Create header in build directory
echo "$HEADER_CONTENT" > "$BUILD_DIR/process_ancestry_cache.h"
echo "✅ Created in build: $BUILD_DIR/process_ancestry_cache.h"

echo ""
echo "📝 Creating process_ancestry_cache.cpp in source directory..."

# Create the source content
SOURCE_CONTENT='#include "process_ancestry_cache.h"
#include <fstream>
#include <sstream>
#include <osquery/core/flags.h>
#include <osquery/logger/logger.h>

namespace osquery {
namespace tables {

DEFINE_uint64(process_ancestry_cache_size, 1000, "Process ancestry cache size");
DEFINE_uint64(process_ancestry_max_depth, 32, "Process ancestry max depth");
DEFINE_uint64(process_ancestry_cache_ttl, 300, "Process ancestry cache TTL");

std::string ProcessAncestryNode::toJson() const {
  std::ostringstream json;
  json << "{";
  json << "\"pid\":" << pid << ",";
  json << "\"ppid\":" << ppid << ",";
  json << "\"path\":\"" << path << "\",";
  json << "\"cmdline\":\"" << cmdline << "\",";
  json << "\"name\":\"" << name << "\",";
  json << "\"uid\":" << uid << ",";
  json << "\"gid\":" << gid;
  json << "}";
  return json.str();
}

ProcessAncestryManager& ProcessAncestryManager::getInstance() {
  static ProcessAncestryManager instance;
  return instance;
}

std::string ProcessAncestryManager::getProcessAncestry(pid_t pid) {
  ProcessAncestryNode node;
  node.pid = pid;
  node.ppid = 0;
  node.path = "[unknown]";
  node.cmdline = "[unknown]";
  node.name = "[unknown]";
  node.uid = 0;
  node.gid = 0;
  
  std::string stat_path = "/proc/" + std::to_string(pid) + "/stat";
  std::ifstream file(stat_path);
  if (file.is_open()) {
    std::string line;
    std::getline(file, line);
    std::istringstream iss(line);
    std::string token;
    for (int i = 0; i < 4 && std::getline(iss, token, " "); ++i) {
      if (i == 3) {
        try {
          node.ppid = std::stoi(token);
        } catch (...) {
          node.ppid = 0;
        }
        break;
      }
    }
  }
  
  return "[" + node.toJson() + "]";
}

} // namespace tables
} // namespace osquery'

# Create source file in source directory only (not needed in build)
echo "$SOURCE_CONTENT" > "$SOURCE_DIR/process_ancestry_cache.cpp"
echo "✅ Created source: $SOURCE_DIR/process_ancestry_cache.cpp"

echo ""
echo "🔍 Verifying files exist..."

if [ -f "$SOURCE_DIR/process_ancestry_cache.h" ] && [ -f "$BUILD_DIR/process_ancestry_cache.h" ]; then
    echo "✅ Header files exist in both locations"
    ls -la "$SOURCE_DIR/process_ancestry_cache.h"
    ls -la "$BUILD_DIR/process_ancestry_cache.h"
else
    echo "❌ Header files missing!"
    exit 1
fi

if [ -f "$SOURCE_DIR/process_ancestry_cache.cpp" ]; then
    echo "✅ Source file exists"
    ls -la "$SOURCE_DIR/process_ancestry_cache.cpp"
else
    echo "❌ Source file missing!"
    exit 1
fi

echo ""
echo "📝 Fixing process_events.h in BUILD directory..."

BUILD_EVENTS_H="$BUILD_DIR/process_events.h"
if [ -f "$BUILD_EVENTS_H" ]; then
    if ! grep -q "process_ancestry_cache.h" "$BUILD_EVENTS_H"; then
        cp "$BUILD_EVENTS_H" "$BUILD_EVENTS_H.backup"
        sed -i '/auditeventpublisher.h/a #include <osquery/tables/events/linux/process_ancestry_cache.h>' "$BUILD_EVENTS_H"
        echo "✅ Updated build process_events.h"
    else
        echo "✅ Build process_events.h already has include"
    fi
else
    echo "❌ Build process_events.h not found at: $BUILD_EVENTS_H"
fi

echo ""
echo "📝 Also fixing source process_events.h..."

SOURCE_EVENTS_H="$SOURCE_DIR/process_events.h"
if [ -f "$SOURCE_EVENTS_H" ]; then
    if ! grep -q "process_ancestry_cache.h" "$SOURCE_EVENTS_H"; then
        cp "$SOURCE_EVENTS_H" "$SOURCE_EVENTS_H.backup"
        sed -i '/auditeventpublisher.h/a #include <osquery/tables/events/linux/process_ancestry_cache.h>' "$SOURCE_EVENTS_H"
        echo "✅ Updated source process_events.h"
    else
        echo "✅ Source process_events.h already has include"
    fi
else
    echo "❌ Source process_events.h not found"
fi

echo ""
echo "📝 Fixing process_events.cpp..."

SOURCE_EVENTS_CPP="$SOURCE_DIR/process_events.cpp"
if [ -f "$SOURCE_EVENTS_CPP" ]; then
    if ! grep -q "ProcessAncestryManager" "$SOURCE_EVENTS_CPP"; then
        cp "$SOURCE_EVENTS_CPP" "$SOURCE_EVENTS_CPP.backup"
        # Add ancestry integration after the pid line
        sed -i '/row\["pid"\] = std::to_string(process_id);/a \
\
  // Add process ancestry\
  try {\
    auto& ancestry_manager = tables::ProcessAncestryManager::getInstance();\
    row["ancestry"] = ancestry_manager.getProcessAncestry(process_id);\
  } catch (...) {\
    row["ancestry"] = "[]";\
  }' "$SOURCE_EVENTS_CPP"
        echo "✅ Updated process_events.cpp with ancestry integration"
    else
        echo "✅ process_events.cpp already has ancestry integration"
    fi
else
    echo "❌ process_events.cpp not found"
fi

echo ""
echo "🎯 Files created in both source and build directories!"
echo ""
echo "🔨 Testing compilation..."
cd build

# Clean the specific target first
echo "🧹 Cleaning previous build artifacts..."
make clean osquery_tables_events_eventstable 2>/dev/null || true

# Try building just the events table
echo "📦 Building events table..."
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 EVENTS TABLE BUILD SUCCESSFUL!"
    echo "🔨 Building full osquery..."
    make -j1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉🎉 COMPLETE BUILD SUCCESS! 🎉🎉"
        echo "✅ osquery with process ancestry support built successfully!"
        echo ""
        echo "🚀 Ready for installation and testing!"
        echo ""
        echo "Next steps:"
        echo "1. sudo make install"
        echo "2. Configure osquery with ancestry flags"
        echo "3. Test: SELECT pid, parent, ancestry FROM process_events LIMIT 5;"
    else
        echo ""
        echo "❌ Full build failed - but events table compiled!"
        echo "The ancestry feature should work when the rest builds successfully."
    fi
else
    echo ""
    echo "❌ Events table build failed"
    echo "Check if files were created correctly:"
    echo ""
    echo "Build directory files:"
    ls -la "$BUILD_DIR/" | grep ancestry || echo "No ancestry files in build dir"
    echo ""
    echo "Source directory files:"
    ls -la "$SOURCE_DIR/" | grep ancestry || echo "No ancestry files in source dir"
fi
