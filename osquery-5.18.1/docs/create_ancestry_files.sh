#!/bin/bash

echo "🔧 CREATING PROCESS ANCESTRY FILES"
echo "=================================="
echo ""

echo "Creating missing process ancestry implementation files..."
echo "These files implement the core ancestry feature for process_events."
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

TARGET_DIR="osquery/tables/events/linux"
echo "Target directory: $TARGET_DIR"

# Ensure the directory exists
mkdir -p "$TARGET_DIR"

echo ""
echo "📝 Creating process_ancestry_cache.h..."

cat > "$TARGET_DIR/process_ancestry_cache.h" << 'EOF'
/**
 * Copyright (c) 2014-present, The osquery authors
 *
 * This source code is licensed as defined by the LICENSE file found in the
 * root directory of this source tree.
 *
 * SPDX-License-Identifier: (Apache-2.0 OR GPL-2.0-only)
 */

#pragma once

#include <chrono>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include <osquery/core/flags.h>
#include <osquery/core/tables.h>

namespace osquery {
namespace tables {

/**
 * Structure representing a single process in the ancestry chain
 */
struct ProcessAncestryNode {
  pid_t pid;
  pid_t ppid;
  std::string path;
  std::string cmdline;
  std::string name;
  uid_t uid;
  gid_t gid;
  std::chrono::steady_clock::time_point creation_time;

  std::string toJson() const;
};

/**
 * Cache entry containing process ancestry information and metadata
 */
struct ProcessAncestryCache {
  std::vector<ProcessAncestryNode> ancestry_chain;
  std::chrono::steady_clock::time_point cache_time;
  size_t depth;
};

/**
 * LRU Cache for process ancestry information to improve performance
 */
class ProcessAncestryLRUCache {
 private:
  size_t max_size_;
  std::list<std::pair<pid_t, ProcessAncestryCache>> cache_list_;
  std::unordered_map<pid_t, decltype(cache_list_)::iterator> cache_map_;
  mutable std::mutex mutex_;

 public:
  explicit ProcessAncestryLRUCache(size_t max_size);
  
  bool get(pid_t pid, ProcessAncestryCache& result);
  void put(pid_t pid, const ProcessAncestryCache& cache_entry);
  void clear();
  size_t size() const;
};

/**
 * Process Ancestry Manager - singleton class that manages ancestry information
 */
class ProcessAncestryManager {
 private:
  std::unique_ptr<ProcessAncestryLRUCache> cache_;
  std::chrono::seconds cache_ttl_;
  size_t max_depth_;
  mutable std::mutex mutex_;

  ProcessAncestryManager();

  // Helper methods for reading process information from /proc
  bool readProcessInfo(pid_t pid, ProcessAncestryNode& node);
  std::string readExecutablePath(pid_t pid);
  std::string readCommandLine(pid_t pid);
  std::string readProcessName(pid_t pid);
  pid_t readParentPid(pid_t pid);
  std::pair<uid_t, gid_t> readProcessIds(pid_t pid);
  
  // Build ancestry chain by traversing parent processes
  std::vector<ProcessAncestryNode> buildAncestryChain(pid_t pid);

 public:
  static ProcessAncestryManager& getInstance();
  
  // Get ancestry information for a process (JSON format)
  std::string getProcessAncestry(pid_t pid);
  
  // Configuration management
  void updateConfiguration();
  void clearCache();
  
  // Statistics
  size_t getCacheSize() const;
  
  // Prevent copying and assignment
  ProcessAncestryManager(const ProcessAncestryManager&) = delete;
  ProcessAncestryManager& operator=(const ProcessAncestryManager&) = delete;
};

} // namespace tables
} // namespace osquery

// Configuration flags
DECLARE_uint64(process_ancestry_cache_size);
DECLARE_uint64(process_ancestry_max_depth);
DECLARE_uint64(process_ancestry_cache_ttl);
EOF

echo "✅ Created process_ancestry_cache.h"

echo ""
echo "📝 Creating process_ancestry_cache.cpp..."

cat > "$TARGET_DIR/process_ancestry_cache.cpp" << 'EOF'
/**
 * Copyright (c) 2014-present, The osquery authors
 *
 * This source code is licensed as defined by the LICENSE file found in the
 * root directory of this source tree.
 *
 * SPDX-License-Identifier: (Apache-2.0 OR GPL-2.0-only)
 */

#include "process_ancestry_cache.h"

#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>

#include <osquery/core/flags.h>
#include <osquery/logger/logger.h>

namespace osquery {
namespace tables {

// Configuration flags with default values
DEFINE_uint64(process_ancestry_cache_size,
              1000,
              "Maximum number of process ancestry entries to cache");

DEFINE_uint64(process_ancestry_max_depth,
              32,
              "Maximum depth to traverse when building process ancestry");

DEFINE_uint64(process_ancestry_cache_ttl,
              300,
              "Time-to-live for cached ancestry entries in seconds");

std::string ProcessAncestryNode::toJson() const {
  std::ostringstream json;
  json << "{";
  json << "\"pid\":" << pid << ",";
  json << "\"ppid\":" << ppid << ",";

  // Escape JSON strings to prevent injection/parsing issues
  json << "\"path\":\"";
  for (char c : path) {
    if (c == '\"' || c == '\\') {
      json << '\\';
    }
    if (c >= 32 && c <= 126) { // Printable ASCII
      json << c;
    } else {
      json << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (unsigned char)c;
    }
  }
  json << "\",";

  json << "\"cmdline\":\"";
  for (char c : cmdline) {
    if (c == '\"' || c == '\\') {
      json << '\\';
    }
    if (c >= 32 && c <= 126) { // Printable ASCII
      json << c;
    } else {
      json << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (unsigned char)c;
    }
  }
  json << "\",";

  json << "\"name\":\"";
  for (char c : name) {
    if (c == '\"' || c == '\\') {
      json << '\\';
    }
    if (c >= 32 && c <= 126) { // Printable ASCII
      json << c;
    } else {
      json << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (unsigned char)c;
    }
  }
  json << "\",";

  json << "\"uid\":" << uid << ",";
  json << "\"gid\":" << gid;
  json << "}";
  return json.str();
}

ProcessAncestryLRUCache::ProcessAncestryLRUCache(size_t max_size) : max_size_(max_size) {}

bool ProcessAncestryLRUCache::get(pid_t pid, ProcessAncestryCache& result) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  auto it = cache_map_.find(pid);
  if (it == cache_map_.end()) {
    return false;
  }

  // Move to front (most recently used)
  cache_list_.splice(cache_list_.begin(), cache_list_, it->second);
  result = it->second->second;
  return true;
}

void ProcessAncestryLRUCache::put(pid_t pid, const ProcessAncestryCache& cache_entry) {
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = cache_map_.find(pid);
  if (it != cache_map_.end()) {
    // Update existing entry
    it->second->second = cache_entry;
    cache_list_.splice(cache_list_.begin(), cache_list_, it->second);
    return;
  }

  // Add new entry
  cache_list_.emplace_front(pid, cache_entry);
  cache_map_[pid] = cache_list_.begin();

  // Remove oldest entry if cache is full
  if (cache_list_.size() > max_size_) {
    auto last = cache_list_.end();
    --last;
    cache_map_.erase(last->first);
    cache_list_.pop_back();
  }
}

void ProcessAncestryLRUCache::clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  cache_list_.clear();
  cache_map_.clear();
}

size_t ProcessAncestryLRUCache::size() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return cache_list_.size();
}

ProcessAncestryManager::ProcessAncestryManager() {
  updateConfiguration();
}

ProcessAncestryManager& ProcessAncestryManager::getInstance() {
  static ProcessAncestryManager instance;
  return instance;
}

void ProcessAncestryManager::updateConfiguration() {
  std::lock_guard<std::mutex> lock(mutex_);
  
  // Update cache size
  size_t cache_size = FLAGS_process_ancestry_cache_size;
  if (!cache_ || cache_->size() != cache_size) {
    cache_ = std::make_unique<ProcessAncestryLRUCache>(cache_size);
  }
  
  // Update other configuration
  cache_ttl_ = std::chrono::seconds(FLAGS_process_ancestry_cache_ttl);
  max_depth_ = FLAGS_process_ancestry_max_depth;
}

std::string ProcessAncestryManager::getProcessAncestry(pid_t pid) {
  // Validate PID
  if (pid <= 0) {
    VLOG(1) << "Invalid PID: " << pid;
    return "[]";
  }

  std::lock_guard<std::mutex> lock(mutex_);

  // Check cache first
  ProcessAncestryCache cached;
  auto now = std::chrono::steady_clock::now();
  
  if (cache_->get(pid, cached)) {
    // Check if cache entry is still valid
    auto age = now - cached.cache_time;
    if (age < cache_ttl_) {
      // Build JSON from cached ancestry
      std::ostringstream json;
      json << "[";
      for (size_t i = 0; i < cached.ancestry_chain.size(); ++i) {
        if (i > 0) json << ",";
        json << cached.ancestry_chain[i].toJson();
      }
      json << "]";
      return json.str();
    }
  }

  // Cache miss or expired - build new ancestry chain
  try {
    auto ancestry_chain = buildAncestryChain(pid);
    
    // Cache the result
    ProcessAncestryCache new_cache;
    new_cache.ancestry_chain = ancestry_chain;
    new_cache.cache_time = now;
    new_cache.depth = ancestry_chain.size();
    cache_->put(pid, new_cache);

    // Build JSON response
    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < ancestry_chain.size(); ++i) {
      if (i > 0) json << ",";
      json << ancestry_chain[i].toJson();
    }
    json << "]";
    return json.str();
    
  } catch (const std::exception& e) {
    VLOG(1) << "Failed to build ancestry for PID " << pid << ": " << e.what();
    return "[]";
  }
}

std::vector<ProcessAncestryNode> ProcessAncestryManager::buildAncestryChain(pid_t pid) {
  std::vector<ProcessAncestryNode> chain;
  std::set<pid_t> visited; // Prevent infinite loops
  
  pid_t current_pid = pid;
  size_t depth = 0;
  
  while (current_pid > 1 && depth < max_depth_) {
    // Check for cycles
    if (visited.count(current_pid) > 0) {
      VLOG(1) << "Detected cycle in process ancestry at PID: " << current_pid;
      break;
    }
    visited.insert(current_pid);
    
    ProcessAncestryNode node;
    if (!readProcessInfo(current_pid, node)) {
      // Process doesn't exist or can't be read
      break;
    }
    
    chain.push_back(node);
    current_pid = node.ppid;
    depth++;
  }
  
  return chain;
}

bool ProcessAncestryManager::readProcessInfo(pid_t pid, ProcessAncestryNode& node) {
  // Validate PID range
  if (pid <= 0 || pid > 4194304) { // Linux PID_MAX_LIMIT
    VLOG(1) << "Invalid PID range: " << pid;
    return false;
  }

  node.pid = pid;
  node.creation_time = std::chrono::steady_clock::now();
  
  // Read parent PID
  node.ppid = readParentPid(pid);
  if (node.ppid < 0) {
    return false;
  }
  
  // Read process name
  node.name = readProcessName(pid);
  
  // Read executable path
  node.path = readExecutablePath(pid);
  if (node.path.empty()) {
    node.path = "[unknown]";
  }
  
  // Read command line
  node.cmdline = readCommandLine(pid);
  if (node.cmdline.empty()) {
    node.cmdline = node.name.empty() ? "[unknown]" : node.name;
  }
  
  // Read UID/GID
  auto ids = readProcessIds(pid);
  node.uid = ids.first;
  node.gid = ids.second;
  
  return true;
}

std::string ProcessAncestryManager::readExecutablePath(pid_t pid) {
  std::string exe_path = "/proc/" + std::to_string(pid) + "/exe";
  char buffer[4096];
  ssize_t len = readlink(exe_path.c_str(), buffer, sizeof(buffer) - 1);
  if (len > 0) {
    buffer[len] = '\0';
    return std::string(buffer);
  }
  return "";
}

std::string ProcessAncestryManager::readCommandLine(pid_t pid) {
  std::string cmdline_path = "/proc/" + std::to_string(pid) + "/cmdline";
  std::ifstream file(cmdline_path);
  if (!file.is_open()) {
    return "";
  }
  
  std::string cmdline;
  std::getline(file, cmdline, '\0');
  
  // Replace null bytes with spaces for multi-argument commands
  for (char& c : cmdline) {
    if (c == '\0') {
      c = ' ';
    }
  }
  
  return cmdline;
}

std::string ProcessAncestryManager::readProcessName(pid_t pid) {
  std::string comm_path = "/proc/" + std::to_string(pid) + "/comm";
  std::ifstream file(comm_path);
  if (!file.is_open()) {
    return "";
  }
  
  std::string name;
  std::getline(file, name);
  return name;
}

pid_t ProcessAncestryManager::readParentPid(pid_t pid) {
  std::string stat_path = "/proc/" + std::to_string(pid) + "/stat";
  std::ifstream file(stat_path);
  if (!file.is_open()) {
    return -1;
  }
  
  std::string line;
  std::getline(file, line);
  
  // Parse stat file - PPID is the 4th field
  std::istringstream iss(line);
  std::string token;
  for (int i = 0; i < 4 && std::getline(iss, token, ' '); ++i) {
    if (i == 3) {
      try {
        return std::stoi(token);
      } catch (const std::exception&) {
        return -1;
      }
    }
  }
  
  return -1;
}

std::pair<uid_t, gid_t> ProcessAncestryManager::readProcessIds(pid_t pid) {
  std::string status_path = "/proc/" + std::to_string(pid) + "/status";
  std::ifstream file(status_path);
  if (!file.is_open()) {
    return {0, 0};
  }
  
  uid_t uid = 0;
  gid_t gid = 0;
  std::string line;
  
  while (std::getline(file, line)) {
    if (line.find("Uid:") == 0) {
      std::istringstream iss(line);
      std::string label, real_uid;
      iss >> label >> real_uid;
      try {
        uid = std::stoul(real_uid);
      } catch (const std::exception&) {
        uid = 0;
      }
    } else if (line.find("Gid:") == 0) {
      std::istringstream iss(line);
      std::string label, real_gid;
      iss >> label >> real_gid;
      try {
        gid = std::stoul(real_gid);
      } catch (const std::exception&) {
        gid = 0;
      }
    }
  }
  
  return {uid, gid};
}

void ProcessAncestryManager::clearCache() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (cache_) {
    cache_->clear();
  }
}

size_t ProcessAncestryManager::getCacheSize() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return cache_ ? cache_->size() : 0;
}

} // namespace tables
} // namespace osquery
EOF

echo "✅ Created process_ancestry_cache.cpp"

echo ""
echo "🎯 Process Ancestry Files Created Successfully!"
echo ""
echo "Files created:"
echo "  ✅ $TARGET_DIR/process_ancestry_cache.h"
echo "  ✅ $TARGET_DIR/process_ancestry_cache.cpp"
echo ""
echo "These files implement:"
echo "  🔧 LRU cache for performance optimization"
echo "  🔧 Process ancestry traversal via /proc filesystem"
echo "  🔧 JSON serialization with proper escaping"
echo "  🔧 Thread-safe singleton manager"
echo "  🔧 Configurable cache size, depth, and TTL"
echo ""
echo "🔨 Continuing build..."
cd build
make -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "✅ Process ancestry implementation compiled successfully!"
    echo "✅ osquery with process ancestry support built successfully!"
    echo ""
    echo "🚀 Your ancestry implementation is ready for testing!"
    echo ""
    echo "Next steps:"
    echo "1. Install the built osquery"
    echo "2. Configure and start osquery daemon"
    echo "3. Test the process_events table with ancestry column"
else
    echo ""
    echo "❌ Build failed. Checking for any remaining issues..."
    echo ""
    echo "The build might need additional fixes or missing dependencies."
fi
EOF

echo "✅ Created create_ancestry_files.sh"
