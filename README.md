# PR Analysis Tools

This repository contains shell and PowerShell scripts for analyzing GitHub pull requests.

## Scripts

### Bash Scripts
- `analyze-pr-diff.sh` - Full featured script for PR analysis with detailed output
- `analyze-pr-diff-min.sh` - Minimalist version of the PR analysis script

### PowerShell Scripts
- `analyze-pr-diff.ps1` - Full featured script for PR analysis in PowerShell
- `analyze-pr-diff-min.ps1` - Minimalist version of the PR analysis script in PowerShell

## Usage

```bash
# For Bash scripts
./analyze-pr-diff.sh <GitHub PR URL> [GitHub Token]
./analyze-pr-diff-min.sh <GitHub PR URL> [GitHub Token]

# For PowerShell scripts
./analyze-pr-diff.ps1 <GitHub PR URL> [GitHub Token]
./analyze-pr-diff-min.ps1 <GitHub PR URL> [GitHub Token]
```

## Requirements

- `jq` - JSON processor for parsing GitHub API responses
- `git` - For cloning repositories
- Access to GitHub (with optional token for API rate limits)

## Output

The scripts generate a markdown file with:
- Lists of new, deleted, and modified files
- Full content comparison for modified files
