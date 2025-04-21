#!/bin/bash
set -euo pipefail

# --- Dependencies check ---
command -v jq >/dev/null 2>&1 || { echo >&2 "This script requires 'jq'. Please install it."; exit 1; }

# --- Input validation ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <GitHub PR URL> [GitHub Token (optional)]"
  exit 1
fi

PR_URL="$1"
GITHUB_TOKEN="${2:-}"

# --- Extract owner, repo, and PR number ---
OWNER=$(echo "$PR_URL" | cut -d'/' -f4)
REPO=$(echo "$PR_URL" | cut -d'/' -f5)
PR_NUMBER=$(echo "$PR_URL" | cut -d'/' -f7)

# --- GitHub API call to get PR info ---
API_URL="https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
AUTH_HEADER=""
if [[ -n "$GITHUB_TOKEN" ]]; then
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
fi

echo "Fetching PR info from GitHub API..."

PR_INFO=$(curl -s -H "$AUTH_HEADER" "$API_URL")

BASE_BRANCH=$(echo "$PR_INFO" | jq -r '.base.ref')
HEAD_BRANCH=$(echo "$PR_INFO" | jq -r '.head.ref')
CLONE_URL=$(echo "$PR_INFO" | jq -r '.head.repo.clone_url')

echo "Base branch: $BASE_BRANCH"
echo "Head branch: $HEAD_BRANCH"

# --- Clone both branches into temp dirs ---
BASE_DIR=$(mktemp -d -t pr_base_XXXX)
HEAD_DIR=$(mktemp -d -t pr_head_XXXX)

echo "Cloning base branch..."
git clone --quiet --depth=1 --branch "$BASE_BRANCH" "$CLONE_URL" "$BASE_DIR"

echo "Cloning head branch..."
git clone --quiet --depth=1 --branch "$HEAD_BRANCH" "$CLONE_URL" "$HEAD_DIR"

# --- Output file ---
OUTPUT_FILE="pr_diff_analysis.md"
echo "# PR Analysis for $OWNER/$REPO PR #$PR_NUMBER" > "$OUTPUT_FILE"
echo "Base branch: \`$BASE_BRANCH\`" >> "$OUTPUT_FILE"
echo "Head branch: \`$HEAD_BRANCH\`" >> "$OUTPUT_FILE"
echo "Generated on: $(date)" >> "$OUTPUT_FILE"
echo -e "\n---\n" >> "$OUTPUT_FILE"

# --- Compare the two directories ---
echo "Comparing branches..."

MODIFIED_FILES=()
NEW_FILES=()
DELETED_FILES=()

while IFS= read -r line; do
  if [[ "$line" == "Only in $HEAD_DIR"* ]]; then
    file=$(echo "$line" | sed -E "s|Only in $HEAD_DIR/?||" | sed 's|: ||')
    NEW_FILES+=("$file")
  elif [[ "$line" == "Only in $BASE_DIR"* ]]; then
    file=$(echo "$line" | sed -E "s|Only in $BASE_DIR/?||" | sed 's|: ||')
    DELETED_FILES+=("$file")
  elif [[ "$line" == "Files "* && "$line" == *"differ" ]]; then
    file=$(echo "$line" | cut -d' ' -f2- | sed "s| and.*||")
    rel_path="${file#$BASE_DIR/}"
    MODIFIED_FILES+=("$rel_path")
  fi
done < <(diff -qr "$BASE_DIR" "$HEAD_DIR")

# --- Output results ---
write_section() {
  echo -e "\n## $1\n" >> "$OUTPUT_FILE"
  for file in "${@:2}"; do
    echo "- \`$file\`" >> "$OUTPUT_FILE"
  done
}

write_section "🟩 New Files" "${NEW_FILES[@]}"
write_section "🟥 Deleted Files" "${DELETED_FILES[@]}"
write_section "🟨 Modified Files" "${MODIFIED_FILES[@]}"

# --- Show diffs for modified files ---
echo -e "\n---\n\n# Detailed Diffs\n" >> "$OUTPUT_FILE"

for file in "${MODIFIED_FILES[@]}"; do
  echo "Processing diff for $file..."

  base_file="$BASE_DIR/$file"
  head_file="$HEAD_DIR/$file"

  if [[ -f "$base_file" && -f "$head_file" ]]; then
    echo -e "\n## 🔄 Modified: \`$file\`\n" >> "$OUTPUT_FILE"
    echo '--------------' >> "$OUTPUT_FILE"
    echo -e "--Original--\n" >> "$OUTPUT_FILE"
    cat "$base_file" >> "$OUTPUT_FILE" || echo "*Error reading base version*" >> "$OUTPUT_FILE"
    echo -e "\n--New--\n" >> "$OUTPUT_FILE"
    cat "$head_file" >> "$OUTPUT_FILE" || echo "*Error reading new version*" >> "$OUTPUT_FILE"
    echo '--------------' >> "$OUTPUT_FILE"
  fi
done

# --- Cleanup ---
rm -rf "$BASE_DIR" "$HEAD_DIR"

echo -e "\n✅ Analysis complete. Output written to: $OUTPUT_FILE"
