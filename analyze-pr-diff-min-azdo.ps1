# PowerShell minimalist version for Azure DevOps
# Stop on errors
$ErrorActionPreference = "Stop"

# --- Dependencies check ---
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Error "This script requires 'jq'. Please install it."
    exit 1
}

# --- Input validation ---
param (
    [Parameter(Mandatory=$true)]
    [string]$PR_URL,
    
    [Parameter(Mandatory=$false)]
    [string]$PAT = ""
)

# --- Extract PR components from URL ---
# Expected URL format: https://dev.azure.com/{organization}/{project}/_git/{repository}/pullrequest/{id}
# Or alternative format: https://{organization}.visualstudio.com/{project}/_git/{repository}/pullrequest/{id}

try {
    $URI = [Uri]$PR_URL
    $PathSegments = $URI.AbsolutePath -split '/'
    
    # Different parsing logic based on the URL format
    if ($URI.Host -eq "dev.azure.com") {
        # Format: https://dev.azure.com/{organization}/{project}/_git/{repository}/pullrequest/{id}
        $Organization = $PathSegments[1]
        $Project = $PathSegments[2]
        $RepoIndex = [array]::IndexOf($PathSegments, '_git')
        $Repository = $PathSegments[$RepoIndex + 1]
        $PullRequestId = $PathSegments[$RepoIndex + 3]
    } 
    elseif ($URI.Host -match "\.visualstudio\.com$") {
        # Format: https://{organization}.visualstudio.com/{project}/_git/{repository}/pullrequest/{id}
        $Organization = $URI.Host -replace "\.visualstudio\.com$", ""
        $Project = $PathSegments[1]
        $RepoIndex = [array]::IndexOf($PathSegments, '_git')
        $Repository = $PathSegments[$RepoIndex + 1]
        $PullRequestId = $PathSegments[$RepoIndex + 3]
    }
    else {
        throw "Unrecognized Azure DevOps URL format"
    }
} 
catch {
    Write-Error "Failed to parse Azure DevOps PR URL. Please check the format and try again."
    Write-Error "Expected format: https://dev.azure.com/{organization}/{project}/_git/{repository}/pullrequest/{id}"
    Write-Error "Or: https://{organization}.visualstudio.com/{project}/_git/{repository}/pullrequest/{id}"
    Write-Error "Error: $_"
    exit 1
}

# --- Setup Azure DevOps connection ---
$AzDoBaseUrl = "https://dev.azure.com/$Organization/$Project"
$ApiVersion = "6.0"
$AuthHeader = @{}

if ($PAT) {
    $Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
    $AuthHeader = @{
        "Authorization" = "Basic $Base64AuthInfo"
    }
}

# --- Get PR details ---
$PrApiUrl = "$AzDoBaseUrl/_apis/git/repositories/$Repository/pullRequests/$PullRequestId`?api-version=$ApiVersion"
$PR_INFO = Invoke-RestMethod -Uri $PrApiUrl -Headers $AuthHeader -Method Get

$BASE_BRANCH = $PR_INFO.targetRefName -replace "refs/heads/"
$HEAD_BRANCH = $PR_INFO.sourceRefName -replace "refs/heads/"
$CLONE_URL = $PR_INFO.repository.webUrl

# --- Clone both branches into temp dirs ---
$BASE_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
$HEAD_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()

New-Item -ItemType Directory -Path $BASE_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $HEAD_DIR -Force | Out-Null

git clone --quiet --depth=1 --branch $BASE_BRANCH $CLONE_URL $BASE_DIR
git clone --quiet --depth=1 --branch $HEAD_BRANCH $CLONE_URL $HEAD_DIR

# --- Output file ---
$OUTPUT_FILE = "pr_diff_result.md"
"PR: $Repository #$PullRequestId" | Out-File -FilePath $OUTPUT_FILE
"Base: $BASE_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Head: $HEAD_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# --- File comparison ---
$NEW_FILES = @()
$DELETED_FILES = @()
$MODIFIED_FILES = @()

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
