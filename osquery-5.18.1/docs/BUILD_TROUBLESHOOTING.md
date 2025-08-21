# Build Troubleshooting Guide

## Current Status: ✅ Progress! 

Your build is **working now** - you can see:
- ✅ Clang compiler fix successful
- ✅ Libraries building (thirdparty_util-linux completed)
- ✅ 5% progress achieved
- ❌ Failing at the end with generic error

## Common Causes & Solutions 🔧

### 1. **Memory Issues** (Most Likely)

Large parallel builds can exhaust memory:

```bash
# Check current memory usage
free -h
htop  # Press 'q' to quit

# If memory is low, try single-threaded build
cd ~/osquery-build/osquery/build
make -j1  # Single thread - slower but uses less memory

# Or reduce parallelism
make -j2  # Use only 2 cores instead of all cores
```

### 2. **Get Detailed Error Messages**

The error might be hiding in the verbose output:

```bash
# Build with verbose output to see actual error
make -j1 VERBOSE=1

# Or redirect output to see what failed
make -j$(nproc) 2>&1 | tee build.log
tail -50 build.log  # See last 50 lines with actual error
```

### 3. **System Resource Check**

```bash
# Check available resources
echo "Memory:"
free -h

echo "Disk space:"
df -h /

echo "CPU cores:"
nproc

echo "Swap:"
swapon --show
```

**Recommended minimums:**
- Memory: 4GB+ (8GB preferred)
- Disk: 15GB+ free space
- Swap: 2GB+ if memory is limited

### 4. **Add Swap if Low Memory**

If your instance has <4GB RAM:

```bash
# Create 4GB swap file
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Verify swap is active
swapon --show

# Then retry build
make -j2  # Use fewer cores with swap
```

### 5. **Check Specific Failure**

The build might be failing on a specific component:

```bash
# Look for the actual error in recent output
dmesg | tail -20  # Check for OOM (Out of Memory) kills
journalctl --since "10 minutes ago" | grep -i error

# Try building a specific target that failed
make -j1 osquery  # Build just the main target
```

## Quick Fix Commands 🚀

Run these in order:

```bash
# 1. Check resources
echo "=== SYSTEM RESOURCES ==="
free -h && df -h / && echo "CPU cores: $(nproc)"

# 2. Try single-threaded build with verbose output
cd ~/osquery-build/osquery/build
echo "=== BUILDING WITH VERBOSE OUTPUT ==="
make -j1 VERBOSE=1

# If that fails, check the last few lines for the real error
echo "=== IF BUILD FAILED, CHECK THESE ==="
echo "Last system messages:"
dmesg | tail -10
echo "Recent journal errors:"
journalctl --since "5 minutes ago" | grep -i error | tail -5
```

## Expected Success Output 📊

When successful, you'll see:
```
[100%] Built target osquery
✅ Build completed successfully
```

## Test After Successful Build ✅

```bash
# Verify the binary works
./osquery/osqueryi --version

# Test our ancestry column exists
echo 'SELECT name FROM pragma_table_info("process_events") WHERE name = "ancestry";' | ./osquery/osqueryi
# Should return: ancestry

# Quick functionality test
echo 'SELECT COUNT(*) FROM osquery_info;' | ./osquery/osqueryi
# Should return: 1
```

## Alternative: Use Smaller Instance 💡

If resource issues persist, the **t3.large** might not have enough memory. Consider:

- **t3.xlarge** (4 vCPU, 16GB RAM) - Better for builds
- **c5.xlarge** (4 vCPU, 8GB RAM) - Compute optimized

Or build on a larger instance, then copy the binary to smaller instances for testing.

## Most Likely Solution 🎯

Based on your progress, try this:

```bash
# Single-threaded build to avoid memory issues
cd ~/osquery-build/osquery/build
make -j1

# If successful, you'll have your osquery binary with ancestry support!
```

The fact that you're reaching 5% and building libraries successfully means the **fundamental issues are fixed**. This is likely just a **resource constraint** that single-threading will solve.
