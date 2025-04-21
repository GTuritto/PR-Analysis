# PowerShell version of analyze-pr-diff.sh adapted for Azure DevOps
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
    
    Write-Output "Extracted from URL:"
    Write-Output "Organization: $Organization"
    Write-Output "Project: $Project"
    Write-Output "Repository: $Repository"
    Write-Output "PR ID: $PullRequestId"
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

Write-Output "Fetching PR info from Azure DevOps API..."

# --- Get PR details ---
$PrApiUrl = "$AzDoBaseUrl/_apis/git/repositories/$Repository/pullRequests/$PullRequestId`?api-version=$ApiVersion"
$PR_INFO = Invoke-RestMethod -Uri $PrApiUrl -Headers $AuthHeader -Method Get

$BASE_BRANCH = $PR_INFO.targetRefName -replace "refs/heads/"
$HEAD_BRANCH = $PR_INFO.sourceRefName -replace "refs/heads/"
$CLONE_URL = $PR_INFO.repository.webUrl

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

# --- Output file optimized for LLM consumption ---
$OUTPUT_FILE = "pr_diff_analysis.md"
"# PR REVIEW CONTEXT" | Out-File -FilePath $OUTPUT_FILE
"" | Out-File -FilePath $OUTPUT_FILE -Append
"PR: $Repository #$PullRequestId" | Out-File -FilePath $OUTPUT_FILE -Append
"URL: $PR_URL" | Out-File -FilePath $OUTPUT_FILE -Append
"Organization: $Organization" | Out-File -FilePath $OUTPUT_FILE -Append
"Project: $Project" | Out-File -FilePath $OUTPUT_FILE -Append
"Base Branch: $BASE_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Head Branch: $HEAD_BRANCH" | Out-File -FilePath $OUTPUT_FILE -Append
"Generated: $(Get-Date)" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

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
    Write-Output "Processing diff for $file..."

    $base_file = Join-Path $BASE_DIR $file
    $head_file = Join-Path $HEAD_DIR $file

    if ((Test-Path $base_file) -and (Test-Path $head_file)) {
        "FILE: $file" | Out-File -FilePath $OUTPUT_FILE -Append
        "<DIFF>" | Out-File -FilePath $OUTPUT_FILE -Append
        
        # Use git diff with context to get a concise diff
        $diff = & git diff --no-index --unified=3 $base_file $head_file
        
        # Remove the git diff header lines and write a cleaner output
        $diff | Select-Object -Skip 4 | ForEach-Object {
            $_ -replace "^\\+", "+ " -replace "^-", "- " | Out-File -FilePath $OUTPUT_FILE -Append
        }
        
        "</DIFF>" | Out-File -FilePath $OUTPUT_FILE -Append
        "" | Out-File -FilePath $OUTPUT_FILE -Append
    }
}

# We're simplifying the script to focus on generating the diff file for LLM consumption
# Removing the PR comment feature to keep things minimal and focused

# --- Cleanup ---
Remove-Item -Recurse -Force $BASE_DIR
Remove-Item -Recurse -Force $HEAD_DIR

Write-Output "`n✅ Analysis complete. Output written to: $OUTPUT_FILE"
