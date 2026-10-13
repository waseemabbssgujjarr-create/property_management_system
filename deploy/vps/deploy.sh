#!/usr/bin/env bash
# MUNSHI — VPS Deploy Script
# Target OS: AlmaLinux 9.8 x86_64
# Nginx user: nginx (AlmaLinux default)
#
# USAGE:
#   # As root:
#   bash deploy.sh
#
#   # As a non-root user with sudo:
#   sudo bash deploy.sh
#
#   # Override env file:
#   sudo MUNSHI_ENV=/path/to/environment bash deploy.sh
#
# PREREQUISITES (one-time setup — see README.md):
#   - Flutter SDK at /opt/flutter (or FLUTTER_BIN env override)
#   - Repo cloned at /opt/munshi-app (or REPO_DIR override)
#   - Environment file at /etc/munshi/environment
#   - Nginx configured and running
#
# WHAT THIS SCRIPT DOES:
#   1.  Validates environment file — refuses placeholder values.
#   2.  Writes .env.prod with real (but public) Supabase values.
#   3.  flutter pub get → build_runner → flutter build web.
#   4.  Copies build/web into a timestamped release directory.
#   5.  Atomically swaps the /var/www/munshi/current symlink.
#   6.  Reloads Nginx (non-disruptive).
#   7.  Resets .env.prod back to placeholder (credentials live only in the bundle).
#   8.  Prunes old releases — keeps ${KEEP_RELEASES} most recent.
#
# WHAT THIS SCRIPT NEVER DOES:
#   - Never writes service-role keys, WA keys, DB passwords or
#     any other server-side secret to any file.
#   - Never modifies /etc/nginx/nginx.conf or any other vhost.
#   - Never restarts Nginx — only reloads configuration.
#   - Never changes firewall rules.
#   - Never touches Apache, MariaDB, Redis or Supervisor.

set -euo pipefail

# ── Configurable variables (override via environment) ─────────────────────
REPO_DIR="${REPO_DIR:-/opt/munshi-app}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/munshi}"
MUNSHI_ENV="${MUNSHI_ENV:-/etc/munshi/environment}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
# AlmaLinux 9 Nginx runs as the 'nginx' user by default.
NGINX_USER="${NGINX_USER:-nginx}"
# Flutter/Dart — auto-detected from PATH, or override explicitly.
FLUTTER="${FLUTTER_BIN:-}"
DART="${DART_BIN:-}"

# Derived paths — do not override these.
APP_DIR="${REPO_DIR}/app"
RELEASES_DIR="${DEPLOY_ROOT}/releases"
CURRENT_LINK="${DEPLOY_ROOT}/current"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RELEASE_DIR="${RELEASES_DIR}/${TIMESTAMP}"

# ── Colour helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
step()    { echo -e "${CYAN}[STEP]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }
divider() { echo -e "${CYAN}────────────────────────────────────────────${NC}"; }

# ── Resolve Flutter/Dart executables ─────────────────────────────────────
# Try: explicit override → PATH → well-known VPS location.
resolve_bin() {
    local name="$1" override="$2" well_known="$3"
    if [[ -n "${override}" ]]; then
        [[ -x "${override}" ]] || die "${name} not executable at override path: ${override}"
        echo "${override}"
        return
    fi
    if command -v "${name}" &>/dev/null; then
        echo "$(command -v "${name}")"
        return
    fi
    if [[ -x "${well_known}" ]]; then
        echo "${well_known}"
        return
    fi
    die "${name} not found. Set ${name^^}_BIN or add it to PATH. Typical path: ${well_known}"
}
FLUTTER="$(resolve_bin flutter "${FLUTTER}" /opt/flutter/bin/flutter)"
DART="$(resolve_bin dart    "${DART}"    /opt/flutter/bin/dart)"

# ── Helper: run privileged command (works as root or with sudo) ───────────
# If already root: run directly. If not: prepend sudo.
run_priv() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

divider
info "MUNSHI DEPLOY — ${TIMESTAMP}"
info "Repo:         ${REPO_DIR}"
info "App dir:      ${APP_DIR}"
info "Deploy root:  ${DEPLOY_ROOT}"
info "Env file:     ${MUNSHI_ENV}"
info "Release dir:  ${RELEASE_DIR}"
info "Flutter:      $(${FLUTTER} --version 2>&1 | head -1)"
divider

# ── Step 0: Pre-flight checks ─────────────────────────────────────────────
step "0/9  Pre-flight checks"

[[ -f "${MUNSHI_ENV}" ]] || die "Environment file not found: ${MUNSHI_ENV}
  Create it with: sudo cp ${REPO_DIR}/deploy/vps/environment.example ${MUNSHI_ENV}
  Then fill in real values and: sudo chmod 600 ${MUNSHI_ENV}"

[[ -d "${APP_DIR}" ]] || die "App directory not found: ${APP_DIR}
  Is the repo cloned to ${REPO_DIR}?"

# ── Step 1: Load and validate environment ─────────────────────────────────
step "1/9  Loading environment: ${MUNSHI_ENV}"

# shellcheck source=/dev/null
set -a
source "${MUNSHI_ENV}"
set +a

# Required variables
for var in SUPABASE_URL SUPABASE_ANON_KEY; do
    [[ -n "${!var:-}" ]] || die "${var} is not set in ${MUNSHI_ENV}"
done

# Reject placeholder values — refuse to build a useless bundle.
if echo "${SUPABASE_URL}" | grep -qE 'your-|example\.com|placeholder'; then
    die "SUPABASE_URL still contains a placeholder value: ${SUPABASE_URL}
  Edit ${MUNSHI_ENV} and set a real Supabase project URL."
fi
if echo "${SUPABASE_ANON_KEY}" | grep -qE 'YOUR_|your-|placeholder'; then
    die "SUPABASE_ANON_KEY still contains a placeholder value.
  Edit ${MUNSHI_ENV} and set the real anon key from Supabase Dashboard."
fi

# Security guard — refuse to bundle a service-role key.
if echo "${SUPABASE_ANON_KEY}" | grep -qi 'service_role'; then
    die "SUPABASE_ANON_KEY appears to contain a service-role key.
  The service-role key must NEVER be shipped to a browser.
  Use only the anon (public) key here."
fi

info "Supabase URL:  ${SUPABASE_URL}"
info "Anon key:      ${SUPABASE_ANON_KEY:0:12}... [truncated for safety]"

# ── Step 2: Pull latest code ──────────────────────────────────────────────
step "2/9  Updating repository"

cd "${REPO_DIR}"
git fetch --quiet origin

# Stash any working-tree changes (e.g. a previous .env.prod injection
# that did not get cleaned up) before pulling.
if ! git diff --quiet; then
    warn "Working tree has uncommitted changes — stashing before pull."
    git stash --quiet
fi

git checkout main --quiet
git pull --quiet origin main
info "Git HEAD: $(git rev-parse --short HEAD) — $(git log -1 --format='%s')"

# ── Step 3: Inject public config into .env.prod ───────────────────────────
step "3/9  Writing .env.prod (public values only)"
# flutter_dotenv bundles this file as a Flutter asset at build time.
# It contains ONLY the public anon key — never any server-side secret.

cat > "${APP_DIR}/.env.prod" <<ENVEOF
# Generated by deploy.sh at ${TIMESTAMP} — do not edit manually.
# Contains ONLY the public Supabase anon key — safe for browser bundles.
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
APP_ENV=production
APP_NAME=${APP_NAME:-Munshi}
APP_FLAVOR=prod
FEATURE_WHATSAPP=${FEATURE_WHATSAPP:-false}
FEATURE_DEMAND_MATCHING=${FEATURE_DEMAND_MATCHING:-false}
FEATURE_DEALER_CIRCLES=${FEATURE_DEALER_CIRCLES:-false}
FEATURE_DOCUMENTS=${FEATURE_DOCUMENTS:-true}
FEATURE_WEB_CONSOLE=${FEATURE_WEB_CONSOLE:-false}
FEATURE_BILLING=${FEATURE_BILLING:-true}
ENVEOF
info ".env.prod written."

# ── Step 4: Flutter pub get ───────────────────────────────────────────────
step "4/9  flutter pub get"
cd "${APP_DIR}"
"${FLUTTER}" pub get

# ── Step 5: Generate Drift code ───────────────────────────────────────────
step "5/9  dart run build_runner build (Drift codegen)"

# Attempt build. If it fails due to a corrupt pub cache, repair and retry.
if ! "${DART}" run build_runner build --delete-conflicting-outputs 2>&1; then
    warn "build_runner failed — attempting pub cache repair and retry..."
    "${FLUTTER}" pub cache repair
    "${FLUTTER}" pub get
    "${DART}" run build_runner build --delete-conflicting-outputs
fi

DRIFT_G="${APP_DIR}/lib/core/offline/drift_database.g.dart"
[[ -f "${DRIFT_G}" ]] || die "drift_database.g.dart was not generated.
  Run manually: cd ${APP_DIR} && dart run build_runner build --delete-conflicting-outputs
  Then check for errors above."
info "Generated: ${DRIFT_G}"

# ── Step 6: Analyze and test ──────────────────────────────────────────────
step "6/9  flutter analyze + flutter test"

"${FLUTTER}" analyze --no-fatal-warnings || \
    die "flutter analyze found errors. Fix them before deploying."

"${FLUTTER}" test || \
    die "flutter test failed. Fix failing tests before deploying."

info "Analyze and test passed."

# ── Step 7: Flutter web build ─────────────────────────────────────────────
step "7/9  flutter build web --release"

"${FLUTTER}" build web --release --base-href "/"

BUILD_DIR="${APP_DIR}/build/web"
[[ -f "${BUILD_DIR}/index.html" ]] || \
    die "build/web/index.html not found. Build failed — check output above."
info "Build output: ${BUILD_DIR}"

# ── Step 8: Deploy to release directory ───────────────────────────────────
step "8/9  Installing release"

run_priv mkdir -p "${RELEASES_DIR}"
run_priv cp -r "${BUILD_DIR}" "${RELEASE_DIR}"

# Set ownership to the Nginx user (nginx on AlmaLinux 9).
if id "${NGINX_USER}" &>/dev/null; then
    run_priv chown -R "${NGINX_USER}:${NGINX_USER}" "${RELEASE_DIR}"
else
    warn "Nginx user '${NGINX_USER}' not found on this system."
    warn "Set NGINX_USER= to the correct user and re-run, or chown manually."
fi

# Directories 755, files 644 — Nginx needs read, not write.
run_priv chmod -R u=rwX,g=rX,o=rX "${RELEASE_DIR}"

info "Release installed: ${RELEASE_DIR}"

# ── Atomic symlink swap ───────────────────────────────────────────────────
PREVIOUS_RELEASE=""
if [[ -L "${CURRENT_LINK}" ]]; then
    PREVIOUS_RELEASE=$(readlink "${CURRENT_LINK}")
    info "Previous release: ${PREVIOUS_RELEASE}"
fi

# ln -sfn on Linux: atomic replace — in-flight requests are never disrupted.
run_priv ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"
info "Symlink updated: ${CURRENT_LINK} → ${RELEASE_DIR}"

# ── Reload Nginx ──────────────────────────────────────────────────────────
info "Validating Nginx config..."
if run_priv nginx -t 2>&1; then
    run_priv systemctl reload nginx
    info "Nginx reloaded successfully."
else
    error "nginx -t failed — Nginx NOT reloaded."
    error "The new release is deployed but Nginx is still serving the previous one."
    error "Fix the Nginx config, then run: sudo systemctl reload nginx"
    exit 1
fi

# ── Step 9: Cleanup ───────────────────────────────────────────────────────
step "9/9  Cleanup"

# Reset .env.prod to placeholder so credentials do not sit in the repo
# working tree. The real values are baked into the Flutter JS bundle.
cat > "${APP_DIR}/.env.prod" <<'PLACEHOLDER'
# Munshi — Production Environment
# NEVER commit real credentials. This file is overwritten by deploy.sh.

SUPABASE_URL=https://your-prod-project.supabase.co
SUPABASE_ANON_KEY=your-prod-anon-key
APP_ENV=production
APP_NAME=Munshi
APP_FLAVOR=prod
FEATURE_WHATSAPP=false
FEATURE_DEMAND_MATCHING=false
FEATURE_DEALER_CIRCLES=false
FEATURE_DOCUMENTS=true
FEATURE_WEB_CONSOLE=false
FEATURE_BILLING=true
PLACEHOLDER
info "Reset .env.prod to placeholder."

# Prune old releases — keep the ${KEEP_RELEASES} most recent.
# Uses a temp file to avoid subshell variable-scope issues.
PRUNE_LIST=$(mktemp)
ls -1t "${RELEASES_DIR}" | tail -n +"$((KEEP_RELEASES + 1))" > "${PRUNE_LIST}" || true
while IFS= read -r old_release; do
    OLD_PATH="${RELEASES_DIR}/${old_release}"
    # Safety: never delete the release we just deployed.
    if [[ "${OLD_PATH}" != "${RELEASE_DIR}" ]] && [[ -d "${OLD_PATH}" ]]; then
        run_priv rm -rf "${OLD_PATH}"
        info "Pruned old release: ${old_release}"
    fi
done < "${PRUNE_LIST}"
rm -f "${PRUNE_LIST}"

# ── Done ──────────────────────────────────────────────────────────────────
divider
info "DEPLOY COMPLETE"
info "Release:  ${RELEASE_DIR}"
info "Live at:  https://property.aderalabs.tech/"
info ""
info "Verify deployment:"
info "  bash ${REPO_DIR}/deploy/vps/health-check.sh https://property.aderalabs.tech"
info ""
info "To roll back:"
info "  See ${REPO_DIR}/deploy/vps/rollback.md"
divider
