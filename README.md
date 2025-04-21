# PR Analysis Tools

This repository contains shell and PowerShell scripts for analyzing GitHub pull requests.

## Scripts

### Bash Scripts

- `analyze-pr-diff.sh` - Full featured script for PR analysis with detailed output
- `analyze-pr-diff-min.sh` - Minimalist version of the PR analysis script

### PowerShell Scripts

- `analyze-pr-diff.ps1` - Full featured script for PR analysis in PowerShell
- `analyze-pr-diff-min.ps1` - Minimalist version of the PR analysis script in PowerShell

### Azure DevOps Integration

- `analyze-pr-diff-azdo.ps1` - Full featured PowerShell script for Azure DevOps PR analysis
- `analyze-pr-diff-min-azdo.ps1` - Minimalist PowerShell script for Azure DevOps PR analysis
- `azure-pipelines.yml` - Azure DevOps pipeline configuration for automation

## Usage

```bash
# For Bash scripts
./analyze-pr-diff.sh <GitHub PR URL> [GitHub Token]
./analyze-pr-diff-min.sh <GitHub PR URL> [GitHub Token]

# For PowerShell scripts
./analyze-pr-diff.ps1 <GitHub PR URL> [GitHub Token]
./analyze-pr-diff-min.ps1 <GitHub PR URL> [GitHub Token]

# For Azure DevOps PowerShell scripts
./analyze-pr-diff-azdo.ps1 -PullRequestId <PR_ID> -Organization <ORG> -Project <PROJECT> -Repository <REPO> [-PAT <PERSONAL_ACCESS_TOKEN>]
./analyze-pr-diff-min-azdo.ps1 -PullRequestId <PR_ID> -Organization <ORG> -Project <PROJECT> -Repository <REPO> [-PAT <PERSONAL_ACCESS_TOKEN>]
```

### Azure DevOps Pipeline Integration

To use the scripts in an Azure DevOps pipeline:

1. Add the `azure-pipelines.yml` file to your repository
2. Create a new pipeline in Azure DevOps pointing to this file
3. The pipeline will automatically run on pull requests to the specified branches
4. You can select between full and minimal analysis using a parameter

## Requirements

- `jq` - JSON processor for parsing GitHub API responses
- `git` - For cloning repositories
- Access to GitHub (with optional token for API rate limits)

## Unit Testing

### Testing Bash Scripts

Unit tests are available in the `unit_tests.sh` script:

```bash
# Run the unit tests
./unit_tests.sh
```

The unit tests verify that the scripts:
- Have correct syntax
- Include dependency checks
- Validate input arguments
- Handle output files correctly
- Construct proper GitHub API URLs
- Include error handling

### Testing PowerShell Scripts

To test the PowerShell scripts, you can use the built-in validation in PowerShell:

```powershell
# Validate PowerShell script syntax
Test-ScriptFileInfo -Path analyze-pr-diff.ps1
Test-ScriptFileInfo -Path analyze-pr-diff-min.ps1
```

## Output

All scripts (both Bash and PowerShell) generate markdown files with:
- Lists of new, deleted, and modified files
- Full content comparison for modified files

### Example Output (Minimal Version)

```markdown
PR: user/repo #123
Base: main
Head: feature-branch

New Files:
- src/new.js

Deleted Files:
- src/deleted.js

Modified Files:
- src/modified.js

File: src/modified.js
<<<<>>>>
<<<<previous>>>>
// Original content
<<<<new>>>>
// Modified content
<<<<>>>>
```

### Example Output (Full Version)

```markdown
# PR Analysis for user/repo PR #123
Base branch: `main`
Head branch: `feature-branch`
Generated on: Mon Apr 21 09:25:00 CEST 2025

---

## 🟩 New Files

- `src/new.js`

## 🟥 Deleted Files

- `src/deleted.js`

## 🟨 Modified Files

- `src/modified.js`

---

# Detailed Diffs

## 🔄 Modified: `src/modified.js`

<<<<>>>>
<<<<previous>>>>
// Original content

<<<<new>>>>
// Modified content
<<<<>>>>
```

> Note: Both the Bash and PowerShell scripts produce identical output formats. The PowerShell scripts are functionally equivalent to their Bash counterparts but optimized for Windows environments.
