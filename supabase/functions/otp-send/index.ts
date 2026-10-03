import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * otp-send Edge Function
 *
 * Sends OTP via WhatsApp (primary), SMS (fallback).
 *
 * Rate limiting:
 * - Max 3 OTP requests per phone per 15 minutes
 * - OTPs expire in 10 minutes (Supabase Auth handles expiry)
 *
 * Security:
 * - OTP value is NEVER logged
 * - Phone is normalized to E.164 before any operation
 * - Provider errors are mapped to safe user-facing messages
 */

const RATE_LIMIT_WINDOW_SECS = 15 * 60
const RATE_LIMIT_MAX         = 3

serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const { phone, otp } = await req.json()

    if (!phone || !otp) {
      return json({ error: 'phone and otp required' }, 400)
    }

    const normalizedPhone = normalizePhone(phone)
    if (!normalizedPhone) {
      return json({ error: 'Invalid phone number format' }, 400)
    }

    // ── Rate limit check ──────────────────────────────────────────────────
    const rateLimitOk = await checkRateLimit(normalizedPhone)
    if (!rateLimitOk) {
      return json({
        error: 'Too many OTP requests. Please wait before trying again.',
        error_code: 'rate_limited',
      }, 429)
    }

    // ── Try WhatsApp first ────────────────────────────────────────────────
    const waResult = await sendViaWhatsApp(normalizedPhone, otp)

    if (waResult.success) {
      return json({ success: true, channel: 'whatsapp' })
    }

    // ── SMS fallback ──────────────────────────────────────────────────────
    const smsResult = await sendViaSms(normalizedPhone, otp)

    if (smsResult.success) {
      return json({ success: true, channel: 'sms' })
    }

    // Both failed
    console.error('OTP delivery failed on all channels', {
      phone: maskPhone(normalizedPhone),
      wa_error: waResult.error,
      sms_error: smsResult.error,
    })

    return json({
      error: 'OTP delivery failed. Please try again.',
      error_code: 'delivery_failed',
    }, 503)

  } catch (err) {
    console.error('otp-send unhandled error:', err instanceof Error ? err.message : 'unknown')
    return json({ error: 'Internal server error' }, 500)
  }
})

// ── WhatsApp delivery ─────────────────────────────────────────────────────

async function sendViaWhatsApp(
  phone: string,
  otp: string,
): Promise<{ success: boolean; error?: string }> {
  const waToken       = Deno.env.get('META_WA_TOKEN')
  const phoneNumberId = Deno.env.get('META_PHONE_NUMBER_ID')

  // Meta WA approach (direct Meta API)
  if (waToken && phoneNumberId) {
    return sendViaMetaWhatsApp(phone, otp, waToken, phoneNumberId)
  }

  // Our own WhatsApp API approach
  const ourWaBaseUrl = Deno.env.get('WA_API_BASE_URL')
  const ourWaApiKey  = Deno.env.get('WA_API_KEY')

  if (ourWaBaseUrl && ourWaApiKey) {
    return sendViaOurWhatsAppApi(phone, otp, ourWaBaseUrl, ourWaApiKey)
  }

  return { success: false, error: 'No WhatsApp provider configured' }
}

async function sendViaMetaWhatsApp(
  phone: string,
  otp: string,
  token: string,
  phoneNumberId: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: phone,
          type: 'template',
          template: {
            name: 'otp_login',
            language: { code: 'ur' },
            components: [{
              type: 'body',
              parameters: [{ type: 'text', text: otp }],
            }],
          },
        }),
      },
    )

    if (!res.ok) {
      const body = await res.text()
      return { success: false, error: `Meta API ${res.status}: ${body.substring(0, 100)}` }
    }

    return { success: true }
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'unknown' }
  }
}

async function sendViaOurWhatsAppApi(
  phone: string,
  otp: string,
  baseUrl: string,
  apiKey: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    const message = `آپ کا منشی لاگ اِن کوڈ ہے: ${otp}۔ کسی سے شیئر نہ کریں۔`

    const res = await fetch(`${baseUrl}/messages/send`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: phone,
        type: 'text',
        text: { body: message },
      }),
    })

    if (!res.ok) {
      return { success: false, error: `WA API ${res.status}` }
    }

    return { success: true }
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'unknown' }
  }
}

// ── SMS delivery ──────────────────────────────────────────────────────────

async function sendViaSms(
  phone: string,
  otp: string,
): Promise<{ success: boolean; error?: string }> {
  // Provider selection: Twilio (international) or local Pakistani SMS
  const twilioSid   = Deno.env.get('TWILIO_ACCOUNT_SID')
  const twilioToken = Deno.env.get('TWILIO_AUTH_TOKEN')
  const twilioFrom  = Deno.env.get('TWILIO_FROM_NUMBER')

  if (twilioSid && twilioToken && twilioFrom) {
    return sendViaTwilioSms(phone, otp, twilioSid, twilioToken, twilioFrom)
  }

  // Pakistani local SMS (e.g., Jazz/Telenor business SMS API)
  const localSmsUrl = Deno.env.get('LOCAL_SMS_API_URL')
  const localSmsKey = Deno.env.get('LOCAL_SMS_API_KEY')

  if (localSmsUrl && localSmsKey) {
    return sendViaLocalSms(phone, otp, localSmsUrl, localSmsKey)
  }

  return { success: false, error: 'No SMS provider configured' }
}

async function sendViaTwilioSms(
  phone: string,
  otp: string,
  sid: string,
  token: string,
  from: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    const body = encodeURIComponent(`Munshi login code: ${otp}. Valid for 10 minutes.`)
    const params = new URLSearchParams({
      To: phone,
      From: from,
      Body: `Munshi login code: ${otp}. Valid for 10 minutes.`,
    })

    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
      },
    )

    if (!res.ok) {
      const data = await res.json()
      return { success: false, error: `Twilio ${res.status}: ${data?.message}` }
    }

    return { success: true }
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'unknown' }
  }
}

async function sendViaLocalSms(
  phone: string,
  otp: string,
  apiUrl: string,
  apiKey: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    // Generic Pakistani SMS gateway contract
    // (Telenor, Jazz, Zong business SMS APIs follow similar patterns)
    const res = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: phone,
        message: `Munshi: آپ کا لاگ اِن کوڈ ${otp} ہے۔ 10 منٹ میں expire ہوگا۔`,
      }),
    })

    if (!res.ok) {
      return { success: false, error: `Local SMS ${res.status}` }
    }

    return { success: true }
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'unknown' }
  }
}

// ── Rate limiting ─────────────────────────────────────────────────────────
// Uses Supabase's service role to read/write a simple rate limit table.

async function checkRateLimit(phone: string): Promise<boolean> {
  try {
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_SECS * 1000).toISOString()

    const { count } = await db
      .from('otp_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('phone', phone)
      .gte('attempted_at', windowStart)

    if ((count ?? 0) >= RATE_LIMIT_MAX) return false

    // Log this attempt (fire-and-forget)
    db.from('otp_attempts')
      .insert({ phone, attempted_at: new Date().toISOString() })
      .then(() => {})

    return true
  } catch {
    // If rate limit check fails, allow the request (fail open for auth)
    return true
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────

function normalizePhone(phone: string): string | null {
  const digits = phone.replace(/\D/g, '')
  if (digits.startsWith('92') && digits.length === 12) return `+${digits}`
  if (digits.startsWith('0') && digits.length === 11)   return `+92${digits.slice(1)}`
  if (digits.length === 10)                              return `+92${digits}`
  if (digits.startsWith('92') && digits.length === 12)  return `+${digits}`
  return null
}

function maskPhone(phone: string): string {
  if (phone.length < 6) return '****'
  return `${phone.slice(0, 4)}****${phone.slice(-3)}`
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
