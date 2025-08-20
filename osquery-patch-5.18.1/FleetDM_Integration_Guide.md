# FleetDM Integration Guide for Process Ancestry Feature

## Overview

This guide provides comprehensive instructions for integrating the osquery process ancestry feature with FleetDM, including configuration management, query optimization, and dashboarding.

## Prerequisites

- FleetDM server running (version 4.0+)
- osquery with ancestry feature compiled and deployed
- Orbit agent for fleet management
- Basic understanding of FleetDM operations

## FleetDM Configuration

### 1. Agent Configuration for Ancestry Feature

Create a configuration profile in FleetDM to enable the ancestry feature:

```yaml
# FleetDM Agent Configuration
apiVersion: v1
kind: config
spec:
  agent_options:
    config:
      options:
        # Enable audit and process events
        audit_allow_process_events: true
        process_events_enable_ancestry: true
        process_events_max_ancestry_depth: 8
        audit_allow_fork_process_events: true
        audit_allow_kill_process_events: false
        
        # Performance tuning for FleetDM
        logger_tls_period: 30
        distributed_interval: 60
        config_refresh: 300
        
        # Database and logging
        database_path: "/opt/orbit/osquery.db"
        logger_path: "/var/log/orbit/"
        
        # Resource limits
        watchdog_memory_limit: 2048
        watchdog_utilization_limit: 50
        
        # Event management
        events_expiry: 7200
        events_max: 2000
        
      schedule:
        # Basic process ancestry monitoring
        process_ancestry_monitor:
          query: >
            SELECT 
              pid,
              parent,
              path,
              cmdline,
              json_extract(ancestry, '$.depth') as ancestry_depth,
              json_extract(ancestry, '$.truncated') as ancestry_truncated,
              time
            FROM process_events 
            WHERE time > (strftime('%s', 'now') - 300)
          interval: 300
          removed: false
          snapshot: false
          
        # Security-focused ancestry queries
        suspicious_process_trees:
          query: >
            SELECT 
              pe.pid,
              pe.path,
              pe.cmdline,
              pe.ancestry,
              pe.time
            FROM process_events pe
            WHERE pe.time > (strftime('%s', 'now') - 600)
            AND (
              pe.path LIKE '%/tmp/%' OR
              pe.path LIKE '%/var/tmp/%' OR
              pe.cmdline LIKE '%base64%' OR
              pe.cmdline LIKE '%curl%' OR
              pe.cmdline LIKE '%wget%' OR
              pe.cmdline LIKE '%powershell%'
            )
          interval: 300
          removed: false
          snapshot: false
          
        # Deep process hierarchy detection
        deep_process_hierarchies:
          query: >
            SELECT 
              pid,
              path,
              cmdline,
              ancestry,
              json_extract(ancestry, '$.depth') as depth,
              time
            FROM process_events 
            WHERE json_extract(ancestry, '$.depth') > 6
            AND time > (strftime('%s', 'now') - 600)
          interval: 600
          removed: false
          snapshot: false
```

### 2. Orbit Integration

Update Orbit configuration to support the ancestry feature:

```json
{
  "fleet": {
    "fleet_url": "https://your-fleet-server.com",
    "enrollment_secret": "your-enrollment-secret"
  },
  "osquery": {
    "executable_path": "/opt/orbit/bin/osquery/osqueryd",
    "config_path": "/opt/orbit/osquery.conf",
    "log_path": "/var/log/orbit/osquery/",
    "database_path": "/opt/orbit/osquery.db",
    "flags": [
      "--audit_allow_process_events=true",
      "--process_events_enable_ancestry=true", 
      "--process_events_max_ancestry_depth=8",
      "--audit_allow_fork_process_events=true",
      "--logger_tls_period=30",
      "--distributed_interval=60",
      "--disable_watchdog=false",
      "--watchdog_level=1"
    ]
  },
  "logging": {
    "level": "info"
  },
  "update": {
    "channel": "stable",
    "disabled": false
  }
}
```

### 3. Fleet Policies for Ancestry Monitoring

Create FleetDM policies to monitor process ancestry patterns:

```sql
-- Policy: Detect Processes with Suspicious Ancestry
-- Description: Identifies processes with suspicious parent chains
SELECT 1 FROM process_events 
WHERE time > (strftime('%s', 'now') - 3600)
AND (
  ancestry LIKE '%/tmp/%' OR
  ancestry LIKE '%suspicious%' OR
  json_extract(ancestry, '$.truncated') = 'true' OR
  json_extract(ancestry, '$.depth') > 10
)
LIMIT 1;

-- Policy: Monitor Critical Process Spawning
-- Description: Monitors spawning of critical system processes
SELECT 1 FROM process_events
WHERE time > (strftime('%s', 'now') - 1800)
AND path IN (
  '/bin/su', '/bin/sudo', '/usr/bin/sudo',
  '/bin/ssh', '/usr/bin/ssh',
  '/sbin/iptables', '/usr/sbin/iptables'
)
AND json_extract(ancestry, '$.ancestors[0].path') NOT IN (
  '/usr/sbin/sshd', '/bin/bash', '/bin/dash'
)
LIMIT 1;

-- Policy: Detect Process Privilege Escalation
-- Description: Identifies potential privilege escalation via process ancestry
SELECT 1 FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 1800) 
AND pe.uid = '0'
AND EXISTS (
  SELECT 1 FROM json_each(pe.ancestry, '$.ancestors') AS ancestor
  WHERE json_extract(ancestor.value, '$.path') LIKE '%/tmp/%'
  OR json_extract(ancestor.value, '$.cmdline') LIKE '%curl%'
  OR json_extract(ancestor.value, '$.cmdline') LIKE '%wget%'
)
LIMIT 1;
```

## Advanced Fleet Queries

### 1. Incident Response Queries

```sql
-- Query: Full Process Tree Analysis
-- Use case: Incident response and forensic analysis
SELECT 
  pe.pid,
  pe.parent,
  pe.path,
  pe.cmdline,
  pe.ancestry,
  pe.time,
  pe.uptime,
  CASE 
    WHEN json_extract(pe.ancestry, '$.depth') > 5 THEN 'Deep'
    WHEN json_extract(pe.ancestry, '$.depth') > 2 THEN 'Medium'
    ELSE 'Shallow'
  END as hierarchy_depth,
  json_extract(pe.ancestry, '$.truncated') as ancestry_truncated
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - ?)
ORDER BY pe.time DESC;

-- Query: Lateral Movement Detection
-- Use case: Detect potential lateral movement patterns
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  pe.ancestry,
  COUNT(*) as occurrence_count,
  GROUP_CONCAT(DISTINCT pe.time) as event_times
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 7200)
AND (
  pe.path LIKE '%ssh%' OR
  pe.path LIKE '%scp%' OR
  pe.path LIKE '%rsync%' OR
  pe.cmdline LIKE '%ssh%' OR
  pe.cmdline LIKE '%scp%'
)
GROUP BY pe.path, pe.cmdline
HAVING occurrence_count > 5
ORDER BY occurrence_count DESC;

-- Query: Persistence Mechanism Detection
-- Use case: Identify persistence mechanisms through process ancestry
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  pe.ancestry,
  pe.time
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 3600)
AND (
  pe.cmdline LIKE '%crontab%' OR
  pe.cmdline LIKE '%systemctl%' OR
  pe.cmdline LIKE '%service%' OR
  pe.path LIKE '%/etc/init.d/%' OR
  pe.path LIKE '%systemd%'
)
AND json_extract(pe.ancestry, '$.ancestors[0].path') NOT LIKE '%/usr/bin/crontab%'
ORDER BY pe.time DESC;
```

### 2. Security Monitoring Queries

```sql
-- Query: Anomalous Process Trees
-- Use case: Detect unusual process spawning patterns
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  json_extract(pe.ancestry, '$.depth') as ancestry_depth,
  json_extract(pe.ancestry, '$.ancestors') as full_ancestry,
  pe.time
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 1800)
AND (
  -- Processes spawned from unusual locations
  json_extract(pe.ancestry, '$.ancestors[0].path') LIKE '%/tmp/%' OR
  json_extract(pe.ancestry, '$.ancestors[0].path') LIKE '%/var/tmp/%' OR
  json_extract(pe.ancestry, '$.ancestors[0].path') LIKE '%/dev/shm/%' OR
  
  -- Deep process hierarchies
  json_extract(pe.ancestry, '$.depth') > 8 OR
  
  -- Truncated ancestry (potential evasion)
  json_extract(pe.ancestry, '$.truncated') = 'true'
)
ORDER BY pe.time DESC;

-- Query: Command Injection Detection
-- Use case: Detect potential command injection via process ancestry
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  pe.ancestry,
  pe.time
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 1800)
AND pe.path IN ('/bin/sh', '/bin/bash', '/bin/dash')
AND EXISTS (
  SELECT 1 FROM json_each(pe.ancestry, '$.ancestors') AS ancestor
  WHERE json_extract(ancestor.value, '$.path') LIKE '%httpd%'
  OR json_extract(ancestor.value, '$.path') LIKE '%nginx%'
  OR json_extract(ancestor.value, '$.path') LIKE '%apache%'
  OR json_extract(ancestor.value, '$.path') LIKE '%php%'
  OR json_extract(ancestor.value, '$.path') LIKE '%python%'
  OR json_extract(ancestor.value, '$.path') LIKE '%node%'
)
ORDER BY pe.time DESC;

-- Query: Container Escape Detection
-- Use case: Detect potential container escape attempts
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  pe.ancestry,
  pe.time
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 1800)
AND (
  pe.cmdline LIKE '%docker%' OR
  pe.cmdline LIKE '%kubectl%' OR
  pe.cmdline LIKE '%crictl%' OR
  pe.path LIKE '%/proc/%' OR
  pe.cmdline LIKE '%/host/%' OR
  pe.cmdline LIKE '%chroot%' OR
  pe.cmdline LIKE '%nsenter%'
)
AND json_extract(pe.ancestry, '$.depth') > 3
ORDER BY pe.time DESC;
```

### 3. Performance and Operations Queries

```sql
-- Query: Process Event Volume Analysis
-- Use case: Monitor process event generation rates
SELECT 
  strftime('%Y-%m-%d %H', datetime(time, 'unixepoch')) as hour,
  COUNT(*) as total_events,
  COUNT(CASE WHEN ancestry != '{}' THEN 1 END) as events_with_ancestry,
  AVG(CAST(json_extract(ancestry, '$.depth') AS REAL)) as avg_ancestry_depth,
  MAX(CAST(json_extract(ancestry, '$.depth') AS INTEGER)) as max_ancestry_depth,
  COUNT(CASE WHEN json_extract(ancestry, '$.truncated') = 'true' THEN 1 END) as truncated_events
FROM process_events 
WHERE time > (strftime('%s', 'now') - 86400)
GROUP BY strftime('%Y-%m-%d %H', datetime(time, 'unixepoch'))
ORDER BY hour DESC;

-- Query: Top Process Generators
-- Use case: Identify processes generating the most child processes
SELECT 
  json_extract(pe.ancestry, '$.ancestors[0].path') as parent_path,
  json_extract(pe.ancestry, '$.ancestors[0].cmdline') as parent_cmdline,
  COUNT(*) as child_count,
  AVG(CAST(json_extract(pe.ancestry, '$.depth') AS REAL)) as avg_tree_depth
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 3600)
AND pe.ancestry != '{}'
GROUP BY 
  json_extract(pe.ancestry, '$.ancestors[0].path'),
  json_extract(pe.ancestry, '$.ancestors[0].cmdline')
HAVING child_count > 10
ORDER BY child_count DESC
LIMIT 20;

-- Query: System Load Impact Assessment
-- Use case: Assess system impact of ancestry feature
SELECT 
  'process_events' as table_name,
  COUNT(*) as total_events,
  COUNT(CASE WHEN ancestry != '{}' THEN 1 END) as ancestry_events,
  ROUND(
    (COUNT(CASE WHEN ancestry != '{}' THEN 1 END) * 100.0 / COUNT(*)), 2
  ) as ancestry_coverage_percent,
  AVG(LENGTH(ancestry)) as avg_ancestry_json_size,
  MAX(LENGTH(ancestry)) as max_ancestry_json_size
FROM process_events 
WHERE time > (strftime('%s', 'now') - 3600);
```

## Dashboard Configuration

### 1. FleetDM Dashboard Widgets

Create custom dashboard widgets in FleetDM to visualize ancestry data:

```sql
-- Widget: Process Event Volume
SELECT 
  strftime('%H:%M', datetime(time, 'unixepoch')) as time_bucket,
  COUNT(*) as event_count
FROM process_events 
WHERE time > (strftime('%s', 'now') - 3600)
GROUP BY strftime('%H:%M', datetime(time, 'unixepoch'))
ORDER BY time_bucket;

-- Widget: Ancestry Depth Distribution
SELECT 
  CASE 
    WHEN json_extract(ancestry, '$.depth') <= 2 THEN 'Shallow (1-2)'
    WHEN json_extract(ancestry, '$.depth') <= 5 THEN 'Medium (3-5)'
    WHEN json_extract(ancestry, '$.depth') <= 8 THEN 'Deep (6-8)'
    ELSE 'Very Deep (9+)'
  END as depth_category,
  COUNT(*) as event_count
FROM process_events 
WHERE time > (strftime('%s', 'now') - 3600)
AND ancestry != '{}'
GROUP BY depth_category
ORDER BY event_count DESC;

-- Widget: Top Suspicious Process Paths
SELECT 
  path,
  COUNT(*) as occurrence_count,
  GROUP_CONCAT(DISTINCT cmdline, ' | ') as command_variations
FROM process_events 
WHERE time > (strftime('%s', 'now') - 3600)
AND (
  path LIKE '%/tmp/%' OR
  path LIKE '%/var/tmp/%' OR
  path LIKE '%/dev/shm/%'
)
GROUP BY path
ORDER BY occurrence_count DESC
LIMIT 10;
```

### 2. Alert Configuration

Configure FleetDM alerts for ancestry-based detections:

```yaml
# FleetDM Alert Configuration
alerts:
  - name: "Suspicious Process Ancestry Detected"
    description: "Process with suspicious ancestry pattern detected"
    query: >
      SELECT 1 FROM process_events 
      WHERE time > (strftime('%s', 'now') - 300)
      AND (
        ancestry LIKE '%/tmp/%' OR
        json_extract(ancestry, '$.depth') > 10
      )
      LIMIT 1
    interval: 300
    severity: "high"
    
  - name: "Deep Process Hierarchy Alert"
    description: "Unusually deep process hierarchy detected"
    query: >
      SELECT 1 FROM process_events
      WHERE time > (strftime('%s', 'now') - 600)
      AND json_extract(ancestry, '$.depth') > 8
      LIMIT 1
    interval: 600
    severity: "medium"
    
  - name: "Truncated Ancestry Detection"
    description: "Process ancestry was truncated due to depth limit"
    query: >
      SELECT 1 FROM process_events
      WHERE time > (strftime('%s', 'now') - 600)
      AND json_extract(ancestry, '$.truncated') = 'true'
      LIMIT 1
    interval: 600
    severity: "low"
```

## Integration with Existing FleetDM Workflows

### 1. Host Targeting by Ancestry Patterns

```sql
-- Target hosts with specific ancestry patterns for further investigation
SELECT DISTINCT h.hostname, h.osquery_version, h.platform
FROM hosts h
JOIN host_additional_queries haq ON h.id = haq.host_id
WHERE haq.query_name = 'process_ancestry_monitor'
AND haq.last_result LIKE '%suspicious%'
AND haq.updated_at > datetime('now', '-1 hour');
```

### 2. Incident Response Automation

Create automated response workflows:

```bash
#!/bin/bash
# incident_response_automation.sh

# Function to trigger incident response based on ancestry data
trigger_incident_response() {
    local host_id="$1"
    local detection_type="$2"
    local ancestry_data="$3"
    
    echo "Incident detected on host $host_id: $detection_type"
    echo "Ancestry data: $ancestry_data"
    
    # Create incident ticket
    curl -X POST "https://your-fleet-server.com/api/v1/incidents" \
        -H "Authorization: Bearer $FLEET_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"title\": \"Suspicious Process Ancestry Detected\",
            \"description\": \"Host $host_id showed $detection_type pattern\",
            \"severity\": \"high\",
            \"ancestry_data\": \"$ancestry_data\"
        }"
    
    # Trigger additional queries on affected host
    fleetctl query --hosts "$host_id" --query "
        SELECT * FROM process_events 
        WHERE time > (strftime('%s', 'now') - 1800)
        ORDER BY time DESC
        LIMIT 50
    "
}

# Monitor for specific patterns and trigger responses
monitor_ancestry_patterns() {
    while true; do
        # Check for suspicious patterns via FleetDM API
        suspicious_hosts=$(fleetctl query --json --query "
            SELECT h.hostname, pe.ancestry
            FROM hosts h
            JOIN process_events pe ON h.id = pe.host_id
            WHERE pe.time > (strftime('%s', 'now') - 300)
            AND (
                pe.ancestry LIKE '%/tmp/%' OR
                json_extract(pe.ancestry, '$.depth') > 10
            )
        ")
        
        if [ -n "$suspicious_hosts" ]; then
            echo "$suspicious_hosts" | jq -r '.[] | @base64' | while read -r encoded_host; do
                host_data=$(echo "$encoded_host" | base64 -d)
                hostname=$(echo "$host_data" | jq -r '.hostname')
                ancestry=$(echo "$host_data" | jq -r '.ancestry')
                
                trigger_incident_response "$hostname" "suspicious_ancestry" "$ancestry"
            done
        fi
        
        sleep 300  # Check every 5 minutes
    done
}

monitor_ancestry_patterns
```

### 3. Compliance Reporting

Generate compliance reports using ancestry data:

```sql
-- Compliance Report: Process Monitoring Coverage
SELECT 
  'Process Monitoring Coverage' as metric,
  COUNT(DISTINCT h.hostname) as total_hosts,
  COUNT(DISTINCT CASE WHEN pe.ancestry != '{}' THEN h.hostname END) as hosts_with_ancestry,
  ROUND(
    (COUNT(DISTINCT CASE WHEN pe.ancestry != '{}' THEN h.hostname END) * 100.0 / 
     COUNT(DISTINCT h.hostname)), 2
  ) as coverage_percentage
FROM hosts h
LEFT JOIN process_events pe ON h.id = pe.host_id
WHERE pe.time > (strftime('%s', 'now') - 86400);

-- Compliance Report: Security Event Detection Capability
SELECT 
  'Security Event Detection' as metric,
  COUNT(*) as total_process_events,
  COUNT(CASE WHEN json_extract(ancestry, '$.depth') > 3 THEN 1 END) as complex_hierarchies,
  COUNT(CASE WHEN ancestry LIKE '%suspicious%' THEN 1 END) as potential_threats,
  ROUND(
    (COUNT(CASE WHEN ancestry LIKE '%suspicious%' THEN 1 END) * 100.0 / COUNT(*)), 2
  ) as threat_detection_rate
FROM process_events 
WHERE time > (strftime('%s', 'now') - 604800);  -- Last 7 days
```

## Performance Optimization for FleetDM

### 1. Query Optimization

```sql
-- Optimized query for large fleets
-- Use indexed columns and limit result sets
SELECT 
  pe.pid,
  pe.path,
  pe.cmdline,
  json_extract(pe.ancestry, '$.depth') as depth,
  pe.time
FROM process_events pe
WHERE pe.time > (strftime('%s', 'now') - 1800)  -- Indexed column
AND pe.path LIKE '/tmp/%'  -- Specific path filter
ORDER BY pe.time DESC
LIMIT 1000;  -- Limit results

-- Use CTEs for complex ancestry analysis
WITH suspicious_processes AS (
  SELECT pid, path, cmdline, ancestry, time
  FROM process_events
  WHERE time > (strftime('%s', 'now') - 3600)
  AND (
    path LIKE '%/tmp/%' OR
    json_extract(ancestry, '$.depth') > 8
  )
),
ancestry_analysis AS (
  SELECT 
    sp.*,
    json_extract(sp.ancestry, '$.ancestors[0].path') as immediate_parent
  FROM suspicious_processes sp
)
SELECT * FROM ancestry_analysis
ORDER BY time DESC;
```

### 2. Configuration Tuning for Fleet Scale

```yaml
# FleetDM configuration for large deployments with ancestry
fleet:
  server:
    # Database optimization
    mysql:
      max_connections: 1000
      innodb_buffer_pool_size: "8G"
      query_cache_size: "1G"
      
    # Query optimization
    osquery:
      max_execution_time: 60
      host_batch_size: 1000
      
  # Agent configuration for ancestry feature
  agent_options:
    config:
      options:
        # Optimize for large fleets
        distributed_interval: 120  # Longer intervals for large fleets
        logger_tls_period: 60
        
        # Ancestry-specific optimizations
        process_events_max_ancestry_depth: 6  # Reduced for performance
        events_max: 1500
        events_expiry: 3600
        
        # Resource management
        watchdog_memory_limit: 1024
        worker_threads: 2
        
      schedule:
        # Reduced frequency for resource-intensive ancestry queries
        ancestry_monitoring:
          query: >
            SELECT pid, path, cmdline, 
                   json_extract(ancestry, '$.depth') as depth,
                   time
            FROM process_events 
            WHERE time > (strftime('%s', 'now') - 600)
            AND (
              json_extract(ancestry, '$.depth') > 4 OR
              path LIKE '%/tmp/%'
            )
          interval: 600  # 10-minute interval
          removed: false
```

## Troubleshooting FleetDM Integration

### 1. Common Issues and Solutions

**Issue: Ancestry data not appearing in FleetDM**
```bash
# Check osquery configuration
fleetctl get config --debug

# Verify ancestry flags are set
fleetctl query --query "SELECT name, value FROM osquery_flags WHERE name LIKE '%ancestry%';"

# Check process events are being generated
fleetctl query --query "SELECT COUNT(*) FROM process_events WHERE time > (strftime('%s', 'now') - 300);"
```

**Issue: High resource usage with ancestry enabled**
```bash
# Monitor resource usage
fleetctl query --query "
SELECT 
  (SELECT value FROM osquery_info WHERE key='version') as osquery_version,
  (SELECT total_size FROM osquery_info WHERE key='memory_rss') as memory_usage,
  (SELECT value FROM osquery_schedule WHERE name='ancestry_monitoring') as ancestry_schedule
"

# Adjust configuration if needed
# Reduce max_ancestry_depth or increase query intervals
```

**Issue: FleetDM query timeouts with ancestry queries**
```bash
# Use pagination for large result sets
fleetctl query --query "
SELECT * FROM process_events 
WHERE time > (strftime('%s', 'now') - 1800)
ORDER BY time DESC 
LIMIT 100 OFFSET 0
"

# Break complex queries into smaller chunks
# Use host targeting to reduce query scope
```

### 2. Performance Monitoring

```bash
#!/bin/bash
# fleet_performance_monitor.sh

monitor_fleet_performance() {
    echo "Monitoring FleetDM performance with ancestry feature..."
    
    # Check query response times
    start_time=$(date +%s)
    fleetctl query --query "SELECT COUNT(*) FROM process_events WHERE ancestry != '{}';" >/dev/null
    end_time=$(date +%s)
    query_time=$((end_time - start_time))
    
    echo "Ancestry query response time: ${query_time}s"
    
    # Check data volume
    result=$(fleetctl query --json --query "
        SELECT 
            COUNT(*) as total_events,
            COUNT(CASE WHEN ancestry != '{}' THEN 1 END) as ancestry_events,
            AVG(LENGTH(ancestry)) as avg_ancestry_size
        FROM process_events 
        WHERE time > (strftime('%s', 'now') - 3600)
    ")
    
    echo "Data metrics: $result"
    
    # Check host connectivity
    offline_hosts=$(fleetctl get hosts --json | jq '[.[] | select(.status == "offline")] | length')
    total_hosts=$(fleetctl get hosts --json | jq '. | length')
    
    echo "Host status: $offline_hosts offline out of $total_hosts total"
}

monitor_fleet_performance
```

## Migration from Existing FleetDM Setup

### 1. Gradual Migration Strategy

```bash
#!/bin/bash
# migration_strategy.sh

# Phase 1: Deploy to test group (5% of fleet)
deploy_test_group() {
    echo "Deploying ancestry feature to test group..."
    
    # Create test team
    fleetctl create team --name "ancestry-test-group"
    
    # Add test hosts to team
    fleetctl modify team --name "ancestry-test-group" --hosts "host1,host2,host3"
    
    # Apply ancestry configuration to test team
    fleetctl apply --config ancestry-test-config.yaml --team "ancestry-test-group"
}

# Phase 2: Monitor test group
monitor_test_group() {
    echo "Monitoring test group performance..."
    
    # Check for issues
    fleetctl query --team "ancestry-test-group" --query "
        SELECT hostname, last_enrolled, status
        FROM hosts 
        WHERE status != 'online'
    "
    
    # Verify ancestry data
    fleetctl query --team "ancestry-test-group" --query "
        SELECT COUNT(*) as ancestry_events
        FROM process_events 
        WHERE ancestry != '{}' 
        AND time > (strftime('%s', 'now') - 3600)
    "
}

# Phase 3: Full deployment
deploy_full_fleet() {
    echo "Deploying to full fleet..."
    
    # Apply to all teams
    fleetctl apply --config ancestry-production-config.yaml
    
    # Monitor rollout
    fleetctl query --query "
        SELECT 
            COUNT(*) as total_hosts,
            COUNT(CASE WHEN status = 'online' THEN 1 END) as online_hosts
        FROM hosts
    "
}

# Execute migration phases
deploy_test_group
sleep 3600  # Wait 1 hour
monitor_test_group
sleep 86400  # Wait 24 hours
deploy_full_fleet
```

### 2. Configuration Backup and Rollback

```bash
#!/bin/bash
# backup_rollback.sh

# Backup current configuration
backup_config() {
    echo "Backing up current FleetDM configuration..."
    
    fleetctl get config > fleet-config-backup-$(date +%Y%m%d-%H%M%S).yaml
    fleetctl get teams --yaml > teams-backup-$(date +%Y%m%d-%H%M%S).yaml
    fleetctl get packs --yaml > packs-backup-$(date +%Y%m%d-%H%M%S).yaml
}

# Rollback if issues occur
rollback_config() {
    local backup_file="$1"
    
    echo "Rolling back to configuration: $backup_file"
    
    # Disable ancestry features
    fleetctl apply --config - <<EOF
apiVersion: v1
kind: config
spec:
  agent_options:
    config:
      options:
        process_events_enable_ancestry: false
        audit_allow_process_events: false
EOF
    
    # Apply original configuration
    fleetctl apply --config "$backup_file"
    
    echo "Rollback completed"
}

# Health check after deployment
health_check() {
    echo "Performing health check..."
    
    # Check host connectivity
    offline_count=$(fleetctl get hosts --json | jq '[.[] | select(.status == "offline")] | length')
    
    if [ "$offline_count" -gt 10 ]; then
        echo "WARNING: $offline_count hosts are offline"
        return 1
    fi
    
    # Check query performance
    start=$(date +%s%N)
    fleetctl query --query "SELECT 1;" >/dev/null
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))  # Convert to milliseconds
    
    if [ "$duration" -gt 5000 ]; then
        echo "WARNING: Query response time is ${duration}ms"
        return 1
    fi
    
    echo "Health check passed"
    return 0
}

# Main migration workflow
backup_config

if ! health_check; then
    echo "Health check failed, initiating rollback..."
    rollback_config "fleet-config-backup-*.yaml"
fi
```

This comprehensive FleetDM integration guide ensures successful deployment and operation of the process ancestry feature within your Fleet management infrastructure.
