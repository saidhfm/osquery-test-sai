# AWS EC2 Testing Guide for Process Ancestry Implementation

## Overview

This guide provides step-by-step instructions for testing the Linux process ancestry implementation on AWS EC2 instances. It covers hardware requirements, instance setup, deployment, and comprehensive testing procedures.

## Hardware Requirements

### Recommended EC2 Instance Types

| Instance Type | vCPU | Memory | Network | Use Case |
|---------------|------|--------|---------|----------|
| **t3.medium** | 2 | 4 GiB | Up to 5 Gbps | Basic testing |
| **t3.large** | 2 | 8 GiB | Up to 5 Gbps | Standard testing |
| **c5.large** | 2 | 4 GiB | Up to 10 Gbps | Performance testing |
| **c5.xlarge** | 4 | 8 GiB | Up to 10 Gbps | Load testing |
| **m5.xlarge** | 4 | 16 GiB | Up to 10 Gbps | High-volume testing |

### Minimum Requirements

- **vCPU**: 2 cores minimum
- **Memory**: 4 GiB minimum (8 GiB recommended)
- **Storage**: 20 GiB gp3 SSD minimum
- **Network**: Enhanced networking enabled

### Storage Configuration

```bash
# Recommended EBS configuration
- Root Volume: 20 GiB gp3 (3000 IOPS, 125 MB/s)
- Data Volume: 50 GiB gp3 (3000 IOPS, 125 MB/s) for logs and testing data
```

## Instance Setup

### 1. Launch EC2 Instance

#### Using AWS CLI

```bash
# Create security group
aws ec2 create-security-group \
    --group-name osquery-testing \
    --description "Security group for osquery testing"

# Add SSH access
aws ec2 authorize-security-group-ingress \
    --group-name osquery-testing \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Launch instance
aws ec2 run-instances \
    --image-id ami-0c55b159cbfafe1d0 \
    --count 1 \
    --instance-type t3.large \
    --key-name your-key-pair \
    --security-groups osquery-testing \
    --block-device-mappings '[
        {
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": 20,
                "VolumeType": "gp3",
                "Iops": 3000,
                "Throughput": 125,
                "DeleteOnTermination": true
            }
        }
    ]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=osquery-ancestry-test}]'
```

#### Using AWS Console

1. Navigate to EC2 Dashboard
2. Click "Launch Instance"
3. Select Amazon Linux 2 AMI or Ubuntu 20.04 LTS
4. Choose instance type (t3.large recommended)
5. Configure instance details:
   - Enable detailed monitoring
   - Enable enhanced networking
6. Add storage as specified above
7. Add tags: Name=osquery-ancestry-test
8. Configure security group (SSH access)
9. Launch with your key pair

### 2. Initial Instance Configuration

#### Connect to Instance

```bash
# For Amazon Linux 2
ssh -i your-key-pair.pem ec2-user@<instance-ip>

# For Ubuntu
ssh -i your-key-pair.pem ubuntu@<instance-ip>
```

#### Update System

```bash
# Amazon Linux 2
sudo yum update -y
sudo yum groupinstall -y "Development Tools"
sudo yum install -y cmake git wget curl htop

# Ubuntu
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential cmake git wget curl htop
```

#### Install Dependencies

```bash
# Install required packages for osquery compilation
# Amazon Linux 2
sudo yum install -y \
    boost-devel \
    bzip2-devel \
    openssl-devel \
    readline-devel \
    rpm-devel \
    rpm-build \
    libuuid-devel \
    libarchive-devel \
    libedit-devel \
    clang \
    clang-devel

# Ubuntu
sudo apt install -y \
    libboost-all-dev \
    libbz2-dev \
    libssl-dev \
    libreadline-dev \
    libuuid1 \
    libarchive-dev \
    libedit-dev \
    pkg-config \
    clang-13 \
    clang++-13 \
    libc++-13-dev \
    libc++abi-13-dev

# Set Clang as default compiler (Ubuntu)
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/clang-13 100
sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-13 100

# Verify compiler
cc --version | head -1
# Should show: clang version 13.x.x
```

## Building and Deploying osquery

### 1. Prepare Build Environment

```bash
# Create working directory
mkdir -p ~/osquery-build
cd ~/osquery-build

# Clone the repository (or upload your modified version)
git clone https://github.com/osquery/osquery.git
cd osquery
git clone --branch 5.18.1 --depth 1 https://github.com/osquery/osquery.git


# Apply your ancestry implementation
# (Copy your modified files to the appropriate locations)
```
Modified Files:
vi specs/posix/process_events.table - Added ancestry column

vi osquery/tables/events/linux/process_events.h - Added ancestry include

vi osquery/tables/events/linux/process_events.cpp - Integrated ancestry logic

vi osquery/tables/events/CMakeLists.txt - Added new source file

New Implementation Files:
vi osquery/tables/events/linux/process_ancestry_cache.h - Interface definitions
vi osquery/tables/events/linux/process_ancestry_cache.cpp - Core implementation


vi editor
ggdg
I
paste code
esc
:wq

```bash

# OPTION 1: Source-level fix (Recommended for build issues)
# Backup the original CMakeLists.txt
cp osquery/CMakeLists.txt osquery/CMakeLists.txt.backup

# Comment out the experimental directory line
sed -i 's/add_subdirectory("experimental")/# add_subdirectory("experimental")/' osquery/CMakeLists.txt

# Verify the change
grep -n "experimental" osquery/CMakeLists.txt
# Should show: # add_subdirectory("experimental")

echo "✅ Experimental eBPF components disabled at source level"


sudo apt-get update
sudo apt-get install -y clang-13 clang++-13 libc++-13-dev libc++abi-13-dev

# 2. Set Clang as default
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/clang-13 100
sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-13 100

# 3. Verify Clang is active
cc --version
# Should show: clang version 13.x.x

# 4. Clean and rebuild
cd ~/osquery-build/osquery/build

# 1. Clean everything completely
make clean

# 2. Remove all CMake cache and generated files
rm -rf CMakeFiles/
rm -rf CMakeCache.txt
rm -rf ns_*
rm -rf *.cmake

# 3. Go back to source directory and regenerate fresh build
cd ~/osquery-build/osquery
rm -rf build
mkdir build
cd build

jump to # CMake configuration with explicit Clang compiler
# 5. Fix libaudit header conflict (common on newer Ubuntu)
# Find and fix the problematic header
-----------
troubleshoot steps:

cd ~/osquery-build/osquery
HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)
echo "Fixing header: $HEADER"
 Backup and fix the circular definition
cp "$HEADER" "$HEADER.backup"
sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$HEADER"
# 3. Add proper definition
echo -e '\n#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif' >> "$HEADER"
# 4. Verify fix
grep -A2 -B2 "AUDIT_FILTER_EXCLUDE" "$HEADER"
# Continue build
cd build
make -j1

# 6. Fix Thrift random_shuffle conflict (C++11+ compatibility)
cd ~/osquery-build/osquery

# Find the Thrift header
THRIFT_HEADER=$(find . -name "random_shuffle.h" -path "*/thrift/patches/*" | head -1)
echo "Found: $THRIFT_HEADER"

# Apply the fix
cp "$THRIFT_HEADER" "$THRIFT_HEADER.backup"
cat > "$THRIFT_HEADER" << 'EOF'
#pragma once
#ifndef OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#define OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#include <algorithm>
#include <random>
#if __cplusplus >= 201703L || !defined(__GLIBCXX__)
template<class RandomIt>
void random_shuffle(RandomIt first, RandomIt last) {
    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(first, last, g);
}
#endif
#endif
EOF

# 7. Fix OpenSSL utils memcpy issue (missing cstring header)
cd ~/osquery-build/osquery
OPENSSL_FILE="osquery/tables/system/posix/openssl_utils.cpp"
cp "$OPENSSL_FILE" "$OPENSSL_FILE.backup"
sed -i '/#include.*<string/a #include <cstring>' "$OPENSSL_FILE"

# 8. Fix sysctl header issue (sys/sysctl.h not found on newer Linux)
SYSCTL_HEADER=$(find . -name "sysctl_utils.h" -path "*/posix/*" | head -1)
echo "Fixing header: $SYSCTL_HEADER"
cp "$SYSCTL_HEADER" "$SYSCTL_HEADER.backup"

finally this code is working - complete_sysctl_utils_fix.sh
#9.
cd ~/osquery-build/osquery
./docs/complete_ancestry_implementation.sh
#10.
chmod +x /Users/sainaga.b/Documents/osquery-5.18.1/docs/fix_build_directory.sh

git clone osquery
./docs/complete_sysctl_utils_fix.sh
./docs/fix_build_directory.sh
make -j$(nproc)

---------------------------------------------
# Sync process_ancestry_cache.h
scp -i "$KEY_PATH" \
  "$LOCAL_PATH/osquery/tables/events/linux/process_ancestry_cache.h" \
  ubuntu@$SERVER_IP:$REMOTE_PATH/osquery/tables/events/linux/

# Sync process_ancestry_cache.cpp
scp -i "$KEY_PATH" \
  "$LOCAL_PATH/osquery/tables/events/linux/process_ancestry_cache.cpp" \
  ubuntu@$SERVER_IP:$REMOTE_PATH/osquery/tables/events/linux/
SERVER_IP="52.23.176.240"   
KEY_PATH="/Users/sainaga.b/Downloads/sai.pem"
LOCAL_PATH="/Users/sainaga.b/Documents/osquery-5.18.1" 
REMOTE_PATH="~/osquery-build/osquery"


### 2. Build osquery
# Note: build directory already created above

# CMake configuration with explicit Clang compiler
# If you used the source fix above, you can use simpler cmake flags:
cmake \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=ON \
  -DOSQUERY_BUILD_DPKG=ON \
  ..

# OR if you didn't use the source fix, use these flags: best
cmake \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_BPF=OFF \
  -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=OFF \
  -DOSQUERY_BUILD_DPKG=ON \
  ..

cmake -DOSQUERY_BUILD_AWS=OFF
# Build osquery (this may take 30-60 minutes)
# Note: libaudit header fix was applied above to prevent common errors
# For memory-constrained instances, use single-threaded build:
make -j4

cd ~/osquery-build/osquery/build

# 2. Clean previous build
make clean

# 3. Remove and regenerate CMake cache (important for new files)
cd ~/osquery-build/osquery
rm -rf build
mkdir build
cd build



# For instances with sufficient memory (4GB+), use parallel build:
make -j$(nproc)

# If build fails with libaudit or memory errors, see troubleshooting section below

# Verify build
# Find our custom-built osquery binaries
ls -la ~/osquery-build/osquery/build/osquery/osqueryd
ls -la ~/os

```Stop any existing osquery processes
sudo pkill -f osquery
sudo systemctl stop auditd


# Update the config file to explicitly enable the audit publisher
# Create/update the config file
sudo tee /etc/osquery/osquery.conf << 'EOF'
{
  "options": {
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem", 
    "logger_path": "/var/log/osquery",
    "database_path": "/var/osquery/osquery.db",
    "utc": "true",
    "audit_allow_process_events": "true",
    "audit_allow_config": "true", 
    "disable_audit": "false",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "32",
    "process_ancestry_cache_ttl": "300",
    "verbose": "true"
  },
  "events": {
    "disable_publishers": [],
    "disable_subscribers": [],
    "enable_subscribers": ["process_events"],
    "enable_publishers": ["auditeventpublisher"]
  }
}
EOF

# Start your custom osqueryd (in background)
# Kill the current daemon
sudo pkill -f osqueryd

# Check if auditd is running and stop it
sudo systemctl status auditd
sudo systemctl stop auditd

# Run with proper audit permissions
sudo ~/osquery-build/osquery/build/osquery/osqueryd \
  --config_path=/etc/osquery/osquery.conf \
  --disable_watchdog \
  --verbose \
  --audit_allow_process_events=true \
  --audit_allow_config=true \
  --disable_audit=false \
  --daemonize=false &

# Wait a few seconds for it to initialize
sleep 5
-------------------------------------------
to start osquery that comes by default:
# Install built binary
sudo make install


# 2. Test the ancestry feature
sudo osqueryi or sudo /opt/osquery/bin/osqueryi
# Or add to PATH for convenience
export PATH="/opt/osquery/bin:$PATH"
sudo osqueryi

SELECT pid, parent, ancestry FROM process_events LIMIT 5;
---------------------------------------

another way:
# Create osquery user and directories
sudo mkdir -p /etc/osquery /var/log/osquery /var/osquery
sudo useradd --system --user-group --shell /bin/false osquery
sudo chown -R osquery:osquery /var/log/osquery /var/osquery /etc/osquery 2>/dev/null || echo "osquery user doesn't exist, using root"
sudo chmod 755 /var/log/osquery /var/osquery /etc/osquery

sudo pkill -f osquery
sudo rm -f /var/osquery/*.pid /var/osquery/osquery.em /root/.osquery/shell.em*

# Try starting osqueryd again
sudo ~/osquery-build/osquery/build/osquery/osqueryd \
  --daemonize=false \
  --disable_watchdog \
  --audit_allow_process_events=true \
  --audit_allow_config=true \
  --disable_audit=false \
  --process_ancestry_cache_size=1000 \
  --process_ancestry_max_depth=32 \
  --process_ancestry_cache_ttl=300 \
  --verbose

sleep 3600  # best

in another terminal:
sleep 2 &
ls -la /tmp
ps aux | head -5
echo "Test process ancestry" 

or

bash -c 'sleep 3 &'
sudo bash -c 'sleep 4 &'
python3 -c 'import time; time.sleep(2)' &


in another terminal
sudo ~/osquery-build/osquery/build/osquery/osqueryi \
  --connect /var/osquery/osquery.em

# Test the ancestry feature with existing events
SELECT pid, parent, ancestry FROM process_events WHERE pid > 0 LIMIT 5;
# Check the schema to confirm ancestry column exists
.schema process_events
# Check if the audit publisher is active
SELECT * FROM osquery_events WHERE name = 'auditeventpublisher';
# Then back in osqueryi:
SELECT pid, parent, ancestry, cmdline FROM process_events WHERE pid > 0 ORDER BY time DESC LIMIT 5;
# Test specific ancestry queries
SELECT pid, parent, ancestry FROM process_events WHERE cmdline LIKE '%sleep%';
SELECT pid, parent, ancestry, cmdline FROM process_events WHERE time > (SELECT MAX(time) - 60 FROM process_events) ORDER BY time DESC LIMIT 10;


**Note**: No schedule needed! `process_events` is an **event-driven table** that captures events in real-time as they occur through the Linux audit subsystem.

#### Create Service File

**Why is this required?** 🤔

The systemd service file is **essential** for proper osquery deployment because:

1. ✅ **Daemon Management**: osquery needs to run as a background daemon continuously
2. ✅ **Auto-Start**: Ensures osquery starts automatically on system boot/reboot  
3. ✅ **Process Monitoring**: Automatically restarts if osquery crashes
4. ✅ **Security**: Runs under dedicated `osquery` user (not root)
5. ✅ **Event Capture**: **Critical for process_events** - must be always running to capture audit events
6. ✅ **Resource Management**: Proper logging and resource limits
7. ✅ **Production Ready**: Standard deployment practice for server applications

**Without the service file:**
- ❌ osquery stops when SSH session ends
- ❌ No automatic restart on crashes  
- ❌ Manual start required after reboots
- ❌ **Missing process events** when daemon is down
- ❌ Not suitable for production use

```bash
sudo tee /etc/systemd/system/osqueryd.service << 'EOF'
[Unit]
Description=osquery daemon
Documentation=https://osquery.io/
After=network.target

[Service]
Type=simple
User=osquery
Group=osquery
ExecStart=/usr/local/bin/osqueryd
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

**Key Service Configuration Explained:**

| Setting | Purpose | Why Important |
|---------|---------|---------------|
| `User=osquery` | Security isolation | Prevents privilege escalation |
| `Restart=always` | Auto-recovery | Ensures continuous monitoring |
| `After=network.target` | Dependency management | Starts after network is ready |
| `WantedBy=multi-user.target` | Boot integration | Auto-starts on system boot |
| `StandardOutput=journal` | Centralized logging | Integrates with system logs |

#### Enable and Start Service

**Service Management Commands Explained:**

```bash
# 1. Reload systemd to recognize new service file
sudo systemctl daemon-reload

# 2. Enable auto-start on boot (critical for production)
sudo systemctl enable osqueryd

# 3. Start the service immediately
sudo systemctl start osqueryd

# 4. Verify service is running and healthy
sudo systemctl status osqueryd
```

**What each command does:**

| Command | Purpose | Result |
|---------|---------|--------|
| `daemon-reload` | Tells systemd about new service file | Service becomes available |
| `enable` | Configures auto-start on boot | Survives server reboots |
| `start` | Starts the daemon immediately | osquery begins monitoring |
| `status` | Shows health and recent logs | Verify everything works |

**Expected status output:**
```
● osqueryd.service - osquery daemon
   Loaded: loaded (/etc/systemd/system/osqueryd.service; enabled; vendor preset: enabled)
   Active: active (running) since [timestamp]
   Main PID: [process-id] (osqueryd)
   ...
```

**Why this matters for process_events:**
- 🎯 **osquery must be running** to capture audit events
- 🎯 **Any downtime = missed events** (no historical replay)
- 🎯 **Auto-restart ensures continuous monitoring**

## Testing Procedures

### 1. Basic Functionality Test

#### Test 1: Verify Ancestry Column Exists

```bash
# Interactive mode test (needs sudo for process_events)
sudo osqueryi

# Check schema
.schema process_events

# Verify ancestry column exists
SELECT name FROM pragma_table_info('process_events') WHERE name = 'ancestry';

# Exit osqueryi
.exit
```

#### Test 2: Basic Ancestry Query

```bash
# Monitor events in real-time (run this in a separate terminal)
echo "🔍 Monitor process events in real-time:"
echo "tail -f /var/log/osquery/osqueryd.results.log | grep process_events"
echo ""

# Generate test processes
echo "Creating test processes..."
bash -c 'echo "Test process started"; sleep 2' &

# Wait a moment for events to be captured
sleep 3

# Query recent process events with ancestry
sudo osqueryi "SELECT pid, parent, path, cmdline, LEFT(ancestry, 100) as ancestry_preview FROM process_events ORDER BY time DESC LIMIT 5;"
```

#### Test 2.5: Simple Real-Time Test

```bash
# Simple test to verify events are flowing
echo "🧪 Testing real-time event capture..."

# Start a background monitoring process
(while true; do 
    echo "Monitor check: $(date)"
    sudo osqueryi "SELECT COUNT(*) as recent_events FROM process_events WHERE time > strftime('%s', 'now', '-30 seconds');" 2>/dev/null | tail -1
    sleep 5
done) &
MONITOR_PID=$!

# Generate some test activity
for i in {1..3}; do
    echo "Test iteration $i"
    bash -c "echo 'Ancestry test $i - PID: $$'; sleep 1" &
    sleep 2
done

# Stop monitoring
sleep 5
kill $MONITOR_PID 2>/dev/null || true

echo "✅ Real-time test completed"
```

### 2. Functional Testing

#### Test 3: Deep Process Hierarchy

```bash
# Create test script for deep hierarchy
cat > /tmp/test_hierarchy.sh << 'EOF'
#!/bin/bash
DEPTH=${1:-5}
echo "Starting Level $DEPTH - PID: $$"
if [ $DEPTH -gt 0 ]; then
    /tmp/test_hierarchy.sh $((DEPTH - 1))
else
    echo "Leaf process reached - PID: $$"
    sleep 5
fi
EOF

chmod +x /tmp/test_hierarchy.sh

# Start monitoring before running test
echo "Starting hierarchy test..."
/tmp/test_hierarchy.sh 5 &

# Wait for hierarchy to complete
wait

# Query for events from our test script
sudo osqueryi "SELECT pid, parent, path, LEFT(ancestry, 200) as ancestry_preview FROM process_events WHERE path LIKE '%test_hierarchy.sh%' ORDER BY time DESC LIMIT 5;"
```

#### Test 4: Cache Performance Test

```bash
# Test cache performance with burst of processes
echo "Testing cache performance with process burst..."

# Generate many processes quickly to test caching
for i in {1..50}; do
    bash -c "echo 'Cache test process $i'; sleep 0.5" &
done

# Wait for processes to complete
wait

# Query events and measure response time
echo "Measuring query performance..."
time sudo osqueryi "SELECT COUNT(*) FROM process_events WHERE cmdline LIKE '%Cache test process%';"

# Test repeated queries (should hit cache)
time sudo osqueryi "SELECT COUNT(*) FROM process_events WHERE cmdline LIKE '%Cache test process%';"
```

### 3. Performance Testing

#### Test 5: Load Testing

```bash
# Create load test script
cat > /tmp/load_test.sh << 'EOF'
#!/bin/bash
for i in {1..1000}; do
    bash -c "echo Process $i; sleep 0.1" &
    if [ $((i % 100)) -eq 0 ]; then
        echo "Started $i processes"
        wait
    fi
done
EOF

chmod +x /tmp/load_test.sh

# Run load test
time /tmp/load_test.sh

# Monitor system resources
htop
```

#### Test 6: Memory Usage Monitoring

```bash
# Monitor memory usage during testing
cat > /tmp/monitor_memory.sh << 'EOF'
#!/bin/bash
while true; do
    echo "$(date): $(ps aux | grep osqueryd | grep -v grep | awk '{print $6}')" >> /tmp/memory_usage.log
    sleep 5
done
EOF

chmod +x /tmp/monitor_memory.sh
/tmp/monitor_memory.sh &
MONITOR_PID=$!

# Run your tests here

# Stop monitoring
kill $MONITOR_PID
```

### 4. Configuration Testing

#### Test 7: Cache Size Limits

```bash
# Test with different cache sizes
sudo systemctl stop osqueryd

# Small cache
sudo sed -i 's/"process_ancestry_cache_size": "1000"/"process_ancestry_cache_size": "10"/' /etc/osquery/osquery.conf
sudo systemctl start osqueryd

# Generate load and test cache behavior
# (Run Test 5 again)

# Check logs for cache evictions
sudo journalctl -u osqueryd | grep -i cache
```

#### Test 8: Depth Limits

```bash
# Test with different depth limits
sudo systemctl stop osqueryd

# Shallow depth
sudo sed -i 's/"process_ancestry_max_depth": "32"/"process_ancestry_max_depth": "3"/' /etc/osquery/osquery.conf
sudo systemctl start osqueryd

# Run deep hierarchy test (Test 3) and verify depth limiting
```

### 5. Error Handling Testing

#### Test 9: Missing Process Information

```bash
# Create process that quickly exits
echo "Testing quick-exit process handling..."
bash -c 'echo "Quick exit process $$"' > /tmp/quick_exit_test.log &

# Wait for process to exit
sleep 1

# Query for events from quick-exit processes
sudo osqueryi "SELECT pid, parent, path, ancestry FROM process_events WHERE cmdline LIKE '%Quick exit process%' ORDER BY time DESC LIMIT 3;"

# Check if ancestry was captured even for short-lived processes
cat /tmp/quick_exit_test.log
```

#### Test 10: Permission Issues

```bash
# Test with restricted permissions
sudo chmod 600 /proc/*/stat
sudo chmod 600 /proc/*/cmdline

# Run tests and check error handling
# Restore permissions
sudo chmod 644 /proc/*/stat
sudo chmod 644 /proc/*/cmdline
```

## Validation and Verification

### 1. Data Validation

#### Validate JSON Structure

```bash
# Extract and validate JSON
sudo osqueryi "SELECT ancestry FROM process_events LIMIT 10;" | \
    tail -n +2 | \
    while read line; do
        if [ -n "$line" ] && [ "$line" != "[]" ]; then
            echo "$line" | python3 -m json.tool || echo "Invalid JSON: $line"
        fi
    done
```

#### Validate Ancestry Chain

```bash
# Check ancestry consistency
sudo osqueryi "
SELECT 
    pid,
    parent,
    ancestry,
    CASE 
        WHEN ancestry = '[]' THEN 'No ancestry data'
        WHEN json_valid(ancestry) = 1 THEN 'Valid JSON'
        ELSE 'Invalid JSON'
    END as validation_status
FROM process_events 
WHERE ancestry IS NOT NULL
LIMIT 10;
"
```

### 2. Performance Validation

#### Cache Hit Rate Analysis

```bash
# Check cache statistics (if implemented)
sudo osqueryi "SELECT * FROM osquery_flags WHERE name LIKE '%ancestry%';"

# Analyze log patterns
sudo journalctl -u osqueryd | grep -E "(cache|ancestry)" | \
    grep -E "(hit|miss)" | \
    awk '{print $NF}' | \
    sort | uniq -c
```

#### Response Time Analysis

```bash
# Measure query response times
for i in {1..5}; do
    echo "Query attempt $i:"
    time sudo osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';"
done
```

## Monitoring and Alerting

### 1. CloudWatch Integration

```bash
# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/osquery/osqueryd.results.log",
                        "log_group_name": "/aws/ec2/osquery/results",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/osquery/osqueryd.INFO",
                        "log_group_name": "/aws/ec2/osquery/info",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent
```

### 2. Custom Metrics

```bash
# Create custom metric script
cat > /tmp/osquery_metrics.sh << 'EOF'
#!/bin/bash
NAMESPACE="osquery/ancestry"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Get process event count
EVENT_COUNT=$(sudo osqueryi "SELECT COUNT(*) FROM process_events;" | tail -1)

# Send to CloudWatch
aws cloudwatch put-metric-data \
    --namespace "$NAMESPACE" \
    --metric-data \
        MetricName=ProcessEventCount,Value=$EVENT_COUNT,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID
EOF

chmod +x /tmp/osquery_metrics.sh

# Add to crontab
echo "*/5 * * * * /tmp/osquery_metrics.sh" | crontab -
```

## Troubleshooting

### Common Build Issues

#### 1. **Compiler Flag Errors**
```
error: unrecognized command-line option '-Qunused-arguments'
```
**Solution:** Install and use Clang (fixed in dependencies section above)

#### 2. **libaudit Header Conflict**
```
error: use of undeclared identifier 'AUDIT_FILTER_EXCLUDE'
```
**Solution:** Already handled in build steps above, but if you encounter it:
```bash
cd ~/osquery-build/osquery
HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)
cp "$HEADER" "$HEADER.backup"
sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$HEADER"
echo -e '\n#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif' >> "$HEADER"
cd build && make -j1
```

#### 2.5. **Thrift random_shuffle Conflict**
```
error: redefinition of 'random_shuffle'
```
**Solution:** Already handled in build steps above, but if you encounter it:
```bash
cd ~/osquery-build/osquery
THRIFT_HEADER=$(find . -name "random_shuffle.h" -path "*/thrift/patches/*" | head -1)
cp "$THRIFT_HEADER" "$THRIFT_HEADER.backup"
cat > "$THRIFT_HEADER" << 'EOF'
#pragma once
#ifndef OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#define OSQUERY_THRIFT_RANDOM_SHUFFLE_H
#include <algorithm>
#include <random>
#if __cplusplus >= 201703L || !defined(__GLIBCXX__)
template<class RandomIt>
void random_shuffle(RandomIt first, RandomIt last) {
    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(first, last, g);
}
#endif
#endif
EOF
cd build && make -j1
```

#### 2.6. **OpenSSL Utils memcpy Error**
```
error: no member named 'memcpy' in namespace 'std'
```
**Solution:** Already handled in build steps above, but if you encounter it:
```bash
cd ~/osquery-build/osquery
OPENSSL_FILE="osquery/tables/system/posix/openssl_utils.cpp"
cp "$OPENSSL_FILE" "$OPENSSL_FILE.backup"
sed -i '/#include.*<string/a #include <cstring>' "$OPENSSL_FILE"
cd build && make -j1
```

#### 2.7. **Missing sys/sysctl.h Header** 
```
fatal error: 'sys/sysctl.h' file not found
use of undeclared identifier 'CTL_MAXNAME'
```
**Solution:** Use the complete sysctl utils fix (fixes all issues):
```bash
cd ~/osquery-build/osquery
./docs/complete_sysctl_utils_fix.sh
```

**Alternative manual fix** (if script doesn't work):
```bash
cd ~/osquery-build/osquery
# Fix ALL sysctl files (source + generated in build directory)
find . -name "sysctl_utils.h" -type f | while read file; do
    cp "$file" "$file.backup"
    echo "Fixing: $file"
    # Apply comprehensive fix to each file
done
cd build && make -j1
```

#### 3. **Memory/Resource Issues**
```
make: *** [Makefile:136: all] Error 2
```
**Solutions:**
- Use single-threaded build: `make -j1`
- Add swap if memory < 4GB
- Check disk space: `df -h /`
- Monitor memory: `free -h`

#### 4. **eBPF Build Errors**
```
Could not find clangParse_path using the following names: libclangParse.a
```
**Solution:** Source-level fix already applied above, but verify:
```bash
grep -n "experimental" ~/osquery-build/osquery/osquery/CMakeLists.txt
# Should show: # add_subdirectory("experimental")
```

### Runtime Issues

1. **Permission Issues**
   - Ensure osquery user has proper permissions
   - Check /proc filesystem accessibility
   - Verify audit subsystem configuration

2. **Performance Issues**
   - Adjust cache settings based on workload
   - Monitor memory usage and adjust instance size
   - Check for filesystem I/O bottlenecks

3. **Missing Ancestry Data**
   - Verify process_events configuration
   - Check audit events are being generated
   - Ensure processes aren't exiting too quickly

### Debug Commands

```bash
# Check system resources
free -h && df -h / && echo "CPU cores: $(nproc)"

# Verbose build output
make -j1 VERBOSE=1

# Check for system errors
dmesg | tail -20
journalctl --since "10 minutes ago" | grep -i error

# Verify osquery functionality
./osquery/osqueryi "SELECT COUNT(*) FROM osquery_info;"
./osquery/osqueryi "SELECT name FROM pragma_table_info('process_events') WHERE name='ancestry';"
```

### Log Analysis

```bash
# Check osquery logs
sudo journalctl -u osqueryd -f

# Check specific ancestry-related logs
sudo journalctl -u osqueryd | grep -i ancestry

# Check system logs for audit events
sudo journalctl -u auditd -f
```

## Cleanup

### 1. Stop Services

```bash
sudo systemctl stop osqueryd
sudo systemctl stop amazon-cloudwatch-agent
sudo systemctl disable osqueryd
sudo systemctl disable amazon-cloudwatch-agent
```

### 2. Remove Test Data

```bash
rm -f /tmp/test_hierarchy.sh
rm -f /tmp/load_test.sh
rm -f /tmp/monitor_memory.sh
rm -f /tmp/osquery_metrics.sh
rm -f /tmp/memory_usage.log
```

### 3. Terminate Instance

```bash
# Using AWS CLI
aws ec2 terminate-instances --instance-ids <instance-id>

# Or through AWS Console
```

## Cost Optimization

### Instance Scheduling

```bash
# Create scripts to start/stop instances for testing
# Start instance
aws ec2 start-instances --instance-ids <instance-id>

# Stop instance
aws ec2 stop-instances --instance-ids <instance-id>
```

### Spot Instances

For cost-effective testing, consider using spot instances:

```bash
aws ec2 request-spot-instances \
    --spot-price "0.05" \
    --instance-count 1 \
    --type "one-time" \
    --launch-specification '{
        "ImageId": "ami-0c55b159cbfafe1d0",
        "InstanceType": "t3.large",
        "KeyName": "your-key-pair",
        "SecurityGroups": ["osquery-testing"]
    }'
```

This comprehensive testing guide ensures thorough validation of the process ancestry implementation on AWS EC2, covering all aspects from basic functionality to performance and reliability testing.
