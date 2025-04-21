# Minimized PowerShell script for GitHub PR analysis optimized for LLMs
# Stop on errors
$ErrorActionPreference = "Stop"

# --- No external dependencies required ---
# This script uses only native PowerShell capabilities

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

# Use native PowerShell JSON handling
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

# Define file type categorization function
function Get-FileCategory {
    param (
        [string]$FilePath
    )

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    # Define file categories based on extension
    $categories = @{
        # Code files
        Code = @(
            '.js', '.jsx', '.ts', '.tsx', '.py', '.rb', '.php', '.java', '.c', '.cpp', '.cs', 
            '.go', '.rs', '.swift', '.kt', '.scala', '.clj', '.fnl', '.lua', '.ex', '.exs',
            '.erl', '.fs', '.fsx', '.pl', '.pm', '.t', '.groovy', '.dart', '.pas'
        )
        # Configuration files
        Config = @(
            '.json', '.xml', '.yaml', '.yml', '.toml', '.ini', '.cfg', '.conf', '.config',
            '.properties', '.props', '.env', '.eslintrc', '.babelrc', '.editorconfig', '.prettierrc',
            '.dockerignore', '.gitignore', '.gitattributes', '.npmrc', '.htaccess', '.gitmodules'
        )
        # Documentation files
        Docs = @(
            '.md', '.mdx', '.txt', '.rtf', '.pdf', '.doc', '.docx', '.html', '.htm', '.rst',
            '.wiki', '.adoc', '.tex', '.asciidoc', '.markdown', '.mdown', '.mkdn'
        )
        # Test files
        Tests = @(
            '.test.js', '.spec.js', '.test.ts', '.spec.ts', '.test.jsx', '.spec.jsx',
            '.test.tsx', '.spec.tsx', '.test.py', '.spec.py', '.test.rb', '.spec.rb'
        )
        # Style files
        Styles = @('.css', '.scss', '.sass', '.less', '.styl', '.stylus', '.pcss')
        # Template files
        Templates = @('.html', '.htm', '.ejs', '.hbs', '.handlebars', '.mustache', '.twig', '.liquid', '.njk', '.jade', '.pug')
        # Data files
        Data = @('.csv', '.tsv', '.json', '.xml', '.yaml', '.yml', '.sqlite', '.sql')
        # Image files
        Images = @('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.bmp', '.ico')
    }

    # Check for test files first (by name pattern)
    if ($FilePath -match '\.(spec|test)\.' -or $FilePath -match '(specs?|tests?|__tests__)\\') {
        return "Tests"
    }
    
    # Check each category
    foreach ($category in $categories.Keys) {
        foreach ($ext in $categories[$category]) {
            if ($FilePath.EndsWith($ext) -or $extension -eq $ext) {
                return $category
            }
        }
    }
    
    # Default to "Other" if no match
    return "Other"
}

# Function to estimate tokens in a file
function Get-TokenEstimate {
    param (
        [string]$FilePath
    )
    
    if (!(Test-Path $FilePath)) {
        return 0
    }
    
    # Read file content
    $content = Get-Content -Path $FilePath -Raw
    if (-not $content) {
        return 0
    }
    
    # Very approximate estimation: ~4 chars per token for code (rough approximation)
    $charCount = $content.Length
    return [math]::Ceiling($charCount / 4)
}

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

# --- Write PR Summary with enhanced statistics ---
"## PR SUMMARY" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Calculate token estimates and collect file categories
$totalFiles = $NEW_FILES.Count + $DELETED_FILES.Count + $MODIFIED_FILES.Count
$totalTokenEstimate = 0
$fileCategories = @{}

# Process new files for token estimates and categories
foreach ($file in $NEW_FILES) {
    $head_path = Join-Path $HEAD_DIR $file
    $category = Get-FileCategory -FilePath $file
    $tokens = Get-TokenEstimate -FilePath $head_path
    $totalTokenEstimate += $tokens
    
    if ($fileCategories.ContainsKey($category)) {
        $fileCategories[$category] += 1
    } else {
        $fileCategories[$category] = 1
    }
}

# Process modified files for token estimates and categories
foreach ($file in $MODIFIED_FILES) {
    $head_path = Join-Path $HEAD_DIR $file
    $category = Get-FileCategory -FilePath $file
    $tokens = Get-TokenEstimate -FilePath $head_path
    $totalTokenEstimate += $tokens
    
    if ($fileCategories.ContainsKey($category)) {
        $fileCategories[$category] += 1
    } else {
        $fileCategories[$category] = 1
    }
}

# Write enhanced summary statistics
"**Repository Stats**" | Out-File -FilePath $OUTPUT_FILE -Append
"- Total Changes: $totalFiles files" | Out-File -FilePath $OUTPUT_FILE -Append
"- Files by Type: New: $($NEW_FILES.Count) | Modified: $($MODIFIED_FILES.Count) | Deleted: $($DELETED_FILES.Count)" | Out-File -FilePath $OUTPUT_FILE -Append
"- Estimated Tokens: $totalTokenEstimate" | Out-File -FilePath $OUTPUT_FILE -Append
"- Processing Time: $(Get-Date) GMT" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Write file category breakdown
"**Files by Category**" | Out-File -FilePath $OUTPUT_FILE -Append
foreach ($category in $fileCategories.Keys | Sort-Object) {
    "- $category: $($fileCategories[$category]) files" | Out-File -FilePath $OUTPUT_FILE -Append
}
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Write detailed file lists
if ($NEW_FILES.Count -gt 0) {
    "### New Files:" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $NEW_FILES) {
        $category = Get-FileCategory -FilePath $file
        $head_path = Join-Path $HEAD_DIR $file
        $tokens = Get-TokenEstimate -FilePath $head_path
        $fileSize = (Get-Item -Path $head_path).Length
        $sizeKb = [math]::Round($fileSize / 1KB, 2)
        "- **[$category]** $file ($sizeKb KB, ~$tokens tokens)" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
    
    # Also include the complete content of new files (useful for LLM review)
    "### NEW FILE CONTENTS" | Out-File -FilePath $OUTPUT_FILE -Append
    "" | Out-File -FilePath $OUTPUT_FILE -Append
    
    foreach ($file in $NEW_FILES) {
        $head_path = Join-Path $HEAD_DIR $file
        if (Test-Path $head_path) {
            $category = Get-FileCategory -FilePath $file
            "FILE: $file **[$category]** **NEWLY ADDED**" | Out-File -FilePath $OUTPUT_FILE -Append
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
        $category = Get-FileCategory -FilePath $file
        $base_path = Join-Path $BASE_DIR $file
        $tokens = Get-TokenEstimate -FilePath $base_path
        $fileSize = 0
        if (Test-Path $base_path) {
            $fileSize = (Get-Item -Path $base_path).Length
        }
        $sizeKb = [math]::Round($fileSize / 1KB, 2)
        "- **[$category]** $file ($sizeKb KB, ~$tokens tokens) **REMOVED**" | Out-File -FilePath $OUTPUT_FILE -Append
    }
    "" | Out-File -FilePath $OUTPUT_FILE -Append
}

if ($MODIFIED_FILES.Count -gt 0) {
    "### Modified Files:" | Out-File -FilePath $OUTPUT_FILE -Append
    foreach ($file in $MODIFIED_FILES) {
        $category = Get-FileCategory -FilePath $file
        $head_path = Join-Path $HEAD_DIR $file
        $base_path = Join-Path $BASE_DIR $file
        $tokens = Get-TokenEstimate -FilePath $head_path
        $fileSize = 0
        if (Test-Path $head_path) {
            $fileSize = (Get-Item -Path $head_path).Length
        }
        $sizeKb = [math]::Round($fileSize / 1KB, 2)
        "- **[$category]** $file ($sizeKb KB, ~$tokens tokens) **MODIFIED**" | Out-File -FilePath $OUTPUT_FILE -Append
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
        $category = Get-FileCategory -FilePath $file
        $tokens = Get-TokenEstimate -FilePath $head_path
        $fileSize = (Get-Item -Path $head_path).Length
        $sizeKb = [math]::Round($fileSize / 1KB, 2)
        
        # Check how many lines were changed
        $diffCount = & git diff --no-index --numstat $base_path $head_path
        $diffParts = $diffCount -split "\t"
        $addedLines = $diffParts[0]
        $removedLines = $diffParts[1]
        
        "FILE: $file **[$category]** **MODIFIED** (+$addedLines/-$removedLines lines)" | Out-File -FilePath $OUTPUT_FILE -Append
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
