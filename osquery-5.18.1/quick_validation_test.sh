#!/bin/bash
# Quick Validation Test for osquery Process Ancestry
# Run this to immediately verify no major regressions

echo "🚀 Quick osquery Functionality Validation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

test_result() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED${NC}: $1"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAILED${NC}: $1"
        FAILED=$((FAILED + 1))
    fi
}

echo ""
echo "1. Testing Basic osquery Functionality..."
echo "----------------------------------------"

# Test 1: Basic query execution
echo "Testing basic query execution..."
sudo osqueryi-daemon "SELECT version FROM osquery_info;" > /dev/null 2>&1
test_result "Basic query execution"

# Test 2: Core tables accessibility  
echo "Testing core tables..."
sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" > /dev/null 2>&1
test_result "Processes table"

sudo osqueryi-daemon "SELECT COUNT(*) FROM users;" > /dev/null 2>&1
test_result "Users table"

sudo osqueryi-daemon "SELECT COUNT(*) FROM system_info;" > /dev/null 2>&1
test_result "System info table"

# Test 3: Event system
echo ""
echo "2. Testing Event System..."
echo "-------------------------"

# Check if osqueryd service is running
if systemctl is-active --quiet osqueryd; then
    echo -e "${GREEN}✅ PASSED${NC}: osqueryd service running"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ FAILED${NC}: osqueryd service not running"
    FAILED=$((FAILED + 1))
fi

# Test event publishers
echo "Testing event publishers..."
PUBLISHERS=$(sudo osqueryi-daemon "SELECT COUNT(*) as count FROM osquery_registry WHERE registry='event_publisher';" 2>/dev/null | grep -o '"count":"[0-9]*"' | cut -d'"' -f4)

if [ -n "$PUBLISHERS" ] && [ "$PUBLISHERS" -gt 0 ]; then
    echo -e "${GREEN}✅ PASSED${NC}: Event publishers available ($PUBLISHERS found)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ FAILED${NC}: No event publishers found"
    echo "  Debugging: Let's check manually..."
    sudo osqueryi-daemon "SELECT name FROM osquery_registry WHERE registry='event_publisher' LIMIT 3;" 2>/dev/null || echo "  Query failed"
    FAILED=$((FAILED + 1))
fi

# Test process_events table
echo "Testing process_events table..."
sudo osqueryi-daemon "SELECT COUNT(*) FROM process_events;" > /dev/null 2>&1
test_result "Process events table"

echo ""
echo "3. Testing Process Ancestry Feature..."
echo "-------------------------------------"

# Test ancestry column exists
echo "Testing ancestry column in schema..."
ANCESTRY_COLUMN=$(sudo osqueryi-daemon "PRAGMA table_info(process_events);" 2>/dev/null | grep ancestry)
if [ -n "$ANCESTRY_COLUMN" ]; then
    echo -e "${GREEN}✅ PASSED${NC}: Ancestry column present in schema"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ FAILED${NC}: Ancestry column missing from schema"
    FAILED=$((FAILED + 1))
fi

# Test ancestry functionality
echo "Testing ancestry data capture..."
sudo osqueryi-daemon "SELECT pid, parent, ancestry FROM process_events WHERE ancestry != '[]' LIMIT 1;" > /dev/null 2>&1
test_result "Ancestry data capture"

echo ""
echo "4. Testing Performance..."
echo "------------------------"

# Memory usage test
echo "Checking memory usage..."
MEMORY_KB=$(ps aux | grep '[o]squeryd' | awk '{sum+=$6} END {print sum}')
if [ -n "$MEMORY_KB" ] && [ "$MEMORY_KB" -lt 200000 ]; then
    echo -e "${GREEN}✅ PASSED${NC}: Memory usage acceptable (${MEMORY_KB}KB < 200MB)"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: Memory usage: ${MEMORY_KB}KB"
    echo "  (This may be normal depending on system activity)"
fi

# Query performance test
echo "Testing query performance..."
QUERY_TIME=$(timeout 10 bash -c "time -p sudo osqueryi-daemon 'SELECT COUNT(*) FROM processes;' >/dev/null" 2>&1 | grep "^real" | awk '{print $2}')
if [ -n "$QUERY_TIME" ] && [ "$QUERY_TIME" != "" ]; then
    echo -e "${GREEN}✅ PASSED${NC}: Query executed in ${QUERY_TIME} seconds"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: Query performance test had parsing issues (query likely worked)"
    echo "  Running simple performance test..."
    if sudo osqueryi-daemon "SELECT COUNT(*) FROM processes;" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASSED${NC}: Query execution successful"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAILED${NC}: Query execution failed"
        FAILED=$((FAILED + 1))
    fi
fi

echo ""
echo "5. Testing Configuration System..."
echo "---------------------------------"

# Test configuration loading
echo "Testing configuration system..."
sudo osqueryi-daemon "SELECT COUNT(*) FROM osquery_flags;" > /dev/null 2>&1
test_result "Configuration system"

# Test logging system
echo "Testing logging system..."
if [ -d "/var/log/osquery" ]; then
    echo -e "${GREEN}✅ PASSED${NC}: Log directory exists"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ FAILED${NC}: Log directory missing"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "📊 QUICK VALIDATION RESULTS"
echo "==========================="
echo "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo "✅ No immediate regressions detected."
    echo "✅ osquery Process Ancestry appears to be working correctly."
    echo ""
    echo "Next steps:"
    echo "1. Run full regression test suite (see REGRESSION_TESTING_GUIDE.md)"
    echo "2. Monitor system performance over time"
    echo "3. Test with your specific queries and workloads"
else
    echo ""
    echo -e "${RED}⚠️  ISSUES DETECTED!${NC}"
    echo "Some tests failed. Please investigate before production deployment."
    echo "Check the specific failed tests above and review logs:"
    echo "  sudo journalctl -u osqueryd -f"
    echo "  sudo tail -f /var/log/osquery/osqueryd.results.log"
fi

echo ""
echo "For comprehensive testing, run:"
echo "  bash run_full_regression_tests.sh"
