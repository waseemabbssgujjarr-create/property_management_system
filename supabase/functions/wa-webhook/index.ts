import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { OurWhatsAppApiClient } from '../_shared/our-wa-client.ts'

/**
 * wa-webhook Edge Function
 *
 * Receives all inbound webhooks from our WhatsApp API platform.
 *
 * Security:
 * - Verifies webhook signature using connection's webhook_secret
 * - Routes by connection_id (never trusts dealer_id from webhook body)
 * - Idempotent: duplicate event_id → safe no-op
 * - No secrets logged or returned
 *
 * Flow:
 *   Our WA API → POST /wa-webhook → verify sig → resolve dealer → store event → process
 */
serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const body = await req.text()
  let payload: unknown

  try {
    payload = JSON.parse(body)
  } catch {
    return new Response('Invalid JSON', { status: 400 })
  }

  // ── Extract connection_id from webhook (required for routing) ─────────
  const p = payload as Record<string, unknown>
  const connectionId = p['connection_id'] as string | undefined

  if (!connectionId) {
    console.error('wa-webhook: missing connection_id in payload')
    return new Response('OK', { status: 200 }) // Ack to prevent retries
  }

  // ── Resolve dealer from connection_id (trusted server-side lookup) ────
  const { data: connection } = await db
    .from('whatsapp_connections')
    .select('id, dealer_id, webhook_secret_encrypted, status')
    .eq('connection_id', connectionId)
    .eq('status', 'active')
    .maybeSingle()

  if (!connection) {
    console.warn(`wa-webhook: unknown or inactive connection_id: ${connectionId}`)
    return new Response('OK', { status: 200 }) // Ack, don't reveal non-existence
  }

  // ── Verify webhook signature ────────────────────────────────────────────
  const signatureHeader = req.headers.get('X-Signature') ??
                          req.headers.get('X-Wa-Signature') ??
                          req.headers.get('X-Hub-Signature-256') ?? ''

  // Decrypt webhook secret server-side
  const { data: creds } = await db.rpc('get_wa_credentials', {
    p_dealer_id:     connection.dealer_id,
    p_connection_id: connectionId,
  })

  if (!creds?.length) {
    console.error(`wa-webhook: could not decrypt credentials for ${connectionId}`)
    return new Response('OK', { status: 200 })
  }

  const { webhook_secret: webhookSecret } = creds[0]

  if (webhookSecret) {
    const waClient = new OurWhatsAppApiClient({
      baseUrl: creds[0].api_base_url,
      apiKey:  creds[0].api_key, // needed for client construction
    })

    const sigValid = await waClient.verifyWebhookSignature(body, signatureHeader, webhookSecret)
    if (!sigValid) {
      console.error(`wa-webhook: invalid signature for connection ${connectionId}`)
      return new Response('Forbidden', { status: 403 })
    }
  }

  // ── Parse events ─────────────────────────────────────────────────────────
  const waClient = new OurWhatsAppApiClient({
    baseUrl: creds[0].api_base_url,
    apiKey:  creds[0].api_key,
  })

  const { messages, statusUpdates } = waClient.parseWebhookPayload(payload)
  const dealerId = connection.dealer_id as string

  // ── Update last_webhook_at ────────────────────────────────────────────────
  await db.from('whatsapp_connections').update({
    last_webhook_at: new Date().toISOString(),
  }).eq('id', connection.id)

  // ── Process messages (idempotent) ─────────────────────────────────────────
  for (const msg of messages) {
    if (!msg.eventId) continue

    // Idempotency check: skip if already processed
    const { data: existing } = await db
      .from('wa_webhook_events')
      .select('id')
      .eq('dealer_id', dealerId)
      .eq('event_id', msg.eventId)
      .maybeSingle()

    if (existing) continue // Already processed

    // Store event (INSERT-ONLY)
    await db.from('wa_webhook_events').insert({
      dealer_id:     dealerId,
      connection_id: connectionId,
      event_id:      msg.eventId,
      event_type:    'message_in',
      raw_payload:   {
        from:         msg.fromPhone,
        message_type: msg.messageType,
        timestamp:    msg.timestamp,
        // NOTE: body included for text; media_url excluded for PII safety
        body:         msg.messageType === 'text' ? msg.body : null,
      },
      processed:     false,
    }).onConflict('dealer_id, event_id').ignore()

    // Store in wa_inbox for UI display
    const fromPhone = msg.fromPhone

    // Identify party by phone (best-effort)
    const { data: party } = await db
      .from('parties')
      .select('id, wa_opt_in')
      .eq('dealer_id', dealerId)
      .eq('phone', fromPhone)
      .maybeSingle()

    await db.from('wa_inbox').insert({
      dealer_id:  dealerId,
      party_id:   party?.id ?? null,
      direction:  'in',
      body:       msg.messageType === 'text' ? msg.body : null,
      audio_url:  msg.messageType === 'audio' ? msg.mediaUrl : null,
      wa_msg_id:  msg.eventId,
      status:     'received',
    }).onConflict('wa_msg_id').ignore()

    // STOP/UNSUBSCRIBE compliance
    if (msg.body) {
      const normalized = msg.body.trim().toUpperCase()
      if (['STOP', 'UNSUBSCRIBE', 'بند کرو'].includes(normalized) && party) {
        await db.from('parties').update({ wa_opt_in: false })
          .eq('id', party.id)
          .eq('dealer_id', dealerId)
      }
    }

    // Mark event processed
    await db.from('wa_webhook_events').update({
      processed:    true,
      processed_at: new Date().toISOString(),
    }).eq('dealer_id', dealerId).eq('event_id', msg.eventId)
  }

  // ── Process status updates ─────────────────────────────────────────────────
  for (const update of statusUpdates) {
    if (!update.eventId) continue

    // Idempotency
    const { data: existing } = await db
      .from('wa_webhook_events')
      .select('id')
      .eq('dealer_id', dealerId)
      .eq('event_id', update.eventId)
      .maybeSingle()

    if (existing) continue

    await db.from('wa_webhook_events').insert({
      dealer_id:     dealerId,
      connection_id: connectionId,
      event_id:      update.eventId,
      event_type:    'status_update',
      raw_payload:   {
        provider_msg_id: update.providerMsgId,
        status:          update.status,
        timestamp:       update.timestamp,
      },
      processed: false,
    }).onConflict('dealer_id, event_id').ignore()

    // Update outbound queue status
    await db.from('wa_outbound_queue').update({
      status:         update.status,
      delivered_at:   update.status === 'delivered' ? new Date().toISOString() : undefined,
      read_at:        update.status === 'read'       ? new Date().toISOString() : undefined,
    })
    .eq('dealer_id', dealerId)
    .eq('provider_msg_id', update.providerMsgId)

    await db.from('wa_webhook_events').update({
      processed: true,
      processed_at: new Date().toISOString(),
    }).eq('dealer_id', dealerId).eq('event_id', update.eventId)
  }

  return new Response('OK', { status: 200 })
})
