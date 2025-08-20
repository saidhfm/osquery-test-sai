# Production Scaling and Testing Guide for Process Ancestry Feature

## Overview

This guide provides comprehensive instructions for testing and deploying the process ancestry feature in production environments, focusing on scalability, reliability, and performance optimization.

## Pre-Production Validation

### Environment Requirements

#### Minimum System Specifications
- **CPU**: 4+ cores (8+ recommended for high-load environments)
- **Memory**: 8GB RAM minimum (16GB+ for production)
- **Storage**: SSD with 100GB+ free space
- **Network**: Stable connectivity for log shipping
- **OS**: RHEL 8+, Ubuntu 20.04+, or Amazon Linux 2

#### Infrastructure Prerequisites
```bash
# System limits configuration
echo '* soft nofile 65536' >> /etc/security/limits.conf
echo '* hard nofile 65536' >> /etc/security/limits.conf
echo 'fs.file-max = 1000000' >> /etc/sysctl.conf
sysctl -p

# Audit system configuration
echo 'max_log_file = 50' >> /etc/audit/auditd.conf
echo 'max_log_file_action = rotate' >> /etc/audit/auditd.conf
```

## Staging Environment Setup

### 1. Multi-Tier Testing Architecture

```bash
# Create testing infrastructure
# Tier 1: Low load (1-10 processes/sec)
# Tier 2: Medium load (10-100 processes/sec) 
# Tier 3: High load (100-1000 processes/sec)
# Tier 4: Stress test (1000+ processes/sec)

# Example staging configuration
cat > staging_config.conf << 'EOF'
{
  "options": {
    "audit_allow_process_events": true,
    "process_events_enable_ancestry": true,
    "process_events_max_ancestry_depth": 10,
    "audit_allow_fork_process_events": true,
    "logger_tls_period": 10,
    "database_path": "/opt/osquery/osquery.db",
    "logger_path": "/var/log/osquery/",
    "disable_watchdog": false,
    "watchdog_level": 0,
    "schedule_timeout": 60
  },
  "schedule": {
    "process_events_monitor": {
      "query": "SELECT * FROM process_events;",
      "interval": 60,
      "description": "Monitor process events with ancestry"
    }
  },
  "packs": {
    "incident-response": "/opt/osquery/packs/incident-response.conf"
  }
}
EOF
```

### 2. Baseline Performance Measurement

```bash
#!/bin/bash
# baseline_metrics.sh - Collect baseline performance metrics

# System metrics before osquery
echo "=== System Baseline (Before osquery) ==="
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1

echo "Memory Usage:"
free -m | awk 'NR==2{printf "%.2f%%\n", $3*100/$2}'

echo "Disk I/O:"
iostat -x 1 3 | tail -n +4

echo "Network:"
sar -n DEV 1 3 | grep Average

# Start osquery with ancestry feature
sudo osqueryd --config_path=staging_config.conf --daemonize

# Wait for stabilization
sleep 60

echo "=== System Performance (After osquery with ancestry) ==="
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1

echo "Memory Usage:"
free -m | awk 'NR==2{printf "%.2f%%\n", $3*100/$2}'

echo "osquery Memory:"
ps aux | grep osqueryd | grep -v grep | awk '{print $6/1024 " MB"}'

echo "File Descriptors:"
sudo lsof -p $(pgrep osqueryd) | wc -l
```

### 3. Load Generation Framework

```bash
#!/bin/bash
# load_generator.sh - Generate realistic process load

generate_web_server_load() {
    echo "Generating web server process patterns..."
    for i in {1..20}; do
        (
            # Simulate nginx worker processes
            sleep $((RANDOM % 10 + 5)) &
            
            # Simulate PHP-FPM processes
            php -r "sleep($((RANDOM % 5 + 1)));" &
            
            # Simulate database connections
            mysql -e "SELECT SLEEP($((RANDOM % 3 + 1)));" 2>/dev/null &
        ) &
    done
}

generate_container_load() {
    echo "Generating containerized application patterns..."
    for i in {1..15}; do
        (
            # Simulate container runtime processes
            docker run --rm alpine:latest sh -c "sleep $((RANDOM % 8 + 2))" &
            
            # Simulate kubectl commands
            kubectl get pods --all-namespaces >/dev/null 2>&1 &
        ) &
    done
}

generate_build_system_load() {
    echo "Generating build system patterns..."
    for i in {1..30}; do
        (
            # Simulate compilation processes
            gcc -c -o /tmp/test_$i.o -x c /dev/null 2>/dev/null
            
            # Simulate make processes
            make -n -f /dev/null 2>/dev/null &
        ) &
    done
}

generate_system_admin_load() {
    echo "Generating system administration patterns..."
    for i in {1..25}; do
        (
            # Simulate monitoring commands
            ps aux >/dev/null &
            netstat -tuln >/dev/null &
            df -h >/dev/null &
            
            # Simulate log processing
            tail -n 100 /var/log/syslog >/dev/null &
        ) &
    done
}

# Execute load patterns
case "${1:-all}" in
    "web") generate_web_server_load ;;
    "container") generate_container_load ;;
    "build") generate_build_system_load ;;
    "admin") generate_system_admin_load ;;
    "all")
        generate_web_server_load
        generate_container_load  
        generate_build_system_load
        generate_system_admin_load
        ;;
esac

echo "Load generation started. Monitor with 'ps aux | wc -l'"
```

## Performance Testing

### 1. Comprehensive Performance Suite

```bash
#!/bin/bash
# performance_test_suite.sh

run_ancestry_performance_test() {
    local test_name="$1"
    local duration="$2"
    local load_type="$3"
    
    echo "Starting performance test: $test_name"
    echo "Duration: $duration seconds"
    echo "Load type: $load_type"
    
    # Start monitoring
    (
        while true; do
            echo "$(date): $(ps aux | grep osqueryd | grep -v grep | awk '{print "CPU:"$3"% MEM:"$4"% RSS:"$6"KB"}')"
            sleep 5
        done
    ) > "performance_${test_name}_$(date +%s).log" &
    MONITOR_PID=$!
    
    # Generate load
    ./load_generator.sh "$load_type" &
    LOAD_PID=$!
    
    # Run for specified duration
    sleep "$duration"
    
    # Stop load generation
    kill $LOAD_PID 2>/dev/null
    wait $LOAD_PID 2>/dev/null
    
    # Stop monitoring
    kill $MONITOR_PID 2>/dev/null
    
    # Collect metrics
    echo "Test completed: $test_name"
    osqueryi --json "SELECT COUNT(*) as events_generated FROM process_events WHERE time > (strftime('%s', 'now') - $duration);"
    
    # Wait for processes to clean up
    sleep 10
}

# Test Suite Execution
echo "=== osquery Process Ancestry Performance Test Suite ==="

# Test 1: Low Load
run_ancestry_performance_test "low_load" 300 "admin"

# Test 2: Medium Load  
run_ancestry_performance_test "medium_load" 300 "web"

# Test 3: High Load
run_ancestry_performance_test "high_load" 300 "all"

# Test 4: Sustained Load
run_ancestry_performance_test "sustained_load" 1800 "all"

echo "Performance test suite completed."
```

### 2. Memory Leak Detection

```bash
#!/bin/bash
# memory_leak_test.sh

echo "Starting memory leak detection test..."

# Get initial memory usage
INITIAL_MEM=$(ps aux | grep osqueryd | grep -v grep | awk '{print $6}')
echo "Initial memory usage: ${INITIAL_MEM}KB"

# Run continuous load for 4 hours
for hour in {1..4}; do
    echo "Hour $hour: Starting load generation..."
    
    # Generate high process activity
    for i in {1..100}; do
        (
            # Deep process hierarchy to test ancestry traversal
            bash -c 'bash -c "bash -c \"bash -c \\\"sleep 5\\\"\"" &'
            sleep 0.1
        ) &
    done
    
    # Wait for hour completion
    sleep 3600
    
    # Check memory usage
    CURRENT_MEM=$(ps aux | grep osqueryd | grep -v grep | awk '{print $6}')
    INCREASE=$((CURRENT_MEM - INITIAL_MEM))
    PERCENT_INCREASE=$(echo "scale=2; $INCREASE * 100 / $INITIAL_MEM" | bc)
    
    echo "Hour $hour memory usage: ${CURRENT_MEM}KB (increase: ${INCREASE}KB, ${PERCENT_INCREASE}%)"
    
    # Alert if memory increase is significant
    if [ $INCREASE -gt 100000 ]; then
        echo "WARNING: Significant memory increase detected!"
    fi
    
    # Clean up any remaining processes
    pkill -f "sleep 5" 2>/dev/null
done

echo "Memory leak test completed."
```

### 3. Stress Testing

```bash
#!/bin/bash
# stress_test.sh

echo "Starting stress test for process ancestry feature..."

# Configure system for stress testing
echo "Configuring system for high load..."
ulimit -n 65536
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# Test 1: Rapid Process Creation
echo "Test 1: Rapid process creation stress test"
for i in {1..1000}; do
    (sleep 0.01; exit) &
    if [ $((i % 100)) -eq 0 ]; then
        echo "Created $i processes..."
        sleep 1
    fi
done

# Test 2: Deep Process Hierarchy  
echo "Test 2: Deep process hierarchy stress test"
create_deep_hierarchy() {
    local depth=$1
    if [ $depth -gt 0 ]; then
        bash -c "$(declare -f create_deep_hierarchy); create_deep_hierarchy $((depth-1))" &
        sleep 0.1
    else
        sleep 10
    fi
}
create_deep_hierarchy 20

# Test 3: Concurrent Process Trees
echo "Test 3: Concurrent process trees stress test"
for tree in {1..50}; do
    (
        for level in {1..5}; do
            bash -c "sleep $((RANDOM % 5 + 1))" &
        done
        wait
    ) &
done

# Monitor during stress test
echo "Monitoring system during stress test..."
for i in {1..60}; do
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    MEM=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    PROCS=$(ps aux | wc -l)
    
    echo "Minute $i: Load: $LOAD, Memory: ${MEM}%, Processes: $PROCS"
    
    # Emergency brake if system becomes unresponsive
    if (( $(echo "$LOAD > 50" | bc -l) )); then
        echo "EMERGENCY: Load too high, stopping stress test"
        pkill -f "sleep" 2>/dev/null
        break
    fi
    
    sleep 60
done

echo "Stress test completed."
```

## Production Deployment Strategy

### 1. Phased Rollout Plan

```bash
# Phase 1: Canary Deployment (1-5% of fleet)
cat > phase1_config.conf << 'EOF'
{
  "options": {
    "audit_allow_process_events": true,
    "process_events_enable_ancestry": true,
    "process_events_max_ancestry_depth": 5,
    "audit_allow_fork_process_events": false,
    "logger_tls_period": 30
  }
}
EOF

# Phase 2: Limited Rollout (10-25% of fleet)  
cat > phase2_config.conf << 'EOF'
{
  "options": {
    "audit_allow_process_events": true,
    "process_events_enable_ancestry": true,
    "process_events_max_ancestry_depth": 8,
    "audit_allow_fork_process_events": true,
    "logger_tls_period": 20
  }
}
EOF

# Phase 3: Full Production (100% of fleet)
cat > phase3_config.conf << 'EOF'
{
  "options": {
    "audit_allow_process_events": true,
    "process_events_enable_ancestry": true,
    "process_events_max_ancestry_depth": 10,
    "audit_allow_fork_process_events": true,
    "logger_tls_period": 10
  }
}
EOF
```

### 2. Production Monitoring Setup

```bash
#!/bin/bash
# production_monitoring.sh

setup_monitoring() {
    echo "Setting up production monitoring for osquery ancestry feature..."
    
    # Create monitoring directory
    mkdir -p /opt/osquery/monitoring
    
    # CPU and Memory monitoring
    cat > /opt/osquery/monitoring/resource_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    pid=$(pgrep osqueryd)
    
    if [ -n "$pid" ]; then
        # Get resource usage
        cpu=$(ps -p $pid -o %cpu --no-headers | tr -d ' ')
        mem=$(ps -p $pid -o %mem --no-headers | tr -d ' ')
        rss=$(ps -p $pid -o rss --no-headers | tr -d ' ')
        
        # Get process event rate
        events=$(osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE time > (strftime('%s', 'now') - 60);" | jq -r '.[0].count')
        
        # Log metrics
        echo "$timestamp,CPU:$cpu,MEM:$mem,RSS:${rss}KB,EVENTS:$events" >> /var/log/osquery/resource_metrics.log
        
        # Alert on high resource usage
        if (( $(echo "$cpu > 50" | bc -l) )); then
            echo "$timestamp: HIGH CPU USAGE: $cpu%" >> /var/log/osquery/alerts.log
        fi
        
        if (( $(echo "$mem > 30" | bc -l) )); then
            echo "$timestamp: HIGH MEMORY USAGE: $mem%" >> /var/log/osquery/alerts.log
        fi
    fi
    
    sleep 60
done
EOF
    
    chmod +x /opt/osquery/monitoring/resource_monitor.sh
    
    # Log rotation for monitoring
    cat > /etc/logrotate.d/osquery_monitoring << 'EOF'
/var/log/osquery/resource_metrics.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

/var/log/osquery/alerts.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
}

# Network and disk I/O monitoring
create_io_monitor() {
    cat > /opt/osquery/monitoring/io_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    pid=$(pgrep osqueryd)
    
    if [ -n "$pid" ]; then
        # Get I/O statistics
        io_stats=$(cat /proc/$pid/io 2>/dev/null)
        read_bytes=$(echo "$io_stats" | grep "read_bytes" | awk '{print $2}')
        write_bytes=$(echo "$io_stats" | grep "write_bytes" | awk '{print $2}')
        
        # Get file descriptor count
        fd_count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
        
        echo "$timestamp,READ:$read_bytes,WRITE:$write_bytes,FDS:$fd_count" >> /var/log/osquery/io_metrics.log
    fi
    
    sleep 60
done
EOF
    
    chmod +x /opt/osquery/monitoring/io_monitor.sh
}

setup_monitoring
create_io_monitor

echo "Production monitoring setup completed."
```

### 3. Automated Health Checks

```bash
#!/bin/bash
# health_check.sh

perform_health_check() {
    local status=0
    
    echo "Performing osquery ancestry feature health check..."
    
    # Check if osquery is running
    if ! pgrep osqueryd >/dev/null; then
        echo "CRITICAL: osqueryd is not running"
        status=2
    fi
    
    # Check if process events are being generated
    recent_events=$(osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE time > (strftime('%s', 'now') - 300);" 2>/dev/null | jq -r '.[0].count')
    
    if [ -z "$recent_events" ] || [ "$recent_events" = "null" ]; then
        echo "CRITICAL: Unable to query process events"
        status=2
    elif [ "$recent_events" -eq 0 ]; then
        echo "WARNING: No process events in last 5 minutes"
        [ $status -lt 1 ] && status=1
    else
        echo "OK: $recent_events process events in last 5 minutes"
    fi
    
    # Check ancestry feature
    ancestry_events=$(osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE ancestry != '{}' AND time > (strftime('%s', 'now') - 300);" 2>/dev/null | jq -r '.[0].count')
    
    if [ -z "$ancestry_events" ] || [ "$ancestry_events" = "null" ]; then
        echo "CRITICAL: Unable to query ancestry data"
        status=2
    elif [ "$ancestry_events" -eq 0 ]; then
        echo "WARNING: No ancestry data in last 5 minutes"
        [ $status -lt 1 ] && status=1
    else
        echo "OK: $ancestry_events events with ancestry data in last 5 minutes"
    fi
    
    # Check resource usage
    memory_usage=$(ps aux | grep osqueryd | grep -v grep | awk '{print $4}' | head -1)
    if (( $(echo "$memory_usage > 25" | bc -l) )); then
        echo "WARNING: High memory usage: $memory_usage%"
        [ $status -lt 1 ] && status=1
    fi
    
    # Check disk space
    disk_usage=$(df /var/log/osquery | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 85 ]; then
        echo "WARNING: High disk usage in log directory: $disk_usage%"
        [ $status -lt 1 ] && status=1
    fi
    
    # Check log file sizes
    log_size=$(du -sm /var/log/osquery/ | awk '{print $1}')
    if [ "$log_size" -gt 1000 ]; then
        echo "WARNING: Large log directory size: ${log_size}MB"
        [ $status -lt 1 ] && status=1
    fi
    
    return $status
}

# Setup automated health checks
setup_health_monitoring() {
    # Create health check cron job
    cat > /etc/cron.d/osquery_health << 'EOF'
# osquery health check every 5 minutes
*/5 * * * * root /opt/osquery/monitoring/health_check.sh >> /var/log/osquery/health_check.log 2>&1
EOF
    
    # Create health check script
    cp "$0" /opt/osquery/monitoring/health_check.sh
    chmod +x /opt/osquery/monitoring/health_check.sh
    
    echo "Health monitoring setup completed."
}

# Run health check if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    perform_health_check
    exit $?
fi
```

## Scaling Recommendations

### 1. Hardware Scaling Guidelines

| Environment | CPU Cores | Memory | Storage | Network | Max Events/Sec |
|-------------|-----------|--------|---------|---------|----------------|
| Development | 2-4 | 4-8GB | 50GB | 1Gbps | 10-50 |
| Staging | 4-8 | 8-16GB | 100GB | 1Gbps | 50-200 |
| Production (Small) | 8-16 | 16-32GB | 500GB | 10Gbps | 200-500 |
| Production (Large) | 16-32 | 32-64GB | 1TB | 10Gbps | 500-1000 |
| Enterprise | 32+ | 64GB+ | 2TB+ | 10Gbps+ | 1000+ |

### 2. Configuration Tuning

```bash
# Production configuration template
cat > production_tuned_config.conf << 'EOF'
{
  "options": {
    "audit_allow_process_events": true,
    "process_events_enable_ancestry": true,
    "process_events_max_ancestry_depth": 8,
    "audit_allow_fork_process_events": true,
    "audit_allow_kill_process_events": false,
    
    "logger_tls_period": 15,
    "distributed_interval": 60,
    "config_refresh": 300,
    
    "database_path": "/opt/osquery/osquery.db",
    "logger_path": "/var/log/osquery/",
    "pidfile": "/var/run/osqueryd.pidfile",
    
    "disable_watchdog": false,
    "watchdog_level": 1,
    "watchdog_memory_limit": 2048,
    "watchdog_utilization_limit": 60,
    
    "schedule_timeout": 60,
    "schedule_max_drift": 60,
    
    "events_expiry": 3600,
    "events_max": 1000,
    
    "worker_threads": 4,
    "database_dump": false,
    "database_preserve_scan": true
  },
  
  "schedule": {
    "process_monitoring": {
      "query": "SELECT pid, parent, path, cmdline, json_extract(ancestry, '$.depth') as ancestry_depth FROM process_events WHERE time > (strftime('%s', 'now') - 3600);",
      "interval": 300,
      "description": "Process events with ancestry monitoring"
    }
  }
}
EOF
```

## Troubleshooting Production Issues

### 1. Performance Degradation

```bash
#!/bin/bash
# performance_troubleshooting.sh

diagnose_performance_issue() {
    echo "Diagnosing performance issues..."
    
    # Check system load
    echo "System Load:"
    uptime
    
    # Check memory pressure
    echo "Memory Status:"
    cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached)"
    
    # Check osquery resource usage
    echo "osquery Resource Usage:"
    ps aux | grep osqueryd | grep -v grep
    
    # Check audit queue
    echo "Audit Status:"
    auditctl -s
    
    # Check process event rate
    echo "Process Event Rate:"
    osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE time > (strftime('%s', 'now') - 60);" | jq -r '.[0].count'
    
    # Check for long ancestry chains
    echo "Ancestry Statistics:"
    osqueryi --json "SELECT 
        AVG(CAST(json_extract(ancestry, '$.depth') AS INTEGER)) as avg_depth,
        MAX(CAST(json_extract(ancestry, '$.depth') AS INTEGER)) as max_depth,
        COUNT(*) as events_with_ancestry
    FROM process_events 
    WHERE ancestry != '{}' 
    AND time > (strftime('%s', 'now') - 300);" | jq '.'
}

check_audit_performance() {
    echo "Audit System Performance:"
    
    # Check audit log size
    ls -lh /var/log/audit/audit.log*
    
    # Check audit daemon status
    systemctl status auditd
    
    # Check audit rules
    auditctl -l | grep -E "(execve|fork|clone)"
}

diagnose_performance_issue
check_audit_performance
```

### 2. Memory Issues

```bash
#!/bin/bash
# memory_troubleshooting.sh

analyze_memory_usage() {
    local pid=$(pgrep osqueryd)
    
    if [ -n "$pid" ]; then
        echo "Memory Analysis for osqueryd (PID: $pid):"
        
        # Detailed memory breakdown
        cat /proc/$pid/status | grep -E "(VmPeak|VmSize|VmLck|VmHWM|VmRSS|VmData|VmStk|VmExe|VmLib)"
        
        # Memory map analysis
        echo "Memory Map Summary:"
        cat /proc/$pid/smaps | grep -E "(Size|Rss|Pss|Shared_Clean|Shared_Dirty|Private_Clean|Private_Dirty)" | \
        awk '
        {
            if ($1 == "Size:") size += $2
            if ($1 == "Rss:") rss += $2
            if ($1 == "Pss:") pss += $2
            if ($1 == "Private_Dirty:") private_dirty += $2
        }
        END {
            print "Total Size: " size " kB"
            print "Total RSS: " rss " kB"
            print "Total PSS: " pss " kB"
            print "Private Dirty: " private_dirty " kB"
        }'
    fi
}

check_memory_leaks() {
    echo "Checking for memory leaks..."
    
    # Monitor memory over time
    for i in {1..10}; do
        memory=$(ps aux | grep osqueryd | grep -v grep | awk '{print $6}')
        echo "Sample $i: ${memory}KB"
        sleep 30
    done
}

analyze_memory_usage
check_memory_leaks
```

## Success Metrics and KPIs

### Key Performance Indicators

1. **System Performance**
   - CPU usage < 20% average
   - Memory usage < 25% of system RAM
   - I/O wait < 10%

2. **Feature Performance**
   - Ancestry collection time < 10ms per event
   - JSON serialization time < 5ms per event
   - Maximum ancestry depth achieved ≥ 90% of configured limit

3. **Data Quality**
   - Ancestry data completeness > 95%
   - JSON validation success rate = 100%
   - Process hierarchy accuracy > 99%

4. **Reliability**
   - osquery uptime > 99.9%
   - Event processing success rate > 99.5%
   - No memory leaks over 7-day periods

### Monitoring Dashboards

```bash
# Create metrics collection for dashboards
cat > collect_metrics.sh << 'EOF'
#!/bin/bash
# Metrics collection for monitoring dashboards

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Performance metrics
cpu_usage=$(ps aux | grep osqueryd | grep -v grep | awk '{print $3}' | head -1)
memory_usage=$(ps aux | grep osqueryd | grep -v grep | awk '{print $4}' | head -1)
memory_rss=$(ps aux | grep osqueryd | grep -v grep | awk '{print $6}' | head -1)

# Event metrics
event_rate=$(osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE time > (strftime('%s', 'now') - 60);" | jq -r '.[0].count')
ancestry_rate=$(osqueryi --json "SELECT COUNT(*) as count FROM process_events WHERE ancestry != '{}' AND time > (strftime('%s', 'now') - 60);" | jq -r '.[0].count')

# Output in InfluxDB line protocol format
echo "osquery_performance,host=$(hostname) cpu_usage=$cpu_usage,memory_usage=$memory_usage,memory_rss=${memory_rss}i $(date +%s)000000000"
echo "osquery_events,host=$(hostname) event_rate=${event_rate}i,ancestry_rate=${ancestry_rate}i $(date +%s)000000000"
EOF

chmod +x collect_metrics.sh
```

This comprehensive production guide ensures successful deployment and operation of the process ancestry feature at scale.
