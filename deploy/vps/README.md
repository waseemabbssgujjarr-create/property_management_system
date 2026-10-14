# MUNSHI — VPS Deployment Guide

**Server:** Contabo VPS — AlmaLinux 9.8 — 6 vCPU / 11 GiB RAM  
**Domain:** https://property.aderalabs.tech  
**Repository:** `https://github.com/waseemabbssgujjarr-create/property_management_system.git`
**Deployment branch:** `deployment-prep/vps-almalinux`
**Cloudflare:** Orange-cloud proxy in front of VPS (Full strict SSL mode)  
**Stack:** Flutter Web → Nginx static serving  
**Supabase:** Cloud-hosted (no backend runs on this VPS)

---

## Architecture

```
Browser  ──HTTPS──▶  Cloudflare edge  ──HTTPS──▶  Nginx (AlmaLinux VPS)
                     (browser cert)               (Origin Certificate)
                                                  /var/www/munshi/current/
                                                  Flutter web SPA

Flutter app  ──HTTPS──▶  Supabase (cloud)
                         Postgres + Auth + Storage + Edge Functions
```

The VPS only serves static files. All backend logic runs in Supabase Edge Functions.  
Cloudflare handles browser-facing TLS; the VPS uses a Cloudflare Origin Certificate for the Cloudflare→VPS leg.

---

## How deploy.sh works

`deploy.sh` follows a strict ordering designed to protect the live site:

1. **Pre-flight** — verifies tools, directories, and the environment file before modifying anything.
2. **Working-tree check** — refuses to run on a dirty working tree (except `.env.prod`, which the script owns). Does not stash or discard developer changes.
3. **Branch checkout** — fetches and checks out `DEPLOY_BRANCH` (default: `deployment-prep/vps-almalinux`). Fails clearly if the branch does not exist on the remote. Never silently deploys a different branch.
4. **Environment load** — sources `/etc/munshi/environment` and validates all required values. Refuses placeholder values.
5. **Write `.env.prod`** — writes public Supabase values into the Flutter asset file. A `trap` registered at script start resets this file to a placeholder on *any* exit — success or failure — so credentials are never left in the working tree.
6. **`flutter pub get`** — installs dependencies.
7. **`dart run build_runner build`** — generates `drift_database.g.dart` (required before `flutter analyze`).
8. **Web platform check** — verifies `web/index.html` exists. Fails with a clear message if the web platform has not been initialised.
9. **`flutter analyze`** — runs after code generation so generated types are available.
10. **`flutter test`** — runs the test suite.
11. **`flutter build web --release`** — produces the final bundle.
12. **Stage release** — copies `build/web` to `/var/www/munshi/releases/TIMESTAMP/`.
13. **`nginx -t`** — validates Nginx config *before* touching the live symlink. Aborts if invalid.
14. **Atomic symlink swap** — updates `/var/www/munshi/current` only after `nginx -t` passes.
15. **`systemctl reload nginx`** — non-disruptive reload. If reload fails, the previous symlink is restored automatically.
16. **Prune** — removes old releases, keeping the 5 most recent.

**On any failure:** the `trap` restores the previous symlink (if swapped), resets `.env.prod`, and exits non-zero. Nginx continues serving the previous working release throughout.

---

## Prerequisites (one-time VPS setup)

Run all commands as root or as a sudo-capable user.

### 1. Install system packages

```bash
# Flutter web build dependencies on AlmaLinux 9
sudo dnf install -y git curl unzip which xz tar

# Nginx (if not already installed)
sudo dnf install -y nginx
sudo systemctl enable --now nginx
```

> **Do not install** `certbot` or `python3-certbot-nginx` — HTTP-01 challenges cannot
> pass behind Cloudflare's orange-cloud proxy. TLS is handled by a Cloudflare Origin
> Certificate (see step 4).

### 2. Install Flutter SDK

Flutter is required on the VPS because `deploy.sh` runs `flutter build web` locally.

```bash
sudo git clone https://github.com/flutter/flutter.git \
    -b stable --depth 1 /opt/flutter

echo 'export PATH="$PATH:/opt/flutter/bin"' \
    | sudo tee /etc/profile.d/flutter.sh
source /etc/profile.d/flutter.sh

# Bootstrap the web platform (downloads the web SDK)
flutter precache --web
flutter config --enable-web
flutter --version
```

> All required system libraries for a web-only build are covered by the `dnf` packages in step 1.

### 3. Clone the repository

```bash
sudo git clone \
    https://github.com/waseemabbssgujjarr-create/property_management_system.git \
    /opt/munshi-app
# Or with SSH:
# sudo git clone \
#     git@github.com:waseemabbssgujjarr-create/property_management_system.git \
#     /opt/munshi-app
```

### 4. Set up Cloudflare Origin Certificate and Nginx

**Set Cloudflare SSL mode first:**

1. Cloudflare Dashboard → **SSL/TLS** → Overview → set mode to **Full (strict)**.
2. Cloudflare Dashboard → **SSL/TLS** → **Origin Server** → **Create Certificate**.
   - Hostnames: `property.aderalabs.tech` (add `*.aderalabs.tech` if needed)
   - Key type: EC (recommended) or RSA 2048 — validity: 15 years
3. Copy the Certificate and Private Key PEM blocks.

**Install the certificate:**

```bash
sudo mkdir -p /etc/ssl/munshi
sudo chmod 700 /etc/ssl/munshi

sudo nano /etc/ssl/munshi/origin.crt   # paste -----BEGIN CERTIFICATE----- block
sudo nano /etc/ssl/munshi/origin.key   # paste -----BEGIN EC PRIVATE KEY----- block

sudo chmod 644 /etc/ssl/munshi/origin.crt
sudo chmod 600 /etc/ssl/munshi/origin.key
```

**Install the Nginx vhost:**

```bash
sudo cp /opt/munshi-app/deploy/vps/nginx.conf.example \
    /etc/nginx/conf.d/munshi.conf

# Edit: replace YOUR_PROJECT_ID in the Content-Security-Policy
# with your Supabase project reference.
sudo nano /etc/nginx/conf.d/munshi.conf

sudo nginx -t
sudo systemctl reload nginx
```

The vhost drops into `/etc/nginx/conf.d/` which AlmaLinux's default `nginx.conf` includes via `conf.d/*.conf`. It does **not** modify `/etc/nginx/nginx.conf` or any other site's vhost.

### 5. Create deployment directories and environment file

```bash
sudo mkdir -p /var/www/munshi/releases
sudo mkdir -p /etc/munshi

sudo cp /opt/munshi-app/deploy/vps/environment.example /etc/munshi/environment
sudo chmod 600 /etc/munshi/environment
sudo nano /etc/munshi/environment
```

Fill in **at minimum** these two values:

| Variable | Where to find it |
|---|---|
| `SUPABASE_URL` | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API → `anon` `public` key |

Adjust feature flags as needed. All server-side secrets go in Supabase Edge Function secrets — never here.

### 6. Initialise Flutter web platform (first time only)

If the `web/` directory has not been committed to the deployment branch:

```bash
cd /opt/munshi-app/app
flutter create . --platforms web
# Answer 'yes' to any merge prompts.
# Commit the generated web/ files to deployment-prep/vps-almalinux before deploying.
```

`deploy.sh` checks for `web/index.html` and fails with a clear error if it is absent.

---

## Deploying

```bash
cd /opt/munshi-app
sudo bash deploy/vps/deploy.sh
```

To deploy a different branch (overrides the default):

```bash
sudo DEPLOY_BRANCH=my-branch bash deploy/vps/deploy.sh
```

---

## Verifying deployment

```bash
bash /opt/munshi-app/deploy/vps/health-check.sh https://property.aderalabs.tech
```

Expected: all PASS, no FAIL. Informational (INFO) items about Cloudflare certificates and Server headers are normal and expected.

---

## Rolling back

See [rollback.md](rollback.md).

---

## Required Supabase configuration

### Auth redirect URLs

In **Supabase Dashboard → Authentication → URL Configuration**, add:

```
https://property.aderalabs.tech
https://property.aderalabs.tech/**
```

### JWT Claims Hook

In **Supabase Dashboard → Authentication → Hooks**:

- Hook type: Custom Access Token
- Function: `public.custom_access_token_hook`

Without this, RLS policies do not work (`auth.dealer_id()` returns NULL).

### WhatsApp credential encryption key

The `store_wa_credentials()` and `get_wa_credentials()` database functions encrypt and decrypt WA API credentials using `pgp_sym_encrypt()` / `pgp_sym_decrypt()` from pgcrypto. The encryption key is read from the PostgreSQL GUC `app.wa_credential_key` at runtime — it is never stored in the database itself, in Flutter source, or in any file shipped to the browser.

**Generate a key (32+ characters of randomness):**

```bash
openssl rand -base64 32
```

**Configure the key in hosted Supabase:**

In hosted Supabase, `ALTER DATABASE postgres SET` does not reliably propagate to PostgREST sessions (which is how Edge Functions via the service-role key connect). The correct approach is to set it on the `authenticator` role, which PostgREST uses for all connections:

```sql
-- Run in Supabase Dashboard → SQL Editor (as postgres / admin)
ALTER ROLE authenticator SET app.wa_credential_key TO 'your-generated-key-here';
```

This makes the setting available to all roles that PostgREST switches to (`anon`, `authenticated`, `service_role`), and therefore to the `SECURITY DEFINER` functions called from Edge Functions.

> **Alternative:** Supabase Dashboard → Project Settings → Database → Configuration → Custom Postgres Config → add `app.wa_credential_key` as a custom setting. This achieves the same effect through the UI.

**Verify the key is set:**

```sql
-- Run as the authenticator role to confirm propagation
SET ROLE authenticator;
SELECT current_setting('app.wa_credential_key', true);
RESET ROLE;
-- Should return your key, not NULL or empty string
```

**Security rules:**

- The key must NEVER be placed in `/etc/munshi/environment`, `app/.env.prod`, or any Flutter asset.
- The key must NEVER be set as a Supabase Edge Function secret (Edge Function secrets are in a different trust boundary and are not accessible from SQL functions).
- If the key is rotated, all existing `whatsapp_connections` credentials become undecryptable. Re-connect each dealer's WhatsApp account after rotation.
- Store the key in your password manager or secrets vault — there is no way to recover it from the database.

### WhatsApp Edge Function SSRF protection

The `wa-connect` Edge Function validates `api_base_url` against an allowlist before making outbound requests. Configure the allowlist via Supabase Edge Function secrets:

```bash
# Comma-separated list of trusted WA API hostnames
supabase secrets set WA_API_ALLOWED_HOSTS=api.ourwhatsapp.example.com,api.wa.aderalabs.tech

# Or set a single trusted base URL (its hostname becomes the sole allowlist entry)
supabase secrets set WA_API_BASE_URL=https://api.ourwhatsapp.example.com/v1
```

If `WA_API_ALLOWED_HOSTS` is set, it takes precedence. If only `WA_API_BASE_URL` is set, its hostname is used as the sole allowlist entry. If neither is set, the Edge Function rejects all client-supplied URLs.

All client-supplied URLs must use HTTPS and must not point to private or internal addresses (loopback, RFC 1918, link-local).

### Server-side secrets (Edge Functions)

Set via `supabase secrets set` — **never** put these in `/etc/munshi/environment`:

```
SUPABASE_SERVICE_ROLE_KEY, WA_API_BASE_URL, WA_API_KEY,
TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER,
LOCAL_SMS_API_URL, LOCAL_SMS_API_KEY,
VOICE_API_URL, VOICE_API_KEY, META_APP_SECRET
```

---

## Security summary

| Item | Status |
|---|---|
| Supabase anon key in Flutter bundle | ✅ Intentional — anon key is public by design; RLS enforces all access |
| Supabase service-role key | ✅ Never in Flutter — Supabase Edge Function secrets only |
| WA API key | ✅ Never in Flutter — Supabase Edge Function secrets only |
| DB password | ✅ Never on VPS — managed by Supabase |
| `.env.prod` with real credentials | ✅ Exists only during the build; trap resets it to placeholder on any exit |
| `/etc/munshi/environment` | ✅ chmod 600 — readable only by root or named deploy user |
| `/etc/ssl/munshi/origin.key` | ✅ chmod 600 — Cloudflare Origin Certificate private key |
| Build artefacts in `/var/www/munshi/` | ✅ Owned by nginx user; world-readable files only |
| Cloudflare SSL mode | ✅ Full (strict) — prevents Cloudflare accepting an untrusted origin cert |

---

## Troubleshooting

### deploy.sh refuses: "dirty working tree"

The script will not run if the working tree has uncommitted changes (other than `.env.prod`, which the script owns). Commit or discard the changes first:

```bash
git status
git diff
# commit what you want to keep, then re-run
```

### deploy.sh refuses: "branch does not exist on remote"

```bash
git branch -r    # list available remote branches
# Then either push your branch:
git push origin deployment-prep/vps-almalinux
# Or set DEPLOY_BRANCH to an existing branch:
sudo DEPLOY_BRANCH=main bash deploy/vps/deploy.sh
```

### 404 on deep links (e.g. /home, /deals)

Verify `/etc/nginx/conf.d/munshi.conf` contains:

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

Then: `sudo nginx -t && sudo systemctl reload nginx`

### App loads but Supabase calls fail (CORS / network error)

1. Check `SUPABASE_URL` in `/etc/munshi/environment` is the real project URL.
2. Confirm `https://property.aderalabs.tech` is listed in Supabase Dashboard → Auth → URL Configuration.
3. Check `connect-src` in `nginx.conf` includes your project's Supabase hostname.

### build_runner fails

```bash
flutter pub cache repair
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Error 525 (SSL handshake failed) from Cloudflare

1. `sudo systemctl status nginx` — is Nginx running?
2. `sudo nginx -t` — is the config valid?
3. `ls -la /etc/ssl/munshi/` — do origin.crt and origin.key exist and are non-empty PEM files?
4. Verify Cloudflare SSL/TLS mode is set to **Full (strict)**.
