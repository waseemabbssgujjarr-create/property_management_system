# MUNSHI — Rollback Procedure

## Before you roll back: check what is currently live

```bash
# What is the current live release?
readlink /var/www/munshi/current

# List all available releases (newest first)
ls -lt /var/www/munshi/releases/
```

Identify the release you want to roll back TO (the one before the broken one).  
It should appear directly below the current release in the `ls -lt` output.

---

## Quick rollback

```bash
# Replace YYYYMMDD_HHMMSS with the target release timestamp from ls -lt above
RELEASE="20261002_120000"

# Verify the release directory exists and has index.html before switching
ls /var/www/munshi/releases/${RELEASE}/index.html

# Atomically swap the symlink
sudo ln -sfn /var/www/munshi/releases/${RELEASE} /var/www/munshi/current

# Confirm the symlink now points to the right place
readlink /var/www/munshi/current

# Validate Nginx config and reload (non-disruptive)
sudo nginx -t && sudo systemctl reload nginx
```

---

## Verify after rollback

```bash
bash /opt/munshi-app/deploy/vps/health-check.sh https://property.aderalabs.tech
```

Expected: all PASS, no FAIL.

---

## After rollback

1. Confirm the health check passes and the site is serving correctly.
2. Identify what broke in the failed release (check deploy logs, `flutter analyze`, browser DevTools).
3. Fix the issue in code, commit, and redeploy via `deploy.sh`.
4. The failed release directory stays in `/var/www/munshi/releases/` until it is pruned  
   by the next successful `deploy.sh` run (keeps 5 most recent).

---

## What rollback does NOT restore

| Resource | Rollback impact |
|---|---|
| Flutter web static files | ✅ Rolled back immediately by symlink swap |
| Nginx config | ❌ Not touched — config stays as-is |
| Supabase schema migrations | ❌ Not reverted — requires a compensating migration |
| Supabase Edge Functions | ❌ Not reverted — redeploy previous version manually |
| Supabase Auth configuration | ❌ Not reverted |

If a database migration caused the issue, apply a compensating migration:

```bash
supabase db push --db-url "postgresql://postgres:[password]@[host]:5432/postgres"
```

---

## Emergency: Nginx serving 404 or wrong content after rollback

```bash
# Confirm symlink
readlink /var/www/munshi/current

# Confirm index.html is present at the target
ls /var/www/munshi/current/index.html

# Check Nginx error log for clues
sudo tail -50 /var/log/nginx/munshi_error.log

# Validate config
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

If Nginx is in a failed state:
```bash
sudo systemctl restart nginx
sudo systemctl status nginx
```

---

## Release directory structure

```
/var/www/munshi/
├── current -> releases/20261002_143022/   ← active symlink (change this to roll back)
└── releases/
    ├── 20261002_143022/   ← current (newest — symlink points here)
    ├── 20261001_182015/   ← ← roll back to this one if current is broken
    ├── 20261001_091200/
    ├── 20260930_161044/
    └── 20260929_104533/   ← oldest (deploy.sh keeps 5 by default)
```
