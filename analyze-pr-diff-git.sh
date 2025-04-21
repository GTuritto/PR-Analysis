#!/bin/bash
set -euo pipefail

# --- No external dependencies required ---
# This script uses pure Bash for all operations with no external tools

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

# --- Check for API errors first ---
echo "Parsing PR information..."

# Check if the API returned an error message
ERROR_MESSAGE=$(echo "$PR_INFO" | grep -o '"message":"[^"]*"' | sed -E 's/"message":"([^"]*)"$/\1/' | head -1)
if [[ -n "$ERROR_MESSAGE" ]]; then
  echo "Error from GitHub API: $ERROR_MESSAGE"
  echo "Please check that PR #$PR_NUMBER exists and you have access to it."
  exit 1
fi

# --- Use pure Bash for JSON parsing ---
# Extract key information using grep and sed - more robust than regex
parse_json_field() {
  local json="$1"
  local field="$2"
  echo "$json" | grep -o "\"$field\":[^,}]*" | sed -E 's/"'"$field"'"://; s/^[[:space:]]*"//; s/"[[:space:]]*$//' | head -1
}

parse_nested_json_field() {
  local json="$1"
  local parent="$2"
  local child="$3"
  local parent_obj
  
  # Extract the parent object first
  parent_obj=$(echo "$json" | grep -o "\"$parent\":{[^}]*}")
  
  # Then extract the child field
  parse_json_field "$parent_obj" "$child"
}

# Extract values or use defaults
BASE_BRANCH=$(parse_nested_json_field "$PR_INFO" "base" "ref")
HEAD_BRANCH=$(parse_nested_json_field "$PR_INFO" "head" "ref")
CLONE_URL=$(parse_nested_json_field "$PR_INFO" "head" "clone_url")

# Fallback for empty values
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="main"
  echo "Using default base branch: $BASE_BRANCH"
fi

if [[ -z "$HEAD_BRANCH" ]]; then
  HEAD_BRANCH="feature"
  echo "Using default head branch: $HEAD_BRANCH"
fi

if [[ -z "$CLONE_URL" ]]; then
  CLONE_URL="https://github.com/$OWNER/$REPO.git"
  echo "Using default clone URL: $CLONE_URL"
fi

echo "Base branch: $BASE_BRANCH"
echo "Head branch: $HEAD_BRANCH"
echo "Clone URL: $CLONE_URL"

# --- Clone branches using the information we extracted ---
BASE_DIR=$(mktemp -d)
HEAD_DIR=$(mktemp -d)

# Try to clone the branches
echo "Cloning base branch: $BASE_BRANCH"
git clone --quiet --depth=1 --branch "$BASE_BRANCH" "$CLONE_URL" "$BASE_DIR" || {
  echo "Failed to clone base branch directly. Trying alternative approach..."
  git clone --quiet --depth=1 "$CLONE_URL" "$BASE_DIR"
}

echo "Cloning head branch: $HEAD_BRANCH"
git clone --quiet --depth=1 --branch "$HEAD_BRANCH" "$CLONE_URL" "$HEAD_DIR" || {
  echo "Failed to clone head branch directly. Trying alternative approach..."
  git clone --quiet --depth=1 "$CLONE_URL" "$HEAD_DIR"
  cd "$HEAD_DIR"
  git fetch --quiet origin "$HEAD_BRANCH" || {
    echo "Could not fetch branch $HEAD_BRANCH directly. Trying PR reference..."
    git fetch --quiet origin "pull/$PR_NUMBER/head:pr-$PR_NUMBER" && \
    git checkout --quiet "pr-$PR_NUMBER" || true
  }
  cd - > /dev/null
}

# --- Helper functions for file categorization and token estimation ---
get_file_category() {
  local file_path="$1"
  local extension="${file_path##*.}"
  # Use tr for lowercase conversion instead of bash-specific ,, operator
  extension=".$(echo "$extension" | tr '[:upper:]' '[:lower:]')"
  
  # Check for test files first (by name pattern)
  if [[ "$file_path" =~ \.(spec|test)\. ]] || [[ "$file_path" =~ /(specs?|tests?|__tests__)/ ]]; then
    echo "Tests"
    return
  fi
  
  # Code files
  if [[ "$extension" =~ ^\.(js|jsx|ts|tsx|py|rb|php|java|c|cpp|cs|go|rs|swift|kt|scala|clj|fnl|lua|ex|exs|erl|fs|fsx|pl|pm|t|groovy|dart|pas)$ ]]; then
    echo "Code"
    return
  fi
  
  # Configuration files
  if [[ "$extension" =~ ^\.(json|xml|yaml|yml|toml|ini|cfg|conf|config|properties|props|env|eslintrc|babelrc|editorconfig|prettierrc|dockerignore|gitignore|gitattributes|npmrc|htaccess|gitmodules)$ ]]; then
    echo "Config"
    return
  fi
  
  # Documentation files
  if [[ "$extension" =~ ^\.(md|mdx|txt|rtf|pdf|doc|docx|html|htm|rst|wiki|adoc|tex|asciidoc|markdown|mdown|mkdn)$ ]]; then
    echo "Docs"
    return
  fi
  
  # Style files
  if [[ "$extension" =~ ^\.(css|scss|sass|less|styl|stylus|pcss)$ ]]; then
    echo "Styles"
    return
  fi
  
  # Template files
  if [[ "$extension" =~ ^\.(html|htm|ejs|hbs|handlebars|mustache|twig|liquid|njk|jade|pug)$ ]]; then
    echo "Templates"
    return
  fi
  
  # Data files
  if [[ "$extension" =~ ^\.(csv|tsv|json|xml|yaml|yml|sqlite|sql)$ ]]; then
    echo "Data"
    return
  fi
  
  # Image files
  if [[ "$extension" =~ ^\.(png|jpg|jpeg|gif|svg|webp|bmp|ico)$ ]]; then
    echo "Images"
    return
  fi
  
  # Default to "Other" if no match
  echo "Other"
}

get_token_estimate() {
  local file_path="$1"
  
  if [[ ! -f "$file_path" ]]; then
    echo "0"
    return
  fi
  
  # Count characters and estimate tokens (rough approximation: ~4 chars per token for code)
  local char_count=$(wc -c < "$file_path")
  local token_estimate=$(( (char_count + 3) / 4 ))  # ceiling division
  echo "$token_estimate"
}

get_file_size_kb() {
  local file_path="$1"
  
  if [[ ! -f "$file_path" ]]; then
    echo "0"
    return
  fi
  
  local size_bytes=$(wc -c < "$file_path")
  local size_kb=$(echo "scale=2; $size_bytes/1024" | bc)
  echo "$size_kb"
}

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

# --- Write PR Summary with enhanced statistics ---
echo "## PR SUMMARY" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Calculate token estimates and collect file categories
TOTAL_CHANGES=$((${#NEW_FILES[@]} + ${#DELETED_FILES[@]} + ${#MODIFIED_FILES[@]}))
TOTAL_TOKEN_ESTIMATE=0
CATEGORY_COUNTS=""

# Process new files for token estimates and categories
# Use nullglob to handle empty arrays safely
shopt -s nullglob
for file in "${NEW_FILES[@]:-}"; do
  head_path="$HEAD_DIR/$file"
  category=$(get_file_category "$file")
  tokens=$(get_token_estimate "$head_path")
  TOTAL_TOKEN_ESTIMATE=$((TOTAL_TOKEN_ESTIMATE + tokens))
  
  # Increment category count using a simpler approach
  if echo "$CATEGORY_COUNTS" | grep -q "$category:"; then
    CURRENT_COUNT=$(echo "$CATEGORY_COUNTS" | grep "$category:" | cut -d':' -f2)
    CATEGORY_COUNTS=$(echo "$CATEGORY_COUNTS" | sed "s/$category:$CURRENT_COUNT/$category:$((CURRENT_COUNT + 1))/")
  else
    CATEGORY_COUNTS="$CATEGORY_COUNTS $category:1"
  fi
done

# Process modified files for token estimates and categories
for file in "${MODIFIED_FILES[@]:-}"; do
  head_path="$HEAD_DIR/$file"
  category=$(get_file_category "$file")
  tokens=$(get_token_estimate "$head_path")
  TOTAL_TOKEN_ESTIMATE=$((TOTAL_TOKEN_ESTIMATE + tokens))
  
  # Increment category count using a simpler approach
  if echo "$CATEGORY_COUNTS" | grep -q "$category:"; then
    CURRENT_COUNT=$(echo "$CATEGORY_COUNTS" | grep "$category:" | cut -d':' -f2)
    CATEGORY_COUNTS=$(echo "$CATEGORY_COUNTS" | sed "s/$category:$CURRENT_COUNT/$category:$((CURRENT_COUNT + 1))/")
  else
    CATEGORY_COUNTS="$CATEGORY_COUNTS $category:1"
  fi
done

# Process deleted files for token estimates and categories
for file in "${DELETED_FILES[@]:-}"; do
  base_path="$BASE_DIR/$file"
  category=$(get_file_category "$file")
  tokens=$(get_token_estimate "$base_path")
  TOTAL_TOKEN_ESTIMATE=$((TOTAL_TOKEN_ESTIMATE + tokens))
  
  # Increment category count using a simpler approach
  if echo "$CATEGORY_COUNTS" | grep -q "$category:"; then
    CURRENT_COUNT=$(echo "$CATEGORY_COUNTS" | grep "$category:" | cut -d':' -f2)
    CATEGORY_COUNTS=$(echo "$CATEGORY_COUNTS" | sed "s/$category:$CURRENT_COUNT/$category:$((CURRENT_COUNT + 1))/")
  else
    CATEGORY_COUNTS="$CATEGORY_COUNTS $category:1"
  fi
done

# Write enhanced summary statistics
echo "**Repository Stats**" >> "$OUTPUT_FILE"
echo "- Total Changes: $TOTAL_CHANGES files" >> "$OUTPUT_FILE"
echo "- Files by Type: New: ${#NEW_FILES[@]:-0} | Modified: ${#MODIFIED_FILES[@]:-0} | Deleted: ${#DELETED_FILES[@]:-0}" >> "$OUTPUT_FILE"
echo "- Estimated Tokens: $TOTAL_TOKEN_ESTIMATE" >> "$OUTPUT_FILE"
echo "- Processing Time: $(date) GMT" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Write file category counts
echo "**Files by Category**" >> "$OUTPUT_FILE"
for category_count in $CATEGORY_COUNTS; do
  if [[ -n "$category_count" ]]; then
    category=$(echo "$category_count" | cut -d':' -f1)
    count=$(echo "$category_count" | cut -d':' -f2)
    echo "- $category: $count files" >> "$OUTPUT_FILE"
  fi
done
echo "" >> "$OUTPUT_FILE"

# Write detailed file lists
if [ ${#NEW_FILES[@]} -gt 0 ]; then
  echo "### New Files:" >> "$OUTPUT_FILE"
  for file in "${NEW_FILES[@]}"; do
    category=$(get_file_category "$file")
    head_path="$HEAD_DIR/$file"
    tokens=$(get_token_estimate "$head_path")
    size_kb=$(get_file_size_kb "$head_path")
    echo "- **[$category]** $file ($size_kb KB, ~$tokens tokens)" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
  
  # Include full content of new files
  echo "### NEW FILE CONTENTS" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  
  for file in "${NEW_FILES[@]}"; do
    head_path="$HEAD_DIR/$file"
    if [ -f "$head_path" ]; then
      category=$(get_file_category "$file")
      echo "FILE: $file **[$category]** **NEWLY ADDED**" >> "$OUTPUT_FILE"
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
    category=$(get_file_category "$file")
    base_path="$BASE_DIR/$file"
    tokens=$(get_token_estimate "$base_path")
    size_kb=$(get_file_size_kb "$base_path")
    echo "- **[$category]** $file ($size_kb KB, ~$tokens tokens) **REMOVED**" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
fi

if [ ${#MODIFIED_FILES[@]} -gt 0 ]; then
  echo "### Modified Files:" >> "$OUTPUT_FILE"
  for file in "${MODIFIED_FILES[@]}"; do
    category=$(get_file_category "$file")
    head_path="$HEAD_DIR/$file"
    base_path="$BASE_DIR/$file"
    tokens=$(get_token_estimate "$head_path")
    size_kb=$(get_file_size_kb "$head_path")
    echo "- **[$category]** $file ($size_kb KB, ~$tokens tokens) **MODIFIED**" >> "$OUTPUT_FILE"
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

  category=$(get_file_category "$file")
  tokens=$(get_token_estimate "$head_path")
  size_kb=$(get_file_size_kb "$head_path")
  
  # Check how many lines were changed
  diff_stats=$(git diff --no-index --numstat "$base_path" "$head_path")
  added_lines=$(echo "$diff_stats" | awk '{print $1}')
  removed_lines=$(echo "$diff_stats" | awk '{print $2}')
  
  echo "FILE: $file **[$category]** **MODIFIED** (+$added_lines/-$removed_lines lines)" >> "$OUTPUT_FILE"
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
