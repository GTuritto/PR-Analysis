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

API_URL="https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
AUTH_HEADER=""
[[ -n "$GITHUB_TOKEN" ]] && AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

echo "Fetching PR information..."

PR_INFO=$(curl -s -H "$AUTH_HEADER" "$API_URL")

BASE_BRANCH=$(echo "$PR_INFO" | jq -r '.base.ref')
HEAD_BRANCH=$(echo "$PR_INFO" | jq -r '.head.ref')
CLONE_URL=$(echo "$PR_INFO" | jq -r '.head.repo.clone_url')

# Use test directories instead of real clones
BASE_DIR="test_base"
HEAD_DIR="test_head"

# Output file
OUTPUT_FILE="test_output_min.md"
echo "PR: $OWNER/$REPO #$PR_NUMBER" > "$OUTPUT_FILE"
echo "Base: $BASE_BRANCH" >> "$OUTPUT_FILE"
echo "Head: $HEAD_BRANCH" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# File comparison (using mock diff)
NEW_FILES=()
DELETED_FILES=()
MODIFIED_FILES=()

while IFS= read -r line; do
  if [[ "$line" == "Only in $HEAD_DIR"* ]]; then
    file=$(echo "$line" | sed -E "s|Only in $HEAD_DIR/?||" | sed 's|: ||')
    NEW_FILES+=("$file")
  elif [[ "$line" == "Only in $BASE_DIR"* ]]; then
    file=$(echo "$line" | sed -E "s|Only in $BASE_DIR/?||" | sed 's|: ||')
    DELETED_FILES+=("$file")
  elif [[ "$line" == "Files "* && "$line" == *"differ" ]]; then
    file=$(echo "$line" | cut -d' ' -f2- | sed "s| and.*||")
    MODIFIED_FILES+=("${file#$BASE_DIR/}")
  fi
done < <(diff)

# Write simple lists
write_section() {
  local title="$1"
  shift
  [[ $# -eq 0 ]] && return
  echo "$title" >> "$OUTPUT_FILE"
  for f in "$@"; do
    echo "- $f" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
}

write_section "New Files:" "${NEW_FILES[@]}"
write_section "Deleted Files:" "${DELETED_FILES[@]}"
write_section "Modified Files:" "${MODIFIED_FILES[@]}"

# Detailed diffs for modified files
for file in "${MODIFIED_FILES[@]}"; do
  base_path="$BASE_DIR/$file"
  head_path="$HEAD_DIR/$file"
  [[ -f "$base_path" && -f "$head_path" ]] || continue

  echo "File: $file" >> "$OUTPUT_FILE"
  echo "<<<<>>>>" >> "$OUTPUT_FILE"
  echo "<<<<previous>>>>" >> "$OUTPUT_FILE"
  cat "$base_path" >> "$OUTPUT_FILE" || echo "[Error reading base file]" >> "$OUTPUT_FILE"
  echo "<<<<new>>>>" >> "$OUTPUT_FILE"
  cat "$head_path" >> "$OUTPUT_FILE" || echo "[Error reading head file]" >> "$OUTPUT_FILE"
  echo "<<<<>>>>" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

echo "Diff saved to $OUTPUT_FILE"
