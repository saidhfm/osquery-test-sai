/**
 * Copyright (c) 2014-present, The osquery authors
 *
 * This source code is licensed as defined by the LICENSE file found in the
 * root directory of this source tree.
 *
 * SPDX-License-Identifier: (Apache-2.0 OR GPL-2.0-only)
 */

#include <osquery/tables/events/linux/process_ancestry_cache.h>

#include <chrono>
#include <fstream>
#include <sstream>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

#include <osquery/filesystem/filesystem.h>
#include <osquery/logger/logger.h>
#include <osquery/utils/conversions/split.h>

namespace osquery {

// Flags for controlling ancestry functionality
FLAG(uint64, 
     process_ancestry_cache_size, 
     1000, 
     "Maximum number of process ancestry entries to cache");

FLAG(uint64, 
     process_ancestry_max_depth, 
     32, 
     "Maximum depth to traverse in process ancestry (0 = unlimited)");

FLAG(uint64, 
     process_ancestry_cache_ttl, 
     300, 
     "Time to live for process ancestry cache entries in seconds");

std::string ProcessAncestryNode::toJson() const {
  std::ostringstream json;
  json << "{";
  json << "\"exe_name\":\"" << name << "\",";
  json << "\"pid\":" << pid << ",";
  json << "\"ppid\":" << ppid;
  
  if (pproc_time_hr > 0) {
    json << ",\"pproc_time_hr\":" << pproc_time_hr;
  }
  json << ",\"path\":\"" << path << "\"";
  json << ",\"cmdline\":\"" << cmdline << "\"";
  
  if (proc_time > 0) {
    json << ",\"proc_time\":" << proc_time;
  }
  if (proc_time_hr > 0) {
    json << ",\"proc_time_hr\":" << proc_time_hr;
  }
  
  json << "}";
  return json.str();
}

std::string ProcessAncestryCache::toJson() const {
  std::ostringstream json;
  json << "[";
  for (size_t i = 0; i < ancestry.size(); ++i) {
    if (i > 0) {
      json << ",";
    }
    json << ancestry[i].toJson();
  }
  json << "]";
  return json.str();
}

ProcessAncestryLRUCache::ProcessAncestryLRUCache(size_t max_size, 
                                               std::chrono::seconds ttl)
    : max_size_(max_size), ttl_(ttl), hits_(0), misses_(0), expired_entries_(0) {
  // Create dummy head and tail nodes
  head_ = std::make_shared<CacheNode>(-1);
  tail_ = std::make_shared<CacheNode>(-1);
  head_->next = tail_;
  tail_->prev = head_;
}

std::string ProcessAncestryLRUCache::getAncestry(pid_t pid) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  auto it = cache_.find(pid);
  if (it == cache_.end()) {
    ++misses_;
    return "";
  }
  
  auto node = it->second;
  
  // Check if entry is expired
  if (node->value.isExpired(ttl_)) {
    removeNode(node);
    cache_.erase(it);
    ++expired_entries_;
    ++misses_;
    return "";
  }
  
  // Move to head (mark as recently used)
  moveToHead(node);
  node->value.last_access = std::chrono::steady_clock::now();
  ++hits_;
  
  return node->value.toJson();
}

void ProcessAncestryLRUCache::putAncestry(pid_t pid, 
                                        const std::vector<ProcessAncestryNode>& ancestry) {
  std::lock_guard<std::mutex> lock(mutex_);
  
  auto it = cache_.find(pid);
  if (it != cache_.end()) {
    // Update existing entry
    auto node = it->second;
    node->value.ancestry = ancestry;
    node->value.creation_time = std::chrono::steady_clock::now();
    node->value.last_access = std::chrono::steady_clock::now();
    moveToHead(node);
    return;
  }
  
  // Create new entry
  auto node = std::make_shared<CacheNode>(pid);
  node->value.ancestry = ancestry;
  
  if (cache_.size() >= max_size_) {
    // Remove least recently used
    auto tail_node = removeTail();
    if (tail_node) {
      cache_.erase(tail_node->key);
    }
  }
  
  addToHead(node);
  cache_[pid] = node;
}

void ProcessAncestryLRUCache::clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  cache_.clear();
  head_->next = tail_;
  tail_->prev = head_;
  hits_ = 0;
  misses_ = 0;
  expired_entries_ = 0;
}

ProcessAncestryLRUCache::CacheStats ProcessAncestryLRUCache::getStats() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return {hits_, misses_, cache_.size(), expired_entries_};
}

void ProcessAncestryLRUCache::moveToHead(CacheNodePtr node) {
  removeNode(node);
  addToHead(node);
}

void ProcessAncestryLRUCache::removeNode(CacheNodePtr node) {
  if (node->prev) {
    node->prev->next = node->next;
  }
  if (node->next) {
    node->next->prev = node->prev;
  }
}

ProcessAncestryLRUCache::CacheNodePtr ProcessAncestryLRUCache::removeTail() {
  auto last_node = tail_->prev;
  if (last_node == head_) {
    return nullptr;
  }
  removeNode(last_node);
  return last_node;
}

void ProcessAncestryLRUCache::addToHead(CacheNodePtr node) {
  node->prev = head_;
  node->next = head_->next;
  head_->next->prev = node;
  head_->next = node;
}

void ProcessAncestryLRUCache::evictExpired() {
  std::lock_guard<std::mutex> lock(mutex_);
  
  std::vector<pid_t> expired_keys;
  for (const auto& pair : cache_) {
    if (pair.second->value.isExpired(ttl_)) {
      expired_keys.push_back(pair.first);
    }
  }
  
  for (pid_t key : expired_keys) {
    auto it = cache_.find(key);
    if (it != cache_.end()) {
      removeNode(it->second);
      cache_.erase(it);
      ++expired_entries_;
    }
  }
}

ProcessAncestryManager& ProcessAncestryManager::getInstance() {
  static ProcessAncestryManager instance;
  return instance;
}

ProcessAncestryManager::ProcessAncestryManager() {
  cache_ = std::make_unique<ProcessAncestryLRUCache>(
      FLAGS_process_ancestry_cache_size,
      std::chrono::seconds(FLAGS_process_ancestry_cache_ttl));
}

std::string ProcessAncestryManager::getProcessAncestry(pid_t pid) {
  // Performance optimization: if cache size is 0, disable ancestry collection
  if (FLAGS_process_ancestry_cache_size == 0) {
    return "[]";
  }
  
  // Try cache first
  std::string cached_result = cache_->getAncestry(pid);
  if (!cached_result.empty()) {
    return cached_result;
  }
  
  // Build ancestry chain
  auto ancestry_chain = buildAncestryChain(pid);
  if (ancestry_chain.empty()) {
    return "[]"; // Return empty JSON array if no ancestry found
  }
  
  // Cache the result
  cache_->putAncestry(pid, ancestry_chain);
  
  // Return JSON representation
  ProcessAncestryCache cache_entry;
  cache_entry.ancestry = ancestry_chain;
  return cache_entry.toJson();
}

void ProcessAncestryManager::clearCache() {
  cache_->clear();
}

ProcessAncestryLRUCache::CacheStats ProcessAncestryManager::getCacheStats() const {
  return cache_->getStats();
}

std::vector<ProcessAncestryNode> ProcessAncestryManager::buildAncestryChain(pid_t pid) {
  std::vector<ProcessAncestryNode> ancestry;
  std::set<pid_t> visited; // Prevent infinite loops
  
  pid_t current_pid = pid;
  size_t depth = 0;
  size_t max_depth = FLAGS_process_ancestry_max_depth;
  
  while (current_pid > 1 && visited.find(current_pid) == visited.end()) {
    // Check depth limit (0 means unlimited)
    if (max_depth > 0 && depth >= max_depth) {
      VLOG(1) << "Reached maximum ancestry depth " << max_depth << " for PID " << pid;
      break;
    }
    
    visited.insert(current_pid);
    
    ProcessAncestryNode node;
    if (!readProcessInfo(current_pid, node)) {
      // Process likely exited - normal in high-frequency scenarios
      break;
    }
    
    ancestry.push_back(node);
    
    // Move to parent
    if (node.ppid == current_pid || node.ppid <= 0) {
      // Avoid infinite loops and invalid parent PIDs
      break;
    }
    
    current_pid = node.ppid;
    ++depth;
  }
  
  return ancestry;
}

bool ProcessAncestryManager::readProcessInfo(pid_t pid, ProcessAncestryNode& node) {
  // Read /proc/pid/stat
  std::string stat_path = "/proc/" + std::to_string(pid) + "/stat";
  std::string stat_content;
  
  if (!osquery::readFile(stat_path, stat_content).ok()) {
    return false;
  }
  
  if (!parseStatFile(stat_content, node)) {
    return false;
  }
  
  node.pid = pid;
  
  // Read executable path
  node.path = readExecutablePath(pid);
  
  // Read command line
  node.cmdline = readCommandLine(pid);
  
  // Calculate timing information
  calculateProcessTiming(node);
  
  // Reduced logging for performance - only in debug mode
  VLOG(2) << "ProcessAncestryNode for PID " << pid << " - ppid: " << node.ppid;
  
  return true;
}

bool ProcessAncestryManager::parseStatFile(const std::string& stat_content, 
                                          ProcessAncestryNode& node) {
  // Parse /proc/pid/stat format
  // Fields: pid comm state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt utime stime cutime cstime priority nice num_threads itrealvalue starttime vsize rss rsslim startcode endcode startstack kstkesp kstkeip signal blocked sigignore sigcatch wchan nswap cnswap exit_signal processor rt_priority policy delayacct_blkio_ticks guest_time cguest_time start_data end_data start_brk arg_start arg_end env_start env_end exit_code
  
  size_t comm_start = stat_content.find('(');
  size_t comm_end = stat_content.rfind(')');
  
  if (comm_start == std::string::npos || comm_end == std::string::npos || comm_end <= comm_start) {
    return false;
  }
  
  // Extract comm (process name)
  node.name = stat_content.substr(comm_start + 1, comm_end - comm_start - 1);
  
  // Parse the remaining fields after comm
  std::string remaining = stat_content.substr(comm_end + 1);
  auto fields = osquery::split(remaining, " ");
  
  if (fields.size() < 22) {  // Need at least 22 fields to get starttime
    return false;
  }
  
  try {
    // Field 1 (index 0): state (skip)
    // Field 2 (index 1): ppid
    node.ppid = std::stoi(fields[1]);
    
    // Field 3 (index 2): pgrp (skip)
    // Field 4 (index 3): session (skip)
    // Field 5 (index 4): tty_nr (skip)
    // Field 6 (index 5): tpgid (skip)
    // Field 7 (index 6): flags (skip)
    // Field 8 (index 7): minflt (skip)
    // Field 9 (index 8): cminflt (skip)
    // Field 10 (index 9): majflt (skip)
    // ...skip to field 22 (index 21): starttime
    // Store starttime in clock ticks (will convert later)
    node.starttime_ticks = std::stoull(fields[21]);
    
    // We'll get uid/gid from /proc/pid/status if needed
    node.uid = 0;
    node.gid = 0;
    
    // Try to read uid/gid from /proc/pid/status
    std::string status_path = "/proc/" + std::to_string(node.pid) + "/status";
    std::string status_content;
    if (osquery::readFile(status_path, status_content).ok()) {
      std::istringstream iss(status_content);
      std::string line;
      while (std::getline(iss, line)) {
        if (line.find("Uid:") == 0) {
          auto uid_fields = osquery::split(line, "\t");
          if (uid_fields.size() >= 2) {
            node.uid = std::stoi(uid_fields[1]);
          }
        } else if (line.find("Gid:") == 0) {
          auto gid_fields = osquery::split(line, "\t");
          if (gid_fields.size() >= 2) {
            node.gid = std::stoi(gid_fields[1]);
          }
        }
      }
    }
    
  } catch (const std::exception& e) {
    VLOG(1) << "Error parsing stat file: " << e.what();
    return false;
  }
  
  return true;
}

std::string ProcessAncestryManager::readCommandLine(pid_t pid) {
  std::string cmdline_path = "/proc/" + std::to_string(pid) + "/cmdline";
  std::string cmdline_content;
  
  if (!osquery::readFile(cmdline_path, cmdline_content).ok()) {
    return "<process_exited>";
  }
  
  // Replace null bytes with spaces
  std::string result;
  for (char c : cmdline_content) {
    if (c == '\0') {
      if (!result.empty() && result.back() != ' ') {
        result += ' ';
      }
    } else {
      result += c;
    }
  }
  
  // Trim trailing space
  if (!result.empty() && result.back() == ' ') {
    result.pop_back();
  }
  
  return result;
}

std::string ProcessAncestryManager::readExecutablePath(pid_t pid) {
  std::string exe_path = "/proc/" + std::to_string(pid) + "/exe";
  
  // Use consistent readlink approach - same error handling as readCommandLine
  char buffer[PATH_MAX];
  ssize_t len = readlink(exe_path.c_str(), buffer, sizeof(buffer) - 1);
  
  if (len == -1) {
    // Process likely exited - normal in high-frequency scenarios
    return "<process_exited>";
  }
  
  buffer[len] = '\0';  // Null terminate
  return std::string(buffer);
}

void ProcessAncestryManager::calculateProcessTiming(ProcessAncestryNode& node) {
  if (node.starttime_ticks == 0) {
    return;
  }
  
  // Get system boot time from /proc/stat
  uint64_t boot_time_sec = 0;
  std::string stat_content;
  if (osquery::readFile("/proc/stat", stat_content).ok()) {
    std::istringstream iss(stat_content);
    std::string line;
    while (std::getline(iss, line)) {
      if (line.find("btime ") == 0) {
        auto parts = osquery::split(line, " ");
        if (parts.size() >= 2) {
          boot_time_sec = std::stoull(parts[1]);
          break;
        }
      }
    }
  }
  
  // Get clock ticks per second
  long clock_ticks_per_sec = sysconf(_SC_CLK_TCK);
  if (clock_ticks_per_sec <= 0) {
    clock_ticks_per_sec = 100; // Default fallback
  }
  
  // Calculate process start time
  uint64_t process_start_sec = boot_time_sec + (node.starttime_ticks / clock_ticks_per_sec);
  
  // Calculate high-resolution timestamp (nanoseconds since epoch)
  uint64_t process_start_ns = process_start_sec * 1000000000ULL;
  
  // Set the timing fields
  node.proc_time = process_start_sec;
  node.proc_time_hr = process_start_ns;
  
  // For now, set pproc_time_hr to 0 - we'd need to look up parent process timing
  // This could be enhanced later by caching parent process times
  node.pproc_time_hr = 0;
}

} // namespace osquery