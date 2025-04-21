# Minimized PowerShell script for GitHub PR analysis optimized for LLMs
# Stop on errors
$ErrorActionPreference = "Stop"

# --- Requirements check ---
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Error "jq is required. Please install it."
    exit 1
}

# --- Input ---
if ($args.Count -lt 1) {
    Write-Output "Usage: $($MyInvocation.MyCommand.Name) <GitHub PR URL> [GitHub Token (optional)]"
    exit 1
}

$PR_URL = $args[0]
$GITHUB_TOKEN = if ($args.Count -gt 1) { $args[1] } else { "" }

# --- Extract PR components from URL ---
try {
    # Parse GitHub PR URL (format: https://github.com/owner/repo/pull/123)
    $URI = [System.Uri]$PR_URL
    if ($URI.Host -ne "github.com") {
        throw "Not a GitHub URL. Expected format: https://github.com/owner/repo/pull/123"
    }
    
    $PathSegments = $URI.AbsolutePath.TrimStart('/') -split '/'
    if ($PathSegments.Length -lt 4 -or $PathSegments[2] -ne "pull") {
        throw "Invalid GitHub PR URL format. Expected: https://github.com/owner/repo/pull/123"
    }
    
    $OWNER = $PathSegments[0]
    $REPO = $PathSegments[1]
    $PR_NUMBER = $PathSegments[3]
    
    Write-Output "Analyzing PR #$PR_NUMBER from $OWNER/$REPO..."
} 
catch {
    Write-Error "Failed to parse GitHub PR URL: $_"
    Write-Error "Expected format: https://github.com/owner/repo/pull/123"
    exit 1
}

# Owner, Repo, and PR_NUMBER are already extracted from the URL above

$API_URL = "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
$AUTH_HEADER = @{}
if ($GITHUB_TOKEN) {
    $AUTH_HEADER = @{ "Authorization" = "token $GITHUB_TOKEN" }
}

Write-Output "Fetching PR information..."

$PR_INFO = Invoke-RestMethod -Uri $API_URL -Headers $AUTH_HEADER

$BASE_BRANCH = $PR_INFO.base.ref
$HEAD_BRANCH = $PR_INFO.head.ref
$CLONE_URL = $PR_INFO.head.repo.clone_url

# --- Clone base and head branches ---
$BASE_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
$HEAD_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()

New-Item -ItemType Directory -Path $BASE_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $HEAD_DIR -Force | Out-Null

git clone --quiet --depth=1 --branch $BASE_BRANCH $CLONE_URL $BASE_DIR
git clone --quiet --depth=1 --branch $HEAD_BRANCH $CLONE_URL $HEAD_DIR

# --- Output file optimized for LLM consumption ---
$OUTPUT_FILE = "pr_diff_result.md"
"# PR REVIEW CONTEXT" | Out-File -FilePath $OUTPUT_FILE
"" | Out-File -FilePath $OUTPUT_FILE -Append
"PR: $OWNER/$REPO #$PR_NUMBER" | Out-File -FilePath $OUTPUT_FILE -Append
"URL: $PR_URL" | Out-File -FilePath $OUTPUT_FILE -Append
"Base Branch: $BASE_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Head Branch: $HEAD_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Generated: $(Get-Date)" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# --- File comparison with optimized output for LLMs ---
$NEW_FILES = @()
$DELETED_FILES = @()
$MODIFIED_FILES = @()

# Get all files in both directories
$BASE_FILES = Get-ChildItem -Path $BASE_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$BASE_DIR\\", "").Replace("$BASE_DIR/", "") }
$HEAD_FILES = Get-ChildItem -Path $HEAD_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$HEAD_DIR\\", "").Replace("$HEAD_DIR/", "") }

# Find new files (in HEAD but not in BASE)
foreach ($file in $HEAD_FILES) {
    if ($BASE_FILES -notcontains $file) {
        $NEW_FILES += $file
    }
}

# Find deleted files (in BASE but not in HEAD)
foreach ($file in $BASE_FILES) {
    if ($HEAD_FILES -notcontains $file) {
        $DELETED_FILES += $file
    }
}

# Find modified files (in both but different)
foreach ($file in $BASE_FILES) {
    if ($HEAD_FILES -contains $file) {
        $base_path = Join-Path $BASE_DIR $file
        $head_path = Join-Path $HEAD_DIR $file
        if ((Get-FileHash $base_path).Hash -ne (Get-FileHash $head_path).Hash) {
            $MODIFIED_FILES += $file
        }
    }
}

# --- Write PR Summary ---
"## PR SUMMARY" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Summary counts for quick understanding
"Total Changes: $($NEW_FILES.Count + $DELETED_FILES.Count + $MODIFIED_FILES.Count) files" | Out-File -FilePath $OUTPUT_FILE -Append
"New: $($NEW_FILES.Count) | Modified: $($MODIFIED_FILES.Count) | Deleted: $($DELETED_FILES.Count)" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Write detailed file lists
if ($NEW_FILES.Count -gt 0) {
    "### New Files:" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $NEW_FILES) {
        "- $file" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
    
    # Also include the complete content of new files (useful for LLM review)
    "### NEW FILE CONTENTS" | Out-File -FilePath $OUTPUT_FILE -Append
    "" | Out-File -FilePath $OUTPUT_FILE -Append
    
    foreach ($file in $NEW_FILES) {
        $head_path = Join-Path $HEAD_DIR $file
        if (Test-Path $head_path) {
            "FILE: $file" | Out-File -FilePath $OUTPUT_FILE -Append
            "<NEW_CONTENT>" | Out-File -FilePath $OUTPUT_FILE -Append
            Get-Content $head_path | Out-File -FilePath $OUTPUT_FILE -Append
            "</NEW_CONTENT>" | Out-File -FilePath $OUTPUT_FILE -Append
            "" | Out-File -FilePath $OUTPUT_FILE -Append
        }
    }
}

if ($DELETED_FILES.Count -gt 0) {
    "### Deleted Files:" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $DELETED_FILES) {
        "- $file" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
}

if ($MODIFIED_FILES.Count -gt 0) {
    "### Modified Files:" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $MODIFIED_FILES) {
        "- $file" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
}

# --- Optimize diff output for modified files (for LLM consumption) ---
"### DIFF SUMMARY" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

foreach ($file in $MODIFIED_FILES) {
    $base_path = Join-Path $BASE_DIR $file
    $head_path = Join-Path $HEAD_DIR $file
    
    if ((Test-Path $base_path) -and (Test-Path $head_path)) {
        "FILE: $file" | Out-File -FilePath $OUTPUT_FILE -Append
        "<DIFF>" | Out-File -FilePath $OUTPUT_FILE -Append
        
        # Use git diff with context to get a concise diff
        $diff = & git diff --no-index --unified=3 $base_path $head_path
        
        # Remove the git diff header lines and write a cleaner output
        $diff | Select-Object -Skip 4 | ForEach-Object {
            $_ -replace "^\\+", "+ " -replace "^-", "- " | Out-File -FilePath $OUTPUT_FILE -Append
        }
        
        "</DIFF>" | Out-File -FilePath $OUTPUT_FILE -Append
        "" | Out-File -FilePath $OUTPUT_FILE -Append
    }
}

# --- Cleanup ---
Remove-Item -Recurse -Force $BASE_DIR
Remove-Item -Recurse -Force $HEAD_DIR

Write-Output "Diff saved to $OUTPUT_FILE"
