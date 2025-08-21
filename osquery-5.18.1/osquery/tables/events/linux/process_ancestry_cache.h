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
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include <osquery/core/core.h>
#include <osquery/core/flags.h>
#include <osquery/logger/logger.h>

namespace osquery {

/// Flags for controlling ancestry functionality
DECLARE_uint64(process_ancestry_cache_size);
DECLARE_uint64(process_ancestry_max_depth);
DECLARE_uint64(process_ancestry_cache_ttl);

/**
 * @brief Structure representing a single process in the ancestry chain
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
  
  // Enhanced fields for richer ancestry data
  uint64_t proc_time;        // Process start time (seconds since epoch)
  uint64_t proc_time_hr;     // Process start time (high resolution)
  uint64_t pproc_time_hr;    // Parent process start time (high resolution)
  uint64_t starttime_ticks;  // Process start time in clock ticks (internal use)

  ProcessAncestryNode() : pid(0), ppid(0), path(""), cmdline(""), 
                         name(""), uid(0), gid(0), 
                         creation_time(std::chrono::steady_clock::now()),
                         proc_time(0), proc_time_hr(0), pproc_time_hr(0), starttime_ticks(0) {}
  ProcessAncestryNode(pid_t p, pid_t pp, const std::string& pt, 
                     const std::string& cmd, const std::string& nm,
                     uid_t u, gid_t g)
      : pid(p), ppid(pp), path(pt), cmdline(cmd), name(nm), uid(u), gid(g),
        creation_time(std::chrono::steady_clock::now()), 
        proc_time(0), proc_time_hr(0), pproc_time_hr(0), starttime_ticks(0) {}

  /// Convert to JSON string
  std::string toJson() const;
};

/**
 * @brief Cache entry for process ancestry information
 */
struct ProcessAncestryCache {
  std::vector<ProcessAncestryNode> ancestry;
  std::chrono::steady_clock::time_point last_access;
  std::chrono::steady_clock::time_point creation_time;
  
  ProcessAncestryCache() : last_access(std::chrono::steady_clock::now()),
                          creation_time(std::chrono::steady_clock::now()) {}
  
  /// Check if cache entry is expired
  bool isExpired(std::chrono::seconds ttl) const {
    auto now = std::chrono::steady_clock::now();
    return (now - creation_time) > ttl;
  }
  
  /// Convert ancestry to JSON string
  std::string toJson() const;
};

/**
 * @brief LRU Cache for process ancestry information
 * 
 * This class implements a thread-safe LRU cache for storing process ancestry
 * information to improve performance of repeated lookups.
 */
class ProcessAncestryLRUCache {
 public:
  explicit ProcessAncestryLRUCache(size_t max_size = 1000, 
                                  std::chrono::seconds ttl = std::chrono::seconds(300));
  
  /// Get ancestry for a process (returns empty string if not found or expired)
  std::string getAncestry(pid_t pid);
  
  /// Store ancestry for a process
  void putAncestry(pid_t pid, const std::vector<ProcessAncestryNode>& ancestry);
  
  /// Clear the cache
  void clear();
  
  /// Get cache statistics
  struct CacheStats {
    size_t hits;
    size_t misses;
    size_t size;
    size_t expired_entries;
  };
  
  CacheStats getStats() const;

 private:
  struct CacheNode {
    pid_t key;
    ProcessAncestryCache value;
    std::shared_ptr<CacheNode> prev;
    std::shared_ptr<CacheNode> next;
    
    CacheNode(pid_t k) : key(k) {}
  };
  
  using CacheNodePtr = std::shared_ptr<CacheNode>;
  
  void moveToHead(CacheNodePtr node);
  void removeNode(CacheNodePtr node);
  CacheNodePtr removeTail();
  void addToHead(CacheNodePtr node);
  void evictExpired();
  
  const size_t max_size_;
  const std::chrono::seconds ttl_;
  
  mutable std::mutex mutex_;
  std::unordered_map<pid_t, CacheNodePtr> cache_;
  
  CacheNodePtr head_;
  CacheNodePtr tail_;
  
  // Statistics
  mutable size_t hits_;
  mutable size_t misses_;
  mutable size_t expired_entries_;
};

/**
 * @brief Process Ancestry Manager
 * 
 * This class manages the process ancestry functionality including
 * cache management and ancestry traversal logic.
 */
class ProcessAncestryManager {
 public:
  static ProcessAncestryManager& getInstance();
  
  /// Get process ancestry as JSON string
  std::string getProcessAncestry(pid_t pid);
  
  /// Clear the cache
  void clearCache();
  
  /// Get cache statistics
  ProcessAncestryLRUCache::CacheStats getCacheStats() const;

 private:
  ProcessAncestryManager();
  ~ProcessAncestryManager() = default;
  
  // Non-copyable and non-movable
  ProcessAncestryManager(const ProcessAncestryManager&) = delete;
  ProcessAncestryManager& operator=(const ProcessAncestryManager&) = delete;
  ProcessAncestryManager(ProcessAncestryManager&&) = delete;
  ProcessAncestryManager& operator=(ProcessAncestryManager&&) = delete;
  
  /// Build ancestry chain by traversing /proc filesystem
  std::vector<ProcessAncestryNode> buildAncestryChain(pid_t pid);
  
  /// Read process information from /proc
  bool readProcessInfo(pid_t pid, ProcessAncestryNode& node);
  
  /// Parse /proc/pid/stat file
  bool parseStatFile(const std::string& stat_content, ProcessAncestryNode& node);
  
  /// Read command line from /proc/pid/cmdline
  std::string readCommandLine(pid_t pid);
  
  /// Read executable path from /proc/pid/exe
  std::string readExecutablePath(pid_t pid);
  
  /// Calculate process timing information
  void calculateProcessTiming(ProcessAncestryNode& node);
  
  std::unique_ptr<ProcessAncestryLRUCache> cache_;
};

} // namespace osquery
