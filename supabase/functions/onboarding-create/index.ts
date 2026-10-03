import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * onboarding-create Edge Function
 *
 * Creates dealer + owner user in a single DB transaction.
 * Idempotent: same phone = returns existing record.
 *
 * Security:
 * - Uses service role for DB access (transaction requires elevated perms)
 * - Validates auth JWT before any write
 * - Phone from JWT auth.users — not trusted from body
 */
serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing authorization' }, 401)

    // Use anon client to verify the JWT
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: authError } = await anonClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    // Phone must come from verified auth, not the request body
    const authPhone = user.phone
    if (!authPhone) return json({ error: 'No phone on auth user' }, 400)

    const body = await req.json()
    const {
      agency_name,
      city,
      areas = [],
      team_size = 1,
    } = body

    if (!agency_name?.trim()) return json({ error: 'agency_name required' }, 400)
    if (!city?.trim())         return json({ error: 'city required' }, 400)

    // Service role client for actual DB writes
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ── Idempotency check ──────────────────────────────────────────────────
    const { data: existingUser } = await db
      .from('users')
      .select('id, dealer_id')
      .eq('phone', authPhone)
      .eq('role', 'owner')
      .maybeSingle()

    if (existingUser) {
      return json({
        dealer_id: existingUser.dealer_id,
        user_id: existingUser.id,
        is_new: false,
      }, 200)
    }

    // ── Atomic insert via RPC ──────────────────────────────────────────────
    const { data, error } = await db.rpc('create_dealer_and_owner', {
      p_phone:       authPhone,
      p_agency_name: agency_name.trim(),
      p_city:        city.trim(),
      p_areas:       areas.length > 0 ? areas : [city.trim()],
    })

    if (error) {
      console.error('onboarding-create error:', error)
      return json({ error: error.message }, 500)
    }

    return json({
      dealer_id: data.dealer_id,
      user_id:   data.user_id,
      is_new:    true,
    }, 200)

  } catch (err) {
    console.error('onboarding-create unhandled:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
