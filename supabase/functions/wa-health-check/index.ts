import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OurWhatsAppApiClient } from '../_shared/our-wa-client.ts'

/**
 * wa-health-check Edge Function
 *
 * Tests whether a WhatsApp connection is healthy.
 * Called on-demand (dealer presses "Test Connection") and
 * periodically by the reminder-runner cron.
 *
 * Security:
 * - Caller JWT verified
 * - dealer_id from JWT — not request body
 * - Credentials fetched server-side via get_wa_credentials()
 * - API key never returned to caller
 */
serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

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

    // Get dealer_id from JWT claims via users table
    const { data: callerUser } = await db
      .from('users')
      .select('dealer_id')
      .eq('phone', user.phone ?? '')
      .maybeSingle()

    if (!callerUser) return json({ error: 'User not found' }, 404)
    const dealerId = callerUser.dealer_id as string

    const body = await req.json()
    const { connection_id } = body

    if (!connection_id) return json({ error: 'connection_id required' }, 400)

    // ── Retrieve credentials server-side (service_role only) ──────────
    const { data: creds, error: credError } = await db.rpc(
      'get_wa_credentials',
      { p_dealer_id: dealerId, p_connection_id: connection_id }
    )

    if (credError || !creds || creds.length === 0) {
      return json({ error: 'Connection not found or not active' }, 404)
    }

    const { api_base_url, api_key, phone_number, display_name } = creds[0]

    // ── Call our WA API to check health ────────────────────────────────
    const waClient = new OurWhatsAppApiClient({
      baseUrl: api_base_url,
      apiKey:  api_key,      // decrypted server-side, never returned
    })

    const result = await waClient.healthCheck(connection_id, api_key)

    // ── Update last_health_check_at in DB ──────────────────────────────
    await db
      .from('whatsapp_connections')
      .update({
        last_health_check_at: new Date().toISOString(),
        status:         result.healthy ? 'active' : 'error',
        error_message:  result.healthy ? null : result.errorMessage,
        phone_number:   result.phoneNumber ?? phone_number,
        display_name:   result.displayName ?? display_name,
      })
      .eq('dealer_id', dealerId)
      .eq('connection_id', connection_id)

    return json({
      healthy:      result.healthy,
      connection_id: result.connectionId,
      phone_number:  result.phoneNumber ?? phone_number,
      display_name:  result.displayName ?? display_name,
      error:         result.errorMessage,
    })

  } catch (err) {
    console.error('wa-health-check error:', err instanceof Error ? err.message : err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
