#!/bin/bash
set -euo pipefail

# --- Requirements check ---
command -v jq >/dev/null || { echo "jq is required. Please install it."; exit 1; }

# --- Input ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <GitHub PR URL> [GitHub Token (optional)]"
  exit 1
fi

PR_URL="$1"
GITHUB_TOKEN="${2:-}"

# --- Extract PR components from URL ---
# Validate and parse GitHub PR URL format
if [[ ! "$PR_URL" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  echo "Error: Invalid GitHub PR URL format."
  echo "Expected format: https://github.com/owner/repo/pull/123"
  exit 1
fi

OWNER=$(echo "$PR_URL" | cut -d'/' -f4)
REPO=$(echo "$PR_URL" | cut -d'/' -f5)
PR_NUMBER=$(echo "$PR_URL" | cut -d'/' -f7)

echo "Analyzing PR #$PR_NUMBER from $OWNER/$REPO..."

API_URL="https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
AUTH_HEADER=""
[[ -n "$GITHUB_TOKEN" ]] && AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

echo "Fetching PR information..."

PR_INFO=$(curl -s -H "$AUTH_HEADER" "$API_URL")

BASE_BRANCH=$(echo "$PR_INFO" | jq -r '.base.ref')
HEAD_BRANCH=$(echo "$PR_INFO" | jq -r '.head.ref')
CLONE_URL=$(echo "$PR_INFO" | jq -r '.head.repo.clone_url')

# --- Clone base and head branches ---
BASE_DIR=$(mktemp -d)
HEAD_DIR=$(mktemp -d)

git clone --quiet --depth=1 --branch "$BASE_BRANCH" "$CLONE_URL" "$BASE_DIR"
git clone --quiet --depth=1 --branch "$HEAD_BRANCH" "$CLONE_URL" "$HEAD_DIR"

# --- Output file optimized for LLM consumption ---
OUTPUT_FILE="pr_diff_result.md"
echo "# PR REVIEW CONTEXT" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "PR: $OWNER/$REPO #$PR_NUMBER" >> "$OUTPUT_FILE"
echo "URL: $PR_URL" >> "$OUTPUT_FILE"
echo "Base Branch: $BASE_BRANCH" >> "$OUTPUT_FILE"
echo "Head Branch: $HEAD_BRANCH" >> "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# --- File comparison ---
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
done < <(diff -qr "$BASE_DIR" "$HEAD_DIR")

# --- Write PR Summary optimized for LLMs ---
echo "## PR SUMMARY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Summary counts for quick understanding
TOTAL_CHANGES=$((${#NEW_FILES[@]} + ${#DELETED_FILES[@]} + ${#MODIFIED_FILES[@]}))
echo "Total Changes: $TOTAL_CHANGES files" >> "$OUTPUT_FILE"
echo "New: ${#NEW_FILES[@]} | Modified: ${#MODIFIED_FILES[@]} | Deleted: ${#DELETED_FILES[@]}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Write detailed file lists
if [ ${#NEW_FILES[@]} -gt 0 ]; then
  echo "### New Files:" >> "$OUTPUT_FILE"
  for file in "${NEW_FILES[@]}"; do
    echo "- $file" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
  
  # Include full content of new files
  echo "### NEW FILE CONTENTS" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  
  for file in "${NEW_FILES[@]}"; do
    head_path="$HEAD_DIR/$file"
    if [ -f "$head_path" ]; then
      echo "FILE: $file" >> "$OUTPUT_FILE"
      echo "<NEW_CONTENT>" >> "$OUTPUT_FILE"
      cat "$head_path" >> "$OUTPUT_FILE"
      echo "</NEW_CONTENT>" >> "$OUTPUT_FILE"
      echo "" >> "$OUTPUT_FILE"
    fi
  done
fi

if [ ${#DELETED_FILES[@]} -gt 0 ]; then
  echo "### Deleted Files:" >> "$OUTPUT_FILE"
  for file in "${DELETED_FILES[@]}"; do
    echo "- $file" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
fi

if [ ${#MODIFIED_FILES[@]} -gt 0 ]; then
  echo "### Modified Files:" >> "$OUTPUT_FILE"
  for file in "${MODIFIED_FILES[@]}"; do
    echo "- $file" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
fi

# --- Optimize diff output for modified files (for LLM consumption) ---
echo "### DIFF SUMMARY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for file in "${MODIFIED_FILES[@]}"; do
  base_path="$BASE_DIR/$file"
  head_path="$HEAD_DIR/$file"
  [[ -f "$base_path" && -f "$head_path" ]] || continue

  echo "FILE: $file" >> "$OUTPUT_FILE"
  echo "<DIFF>" >> "$OUTPUT_FILE"
  
  # Use git diff with context to create a more useful diff for code review
  git diff --no-index --unified=3 "$base_path" "$head_path" | tail -n +5 | \
    sed 's/^+/+ /' | sed 's/^-/- /' >> "$OUTPUT_FILE"
  
  echo "</DIFF>" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# --- Cleanup ---
rm -rf "$BASE_DIR" "$HEAD_DIR"

echo "Diff saved to $OUTPUT_FILE"
