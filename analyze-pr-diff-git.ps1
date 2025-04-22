# Minimized PowerShell script for GitHub PR analysis optimized for LLMs
# Stop on errors
$ErrorActionPreference = "Stop"

# Modified to include PR commentaries and conversations in the final output

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

# Fetch PR comments
function Get-PRComments {
    param (
        [string]$Owner,
        [string]$Repo,
        [string]$PrNumber,
        [hashtable]$Headers
    )
    
    # Get comments from the PR issue
    try {
        $commentsUrl = "https://api.github.com/repos/$Owner/$Repo/issues/$PrNumber/comments"
        Write-Output "Fetching PR comments from $commentsUrl"
        $response = Invoke-RestMethod -Uri $commentsUrl -Headers $Headers -ErrorAction Stop
        Write-Output "Retrieved $($response.Count) PR comments"
        return $response
    } catch {
        Write-Warning "Error fetching PR comments: $_"
        # Return empty array instead of failing
        return @()
    }
}

# Fetch PR review comments (specific to code lines)
function Get-PRReviewComments {
    param (
        [string]$Owner,
        [string]$Repo,
        [string]$PrNumber,
        [hashtable]$Headers
    )
    
    # Get review comments from the PR (comments on specific lines of code)
    try {
        $reviewCommentsUrl = "https://api.github.com/repos/$Owner/$Repo/pulls/$PrNumber/comments"
        Write-Output "Fetching PR review comments from $reviewCommentsUrl"
        $response = Invoke-RestMethod -Uri $reviewCommentsUrl -Headers $Headers -ErrorAction Stop
        Write-Output "Retrieved $($response.Count) PR review comments"
        return $response
    } catch {
        Write-Warning "Error fetching PR review comments: $_"
        # Return empty array instead of failing
        return @()
    }
}

# Fetch PR reviews
function Get-PRReviews {
    param (
        [string]$Owner,
        [string]$Repo,
        [string]$PrNumber,
        [hashtable]$Headers
    )
    
    # Get reviews from the PR
    try {
        $reviewsUrl = "https://api.github.com/repos/$Owner/$Repo/pulls/$PrNumber/reviews"
        Write-Output "Fetching PR reviews from $reviewsUrl"
        $response = Invoke-RestMethod -Uri $reviewsUrl -Headers $Headers -ErrorAction Stop
        Write-Output "Retrieved $($response.Count) PR reviews"
        return $response
    } catch {
        Write-Warning "Error fetching PR reviews: $_"
        # Return empty array instead of failing
        return @()
    }
}

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
# Use literal strings to prevent colon parsing issues
$colonStr = ':'
('- Total Changes' + $colonStr + ' ' + $totalFiles + ' files') | Out-File -FilePath $OUTPUT_FILE -Append

$filesStr = '- Files by Type' + $colonStr + ' New' + $colonStr + ' ' + $NEW_FILES.Count + ' | Modified' + $colonStr + ' ' + $MODIFIED_FILES.Count + ' | Deleted' + $colonStr + ' ' + $DELETED_FILES.Count
$filesStr | Out-File -FilePath $OUTPUT_FILE -Append
"- Estimated Tokens: $totalTokenEstimate" | Out-File -FilePath $OUTPUT_FILE -Append
"- Processing Time: $(Get-Date) GMT" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Write file category breakdown
"**Files by Category**" | Out-File -FilePath $OUTPUT_FILE -Append
foreach ($category in $fileCategories.Keys | Sort-Object) {
    ('- ' + $category + $colonStr + ' ' + $fileCategories[$category] + ' files') | Out-File -FilePath $OUTPUT_FILE -Append
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

# --- Fetch and add PR comments and conversations to the output file
"## PR COMMENTARIES AND CONVERSATIONS" | Out-File -FilePath $OUTPUT_FILE -Append
"" | Out-File -FilePath $OUTPUT_FILE -Append

# Fetch PR comments and reviews
Write-Output "Fetching PR comments and conversations..."
try {
    $PR_COMMENTS = Get-PRComments -Owner $OWNER -Repo $REPO -PrNumber $PR_NUMBER -Headers $AUTH_HEADER
    $PR_REVIEW_COMMENTS = Get-PRReviewComments -Owner $OWNER -Repo $REPO -PrNumber $PR_NUMBER -Headers $AUTH_HEADER
    $PR_REVIEWS = Get-PRReviews -Owner $OWNER -Repo $REPO -PrNumber $PR_NUMBER -Headers $AUTH_HEADER

    # Add PR general comments to the output file
    "### PR Comments" | Out-File -FilePath $OUTPUT_FILE -Append
    "" | Out-File -FilePath $OUTPUT_FILE -Append

    if ($PR_COMMENTS.Count -eq 0) {
        "No general comments found on this PR." | Out-File -FilePath $OUTPUT_FILE -Append
    } else {
        Write-Output "Processing $($PR_COMMENTS.Count) PR comments for output"
        foreach ($comment in $PR_COMMENTS) {
            try {
                # Create a formatted date if possible
                $commentDate = $comment.created_at
                try {
                    $dateObj = [DateTime]::Parse($comment.created_at)
                    $commentDate = $dateObj.ToString('yyyy-MM-dd HH:mm:ss')
                } catch {
                    # Use the original string if parsing fails
                }
                
                # Format the comment header
                $commentHeader = "**@$($comment.user.login)** commented on $commentDate$colonStr"
                $commentHeader | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
                
                # Process the comment body - replace escaped newlines with actual newlines
                $bodyText = $comment.body -replace '\r\n', "`n" -replace '\r', "`n" -replace '\n', "`n"
                $bodyText | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
                "---" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            } catch {
                Write-Warning "Error processing comment: $_"
                "*Error processing a comment*" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            }
        }
    }

    # Add PR review comments to the output file
    "### Code Review Comments" | Out-File -FilePath $OUTPUT_FILE -Append
    "" | Out-File -FilePath $OUTPUT_FILE -Append

    if ($PR_REVIEW_COMMENTS.Count -eq 0) {
        "No code review comments found on this PR." | Out-File -FilePath $OUTPUT_FILE -Append
    } else {
        Write-Output "Processing $($PR_REVIEW_COMMENTS.Count) PR review comments for output"
        foreach ($comment in $PR_REVIEW_COMMENTS) {
            try {
                # Create a formatted date if possible
                $commentDate = $comment.created_at
                try {
                    $dateObj = [DateTime]::Parse($comment.created_at)
                    $commentDate = $dateObj.ToString('yyyy-MM-dd HH:mm:ss')
                } catch {
                    # Use the original string if parsing fails
                }
                
                # Get line information safely
                $lineInfo = ""
                if ($null -ne $comment.position) {
                    $lineInfo = " (line $($comment.position))"
                }
                
                # Format the comment header
                $commentHeader = "**@$($comment.user.login)** commented on $($comment.path)$lineInfo on $commentDate$colonStr"
                $commentHeader | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
                
                # Process the comment body - replace escaped newlines with actual newlines
                $bodyText = $comment.body -replace '\r\n', "`n" -replace '\r', "`n" -replace '\n', "`n"
                $bodyText | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
                "---" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            } catch {
                Write-Warning "Error processing review comment: $_"
                "*Error processing a review comment*" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            }
        }
    }

    # Add PR reviews to the output file
    "### PR Reviews" | Out-File -FilePath $OUTPUT_FILE -Append
    "" | Out-File -FilePath $OUTPUT_FILE -Append

    if ($PR_REVIEWS.Count -eq 0) {
        "No reviews found on this PR." | Out-File -FilePath $OUTPUT_FILE -Append
    } else {
        Write-Output "Processing $($PR_REVIEWS.Count) PR reviews for output"
        foreach ($review in $PR_REVIEWS) {
            try {
                # Create a formatted date if possible
                $reviewDate = $review.submitted_at
                try {
                    $dateObj = [DateTime]::Parse($review.submitted_at)
                    $reviewDate = $dateObj.ToString('yyyy-MM-dd HH:mm:ss')
                } catch {
                    # Use the original string if parsing fails
                }
                
                # Format review state (capitalize first letter)
                $reviewState = $review.state
                if ($reviewState) {
                    $reviewState = $reviewState.Substring(0,1).ToUpper() + $reviewState.Substring(1).ToLower()
                } else {
                    $reviewState = "reviewed"
                }
                
                # Format the review header
                $reviewHeader = "**@$($review.user.login)** $reviewState on $reviewDate$colonStr"
                $reviewHeader | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
                
                # Process the review body
                if ($review.body) {
                    # Replace escaped newlines with actual newlines
                    $bodyText = $review.body -replace '\r\n', "`n" -replace '\r', "`n" -replace '\n', "`n"
                    $bodyText | Out-File -FilePath $OUTPUT_FILE -Append
                    "" | Out-File -FilePath $OUTPUT_FILE -Append
                } else {
                    "(No review comment provided)" | Out-File -FilePath $OUTPUT_FILE -Append
                    "" | Out-File -FilePath $OUTPUT_FILE -Append
                }
                "---" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            } catch {
                Write-Warning "Error processing review: $_"
                "*Error processing a review*" | Out-File -FilePath $OUTPUT_FILE -Append
                "" | Out-File -FilePath $OUTPUT_FILE -Append
            }
        }
    }
} catch {
    Write-Warning "Failed to fetch PR comments: $_"
    "Could not retrieve PR comments and conversations due to an error." | Out-File -FilePath $OUTPUT_FILE -Append
}

# --- Cleanup temporary directories
Remove-Item -Path $BASE_DIR -Recurse -Force
Remove-Item -Path $HEAD_DIR -Recurse -Force

Write-Output "Diff with PR commentaries saved to $OUTPUT_FILE"
