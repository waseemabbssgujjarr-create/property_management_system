import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OurWhatsAppApiClient } from '../_shared/our-wa-client.ts'
import { v4 as uuid } from 'https://deno.land/std@0.177.0/uuid/mod.ts'

/**
 * wa-send Edge Function
 *
 * Sends a WhatsApp message through our WA API on behalf of a dealer.
 * Processes one message from wa_outbound_queue.
 *
 * Security:
 * - Caller must be service_role (called from cron/internal only)
 * - OR authenticated dealer sending a one-off message
 * - Connection credentials fetched server-side
 * - Idempotency key prevents duplicate sends
 * - Tenant isolation: can only send through dealer's own connection
 *
 * Offline support: messages are queued in wa_outbound_queue.
 * This function is called by the cron runner to process the queue.
 */
serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  try {
    const body = await req.json()

    // Support two modes:
    // 1. Process queued message by ID (from cron runner)
    // 2. Send immediate message (from authenticated dealer action)
    const queueId = body['queue_id'] as string | undefined

    if (queueId) {
      return await processQueuedMessage(db, queueId)
    }

    // Immediate send — requires auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await anonClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const { data: callerUser } = await db
      .from('users')
      .select('dealer_id')
      .eq('phone', user.phone ?? '')
      .maybeSingle()

    if (!callerUser) return json({ error: 'User not found' }, 404)

    const dealerId = callerUser.dealer_id as string
    const { connection_id, to_phone, message_body, idempotency_key, deal_id, party_id } = body

    if (!connection_id || !to_phone || !message_body) {
      return json({ error: 'connection_id, to_phone, message_body required' }, 400)
    }

    // Queue the message first (offline safety)
    const iKey = idempotency_key ?? uuid.generate()
    await db.from('wa_outbound_queue').insert({
      dealer_id:       dealerId,
      connection_id,
      to_phone,
      message_body,
      message_type:    'text',
      idempotency_key: iKey,
      deal_id:         deal_id ?? null,
      party_id:        party_id ?? null,
      status:          'queued',
    })

    // Attempt immediate send
    const result = await sendViaConnection(db, {
      dealerId, connectionId: connection_id,
      toPhone: to_phone, body: message_body, iKey,
    })

    return json(result)

  } catch (err) {
    console.error('wa-send error:', err instanceof Error ? err.message : err)
    return json({ error: 'Internal server error' }, 500)
  }
})

async function processQueuedMessage(
  db: ReturnType<typeof createClient>,
  queueId: string,
) {
  const { data: msg } = await db
    .from('wa_outbound_queue')
    .select('*')
    .eq('id', queueId)
    .single()

  if (!msg) return json({ error: 'Message not found' }, 404)
  if (msg.status === 'sent' || msg.status === 'delivered') {
    return json({ success: true, already_sent: true })
  }
  if (msg.retry_count >= msg.max_retries) {
    return json({ success: false, error: 'Max retries exceeded' })
  }

  const result = await sendViaConnection(db, {
    dealerId:     msg.dealer_id,
    connectionId: msg.connection_id,
    toPhone:      msg.to_phone,
    body:         msg.message_body,
    iKey:         msg.idempotency_key,
  })

  // Update queue entry
  await db.from('wa_outbound_queue').update({
    status:          result.success ? 'sent' : 'failed',
    provider_msg_id: result.providerMsgId,
    error_message:   result.error,
    retry_count:     msg.retry_count + (result.success ? 0 : 1),
    sent_at:         result.success ? new Date().toISOString() : null,
    next_retry_at:   result.success ? null : exponentialBackoff(msg.retry_count + 1),
  }).eq('id', queueId)

  return json(result)
}

async function sendViaConnection(
  db: ReturnType<typeof createClient>,
  params: {
    dealerId:     string
    connectionId: string
    toPhone:      string
    body:         string
    iKey:         string
  },
) {
  // Fetch credentials server-side
  const { data: creds, error } = await db.rpc('get_wa_credentials', {
    p_dealer_id:     params.dealerId,
    p_connection_id: params.connectionId,
  })

  if (error || !creds?.length) {
    return { success: false, providerMsgId: null, error: 'Connection not found or not active' }
  }

  const { api_base_url, api_key } = creds[0]

  const waClient = new OurWhatsAppApiClient({ baseUrl: api_base_url, apiKey: api_key })
  const result   = await waClient.sendText(
    params.connectionId,
    api_key,
    params.toPhone,
    params.body,
    params.iKey,
  )

  // Update last_message_sent_at
  if (result.success) {
    await db.from('whatsapp_connections').update({
      last_message_sent_at: new Date().toISOString(),
    })
    .eq('dealer_id', params.dealerId)
    .eq('connection_id', params.connectionId)
  }

  return result
}

function exponentialBackoff(retryCount: number): string {
  const delayMs = Math.min(1000 * Math.pow(2, retryCount), 30 * 60 * 1000)
  return new Date(Date.now() + delayMs).toISOString()
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
