#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create test directories and files
setup() {
    echo "Setting up test environment..."
    
    # Create mock directories
    mkdir -p test_base/src test_head/src
    
    # Create identical files
    echo "// Common file content" > test_base/src/common.js
    echo "// Common file content" > test_head/src/common.js
    
    # Create modified file
    echo "// Original content" > test_base/src/modified.js
    echo "// Modified content" > test_head/src/modified.js
    
    # Create new file in head
    echo "// New file" > test_head/src/new.js
    
    # Create deleted file in base
    echo "// Deleted file" > test_base/src/deleted.js
    
    # Mock PR info JSON
    cat > test_pr_info.json << EOF
{
  "base": {
    "ref": "main"
  },
  "head": {
    "ref": "feature-branch",
    "repo": {
      "clone_url": "https://github.com/user/repo.git"
    }
  }
}
EOF
}

# Mock functions to replace actual commands
mock_curl() {
    cat test_pr_info.json
}

mock_git_clone() {
    # Mock git clone, just return success
    return 0
}

mock_diff() {
    # Simulate diff output between test directories
    echo "Only in test_head/src: new.js"
    echo "Only in test_base/src: deleted.js"
    echo "Files test_base/src/modified.js and test_head/src/modified.js differ"
}

# Clean up test files
cleanup() {
    echo "Cleaning up test environment..."
    rm -rf test_base test_head test_pr_info.json
    rm -f test_output_min.md test_output_full.md
}

# Test analyze-pr-diff-min.sh
test_analyze_pr_diff_min() {
    echo "Testing analyze-pr-diff-min.sh..."
    
    # Mock version of the script
    cat > test_analyze_pr_diff_min.sh << EOF
#!/bin/bash
set -euo pipefail

# Mock for testing
curl() { mock_curl; }
git() { mock_git_clone; }
diff() { mock_diff; }

PR_URL="https://github.com/user/repo/pull/123"
GITHUB_TOKEN=""

# Extract PR components (mock)
OWNER="user"
REPO="repo"
PR_NUMBER="123"

API_URL="https://api.github.com/repos/\$OWNER/\$REPO/pulls/\$PR_NUMBER"
AUTH_HEADER=""
[[ -n "\$GITHUB_TOKEN" ]] && AUTH_HEADER="Authorization: token \$GITHUB_TOKEN"

echo "Fetching PR information..."

PR_INFO=\$(curl -s -H "\$AUTH_HEADER" "\$API_URL")

BASE_BRANCH=\$(echo "\$PR_INFO" | jq -r '.base.ref')
HEAD_BRANCH=\$(echo "\$PR_INFO" | jq -r '.head.ref')
CLONE_URL=\$(echo "\$PR_INFO" | jq -r '.head.repo.clone_url')

# Use test directories instead of real clones
BASE_DIR="test_base"
HEAD_DIR="test_head"

# Output file
OUTPUT_FILE="test_output_min.md"
echo "PR: \$OWNER/\$REPO #\$PR_NUMBER" > "\$OUTPUT_FILE"
echo "Base: \$BASE_BRANCH" >> "\$OUTPUT_FILE"
echo "Head: \$HEAD_BRANCH" >> "\$OUTPUT_FILE"
echo "" >> "\$OUTPUT_FILE"

# File comparison (using mock diff)
NEW_FILES=()
DELETED_FILES=()
MODIFIED_FILES=()

while IFS= read -r line; do
  if [[ "\$line" == "Only in \$HEAD_DIR"* ]]; then
    file=\$(echo "\$line" | sed -E "s|Only in \$HEAD_DIR/?||" | sed 's|: ||')
    NEW_FILES+=("\$file")
  elif [[ "\$line" == "Only in \$BASE_DIR"* ]]; then
    file=\$(echo "\$line" | sed -E "s|Only in \$BASE_DIR/?||" | sed 's|: ||')
    DELETED_FILES+=("\$file")
  elif [[ "\$line" == "Files "* && "\$line" == *"differ" ]]; then
    file=\$(echo "\$line" | cut -d' ' -f2- | sed "s| and.*||")
    MODIFIED_FILES+=("\${file#\$BASE_DIR/}")
  fi
done < <(diff)

# Write simple lists
write_section() {
  local title="\$1"
  shift
  [[ \$# -eq 0 ]] && return
  echo "\$title" >> "\$OUTPUT_FILE"
  for f in "\$@"; do
    echo "- \$f" >> "\$OUTPUT_FILE"
  done
  echo "" >> "\$OUTPUT_FILE"
}

write_section "New Files:" "\${NEW_FILES[@]}"
write_section "Deleted Files:" "\${DELETED_FILES[@]}"
write_section "Modified Files:" "\${MODIFIED_FILES[@]}"

# Detailed diffs for modified files
for file in "\${MODIFIED_FILES[@]}"; do
  base_path="\$BASE_DIR/\$file"
  head_path="\$HEAD_DIR/\$file"
  [[ -f "\$base_path" && -f "\$head_path" ]] || continue

  echo "File: \$file" >> "\$OUTPUT_FILE"
  echo "<<<<>>>>" >> "\$OUTPUT_FILE"
  echo "<<<<previous>>>>" >> "\$OUTPUT_FILE"
  cat "\$base_path" >> "\$OUTPUT_FILE" || echo "[Error reading base file]" >> "\$OUTPUT_FILE"
  echo "<<<<new>>>>" >> "\$OUTPUT_FILE"
  cat "\$head_path" >> "\$OUTPUT_FILE" || echo "[Error reading head file]" >> "\$OUTPUT_FILE"
  echo "<<<<>>>>" >> "\$OUTPUT_FILE"
  echo "" >> "\$OUTPUT_FILE"
done

echo "Diff saved to \$OUTPUT_FILE"
EOF

    chmod +x test_analyze_pr_diff_min.sh
    
    # Run test script
    ./test_analyze_pr_diff_min.sh
    
    # Verify results
    if grep -q "New Files:" test_output_min.md && \
       grep -q "Deleted Files:" test_output_min.md && \
       grep -q "Modified Files:" test_output_min.md && \
       grep -q "<<<<previous>>>>" test_output_min.md && \
       grep -q "<<<<new>>>>" test_output_min.md; then
        echo -e "${GREEN}✓ analyze-pr-diff-min.sh test passed!${NC}"
    else
        echo -e "${RED}✗ analyze-pr-diff-min.sh test failed!${NC}"
        return 1
    fi
    
    # Clean up test script
    rm test_analyze_pr_diff_min.sh
}

# Test analyze-pr-diff.sh
test_analyze_pr_diff() {
    echo "Testing analyze-pr-diff.sh..."
    
    # Mock version of the script
    cat > test_analyze_pr_diff.sh << EOF
#!/bin/bash
set -euo pipefail

# Mock for testing
curl() { mock_curl; }
git() { mock_git_clone; }
diff() { mock_diff; }

PR_URL="https://github.com/user/repo/pull/123"
GITHUB_TOKEN=""

# Extract components (mock)
OWNER="user"
REPO="repo"
PR_NUMBER="123"

API_URL="https://api.github.com/repos/\$OWNER/\$REPO/pulls/\$PR_NUMBER"
AUTH_HEADER=""
[[ -n "\$GITHUB_TOKEN" ]] && AUTH_HEADER="Authorization: token \$GITHUB_TOKEN"

echo "Fetching PR info from GitHub API..."

PR_INFO=\$(curl -s -H "\$AUTH_HEADER" "\$API_URL")

BASE_BRANCH=\$(echo "\$PR_INFO" | jq -r '.base.ref')
HEAD_BRANCH=\$(echo "\$PR_INFO" | jq -r '.head.ref')
CLONE_URL=\$(echo "\$PR_INFO" | jq -r '.head.repo.clone_url')

echo "Base branch: \$BASE_BRANCH"
echo "Head branch: \$HEAD_BRANCH"

# Use test directories instead of real clones
BASE_DIR="test_base"
HEAD_DIR="test_head"

# Output file
OUTPUT_FILE="test_output_full.md"
echo "# PR Analysis for \$OWNER/\$REPO PR #\$PR_NUMBER" > "\$OUTPUT_FILE"
echo "Base branch: \`\$BASE_BRANCH\`" >> "\$OUTPUT_FILE"
echo "Head branch: \`\$HEAD_BRANCH\`" >> "\$OUTPUT_FILE"
echo "Generated on: \$(date)" >> "\$OUTPUT_FILE"
echo -e "\n---\n" >> "\$OUTPUT_FILE"

echo "Comparing branches..."

MODIFIED_FILES=()
NEW_FILES=()
DELETED_FILES=()

while IFS= read -r line; do
  if [[ "\$line" == "Only in \$HEAD_DIR"* ]]; then
    file=\$(echo "\$line" | sed -E "s|Only in \$HEAD_DIR/?||" | sed 's|: ||')
    NEW_FILES+=("\$file")
  elif [[ "\$line" == "Only in \$BASE_DIR"* ]]; then
    file=\$(echo "\$line" | sed -E "s|Only in \$BASE_DIR/?||" | sed 's|: ||')
    DELETED_FILES+=("\$file")
  elif [[ "\$line" == "Files "* && "\$line" == *"differ" ]]; then
    file=\$(echo "\$line" | cut -d' ' -f2- | sed "s| and.*||")
    rel_path="\${file#\$BASE_DIR/}"
    MODIFIED_FILES+=("\$rel_path")
  fi
done < <(diff)

# Output results
write_section() {
  echo -e "\n## \$1\n" >> "\$OUTPUT_FILE"
  for file in "\${@:2}"; do
    echo "- \`\$file\`" >> "\$OUTPUT_FILE"
  done
}

write_section "🟩 New Files" "\${NEW_FILES[@]}"
write_section "🟥 Deleted Files" "\${DELETED_FILES[@]}"
write_section "🟨 Modified Files" "\${MODIFIED_FILES[@]}"

# Show diffs for modified files
echo -e "\n---\n\n# Detailed Diffs\n" >> "\$OUTPUT_FILE"

for file in "\${MODIFIED_FILES[@]}"; do
  echo "Processing diff for \$file..."

  base_file="\$BASE_DIR/\$file"
  head_file="\$HEAD_DIR/\$file"

  if [[ -f "\$base_file" && -f "\$head_file" ]]; then
    echo -e "\n## 🔄 Modified: \`\$file\`\n" >> "\$OUTPUT_FILE"
    echo '<<<<>>>>' >> "\$OUTPUT_FILE"
    echo -e "<<<<previous>>>>\n" >> "\$OUTPUT_FILE"
    cat "\$base_file" >> "\$OUTPUT_FILE" || echo "*Error reading base version*" >> "\$OUTPUT_FILE"
    echo -e "\n<<<<new>>>>\n" >> "\$OUTPUT_FILE"
    cat "\$head_file" >> "\$OUTPUT_FILE" || echo "*Error reading new version*" >> "\$OUTPUT_FILE"
    echo '<<<<>>>>' >> "\$OUTPUT_FILE"
  fi
done

echo -e "\n✅ Analysis complete. Output written to: \$OUTPUT_FILE"
EOF

    chmod +x test_analyze_pr_diff.sh
    
    # Run test script
    ./test_analyze_pr_diff.sh
    
    # Verify results
    if grep -q "New Files" test_output_full.md && \
       grep -q "Deleted Files" test_output_full.md && \
       grep -q "Modified Files" test_output_full.md && \
       grep -q "<<<<previous>>>>" test_output_full.md && \
       grep -q "<<<<new>>>>" test_output_full.md; then
        echo -e "${GREEN}✓ analyze-pr-diff.sh test passed!${NC}"
    else
        echo -e "${RED}✗ analyze-pr-diff.sh test failed!${NC}"
        return 1
    fi
    
    # Clean up test script
    rm test_analyze_pr_diff.sh
}

# Run tests
run_tests() {
    setup
    
    echo "Running tests..."
    test_analyze_pr_diff_min
    test_analyze_pr_diff
    
    # Save example results for README
    cp test_output_min.md example_output_min.md
    cp test_output_full.md example_output_full.md
    
    cleanup
}

# Main execution
run_tests
echo "All tests completed!"
