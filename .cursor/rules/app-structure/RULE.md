---
description: "App directory structure and deployment conventions"
globs:
  - "lib/app.sh"
  - "lib/provision.sh"
  - "lib/release.sh"
alwaysApply: false
---

# App Directory Structure

## Home Directory Layout

Each app user has this structure at `/home/{username}/`:

```
/home/{username}/
├── current -> releases/20240101120000    # Symlink to active release
├── releases/
│   ├── 20240101120000/                   # Release directories (timestamp)
│   └── 20240102130000/
├── storage/                              # Shared storage (persists across releases)
│   ├── app/
│   ├── framework/
│   │   ├── cache/
│   │   ├── sessions/
│   │   └── views/
│   └── logs/
├── logs/                                 # App logs (nginx, etc.)
├── .env                                  # Shared .env (symlinked from releases)
└── deploy.sh                             # Deployment script
```

## Symlinks in Each Release

Each release has these symlinks:

- `storage -> /home/{username}/storage`
- `.env -> /home/{username}/.env`

## Deployment Flow

1. Create new release directory with timestamp
2. Clone/pull code into release
3. Symlink storage and .env
4. Run composer/npm install
5. Run migrations
6. Switch `current` symlink atomically
7. Restart queue workers
8. Clean up old releases (keep last 5)

## Permissions

- Home directory: `755` (traversable for nginx)
- Storage: `775` (writable by app)
- Release files: `640` (readable by nginx via group)
- Release dirs: `750`
