# Production Scaling and End-to-End Testing Guide for Process Ancestry

## Overview

This guide provides comprehensive instructions for deploying, scaling, and testing the Linux process ancestry implementation in production environments. It covers deployment strategies, performance tuning, monitoring, and end-to-end testing procedures for enterprise-scale deployments.

## Production Architecture

### Deployment Models

#### 1. Centralized Fleet Management

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Fleet Server  │    │   Log Pipeline  │    │   SIEM/Analytics│
│   (FleetDM)     │◄───┤   (ELK/Splunk)  │◄───┤   (Elastic/etc) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                        ▲                        ▲
         │                        │                        │
    ┌────▼────┐              ┌────▼────┐              ┌────▼────┐
    │osquery  │              │osquery  │              │osquery  │
    │Agent 1  │              │Agent 2  │              │Agent N  │
    └─────────┘              └─────────┘              └─────────┘
```

#### 2. Distributed Fleet Management

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│Regional Fleet 1 │    │Regional Fleet 2 │    │Regional Fleet N │
│   (FleetDM)     │    │   (FleetDM)     │    │   (FleetDM)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                        ▲                        ▲
         │                        │                        │
    ┌────▼────┐              ┌────▼────┐              ┌────▼────┐
    │ 1000+   │              │ 1000+   │              │ 1000+   │
    │ Agents  │              │ Agents  │              │ Agents  │
    └─────────┘              └─────────┘              └─────────┘
                                     │
                              ┌─────▼─────┐
                              │ Central   │
                              │ Analytics │
                              └───────────┘
```

## Hardware Requirements by Scale

### Small Scale (1-100 endpoints)

| Component | Specification |
|-----------|---------------|
| **CPU** | 2-4 cores |
| **Memory** | 4-8 GB |
| **Storage** | 50-100 GB SSD |
| **Network** | 1 Gbps |
| **osquery Config** | Default settings |

```bash
# Recommended flags for small scale
--process_ancestry_cache_size=500
--process_ancestry_max_depth=16
--process_ancestry_cache_ttl=600
```

### Medium Scale (100-1000 endpoints)

| Component | Specification |
|-----------|---------------|
| **CPU** | 4-8 cores |
| **Memory** | 8-16 GB |
| **Storage** | 200-500 GB SSD |
| **Network** | 10 Gbps |
| **Load Balancer** | Required |

```bash
# Recommended flags for medium scale
--process_ancestry_cache_size=2000
--process_ancestry_max_depth=20
--process_ancestry_cache_ttl=300
```

### Large Scale (1000-10000 endpoints)

| Component | Specification |
|-----------|---------------|
| **CPU** | 8-16 cores |
| **Memory** | 16-32 GB |
| **Storage** | 1-2 TB NVMe SSD |
| **Network** | 25 Gbps |
| **Database** | Dedicated cluster |

```bash
# Recommended flags for large scale
--process_ancestry_cache_size=5000
--process_ancestry_max_depth=24
--process_ancestry_cache_ttl=180
```

### Enterprise Scale (10000+ endpoints)

| Component | Specification |
|-----------|---------------|
| **CPU** | 16-32 cores |
| **Memory** | 32-64 GB |
| **Storage** | 2-5 TB NVMe SSD |
| **Network** | 100 Gbps |
| **Architecture** | Multi-region |

```bash
# Recommended flags for enterprise scale
--process_ancestry_cache_size=10000
--process_ancestry_max_depth=32
--process_ancestry_cache_ttl=120
```

## Performance Tuning

### 1. Cache Optimization

#### Calculating Optimal Cache Size

```bash
# Formula: cache_size = (peak_processes_per_hour * 0.1) + safety_margin
# Example for 10,000 processes/hour:
cache_size = (10000 * 0.1) + 200 = 1200

# Monitor cache efficiency
osqueryi "SELECT 
    json_extract(value, '$.cache_hits') as hits,
    json_extract(value, '$.cache_misses') as misses,
    ROUND(
        CAST(json_extract(value, '$.cache_hits') AS FLOAT) / 
        (CAST(json_extract(value, '$.cache_hits') AS FLOAT) + 
         CAST(json_extract(value, '$.cache_misses') AS FLOAT)) * 100, 2
    ) as hit_rate_percent
FROM osquery_extensions 
WHERE name = 'process_ancestry_stats';"
```

#### Dynamic Cache Tuning

```bash
# Create cache tuning script
cat > /opt/osquery/bin/tune_cache.sh << 'EOF'
#!/bin/bash

STATS_FILE="/tmp/osquery_cache_stats.json"
CONFIG_FILE="/etc/osquery/osquery.conf"

# Get current cache stats
osqueryi "SELECT json_object(
    'hits', cache_hits,
    'misses', cache_misses,
    'size', cache_size,
    'hit_rate', ROUND(cache_hits * 100.0 / (cache_hits + cache_misses), 2)
) as stats FROM process_ancestry_cache_stats;" > $STATS_FILE

# Parse stats
HIT_RATE=$(cat $STATS_FILE | jq -r '.hit_rate')
CACHE_SIZE=$(cat $STATS_FILE | jq -r '.size')
MISSES=$(cat $STATS_FILE | jq -r '.misses')

# Adjust cache size if hit rate < 90%
if (( $(echo "$HIT_RATE < 90" | bc -l) )); then
    NEW_SIZE=$((CACHE_SIZE + MISSES / 10))
    echo "Increasing cache size to $NEW_SIZE (hit rate: $HIT_RATE%)"
    
    # Update configuration
    jq ".options.process_ancestry_cache_size = \"$NEW_SIZE\"" $CONFIG_FILE > /tmp/osquery.conf.new
    mv /tmp/osquery.conf.new $CONFIG_FILE
    
    # Restart osquery
    systemctl restart osqueryd
fi
EOF

chmod +x /opt/osquery/bin/tune_cache.sh

# Add to crontab for hourly tuning
echo "0 * * * * /opt/osquery/bin/tune_cache.sh" | crontab -
```

### 2. Memory Management

#### Memory Monitoring

```bash
# Create memory monitoring script
cat > /opt/osquery/bin/monitor_memory.sh << 'EOF'
#!/bin/bash

OSQUERY_PID=$(pgrep osqueryd)
if [ -z "$OSQUERY_PID" ]; then
    echo "osqueryd not running"
    exit 1
fi

# Get memory usage
MEMORY_KB=$(cat /proc/$OSQUERY_PID/status | grep VmRSS | awk '{print $2}')
MEMORY_MB=$((MEMORY_KB / 1024))

echo "{
    \"timestamp\": \"$(date -Iseconds)\",
    \"pid\": $OSQUERY_PID,
    \"memory_mb\": $MEMORY_MB,
    \"cache_size\": $(osqueryi "SELECT cache_size FROM process_ancestry_cache_stats;" | tail -1)
}" >> /var/log/osquery/memory_usage.jsonl

# Alert if memory usage > 1GB
if [ $MEMORY_MB -gt 1024 ]; then
    echo "WARNING: osqueryd memory usage is ${MEMORY_MB}MB" | logger -t osquery-monitor
fi
EOF

chmod +x /opt/osquery/bin/monitor_memory.sh

# Run every 5 minutes
echo "*/5 * * * * /opt/osquery/bin/monitor_memory.sh" | crontab -
```

#### Memory Limits

```bash
# Set systemd memory limits
sudo tee /etc/systemd/system/osqueryd.service.d/memory-limit.conf << 'EOF'
[Service]
MemoryMax=2G
MemoryHigh=1.5G
EOF

sudo systemctl daemon-reload
sudo systemctl restart osqueryd
```

### 3. Network Optimization

#### Batch Configuration

```json
{
  "options": {
    "logger_min_status": "1",
    "logger_min_stderr": "1",
    "schedule_splay_percent": "10",
    "schedule_default_interval": "3600",
    "pack_delimiter": "/",
    "logger_tls_compress": "true",
    "logger_kafka_acks": "1",
    "logger_kafka_compression": "snappy"
  }
}
```

#### Load Balancing

```bash
# HAProxy configuration for osquery fleet
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    maxconn 4096
    log stdout local0

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option httplog

frontend osquery_fleet
    bind *:443 ssl crt /etc/ssl/certs/fleet.pem
    redirect scheme https if !{ ssl_fc }
    default_backend fleet_servers

backend fleet_servers
    balance roundrobin
    option httpchk GET /api/v1/fleet/status
    server fleet1 10.0.1.10:8080 check
    server fleet2 10.0.1.11:8080 check
    server fleet3 10.0.1.12:8080 check
EOF
```

## Production Deployment

### 1. Staged Rollout Strategy

#### Phase 1: Canary Deployment (1% of fleet)

```bash
# Create canary configuration
cat > /etc/osquery/osquery-canary.conf << 'EOF'
{
  "options": {
    "config_plugin": "tls",
    "logger_plugin": "tls",
    "enroll_tls_endpoint": "/api/osquery/enroll",
    "config_tls_endpoint": "/api/osquery/config",
    "logger_tls_endpoint": "/api/osquery/log",
    "distributed_plugin": "tls",
    "distributed_interval": "60",
    "distributed_tls_max_attempts": "3",
    "distributed_tls_read_endpoint": "/api/osquery/distributed/read",
    "distributed_tls_write_endpoint": "/api/osquery/distributed/write",
    "tls_hostname": "fleet.company.com",
    "enroll_secret_path": "/etc/osquery/enroll_secret",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "16",
    "process_ancestry_cache_ttl": "300",
    "logger_tls_period": "10"
  }
}
EOF

# Deploy to 1% of nodes
ansible-playbook -i inventories/canary deploy-osquery.yml
```

#### Phase 2: Limited Rollout (10% of fleet)

```bash
# Monitor canary metrics for 48 hours
# If successful, proceed to 10% rollout
ansible-playbook -i inventories/limited deploy-osquery.yml
```

#### Phase 3: Full Rollout (100% of fleet)

```bash
# Monitor limited rollout for 1 week
# If successful, proceed to full rollout
ansible-playbook -i inventories/production deploy-osquery.yml
```

### 2. Configuration Management

#### Ansible Playbook

```yaml
# deploy-osquery.yml
---
- name: Deploy osquery with ancestry support
  hosts: all
  become: yes
  vars:
    osquery_version: "5.18.1-ancestry"
    cache_size: "{{ ansible_memtotal_mb // 8 }}"  # 1/8 of total memory
    max_depth: "{{ 16 if ansible_memtotal_mb < 4096 else 32 }}"
    
  tasks:
    - name: Install osquery
      package:
        name: osquery
        state: present
        
    - name: Configure osquery
      template:
        src: osquery.conf.j2
        dest: /etc/osquery/osquery.conf
        backup: yes
      notify: restart osquery
      
    - name: Deploy custom binary
      copy:
        src: "{{ osquery_binary_path }}"
        dest: /usr/bin/osqueryd
        mode: '0755'
        backup: yes
      notify: restart osquery
      
    - name: Start and enable osquery
      systemd:
        name: osqueryd
        state: started
        enabled: yes
        
  handlers:
    - name: restart osquery
      systemd:
        name: osqueryd
        state: restarted
```

#### Configuration Template

```jinja2
{# osquery.conf.j2 #}
{
  "options": {
    "config_plugin": "{{ osquery_config_plugin | default('filesystem') }}",
    "logger_plugin": "{{ osquery_logger_plugin | default('filesystem') }}",
    "logger_path": "/var/log/osquery",
    "database_path": "/var/osquery/osquery.db",
    "pidfile": "/var/osquery/osqueryd.pidfile",
    "host_identifier": "hostname",
    "utc": "true",
    "audit_allow_process_events": "true",
    "process_ancestry_cache_size": "{{ cache_size }}",
    "process_ancestry_max_depth": "{{ max_depth }}",
    "process_ancestry_cache_ttl": "{{ cache_ttl | default(300) }}",
    "schedule_splay_percent": "10",
    "worker_threads": "{{ ansible_processor_vcpus }}"
  },
  "schedule": {
    "process_events_ancestry": {
      "query": "SELECT pid, parent, path, cmdline, ancestry FROM process_events;",
      "interval": 300,
      "description": "Process events with ancestry information"
    }
  }
}
```

### 3. Monitoring and Alerting

#### Prometheus Integration

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'osquery-exporter'
    static_configs:
      - targets: ['localhost:9393']
    scrape_interval: 30s
    metrics_path: /metrics
```

#### Custom Metrics

```bash
# Create osquery Prometheus exporter
cat > /opt/osquery/bin/osquery_exporter.py << 'EOF'
#!/usr/bin/env python3
import json
import subprocess
import time
from prometheus_client import start_http_server, Gauge, Counter

# Metrics
process_events_total = Counter('osquery_process_events_total', 'Total process events')
ancestry_cache_hits = Gauge('osquery_ancestry_cache_hits', 'Cache hits')
ancestry_cache_misses = Gauge('osquery_ancestry_cache_misses', 'Cache misses')
ancestry_cache_size = Gauge('osquery_ancestry_cache_size', 'Cache size')
memory_usage_mb = Gauge('osquery_memory_usage_mb', 'Memory usage in MB')

def collect_metrics():
    try:
        # Get cache stats
        result = subprocess.run([
            'osqueryi', '--json',
            'SELECT cache_hits, cache_misses, cache_size FROM process_ancestry_cache_stats;'
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            data = json.loads(result.stdout)
            if data:
                stats = data[0]
                ancestry_cache_hits.set(stats['cache_hits'])
                ancestry_cache_misses.set(stats['cache_misses'])
                ancestry_cache_size.set(stats['cache_size'])
        
        # Get memory usage
        pid_result = subprocess.run(['pgrep', 'osqueryd'], capture_output=True, text=True)
        if pid_result.returncode == 0:
            pid = pid_result.stdout.strip()
            with open(f'/proc/{pid}/status', 'r') as f:
                for line in f:
                    if line.startswith('VmRSS:'):
                        kb = int(line.split()[1])
                        memory_usage_mb.set(kb / 1024)
                        break
                        
    except Exception as e:
        print(f"Error collecting metrics: {e}")

if __name__ == '__main__':
    start_http_server(9393)
    while True:
        collect_metrics()
        time.sleep(30)
EOF

chmod +x /opt/osquery/bin/osquery_exporter.py

# Create systemd service
sudo tee /etc/systemd/system/osquery-exporter.service << 'EOF'
[Unit]
Description=osquery Prometheus Exporter
After=network.target

[Service]
Type=simple
User=osquery
ExecStart=/opt/osquery/bin/osquery_exporter.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable osquery-exporter
sudo systemctl start osquery-exporter
```

#### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "osquery Process Ancestry",
    "panels": [
      {
        "title": "Cache Hit Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "osquery_ancestry_cache_hits / (osquery_ancestry_cache_hits + osquery_ancestry_cache_misses) * 100"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "osquery_memory_usage_mb"
          }
        ]
      },
      {
        "title": "Process Events Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(osquery_process_events_total[5m])"
          }
        ]
      }
    ]
  }
}
```

## End-to-End Testing

### 1. Integration Testing Framework

#### Test Suite Structure

```bash
mkdir -p /opt/osquery/tests/{unit,integration,performance,load}
```

#### Integration Test Script

```bash
cat > /opt/osquery/tests/integration/test_ancestry.sh << 'EOF'
#!/bin/bash

set -e

TEST_DIR="/tmp/osquery_test_$$"
mkdir -p $TEST_DIR
cd $TEST_DIR

echo "Starting integration tests for process ancestry..."

# Test 1: Basic functionality
echo "Test 1: Basic ancestry retrieval"
bash -c 'sleep 2' &
TEST_PID=$!
sleep 1

RESULT=$(osqueryi --json "SELECT ancestry FROM process_events WHERE pid = $TEST_PID;" | jq -r '.[0].ancestry')
if [ "$RESULT" != "null" ] && [ "$RESULT" != "[]" ]; then
    echo "✓ Test 1 passed: Ancestry data retrieved"
else
    echo "✗ Test 1 failed: No ancestry data"
    exit 1
fi

# Test 2: JSON validity
echo "Test 2: JSON validity"
echo "$RESULT" | jq . > /dev/null
if [ $? -eq 0 ]; then
    echo "✓ Test 2 passed: Valid JSON"
else
    echo "✗ Test 2 failed: Invalid JSON"
    exit 1
fi

# Test 3: Cache performance
echo "Test 3: Cache performance"
for i in {1..10}; do
    bash -c "echo $i; sleep 0.1" &
    PIDS[$i]=$!
done

start_time=$(date +%s%N)
osqueryi "SELECT COUNT(*) FROM process_events WHERE pid IN ($(IFS=','; echo "${PIDS[*]}"));" > /dev/null
end_time=$(date +%s%N)
duration=$(((end_time - start_time) / 1000000))  # Convert to milliseconds

if [ $duration -lt 5000 ]; then  # Less than 5 seconds
    echo "✓ Test 3 passed: Query completed in ${duration}ms"
else
    echo "✗ Test 3 failed: Query took ${duration}ms (too slow)"
    exit 1
fi

# Cleanup
wait
rm -rf $TEST_DIR

echo "All integration tests passed!"
EOF

chmod +x /opt/osquery/tests/integration/test_ancestry.sh
```

### 2. Load Testing

#### Load Test Framework

```bash
cat > /opt/osquery/tests/load/load_test.sh << 'EOF'
#!/bin/bash

DURATION=${1:-300}  # Default 5 minutes
PROCESS_RATE=${2:-10}  # Processes per second
QUERY_RATE=${3:-5}  # Queries per second

echo "Starting load test:"
echo "  Duration: ${DURATION}s"
echo "  Process creation rate: ${PROCESS_RATE}/s"
echo "  Query rate: ${QUERY_RATE}/s"

# Start process generator
(
    while true; do
        for i in $(seq 1 $PROCESS_RATE); do
            bash -c "sleep 1" &
        done
        sleep 1
    done
) &
PROC_GEN_PID=$!

# Start query generator
(
    while true; do
        for i in $(seq 1 $QUERY_RATE); do
            osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';" > /dev/null &
        done
        sleep 1
    done
) &
QUERY_GEN_PID=$!

# Monitor performance
(
    echo "timestamp,memory_mb,cpu_percent,cache_hits,cache_misses" > /tmp/load_test_results.csv
    while true; do
        TIMESTAMP=$(date -Iseconds)
        
        # Get memory usage
        OSQUERY_PID=$(pgrep osqueryd)
        MEMORY_KB=$(cat /proc/$OSQUERY_PID/status | grep VmRSS | awk '{print $2}')
        MEMORY_MB=$((MEMORY_KB / 1024))
        
        # Get CPU usage
        CPU_PERCENT=$(top -bn1 -p $OSQUERY_PID | tail -1 | awk '{print $9}')
        
        # Get cache stats
        CACHE_STATS=$(osqueryi --json "SELECT cache_hits, cache_misses FROM process_ancestry_cache_stats;" | jq -r '.[0] | "\(.cache_hits),\(.cache_misses)"')
        
        echo "$TIMESTAMP,$MEMORY_MB,$CPU_PERCENT,$CACHE_STATS" >> /tmp/load_test_results.csv
        sleep 10
    done
) &
MONITOR_PID=$!

# Run for specified duration
sleep $DURATION

# Cleanup
kill $PROC_GEN_PID $QUERY_GEN_PID $MONITOR_PID 2>/dev/null
wait

echo "Load test completed. Results in /tmp/load_test_results.csv"
EOF

chmod +x /opt/osquery/tests/load/load_test.sh
```

### 3. Performance Validation

#### Benchmark Script

```bash
cat > /opt/osquery/tests/performance/benchmark.sh << 'EOF'
#!/bin/bash

echo "osquery Process Ancestry Performance Benchmark"
echo "=============================================="

# Test 1: Query performance without cache
echo "Test 1: Cold cache performance"
systemctl restart osqueryd
sleep 5

time osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';" | tail -1

# Test 2: Query performance with warm cache
echo "Test 2: Warm cache performance"
# Run query twice to warm cache
osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';" > /dev/null

time osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';" | tail -1

# Test 3: Memory usage under load
echo "Test 3: Memory usage under load"
INITIAL_MEMORY=$(ps -o rss= -p $(pgrep osqueryd))

# Generate load
for i in {1..100}; do
    bash -c "sleep 0.1" &
done

sleep 5
LOADED_MEMORY=$(ps -o rss= -p $(pgrep osqueryd))

echo "Initial memory: ${INITIAL_MEMORY}KB"
echo "Under load: ${LOADED_MEMORY}KB"
echo "Increase: $((LOADED_MEMORY - INITIAL_MEMORY))KB"

wait

# Test 4: Cache efficiency
echo "Test 4: Cache efficiency"
STATS=$(osqueryi --json "SELECT cache_hits, cache_misses FROM process_ancestry_cache_stats;" | jq -r '.[0]')
HITS=$(echo $STATS | jq -r '.cache_hits')
MISSES=$(echo $STATS | jq -r '.cache_misses')
TOTAL=$((HITS + MISSES))

if [ $TOTAL -gt 0 ]; then
    HIT_RATE=$(echo "scale=2; $HITS * 100 / $TOTAL" | bc)
    echo "Cache hit rate: ${HIT_RATE}%"
else
    echo "No cache activity recorded"
fi

echo "Benchmark completed!"
EOF

chmod +x /opt/osquery/tests/performance/benchmark.sh
```

### 4. Automated Testing Pipeline

#### CI/CD Integration

```yaml
# .github/workflows/osquery-ancestry-test.yml
name: osquery Ancestry Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y build-essential cmake
        
    - name: Build osquery
      run: |
        mkdir build && cd build
        cmake ..
        make -j$(nproc)
        
    - name: Install test dependencies
      run: |
        sudo apt-get install -y jq bc
        
    - name: Run unit tests
      run: |
        ./build/osquery/tests/osquery_tests
        
    - name: Run integration tests
      run: |
        sudo ./tests/integration/test_ancestry.sh
        
    - name: Run performance tests
      run: |
        sudo ./tests/performance/benchmark.sh
```

## Disaster Recovery

### 1. Backup Procedures

```bash
# Create backup script
cat > /opt/osquery/bin/backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/backup/osquery/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup configuration
tar -czf $BACKUP_DIR/config.tar.gz /etc/osquery/

# Backup database
cp /var/osquery/osquery.db $BACKUP_DIR/

# Backup logs
tar -czf $BACKUP_DIR/logs.tar.gz /var/log/osquery/

# Backup custom binaries
cp /usr/bin/osqueryd $BACKUP_DIR/

echo "Backup completed: $BACKUP_DIR"
EOF

chmod +x /opt/osquery/bin/backup.sh

# Schedule daily backups
echo "0 2 * * * /opt/osquery/bin/backup.sh" | crontab -
```

### 2. Recovery Procedures

```bash
# Create recovery script
cat > /opt/osquery/bin/recover.sh << 'EOF'
#!/bin/bash

BACKUP_DIR=${1:-/backup/osquery/latest}

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "Recovering from backup: $BACKUP_DIR"

# Stop osquery
systemctl stop osqueryd

# Restore configuration
tar -xzf $BACKUP_DIR/config.tar.gz -C /

# Restore database
cp $BACKUP_DIR/osquery.db /var/osquery/

# Restore binary
cp $BACKUP_DIR/osqueryd /usr/bin/

# Set permissions
chown -R osquery:osquery /var/osquery
chmod +x /usr/bin/osqueryd

# Start osquery
systemctl start osqueryd

echo "Recovery completed!"
EOF

chmod +x /opt/osquery/bin/recover.sh
```

## Security Considerations

### 1. Hardening

```bash
# Create hardening script
cat > /opt/osquery/bin/harden.sh << 'EOF'
#!/bin/bash

# Set file permissions
chmod 600 /etc/osquery/osquery.conf
chmod 600 /etc/osquery/enroll_secret
chown -R osquery:osquery /etc/osquery
chown -R osquery:osquery /var/osquery
chown -R osquery:osquery /var/log/osquery

# Secure systemd service
mkdir -p /etc/systemd/system/osqueryd.service.d
cat > /etc/systemd/system/osqueryd.service.d/security.conf << 'INNER_EOF'
[Service]
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/osquery /var/log/osquery /tmp
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
INNER_EOF

systemctl daemon-reload
echo "Hardening completed!"
EOF

chmod +x /opt/osquery/bin/harden.sh
```

### 2. Audit and Compliance

```bash
# Create compliance check script
cat > /opt/osquery/bin/compliance_check.sh << 'EOF'
#!/bin/bash

echo "osquery Compliance Check"
echo "======================="

# Check file permissions
echo "Checking file permissions..."
ISSUES=0

if [ "$(stat -c %a /etc/osquery/osquery.conf)" != "600" ]; then
    echo "FAIL: osquery.conf permissions not secure"
    ((ISSUES++))
else
    echo "PASS: osquery.conf permissions secure"
fi

# Check service security
echo "Checking service security..."
if systemctl show osqueryd | grep -q "NoNewPrivileges=yes"; then
    echo "PASS: NoNewPrivileges enabled"
else
    echo "FAIL: NoNewPrivileges not enabled"
    ((ISSUES++))
fi

# Check process ancestry configuration
echo "Checking ancestry configuration..."
CACHE_SIZE=$(grep -o '"process_ancestry_cache_size": "[0-9]*"' /etc/osquery/osquery.conf | grep -o '[0-9]*')
if [ "$CACHE_SIZE" -le 10000 ]; then
    echo "PASS: Cache size within limits ($CACHE_SIZE)"
else
    echo "WARN: Cache size may be too large ($CACHE_SIZE)"
fi

echo "Compliance check completed with $ISSUES issues"
exit $ISSUES
EOF

chmod +x /opt/osquery/bin/compliance_check.sh
```

This comprehensive production guide ensures successful deployment and operation of the process ancestry implementation at enterprise scale, with proper monitoring, testing, and security measures in place.
