# PR Analysis Tools for LLM Code Review

This repository contains lightweight scripts to generate optimized PR diffs that provide the perfect context for LLMs (like ChatGPT or Claude) to perform high-quality code reviews.

## Scripts

### GitHub PR Analysis

- `analyze-pr-diff-min.sh` - Bash script for GitHub PR diff extraction
- `analyze-pr-diff-min.ps1` - PowerShell script for GitHub PR diff extraction

### Azure DevOps PR Analysis

- `analyze-pr-diff-azdo.ps1` - PowerShell script for Azure DevOps PR diff extraction
- `azure-pipelines.yml` - Azure DevOps pipeline configuration for automation

## Usage

```bash
# For GitHub PR analysis with Bash
./analyze-pr-diff-min.sh <GitHub PR URL> [GitHub Token]

# For GitHub PR analysis with PowerShell
./analyze-pr-diff-min.ps1 <GitHub PR URL> [GitHub Token]

# For Azure DevOps PR analysis with PowerShell
./analyze-pr-diff-azdo.ps1 -PR_URL <Azure_DevOps_PR_URL> [-PAT <PERSONAL_ACCESS_TOKEN>]
```

### Azure DevOps Pipeline Integration

To automate PR analysis in Azure DevOps:

1. Add the `azure-pipelines.yml` file to your repository
2. Create a new pipeline in Azure DevOps pointing to this file
3. The pipeline will automatically run on pull requests to the specified branches

## Requirements

- `jq` - JSON processor for parsing GitHub API responses
- `git` - For cloning repositories and generating diffs
- Access to GitHub or Azure DevOps (with optional token for API rate limits)

## Using with LLMs

The scripts generate an optimized markdown file (`pr_diff_result.md` or `pr_diff_analysis.md`) structured specifically for LLM code review:

1. **PR Context**: Basic information about the PR, branches, and repositories
2. **Summary**: Count of new, modified, and deleted files
3. **New Files**: Complete content of newly added files
4. **Diffs**: Clean, focused diff output for modified files with 3 lines of context

This format allows LLMs to:
- Understand the scope of changes quickly
- See full context for new files
- Focus on actual code changes without noise
- Generate more accurate and helpful code reviews

## Example Output

The scripts generate a markdown file with this structure:

```markdown
# PR REVIEW CONTEXT

PR: user/repo #123
URL: https://github.com/user/repo/pull/123
Base Branch: main
Head Branch: feature-branch
Generated: Mon Apr 21 20:00:00 CEST 2025

## PR SUMMARY

Total Changes: 3 files
New: 1 | Modified: 1 | Deleted: 1

### New Files:
- src/new.js

### NEW FILE CONTENTS

FILE: src/new.js
<NEW_CONTENT>
// New file content here
</NEW_CONTENT>

### Deleted Files:
- src/deleted.js

### Modified Files:
- src/modified.js

### DIFF SUMMARY

FILE: src/modified.js
<DIFF>
@@ -1,5 +1,5 @@
  // File header
- // Original content
+ // Modified content
  // Footer
</DIFF>
```

This format provides exactly what an LLM needs for effective code review: context, changes, and concise diffs optimized for token efficiency.
