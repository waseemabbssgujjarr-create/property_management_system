import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * send-staff-invite Edge Function
 *
 * Notifies a new staff member that they have been added to a dealer's team.
 * Sends a WhatsApp message or SMS with a login prompt.
 *
 * Security:
 * - Validates caller is authenticated (JWT)
 * - Validates caller belongs to the same dealer_id
 * - Never sends invite for a different dealer's staff
 * - Phone comes from server DB — not from request body
 *
 * Message: "آپ کو [agency name] کی ٹیم میں شامل کیا گیا ہے۔
 *           منشی ایپ پر لاگ ان کریں: [store link]"
 */
serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    // Verify caller
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error } = await anonClient.auth.getUser()
    if (error || !user) return json({ error: 'Unauthorized' }, 401)

    const body = await req.json()
    const { user_id, dealer_id } = body

    if (!user_id || !dealer_id) {
      return json({ error: 'user_id and dealer_id required' }, 400)
    }

    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ── Security: verify caller belongs to this dealer ─────────────────────
    const { data: callerUser } = await db
      .from('users')
      .select('dealer_id, role')
      .eq('phone', user.phone ?? '')
      .maybeSingle()

    if (!callerUser || callerUser.dealer_id !== dealer_id) {
      return json({ error: 'Forbidden: dealer mismatch' }, 403)
    }

    if (!['owner', 'manager'].includes(callerUser.role)) {
      return json({ error: 'Forbidden: insufficient role' }, 403)
    }

    // ── Fetch invite target and dealer info ────────────────────────────────
    const { data: invitedUser } = await db
      .from('users')
      .select('phone, name, dealer_id')
      .eq('id', user_id)
      .eq('dealer_id', dealer_id) // enforce tenant scope
      .single()

    if (!invitedUser) {
      return json({ error: 'User not found' }, 404 )
    }

    const { data: dealer } = await db
      .from('dealers')
      .select('name')
      .eq('id', dealer_id)
      .single()

    const agencyName = dealer?.name ?? 'منشی'
    const phone      = invitedUser.phone
    const storeLink  = Deno.env.get('APP_STORE_LINK') ?? 'https://munshi.app'

    const message = `السلام علیکم ${invitedUser.name}! آپ کو ${agencyName} کی ٹیم میں شامل کیا گیا ہے۔ منشی ایپ پر لاگ ان کریں: ${storeLink}`

    // ── Try sending via our WhatsApp API ────────────────────────────────────
    const waBaseUrl = Deno.env.get('WA_API_BASE_URL')
    const waApiKey  = Deno.env.get('WA_API_KEY')

    if (waBaseUrl && waApiKey) {
      try {
        await fetch(`${waBaseUrl}/messages/send`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${waApiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ to: phone, type: 'text', text: { body: message } }),
        })
      } catch (e) {
        console.error('send-staff-invite WA failed:', e instanceof Error ? e.message : e)
        // Fall through to SMS
      }
    }

    // ── SMS fallback ────────────────────────────────────────────────────────
    const smsApiUrl = Deno.env.get('LOCAL_SMS_API_URL')
    const smsApiKey = Deno.env.get('LOCAL_SMS_API_KEY')

    if (smsApiUrl && smsApiKey) {
      try {
        await fetch(smsApiUrl, {
          method: 'POST',
          headers: { 'X-API-Key': smsApiKey, 'Content-Type': 'application/json' },
          body: JSON.stringify({ to: phone, message }),
        })
      } catch (e) {
        console.error('send-staff-invite SMS failed:', e instanceof Error ? e.message : e)
      }
    }

    return json({ success: true })

  } catch (err) {
    console.error('send-staff-invite error:', err instanceof Error ? err.message : err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
