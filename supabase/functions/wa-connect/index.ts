import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OurWhatsAppApiClient } from '../_shared/our-wa-client.ts'

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
 */
serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    // Verify caller and extract JWT claims
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await anonClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
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

    const baseUrl = api_base_url || Deno.env.get('WA_API_BASE_URL') || ''
    if (!baseUrl) {
      return json({ error: 'api_base_url is required' }, 400)
    }

    // ── Validate connection against our WA API ─────────────────────────
    const waClient = new OurWhatsAppApiClient({
      baseUrl,
      apiKey: api_key,
    })

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
        p_dealer_id:      dealerId,
        p_connection_id:  connection_id,
        p_api_base_url:   baseUrl,
        p_api_key:        api_key,          // plaintext — encrypted inside DB function
        p_webhook_secret: webhook_secret,   // plaintext — encrypted inside DB function
        p_phone_number:   phone_number ?? validation.phoneNumber ?? null,
        p_display_name:   display_name ?? validation.displayName ?? null,
      }
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
        'display_name, status, last_health_check_at, created_at, updated_at'
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
