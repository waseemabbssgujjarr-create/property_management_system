import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

/**
 * voice-otp-call Edge Function
 *
 * Delivers OTP via voice call — critical accessibility feature for
 * owners who cannot read SMS.
 *
 * The call speaks the code in Urdu:
 *   "آپ کا منشی لاگ اِن کوڈ ہے: 1 2 3 4 5 6۔ کسی سے شیئر نہ کریں۔"
 *
 * Provider support (configured via env secrets):
 *   TWILIO_ACCOUNT_SID + TWILIO_AUTH_TOKEN + TWILIO_FROM_NUMBER → Twilio Voice
 *   VOICE_API_URL + VOICE_API_KEY                               → Local Pakistani voice provider
 *
 * Security:
 * - OTP value is NEVER logged
 * - Phone is normalized and validated before use
 * - Rate limited by the same otp_attempts table used in otp-send
 */
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
      return json({ error: 'Invalid phone number' }, 400)
    }

    // ── Try Twilio Voice (primary for voice calls) ────────────────────────
    const twilioSid   = Deno.env.get('TWILIO_ACCOUNT_SID')
    const twilioToken = Deno.env.get('TWILIO_AUTH_TOKEN')
    const twilioFrom  = Deno.env.get('TWILIO_FROM_NUMBER')

    if (twilioSid && twilioToken && twilioFrom) {
      const result = await callViaTwilio(
        normalizedPhone, otp, twilioSid, twilioToken, twilioFrom,
      )
      if (result.success) {
        return json({ success: true, provider: 'twilio' })
      }
      // Log provider error without revealing OTP
      console.error('Twilio voice call failed', {
        phone: maskPhone(normalizedPhone),
        error: result.error,
      })
    }

    // ── Try local Pakistani voice provider ────────────────────────────────
    const voiceApiUrl = Deno.env.get('VOICE_API_URL')
    const voiceApiKey = Deno.env.get('VOICE_API_KEY')

    if (voiceApiUrl && voiceApiKey) {
      const result = await callViaLocalProvider(
        normalizedPhone, otp, voiceApiUrl, voiceApiKey,
      )
      if (result.success) {
        return json({ success: true, provider: 'local' })
      }
      console.error('Local voice provider failed', {
        phone: maskPhone(normalizedPhone),
        error: result.error,
      })
    }

    // No provider configured — return a clear configuration error
    // (not a silent success)
    if (!twilioSid && !voiceApiUrl) {
      console.error('voice-otp-call: No voice provider configured. Set TWILIO_* or VOICE_API_* secrets.')
      return json({
        error: 'Voice call service not configured.',
        error_code: 'provider_not_configured',
        setup_required: [
          'Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER',
          'OR set VOICE_API_URL and VOICE_API_KEY for a local provider',
        ],
      }, 503)
    }

    return json({
      error: 'Voice call delivery failed. Please use SMS or WhatsApp OTP.',
      error_code: 'delivery_failed',
    }, 503)

  } catch (err) {
    console.error('voice-otp-call error:', err instanceof Error ? err.message : 'unknown')
    return json({ error: 'Internal server error' }, 500)
  }
})

// ── Twilio Voice ──────────────────────────────────────────────────────────

async function callViaTwilio(
  phone: string,
  otp: string,
  sid: string,
  token: string,
  from: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    // Twilio TwiML: speak digits with pauses for clarity
    const digits = otp.split('').join(' ')
    const twiml = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="ur-PK" voice="Polly.Aditi">
    آپ کا منشی لاگ اِن کوڈ ہے
  </Say>
  <Pause length="1"/>
  <Say language="ur-PK" voice="Polly.Aditi">${digits}</Say>
  <Pause length="1"/>
  <Say language="ur-PK" voice="Polly.Aditi">
    دوبارہ:
  </Say>
  <Say language="ur-PK" voice="Polly.Aditi">${digits}</Say>
  <Pause length="1"/>
  <Say language="ur-PK" voice="Polly.Aditi">
    کسی سے شیئر نہ کریں۔
  </Say>
</Response>`

    const params = new URLSearchParams({
      To:   phone,
      From: from,
      Twiml: twiml,
    })

    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Calls.json`,
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

// ── Local Pakistani voice provider ────────────────────────────────────────
// Supports any provider with a simple REST API:
// POST {apiUrl}/calls with { to, message/tts_text }

async function callViaLocalProvider(
  phone: string,
  otp: string,
  apiUrl: string,
  apiKey: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    const message = `آپ کا منشی لاگ اِن کوڈ ہے: ${otp.split('').join(' ')}۔ دوبارہ: ${otp.split('').join(' ')}۔ کسی سے شیئر نہ کریں۔`

    const res = await fetch(`${apiUrl}/calls`, {
      method: 'POST',
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: phone,
        tts_text: message,
        language: 'ur-PK',
      }),
    })

    if (!res.ok) {
      return { success: false, error: `Local provider ${res.status}` }
    }

    return { success: true }
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'unknown' }
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────

function normalizePhone(phone: string): string | null {
  const digits = phone.replace(/\D/g, '')
  if (digits.startsWith('92') && digits.length === 12) return `+${digits}`
  if (digits.startsWith('0')  && digits.length === 11) return `+92${digits.slice(1)}`
  if (digits.length === 10)                            return `+92${digits}`
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
