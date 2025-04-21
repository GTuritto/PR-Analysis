# PowerShell version of analyze-pr-diff-min.sh
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

# --- Extract PR components ---
$PR_URL_PARTS = $PR_URL -split "/"
$OWNER = $PR_URL_PARTS[3]
$REPO = $PR_URL_PARTS[4]
$PR_NUMBER = $PR_URL_PARTS[6]

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

# --- Output file ---
$OUTPUT_FILE = "pr_diff_result.md"
"PR: $OWNER/$REPO #$PR_NUMBER" | Out-File -FilePath $OUTPUT_FILE
"Base: $BASE_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Head: $HEAD_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# --- File comparison ---
$NEW_FILES = @()
$DELETED_FILES = @()
$MODIFIED_FILES = @()

# Get all files in both directories
$BASE_FILES = Get-ChildItem -Path $BASE_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$BASE_DIR\", "") }
$HEAD_FILES = Get-ChildItem -Path $HEAD_DIR -Recurse -File | ForEach-Object { $_.FullName.Replace("$HEAD_DIR\", "") }

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

# --- Write simple lists ---
function Write-Section {
    param (
        [string]$title,
        [array]$files
    )
    
    if ($files.Count -eq 0) { return }
    
    $title | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($f in $files) {
        "- $f" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
}

Write-Section -title "New Files:" -files $NEW_FILES
Write-Section -title "Deleted Files:" -files $DELETED_FILES
Write-Section -title "Modified Files:" -files $MODIFIED_FILES

# --- Detailed diffs for modified files ---
foreach ($file in $MODIFIED_FILES) {
    $base_path = Join-Path $BASE_DIR $file
    $head_path = Join-Path $HEAD_DIR $file
    
    if ((Test-Path $base_path) -and (Test-Path $head_path)) {
        "File: $file" | Out-File -FilePath $OUTPUT_FILE -Append
        "<<<<>>>>" | Out-File -FilePath $OUTPUT_FILE -Append
        "<<<<previous>>>>" | Out-File -FilePath $OUTPUT_FILE -Append
        try {
            Get-Content $base_path | Out-File -FilePath $OUTPUT_FILE -Append
        }
        catch {
            "[Error reading base file]" | Out-File -FilePath $OUTPUT_FILE -Append
        }
        "<<<<new>>>>" | Out-File -FilePath $OUTPUT_FILE -Append
        try {
            Get-Content $head_path | Out-File -FilePath $OUTPUT_FILE -Append
        }
        catch {
            "[Error reading head file]" | Out-File -FilePath $OUTPUT_FILE -Append
        }
        "<<<<>>>>" | Out-File -FilePath $OUTPUT_FILE -Append
        "" | Out-File -FilePath $OUTPUT_FILE -Append
    }
}

# --- Cleanup ---
Remove-Item -Recurse -Force $BASE_DIR
Remove-Item -Recurse -Force $HEAD_DIR

Write-Output "Diff saved to $OUTPUT_FILE"
