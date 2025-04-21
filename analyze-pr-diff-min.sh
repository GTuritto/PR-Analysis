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

# --- Extract PR components ---
OWNER=$(echo "$PR_URL" | cut -d'/' -f4)
REPO=$(echo "$PR_URL" | cut -d'/' -f5)
PR_NUMBER=$(echo "$PR_URL" | cut -d'/' -f7)

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

# --- Output file ---
OUTPUT_FILE="pr_diff_result.md"
echo "PR: $OWNER/$REPO #$PR_NUMBER" > "$OUTPUT_FILE"
echo "Base: $BASE_BRANCH" >> "$OUTPUT_FILE"
echo "Head: $HEAD_BRANCH" >> "$OUTPUT_FILE"
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

# --- Write simple lists ---
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

# --- Detailed diffs for modified files ---
for file in "${MODIFIED_FILES[@]}"; do
  base_path="$BASE_DIR/$file"
  head_path="$HEAD_DIR/$file"
  [[ -f "$base_path" && -f "$head_path" ]] || continue

  echo "File: $file" >> "$OUTPUT_FILE"
  echo "--------" >> "$OUTPUT_FILE"
  echo "--Original--" >> "$OUTPUT_FILE"
  cat "$base_path" >> "$OUTPUT_FILE" || echo "[Error reading base file]" >> "$OUTPUT_FILE"
  echo "--New--" >> "$OUTPUT_FILE"
  cat "$head_path" >> "$OUTPUT_FILE" || echo "[Error reading head file]" >> "$OUTPUT_FILE"
  echo "--------" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# --- Cleanup ---
rm -rf "$BASE_DIR" "$HEAD_DIR"

echo "Diff saved to $OUTPUT_FILE"
