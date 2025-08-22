# 🚀 osquery Ancestry Sensor - Installation Guide

## 📦 Package Information

- **Package**: `osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb`
- **Size**: 61MB (includes compiled ancestry functionality)
- **Architecture**: amd64 (Intel/AMD 64-bit)
- **Compatible**: Ubuntu 22.04+, Debian 11+
- **Features**: Process ancestry tracking with LRU cache and JSON output

## ⚡ Quick Installation

### Single Machine Deployment
```bash
# 1. Copy package to Ubuntu machine
scp osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb user@server:~/

# 2. Install on Ubuntu machine
sudo dpkg -i osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb

# 3. Verify installation
sudo systemctl status osqueryd
sudo osqueryi "SELECT pid, parent, ancestry FROM process_events LIMIT 3;"
```

### Automated Deployment
```bash
# Use the provided deployment script
./deploy_ancestry_sensor.sh
```

## 📋 Detailed Installation Steps

### Prerequisites
- Ubuntu 22.04+ or Debian 11+
- amd64 architecture
- Sudo/root access
- Network connectivity (for dependencies)

### Step 1: System Preparation
```bash
# Update system packages
sudo apt update

# Install any missing dependencies (usually not needed)
sudo apt install -y libaudit1 libssl3 libsqlite3-0
```

### Step 2: Package Installation
```bash
# Install the DEB package
sudo dpkg -i osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb

# If dependency issues occur, fix them
sudo apt-get install -f -y
```

### Step 3: Service Configuration
```bash
# The package automatically:
# ✅ Creates osquery user/group
# ✅ Sets up directories with proper permissions
# ✅ Installs systemd service
# ✅ Configures audit events and process monitoring
# ✅ Starts the service

# Verify service status
sudo systemctl status osqueryd
```

### Step 4: Functionality Verification
```bash
# Check if process_events table is available
sudo osqueryi "SELECT name FROM osquery_registry WHERE registry='table' AND name='process_events';"

# Test ancestry functionality
sudo osqueryi "SELECT pid, parent, ancestry FROM process_events WHERE pid > 0 LIMIT 5;"

# Check for ancestry column specifically
sudo osqueryi "PRAGMA table_info(process_events);" | grep ancestry
```

## 🔧 Configuration

### Default Configuration Location
- **Config File**: `/etc/osquery/osquery.conf`
- **Log Directory**: `/var/log/osquery/`
- **Database**: `/var/osquery/osquery.db`

### Ancestry-Specific Settings
The package includes pre-configured settings for optimal ancestry tracking:

```json
{
  "options": {
    "audit_allow_process_events": "true",
    "audit_allow_config": "true",
    "disable_audit": "false",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "32",
    "process_ancestry_cache_ttl": "300"
  }
}
```

### Custom Configuration
```bash
# Edit configuration
sudo nano /etc/osquery/osquery.conf

# Restart service after changes
sudo systemctl restart osqueryd
```

## 🧪 Testing & Validation

### Basic Functionality Test
```bash
# Test 1: Service health
sudo systemctl is-active osqueryd

# Test 2: Basic queries
sudo osqueryi "SELECT version FROM osquery_info;"

# Test 3: Process events
sudo osqueryi "SELECT COUNT(*) FROM process_events;"

# Test 4: Ancestry data
sudo osqueryi "SELECT pid, parent, JSON_EXTRACT(ancestry, '$[0].exe_name') as root_process FROM process_events WHERE ancestry != '[]' LIMIT 3;"
```

### Performance Validation
```bash
# Check resource usage
sudo systemctl status osqueryd --no-pager
sudo journalctl -u osqueryd --no-pager -n 50

# Monitor real-time logs
sudo journalctl -u osqueryd -f
```

### Advanced Testing
```bash
# Test ancestry chain depth
sudo osqueryi "SELECT pid, JSON_ARRAY_LENGTH(ancestry) as ancestry_depth FROM process_events WHERE ancestry != '[]' ORDER BY ancestry_depth DESC LIMIT 5;"

# Test specific process ancestry
sudo osqueryi "SELECT pid, parent, JSON_PRETTY(ancestry) FROM process_events WHERE name = 'bash' AND ancestry != '[]' LIMIT 1;"
```

## 🚨 Troubleshooting

### Common Issues

#### Service Not Starting
```bash
# Check service status
sudo systemctl status osqueryd --no-pager

# Check logs
sudo journalctl -u osqueryd --no-pager -n 50

# Common fix: permissions
sudo chown -R osquery:osquery /var/log/osquery /var/osquery /etc/osquery
```

#### No Process Events
```bash
# Check audit system
sudo auditctl -l

# Verify configuration
sudo osqueryi "SELECT value FROM osquery_flags WHERE name='audit_allow_process_events';"

# Restart with debug
sudo systemctl stop osqueryd
sudo /usr/bin/osqueryd --verbose --config_path=/etc/osquery/osquery.conf
```

#### Empty Ancestry Data
```bash
# This is normal for:
# - Short-lived processes
# - System startup
# - High-frequency process creation

# Wait a few minutes for data collection
# Check with more specific queries
sudo osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';"
```

### Log Analysis
```bash
# View recent logs
sudo journalctl -u osqueryd --since "1 hour ago"

# Filter for ancestry-related logs
sudo journalctl -u osqueryd | grep -i ancestry

# Check for errors
sudo journalctl -u osqueryd | grep -i error
```

## 📊 Usage Examples

### Security Monitoring
```sql
-- Processes with deep ancestry chains (potential privilege escalation)
SELECT pid, name, JSON_ARRAY_LENGTH(ancestry) as chain_length, ancestry 
FROM process_events 
WHERE JSON_ARRAY_LENGTH(ancestry) > 5 
ORDER BY chain_length DESC;

-- Processes spawned by suspicious parents
SELECT pid, parent, name, JSON_EXTRACT(ancestry, '$[0].exe_name') as root_process
FROM process_events 
WHERE JSON_EXTRACT(ancestry, '$[0].exe_name') IN ('nc', 'netcat', 'bash', 'sh');
```

### System Analysis
```sql
-- Most active parent processes
SELECT parent, COUNT(*) as child_count, 
       GROUP_CONCAT(DISTINCT name) as child_types
FROM process_events 
GROUP BY parent 
ORDER BY child_count DESC 
LIMIT 10;

-- Process creation timeline with ancestry
SELECT datetime(time, 'unixepoch') as timestamp, 
       pid, parent, name, 
       JSON_EXTRACT(ancestry, '$[0].exe_name') as root_ancestor
FROM process_events 
ORDER BY time DESC 
LIMIT 20;
```

## 🔄 Maintenance

### Regular Tasks
```bash
# Weekly: Check service health
sudo systemctl status osqueryd

# Monthly: Review logs for errors
sudo journalctl -u osqueryd --since "30 days ago" | grep -i error

# As needed: Restart service
sudo systemctl restart osqueryd
```

### Updates
```bash
# To update: install new DEB package
sudo dpkg -i new-osquery-ancestry-sensor-version.deb
sudo systemctl restart osqueryd
```

### Removal
```bash
# Complete removal
sudo apt remove --purge osquery-ancestry-sensor
sudo rm -rf /etc/osquery /var/log/osquery /var/osquery
```

## 📞 Support

### Package Information
- **Version**: 5.18.1-ancestry-1.0
- **Architecture**: amd64
- **Dependencies**: libc6, libaudit1, libssl3, libsqlite3-0

### Key Features Included
- ✅ Process ancestry tracking with JSON output
- ✅ LRU cache for performance optimization
- ✅ Enhanced timing information (proc_time, proc_time_hr)
- ✅ Race condition handling for short-lived processes
- ✅ Security-hardened systemd service
- ✅ Comprehensive audit event configuration

### Documentation
- Configuration: `/etc/osquery/osquery.conf`
- Logs: `sudo journalctl -u osqueryd`
- Official osquery docs: https://osquery.io/

## 🎯 Success Indicators

Your installation is successful when:
- ✅ `systemctl status osqueryd` shows "active (running)"
- ✅ `sudo osqueryi "SELECT * FROM process_events LIMIT 1;"` returns data
- ✅ Process events contain ancestry column with JSON data
- ✅ No errors in `sudo journalctl -u osqueryd`

**🎉 Congratulations! Your production osquery ancestry sensor is ready!**
