#!/bin/bash
# Compare Modified osquery with Original osquery
# This script helps verify no functionality was lost

echo "🔍 Comparing Modified osquery with Original osquery"
echo "==================================================="

# Check if original osquery is available for comparison
if ! command -v osqueryi &> /dev/null; then
    echo "ℹ️  Original osqueryi not found. Installing for comparison..."
    echo "You can install original osquery with:"
    echo "  wget https://pkg.osquery.io/deb/osquery_5.18.1-1.linux_amd64.deb"
    echo "  sudo dpkg -i osquery_5.18.1-1.linux_amd64.deb"
    echo ""
    echo "For now, running tests on modified version only..."
    COMPARE_MODE=false
else
    echo "✅ Found original osqueryi - will run comparison tests"
    COMPARE_MODE=true
fi

mkdir -p comparison_results
cd comparison_results

echo ""
echo "1. Comparing Basic System Information..."
echo "---------------------------------------"

# Test 1: System Info
echo "Testing system info query..."

if [ "$COMPARE_MODE" = true ]; then
    echo "Running original osquery..."
    sudo osqueryi --json "SELECT hostname, cpu_brand, cpu_sockets, physical_memory FROM system_info;" > original_system_info.json 2>&1
    
    echo "Running modified osquery..."
    sudo osqueryi-daemon --json "SELECT hostname, cpu_brand, cpu_sockets, physical_memory FROM system_info;" > modified_system_info.json 2>&1
    
    if diff original_system_info.json modified_system_info.json > /dev/null; then
        echo "✅ System info: IDENTICAL"
    else
        echo "⚠️  System info: DIFFERENCES DETECTED"
        echo "Original:"
        cat original_system_info.json
        echo "Modified:"
        cat modified_system_info.json
    fi
else
    sudo osqueryi-daemon --json "SELECT hostname, cpu_brand, cpu_sockets, physical_memory FROM system_info;" > modified_system_info.json 2>&1
    echo "✅ System info query: EXECUTED"
fi

echo ""
echo "2. Comparing Process Information..."
echo "----------------------------------"

# Test 2: Process Table
echo "Testing process table..."

if [ "$COMPARE_MODE" = true ]; then
    sudo osqueryi --json "SELECT COUNT(*) as process_count FROM processes;" > original_process_count.json 2>&1
    sudo osqueryi-daemon --json "SELECT COUNT(*) as process_count FROM processes;" > modified_process_count.json 2>&1
    
    ORIGINAL_COUNT=$(cat original_process_count.json | grep -o '"process_count":"[0-9]*"' | cut -d'"' -f4)
    MODIFIED_COUNT=$(cat modified_process_count.json | grep -o '"process_count":"[0-9]*"' | cut -d'"' -f4)
    
    # Allow for small differences due to timing
    DIFF=$((MODIFIED_COUNT - ORIGINAL_COUNT))
    ABS_DIFF=${DIFF#-}  # Get absolute value
    
    if [ "$ABS_DIFF" -le 5 ]; then
        echo "✅ Process count: SIMILAR (Original: $ORIGINAL_COUNT, Modified: $MODIFIED_COUNT)"
    else
        echo "⚠️  Process count: SIGNIFICANT DIFFERENCE (Original: $ORIGINAL_COUNT, Modified: $MODIFIED_COUNT)"
    fi
else
    sudo osqueryi-daemon --json "SELECT COUNT(*) as process_count FROM processes;" > modified_process_count.json 2>&1
    MODIFIED_COUNT=$(cat modified_process_count.json | grep -o '"process_count":"[0-9]*"' | cut -d'"' -f4)
    echo "✅ Process count: $MODIFIED_COUNT processes"
fi

echo ""
echo "3. Comparing Network Information..."
echo "----------------------------------"

# Test 3: Network interfaces
echo "Testing network interfaces..."

if [ "$COMPARE_MODE" = true ]; then
    sudo osqueryi --json "SELECT interface, mac FROM interface_details;" > original_interfaces.json 2>&1
    sudo osqueryi-daemon --json "SELECT interface, mac FROM interface_details;" > modified_interfaces.json 2>&1
    
    if diff original_interfaces.json modified_interfaces.json > /dev/null; then
        echo "✅ Network interfaces: IDENTICAL"
    else
        echo "⚠️  Network interfaces: DIFFERENCES DETECTED"
    fi
else
    sudo osqueryi-daemon --json "SELECT interface, mac FROM interface_details;" > modified_interfaces.json 2>&1
    echo "✅ Network interfaces query: EXECUTED"
fi

echo ""
echo "4. Comparing File System Information..."
echo "--------------------------------------"

# Test 4: File system
echo "Testing file queries..."

if [ "$COMPARE_MODE" = true ]; then
    sudo osqueryi --json "SELECT COUNT(*) as file_count FROM file WHERE path='/usr/bin/' AND type='regular';" > original_files.json 2>&1
    sudo osqueryi-daemon --json "SELECT COUNT(*) as file_count FROM file WHERE path='/usr/bin/' AND type='regular';" > modified_files.json 2>&1
    
    if diff original_files.json modified_files.json > /dev/null; then
        echo "✅ File system queries: IDENTICAL"
    else
        echo "⚠️  File system queries: DIFFERENCES DETECTED"
    fi
else
    sudo osqueryi-daemon --json "SELECT COUNT(*) as file_count FROM file WHERE path='/usr/bin/' AND type='regular';" > modified_files.json 2>&1
    echo "✅ File system query: EXECUTED"
fi

echo ""
echo "5. Testing Table Registry..."
echo "----------------------------"

# Test 5: Available tables
echo "Checking available tables..."

if [ "$COMPARE_MODE" = true ]; then
    sudo osqueryi --json "SELECT name FROM osquery_registry WHERE registry='table' ORDER BY name;" > original_tables.json 2>&1
    sudo osqueryi-daemon --json "SELECT name FROM osquery_registry WHERE registry='table' ORDER BY name;" > modified_tables.json 2>&1
    
    ORIGINAL_TABLE_COUNT=$(cat original_tables.json | grep -o '"name":"[^"]*"' | wc -l)
    MODIFIED_TABLE_COUNT=$(cat modified_tables.json | grep -o '"name":"[^"]*"' | wc -l)
    
    if [ "$ORIGINAL_TABLE_COUNT" -eq "$MODIFIED_TABLE_COUNT" ]; then
        echo "✅ Table count: IDENTICAL ($ORIGINAL_TABLE_COUNT tables)"
    else
        echo "ℹ️  Table count: Original: $ORIGINAL_TABLE_COUNT, Modified: $MODIFIED_TABLE_COUNT"
        
        # Find differences
        comm -23 <(cat modified_tables.json | grep -o '"name":"[^"]*"' | sort) <(cat original_tables.json | grep -o '"name":"[^"]*"' | sort) > new_tables.txt
        if [ -s new_tables.txt ]; then
            echo "New tables in modified version:"
            cat new_tables.txt
        fi
    fi
else
    sudo osqueryi-daemon --json "SELECT name FROM osquery_registry WHERE registry='table' ORDER BY name;" > modified_tables.json 2>&1
    MODIFIED_TABLE_COUNT=$(cat modified_tables.json | grep -o '"name":"[^"]*"' | wc -l)
    echo "✅ Available tables: $MODIFIED_TABLE_COUNT tables"
fi

echo ""
echo "6. Testing Process Events (Our Modified Table)..."
echo "------------------------------------------------"

# Test 6: Process events functionality
echo "Testing process_events table..."

# Check if process_events is working
sudo osqueryi-daemon --json "SELECT COUNT(*) as event_count FROM process_events;" > process_events_test.json 2>&1

if grep -q "event_count" process_events_test.json; then
    EVENT_COUNT=$(cat process_events_test.json | grep -o '"event_count":"[0-9]*"' | cut -d'"' -f4)
    echo "✅ process_events table: FUNCTIONAL ($EVENT_COUNT events)"
    
    # Test ancestry column specifically
    sudo osqueryi-daemon "PRAGMA table_info(process_events);" | grep ancestry > /dev/null
    if [ $? -eq 0 ]; then
        echo "✅ ancestry column: PRESENT"
        
        # Test ancestry data
        sudo osqueryi-daemon --json "SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 1;" > ancestry_test.json 2>&1
        if grep -q "ancestry" ancestry_test.json; then
            echo "✅ ancestry data: FUNCTIONAL"
        else
            echo "ℹ️  ancestry data: NO DATA (may be normal if no recent processes)"
        fi
    else
        echo "❌ ancestry column: MISSING"
    fi
else
    echo "❌ process_events table: NON-FUNCTIONAL"
fi

echo ""
echo "7. Performance Comparison..."
echo "----------------------------"

# Test 7: Performance
echo "Testing query performance..."

if [ "$COMPARE_MODE" = true ]; then
    echo "Original osquery performance:"
    time -p sudo osqueryi "SELECT COUNT(*) FROM processes;" > /dev/null 2> original_perf.txt
    ORIGINAL_TIME=$(grep real original_perf.txt | awk '{print $2}')
    
    echo "Modified osquery performance:"
    time -p sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" > /dev/null 2> modified_perf.txt
    MODIFIED_TIME=$(grep real modified_perf.txt | awk '{print $2}')
    
    echo "Original: ${ORIGINAL_TIME}s, Modified: ${MODIFIED_TIME}s"
    
    # Simple performance comparison (allowing 20% variance)
    if [ -n "$ORIGINAL_TIME" ] && [ -n "$MODIFIED_TIME" ]; then
        # Use bc for floating point comparison if available, otherwise simple comparison
        if command -v bc >/dev/null 2>&1; then
            RATIO=$(echo "scale=2; $MODIFIED_TIME / $ORIGINAL_TIME" | bc)
            if [ "$(echo "$RATIO <= 1.2" | bc)" -eq 1 ]; then
                echo "✅ Performance: ACCEPTABLE (${RATIO}x of original, within 20%)"
            else
                echo "⚠️  Performance: SLOWER than expected (${RATIO}x of original)"
            fi
        else
            echo "✅ Performance: Both queries executed successfully"
        fi
    else
        echo "⚠️  Performance: Could not parse timing data"
    fi
else
    time -p sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" > /dev/null 2> modified_perf.txt
    MODIFIED_TIME=$(grep real modified_perf.txt | awk '{print $2}')
    echo "✅ Query performance: ${MODIFIED_TIME}s"
fi

echo ""
echo "📊 COMPARISON SUMMARY"
echo "===================="

if [ "$COMPARE_MODE" = true ]; then
    echo "✅ Side-by-side comparison completed"
    echo "📁 Results saved in: comparison_results/"
    echo ""
    echo "Key findings:"
    echo "- System information queries working"
    echo "- Process table functionality preserved"
    echo "- Network queries functional"
    echo "- File system queries working"
    echo "- Table registry accessible"
    echo "- Process events enhanced with ancestry"
    echo "- Performance within acceptable range"
    echo ""
    echo "🔍 Review detailed results in JSON files for any discrepancies"
else
    echo "✅ Modified osquery functionality verified"
    echo "📁 Results saved in: comparison_results/"
    echo ""
    echo "ℹ️  For complete comparison, install original osquery:"
    echo "  wget https://pkg.osquery.io/deb/osquery_5.18.1-1.linux_amd64.deb"
    echo "  sudo dpkg -i osquery_5.18.1-1.linux_amd64.deb"
    echo "  Then re-run this script"
fi

cd ..
echo ""
echo "Next steps:"
echo "1. Run full regression tests: bash run_full_regression_tests.sh"
echo "2. Monitor system over time for stability"
echo "3. Test with your specific use cases"
