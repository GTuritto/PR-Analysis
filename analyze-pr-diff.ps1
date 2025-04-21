# PowerShell version of analyze-pr-diff.sh
# Stop on errors
$ErrorActionPreference = "Stop"

# --- Dependencies check ---
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Error "This script requires 'jq'. Please install it."
    exit 1
}

# --- Input validation ---
if ($args.Count -lt 1) {
    Write-Output "Usage: $($MyInvocation.MyCommand.Name) <GitHub PR URL> [GitHub Token (optional)]"
    exit 1
}

$PR_URL = $args[0]
$GITHUB_TOKEN = if ($args.Count -gt 1) { $args[1] } else { "" }

# --- Extract owner, repo, and PR number ---
$PR_URL_PARTS = $PR_URL -split "/"
$OWNER = $PR_URL_PARTS[3]
$REPO = $PR_URL_PARTS[4]
$PR_NUMBER = $PR_URL_PARTS[6]

# --- GitHub API call to get PR info ---
$API_URL = "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER"
$AUTH_HEADER = @{}
if ($GITHUB_TOKEN) {
    $AUTH_HEADER = @{ "Authorization" = "token $GITHUB_TOKEN" }
}

Write-Output "Fetching PR info from GitHub API..."

$PR_INFO = Invoke-RestMethod -Uri $API_URL -Headers $AUTH_HEADER

$BASE_BRANCH = $PR_INFO.base.ref
$HEAD_BRANCH = $PR_INFO.head.ref
$CLONE_URL = $PR_INFO.head.repo.clone_url

Write-Output "Base branch: $BASE_BRANCH"
Write-Output "Head branch: $HEAD_BRANCH"

# --- Clone both branches into temp dirs ---
$BASE_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "pr_base_$([System.Guid]::NewGuid().ToString())"
$HEAD_DIR = Join-Path ([System.IO.Path]::GetTempPath()) "pr_head_$([System.Guid]::NewGuid().ToString())"

New-Item -ItemType Directory -Path $BASE_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $HEAD_DIR -Force | Out-Null

Write-Output "Cloning base branch..."
git clone --quiet --depth=1 --branch $BASE_BRANCH $CLONE_URL $BASE_DIR

Write-Output "Cloning head branch..."
git clone --quiet --depth=1 --branch $HEAD_BRANCH $CLONE_URL $HEAD_DIR

# --- Output file ---
$OUTPUT_FILE = "pr_diff_analysis.md"
"# PR Analysis for $OWNER/$REPO PR #$PR_NUMBER" | Out-File -FilePath $OUTPUT_FILE
"Base branch: ``$BASE_BRANCH``" | Out-File -FilePath $OUTPUT_FILE -Append
"Head branch: ``$HEAD_BRANCH``" | Out-File -FilePath $OUTPUT_FILE -Append
"Generated on: $(Get-Date)" | Out-File -FilePath $OUTPUT_FILE -Append
"`n---`n" | Out-File -FilePath $OUTPUT_FILE -Append

# --- Compare the two directories ---
Write-Output "Comparing branches..."

$MODIFIED_FILES = @()
$NEW_FILES = @()
$DELETED_FILES = @()

# Get all files in both directories
$BASE_FILES = Get-ChildItem -Path $BASE_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$BASE_DIR\", "").Replace("$BASE_DIR/", "") }
$HEAD_FILES = Get-ChildItem -Path $HEAD_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$HEAD_DIR\", "").Replace("$HEAD_DIR/", "") }

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

# --- Output results ---
function Write-Section {
    param (
        [string]$title,
        [array]$files
    )
    
    "`n## $title`n" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $files) {
        "- ``$file``" | Out-File -FilePath $OUTPUT_FILE -Append
    }
}

Write-Section -title "🟩 New Files" -files $NEW_FILES
Write-Section -title "🟥 Deleted Files" -files $DELETED_FILES
Write-Section -title "🟨 Modified Files" -files $MODIFIED_FILES

# --- Show diffs for modified files ---
"`n---`n`n# Detailed Diffs`n" | Out-File -FilePath $OUTPUT_FILE -Append

foreach ($file in $MODIFIED_FILES) {
    Write-Output "Processing diff for $file..."

    $base_file = Join-Path $BASE_DIR $file
    $head_file = Join-Path $HEAD_DIR $file

    if ((Test-Path $base_file) -and (Test-Path $head_file)) {
        "`n## 🔄 Modified: ``$file```n" | Out-File -FilePath $OUTPUT_FILE -Append
        '--------------' | Out-File -FilePath $OUTPUT_FILE -Append
        "--Original--`n" | Out-File -FilePath $OUTPUT_FILE -Append
        
        try {
            Get-Content $base_file | Out-File -FilePath $OUTPUT_FILE -Append
        }
        catch {
            "*Error reading base version*" | Out-File -FilePath $OUTPUT_FILE -Append
        }
        
        "`n--New--`n" | Out-File -FilePath $OUTPUT_FILE -Append
        
        try {
            Get-Content $head_file | Out-File -FilePath $OUTPUT_FILE -Append
        }
        catch {
            "*Error reading new version*" | Out-File -FilePath $OUTPUT_FILE -Append
        }
        
        '--------------' | Out-File -FilePath $OUTPUT_FILE -Append
    }
}

# --- Cleanup ---
Remove-Item -Recurse -Force $BASE_DIR
Remove-Item -Recurse -Force $HEAD_DIR

Write-Output "`n✅ Analysis complete. Output written to: $OUTPUT_FILE"
