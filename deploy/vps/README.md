# MUNSHI — VPS Deployment Guide

**Server:** Contabo VPS — AlmaLinux 9.8 — 6 vCPU / 11 GiB RAM  
**Domain:** https://property.aderalabs.tech  
**Cloudflare:** Orange-cloud proxy in front of VPS (Full strict SSL mode)  
**Stack:** Flutter Web → Nginx static serving  
**Supabase:** Cloud-hosted (no backend on this VPS)

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

## Prerequisites (one-time VPS setup)

Run all commands as root, or as a sudo-capable user.

### 1. Install system packages

```bash
# Flutter web build dependencies on AlmaLinux 9
sudo dnf install -y git curl unzip which xz tar

# Nginx (if not already installed)
sudo dnf install -y nginx
sudo systemctl enable --now nginx
```

> **Do not install** `certbot` or `python3-certbot-nginx` — Certbot HTTP-01 challenges  
> cannot pass when the domain is behind Cloudflare's orange-cloud proxy.  
> TLS is handled by a Cloudflare Origin Certificate (see step 4).

### 2. Install Flutter SDK on the VPS

Flutter is needed on the VPS because `deploy.sh` runs `flutter build web`.

```bash
# Clone stable Flutter at a well-known path
sudo git clone https://github.com/flutter/flutter.git \
    -b stable --depth 1 /opt/flutter

# Persist the PATH for all users
echo 'export PATH="$PATH:/opt/flutter/bin"' \
    | sudo tee /etc/profile.d/flutter.sh
source /etc/profile.d/flutter.sh

# Bootstrap the web platform (downloads web SDK and Chrome driver binaries)
flutter precache --web
flutter config --enable-web

# Verify
flutter --version
```

> Flutter system dependencies on AlmaLinux 9 are covered by the packages in step 1.  
> There is no `libglu1-mesa` equivalent needed for a web-only build on AlmaLinux.

### 3. Clone the repository

```bash
sudo git clone https://github.com/YOUR_ORG/munshi-app.git /opt/munshi-app
# Or with SSH:
# sudo git clone git@github.com:YOUR_ORG/munshi-app.git /opt/munshi-app
```

### 4. Set up Cloudflare Origin Certificate and Nginx

**Cloudflare SSL mode (do this first):**

1. Cloudflare Dashboard → **SSL/TLS** → Overview → set mode to **Full (strict)**.
2. Cloudflare Dashboard → **SSL/TLS** → **Origin Server** → **Create Certificate**.
   - Hostnames: `property.aderalabs.tech` (add `*.aderalabs.tech` if needed)
   - Key type: EC (recommended) or RSA 2048
   - Validity: 15 years
3. Copy the **Certificate** and **Private Key** values shown in the dashboard.

**Install the certificate on the VPS:**

```bash
sudo mkdir -p /etc/ssl/munshi
sudo chmod 700 /etc/ssl/munshi

# Paste the certificate PEM block (begins -----BEGIN CERTIFICATE-----)
sudo nano /etc/ssl/munshi/origin.crt
# Paste the private key PEM block (begins -----BEGIN EC PRIVATE KEY-----)
sudo nano /etc/ssl/munshi/origin.key

sudo chmod 644 /etc/ssl/munshi/origin.crt
sudo chmod 600 /etc/ssl/munshi/origin.key    # key readable by root only
```

**Install the Nginx vhost:**

```bash
sudo cp /opt/munshi-app/deploy/vps/nginx.conf.example \
    /etc/nginx/conf.d/munshi.conf

# Edit the file: replace YOUR_PROJECT_ID in the Content-Security-Policy
# with your actual Supabase project reference (e.g. abcdefghijklmnop).
sudo nano /etc/nginx/conf.d/munshi.conf

# Validate and reload
sudo nginx -t
sudo systemctl reload nginx
```

> The vhost drops into `/etc/nginx/conf.d/` which AlmaLinux's default  
> `/etc/nginx/nginx.conf` includes via `conf.d/*.conf`. This does **not**  
> modify the main Nginx config or any other site's vhost.

### 5. Create deployment directories

```bash
sudo mkdir -p /var/www/munshi/releases
sudo mkdir -p /etc/munshi

# Optionally create a non-root deploy user
# sudo useradd -r -s /sbin/nologin deployuser
# sudo chown -R deployuser:deployuser /var/www/munshi
```

### 6. Create the environment file

```bash
sudo cp /opt/munshi-app/deploy/vps/environment.example /etc/munshi/environment
sudo chmod 600 /etc/munshi/environment
sudo nano /etc/munshi/environment
```

Fill in **only** these two values (public — safe for the browser bundle):

| Variable | Where to find it |
|---|---|
| `SUPABASE_URL` | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API → `anon` `public` key |

Leave all server-side secrets **out of this file** — they go into Supabase Edge Function secrets.

---

## First-time Flutter web setup

If the Flutter web platform has never been initialised in this repo:

```bash
cd /opt/munshi-app/app
flutter create . --platforms web
# Answer 'yes' to any merge prompts.
# This creates web/index.html, web/manifest.json, web/favicon.png if missing.
```

You only need to do this once. Subsequent deploys use `deploy.sh` directly.

---

## Deploying

```bash
cd /opt/munshi-app
sudo bash deploy/vps/deploy.sh
```

The script:

1. Loads `/etc/munshi/environment` and validates no placeholder values remain.
2. Writes real Supabase values into `app/.env.prod` (public anon key only).
3. `flutter pub get` → `dart run build_runner build` (Drift codegen) → `flutter build web --release`
4. Copies `build/web` to `/var/www/munshi/releases/TIMESTAMP/`.
5. Atomically updates the `/var/www/munshi/current` symlink.
6. `nginx -t` → `systemctl reload nginx`.
7. Resets `app/.env.prod` to a placeholder (credentials live in the JS bundle).
8. Prunes old releases, keeping the 5 most recent.

---

## Verifying deployment

```bash
bash /opt/munshi-app/deploy/vps/health-check.sh https://property.aderalabs.tech
```

Expected outcome: all PASS, no FAIL. Informational (INFO) items about Cloudflare are normal.

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

Without this, RLS policies will not work (`auth.dealer_id()` returns NULL).

### WhatsApp credential encryption key

```sql
-- Run in Supabase SQL Editor (once, on production DB)
ALTER DATABASE postgres SET app.wa_credential_key = 'your-32-char-random-key';
```

Generate a suitable key with:
```bash
openssl rand -base64 32
```

### Server-side secrets (Edge Functions)

Set these via `supabase secrets set` — **never** put them in `/etc/munshi/environment`:

```bash
supabase secrets set --env-file <(cat <<'EOF'
SUPABASE_SERVICE_ROLE_KEY=...
WA_API_BASE_URL=...
WA_API_KEY=...
TWILIO_ACCOUNT_SID=...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=...
LOCAL_SMS_API_URL=...
LOCAL_SMS_API_KEY=...
VOICE_API_URL=...
VOICE_API_KEY=...
META_APP_SECRET=...
EOF
)
```

---

## Security summary

| Item | Status |
|------|--------|
| Supabase anon key in Flutter bundle | ✅ Intentional and safe — anon key is public by design. RLS enforces all access. |
| Supabase service-role key | ✅ NEVER in Flutter — only in Supabase Edge Function secrets |
| WA API key | ✅ NEVER in Flutter — only in Supabase Edge Function secrets |
| DB password | ✅ NEVER on VPS — managed by Supabase |
| `/etc/munshi/environment` | ✅ chmod 600 — readable only by root (or named deploy user) |
| `/etc/ssl/munshi/origin.key` | ✅ chmod 600 — Cloudflare Origin Certificate private key |
| Build artefacts in `/var/www/munshi/` | ✅ Owned by nginx user, world-readable files only |
| Cloudflare SSL mode | ✅ Full (strict) — prevents Cloudflare from accepting a fake origin cert |

---

## Troubleshooting

### 404 on deep links (e.g. /home, /deals)

Verify `/etc/nginx/conf.d/munshi.conf` contains:

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

Then: `sudo nginx -t && sudo systemctl reload nginx`

### App loads but Supabase calls fail (CORS / network error)

Check browser DevTools console. Verify:

1. `SUPABASE_URL` in `/etc/munshi/environment` is your actual project URL (not a placeholder).
2. `https://property.aderalabs.tech` is listed in Supabase Dashboard → Auth → URL Configuration.
3. The `connect-src` in `nginx.conf` includes your project's Supabase hostname.

### build_runner fails

```bash
flutter pub cache repair
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Nginx config fails validation after editing

```bash
sudo nginx -t          # shows the exact error line
sudo journalctl -u nginx --since "5 min ago"
```

### TLS: openssl shows "Cloudflare" cert issuer

This is correct. The Cloudflare Origin Certificate on the VPS is never seen by browsers — Cloudflare presents its own browser-trusted cert. The openssl command connects to the Cloudflare edge, so it shows the Cloudflare cert.

### Cloudflare shows "SSL handshake failed" error (Error 525)

Cloudflare cannot reach the VPS on port 443, or the Origin Certificate is wrong.

Check:
1. `sudo systemctl status nginx` — is Nginx running?
2. `sudo nginx -t` — is the config valid?
3. `ls -la /etc/ssl/munshi/` — do origin.crt and origin.key exist and are they non-empty?
4. The cert and key files are PEM format (begin with `-----BEGIN ...-----`).
5. Firewall: port 443 is open to Cloudflare IP ranges (or to all, since Cloudflare proxies it).
