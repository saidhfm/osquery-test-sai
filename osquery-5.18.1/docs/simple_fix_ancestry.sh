#!/bin/bash

echo "🔧 SIMPLE ANCESTRY FIX"
echo "====================="
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
echo "Creating files in: $TARGET_DIR"

# Ensure directory exists
mkdir -p "$TARGET_DIR"

echo ""
echo "📝 Creating process_ancestry_cache.h..."

# Create header file with cat (simpler than heredoc)
cat > "$TARGET_DIR/process_ancestry_cache.h" << 'HEADER_END'
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

struct ProcessAncestryCache {
  std::vector<ProcessAncestryNode> ancestry_chain;
  std::chrono::steady_clock::time_point cache_time;
  size_t depth;
};

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

class ProcessAncestryManager {
 private:
  std::unique_ptr<ProcessAncestryLRUCache> cache_;
  std::chrono::seconds cache_ttl_;
  size_t max_depth_;
  mutable std::mutex mutex_;
  ProcessAncestryManager();
  bool readProcessInfo(pid_t pid, ProcessAncestryNode& node);
  std::string readExecutablePath(pid_t pid);
  std::string readCommandLine(pid_t pid);
  std::string readProcessName(pid_t pid);
  pid_t readParentPid(pid_t pid);
  std::pair<uid_t, gid_t> readProcessIds(pid_t pid);
  std::vector<ProcessAncestryNode> buildAncestryChain(pid_t pid);

 public:
  static ProcessAncestryManager& getInstance();
  std::string getProcessAncestry(pid_t pid);
  void updateConfiguration();
  void clearCache();
  size_t getCacheSize() const;
  ProcessAncestryManager(const ProcessAncestryManager&) = delete;
  ProcessAncestryManager& operator=(const ProcessAncestryManager&) = delete;
};

} // namespace tables
} // namespace osquery

DECLARE_uint64(process_ancestry_cache_size);
DECLARE_uint64(process_ancestry_max_depth);
DECLARE_uint64(process_ancestry_cache_ttl);
HEADER_END

echo "✅ Created process_ancestry_cache.h"

echo ""
echo "📝 Creating process_ancestry_cache.cpp..."

# Split the .cpp file into parts to avoid heredoc issues
cat > "$TARGET_DIR/process_ancestry_cache.cpp" << 'CPP_PART1'
#include "process_ancestry_cache.h"
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <set>
#include <osquery/core/flags.h>
#include <osquery/logger/logger.h>

namespace osquery {
namespace tables {

DEFINE_uint64(process_ancestry_cache_size, 1000, "Maximum number of process ancestry entries to cache");
DEFINE_uint64(process_ancestry_max_depth, 32, "Maximum depth to traverse when building process ancestry");
DEFINE_uint64(process_ancestry_cache_ttl, 300, "Time-to-live for cached ancestry entries in seconds");

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

ProcessAncestryLRUCache::ProcessAncestryLRUCache(size_t max_size) : max_size_(max_size) {}

bool ProcessAncestryLRUCache::get(pid_t pid, ProcessAncestryCache& result) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = cache_map_.find(pid);
  if (it == cache_map_.end()) return false;
  cache_list_.splice(cache_list_.begin(), cache_list_, it->second);
  result = it->second->second;
  return true;
}

void ProcessAncestryLRUCache::put(pid_t pid, const ProcessAncestryCache& cache_entry) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = cache_map_.find(pid);
  if (it != cache_map_.end()) {
    it->second->second = cache_entry;
    cache_list_.splice(cache_list_.begin(), cache_list_, it->second);
    return;
  }
  cache_list_.emplace_front(pid, cache_entry);
  cache_map_[pid] = cache_list_.begin();
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

ProcessAncestryManager::ProcessAncestryManager() { updateConfiguration(); }

ProcessAncestryManager& ProcessAncestryManager::getInstance() {
  static ProcessAncestryManager instance;
  return instance;
}
CPP_PART1

# Continue with the rest of the implementation
cat >> "$TARGET_DIR/process_ancestry_cache.cpp" << 'CPP_PART2'
void ProcessAncestryManager::updateConfiguration() {
  std::lock_guard<std::mutex> lock(mutex_);
  size_t cache_size = FLAGS_process_ancestry_cache_size;
  if (!cache_ || cache_->size() != cache_size) {
    cache_ = std::make_unique<ProcessAncestryLRUCache>(cache_size);
  }
  cache_ttl_ = std::chrono::seconds(FLAGS_process_ancestry_cache_ttl);
  max_depth_ = FLAGS_process_ancestry_max_depth;
}

std::string ProcessAncestryManager::getProcessAncestry(pid_t pid) {
  if (pid <= 0) return "[]";
  std::lock_guard<std::mutex> lock(mutex_);
  ProcessAncestryCache cached;
  auto now = std::chrono::steady_clock::now();
  
  if (cache_->get(pid, cached)) {
    auto age = now - cached.cache_time;
    if (age < cache_ttl_) {
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

  try {
    auto ancestry_chain = buildAncestryChain(pid);
    ProcessAncestryCache new_cache;
    new_cache.ancestry_chain = ancestry_chain;
    new_cache.cache_time = now;
    new_cache.depth = ancestry_chain.size();
    cache_->put(pid, new_cache);
    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < ancestry_chain.size(); ++i) {
      if (i > 0) json << ",";
      json << ancestry_chain[i].toJson();
    }
    json << "]";
    return json.str();
  } catch (const std::exception& e) {
    return "[]";
  }
}

std::vector<ProcessAncestryNode> ProcessAncestryManager::buildAncestryChain(pid_t pid) {
  std::vector<ProcessAncestryNode> chain;
  std::set<pid_t> visited;
  pid_t current_pid = pid;
  size_t depth = 0;
  
  while (current_pid > 1 && depth < max_depth_) {
    if (visited.count(current_pid) > 0) break;
    visited.insert(current_pid);
    ProcessAncestryNode node;
    if (!readProcessInfo(current_pid, node)) break;
    chain.push_back(node);
    current_pid = node.ppid;
    depth++;
  }
  return chain;
}

bool ProcessAncestryManager::readProcessInfo(pid_t pid, ProcessAncestryNode& node) {
  if (pid <= 0 || pid > 4194304) return false;
  node.pid = pid;
  node.creation_time = std::chrono::steady_clock::now();
  node.ppid = readParentPid(pid);
  if (node.ppid < 0) return false;
  node.name = readProcessName(pid);
  node.path = readExecutablePath(pid);
  if (node.path.empty()) node.path = "[unknown]";
  node.cmdline = readCommandLine(pid);
  if (node.cmdline.empty()) node.cmdline = node.name.empty() ? "[unknown]" : node.name;
  auto ids = readProcessIds(pid);
  node.uid = ids.first;
  node.gid = ids.second;
  return true;
}
CPP_PART2

# Add the helper functions
cat >> "$TARGET_DIR/process_ancestry_cache.cpp" << 'CPP_PART3'
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
  if (!file.is_open()) return "";
  std::string cmdline;
  std::getline(file, cmdline, '\0');
  for (char& c : cmdline) {
    if (c == '\0') c = ' ';
  }
  return cmdline;
}

std::string ProcessAncestryManager::readProcessName(pid_t pid) {
  std::string comm_path = "/proc/" + std::to_string(pid) + "/comm";
  std::ifstream file(comm_path);
  if (!file.is_open()) return "";
  std::string name;
  std::getline(file, name);
  return name;
}

pid_t ProcessAncestryManager::readParentPid(pid_t pid) {
  std::string stat_path = "/proc/" + std::to_string(pid) + "/stat";
  std::ifstream file(stat_path);
  if (!file.is_open()) return -1;
  std::string line;
  std::getline(file, line);
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
  if (!file.is_open()) return {0, 0};
  uid_t uid = 0;
  gid_t gid = 0;
  std::string line;
  while (std::getline(file, line)) {
    if (line.find("Uid:") == 0) {
      std::istringstream iss(line);
      std::string label, real_uid;
      iss >> label >> real_uid;
      try { uid = std::stoul(real_uid); } catch (const std::exception&) { uid = 0; }
    } else if (line.find("Gid:") == 0) {
      std::istringstream iss(line);
      std::string label, real_gid;
      iss >> label >> real_gid;
      try { gid = std::stoul(real_gid); } catch (const std::exception&) { gid = 0; }
    }
  }
  return {uid, gid};
}

void ProcessAncestryManager::clearCache() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (cache_) cache_->clear();
}

size_t ProcessAncestryManager::getCacheSize() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return cache_ ? cache_->size() : 0;
}

} // namespace tables
} // namespace osquery
CPP_PART3

echo "✅ Created process_ancestry_cache.cpp"

echo ""
echo "📝 Updating process_events.h..."

# Add include to process_events.h if not already there
if [ -f "$TARGET_DIR/process_events.h" ]; then
    if ! grep -q "process_ancestry_cache.h" "$TARGET_DIR/process_events.h"; then
        cp "$TARGET_DIR/process_events.h" "$TARGET_DIR/process_events.h.backup"
        sed -i '/auditeventpublisher.h/a #include <osquery/tables/events/linux/process_ancestry_cache.h>' "$TARGET_DIR/process_events.h"
        echo "✅ Added ancestry include to process_events.h"
    else
        echo "✅ Ancestry include already in process_events.h"
    fi
fi

echo ""
echo "📝 Updating process_events.cpp..."

# Add ancestry integration to process_events.cpp if not already there
if [ -f "$TARGET_DIR/process_events.cpp" ]; then
    if ! grep -q "ProcessAncestryManager" "$TARGET_DIR/process_events.cpp"; then
        cp "$TARGET_DIR/process_events.cpp" "$TARGET_DIR/process_events.cpp.backup"
        # Use a simple approach to add the ancestry code
        sed -i '/row\["pid"\] = std::to_string(process_id);/a\\n  // Get process ancestry\n  try {\n    auto& ancestry_manager = ProcessAncestryManager::getInstance();\n    row["ancestry"] = ancestry_manager.getProcessAncestry(process_id);\n  } catch (const std::exception& e) {\n    row["ancestry"] = "[]";\n  }' "$TARGET_DIR/process_events.cpp"
        echo "✅ Added ancestry integration to process_events.cpp"
    else
        echo "✅ Ancestry integration already in process_events.cpp"
    fi
fi

echo ""
echo "🎯 Files created successfully!"
echo ""
echo "🔨 Testing build..."
cd build
make osquery_tables_events_eventstable -j1

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "✅ Process ancestry implemented and compiled!"
    make -j1
else
    echo ""
    echo "❌ Build failed. Check errors above."
fi
