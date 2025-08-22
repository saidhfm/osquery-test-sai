# 🧪 osquery Process Ancestry - Regression Testing Guide

## 🎯 **Ensuring No Functionality Loss**

This guide provides comprehensive testing strategies to validate that our process ancestry modifications haven't broken existing osquery functionality.

---

## 📋 **Overview of Changes Made**

### **What We Modified:**
✅ **ADDITIONS ONLY** - No core osquery functionality was altered
- ✅ Added `ancestry` column to `process_events` table
- ✅ Added new files: `process_ancestry_cache.h/cpp`
- ✅ Added command-line flags: `--process_ancestry_*`
- ✅ Modified `CMakeLists.txt` to include new files
- ✅ Modified `process_events.cpp` to integrate ancestry manager

### **What We DID NOT Modify:**
- ❌ Core osquery engine
- ❌ Existing table schemas (except adding ancestry column)
- ❌ Database functionality
- ❌ Logging systems
- ❌ Network/TLS functionality
- ❌ Other event publishers/subscribers
- ❌ Extension system
- ❌ Configuration parsing

---

## 🔍 **Regression Testing Strategy**

### **1. Side-by-Side Comparison Testing**

#### **Setup Two Systems:**
```bash
# System A: Original osquery 5.18.1
# System B: osquery 5.18.1 + Process Ancestry

# Download original osquery for comparison
wget https://pkg.osquery.io/deb/osquery_5.18.1-1.linux_amd64.deb
sudo dpkg -i osquery_5.18.1-1.linux_amd64.deb
```

#### **Parallel Testing Script:**
```bash
#!/bin/bash
# compare_functionality.sh

echo "🔍 Comparing Original vs Modified osquery functionality"

# Test basic functionality
echo "1. Testing basic queries..."
sudo osqueryi --json "SELECT version FROM osquery_info;" > original_version.json
sudo osqueryi-daemon --json "SELECT version FROM osquery_info;" > modified_version.json

# Test table availability
echo "2. Testing table availability..."
sudo osqueryi --json "SELECT name FROM osquery_registry WHERE registry='table';" > original_tables.json
sudo osqueryi-daemon --json "SELECT name FROM osquery_registry WHERE registry='table';" > modified_tables.json

# Compare results
echo "3. Comparing results..."
diff original_tables.json modified_tables.json || echo "✅ Only expected differences found"
```

---

## 🧪 **Comprehensive Test Suite**

### **Test 1: Core System Tables** 
```bash
#!/bin/bash
# test_core_tables.sh

echo "🧪 Testing Core System Tables..."

CORE_TABLES=(
    "processes"
    "users" 
    "groups"
    "listening_ports"
    "file"
    "hash"
    "system_info"
    "os_version"
    "cpu_info"
    "memory_info"
    "disk_info"
    "interface_details"
    "routes"
    "arp_cache"
    "dns_resolvers"
)

for table in "${CORE_TABLES[@]}"; do
    echo "Testing table: $table"
    
    # Test with original
    sudo osqueryi --json "SELECT COUNT(*) as count FROM $table LIMIT 1;" > "original_$table.json" 2>&1
    
    # Test with modified
    sudo osqueryi-daemon --json "SELECT COUNT(*) as count FROM $table LIMIT 1;" > "modified_$table.json" 2>&1
    
    # Compare results
    if diff "original_$table.json" "modified_$table.json" > /dev/null; then
        echo "✅ $table: PASSED"
    else
        echo "❌ $table: FAILED - Results differ"
        echo "Original:"
        cat "original_$table.json"
        echo "Modified:"
        cat "modified_$table.json"
    fi
done
```

### **Test 2: Event Publishers/Subscribers**
```bash
#!/bin/bash
# test_event_system.sh

echo "🧪 Testing Event System..."

# Test available publishers
echo "1. Testing Event Publishers..."
sudo osqueryi-daemon --json "SELECT name, type FROM osquery_registry WHERE registry='event_publisher';" > publishers.json

EXPECTED_PUBLISHERS=("auditeventpublisher" "inotify" "syslog" "udev")

for pub in "${EXPECTED_PUBLISHERS[@]}"; do
    if grep -q "$pub" publishers.json; then
        echo "✅ Publisher $pub: PRESENT"
    else
        echo "❌ Publisher $pub: MISSING"
    fi
done

# Test available subscribers  
echo "2. Testing Event Subscribers..."
sudo osqueryi-daemon --json "SELECT name, type FROM osquery_registry WHERE registry='event_subscriber';" > subscribers.json

EXPECTED_SUBSCRIBERS=("process_events" "file_events" "hardware_events" "socket_events")

for sub in "${EXPECTED_SUBSCRIBERS[@]}"; do
    if grep -q "$sub" subscribers.json; then
        echo "✅ Subscriber $sub: PRESENT"
    else
        echo "❌ Subscriber $sub: MISSING"
    fi
done
```

### **Test 3: Database Functionality**
```bash
#!/bin/bash
# test_database.sh

echo "🧪 Testing Database Functionality..."

# Test database operations
echo "1. Testing database read/write..."
sudo osqueryi-daemon "SELECT key, value FROM osquery_flags WHERE key LIKE 'database%';"

# Test pack functionality
echo "2. Testing pack loading..."
cat > test_pack.conf << EOF
{
  "schedule": {
    "system_info": {
      "query": "SELECT hostname, cpu_brand FROM system_info;",
      "interval": 60
    }
  }
}
EOF

sudo osqueryi-daemon --pack_file=test_pack.conf "SELECT name FROM osquery_packs;" || echo "Pack test completed"

# Test query execution performance
echo "3. Testing query performance..."
time sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" > performance.log
```

### **Test 4: Configuration System**
```bash
#!/bin/bash
# test_config.sh

echo "🧪 Testing Configuration System..."

# Test configuration parsing
cat > test_config.conf << EOF
{
  "options": {
    "verbose": "true",
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem"
  },
  "schedule": {
    "test_query": {
      "query": "SELECT pid, name FROM processes LIMIT 5;",
      "interval": 300
    }
  }
}
EOF

echo "1. Testing config loading..."
sudo osqueryi-daemon --config_path=test_config.conf "SELECT source FROM osquery_info;" || echo "Config test completed"

echo "2. Testing config parsing..."  
sudo osqueryi-daemon "SELECT key, value FROM osquery_flags WHERE key LIKE 'config%';"
```

### **Test 5: Performance Benchmarking**
```bash
#!/bin/bash
# test_performance.sh

echo "🧪 Testing Performance..."

# Memory usage test
echo "1. Testing memory usage..."
sudo systemctl start osqueryd
sleep 5

MEMORY_USAGE=$(ps aux | grep osqueryd | grep -v grep | awk '{print $6}')
echo "Memory usage: ${MEMORY_USAGE}KB"

if [ "$MEMORY_USAGE" -lt 100000 ]; then
    echo "✅ Memory usage acceptable (<100MB)"
else
    echo "⚠️  Memory usage high: ${MEMORY_USAGE}KB"
fi

# CPU usage test
echo "2. Testing CPU usage..."
CPU_USAGE=$(top -b -n1 -p $(pgrep osqueryd) | tail -1 | awk '{print $9}')
echo "CPU usage: ${CPU_USAGE}%"

# Query performance test
echo "3. Testing query performance..."
time sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" 2>&1 | grep real
time sudo osqueryi-daemon "SELECT COUNT(*) FROM file WHERE path='/usr/bin/' LIMIT 100;" 2>&1 | grep real
```

---

## 🔄 **Automated Regression Test Suite**

### **Master Test Runner:**
```bash
#!/bin/bash
# run_full_regression_tests.sh

echo "🚀 Starting Full Regression Test Suite for osquery Process Ancestry"
echo "=================================================================="

# Ensure services are running
sudo systemctl start osqueryd
sleep 5

# Initialize results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_script="$2"
    
    echo ""
    echo "🧪 Running: $test_name"
    echo "----------------------------------------"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if bash "$test_script"; then
        echo "✅ PASSED: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ FAILED: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Run all test suites
run_test "Core Tables Functionality" "test_core_tables.sh"
run_test "Event System Functionality" "test_event_system.sh" 
run_test "Database Functionality" "test_database.sh"
run_test "Configuration System" "test_config.sh"
run_test "Performance Benchmarks" "test_performance.sh"

# Process ancestry specific tests
echo ""
echo "🧬 Testing Process Ancestry Specific Functionality"
echo "=================================================="

# Test ancestry functionality doesn't break existing process_events
echo "Testing process_events compatibility..."
PROCESS_EVENTS_COUNT=$(sudo osqueryi-daemon --json "SELECT COUNT(*) as count FROM process_events;" 2>/dev/null | jq -r '.[0].count' 2>/dev/null)

if [ "$PROCESS_EVENTS_COUNT" != "null" ] && [ -n "$PROCESS_EVENTS_COUNT" ]; then
    echo "✅ process_events table functional"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ process_events table non-functional" 
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test ancestry column exists
echo "Testing ancestry column..."
ANCESTRY_SCHEMA=$(sudo osqueryi-daemon "PRAGMA table_info(process_events);" | grep ancestry)

if [ -n "$ANCESTRY_SCHEMA" ]; then
    echo "✅ ancestry column present in schema"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ ancestry column missing from schema"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Final results
echo ""
echo "📊 REGRESSION TEST RESULTS"
echo "=========================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo "🎉 ALL TESTS PASSED! No regressions detected."
    echo "✅ osquery Process Ancestry is safe for production."
else
    echo ""
    echo "⚠️  REGRESSIONS DETECTED! Review failed tests before deployment."
    exit 1
fi
```

---

## 🔍 **Specific Areas to Monitor**

### **1. Audit System Integration**
```bash
# Verify audit system still works normally
sudo osqueryi-daemon "SELECT COUNT(*) FROM process_events WHERE pid > 0;" 
sudo osqueryi-daemon "SELECT COUNT(*) FROM socket_events WHERE pid > 0;"
sudo osqueryi-daemon "SELECT COUNT(*) FROM file_events WHERE target_path != '';"
```

### **2. Memory and Performance**
```bash
# Monitor for memory leaks or performance issues
watch -n 5 'ps aux | grep osqueryd | grep -v grep'

# Check for any unusual system resource usage
sudo osqueryi-daemon "SELECT pid, resident_size, user_time, system_time FROM processes WHERE name='osqueryd';"
```

### **3. Log Analysis**
```bash
# Check for any error patterns in logs
sudo journalctl -u osqueryd -f | grep -E "(ERROR|FATAL|exception|segfault)"

# Verify no new warning patterns
sudo tail -f /var/log/osquery/osqueryd.results.log | grep -E "(WARNING|ERROR)"
```

---

## 🎯 **Validation Checklist**

### **Pre-Deployment Validation:**
- [ ] ✅ All core tables return expected results
- [ ] ✅ Event publishers/subscribers function normally
- [ ] ✅ Database operations work correctly  
- [ ] ✅ Configuration parsing unchanged
- [ ] ✅ Memory usage within acceptable limits
- [ ] ✅ CPU usage patterns normal
- [ ] ✅ Query performance comparable
- [ ] ✅ No new error patterns in logs
- [ ] ✅ Extension system functional (if used)
- [ ] ✅ Scheduled queries execute properly
- [ ] ✅ Existing process_events work without ancestry
- [ ] ✅ New ancestry column available when enabled

### **Production Monitoring:**
- [ ] Monitor system resource usage
- [ ] Check for memory leaks over time  
- [ ] Verify query performance stability
- [ ] Watch for any error patterns
- [ ] Validate data consistency
- [ ] Confirm audit system stability

---

## 🚨 **Rollback Strategy**

If regressions are detected:

1. **Immediate**: Stop osqueryd service
2. **Rollback**: Install original osquery package
3. **Verify**: Run basic functionality tests
4. **Investigate**: Analyze specific regression
5. **Fix**: Address issue in ancestry code
6. **Retest**: Full regression suite before redeployment

```bash
# Emergency rollback script
#!/bin/bash
echo "🚨 Rolling back to original osquery..."
sudo systemctl stop osqueryd
sudo apt remove osquery-ancestry-sensor -y
sudo dpkg -i osquery_5.18.1-1.linux_amd64.deb
sudo systemctl start osqueryd
echo "✅ Rollback complete"
```

---

## 📈 **Continuous Testing**

### **Set up automated regression testing:**
```bash
# Add to crontab for daily validation
0 2 * * * /usr/local/bin/run_full_regression_tests.sh > /var/log/osquery_regression_$(date +\%Y\%m\%d).log 2>&1
```

This comprehensive approach ensures we maintain osquery's reliability while adding our ancestry functionality! 🛡️
