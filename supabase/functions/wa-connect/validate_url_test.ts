/**
 * validate_url_test.ts — unit tests for the SSRF validation function.
 *
 * Run with:
 *   deno test --allow-env supabase/functions/wa-connect/validate_url_test.ts
 *
 * These tests do NOT require a running Supabase instance or network access.
 * They test validateApiBaseUrl() in isolation with injected config.
 */

import { assertEquals } from 'https://deno.land/std@0.177.0/testing/asserts.ts'
import { validateApiBaseUrl } from './validate_url.ts'

// ── Helper: standard options for client-supplied URLs ────────────────────
const clientOpts = (allowedHosts: string, fallbackHost = '') => ({
  enforceAllowlist: true,
  allowedHosts,
  fallbackHost,
})

// ── Helper: standard options for env-var URLs ────────────────────────────
const envOpts = () => ({
  enforceAllowlist: false,
  allowedHosts: '',
  fallbackHost: '',
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: client-supplied URLs (allowlist enforced)
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL with exact allowlist match passes', () => {
  const result = validateApiBaseUrl(
    'https://api.ourwhatsapp.example.com/v1',
    clientOpts('api.ourwhatsapp.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('client URL with no allowlist match is rejected', () => {
  const result = validateApiBaseUrl(
    'https://evil.example.com/v1',
    clientOpts('api.ourwhatsapp.example.com'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('not in the allowed list'), true)
})

Deno.test('client URL with multiple allowed hosts passes on any match', () => {
  const result = validateApiBaseUrl(
    'https://api.wa.aderalabs.tech/v1',
    clientOpts('api.ourwhatsapp.example.com,api.wa.aderalabs.tech'),
  )
  assertEquals(result.valid, true)
})

Deno.test('client URL with wildcard subdomain allowlist passes', () => {
  const result = validateApiBaseUrl(
    'https://api.ourwhatsapp.example.com/v1',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('client URL with wildcard allowlist rejects bare domain', () => {
  const result = validateApiBaseUrl(
    'https://example.com/v1',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: missing allowlist
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL with empty allowlist and no fallback is rejected', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com/v1',
    clientOpts(''),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('No WA API allowed hosts configured'), true)
})

Deno.test('client URL with empty allowlist but fallback host passes', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com/v1',
    clientOpts('', 'api.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('client URL with empty allowlist and mismatched fallback is rejected', () => {
  const result = validateApiBaseUrl(
    'https://evil.com/v1',
    clientOpts('', 'api.example.com'),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: HTTP URLs (rejected for all sources)
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client HTTP URL is rejected', () => {
  const result = validateApiBaseUrl(
    'http://api.example.com/v1',
    clientOpts('api.example.com'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error, 'api_base_url must use HTTPS')
})

Deno.test('env-var HTTP URL is rejected', () => {
  const result = validateApiBaseUrl(
    'http://api.example.com/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error, 'api_base_url must use HTTPS')
})

Deno.test('env-var HTTP localhost URL is rejected (not just HTTPS check)', () => {
  const result = validateApiBaseUrl(
    'http://localhost:8080',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error, 'api_base_url must use HTTPS')
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: private / internal IPs (rejected for all sources)
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL to 127.0.0.1 is rejected', () => {
  const result = validateApiBaseUrl(
    'https://127.0.0.1/v1',
    clientOpts('127.0.0.1'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('client URL to 10.x.x.x is rejected', () => {
  const result = validateApiBaseUrl(
    'https://10.0.0.1/v1',
    clientOpts('10.0.0.1'),
  )
  assertEquals(result.valid, false)
})

Deno.test('client URL to 192.168.x.x is rejected', () => {
  const result = validateApiBaseUrl(
    'https://192.168.1.1/v1',
    clientOpts('192.168.1.1'),
  )
  assertEquals(result.valid, false)
})

Deno.test('client URL to 169.254.x.x (AWS IMDS) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://169.254.169.254/latest/meta-data/',
    clientOpts('169.254.169.254'),
  )
  assertEquals(result.valid, false)
})

Deno.test('client URL to 172.16.x.x is rejected', () => {
  const result = validateApiBaseUrl(
    'https://172.16.0.1/v1',
    clientOpts('172.16.0.1'),
  )
  assertEquals(result.valid, false)
})

Deno.test('client URL to 172.31.x.x is rejected', () => {
  const result = validateApiBaseUrl(
    'https://172.31.0.1/v1',
    clientOpts('172.31.0.1'),
  )
  assertEquals(result.valid, false)
})

Deno.test('client URL to 172.32.x.x is NOT rejected (outside private range)', () => {
  const result = validateApiBaseUrl(
    'https://172.32.0.1/v1',
    clientOpts('172.32.0.1'),
  )
  assertEquals(result.valid, true)
})

Deno.test('env-var URL to private IP is rejected', () => {
  const result = validateApiBaseUrl(
    'https://10.0.0.1/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to 169.254.169.254 (AWS IMDS) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://169.254.169.254/latest/meta-data/',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to localhost is rejected', () => {
  const result = validateApiBaseUrl(
    'https://localhost/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to .internal TLD is rejected', () => {
  const result = validateApiBaseUrl(
    'https://db.internal/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to .local TLD is rejected', () => {
  const result = validateApiBaseUrl(
    'https://mdns.local/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: invalid URL formats
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('empty string is rejected as invalid URL', () => {
  const result = validateApiBaseUrl('', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error, 'Invalid URL format')
})

Deno.test('non-URL string is rejected', () => {
  const result = validateApiBaseUrl('not-a-url', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error, 'Invalid URL format')
})

Deno.test('URL with no protocol is rejected', () => {
  const result = validateApiBaseUrl('api.example.com/v1', envOpts())
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: env-var fallback (no allowlist, but HTTPS + private-IP checked)
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('env-var URL with valid HTTPS public host passes', () => {
  const result = validateApiBaseUrl(
    'https://api.ourwhatsapp.example.com/v1',
    envOpts(),
  )
  assertEquals(result.valid, true)
})

Deno.test('env-var URL with valid HTTPS and path passes', () => {
  const result = validateApiBaseUrl(
    'https://api.wa.aderalabs.tech/v1/connect',
    envOpts(),
  )
  assertEquals(result.valid, true)
})

Deno.test('env-var URL with port passes if HTTPS and public', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com:8443/v1',
    envOpts(),
  )
  assertEquals(result.valid, true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv6 edge cases
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL to ::1 (IPv6 loopback) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[::1]/v1',
    clientOpts('::1'),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to [::1] (IPv6 loopback) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[::1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to fe80:: (IPv6 link-local) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[fe80::1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv6 unique-local addresses (fc00::/7) — NEW
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL to fc00::1 (IPv6 ULA) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[fc00::1]/v1',
    clientOpts('fc00::1'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to fc00::1 (IPv6 ULA) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[fc00::1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to fd00::1 (IPv6 ULA fd prefix) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[fd00::1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to full fd12:3456:789a::1 (IPv6 ULA) is rejected', () => {
  const result = validateApiBaseUrl(
    'https://[fd12:3456:789a::1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv4 0.0.0.0/8 full range — NEW
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('client URL to 0.0.0.1 is rejected (0.0.0.0/8 range)', () => {
  const result = validateApiBaseUrl(
    'https://0.0.0.1/v1',
    clientOpts('0.0.0.1'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to 0.0.0.0 is rejected', () => {
  const result = validateApiBaseUrl(
    'https://0.0.0.0/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to 0.1.2.3 is rejected (0.0.0.0/8 range)', () => {
  const result = validateApiBaseUrl(
    'https://0.1.2.3/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv4-mapped IPv6 (mixed notation) — NEW
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('env-var URL to [::ffff:10.0.0.1] is rejected (mapped private IPv4)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:10.0.0.1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to [::ffff:127.0.0.1] is rejected (mapped loopback)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:127.0.0.1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to [::ffff:192.168.1.1] is rejected (mapped private 192.168)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:192.168.1.1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to [::ffff:0.0.0.0] is rejected (mapped 0.0.0.0/8)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:0.0.0.0]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

Deno.test('env-var URL to [::ffff:8.8.8.8] is NOT rejected (mapped public IPv4)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:8.8.8.8]/v1',
    envOpts(),
  )
  assertEquals(result.valid, true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv4-mapped IPv6 (hex notation) — NEW
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('env-var URL to [::ffff:0a00:0001] is rejected (hex for 10.0.0.1)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:0a00:0001]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to [::ffff:a00:1] is rejected (compressed hex for 10.0.0.1)', () => {
  const result = validateApiBaseUrl(
    'https://[::ffff:a00:1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv4-compatible IPv6 (deprecated bypass vector) — NEW
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('env-var URL to [::10.0.0.1] is rejected (IPv4-compatible private)', () => {
  const result = validateApiBaseUrl(
    'https://[::10.0.0.1]/v1',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('env-var URL to [::8.8.8.8] is NOT rejected (IPv4-compatible public)', () => {
  const result = validateApiBaseUrl(
    'https://[::8.8.8.8]/v1',
    envOpts(),
  )
  assertEquals(result.valid, true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: IPv6 bracket normalization regression — NEW
//
// The WHATWG URL spec and V8/Deno include square brackets in the hostname
// property for IPv6 addresses (e.g. "[::1]"). Without stripping brackets,
// all prefix-based IPv6 checks fail because the hostname starts with "["
// instead of the address prefix. These tests use actual bracketed URL
// inputs to verify the normalization works correctly.
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('regression: https://[::1]/ is rejected (bracket loopback)', () => {
  const result = validateApiBaseUrl('https://[::1]/', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('regression: https://[fe80::1]/ is rejected (bracket link-local)', () => {
  const result = validateApiBaseUrl('https://[fe80::1]/', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('regression: https://[fd00::1]/ is rejected (bracket ULA)', () => {
  const result = validateApiBaseUrl('https://[fd00::1]/', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('regression: https://[::ffff:10.0.0.1]/ is rejected (bracket mapped private)', () => {
  // V8/Deno normalizes this to "[::ffff:a00:1]" — brackets + hex notation.
  // The validator must strip brackets AND parse hex to catch the embedded 10.0.0.1.
  const result = validateApiBaseUrl('https://[::ffff:10.0.0.1]/', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('regression: https://[::10.0.0.1]/ is rejected (bracket IPv4-compatible private)', () => {
  // V8/Deno normalizes this to "[::a00:1]" — brackets + hex notation.
  // The validator must strip brackets AND parse hex in the IPv4-compatible block.
  const result = validateApiBaseUrl('https://[::10.0.0.1]/', envOpts())
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

Deno.test('regression: bracket-normalized public IPv6 is NOT rejected', () => {
  // Cloudflare DNS public IPv6 — bracket stripping must not cause false positives.
  const result = validateApiBaseUrl('https://[2606:4700:4700::1111]/v1', envOpts())
  assertEquals(result.valid, true)
})

Deno.test('regression: bracket-normalized public IPv4-mapped IPv6 is NOT rejected', () => {
  // ::ffff:8.8.8.8 normalizes to ::ffff:808:808 (hex). After bracket stripping
  // and hex parsing, the embedded 8.8.8.8 is public and should pass.
  const result = validateApiBaseUrl('https://[::ffff:8.8.8.8]/v1', envOpts())
  assertEquals(result.valid, true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: wildcard hostname allowlist correctness — NEW
//
// *.example.com matches any subdomain (one or more levels) of example.com.
// The suffix ".example.com" (with leading dot) provides the dot-boundary
// anchor: "notexample.com" ends with "texample.com", not ".example.com",
// so the boundary is secure without needing a single-level restriction.
//
// Verified: evil.notexample.com does NOT end with ".example.com" (the
// character at that boundary is 't', not '.') — no bypass exists.
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('wildcard: *.example.com rejects https://notexample.com/', () => {
  const result = validateApiBaseUrl(
    'https://notexample.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('not in the allowed list'), true)
})

Deno.test('wildcard: *.example.com accepts https://api.example.com/', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('wildcard: *.example.com rejects evil.notexample.com (no dot boundary)', () => {
  // 'evil.notexample.com' ends with 'texample.com', NOT '.example.com'.
  // The leading dot in the suffix is the boundary anchor — no bypass.
  const result = validateApiBaseUrl(
    'https://evil.notexample.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('not in the allowed list'), true)
})

Deno.test('wildcard: *.example.com rejects bare example.com (no subdomain)', () => {
  const result = validateApiBaseUrl(
    'https://example.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, false)
})

Deno.test('wildcard: *.example.com accepts multi-level subdomain deep.api.example.com', () => {
  // endsWith('.example.com') allows multi-level subdomains — this is intentional.
  const result = validateApiBaseUrl(
    'https://deep.api.example.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('wildcard: *.example.com accepts exactly-one-level sub.example.com', () => {
  const result = validateApiBaseUrl(
    'https://sub.example.com/',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: FQDN trailing dot normalisation — NEW
//
// RFC 1034 allows a trailing dot in domain names (FQDN notation).
// Without stripping it, allowlist comparisons fail for valid URLs.
// This is a correctness issue, not a security bypass.
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('FQDN trailing dot: api.example.com. passes exact allowlist match', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com./',
    clientOpts('api.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('FQDN trailing dot: api.example.com. passes wildcard allowlist match', () => {
  const result = validateApiBaseUrl(
    'https://api.example.com./',
    clientOpts('*.example.com'),
  )
  assertEquals(result.valid, true)
})

Deno.test('FQDN trailing dot: private IP with trailing dot is still rejected', () => {
  // Trailing dot stripped: "10.0.0.1." → "10.0.0.1", still private.
  const result = validateApiBaseUrl(
    'https://10.0.0.1./',
    envOpts(),
  )
  assertEquals(result.valid, false)
  assertEquals(result.error?.includes('private or internal address'), true)
})

// ═══════════════════════════════════════════════════════════════════════════
// Test group: empty hostname edge case — UPDATED
//
// new URL('https:///path').hostname returns "path" in V8/Deno — not an
// empty string and not a parse failure. The three slashes are parsed as
// scheme + empty authority + path, but V8 then treats the path segment as
// the host. This means 'https:///path' is valid with hostname="path", which
// passes both private-IP and HTTPS checks (with envOpts, no allowlist).
//
// The empty-hostname guard (hostname.length === 0) exists as defense-in-depth
// for any future runtime that might return an empty string, but it is not
// reachable via standard URL inputs in V8/Deno.
// ═══════════════════════════════════════════════════════════════════════════

Deno.test('https:///path parses to hostname "path" and is treated as valid (env-var mode)', () => {
  // V8/Deno: new URL('https:///path').hostname === 'path'
  // Not an empty hostname — the URL parses successfully.
  // In env-var mode (no allowlist) it passes as a public hostname.
  const result = validateApiBaseUrl('https:///path', envOpts())
  assertEquals(result.valid, true)
})
