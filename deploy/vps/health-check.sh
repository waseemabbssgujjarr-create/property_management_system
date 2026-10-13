#!/usr/bin/env bash
# MUNSHI — Health Check Script
# Target: AlmaLinux 9.8 VPS behind Cloudflare orange-cloud proxy
#
# USAGE:
#   bash health-check.sh [https://property.aderalabs.tech]
#
# CLOUDFLARE NOTES:
#   - The TLS certificate seen by openssl s_client is Cloudflare's OWN
#     browser-facing cert, NOT the Cloudflare Origin Certificate on the VPS.
#     This is correct and expected. The check reports the expiry as INFO only.
#   - The Server: header is suppressed or replaced by Cloudflare ("cloudflare").
#     This is correct and expected — not a failure.
#   - Checks 1-5 (HTTP responses) work normally behind Cloudflare.
#   - Check 9 (local symlink) requires running ON the VPS; it is skipped
#     gracefully when run remotely.

set -euo pipefail

BASE_URL="${1:-https://property.aderalabs.tech}"
TIMEOUT=20
PASS=0
FAIL=0
INFO=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { PASS=$((PASS+1)); echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { FAIL=$((FAIL+1)); echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { INFO=$((INFO+1)); echo -e "${CYAN}[INFO]${NC} $*"; }

echo "=== MUNSHI Health Check — $(date) ==="
echo "Target:  ${BASE_URL}"
echo "Note:    Domain is behind Cloudflare — TLS and Server header"
echo "         checks are Cloudflare-aware (see comments below)."
echo ""

# ── Check 1: /health endpoint ────────────────────────────────────────────
echo "--- HTTP checks ---"
HTTP_CODE=$(curl -sSL -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" "${BASE_URL}/health" 2>/dev/null || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
    pass "HTTP /health → ${HTTP_CODE}"
else
    fail "HTTP /health → ${HTTP_CODE} (expected 200)"
    warn "  Check: Is Nginx running? Is /etc/nginx/conf.d/munshi.conf loaded?"
    warn "  Run:   sudo nginx -t && sudo systemctl status nginx"
fi

# ── Check 2: Root serves 200 ─────────────────────────────────────────────
HTTP_ROOT=$(curl -sSL -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" "${BASE_URL}/" 2>/dev/null || echo "000")
if [[ "${HTTP_ROOT}" == "200" ]]; then
    pass "Root / → ${HTTP_ROOT}"
else
    fail "Root / → ${HTTP_ROOT} (expected 200)"
fi

# ── Check 3: Flutter marker in index.html ────────────────────────────────
HTML=$(curl -sSL --max-time "${TIMEOUT}" "${BASE_URL}/" 2>/dev/null || echo "")
if echo "${HTML}" | grep -q "flutter.js"; then
    pass "flutter.js referenced in index.html"
elif echo "${HTML}" | grep -q "FlutterLoader\|_flutter\|main\.dart\.js"; then
    pass "Flutter bootstrap found in index.html"
else
    fail "No Flutter bootstrap marker found in index.html — build may be missing or corrupt"
    warn "  Check: ls /var/www/munshi/current/index.html"
fi

# ── Check 4: Deep-link SPA routing ───────────────────────────────────────
DEEP=$(curl -sSL -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" "${BASE_URL}/home" 2>/dev/null || echo "000")
if [[ "${DEEP}" == "200" ]]; then
    pass "Deep-link /home → ${DEEP} (SPA routing OK)"
else
    fail "Deep-link /home → ${DEEP} (expected 200)"
    warn "  Check nginx.conf has: try_files \$uri \$uri/ /index.html;"
fi

# ── Check 5: main.dart.js present ────────────────────────────────────────
MAIN_JS=$(curl -sSL -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" "${BASE_URL}/main.dart.js" 2>/dev/null || echo "000")
if [[ "${MAIN_JS}" == "200" ]]; then
    pass "main.dart.js → ${MAIN_JS}"
else
    fail "main.dart.js → ${MAIN_JS} (Flutter compiled JS missing)"
    warn "  Check: ls /var/www/munshi/current/main.dart.js"
fi

# ── Check 6: HTTP → HTTPS redirect ───────────────────────────────────────
# Cloudflare handles this redirect at its edge when "Always Use HTTPS"
# is enabled. We check curl sees a 2xx final response (after redirect).
if [[ "${BASE_URL}" =~ ^https:// ]]; then
    HTTP_URL="${BASE_URL/https:\/\//http://}"
    REDIRECT_CODE=$(curl -sSL -o /dev/null -w "%{http_code}" \
        --max-time "${TIMEOUT}" "${HTTP_URL}/health" 2>/dev/null || echo "000")
    if [[ "${REDIRECT_CODE}" == "200" ]]; then
        pass "HTTP→HTTPS redirect: final status ${REDIRECT_CODE} (Cloudflare handled)"
    elif [[ "${REDIRECT_CODE}" == "301" || "${REDIRECT_CODE}" == "302" ]]; then
        pass "HTTP→HTTPS redirect status: ${REDIRECT_CODE}"
    else
        warn "HTTP→HTTPS: final status ${REDIRECT_CODE}"
        warn "  Enable 'Always Use HTTPS' in Cloudflare Dashboard → SSL/TLS → Edge Certificates"
    fi
fi

# ── Check 7: TLS certificate (Cloudflare-aware) ───────────────────────────
echo ""
echo "--- TLS check (Cloudflare-aware) ---"
if [[ "${BASE_URL}" =~ ^https:// ]]; then
    DOMAIN=$(echo "${BASE_URL}" | sed 's|https://||' | cut -d/ -f1)

    # When Cloudflare proxies the domain, openssl s_client connects to
    # Cloudflare's edge — it will see CLOUDFLARE's browser-facing cert,
    # not the Origin Certificate installed on the VPS. This is correct.
    CERT_INFO=$(echo | openssl s_client \
        -connect "${DOMAIN}:443" \
        -servername "${DOMAIN}" \
        2>/dev/null || echo "")

    if [[ -z "${CERT_INFO}" ]]; then
        fail "Could not connect to ${DOMAIN}:443 via openssl"
        warn "  Check: Is port 443 open on Cloudflare? Is the domain orange-cloud?"
    else
        CERT_CN=$(echo "${CERT_INFO}" | openssl x509 -noout -subject 2>/dev/null \
            | sed 's/.*CN = //' | sed 's/.*CN=//' || echo "unknown")
        CERT_EXPIRE=$(echo "${CERT_INFO}" | openssl x509 -noout -enddate 2>/dev/null \
            | cut -d= -f2 || echo "")
        CERT_ISSUER=$(echo "${CERT_INFO}" | openssl x509 -noout -issuer 2>/dev/null \
            | head -1 || echo "")

        if echo "${CERT_ISSUER}" | grep -qi "cloudflare"; then
            info "TLS cert issuer: Cloudflare (expected — domain is orange-cloud proxied)"
        else
            info "TLS cert issuer: ${CERT_ISSUER}"
            warn "  Issuer is not Cloudflare. Is the domain still grey-cloud (DNS only)?"
            warn "  In grey-cloud mode, the VPS Origin Certificate is presented directly."
            warn "  Ensure Cloudflare SSL/TLS mode is set to 'Full (strict)'."
        fi

        info "TLS cert CN: ${CERT_CN}"

        if [[ -n "${CERT_EXPIRE}" ]]; then
            info "TLS cert valid until: ${CERT_EXPIRE}"
            EXPIRE_EPOCH=$(date -d "${CERT_EXPIRE}" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 ))
            if (( DAYS_LEFT < 30 )); then
                warn "Certificate expires in ${DAYS_LEFT} days — renew in Cloudflare Dashboard"
            elif (( DAYS_LEFT > 0 )); then
                pass "TLS certificate valid (${DAYS_LEFT} days remaining)"
            else
                fail "TLS certificate appears to have expired"
            fi
        fi
    fi
else
    warn "Skipping TLS check (not HTTPS URL)"
fi

# ── Check 8: Server header (Cloudflare-aware) ─────────────────────────────
echo ""
echo "--- Server header check (Cloudflare-aware) ---"
SERVER_HEADER=$(curl -sSL -I --max-time "${TIMEOUT}" "${BASE_URL}/" 2>/dev/null \
    | grep -i "^server:" | head -1 | tr -d '\r' || echo "")
if [[ -z "${SERVER_HEADER}" ]]; then
    info "Server header: (absent — Cloudflare may have stripped it)"
elif echo "${SERVER_HEADER}" | grep -qi "cloudflare"; then
    info "Server header: ${SERVER_HEADER} (expected — Cloudflare replaces the Nginx header when proxying)"
    info "  Your nginx.conf has 'server_tokens off' which limits version exposure on the origin."
elif echo "${SERVER_HEADER}" | grep -qi "nginx"; then
    # Seen when domain is grey-cloud (DNS only) — Nginx header passes through directly.
    pass "Server header: ${SERVER_HEADER} (Nginx visible — domain may be grey-cloud)"
    warn "  If domain should be orange-cloud, enable the proxy toggle in Cloudflare DNS."
else
    warn "Server header: ${SERVER_HEADER} (unexpected value — check Nginx is running)"
fi

# ── Check 9: Security response headers ────────────────────────────────────
echo ""
echo "--- Security headers ---"
RESP_HEADERS=$(curl -sSL -I --max-time "${TIMEOUT}" "${BASE_URL}/" 2>/dev/null || echo "")
for header in "X-Frame-Options" "X-Content-Type-Options" "Strict-Transport-Security"; do
    if echo "${RESP_HEADERS}" | grep -qi "${header}"; then
        pass "Security header present: ${header}"
    else
        warn "Security header absent: ${header}"
        warn "  This may be set by Cloudflare Transform Rules or missing from nginx.conf."
        warn "  Add to /etc/nginx/conf.d/munshi.conf if not relying on Cloudflare to inject it."
    fi
done

# ── Check 10: Local symlink (VPS-only) ────────────────────────────────────
echo ""
echo "--- Local VPS checks (skipped if running remotely) ---"
CURRENT="/var/www/munshi/current"
if [[ -L "${CURRENT}" ]]; then
    TARGET=$(readlink "${CURRENT}")
    if [[ -d "${TARGET}" ]]; then
        pass "Symlink ${CURRENT} → ${TARGET}"
        INDEX="${TARGET}/index.html"
        if [[ -f "${INDEX}" ]]; then
            pass "index.html exists at ${TARGET}"
        else
            fail "index.html NOT found at ${TARGET} — deploy may be incomplete"
        fi
    else
        fail "Symlink ${CURRENT} → ${TARGET} (target directory missing!)"
        warn "  Run deploy.sh again or manually point the symlink to a valid release."
    fi
elif [[ -d /var/www/munshi ]]; then
    fail "Symlink ${CURRENT} not found — deploy.sh has not been run yet"
else
    info "Skipping local symlink check (not running on the VPS)"
fi

# ── Check 11: Nginx service running (VPS-only) ────────────────────────────
if command -v systemctl &>/dev/null && systemctl list-units --type=service 2>/dev/null | grep -q nginx; then
    NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "unknown")
    if [[ "${NGINX_STATUS}" == "active" ]]; then
        pass "Nginx service: ${NGINX_STATUS}"
    else
        fail "Nginx service: ${NGINX_STATUS} (expected active)"
        warn "  Run: sudo systemctl start nginx"
    fi
else
    info "Skipping Nginx service check (systemctl not available or not on VPS)"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "================================================="
echo "Results: ${PASS} passed  |  ${FAIL} failed  |  ${INFO} informational"
echo "================================================="
if (( FAIL > 0 )); then
    echo -e "${RED}HEALTH CHECK FAILED — ${FAIL} issue(s) need attention.${NC}"
    exit 1
else
    echo -e "${GREEN}HEALTH CHECK PASSED${NC}"
    if (( INFO > 0 )); then
        echo "(Review INFO items above — they are not failures but worth confirming)"
    fi
fi
