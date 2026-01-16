---
description: "Enforce HTTPS URLs for all GitHub operations - reject SSH"
alwaysApply: true
---

# GitHub HTTPS Rule

Always use HTTPS URLs for GitHub repositories. SSH URLs are rejected with an error.

## URL Formats

- **Required**: `https://github.com/owner/repo.git`
- **Rejected**: `git@github.com:owner/repo.git`

## Validation

- Use `github_validate_https_url()` to validate repository URLs early
- Reject SSH URLs with a clear error message showing the correct format
- Never convert SSH to HTTPS - require user to provide correct format

## Authentication

- Use GitHub App installation tokens for authentication
- Tokens are obtained via `github_app_get_token()`
- Clone format: `https://x-access-token:{token}@github.com/owner/repo.git`
- Never store tokens in remote URLs permanently
