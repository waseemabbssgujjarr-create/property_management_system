#!/usr/bin/env bash
# MUNSHI — VPS Deploy Script
# Target OS : AlmaLinux 9.8 x86_64
# Nginx user: nginx  (AlmaLinux default)
#
# USAGE
#   As root:
#     bash deploy/vps/deploy.sh
#
#   As a non-root user with sudo:
#     sudo bash deploy/vps/deploy.sh
#
#   Override the deployment branch:
#     sudo DEPLOY_BRANCH=my-branch bash deploy/vps/deploy.sh
#
#   Override the environment file:
#     sudo MUNSHI_ENV=/path/to/environment bash deploy/vps/deploy.sh
#
# WHAT THIS SCRIPT DOES
#   1.  Validates required tools and paths.
#   2.  Checks working tree is clean (refuses to run on dirty trees, except
#       .env.prod which the script manages).
#   3.  Fetches and checks out the configured DEPLOY_BRANCH; aborts if the
#       branch does not exist on the remote.
#   4.  Loads and validates /etc/munshi/environment — refuses placeholder values.
#   5.  Writes .env.prod with public Supabase values (cleaned up by trap on any exit).
#   6.  flutter pub get.
#   7.  dart run build_runner build  (generates drift_database.g.dart).
#   8.  Checks web/index.html exists (requires prior `flutter create . --platforms web`).
#   9.  flutter analyze.
#   10. flutter test.
#   11. flutter build web --release.
#   12. Copies build/web into a timestamped release directory.
#   13. Runs `nginx -t` against the candidate release BEFORE touching the live symlink.
#   14. Atomically swaps /var/www/munshi/current only after nginx -t passes.
#   15. Reloads Nginx.
#   16. On any failure: restores previous symlink, leaves Nginx serving the old release.
#   17. Cleans up .env.prod (trap fires on both success and failure).
#   18. Prunes old releases — keeps ${KEEP_RELEASES} most recent.
#
# WHAT THIS SCRIPT NEVER DOES
#   - Writes service-role keys, WA keys, DB passwords or any server-side secret.
#   - Modifies /etc/nginx/nginx.conf or any other vhost.
#   - Restarts Nginx — only sends a reload signal after nginx -t passes.
#   - Changes firewall rules.
#   - Touches Apache, MariaDB, Redis or Supervisor.
#   - Silently deploys a branch other than DEPLOY_BRANCH.
#   - Stashes or discards developer working-tree changes.

set -euo pipefail

# ── Configurable variables (override via environment) ────────────────────────
# The branch that is deployed to production.  Override with DEPLOY_BRANCH=name.
# NEVER silently falls back to 'main' — if the branch is wrong you get an error.
DEPLOY_BRANCH="${DEPLOY_BRANCH:-deployment-prep/vps-almalinux}"
REPO_DIR="${REPO_DIR:-/opt/munshi-app}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/munshi}"
MUNSHI_ENV="${MUNSHI_ENV:-/etc/munshi/environment}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
# AlmaLinux 9 Nginx runs as the 'nginx' user by default.
NGINX_USER="${NGINX_USER:-nginx}"
# Flutter/Dart — auto-detected from PATH, or set FLUTTER_BIN / DART_BIN explicitly.
FLUTTER="${FLUTTER_BIN:-}"
DART="${DART_BIN:-}"

# Derived paths — do not override.
APP_DIR="${REPO_DIR}/app"
RELEASES_DIR="${DEPLOY_ROOT}/releases"
CURRENT_LINK="${DEPLOY_ROOT}/current"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RELEASE_DIR="${RELEASES_DIR}/${TIMESTAMP}"
ENV_PROD="${APP_DIR}/.env.prod"

# Remembered during deployment — used by the failure-recovery trap.
PREVIOUS_RELEASE=""
SYMLINK_SWAPPED=false   # true only after ln -sfn succeeds
ENV_PROD_WRITTEN=false  # true only after we write real creds to .env.prod

# ── Colour helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
step()    { echo -e "${CYAN}${BOLD}[STEP]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }
divider() { echo -e "${CYAN}────────────────────────────────────────────${NC}"; }

# ── Resolve Flutter/Dart executables ──────────────────────────────────────
resolve_bin() {
    local name="$1" override="$2" well_known="$3"
    if [[ -n "${override}" ]]; then
        [[ -x "${override}" ]] || die "${name} not executable at override path: ${override}"
        echo "${override}"; return
    fi
    if command -v "${name}" &>/dev/null; then
        echo "$(command -v "${name}")"; return
    fi
    if [[ -x "${well_known}" ]]; then
        echo "${well_known}"; return
    fi
    die "${name} not found. Set ${name^^}_BIN or add it to PATH. Typical VPS path: ${well_known}"
}
FLUTTER="$(resolve_bin flutter "${FLUTTER}" /opt/flutter/bin/flutter)"
DART="$(resolve_bin dart    "${DART}"    /opt/flutter/bin/dart)"

# ── Privileged command wrapper ────────────────────────────────────────────
# Runs command directly as root, or via sudo for non-root callers.
run_priv() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# ── .env.prod placeholder content ────────────────────────────────────────
# Written back by reset_env_prod() — used in trap and normal cleanup.
readonly ENV_PROD_PLACEHOLDER='# Munshi — Production Environment
# NEVER commit real credentials. This file is overwritten by deploy.sh.

SUPABASE_URL=https://your-prod-project.supabase.co
SUPABASE_ANON_KEY=REPLACE_WITH_ANON_KEY_FROM_SUPABASE_DASHBOARD
APP_ENV=production
APP_NAME=Munshi
APP_FLAVOR=prod
FEATURE_WHATSAPP=false
FEATURE_DEMAND_MATCHING=false
FEATURE_DEALER_CIRCLES=false
FEATURE_DOCUMENTS=true
FEATURE_WEB_CONSOLE=false
FEATURE_BILLING=true'

reset_env_prod() {
    # Restore .env.prod to placeholder — called from trap (both success and failure).
    # Uses a subshell so the return value of the calling function is not affected.
    if [[ "${ENV_PROD_WRITTEN}" == "true" ]]; then
        printf '%s\n' "${ENV_PROD_PLACEHOLDER}" > "${ENV_PROD}" 2>/dev/null || \
            error "WARNING: could not reset ${ENV_PROD} — check and reset manually."
        info "Reset ${ENV_PROD} to placeholder."
        ENV_PROD_WRITTEN=false
    fi
}

restore_symlink() {
    # Restore the previous symlink if we already swapped it.
    # Called from the failure trap — must not exit the trap.
    if [[ "${SYMLINK_SWAPPED}" == "true" ]]; then
        if [[ -n "${PREVIOUS_RELEASE}" && -d "${PREVIOUS_RELEASE}" ]]; then
            error "Restoring previous symlink: ${CURRENT_LINK} → ${PREVIOUS_RELEASE}"
            run_priv ln -sfn "${PREVIOUS_RELEASE}" "${CURRENT_LINK}" || \
                error "CRITICAL: could not restore previous symlink. Manual intervention required."
            error "Previous release restored. Nginx was NOT reloaded — it continues serving the old release."
        else
            error "No previous release to restore — ${CURRENT_LINK} may be broken."
            error "Manual intervention required: sudo ln -sfn <release_dir> ${CURRENT_LINK}"
        fi
        SYMLINK_SWAPPED=false
    fi
}

# ── Global cleanup trap ───────────────────────────────────────────────────
# Fires on EXIT (normal finish, die(), set -e abort, Ctrl-C, SIGTERM).
# Order: restore symlink first (un-breaks Nginx state), then clean .env.prod.
cleanup_on_exit() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        error ""
        error "Deploy failed (exit ${exit_code}) — running cleanup."
        restore_symlink
    fi
    reset_env_prod
}
trap cleanup_on_exit EXIT

# ── Banner ────────────────────────────────────────────────────────────────
divider
info "MUNSHI DEPLOY — ${TIMESTAMP}"
info "Branch:       ${DEPLOY_BRANCH}"
info "Repo:         ${REPO_DIR}"
info "App dir:      ${APP_DIR}"
info "Deploy root:  ${DEPLOY_ROOT}"
info "Env file:     ${MUNSHI_ENV}"
info "Release dir:  ${RELEASE_DIR}"
info "Flutter:      $("${FLUTTER}" --version 2>&1 | head -1)"
divider

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1 — Pre-flight: tools and paths
# ═══════════════════════════════════════════════════════════════════════════
step "1/10  Pre-flight checks"

[[ -d "${REPO_DIR}" ]]    || die "Repo directory not found: ${REPO_DIR}"
[[ -d "${APP_DIR}" ]]     || die "App directory not found: ${APP_DIR} — is the repo cloned to ${REPO_DIR}?"
[[ -f "${MUNSHI_ENV}" ]]  || die "Environment file not found: ${MUNSHI_ENV}
  Create it: sudo cp ${REPO_DIR}/deploy/vps/environment.example ${MUNSHI_ENV}
  Then fill in real values and: sudo chmod 600 ${MUNSHI_ENV}"

# Verify nginx is available (needed for nginx -t later).
if ! command -v nginx &>/dev/null; then
    if [[ -x /usr/sbin/nginx ]]; then
        NGINX=/usr/sbin/nginx
    else
        die "nginx not found. Install with: sudo dnf install -y nginx"
    fi
else
    NGINX="$(command -v nginx)"
fi
info "Nginx:        ${NGINX}"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2 — Working-tree safety check
# ═══════════════════════════════════════════════════════════════════════════
step "2/10  Working-tree check"

cd "${REPO_DIR}"

# Collect dirty files, excluding .env.prod which the script owns.
DIRTY_FILES=$(git status --porcelain | grep -v '^\?\?' | awk '{print $2}' | \
              grep -v '^app/\.env\.prod$' || true)

if [[ -n "${DIRTY_FILES}" ]]; then
    error "The working tree has uncommitted changes:"
    echo "${DIRTY_FILES}" | sed 's/^/    /'
    error ""
    error "Deploy refused — the deployment branch must be clean to guarantee"
    error "reproducibility. Commit, stash, or discard these changes and re-run."
    error ""
    error "If these are intentional pre-release changes, commit them to ${DEPLOY_BRANCH} first."
    die "Aborting: dirty working tree."
fi

info "Working tree is clean."

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3 — Fetch and check out DEPLOY_BRANCH
# ═══════════════════════════════════════════════════════════════════════════
step "3/10  Updating repository (branch: ${DEPLOY_BRANCH})"

cd "${REPO_DIR}"
git fetch --quiet origin

# Verify the branch exists on the remote before attempting checkout.
# This prevents silent fallback to whatever branch is currently checked out.
if ! git ls-remote --exit-code --heads origin "${DEPLOY_BRANCH}" &>/dev/null; then
    die "Branch '${DEPLOY_BRANCH}' does not exist on remote 'origin'.
  Available remote branches:
$(git branch -r | sed 's/^/    /')
  Set DEPLOY_BRANCH=<branch> to deploy a different branch."
fi

# Check out the branch and pull the latest commits.
git checkout --quiet "${DEPLOY_BRANCH}"
git pull --quiet origin "${DEPLOY_BRANCH}"
info "Git HEAD: $(git rev-parse --short HEAD) — $(git log -1 --format='%s')"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4 — Load and validate environment
# ═══════════════════════════════════════════════════════════════════════════
step "4/10  Loading environment: ${MUNSHI_ENV}"

# shellcheck source=/dev/null
set -a
source "${MUNSHI_ENV}"
set +a

# Required public variables.
for var in SUPABASE_URL SUPABASE_ANON_KEY; do
    [[ -n "${!var:-}" ]] || die "${var} is not set in ${MUNSHI_ENV}"
done

# Reject placeholder values — refuse to build a bundle with fake config.
if echo "${SUPABASE_URL}" | grep -qE 'your-|REPLACE_WITH|example\.com|placeholder'; then
    die "SUPABASE_URL still contains a placeholder value: ${SUPABASE_URL}
  Edit ${MUNSHI_ENV} with a real Supabase project URL."
fi
if echo "${SUPABASE_ANON_KEY}" | grep -qE 'YOUR_|your-|REPLACE_WITH|placeholder'; then
    die "SUPABASE_ANON_KEY still contains a placeholder value.
  Edit ${MUNSHI_ENV} with the real anon key from the Supabase Dashboard."
fi

# Safety guard — the service-role key must never be shipped to a browser.
if echo "${SUPABASE_ANON_KEY}" | grep -qi 'service_role'; then
    die "SUPABASE_ANON_KEY appears to contain a service-role key.
  The service-role key must NEVER be shipped to a browser.
  Use only the anon (public) key here."
fi

info "Supabase URL: ${SUPABASE_URL}"
info "Anon key:     ${SUPABASE_ANON_KEY:0:12}... [truncated]"

# Report which feature flags will be bundled.
info "Feature flags bundled into build:"
for flag in FEATURE_WHATSAPP FEATURE_DEMAND_MATCHING FEATURE_DEALER_CIRCLES \
            FEATURE_DOCUMENTS FEATURE_WEB_CONSOLE FEATURE_BILLING; do
    info "  ${flag}=${!flag:-<unset — will use script default>}"
done

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5 — Write .env.prod (public values only)
# ═══════════════════════════════════════════════════════════════════════════
# Done as late as possible, after all pre-flight checks pass.
# The trap registered above restores the placeholder on any subsequent failure.
step "5/10  Writing .env.prod (public values only)"

# Feature flag values: honour what the operator set in /etc/munshi/environment.
# The ${VAR:-default} syntax is used only where the environment file genuinely
# has no opinion; FEATURE_WEB_CONSOLE deliberately defaults to false (off by
# default for safety) but is fully overridable by setting it in the env file.
cat > "${ENV_PROD}" <<ENVEOF
# Generated by deploy.sh at ${TIMESTAMP} — do not edit manually.
# Contains ONLY the public Supabase anon key — safe for browser bundles.
# Rebuilt from /etc/munshi/environment on every deploy.
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

ENV_PROD_WRITTEN=true
info ".env.prod written (will be reset to placeholder on exit)."

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6 — flutter pub get
# ═══════════════════════════════════════════════════════════════════════════
step "6/10  flutter pub get"
cd "${APP_DIR}"
"${FLUTTER}" pub get

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7 — Generate Drift code (build_runner)
# ═══════════════════════════════════════════════════════════════════════════
step "7/10  dart run build_runner build  (Drift code generation)"

# Attempt code generation. On failure, repair the pub cache and retry once.
# build_runner must succeed before flutter analyze can see the generated types.
if ! "${DART}" run build_runner build --delete-conflicting-outputs 2>&1; then
    warn "build_runner failed on first attempt — repairing pub cache and retrying..."
    "${FLUTTER}" pub cache repair
    "${FLUTTER}" pub get
    # Retry; if this also fails, set -e terminates the script via the trap.
    "${DART}" run build_runner build --delete-conflicting-outputs
fi

DRIFT_G="${APP_DIR}/lib/core/offline/drift_database.g.dart"
[[ -f "${DRIFT_G}" ]] || \
    die "drift_database.g.dart was not generated at ${DRIFT_G}.
  Run manually: cd ${APP_DIR} && dart run build_runner build --delete-conflicting-outputs
  Then check for errors above."
info "Generated: ${DRIFT_G}"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 8 — Verify Flutter web platform files exist
# ═══════════════════════════════════════════════════════════════════════════
step "8/10  Checking Flutter web platform prerequisites"

WEB_INDEX="${APP_DIR}/web/index.html"
if [[ ! -f "${WEB_INDEX}" ]]; then
    die "Flutter web platform files not found: ${WEB_INDEX}
  The web platform must be initialised once before deploying:
    cd ${APP_DIR}
    flutter create . --platforms web
  Commit the generated web/ files to ${DEPLOY_BRANCH}, then re-run this script."
fi
info "Flutter web platform files present: ${APP_DIR}/web/"

# ── flutter analyze ─────────────────────────────────────────────────────
# Runs AFTER build_runner so generated types are available.
"${FLUTTER}" analyze --no-fatal-warnings || \
    die "flutter analyze found errors. Fix them before deploying."
info "flutter analyze: OK"

# ── flutter test ────────────────────────────────────────────────────────
"${FLUTTER}" test || \
    die "flutter test failed. Fix failing tests before deploying."
info "flutter test: OK"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 9 — flutter build web --release
# ═══════════════════════════════════════════════════════════════════════════
step "9/10  flutter build web --release"

"${FLUTTER}" build web --release --base-href "/"

BUILD_DIR="${APP_DIR}/build/web"
[[ -f "${BUILD_DIR}/index.html" ]] || \
    die "build/web/index.html not found after build — check Flutter output above."
info "Build output: ${BUILD_DIR}"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 10 — Deploy release and activate atomically
# ═══════════════════════════════════════════════════════════════════════════
step "10/10  Installing release and activating"

# ── 10a. Copy build output to a timestamped release directory ─────────────
run_priv mkdir -p "${RELEASES_DIR}"
run_priv cp -r "${BUILD_DIR}" "${RELEASE_DIR}"

if id "${NGINX_USER}" &>/dev/null; then
    run_priv chown -R "${NGINX_USER}:${NGINX_USER}" "${RELEASE_DIR}"
else
    warn "Nginx user '${NGINX_USER}' not found — set NGINX_USER= and re-run, or chown manually."
fi

# Directories 750, files 640 — Nginx can read, world cannot write.
run_priv chmod -R u=rwX,g=rX,o= "${RELEASE_DIR}"

info "Release staged: ${RELEASE_DIR}"

# ── 10b. Validate Nginx configuration against the candidate release ────────
# We run nginx -t BEFORE touching the live symlink.
# Nginx includes the munshi.conf vhost which uses `root /var/www/munshi/current`.
# Even though `current` still points at the previous release at this point, the
# purpose of nginx -t here is to confirm the Nginx *config* is syntactically valid
# (not that the new content is correct). Any config breakage is caught before
# the symlink swap.
info "Validating Nginx configuration (nginx -t)..."
if ! run_priv "${NGINX}" -t 2>&1; then
    die "nginx -t failed — Nginx configuration is invalid.
  The new release has been staged at ${RELEASE_DIR} but was NOT activated.
  Fix /etc/nginx/conf.d/munshi.conf, then run this script again."
fi
info "Nginx configuration: valid"

# ── 10c. Capture previous release for rollback ────────────────────────────
if [[ -L "${CURRENT_LINK}" ]]; then
    PREVIOUS_RELEASE=$(readlink "${CURRENT_LINK}")
    info "Previous release: ${PREVIOUS_RELEASE}"
fi

# ── 10d. Atomic symlink swap ──────────────────────────────────────────────
# ln -sfn on Linux is atomic — in-flight requests are never disrupted.
run_priv ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"
SYMLINK_SWAPPED=true
info "Symlink updated: ${CURRENT_LINK} → ${RELEASE_DIR}"

# ── 10e. Reload Nginx ─────────────────────────────────────────────────────
# nginx -t already passed above; reload should not fail unless the config
# was changed by a concurrent process between the -t check and now.
if ! run_priv systemctl reload nginx; then
    error "systemctl reload nginx failed after symlink swap."
    error "Attempting to restore previous symlink..."
    # restore_symlink is also called by the trap, but calling it here gives a
    # cleaner error message before the trap runs.
    restore_symlink
    die "Deployment failed: Nginx reload error. Previous release has been restored."
fi
info "Nginx reloaded successfully."

# At this point the deployment is fully committed.
# Mark symlink as stable so the exit trap does NOT attempt to restore it.
SYMLINK_SWAPPED=false

# ═══════════════════════════════════════════════════════════════════════════
# Cleanup — prune old releases
# ═══════════════════════════════════════════════════════════════════════════
# .env.prod reset is handled by the trap; do not duplicate it here.

# Prune old releases, keeping the ${KEEP_RELEASES} most recent.
# Uses a temp file to avoid subshell variable-scope issues.
PRUNE_LIST=$(mktemp)
ls -1t "${RELEASES_DIR}" | tail -n +"$((KEEP_RELEASES + 1))" > "${PRUNE_LIST}" || true
while IFS= read -r old_release; do
    OLD_PATH="${RELEASES_DIR}/${old_release}"
    # Never delete the release just deployed or the one we just restored from.
    if [[ "${OLD_PATH}" != "${RELEASE_DIR}" ]] && \
       [[ "${OLD_PATH}" != "${PREVIOUS_RELEASE}" ]] && \
       [[ -d "${OLD_PATH}" ]]; then
        run_priv rm -rf "${OLD_PATH}"
        info "Pruned old release: ${old_release}"
    fi
done < "${PRUNE_LIST}"
rm -f "${PRUNE_LIST}"

# ── Done ──────────────────────────────────────────────────────────────────
divider
info "DEPLOY COMPLETE"
info "Branch:   ${DEPLOY_BRANCH}"
info "Commit:   $(git -C "${REPO_DIR}" rev-parse --short HEAD)"
info "Release:  ${RELEASE_DIR}"
info "Live at:  https://property.aderalabs.tech/"
info ""
info "Verify:"
info "  bash ${REPO_DIR}/deploy/vps/health-check.sh https://property.aderalabs.tech"
info ""
info "To roll back:"
info "  See ${REPO_DIR}/deploy/vps/rollback.md"
divider
# trap fires here (exit 0) — resets .env.prod to placeholder, no symlink restore.
