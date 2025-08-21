# FleetDM Integration Guide for Process Ancestry Implementation

## Overview

This guide provides comprehensive instructions for integrating the Linux process ancestry implementation with FleetDM, transitioning from Orbit deployments, and leveraging FleetDM's management capabilities for the enhanced process_events table.

## Current Architecture vs Target Architecture

### Current: Orbit Deployment

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Orbit Agent   │────▶│  osquery daemon │────▶│   Log Backend   │
│   (Management)  │    │  (Process Events)│    │   (ELK/Splunk)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Target: FleetDM Integration

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   FleetDM       │◄───┤   osquery with │────▶│   FleetDM       │
│   Server        │    │   Ancestry      │    │   Database      │
│   (Management)  │    │   Support       │    │   (Results)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Fleet API     │    │   Live Query    │    │   Analytics/    │
│   (REST/GraphQL)│    │   Interface     │    │   Alerting      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Migration from Orbit to FleetDM

### 1. Assessment and Planning

#### Pre-Migration Inventory

```bash
# Create inventory script
cat > /tmp/orbit_inventory.sh << 'EOF'
#!/bin/bash

echo "Orbit to FleetDM Migration Inventory"
echo "==================================="

# Check current Orbit installation
if command -v orbit &> /dev/null; then
    echo "Orbit Version: $(orbit version)"
    echo "Orbit Status: $(systemctl is-active orbit || service orbit status)"
    echo "Orbit Config: $(find /opt/orbit -name "*.json" 2>/dev/null)"
else
    echo "Orbit: Not installed"
fi

# Check osquery version
if command -v osqueryd &> /dev/null; then
    echo "osquery Version: $(osqueryd --version)"
    echo "osquery Config: $(find /etc/osquery -name "osquery.conf" 2>/dev/null)"
    echo "osquery Database: $(find /var/osquery -name "osquery.db" 2>/dev/null)"
else
    echo "osquery: Not installed"
fi

# Check system resources
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "CPU Cores: $(nproc)"
echo "Disk Space: $(df -h / | tail -1 | awk '{print $4}')"

# Check network connectivity
echo "Fleet Server Connectivity: $(curl -s -o /dev/null -w "%{http_code}" https://fleet.company.com/api/v1/fleet/status || echo "Failed")"

echo "Inventory completed!"
EOF

chmod +x /tmp/orbit_inventory.sh
/tmp/orbit_inventory.sh > /tmp/migration_inventory.txt
```

#### Migration Plan

```bash
# Create migration plan
cat > /tmp/migration_plan.md << 'EOF'
# Orbit to FleetDM Migration Plan

## Phase 1: Preparation (Week 1)
- [ ] Backup existing Orbit configurations
- [ ] Set up FleetDM server infrastructure
- [ ] Test osquery with ancestry support
- [ ] Create FleetDM enrollment packages

## Phase 2: Pilot Migration (Week 2)
- [ ] Select 10 pilot systems
- [ ] Deploy FleetDM agents
- [ ] Verify process ancestry functionality
- [ ] Test live queries and policies

## Phase 3: Staged Rollout (Weeks 3-6)
- [ ] 25% of fleet (Week 3)
- [ ] 50% of fleet (Week 4)
- [ ] 75% of fleet (Week 5)
- [ ] 100% of fleet (Week 6)

## Phase 4: Cleanup (Week 7)
- [ ] Remove Orbit agents
- [ ] Cleanup old configurations
- [ ] Optimize FleetDM queries
- [ ] Update documentation
EOF
```

### 2. FleetDM Server Setup

#### Docker Deployment

```yaml
# docker-compose.yml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: fleet_password
      MYSQL_DATABASE: fleet
      MYSQL_USER: fleet
      MYSQL_PASSWORD: fleet_password
    volumes:
      - mysql_data:/var/lib/mysql
    command: >
      --default-authentication-plugin=mysql_native_password
      --sql_mode=""
      --innodb_buffer_pool_size=1G
      --innodb_log_file_size=256M

  redis:
    image: redis:7
    volumes:
      - redis_data:/data

  fleet:
    image: fleetdm/fleet:v4.44.0
    depends_on:
      - mysql
      - redis
    environment:
      FLEET_MYSQL_ADDRESS: mysql:3306
      FLEET_MYSQL_DATABASE: fleet
      FLEET_MYSQL_USERNAME: fleet
      FLEET_MYSQL_PASSWORD: fleet_password
      FLEET_REDIS_ADDRESS: redis:6379
      FLEET_SERVER_CERT: /etc/ssl/certs/server.crt
      FLEET_SERVER_KEY: /etc/ssl/private/server.key
      FLEET_AUTH_JWT_KEY: your_jwt_key_here
      FLEET_OSQUERY_RESULT_LOG_FILE: /var/log/fleet/osquery_result.log
      FLEET_OSQUERY_STATUS_LOG_FILE: /var/log/fleet/osquery_status.log
    volumes:
      - ./certs:/etc/ssl/certs:ro
      - ./private:/etc/ssl/private:ro
      - fleet_logs:/var/log/fleet
    ports:
      - "443:8080"
    command: >
      fleet serve
      --mysql_address=mysql:3306
      --mysql_database=fleet
      --mysql_username=fleet
      --mysql_password=fleet_password
      --redis_address=redis:6379
      --server_cert=/etc/ssl/certs/server.crt
      --server_key=/etc/ssl/private/server.key
      --auth_jwt_key=your_jwt_key_here

volumes:
  mysql_data:
  redis_data:
  fleet_logs:
```

#### Kubernetes Deployment

```yaml
# fleetdm-k8s.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetdm
  namespace: fleet
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fleetdm
  template:
    metadata:
      labels:
        app: fleetdm
    spec:
      containers:
      - name: fleet
        image: fleetdm/fleet:v4.44.0
        env:
        - name: FLEET_MYSQL_ADDRESS
          value: "mysql.fleet.svc.cluster.local:3306"
        - name: FLEET_MYSQL_DATABASE
          value: "fleet"
        - name: FLEET_MYSQL_USERNAME
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: username
        - name: FLEET_MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: password
        - name: FLEET_REDIS_ADDRESS
          value: "redis.fleet.svc.cluster.local:6379"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: fleetdm
  namespace: fleet
spec:
  selector:
    app: fleetdm
  ports:
  - port: 443
    targetPort: 8080
  type: LoadBalancer
```

### 3. Enhanced osquery Package Creation

#### Custom osquery Build for FleetDM

```bash
# Create custom package build script
cat > /tmp/build_osquery_fleet.sh << 'EOF'
#!/bin/bash

BUILD_DIR="/tmp/osquery_fleet_build"
PACKAGE_DIR="/tmp/osquery_fleet_package"
VERSION="5.18.1-ancestry"

mkdir -p $BUILD_DIR $PACKAGE_DIR

# Build osquery with ancestry support
cd $BUILD_DIR
git clone https://github.com/osquery/osquery.git
cd osquery

# Apply ancestry patches (copy your implementation files)
cp /path/to/your/ancestry/files/* ./osquery/tables/events/linux/

# Build
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DOSQUERY_BUILD_TESTS=OFF ..
make -j$(nproc)

# Package for different distributions
cd $PACKAGE_DIR

# Create DEB package
mkdir -p osquery-fleet-${VERSION}/DEBIAN
mkdir -p osquery-fleet-${VERSION}/usr/bin
mkdir -p osquery-fleet-${VERSION}/etc/osquery
mkdir -p osquery-fleet-${VERSION}/etc/systemd/system

# Copy binaries
cp $BUILD_DIR/osquery/build/osquery/osqueryd osquery-fleet-${VERSION}/usr/bin/
cp $BUILD_DIR/osquery/build/osquery/osqueryi osquery-fleet-${VERSION}/usr/bin/

# Create DEB control file
cat > osquery-fleet-${VERSION}/DEBIAN/control << 'INNER_EOF'
Package: osquery-fleet
Version: 5.18.1-ancestry
Section: utils
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.17)
Maintainer: Your Organization <admin@company.com>
Description: osquery with process ancestry support for FleetDM
 Enhanced osquery build with process ancestry tracking capability
 designed for FleetDM fleet management.
INNER_EOF

# Create post-install script
cat > osquery-fleet-${VERSION}/DEBIAN/postinst << 'INNER_EOF'
#!/bin/bash
set -e

# Create osquery user
if ! id osquery >/dev/null 2>&1; then
    useradd --system --user-group --shell /bin/false osquery
fi

# Create directories
mkdir -p /var/log/osquery /var/osquery
chown -R osquery:osquery /var/log/osquery /var/osquery

# Set permissions
chmod +x /usr/bin/osqueryd
chmod +x /usr/bin/osqueryi

echo "osquery-fleet installation completed"
INNER_EOF

chmod +x osquery-fleet-${VERSION}/DEBIAN/postinst

# Build DEB package
dpkg-deb --build osquery-fleet-${VERSION}

# Create RPM spec
cat > osquery-fleet.spec << 'INNER_EOF'
Name:           osquery-fleet
Version:        5.18.1
Release:        ancestry
Summary:        osquery with process ancestry support for FleetDM

License:        Apache 2.0
URL:            https://osquery.io
BuildArch:      x86_64

%description
Enhanced osquery build with process ancestry tracking capability
designed for FleetDM fleet management.

%files
/usr/bin/osqueryd
/usr/bin/osqueryi

%post
if ! id osquery >/dev/null 2>&1; then
    useradd --system --user-group --shell /bin/false osquery
fi
mkdir -p /var/log/osquery /var/osquery
chown -R osquery:osquery /var/log/osquery /var/osquery
chmod +x /usr/bin/osqueryd
chmod +x /usr/bin/osqueryi

%clean
rm -rf $RPM_BUILD_ROOT
INNER_EOF

echo "Package build completed!"
echo "DEB package: $PACKAGE_DIR/osquery-fleet-${VERSION}.deb"
EOF

chmod +x /tmp/build_osquery_fleet.sh
```

### 4. FleetDM Configuration for Process Ancestry

#### Enhanced Fleet Configuration

```json
{
  "org_info": {
    "org_name": "Your Organization",
    "org_logo_url": "https://company.com/logo.png"
  },
  "server_settings": {
    "server_url": "https://fleet.company.com",
    "live_query_disabled": false,
    "enable_analytics": true,
    "deferred_save_host": false
  },
  "agent_options": {
    "config": {
      "options": {
        "logger_plugin": "tls",
        "pack_delimiter": "/",
        "logger_tls_period": "10",
        "distributed_plugin": "tls",
        "disable_distributed": false,
        "logger_tls_endpoint": "/api/osquery/log",
        "distributed_interval": "10",
        "distributed_tls_max_attempts": "3",
        "distributed_tls_read_endpoint": "/api/osquery/distributed/read",
        "distributed_tls_write_endpoint": "/api/osquery/distributed/write",
        "audit_allow_process_events": "true",
        "process_ancestry_cache_size": "2000",
        "process_ancestry_max_depth": "24",
        "process_ancestry_cache_ttl": "300"
      },
      "decorators": {
        "load": [
          "SELECT uuid AS host_uuid FROM system_info;",
          "SELECT hostname AS hostname FROM system_info;"
        ]
      }
    },
    "overrides": {
      "platforms": {
        "linux": {
          "options": {
            "audit_allow_process_events": "true",
            "process_ancestry_cache_size": "2000"
          }
        }
      }
    }
  }
}
```

#### Process Ancestry Queries and Policies

```yaml
# fleet_queries.yml
apiVersion: v1
kind: query
spec:
  name: "Process Events with Ancestry"
  description: "Collect process events with full ancestry information"
  query: |
    SELECT 
      pe.pid,
      pe.parent,
      pe.path,
      pe.cmdline,
      pe.ancestry,
      pe.time,
      pe.uid,
      pe.gid,
      pe.syscall,
      h.hostname,
      h.uuid as host_uuid
    FROM process_events pe
    JOIN system_info h
    WHERE pe.ancestry != '[]'
  interval: 300
  platform: "linux"
  min_osquery_version: "5.18.1"
  observer_can_run: true
  automations_enabled: true
  logging: "snapshot"

---
apiVersion: v1
kind: query
spec:
  name: "Suspicious Process Ancestry"
  description: "Detect suspicious process execution patterns using ancestry"
  query: |
    SELECT 
      pe.pid,
      pe.path,
      pe.cmdline,
      pe.ancestry,
      COUNT(*) as occurrence_count
    FROM process_events pe
    WHERE pe.ancestry != '[]'
      AND (
        pe.path LIKE '%/tmp/%' OR
        pe.path LIKE '%/var/tmp/%' OR
        pe.cmdline LIKE '%wget%' OR
        pe.cmdline LIKE '%curl%' OR
        pe.cmdline LIKE '%/bin/sh -c%'
      )
      AND pe.time > (strftime('%s', 'now') - 3600)
    GROUP BY pe.path, pe.cmdline
    HAVING occurrence_count > 5
  interval: 300
  platform: "linux"
  snapshot: true

---
apiVersion: v1
kind: policy
spec:
  name: "Unauthorized Binary Execution"
  description: "Alert on execution of binaries from unusual locations"
  query: |
    SELECT 1 
    FROM process_events 
    WHERE path NOT LIKE '/usr/%' 
      AND path NOT LIKE '/bin/%' 
      AND path NOT LIKE '/sbin/%'
      AND path NOT LIKE '/opt/%'
      AND ancestry != '[]'
      AND time > (strftime('%s', 'now') - 300)
  resolution: "Investigate the process and its ancestry chain"
  platform: "linux"
  critical: true
```

### 5. Migration Automation Scripts

#### Orbit Removal Script

```bash
cat > /tmp/remove_orbit.sh << 'EOF'
#!/bin/bash

echo "Removing Orbit agent..."

# Stop orbit service
systemctl stop orbit 2>/dev/null || service orbit stop 2>/dev/null

# Disable orbit service
systemctl disable orbit 2>/dev/null

# Backup orbit configuration
if [ -d "/opt/orbit" ]; then
    mkdir -p /tmp/orbit_backup
    cp -r /opt/orbit/* /tmp/orbit_backup/ 2>/dev/null
    echo "Orbit configuration backed up to /tmp/orbit_backup"
fi

# Remove orbit files
rm -rf /opt/orbit
rm -f /etc/systemd/system/orbit.service
rm -f /etc/init.d/orbit
rm -f /usr/bin/orbit
rm -f /usr/local/bin/orbit

# Remove orbit user (if exists)
if id orbit >/dev/null 2>&1; then
    userdel orbit 2>/dev/null
fi

# Reload systemd
systemctl daemon-reload 2>/dev/null

echo "Orbit removal completed"
EOF

chmod +x /tmp/remove_orbit.sh
```

#### FleetDM Agent Installation Script

```bash
cat > /tmp/install_fleet_agent.sh << 'EOF'
#!/bin/bash

FLEET_URL="${1:-https://fleet.company.com}"
ENROLL_SECRET="${2}"
PACKAGE_URL="${3:-https://github.com/fleetdm/fleet/releases/download/fleet-v4.44.0/fleet_v4.44.0_linux.tar.gz}"

if [ -z "$ENROLL_SECRET" ]; then
    echo "Usage: $0 <fleet_url> <enroll_secret> [package_url]"
    exit 1
fi

echo "Installing FleetDM agent..."
echo "Fleet URL: $FLEET_URL"

# Install dependencies
if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y curl ca-certificates
elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y curl ca-certificates
fi

# Download and install osquery with ancestry support
curl -O https://releases.company.com/osquery-fleet-5.18.1-ancestry.deb
dpkg -i osquery-fleet-5.18.1-ancestry.deb || apt-get install -f -y

# Create FleetDM configuration
mkdir -p /etc/osquery

cat > /etc/osquery/osquery.conf << INNER_EOF
{
  "options": {
    "config_plugin": "tls",
    "logger_plugin": "tls",
    "enroll_tls_endpoint": "/api/osquery/enroll",
    "config_tls_endpoint": "/api/osquery/config",
    "logger_tls_endpoint": "/api/osquery/log",
    "distributed_plugin": "tls",
    "distributed_interval": "10",
    "distributed_tls_max_attempts": "3",
    "distributed_tls_read_endpoint": "/api/osquery/distributed/read",
    "distributed_tls_write_endpoint": "/api/osquery/distributed/write",
    "tls_hostname": "$(echo $FLEET_URL | sed 's|https://||')",
    "enroll_secret_path": "/etc/osquery/enroll_secret",
    "host_identifier": "uuid",
    "utc": "true",
    "audit_allow_process_events": "true",
    "process_ancestry_cache_size": "2000",
    "process_ancestry_max_depth": "24",
    "process_ancestry_cache_ttl": "300",
    "logger_tls_period": "10"
  }
}
INNER_EOF

# Create enroll secret file
echo "$ENROLL_SECRET" > /etc/osquery/enroll_secret
chmod 600 /etc/osquery/enroll_secret

# Create systemd service
cat > /etc/systemd/system/osqueryd.service << 'INNER_EOF'
[Unit]
Description=osquery daemon
Documentation=https://osquery.io/
After=network.target syslog.service

[Service]
Type=simple
User=osquery
Group=osquery
ExecStart=/usr/bin/osqueryd
Restart=always
RestartSec=5
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
INNER_EOF

# Set permissions
chown -R osquery:osquery /etc/osquery
chmod 644 /etc/osquery/osquery.conf

# Enable and start service
systemctl daemon-reload
systemctl enable osqueryd
systemctl start osqueryd

# Verify enrollment
sleep 10
if systemctl is-active --quiet osqueryd; then
    echo "✓ osqueryd is running"
    echo "✓ FleetDM agent installation completed"
else
    echo "✗ osqueryd failed to start"
    systemctl status osqueryd
    exit 1
fi
EOF

chmod +x /tmp/install_fleet_agent.sh
```

### 6. Fleet Management Automation

#### Ansible Playbook for Fleet Migration

```yaml
# fleet_migration.yml
---
- name: Migrate from Orbit to FleetDM with Ancestry Support
  hosts: all
  become: yes
  vars:
    fleet_url: "{{ fleet_server_url }}"
    enroll_secret: "{{ fleet_enroll_secret }}"
    backup_dir: "/tmp/migration_backup_{{ ansible_date_time.epoch }}"
    
  tasks:
    - name: Create backup directory
      file:
        path: "{{ backup_dir }}"
        state: directory
        
    - name: Backup current configuration
      archive:
        path:
          - /opt/orbit
          - /etc/osquery
          - /var/osquery
        dest: "{{ backup_dir }}/pre_migration_backup.tar.gz"
        format: gz
        exclude_path:
          - "*.log"
        ignore_errors: yes
        
    - name: Stop and disable orbit
      systemd:
        name: orbit
        state: stopped
        enabled: no
      ignore_errors: yes
      
    - name: Stop existing osquery
      systemd:
        name: osqueryd
        state: stopped
      ignore_errors: yes
        
    - name: Remove orbit installation
      file:
        path: "{{ item }}"
        state: absent
      loop:
        - /opt/orbit
        - /etc/systemd/system/orbit.service
        - /usr/bin/orbit
        
    - name: Install osquery with ancestry support
      package:
        deb: "{{ osquery_ancestry_package_url }}"
        state: present
      when: ansible_os_family == "Debian"
      
    - name: Install osquery with ancestry support (RPM)
      yum:
        name: "{{ osquery_ancestry_package_url }}"
        state: present
      when: ansible_os_family == "RedHat"
        
    - name: Create FleetDM configuration
      template:
        src: osquery.conf.j2
        dest: /etc/osquery/osquery.conf
        owner: osquery
        group: osquery
        mode: '0644'
        backup: yes
        
    - name: Create enroll secret
      copy:
        content: "{{ enroll_secret }}"
        dest: /etc/osquery/enroll_secret
        owner: osquery
        group: osquery
        mode: '0600'
        
    - name: Enable and start osqueryd
      systemd:
        name: osqueryd
        state: started
        enabled: yes
        daemon_reload: yes
        
    - name: Verify osquery is running
      wait_for:
        timeout: 30
        delay: 5
        host: "{{ fleet_url.split('//')[1] }}"
        port: 443
        
    - name: Check enrollment status
      uri:
        url: "{{ fleet_url }}/api/v1/fleet/hosts"
        headers:
          Authorization: "Bearer {{ fleet_api_token }}"
        method: GET
      register: fleet_hosts
      delegate_to: localhost
      
    - name: Verify host enrolled
      assert:
        that:
          - fleet_hosts.json.hosts | selectattr('hostname', 'equalto', inventory_hostname) | list | length > 0
        fail_msg: "Host {{ inventory_hostname }} not found in Fleet"
        success_msg: "Host {{ inventory_hostname }} successfully enrolled"

  handlers:
    - name: restart osqueryd
      systemd:
        name: osqueryd
        state: restarted
```

#### Fleet API Integration Scripts

```bash
# Create Fleet API management script
cat > /opt/fleet/bin/fleet_api.sh << 'EOF'
#!/bin/bash

FLEET_URL="${FLEET_URL:-https://fleet.company.com}"
FLEET_TOKEN="${FLEET_TOKEN}"

if [ -z "$FLEET_TOKEN" ]; then
    echo "FLEET_TOKEN environment variable required"
    exit 1
fi

API_BASE="$FLEET_URL/api/v1/fleet"

# Function to make API calls
fleet_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer $FLEET_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$API_BASE$endpoint"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer $FLEET_TOKEN" \
            "$API_BASE$endpoint"
    fi
}

# Function to create ancestry-specific queries
create_ancestry_queries() {
    echo "Creating ancestry queries..."
    
    # Process Events with Ancestry query
    fleet_api POST "/queries" '{
        "name": "Process Events with Ancestry",
        "description": "Collect process events with full ancestry information",
        "query": "SELECT pe.pid, pe.parent, pe.path, pe.cmdline, pe.ancestry, pe.time FROM process_events pe WHERE pe.ancestry != '\''[]'\''",
        "interval": 300,
        "platform": "linux",
        "min_osquery_version": "5.18.1",
        "observer_can_run": true,
        "automations_enabled": true,
        "logging": "snapshot"
    }'
    
    # Suspicious Process Detection query
    fleet_api POST "/queries" '{
        "name": "Suspicious Process Ancestry Detection",
        "description": "Detect suspicious process execution patterns using ancestry",
        "query": "SELECT pe.pid, pe.path, pe.cmdline, pe.ancestry FROM process_events pe WHERE pe.ancestry != '\''[]'\'' AND (pe.path LIKE '\''%/tmp/%'\'' OR pe.cmdline LIKE '\''%wget%'\'' OR pe.cmdline LIKE '\''%curl%'\'')",
        "interval": 60,
        "platform": "linux",
        "snapshot": true
    }'
}

# Function to create policies
create_ancestry_policies() {
    echo "Creating ancestry policies..."
    
    fleet_api POST "/policies" '{
        "name": "Unauthorized Binary Execution",
        "description": "Alert on execution of binaries from unusual locations",
        "query": "SELECT 1 FROM process_events WHERE path NOT LIKE '\''/usr/%'\'' AND path NOT LIKE '\''/bin/%'\'' AND path NOT LIKE '\''/sbin/%'\'' AND ancestry != '\''[]'\''",
        "resolution": "Investigate the process and its ancestry chain",
        "platform": "linux",
        "critical": true
    }'
}

# Function to check host enrollment
check_enrollment() {
    echo "Checking host enrollment..."
    fleet_api GET "/hosts" | jq '.hosts[] | {hostname, status, osquery_version}'
}

# Function to run live query
run_live_query() {
    local query="$1"
    local host_ids="$2"
    
    if [ -z "$query" ]; then
        echo "Usage: run_live_query <query> [host_ids]"
        return 1
    fi
    
    if [ -z "$host_ids" ]; then
        # Get all host IDs
        host_ids=$(fleet_api GET "/hosts" | jq -r '.hosts[].id' | tr '\n' ',' | sed 's/,$//')
    fi
    
    fleet_api POST "/queries/run" "{
        \"query\": \"$query\",
        \"selected\": {
            \"hosts\": [$host_ids]
        }
    }"
}

# Main script logic
case "$1" in
    "setup")
        create_ancestry_queries
        create_ancestry_policies
        ;;
    "hosts")
        check_enrollment
        ;;
    "query")
        run_live_query "$2" "$3"
        ;;
    "test-ancestry")
        run_live_query "SELECT COUNT(*) as ancestry_events FROM process_events WHERE ancestry != '[]'"
        ;;
    *)
        echo "Usage: $0 {setup|hosts|query|test-ancestry}"
        echo "  setup        - Create ancestry queries and policies"
        echo "  hosts        - Check host enrollment status"
        echo "  query        - Run live query on hosts"
        echo "  test-ancestry - Test ancestry functionality"
        ;;
esac
EOF

chmod +x /opt/fleet/bin/fleet_api.sh
```

### 7. Monitoring and Alerting for FleetDM

#### Custom Fleet Webhooks

```python
#!/usr/bin/env python3
# fleet_webhook_handler.py

import json
import logging
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Configuration
SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
PAGERDUTY_URL = "https://events.pagerduty.com/v2/enqueue"
PAGERDUTY_ROUTING_KEY = "your-pagerduty-routing-key"

@app.route('/webhook/policy-violation', methods=['POST'])
def handle_policy_violation():
    """Handle policy violations from FleetDM"""
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'No data received'}), 400
    
    # Extract relevant information
    hostname = data.get('hostname', 'Unknown')
    policy_name = data.get('policy_name', 'Unknown Policy')
    violation_data = data.get('data', {})
    
    # Check if this is an ancestry-related violation
    if 'ancestry' in str(violation_data).lower():
        handle_ancestry_violation(hostname, policy_name, violation_data)
    
    return jsonify({'status': 'processed'}), 200

def handle_ancestry_violation(hostname, policy_name, violation_data):
    """Handle ancestry-specific policy violations"""
    message = f"""
    🚨 Process Ancestry Policy Violation
    
    Host: {hostname}
    Policy: {policy_name}
    
    Details:
    {json.dumps(violation_data, indent=2)}
    """
    
    # Send to Slack
    send_slack_alert(message)
    
    # Send to PagerDuty if critical
    if 'critical' in policy_name.lower() or 'unauthorized' in policy_name.lower():
        send_pagerduty_alert(hostname, policy_name, violation_data)

def send_slack_alert(message):
    """Send alert to Slack"""
    payload = {
        'text': message,
        'username': 'FleetDM',
        'icon_emoji': ':warning:'
    }
    
    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload)
        response.raise_for_status()
        logging.info("Slack alert sent successfully")
    except Exception as e:
        logging.error(f"Failed to send Slack alert: {e}")

def send_pagerduty_alert(hostname, policy_name, violation_data):
    """Send critical alert to PagerDuty"""
    payload = {
        'routing_key': PAGERDUTY_ROUTING_KEY,
        'event_action': 'trigger',
        'payload': {
            'summary': f'Critical Process Ancestry Violation on {hostname}',
            'source': hostname,
            'severity': 'critical',
            'component': 'osquery-ancestry',
            'group': 'security',
            'class': 'process-monitoring',
            'custom_details': {
                'policy': policy_name,
                'host': hostname,
                'violation_data': violation_data
            }
        }
    }
    
    try:
        response = requests.post(PAGERDUTY_URL, json=payload)
        response.raise_for_status()
        logging.info("PagerDuty alert sent successfully")
    except Exception as e:
        logging.error(f"Failed to send PagerDuty alert: {e}")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### 8. Performance Optimization for FleetDM

#### Fleet-Specific Configuration Tuning

```bash
# Create Fleet optimization script
cat > /opt/fleet/bin/optimize_fleet.sh << 'EOF'
#!/bin/bash

echo "Optimizing FleetDM for Process Ancestry..."

# Optimize database queries
mysql -h mysql.fleet.local -u fleet -p fleet << 'SQL'
-- Add indexes for ancestry queries
ALTER TABLE osquery_results ADD INDEX idx_ancestry_timestamp (timestamp);
ALTER TABLE osquery_results ADD INDEX idx_hostname_timestamp (hostname, timestamp);

-- Optimize table for faster inserts
ALTER TABLE osquery_results ENGINE=InnoDB ROW_FORMAT=COMPRESSED;

-- Create view for ancestry analysis
CREATE OR REPLACE VIEW process_ancestry_view AS
SELECT 
    hostname,
    JSON_EXTRACT(columns, '$.pid') as pid,
    JSON_EXTRACT(columns, '$.path') as path,
    JSON_EXTRACT(columns, '$.cmdline') as cmdline,
    JSON_EXTRACT(columns, '$.ancestry') as ancestry,
    timestamp
FROM osquery_results 
WHERE name = 'Process Events with Ancestry'
    AND JSON_EXTRACT(columns, '$.ancestry') != '[]';
SQL

# Optimize Fleet server configuration
cat > /etc/fleet/fleet.conf << 'INNER_EOF'
# Fleet server optimization for ancestry workloads
mysql_max_open_conns=50
mysql_max_idle_conns=10
mysql_conn_max_lifetime=3600

# Redis optimization
redis_pool_size=20
redis_idle_timeout=240

# Osquery result processing
osquery_result_log_file=/var/log/fleet/ancestry_results.log
osquery_status_log_file=/var/log/fleet/ancestry_status.log

# Rate limiting for ancestry queries
query_rate_limit=100
distributed_query_rate_limit=50

# Performance monitoring
enable_software_inventory=false
enable_host_expiry=true
host_expiry_enabled=true
host_expiry_window=30
INNER_EOF

echo "Fleet optimization completed!"
EOF

chmod +x /opt/fleet/bin/optimize_fleet.sh
```

### 9. Testing and Validation

#### Fleet Integration Test Suite

```bash
# Create Fleet integration test
cat > /opt/fleet/tests/test_ancestry_integration.sh << 'EOF'
#!/bin/bash

set -e

FLEET_URL="${FLEET_URL:-https://fleet.company.com}"
FLEET_TOKEN="${FLEET_TOKEN}"

echo "FleetDM Process Ancestry Integration Test"
echo "========================================"

# Test 1: Verify host enrollment
echo "Test 1: Host enrollment verification"
HOSTNAME=$(hostname)
HOST_INFO=$(curl -s -H "Authorization: Bearer $FLEET_TOKEN" \
    "$FLEET_URL/api/v1/fleet/hosts" | \
    jq -r ".hosts[] | select(.hostname == \"$HOSTNAME\")")

if [ -n "$HOST_INFO" ]; then
    echo "✓ Host enrolled successfully"
    HOST_ID=$(echo "$HOST_INFO" | jq -r '.id')
else
    echo "✗ Host not enrolled"
    exit 1
fi

# Test 2: Test ancestry query
echo "Test 2: Ancestry query execution"
QUERY_RESULT=$(curl -s -X POST \
    -H "Authorization: Bearer $FLEET_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"SELECT COUNT(*) as count FROM process_events WHERE ancestry != '[]'\", \"selected\": {\"hosts\": [$HOST_ID]}}" \
    "$FLEET_URL/api/v1/fleet/queries/run")

if echo "$QUERY_RESULT" | jq -e '.campaign.id' > /dev/null; then
    echo "✓ Ancestry query executed successfully"
    CAMPAIGN_ID=$(echo "$QUERY_RESULT" | jq -r '.campaign.id')
else
    echo "✗ Failed to execute ancestry query"
    exit 1
fi

# Test 3: Verify query results
echo "Test 3: Query results verification"
sleep 5  # Wait for query execution

RESULTS=$(curl -s -H "Authorization: Bearer $FLEET_TOKEN" \
    "$FLEET_URL/api/v1/fleet/campaigns/$CAMPAIGN_ID")

RESULT_COUNT=$(echo "$RESULTS" | jq -r '.campaign.hosts[0].rows[0].count // 0')

if [ "$RESULT_COUNT" -gt 0 ]; then
    echo "✓ Ancestry data found ($RESULT_COUNT events)"
else
    echo "⚠ No ancestry data found (may be normal for quiet systems)"
fi

# Test 4: Policy compliance check
echo "Test 4: Policy compliance verification"
POLICIES=$(curl -s -H "Authorization: Bearer $FLEET_TOKEN" \
    "$FLEET_URL/api/v1/fleet/policies")

ANCESTRY_POLICIES=$(echo "$POLICIES" | jq -r '.policies[] | select(.name | contains("Ancestry") or contains("ancestry")) | .name')

if [ -n "$ANCESTRY_POLICIES" ]; then
    echo "✓ Ancestry policies found:"
    echo "$ANCESTRY_POLICIES" | sed 's/^/  /'
else
    echo "⚠ No ancestry policies configured"
fi

echo "Integration test completed successfully!"
EOF

chmod +x /opt/fleet/tests/test_ancestry_integration.sh
```

## Migration Checklist

### Pre-Migration

- [ ] Backup all Orbit configurations and data
- [ ] Test osquery with ancestry support in lab environment
- [ ] Set up FleetDM server infrastructure
- [ ] Create enrollment packages with ancestry-enabled osquery
- [ ] Document current Orbit queries and convert to FleetDM format
- [ ] Plan migration timeline and rollback procedures

### During Migration

- [ ] Deploy FleetDM to pilot group (10 hosts)
- [ ] Verify ancestry functionality on pilot hosts
- [ ] Monitor performance and resource usage
- [ ] Test live queries and policies
- [ ] Validate data collection and storage
- [ ] Document any issues and resolutions

### Post-Migration

- [ ] Remove Orbit agents from all systems
- [ ] Clean up old configuration files and services
- [ ] Optimize FleetDM queries for ancestry data
- [ ] Set up monitoring and alerting
- [ ] Train security team on new FleetDM interface
- [ ] Update documentation and runbooks

This comprehensive FleetDM integration guide ensures a smooth transition from Orbit to FleetDM while maximizing the benefits of the new process ancestry functionality.
