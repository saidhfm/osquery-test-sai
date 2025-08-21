# Build Fix for Process Ancestry Implementation

## Issue: eBPF Build Errors

The error you're seeing is because CMake is trying to build eBPF components that we don't need for our implementation.

**Our implementation uses:**
- ✅ Audit subsystem (auditd) - already in osquery
- ✅ /proc filesystem traversal  
- ✅ LRU caching system
- ❌ NOT eBPF

## Solution: Disable eBPF Build

Run these commands on your EC2 instance:

```bash
# Navigate to build directory
cd ~/osquery-build/osquery

# Clean previous build attempt
rm -rf build
mkdir build && cd build

# Configure CMake WITHOUT eBPF components
cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_BPF=OFF \
  -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=ON \
  -DOSQUERY_BUILD_DPKG=ON \
  ..

# Build osquery (this should work now)
make -j$(nproc)
```

## Why This Fixes the Issue

### The Error Was Caused By:
- CMake trying to build `osquery/experimental/experiments/linuxevents/`
- This includes eBPF components that require:
  - `libclangParse.a` (Clang development libraries)
  - Additional kernel headers
  - eBPF toolchain

### Our Implementation Doesn't Need:
- eBPF kernel modules
- Clang parsing libraries  
- Experimental Linux events
- BPF socket events

### What We Actually Use:
- Standard osquery audit events (`process_events` table)
- /proc filesystem access (standard Linux)
- C++ caching implementation
- Existing audit subsystem

## Alternative: Install Missing Dependencies (Not Recommended)

If you want to build with eBPF anyway (though unnecessary):

```bash
# Install Clang development libraries
sudo apt-get update
sudo apt-get install -y \
  clang-13 \
  clang-13-dev \
  libclang-13-dev \
  llvm-13 \
  llvm-13-dev \
  libbpf-dev

# Install missing headers
sudo apt-get install -y \
  linux-headers-$(uname -r) \
  libc6-dev

# Then rebuild
```

**But this is unnecessary for our implementation!**

## Recommended Build Configuration

```bash
#!/bin/bash
# build_ancestry_osquery.sh

echo "Building osquery with Process Ancestry support (NO eBPF)"

# Ensure we're in the right directory
cd ~/osquery-build/osquery

# Clean build
rm -rf build
mkdir build && cd build

# Configure with minimal dependencies
cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_BPF=OFF \
  -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=ON \
  -DOSQUERY_BUILD_DPKG=ON \
  -DOSQUERY_TOOLCHAIN_SYSROOT=/usr/local/osquery-toolchain \
  ..

echo "Starting build (this may take 30-45 minutes)..."
make -j$(nproc)

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Binary location: $(pwd)/osquery/osqueryd"
    echo "Test with: ./osquery/osqueryi --version"
else
    echo "❌ Build failed"
    exit 1
fi
```

## Verify Our Implementation is Included

After successful build, verify our ancestry code is included:

```bash
# Check if our files are in the build
find build -name "*ancestry*" -type f

# Should show our compiled object files:
# build/.../process_ancestry_cache.cpp.o

# Test the binary
./osquery/osqueryi "SELECT name FROM pragma_table_info('process_events') WHERE name = 'ancestry';"
# Should return: ancestry
```

## Summary

The build error occurred because:
1. ✅ **Default osquery build** includes experimental eBPF components
2. ❌ **eBPF requires** additional dependencies we don't need  
3. ✅ **Our implementation** uses standard audit + /proc + caching
4. ✅ **Solution**: Disable eBPF build with `-DOSQUERY_BUILD_BPF=OFF`

This is actually **better** because:
- Faster build time (no eBPF compilation)
- Fewer dependencies  
- More reliable across different Linux versions
- Exactly what our design intended

Run the fixed cmake command and your build should complete successfully!
