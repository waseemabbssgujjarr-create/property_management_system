/**
 * OurWhatsAppApiClient — typed adapter for our own WhatsApp API platform.
 *
 * Architecture:
 *   Munshi Edge Functions → OurWhatsAppApiClient → Our WA API → WhatsApp
 *
 * This is the SINGLE integration boundary. All WA API calls go through here.
 * No other Edge Function makes direct HTTP calls to the WA API.
 *
 * The actual API contract (endpoints, request/response shapes) must be
 * configured to match the real API spec. The adapter is designed to be
 * updated when the API evolves without touching business-logic functions.
 *
 * Configuration via env:
 *   WA_API_BASE_URL       — base URL of our WA API (no trailing slash)
 *   WA_API_KEY            — global platform API key (for platform-level ops)
 *   WA_API_TIMEOUT_MS     — request timeout in ms (default: 10000)
 */

export interface WaApiConfig {
  baseUrl:    string
  apiKey:     string
  timeoutMs?: number
}

export interface WaSendTextResult {
  success:       boolean
  providerMsgId: string | null
  error?:        string
  errorCode?:    string
}

export interface WaConnectionInfo {
  connectionId:  string
  phoneNumber:   string | null
  displayName:   string | null
  status:        'active' | 'inactive' | 'error'
  errorMessage?: string
}

export interface WaHealthCheckResult {
  healthy:      boolean
  connectionId: string
  phoneNumber?: string
  displayName?: string
  errorMessage?: string
}

export interface WaValidateConnectionResult {
  valid:        boolean
  connectionId: string
  phoneNumber?: string
  displayName?: string
  errorMessage?: string
}

export interface WaInboundMessage {
  eventId:      string     // provider's unique event ID (for idempotency)
  connectionId: string
  fromPhone:    string
  toPhone:      string
  messageType:  'text' | 'audio' | 'image' | 'document' | 'other'
  body?:        string
  mediaUrl?:    string
  timestamp:    string    // ISO 8601
}

export interface WaStatusUpdate {
  eventId:       string
  connectionId:  string
  providerMsgId: string
  status:        'sent' | 'delivered' | 'read' | 'failed'
  timestamp:     string
}

// ── Client class ────────────────────────────────────────────────────────────

export class OurWhatsAppApiClient {
  private readonly baseUrl:   string
  private readonly apiKey:    string
  private readonly timeoutMs: number

  constructor(config: WaApiConfig) {
    this.baseUrl   = config.baseUrl.replace(/\/$/, '') // strip trailing slash
    this.apiKey    = config.apiKey
    this.timeoutMs = config.timeoutMs ?? 10_000
  }

  // ── Connection management ──────────────────────────────────────────────

  /**
   * Validate a connection ID and retrieve its metadata.
   * Called when the dealer first configures their WA connection.
   */
  async validateConnection(
    connectionId: string,
    connectionApiKey: string,
  ): Promise<WaValidateConnectionResult> {
    try {
      const res = await this.request(
        'GET',
        `/connections/${encodeURIComponent(connectionId)}/info`,
        null,
        connectionApiKey,
      )

      if (!res.ok) {
        return {
          valid: false,
          connectionId,
          errorMessage: `API ${res.status}: ${await this.safeText(res)}`,
        }
      }

      const data = await res.json() as Record<string, unknown>
      return {
        valid:        true,
        connectionId,
        phoneNumber:  data['phone_number']  as string | undefined,
        displayName:  data['display_name']  as string | undefined,
      }
    } catch (e) {
      return {
        valid: false,
        connectionId,
        errorMessage: e instanceof Error ? e.message : 'Network error',
      }
    }
  }

  /**
   * Health check for an active connection.
   * Called periodically and on-demand.
   */
  async healthCheck(
    connectionId: string,
    connectionApiKey: string,
  ): Promise<WaHealthCheckResult> {
    try {
      const res = await this.request(
        'GET',
        `/connections/${encodeURIComponent(connectionId)}/health`,
        null,
        connectionApiKey,
      )

      if (!res.ok) {
        return { healthy: false, connectionId, errorMessage: `API ${res.status}` }
      }

      const data = await res.json() as Record<string, unknown>
      return {
        healthy:      data['healthy'] as boolean ?? false,
        connectionId,
        phoneNumber:  data['phone_number'] as string | undefined,
        displayName:  data['display_name'] as string | undefined,
      }
    } catch (e) {
      return {
        healthy: false,
        connectionId,
        errorMessage: e instanceof Error ? e.message : 'Network error',
      }
    }
  }

  // ── Sending messages ───────────────────────────────────────────────────

  /**
   * Send a text message.
   * Returns provider message ID for delivery tracking.
   */
  async sendText(
    connectionId:    string,
    connectionApiKey: string,
    toPhone:         string,
    body:            string,
    idempotencyKey:  string,
  ): Promise<WaSendTextResult> {
    try {
      const res = await this.request(
        'POST',
        `/connections/${encodeURIComponent(connectionId)}/messages/send`,
        {
          to:               toPhone,
          type:             'text',
          text:             { body },
          idempotency_key:  idempotencyKey,
        },
        connectionApiKey,
      )

      if (!res.ok) {
        const errText = await this.safeText(res)
        return {
          success:       false,
          providerMsgId: null,
          error:         `API ${res.status}: ${errText.substring(0, 200)}`,
          errorCode:     res.status === 429 ? 'rate_limited'
                       : res.status === 401 ? 'auth_failed'
                       : res.status === 403 ? 'forbidden'
                       : 'api_error',
        }
      }

      const data = await res.json() as Record<string, unknown>
      return {
        success:       true,
        providerMsgId: data['message_id'] as string ?? null,
      }
    } catch (e) {
      return {
        success:       false,
        providerMsgId: null,
        error:         e instanceof Error ? e.message : 'Network error',
        errorCode:     'network_error',
      }
    }
  }

  /**
   * Send a template message (pre-approved marketing/utility templates).
   */
  async sendTemplate(
    connectionId:     string,
    connectionApiKey: string,
    toPhone:          string,
    templateName:     string,
    templateVars:     Record<string, string>,
    idempotencyKey:   string,
  ): Promise<WaSendTextResult> {
    try {
      const res = await this.request(
        'POST',
        `/connections/${encodeURIComponent(connectionId)}/messages/send`,
        {
          to:               toPhone,
          type:             'template',
          template: {
            name:      templateName,
            language:  { code: 'ur' },
            variables: templateVars,
          },
          idempotency_key: idempotencyKey,
        },
        connectionApiKey,
      )

      if (!res.ok) {
        return {
          success: false,
          providerMsgId: null,
          error: `Template API ${res.status}`,
        }
      }

      const data = await res.json() as Record<string, unknown>
      return {
        success:       true,
        providerMsgId: data['message_id'] as string ?? null,
      }
    } catch (e) {
      return {
        success: false,
        providerMsgId: null,
        error: e instanceof Error ? e.message : 'Network error',
      }
    }
  }

  // ── Webhook signature verification ────────────────────────────────────

  /**
   * Verify webhook signature from our WA API.
   * Returns true if the request is authentic.
   *
   * The exact signature algorithm depends on our WA API's specification.
   * Supported: HMAC-SHA256 in X-Signature header (common pattern).
   * Update this method if our API uses a different scheme.
   */
  async verifyWebhookSignature(
    payload:       string,
    signatureHeader: string,
    webhookSecret: string,
  ): Promise<boolean> {
    if (!signatureHeader) return false

    try {
      // HMAC-SHA256 verification (standard approach)
      const encoder = new TextEncoder()
      const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(webhookSecret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['verify'],
      )

      // Support both "sha256=<hex>" and raw hex formats
      const hexSig = signatureHeader.replace(/^sha256=/i, '')
      const sigBytes = hexToBytes(hexSig)

      const isValid = await crypto.subtle.verify(
        'HMAC',
        key,
        sigBytes.buffer as ArrayBuffer,
        encoder.encode(payload),
      )

      return isValid
    } catch {
      return false
    }
  }

  /**
   * Parse inbound webhook payload into normalized events.
   * Returns messages and status updates separately.
   * Unknown event types are safely ignored.
   */
  parseWebhookPayload(payload: unknown): {
    messages: WaInboundMessage[]
    statusUpdates: WaStatusUpdate[]
  } {
    const messages:      WaInboundMessage[] = []
    const statusUpdates: WaStatusUpdate[]   = []

    if (!payload || typeof payload !== 'object') {
      return { messages, statusUpdates }
    }

    const p = payload as Record<string, unknown>

    // Our WA API webhook format — adapt to match actual spec
    const events = Array.isArray(p['events']) ? p['events'] as unknown[] : []

    for (const event of events) {
      if (!event || typeof event !== 'object') continue
      const e = event as Record<string, unknown>

      if (e['type'] === 'message') {
        messages.push({
          eventId:      e['event_id']     as string ?? '',
          connectionId: e['connection_id'] as string ?? '',
          fromPhone:    e['from']          as string ?? '',
          toPhone:      e['to']            as string ?? '',
          messageType:  (e['message_type'] as WaInboundMessage['messageType']) ?? 'other',
          body:         e['body']          as string | undefined,
          mediaUrl:     e['media_url']     as string | undefined,
          timestamp:    e['timestamp']     as string ?? new Date().toISOString(),
        })
      } else if (e['type'] === 'status') {
        statusUpdates.push({
          eventId:       e['event_id']      as string ?? '',
          connectionId:  e['connection_id'] as string ?? '',
          providerMsgId: e['message_id']    as string ?? '',
          status:        (e['status']       as WaStatusUpdate['status']) ?? 'sent',
          timestamp:     e['timestamp']     as string ?? new Date().toISOString(),
        })
      }
    }

    return { messages, statusUpdates }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  private async request(
    method:     string,
    path:       string,
    body:       unknown | null,
    apiKey:     string,
  ): Promise<Response> {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.timeoutMs)

    try {
      return await fetch(`${this.baseUrl}${path}`, {
        method,
        headers: {
          Authorization:  `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent':   'Munshi/1.0',
        },
        body:     body !== null ? JSON.stringify(body) : undefined,
        signal:   controller.signal,
        // Prevent redirect-based SSRF: if the WA API server returns a
        // redirect (3xx), throw instead of following it to an unexpected
        // destination. A well-behaved API should not redirect auth'd requests.
        redirect: 'error',
      })
    } finally {
      clearTimeout(timer)
    }
  }

  private async safeText(res: Response): Promise<string> {
    try { return await res.text() } catch { return '' }
  }
}

// ── Utilities ────────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  }
  return bytes
}

/**
 * Build a client from Edge Function environment variables.
 * Uses connection-specific API key for per-dealer isolation.
 */
export function buildClientFromEnv(): OurWhatsAppApiClient {
  const baseUrl = Deno.env.get('WA_API_BASE_URL')
  const apiKey  = Deno.env.get('WA_API_KEY')

  if (!baseUrl || !apiKey) {
    throw new Error(
      'WA_API_BASE_URL and WA_API_KEY must be set in Edge Function secrets'
    )
  }

  return new OurWhatsAppApiClient({ baseUrl, apiKey })
}
