import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OurWhatsAppApiClient } from '../_shared/our-wa-client.ts'
import { validateApiBaseUrl } from './validate_url.ts'

/**
 * wa-connect Edge Function
 *
 * Validates and stores a WhatsApp connection for a dealer.
 *
 * Security:
 * - Caller JWT verified (must be owner or manager)
 * - dealer_id from JWT claims — not trusted from request body
 * - API key and webhook secret stored encrypted via store_wa_credentials()
 * - Credentials NEVER returned to caller after storage
 * - Connection validated against our WA API before storage
 * - api_base_url validated for SSRF: HTTPS + private-IP block (all URLs) +
 *   hostname allowlist (client-supplied URLs only)
 */

// ── HTTP handler ──────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    // Verify caller and extract JWT claims
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: { user }, error: authError } = await anonClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── Authorization: must be owner or manager ────────────────────────
    const { data: callerUser } = await db
      .from('users')
      .select('dealer_id, role')
      .eq('phone', user.phone ?? '')
      .maybeSingle()

    if (!callerUser) return json({ error: 'User not found' }, 404)
    if (!['owner', 'manager'].includes(callerUser.role)) {
      return json({ error: 'Forbidden: owner or manager required' }, 403)
    }

    const dealerId = callerUser.dealer_id as string

    // ── Parse request ──────────────────────────────────────────────────
    const body = await req.json()
    const {
      connection_id,
      api_key,
      webhook_secret,
      api_base_url,
      phone_number,
      display_name,
    } = body

    if (!connection_id || !api_key || !webhook_secret) {
      return json({ error: 'connection_id, api_key, and webhook_secret are required' }, 400)
    }

    // ── Resolve and validate api_base_url (SSRF protection) ────────────
    //
    // The resolved baseUrl is validated REGARDLESS of source:
    //   - Client-supplied URL: HTTPS + private-IP block + hostname allowlist
    //   - Env-var fallback URL: HTTPS + private-IP block (no allowlist —
    //     the env var is operator-configured and trusted for hostname)
    //
    // The exact validated baseUrl string is passed to OurWhatsAppApiClient.
    // No re-resolution or normalization happens after validation.

    const clientUrl = typeof api_base_url === 'string' ? api_base_url.trim() : ''
    const envUrl = Deno.env.get('WA_API_BASE_URL') || ''
    const baseUrl = clientUrl || envUrl

    if (!baseUrl) {
      return json({ error: 'api_base_url is required' }, 400)
    }

    // Build allowlist config from env vars
    const allowedHosts = Deno.env.get('WA_API_ALLOWED_HOSTS') || ''
    let fallbackHost = ''
    if (envUrl) {
      try {
        fallbackHost = new URL(envUrl).hostname.toLowerCase()
      } catch {
        // WA_API_BASE_URL is malformed — fallback stays empty
      }
    }

    // Validate the resolved baseUrl.
    // enforceAllowlist is true for client-supplied URLs, false for env-var URLs.
    const urlValidation = validateApiBaseUrl(baseUrl, {
      enforceAllowlist: !!clientUrl,
      allowedHosts,
      fallbackHost,
    })
    if (!urlValidation.valid) {
      return json({ error: urlValidation.error ?? 'Invalid api_base_url' }, 400)
    }

    // The exact validated baseUrl is passed to OurWhatsAppApiClient — no
    // re-resolution or substitution after the validation boundary.
    const waClient = new OurWhatsAppApiClient({
      baseUrl,
      apiKey: api_key,
    })

    // ── Validate connection against our WA API ─────────────────────────
    const validation = await waClient.validateConnection(connection_id, api_key)
    if (!validation.valid) {
      return json({
        error: validation.errorMessage ?? 'Connection validation failed',
        error_code: 'invalid_connection',
      }, 422)
    }

    // ── Store credentials encrypted (service_role DB function) ─────────
    const { data: connectionId, error: storeError } = await db.rpc(
      'store_wa_credentials',
      {
        p_dealer_id: dealerId,
        p_connection_id: connection_id,
        p_api_base_url: baseUrl,
        p_api_key: api_key, // plaintext — encrypted inside DB function
        p_webhook_secret: webhook_secret, // plaintext — encrypted inside DB function
        p_phone_number: phone_number ?? validation.phoneNumber ?? null,
        p_display_name: display_name ?? validation.displayName ?? null,
      },
    )

    if (storeError) {
      console.error('wa-connect: store_wa_credentials error:', storeError.message)
      return json({ error: 'Failed to store credentials' }, 500)
    }

    // ── Return safe metadata only (NO credentials) ──────────────────────
    const { data: connection } = await db
      .from('whatsapp_connections')
      .select(
        'id, dealer_id, connection_id, api_base_url, phone_number, ' +
        'display_name, status, last_health_check_at, created_at, updated_at',
      )
      .eq('id', connectionId)
      .single()

    return json({ success: true, connection })
  } catch (err) {
    console.error('wa-connect error:', err instanceof Error ? err.message : err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
