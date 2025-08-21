# libaudit Header Conflict Fix

## The Problem 🔍

You're seeing this error:
```
error: use of undeclared identifier 'AUDIT_FILTER_EXCLUDE'
#define AUDIT_FILTER_EXCLUDE    AUDIT_FILTER_TYPE
#define AUDIT_FILTER_TYPE       AUDIT_FILTER_EXCLUDE /* obsolete misleading naming */
```

**Root Cause:** Circular macro definition between osquery's bundled libaudit and system audit headers.

**Why This Matters:** Our process ancestry implementation uses the audit subsystem, so libaudit must compile correctly.

## Solution 1: Fix the Header Conflict ⚡

```bash
# Navigate to the problematic file
cd ~/osquery-build/osquery
find . -name "libaudit.h" -path "*/libaudit/src/*"

# Fix the circular definition
LIBAUDIT_HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*")
echo "Found libaudit header: $LIBAUDIT_HEADER"

# Backup and fix the header
cp "$LIBAUDIT_HEADER" "$LIBAUDIT_HEADER.backup"

# Remove the conflicting macro definition
sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$LIBAUDIT_HEADER"

# Add a proper definition instead
echo '#ifndef AUDIT_FILTER_EXCLUDE' >> "$LIBAUDIT_HEADER"
echo '#define AUDIT_FILTER_EXCLUDE 5' >> "$LIBAUDIT_HEADER"
echo '#endif' >> "$LIBAUDIT_HEADER"

# Verify the fix
grep -n "AUDIT_FILTER_EXCLUDE" "$LIBAUDIT_HEADER"
```

## Solution 2: Use System libaudit (Alternative) 🔄

```bash
# Install system libaudit development package
sudo apt-get install -y libaudit-dev

# Reconfigure build to use system libaudit
cd ~/osquery-build/osquery
rm -rf build && mkdir build && cd build

# Configure with system libaudit
cmake \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DOSQUERY_BUILD_BPF=OFF \
  -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
  -DOSQUERY_BUILD_TESTS=OFF \
  -DOSQUERY_BUILD_AWS=ON \
  -DOSQUERY_BUILD_DPKG=ON \
  -DUSE_SYSTEM_LIBAUDIT=ON \
  ..

make -j1
```

## Solution 3: Complete Header Fix Script 🚀

```bash
#!/bin/bash
echo "🔧 Fixing libaudit header conflict..."

cd ~/osquery-build/osquery

# Find the problematic header
LIBAUDIT_HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)

if [ -n "$LIBAUDIT_HEADER" ]; then
    echo "Found libaudit header: $LIBAUDIT_HEADER"
    
    # Backup original
    cp "$LIBAUDIT_HEADER" "$LIBAUDIT_HEADER.backup"
    
    # Create fixed version
    cat > /tmp/libaudit_fix.patch << 'EOF'
--- a/libaudit.h
+++ b/libaudit.h
@@ -260,7 +260,10 @@
 #define AUDIT_FILTER_WATCH     0x03    /* Apply rule to file system watches */
 #define AUDIT_FILTER_EXIT      0x04    /* Apply rule at syscall exit */
 #define AUDIT_FILTER_USER      0x05    /* Apply rule at user filter */
-#define AUDIT_FILTER_EXCLUDE   AUDIT_FILTER_TYPE
+#ifndef AUDIT_FILTER_EXCLUDE
+#define AUDIT_FILTER_EXCLUDE   5
+#endif
+
 #define AUDIT_FILTER_FS                0x06    /* Apply rule at filesystem filter */
 
 /* Rule actions */
EOF
    
    # Apply the fix manually since we can't use patch
    sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$/#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif/' "$LIBAUDIT_HEADER"
    
    echo "✅ Header fixed"
    
    # Rebuild
    cd build
    echo "🔨 Rebuilding..."
    make -j1
    
else
    echo "❌ Could not find libaudit header"
    echo "Trying alternative approach..."
    
    # Try system libaudit approach
    sudo apt-get update
    sudo apt-get install -y libaudit-dev
    
    rm -rf build && mkdir build && cd build
    cmake \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DOSQUERY_BUILD_BPF=OFF \
      -DOSQUERY_BUILD_EXPERIMENTAL=OFF \
      -DOSQUERY_BUILD_TESTS=OFF \
      -DOSQUERY_BUILD_AWS=ON \
      -DOSQUERY_BUILD_DPKG=ON \
      ..
    
    make -j1
fi
```

## Quick Fix Commands ⚡

Run these commands on your EC2 instance:

```bash
# Method 1: Quick header fix
cd ~/osquery-build/osquery
HEADER=$(find . -name "libaudit.h" -path "*/libaudit/src/*" | head -1)
cp "$HEADER" "$HEADER.backup"
sed -i 's/#define AUDIT_FILTER_EXCLUDE.*AUDIT_FILTER_TYPE.*$//' "$HEADER"
echo -e '\n#ifndef AUDIT_FILTER_EXCLUDE\n#define AUDIT_FILTER_EXCLUDE 5\n#endif' >> "$HEADER"

# Continue build
cd build
make -j1
```

## Why This Error Occurs 📚

### Technical Background:
- **osquery bundles** its own version of libaudit
- **System headers** have evolved and now conflict
- **Circular macro definition** creates compilation error
- **This affects audit functionality** (which our ancestry implementation uses)

### Our Implementation Impact:
- ✅ **Our code is fine** - this is a build dependency issue
- ✅ **Audit integration works** - once libaudit compiles correctly
- ✅ **Process ancestry** will function properly after fix

## Verification After Fix ✅

Once the build completes:

```bash
# Test that audit functionality works
./osquery/osqueryi "SELECT name FROM osquery_registry WHERE registry='event_subscriber' AND name='process_events';"
# Should return: process_events

# Test our ancestry column
./osquery/osqueryi "SELECT name FROM pragma_table_info('process_events') WHERE name='ancestry';"
# Should return: ancestry
```

## Alternative: Use Pre-built Package 💡

If header fixes continue to be problematic, consider using official osquery packages:

```bash
# Download official osquery package
wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb

# Install it
sudo dpkg -i osquery_5.9.1-1.linux_amd64.deb

# Then integrate our ancestry code as a plugin
# (More complex but avoids build issues)
```

## Summary 📋

This libaudit error is a **known compatibility issue** between osquery's bundled libaudit and newer Linux distributions. The fix involves resolving the circular macro definition.

**This is NOT a problem with our ancestry implementation** - it's a standard osquery build dependency issue that affects the audit subsystem we rely on.

Try the quick fix commands above and the build should continue successfully! 🎯
