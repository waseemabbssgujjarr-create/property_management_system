# MUNSHI — Rollback Procedure

Rollback swaps the `/var/www/munshi/current` symlink back to a previous release directory and reloads Nginx. No files are deleted. The failed release stays on disk until the next successful `deploy.sh` run prunes it.

---

## Before you roll back: check what is currently live

```bash
# What release is the symlink pointing at right now?
readlink /var/www/munshi/current

# List all available releases, newest first
ls -lt /var/www/munshi/releases/
```

Identify the release you want to restore — it should be the one directly below the current (broken) release in the `ls -lt` output.

---

## Quick rollback

```bash
# Replace with the timestamp of the release to restore
RELEASE="20261002_120000"

# Confirm the release directory and its index.html exist before switching
ls /var/www/munshi/releases/${RELEASE}/index.html

# Atomically swap the symlink
sudo ln -sfn /var/www/munshi/releases/${RELEASE} /var/www/munshi/current

# Verify
readlink /var/www/munshi/current

# Validate Nginx config, then reload (non-disruptive)
sudo nginx -t && sudo systemctl reload nginx
```

---

## Verify after rollback

```bash
bash /opt/munshi-app/deploy/vps/health-check.sh https://property.aderalabs.tech
```

Expected: all PASS, no FAIL.

---

## Automatic rollback during deploy.sh

`deploy.sh` registers a cleanup trap at startup. If the deploy fails **after** the symlink has been swapped (i.e. during `systemctl reload nginx`), the trap automatically:

1. Restores the previous symlink.
2. Resets `.env.prod` to its placeholder.
3. Exits non-zero.

Nginx continues serving the previous working release throughout. You do not need to run manual rollback steps in that case — just check the deploy output for the error and fix it.

---

## After rollback

1. Confirm the health check passes.
2. Identify what broke (deploy logs, `flutter analyze`, browser DevTools console).
3. Fix the issue, commit to `deployment-prep/vps-almalinux`, and re-run `deploy.sh`.
4. The failed release directory remains in `/var/www/munshi/releases/` until it is pruned by the next successful deploy (the script keeps the 5 most recent releases).

---

## What rollback does and does not restore

| Resource | Effect |
|---|---|
| Flutter web static files | ✅ Restored immediately by the symlink swap |
| Nginx configuration | ❌ Not changed — fix `/etc/nginx/conf.d/munshi.conf` manually if needed |
| Supabase schema migrations | ❌ Not reverted — apply a compensating migration |
| Supabase Edge Functions | ❌ Not reverted — redeploy the previous version manually |
| Supabase Auth configuration | ❌ Not reverted |

If a database migration caused the breakage:

```bash
supabase db push --db-url "postgresql://postgres:[password]@[host]:5432/postgres"
```

---

## Emergency: Nginx serving 404 or wrong content after rollback

```bash
# Confirm the symlink target
readlink /var/www/munshi/current

# Confirm index.html is present
ls /var/www/munshi/current/index.html

# Check the Nginx error log
sudo tail -50 /var/log/nginx/munshi_error.log

# Validate config and reload
sudo nginx -t
sudo systemctl reload nginx
```

If Nginx is in a failed state:

```bash
sudo systemctl restart nginx
sudo systemctl status nginx
```

---

## Release directory layout

```
/var/www/munshi/
├── current -> releases/20261002_143022/   ← live symlink — swap this to roll back
└── releases/
    ├── 20261002_143022/   ← currently live (newest)
    ├── 20261001_182015/   ← ← roll back to this if the live one is broken
    ├── 20261001_091200/
    ├── 20260930_161044/
    └── 20260929_104533/   ← oldest kept (deploy.sh keeps 5 by default)
```
