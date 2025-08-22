# osquery Process Ancestry Sensor - DEB Packaging Guide

This guide walks you through creating, testing, and distributing DEB packages for your enhanced osquery sensor with process ancestry tracking.

## 🚀 Quick Start

### Option 1: Build and Package (One Command)
```bash
chmod +x build_and_package.sh
./build_and_package.sh
```

### Option 2: Step-by-Step Process
```bash
# 1. Build osquery (if not already built)
mkdir build && cd build
cmake -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DOSQUERY_BUILD_BPF=OFF -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
      -DOSQUERY_BUILD_TESTS=OFF -DOSQUERY_BUILD_AWS=OFF \
      -DOSQUERY_BUILD_DPKG=ON ..
make -j$(nproc)
cd ..

# 2. Create DEB package
chmod +x create_deb_package.sh
./create_deb_package.sh

# 3. Test the package
chmod +x test_deb_package.sh
sudo ./test_deb_package.sh
```

## 📦 Package Contents

The DEB package includes:

### Binaries
- `/usr/bin/osqueryd` - Enhanced osquery daemon with ancestry support
- `/usr/bin/osqueryi` - Interactive osquery shell

### Configuration
- `/etc/osquery/osquery.conf.example` - Example configuration with ancestry settings
- `/etc/osquery/osquery.flags.example` - Example flags file
- `/etc/systemd/system/osqueryd.service` - Systemd service file

### Documentation
- `/usr/share/doc/osquery-ancestry-sensor/README.md` - Complete documentation
- `/usr/share/doc/osquery-ancestry-sensor/copyright` - License information

### Runtime Directories
- `/var/osquery/` - Database and runtime files (owned by osquery user)
- `/var/log/osquery/` - Log files (owned by osquery user)

## 🔧 Package Configuration

### Key Features
- **Package Name**: `osquery-ancestry-sensor`
- **Version**: `5.18.1-ancestry-1.0`
- **Architecture**: `amd64`
- **Dependencies**: Minimal system dependencies (libc6, libssl, etc.)

### Security Features
- Dedicated `osquery` system user
- Secure file permissions
- Systemd service hardening
- No privileged operations required

### Process Ancestry Settings
- **Cache Size**: 1000 entries (configurable)
- **Max Depth**: 32 levels (configurable)
- **Cache TTL**: 300 seconds (configurable)

## 🧪 Testing Your Package

### 1. Package Integrity Test
```bash
./test_deb_package.sh
```

### 2. Manual Installation Test
```bash
# Install
sudo dpkg -i packaging/osquery-ancestry-sensor_*.deb
sudo apt-get install -f  # Fix any dependency issues

# Configure
sudo cp /etc/osquery/osquery.conf.example /etc/osquery/osquery.conf
sudo cp /etc/osquery/osquery.flags.example /etc/osquery/osquery.flags

# Start service
sudo systemctl enable osqueryd
sudo systemctl start osqueryd

# Test functionality
sudo osqueryi "SELECT * FROM osquery_info;"
sudo osqueryi "SELECT COUNT(*) FROM process_events WHERE ancestry != '[]';"

# Check service status
sudo systemctl status osqueryd
```

### 3. Ancestry Feature Validation
```bash
# Generate some test processes
bash -c 'sleep 2' &

# Query ancestry data
sudo osqueryi "SELECT pid, parent, ancestry, cmdline FROM process_events WHERE ancestry != '[]' ORDER BY time DESC LIMIT 3;"

# Check ancestry column exists
sudo osqueryi "SELECT name FROM pragma_table_info('process_events') WHERE name='ancestry';"
```

## 📤 Distribution Methods

### 1. Direct Distribution
```bash
# Copy to target systems
scp packaging/osquery-ancestry-sensor_*.deb user@target-system:/tmp/

# Install on target
ssh user@target-system
sudo dpkg -i /tmp/osquery-ancestry-sensor_*.deb
sudo apt-get install -f
```

### 2. APT Repository Setup

#### Create Repository Structure
```bash
mkdir -p repo/dists/stable/main/binary-amd64
mkdir -p repo/pool/main/o/osquery-ancestry-sensor

# Copy package
cp packaging/osquery-ancestry-sensor_*.deb repo/pool/main/o/osquery-ancestry-sensor/

# Generate Packages file
cd repo
dpkg-scanpackages pool/ /dev/null | gzip -9c > dists/stable/main/binary-amd64/Packages.gz
dpkg-scanpackages pool/ /dev/null > dists/stable/main/binary-amd64/Packages

# Create Release file
cat > dists/stable/Release << EOF
Origin: Your Organization
Label: osquery Ancestry Sensor Repository
Suite: stable
Codename: stable
Version: 1.0
Architectures: amd64
Components: main
Description: Enhanced osquery with process ancestry tracking
Date: $(date -Ru)
MD5Sum:
 $(md5sum dists/stable/main/binary-amd64/Packages.gz | cut -d' ' -f1) $(stat --printf="%s" dists/stable/main/binary-amd64/Packages.gz) main/binary-amd64/Packages.gz
 $(md5sum dists/stable/main/binary-amd64/Packages | cut -d' ' -f1) $(stat --printf="%s" dists/stable/main/binary-amd64/Packages) main/binary-amd64/Packages
SHA256:
 $(sha256sum dists/stable/main/binary-amd64/Packages.gz | cut -d' ' -f1) $(stat --printf="%s" dists/stable/main/binary-amd64/Packages.gz) main/binary-amd64/Packages.gz
 $(sha256sum dists/stable/main/binary-amd64/Packages | cut -d' ' -f1) $(stat --printf="%s" dists/stable/main/binary-amd64/Packages) main/binary-amd64/Packages
EOF
```

#### Client Configuration
```bash
# Add repository to client systems
echo "deb [trusted=yes] http://your-repo-server/repo stable main" | sudo tee /etc/apt/sources.list.d/osquery-ancestry.list

# Update and install
sudo apt update
sudo apt install osquery-ancestry-sensor
```

### 3. Enterprise Distribution

#### Ansible Deployment
```yaml
---
- name: Deploy osquery Ancestry Sensor
  hosts: all
  become: yes
  tasks:
    - name: Copy DEB package
      copy:
        src: osquery-ancestry-sensor_5.18.1-ancestry-1.0_amd64.deb
        dest: /tmp/osquery-ancestry-sensor.deb
    
    - name: Install package
      apt:
        deb: /tmp/osquery-ancestry-sensor.deb
        state: present
    
    - name: Copy configuration
      copy:
        src: osquery.conf
        dest: /etc/osquery/osquery.conf
        owner: root
        group: root
        mode: '0644'
    
    - name: Enable and start service
      systemd:
        name: osqueryd
        enabled: yes
        state: started
```

#### Docker Deployment
```dockerfile
FROM ubuntu:20.04

# Install package
COPY osquery-ancestry-sensor_*.deb /tmp/
RUN apt-get update && \
    dpkg -i /tmp/osquery-ancestry-sensor_*.deb || true && \
    apt-get install -f -y && \
    rm /tmp/osquery-ancestry-sensor_*.deb

# Add configuration
COPY osquery.conf /etc/osquery/osquery.conf

# Run as non-root
USER osquery
CMD ["/usr/bin/osqueryd", "--flagfile=/etc/osquery/osquery.flags"]
```

## 📊 Configuration Examples

### Basic Configuration
```json
{
  "options": {
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem",
    "audit_allow_process_events": "true",
    "process_ancestry_cache_size": "1000",
    "process_ancestry_max_depth": "32",
    "process_ancestry_cache_ttl": "300"
  },
  "events": {
    "enable_subscribers": ["process_events"],
    "enable_publishers": ["auditeventpublisher"]
  }
}
```

### FleetDM Integration
```json
{
  "options": {
    "config_plugin": "tls",
    "logger_plugin": "tls",
    "enroll_tls_endpoint": "/api/osquery/enroll",
    "config_tls_endpoint": "/api/osquery/config",
    "logger_tls_endpoint": "/api/osquery/log",
    "audit_allow_process_events": "true",
    "process_ancestry_cache_size": "2000",
    "process_ancestry_max_depth": "24"
  }
}
```

### High-Volume Environment
```json
{
  "options": {
    "process_ancestry_cache_size": "5000",
    "process_ancestry_max_depth": "16",
    "process_ancestry_cache_ttl": "120",
    "logger_tls_period": "5"
  }
}
```

## 🔍 Troubleshooting

### Common Issues

#### Package Installation Fails
```bash
# Check dependencies
sudo apt-get install -f

# Force install if needed
sudo dpkg -i --force-depends package.deb
```

#### Service Won't Start
```bash
# Check configuration
sudo osqueryd --config_check --config_path=/etc/osquery/osquery.conf

# Check logs
sudo journalctl -u osqueryd -f

# Verify permissions
sudo chown -R osquery:osquery /var/osquery /var/log/osquery
```

#### No Ancestry Data
```bash
# Check audit system
sudo auditctl -s

# Stop conflicting services
sudo systemctl stop auditd

# Verify configuration
grep -i ancestry /etc/osquery/osquery.conf
```

### Performance Monitoring
```bash
# Check memory usage
ps aux | grep osqueryd

# Monitor cache performance
sudo osqueryi "SELECT cache_hits, cache_misses FROM process_ancestry_cache_stats;"

# Check service status
sudo systemctl status osqueryd
```

## 📈 Version Management

### Updating the Package
```bash
# 1. Modify version in create_deb_package.sh
# VERSION="5.18.1-ancestry-1.1"

# 2. Rebuild package
./create_deb_package.sh

# 3. Test new package
sudo ./test_deb_package.sh

# 4. Distribute update
```

### Changelog Management
Keep track of changes in `/usr/share/doc/osquery-ancestry-sensor/changelog`:

```
osquery-ancestry-sensor (5.18.1-ancestry-1.1) stable; urgency=medium

  * Improved cache performance
  * Fixed race condition handling
  * Updated documentation

 -- Your Organization <admin@company.com>  Mon, 20 Jan 2025 10:00:00 +0000
```

## 🎯 Best Practices

### 1. Testing
- Always test packages before distribution
- Validate on clean Ubuntu systems
- Test upgrade scenarios

### 2. Security
- Sign packages with GPG for production
- Use secure distribution channels
- Regular security updates

### 3. Monitoring
- Monitor deployment success rates
- Track sensor performance metrics
- Set up alerting for failures

### 4. Documentation
- Maintain clear installation guides
- Document configuration options
- Provide troubleshooting steps

## 📞 Support

For issues with packaging or distribution:
1. Check the troubleshooting section above
2. Review logs: `sudo journalctl -u osqueryd`
3. Test with minimal configuration
4. Open issues at: https://github.com/saidhfm/osquery-test-sai/issues

---

**Ready to distribute your enhanced osquery sensor!** 🚀
