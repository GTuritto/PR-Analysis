#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test a script for syntax and required elements
test_script() {
    local script="$1"
    echo "Testing ${script}..."
    
    if [ ! -f "${script}" ]; then
        echo -e "${RED}✗ ${script} not found!${NC}"
        return 1
    fi
    
    # Basic syntax check
    bash -n "${script}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ ${script} syntax check passed!${NC}"
    else
        echo -e "${RED}✗ ${script} syntax check failed!${NC}"
        return 1
    fi
    
    # Check for required commands
    if grep -q "command -v jq" "${script}"; then
        echo -e "${GREEN}✓ ${script} dependency check present!${NC}"
    else
        echo -e "${RED}✗ ${script} missing dependency check!${NC}"
        return 1
    fi
    
    # Check for required arguments
    if grep -q "\$#" "${script}"; then
        echo -e "${GREEN}✓ ${script} argument validation present!${NC}"
    else
        echo -e "${RED}✗ ${script} missing argument validation!${NC}"
        return 1
    fi
    
    # Check for proper output file handling
    if grep -q "OUTPUT_FILE" "${script}"; then
        echo -e "${GREEN}✓ ${script} output file handling present!${NC}"
    else
        echo -e "${RED}✗ ${script} missing output file handling!${NC}"
        return 1
    fi
    
    # Check for proper API URL construction
    if grep -q "API_URL.*github.com/repos/" "${script}"; then
        echo -e "${GREEN}✓ ${script} GitHub API URL construction present!${NC}"
    else
        echo -e "${RED}✗ ${script} missing proper GitHub API URL construction!${NC}"
        return 1
    fi
    
    # Check for proper error handling
    if grep -q "exit 1" "${script}"; then
        echo -e "${GREEN}✓ ${script} error handling present!${NC}"
    else
        echo -e "${RED}✗ ${script} missing error handling!${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ All checks passed for ${script}!${NC}"
    return 0
}

# Run the tests
echo "Running unit tests for analyze-pr-diff scripts..."
test_script "analyze-pr-diff-min.sh"
test_script "analyze-pr-diff.sh"
echo "All tests completed!"
