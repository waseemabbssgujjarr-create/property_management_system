/**
 * validate_url.ts — SSRF protection for wa-connect Edge Function.
 *
 * Extracted from index.ts so it can be unit-tested without a running server.
 *
 * Validation layers (applied to ALL URLs regardless of source):
 *   1. Valid URL syntax (parseable by the URL constructor)
 *   2. HTTPS protocol only (reject http://)
 *   3. Not a private or internal address (loopback, RFC 1918, link-local)
 *
 * Additional layer (client-supplied URLs only):
 *   4. Hostname must be in an explicit allowlist
 *
 * Env-var URLs (WA_API_BASE_URL) are operator-configured and trusted for
 * hostname, but still must pass layers 1–3 as defense-in-depth against
 * misconfiguration (e.g. accidentally setting http://localhost:8080).
 */

export interface ValidateApiBaseUrlOptions {
  /**
   * When true, the URL's hostname must match an entry in the allowlist.
   * Set to true for client-supplied URLs, false for trusted env-var URLs.
   */
  enforceAllowlist: boolean

  /**
   * Comma-separated list of allowed hostnames (e.g. "api.example.com,api.wa.example.com").
   * Supports wildcard subdomains: "*.example.com" matches "api.example.com".
   * If empty and enforceAllowlist is true, fallbackHost is used as the sole entry.
   * Ignored when enforceAllowlist is false.
   */
  allowedHosts?: string

  /**
   * Fallback hostname used as the sole allowlist entry when allowedHosts is empty.
   * Typically derived from the hostname of WA_API_BASE_URL.
   */
  fallbackHost?: string
}

export interface ValidationResult {
  valid: boolean
  error?: string
}

// ── Private-IP / internal-address check ────────────────────────────────────
// Applies to ALL URLs (client-supplied and env-var) as defense-in-depth.
// Covers IPv4 private ranges, IPv6 ULA, IPv6 link-local, IPv6 loopback,
// and IPv4-mapped/compatible IPv6 addresses that embed private IPv4.

function looksLikeIPv4(s: string): boolean {
  return /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(s)
}

/**
 * Convert two hex 16-bit groups to an IPv4 string.
 * E.g. "a00:1" → "10.0.0.1", "808:808" → "8.8.8.8".
 * Returns null if the input doesn't match the expected pattern.
 *
 * V8/Deno normalizes all IPv4-in-IPv6 mixed notation to compressed hex:
 *   ::ffff:10.0.0.1 → ::ffff:a00:1
 *   ::10.0.0.1      → ::a00:1
 * So the hex path is the one that fires in production. The mixed-notation
 * path (looksLikeIPv4) is retained as defense-in-depth for runtimes that
 * might preserve the original form.
 */
function extractIpv4FromHexGroups(mapped: string): string | null {
  const m = mapped.match(/^([0-9a-f]{1,4}):([0-9a-f]{1,4})$/)
  if (!m) return null
  const hi = parseInt(m[1], 16)
  const lo = parseInt(m[2], 16)
  return `${(hi >> 8) & 0xff}.${hi & 0xff}.${(lo >> 8) & 0xff}.${lo & 0xff}`
}

function isPrivateOrInternal(hostname: string): boolean {
  const h = hostname.toLowerCase()

  // ── Named internal hosts ────────────────────────────────────────────────
  if (h === 'localhost') return true
  if (h.endsWith('.internal') || h.endsWith('.local')) return true

  // ── IPv4 ranges ─────────────────────────────────────────────────────────
  // This-network 0.0.0.0/8
  if (h.startsWith('0.')) return true
  // Loopback 127.0.0.0/8
  if (h.startsWith('127.')) return true
  // Private 10.0.0.0/8
  if (h.startsWith('10.')) return true
  // Private 192.168.0.0/16
  if (h.startsWith('192.168.')) return true
  // Link-local 169.254.0.0/16
  if (h.startsWith('169.254.')) return true
  // Private 172.16.0.0/12 (172.16.x – 172.31.x)
  if (h.startsWith('172.')) {
    const secondOctet = parseInt(h.split('.')[1], 10)
    if (secondOctet >= 16 && secondOctet <= 31) return true
  }

  // ── IPv6 ranges ─────────────────────────────────────────────────────────
  if (h.includes(':')) {
    // Loopback ::1
    if (h === '::1') return true
    // Unique local addresses fc00::/7 (covers fc00:: and fd00::)
    if (h.startsWith('fc') || h.startsWith('fd')) return true
    // Link-local fe80::/10
    if (h.startsWith('fe80:')) return true

    // IPv4-mapped IPv6: ::ffff:X.X.X.X (mixed) or ::ffff:XXXX:XXXX (hex)
    // V8/Deno normalizes mixed notation to hex, so the hex path is what
    // fires in production. Mixed notation is kept as defense-in-depth.
    if (h.startsWith('::ffff:')) {
      const mapped = h.slice(7) // strip "::ffff:"
      if (looksLikeIPv4(mapped)) {
        if (isPrivateOrInternal(mapped)) return true
      } else {
        const ip4 = extractIpv4FromHexGroups(mapped)
        if (ip4 && isPrivateOrInternal(ip4)) return true
      }
    }

    // IPv4-compatible IPv6: ::X.X.X.X or ::XXXX:XXXX (deprecated bypass vector)
    // V8/Deno normalizes ::10.0.0.1 to ::a00:1, so hex parsing is required.
    if (h.startsWith('::') && !h.startsWith('::ffff:')) {
      const mapped = h.slice(2) // strip "::"
      if (looksLikeIPv4(mapped)) {
        if (isPrivateOrInternal(mapped)) return true
      } else {
        const ip4 = extractIpv4FromHexGroups(mapped)
        if (ip4 && isPrivateOrInternal(ip4)) return true
      }
    }
  }

  return false
}

// ── Hostname allowlist check ────────────────────────────────────────────────

function hostnameMatchesAllowlist(hostname: string, allowedHosts: string[]): boolean {
  return allowedHosts.some((allowed) => {
    if (allowed.startsWith('*.')) {
      // Wildcard subdomain: *.example.com matches api.example.com,
      // api.ourwhatsapp.example.com (multi-level subdomains), etc.
      //
      // The suffix is ".example.com" (with a leading dot). The endsWith()
      // check requires a real dot before "example.com", so:
      //   api.example.com           → ends with ".example.com" → PASS
      //   api.ourwhatsapp.example.com → ends with ".example.com" → PASS
      //   notexample.com            → ends with "texample.com" (no leading dot) → FAIL
      //   evil.notexample.com       → ends with "texample.com" (no leading dot) → FAIL
      //   example.com               → ends with "xample.com" → FAIL
      //
      // The leading dot in the suffix is the dot-boundary anchor.
      // "notexample.com" cannot end with ".example.com" because the character
      // at that boundary position is 't', not '.'.
      return hostname.endsWith(allowed.slice(1))
    }
    return hostname === allowed
  })
}

// ── Main validation function ────────────────────────────────────────────────

export function validateApiBaseUrl(
  urlStr: string,
  options: ValidateApiBaseUrlOptions,
): ValidationResult {
  // ── Layer 1: Valid URL syntax ──────────────────────────────────────────
  let parsed: URL
  try {
    parsed = new URL(urlStr)
  } catch {
    return { valid: false, error: 'Invalid URL format' }
  }

  // ── Layer 2: HTTPS only ─────────────────────────────────────────────────
  if (parsed.protocol !== 'https:') {
    return { valid: false, error: 'api_base_url must use HTTPS' }
  }

  // The WHATWG URL spec and V8/Deno include square brackets in the hostname
  // property for IPv6 addresses (e.g. "[::1]"). Strip them so prefix-based
  // checks (startsWith, ===) match correctly.
  // Also strip a trailing dot that appears in FQDN notation
  // (e.g. "api.example.com." → "api.example.com") so allowlist comparisons
  // do not fail on technically-valid but unusual URL forms.
  const hostname = parsed.hostname
    .toLowerCase()
    .replace(/^\[|\]$/g, '') // strip IPv6 brackets
    .replace(/\.$/, '')      // strip FQDN trailing dot

  if (hostname.length === 0) {
    return { valid: false, error: 'Invalid URL format' }
  }

  // ── Layer 3: Reject private / internal addresses ───────────────────────
  if (isPrivateOrInternal(hostname)) {
    return { valid: false, error: 'api_base_url must not point to a private or internal address' }
  }

  // ── Layer 4: Hostname allowlist (client-supplied URLs only) ────────────
  if (options.enforceAllowlist) {
    let allowedHosts = (options.allowedHosts || '')
      .split(',')
      .map((h) => h.trim().toLowerCase())
      .filter((h) => h.length > 0)

    // Fall back to the provided fallback host
    if (allowedHosts.length === 0 && options.fallbackHost) {
      allowedHosts = [options.fallbackHost.toLowerCase()]
    }

    if (allowedHosts.length === 0) {
      return {
        valid: false,
        error:
          'No WA API allowed hosts configured. Set WA_API_ALLOWED_HOSTS env var ' +
          '(comma-separated list of trusted hostnames).',
      }
    }

    if (!hostnameMatchesAllowlist(hostname, allowedHosts)) {
      return {
        valid: false,
        error:
          `api_base_url host "${hostname}" is not in the allowed list. ` +
          `Allowed: ${allowedHosts.join(', ')}`,
      }
    }
  }

  return { valid: true }
}
