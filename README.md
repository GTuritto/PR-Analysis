# PR Analysis Tools for LLM Code Review

This repository contains intelligent, zero-dependency scripts that generate optimized PR diffs with rich metadata, providing perfect context for LLMs (like ChatGPT or Claude) to perform high-quality code reviews.

## Scripts

### GitHub PR Analysis

- `analyze-pr-diff-git.sh` - Bash script for GitHub PR diff extraction
- `analyze-pr-diff-git.ps1` - PowerShell script for GitHub PR diff extraction

### Azure DevOps PR Analysis

- `analyze-pr-diff-azdo.ps1` - PowerShell script for Azure DevOps PR diff extraction

## Usage

```bash
# For GitHub PR analysis with Bash
./analyze-pr-diff-git.sh <GitHub PR URL> [GitHub Token]

# For GitHub PR analysis with PowerShell
./analyze-pr-diff-git.ps1 <GitHub PR URL> [GitHub Token]

# For Azure DevOps PR analysis with PowerShell
./analyze-pr-diff-azdo.ps1 -PR_URL <Azure_DevOps_PR_URL> [-PAT <PERSONAL_ACCESS_TOKEN>]
```

## Requirements

- `git` - For cloning repositories and generating diffs (the only external dependency)
- Access to GitHub or Azure DevOps (with optional token for API rate limits)

## Features

### Zero External Dependencies

- **Pure Bash Implementation**: The shell script uses only Bash built-ins and standard Unix tools
- **Native PowerShell**: The PowerShell scripts use only built-in PowerShell capabilities
- **No Third-Party Tools**: No need to install jq, Python, or any other external tools

### LLM-Optimized Output

The scripts generate enhanced markdown files (`pr_diff_result.md` or `pr_diff_analysis.md`) with:

#### 1. Rich Metadata

- **Intelligent File Categorization**: Files automatically categorized as Code, Config, Docs, Tests, Styles, etc.
- **Token Estimation**: Approximate token counts for each file and the entire PR (helps LLMs manage context windows)
- **File Statistics**: Size in KB, added/removed line counts, and modification status

#### 2. Structured Information

- **PR Context**: Basic information about the PR, branches, and repositories
- **Summary Statistics**: Total files, categories breakdown, and estimated tokens
- **File Category Lists**: Files grouped by type with comprehensive metadata
- **Complete New File Content**: Full content of newly added files
- **Smart Diffs**: Clean, focused diffs with 3 lines of context

### Benefits for LLMs

This format provides critical context that dramatically improves code review quality:

- **Category awareness**: Understand file types without inference
- **Change scope awareness**: Precisely gauge the size and complexity of changes
- **Visual indicators**: Clearly identify newly added, modified, and removed files
- **Context management**: Make better use of available token context windows

## Example Output

The scripts generate a rich, structured markdown file with this format:

```markdown
# PR REVIEW CONTEXT

PR: user/repo #123
URL: https://github.com/user/repo/pull/123
Base Branch: main
Head Branch: feature-branch
Generated: Mon Apr 21 20:04:12 CEST 2025

## PR SUMMARY

**Repository Stats**
- Total Changes: a files
- Files by Type: New: 1 | Modified: 2 | Deleted: 1
- Estimated Tokens: 1250
- Processing Time: Mon Apr 21 20:04:12 CEST 2025 GMT

**Files by Category**
- Code: 2 files
- Config: 1 file
- Docs: 1 file

### New Files:
- **[Code]** src/new.js (4.25 KB, ~1064 tokens)

### NEW FILE CONTENTS

FILE: src/new.js **[Code]** **NEWLY ADDED**
<NEW_CONTENT>
// New file content here
</NEW_CONTENT>

### Deleted Files:
- **[Config]** config/settings.json (0.5 KB, ~125 tokens) **REMOVED**

### Modified Files:
- **[Code]** src/main.js (2.8 KB, ~700 tokens) **MODIFIED**
- **[Docs]** README.md (1.2 KB, ~300 tokens) **MODIFIED**

### DIFF SUMMARY

FILE: src/main.js **[Code]** **MODIFIED** (+5/-2 lines)
<DIFF>
@@ -1,5 +1,5 @@
  // File header
- // Original content
+ // Modified content with new functionality
  // Footer
</DIFF>
```

This enhanced format offers everything an LLM needs for high-quality code review - providing explicit file categorization, token estimates, and clear visual indicators of what changed.
