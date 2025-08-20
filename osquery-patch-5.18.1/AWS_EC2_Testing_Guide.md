# AWS EC2 Testing Guide for Process Ancestry Feature

## Overview

This guide provides step-by-step instructions for testing the process ancestry feature in osquery on AWS EC2 instances.

## Prerequisites

- AWS account with EC2 access
- Basic knowledge of Linux command line
- Understanding of osquery basics

## Environment Setup

### 1. Launch EC2 Instance

```bash
# Launch Ubuntu 20.04 LTS instance
aws ec2 run-instances \
    --image-id ami-0885b1f6bd170450c \
    --instance-type t3.medium \
    --key-name your-key-pair \
    --security-group-ids sg-your-security-group \
    --subnet-id subnet-your-subnet \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=osquery-ancestry-test}]'
```

**Instance Requirements:**
- **Instance Type**: t3.medium or larger (2 vCPU, 4GB RAM minimum)
- **OS**: Ubuntu 20.04 LTS or Amazon Linux 2
- **Storage**: 20GB minimum
- **Security Groups**: SSH (port 22) access

### 2. Connect to Instance

```bash
ssh -i your-key.pem ubuntu@your-ec2-public-ip
```

### 3. Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install build dependencies
sudo apt install -y \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    libssl-dev \
    liblzma-dev \
    libzstd-dev \
    libbz2-dev \
    libsnappy-dev \
    libsqlite3-dev \
    ninja-build

# Install osquery build dependencies
sudo apt install -y \
    libaudit-dev \
    libdpkg-dev \
    libudev-dev \
    uuid-dev \
    libcryptsetup-dev
```

## Building osquery with Ancestry Feature

### 1. Clone and Build

```bash
# Clone the repository (with your changes)
git clone /path/to/your/osquery-fork osquery-ancestry
cd osquery-ancestry

# Configure build
mkdir build && cd build
cmake \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DOSQUERY_BUILD_TESTS=ON \
    ..

# Build osquery
ninja -j$(nproc)
```

### 2. Verify Build

```bash
# Check if osquery built successfully
./osquery/osqueryi --version

# Verify ancestry column exists
./osquery/osqueryi --json "PRAGMA table_info(process_events);" | jq '.[] | select(.name=="ancestry")'
```

## Testing Process Ancestry

### 1. Basic Functionality Test

```bash
# Start osquery daemon with process events enabled
sudo ./osquery/osqueryd \
    --config_path=/dev/null \
    --logger_path=/tmp/osquery \
    --audit_allow_process_events=true \
    --process_events_enable_ancestry=true \
    --process_events_max_ancestry_depth=10 \
    --audit_allow_fork_process_events=true \
    --verbose &

# Wait for startup
sleep 5

# Create a test process hierarchy
bash -c 'sleep 30 &'
```

### 2. Query Process Events

```bash
# Query recent process events with ancestry
./osquery/osqueryi --json "
SELECT 
    pid,
    parent,
    path,
    cmdline,
    ancestry,
    time
FROM process_events 
WHERE time > (strftime('%s', 'now') - 60)
ORDER BY time DESC 
LIMIT 10;" | jq '.'
```

### 3. Verify Ancestry Data Structure

```bash
# Test ancestry JSON structure
./osquery/osqueryi --json "
SELECT 
    pid,
    json_extract(ancestry, '$.depth') as ancestry_depth,
    json_extract(ancestry, '$.truncated') as truncated,
    json_extract(ancestry, '$.ancestors') as ancestors
FROM process_events 
WHERE ancestry != '{}' 
LIMIT 5;" | jq '.'
```

## Performance Testing

### 1. Load Testing

```bash
# Create a script to generate process load
cat > process_load_test.sh << 'EOF'
#!/bin/bash
for i in {1..100}; do
    (
        sleep 0.1
        bash -c 'echo "test process $i"'
    ) &
done
wait
EOF

chmod +x process_load_test.sh

# Monitor system resources during test
top -p $(pgrep osqueryd) &
./process_load_test.sh
```

### 2. Memory Usage Monitoring

```bash
# Monitor osquery memory usage
sudo cat > memory_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    ps aux | grep osqueryd | grep -v grep | awk '{print strftime("%Y-%m-%d %H:%M:%S"), "Memory:", $6/1024 "MB", "CPU:", $3"%"}'
    sleep 10
done
EOF

chmod +x memory_monitor.sh
./memory_monitor.sh &
```

### 3. Log Analysis

```bash
# Analyze osquery logs for performance issues
tail -f /tmp/osquery/osqueryd.results.log | jq '.columns.ancestry' | head -20

# Check for any error messages
grep -i "ancestry\|error" /tmp/osquery/osqueryd.INFO
```

## Configuration Testing

### 1. Test Configuration Flags

```bash
# Test with ancestry disabled
sudo ./osquery/osqueryd \
    --config_path=/dev/null \
    --logger_path=/tmp/osquery-no-ancestry \
    --audit_allow_process_events=true \
    --process_events_enable_ancestry=false \
    --verbose &

# Verify ancestry column is empty
./osquery/osqueryi "SELECT ancestry FROM process_events LIMIT 5;"
```

### 2. Test Depth Limiting

```bash
# Test with limited depth
sudo ./osquery/osqueryd \
    --config_path=/dev/null \
    --logger_path=/tmp/osquery-limited \
    --audit_allow_process_events=true \
    --process_events_enable_ancestry=true \
    --process_events_max_ancestry_depth=3 \
    --verbose &

# Create deep process hierarchy
bash -c 'bash -c "bash -c \"bash -c \\\"bash -c \\\\\\\"sleep 10\\\\\\\"\\\"\"" &'
```

## Edge Case Testing

### 1. Rapid Process Creation

```bash
# Test rapid process creation/termination
for i in {1..50}; do
    (sleep 0.01; exit) &
done
```

### 2. Long-Running Processes

```bash
# Test with long-running background processes
nohup sleep 3600 &
nohup python3 -c "import time; time.sleep(3600)" &
```

### 3. Process Tree Monitoring

```bash
# Monitor the actual process tree
pstree -p $$ | head -20

# Compare with ancestry data
./osquery/osqueryi --json "
SELECT pid, json_extract(ancestry, '$.ancestors[0].pid') as parent_from_ancestry 
FROM process_events 
WHERE pid = '$$';" | jq '.'
```

## Data Validation

### 1. Ancestry Accuracy Verification

```bash
# Create verification script
cat > verify_ancestry.sh << 'EOF'
#!/bin/bash
PID=$$
echo "Current PID: $PID"
echo "Parent PID: $PPID"

# Get ancestry from osquery
ANCESTRY=$(./osquery/osqueryi --json "SELECT ancestry FROM process_events WHERE pid='$PID' ORDER BY time DESC LIMIT 1;" | jq -r '.[0].ancestry')

echo "Ancestry from osquery: $ANCESTRY"

# Get actual parent chain
CURRENT=$PID
echo "Actual parent chain:"
while [ $CURRENT -gt 1 ]; do
    PARENT=$(ps -o ppid= -p $CURRENT | tr -d ' ')
    echo "PID: $CURRENT -> Parent: $PARENT"
    CURRENT=$PARENT
    if [ $CURRENT -eq 1 ]; then break; fi
done
EOF

chmod +x verify_ancestry.sh
./verify_ancestry.sh
```

### 2. JSON Validation

```bash
# Validate JSON structure of ancestry data
./osquery/osqueryi --json "SELECT ancestry FROM process_events WHERE ancestry != '{}' LIMIT 10;" | \
jq '.[] | .ancestry | fromjson | {depth: .depth, truncated: .truncated, ancestor_count: (.ancestors | length)}'
```

## Troubleshooting

### Common Issues

1. **No Process Events Generated**
   ```bash
   # Check audit system
   sudo auditctl -l
   
   # Ensure audit daemon is running
   sudo systemctl status auditd
   ```

2. **Empty Ancestry Data**
   ```bash
   # Check flag configuration
   ./osquery/osqueryi "SELECT value FROM osquery_flags WHERE name LIKE '%ancestry%';"
   ```

3. **Performance Issues**
   ```bash
   # Check system load
   uptime
   iostat 1 5
   
   # Monitor osquery process
   sudo strace -p $(pgrep osqueryd) -e trace=openat,read
   ```

### Log Analysis

```bash
# Check osquery logs for ancestry-related messages
grep -i ancestry /tmp/osquery/osqueryd.INFO
grep -i "process.*event" /tmp/osquery/osqueryd.INFO | tail -10

# Monitor real-time log output
tail -f /tmp/osquery/osqueryd.results.log | jq 'select(.columns.ancestry != "{}")'
```

## Cleanup

```bash
# Stop osquery
sudo pkill osqueryd

# Clean up test files
rm -f process_load_test.sh memory_monitor.sh verify_ancestry.sh
rm -rf /tmp/osquery*

# Terminate EC2 instance (when done)
aws ec2 terminate-instances --instance-ids i-your-instance-id
```

## Success Criteria

✅ **Build Success**: osquery compiles without errors  
✅ **Feature Availability**: ancestry column exists in process_events table  
✅ **Data Generation**: Process events generate non-empty ancestry JSON  
✅ **JSON Validity**: Ancestry data is valid JSON with expected structure  
✅ **Performance**: No significant performance degradation during normal operation  
✅ **Configuration**: Flags properly control ancestry behavior  
✅ **Error Handling**: System remains stable with malformed or missing process data  

## Next Steps

After successful EC2 testing, proceed to:
1. Production scaling tests (see Production_Testing_Guide.md)
2. FleetDM integration (see FleetDM_Integration_Guide.md)
3. Long-term stability testing
