# WHATSAPP INTEGRATION — Munshi
**Version:** 1.0 | **Date:** 2026-10-02

---

## Architecture

Munshi does NOT build its own WhatsApp provider infrastructure. It integrates with our existing WhatsApp API platform as a client.

```
┌─────────────────────────────────┐
│     MUNSHI Flutter App          │
│     (dealer's phone)            │
└───────────────┬─────────────────┘
                │ HTTPS (secure)
                │ No credentials in Flutter
                ▼
┌─────────────────────────────────┐
│   MUNSHI BACKEND                │
│   Supabase Edge Functions       │
│                                 │
│   wa-connect      (save creds)  │
│   wa-send         (send msg)    │
│   wa-health-check (test conn)   │
│   wa-webhook      (receive)     │
└───────────────┬─────────────────┘
                │ API Key + Connection ID
                │ (decrypted server-side only)
                ▼
┌─────────────────────────────────┐
│   OUR WHATSAPP API              │
│                                 │
│   Connection management         │
│   Message delivery              │
│   Webhook forwarding            │
└───────────────┬─────────────────┘
                │
                ▼
           WhatsApp
```

**Inbound flow (messages FROM WhatsApp):**

```
WhatsApp
    ↓
Our WhatsApp API
    ↓  (signed webhook POST)
/wa-webhook Edge Function
    ↓  verify HMAC-SHA256 signature
    ↓  resolve dealer by connection_id
    ↓  check idempotency (event_id)
    ↓  store in wa_webhook_events + wa_inbox
    ↓  update wa_outbound_queue status
Dealer sees message in Inbox-lite UI
```

---

## Credentials

Each dealer has exactly one WhatsApp connection record. Three credentials are required:

| Credential | Description | Where stored |
|---|---|---|
| `connection_id` | Unique ID assigned by our WA API | `whatsapp_connections.connection_id` (plaintext — not sensitive) |
| `api_key` | Authentication key for our WA API | `whatsapp_connections.api_key_encrypted` (pgp_sym_encrypt) |
| `webhook_secret` | HMAC-SHA256 signing secret for webhooks | `whatsapp_connections.webhook_secret_encrypted` (pgp_sym_encrypt) |

### Credential lifecycle

1. Dealer enters credentials in `WaConnectScreen` (API key and webhook secret fields)
2. Flutter calls `wa-connect` Edge Function via HTTPS
3. `wa-connect` validates credentials against our WA API
4. On success: calls `store_wa_credentials()` DB function (service_role) which encrypts and persists
5. **Credentials are cleared from Dart state immediately after the Edge Function call**
6. Flutter never sees the credentials again — subsequent reads return only safe metadata

### What the Flutter client receives

After connecting, the Flutter app only ever receives:
```json
{
  "id": "uuid",
  "connection_id": "conn_****5678",   ← masked
  "phone_number": "+923001234567",
  "display_name": "Al-Hamid Properties",
  "status": "active",
  "last_health_check_at": "2026-10-02T09:00:00Z",
  "last_webhook_at": "2026-10-02T10:30:00Z"
}
```

The `api_key` and `webhook_secret` fields **do not exist** in any Flutter model or API response.

---

## Credential Storage

```sql
-- Encryption uses pgp_sym_encrypt (pgcrypto extension)
-- Key stored as DB session variable: app.wa_credential_key
-- Set in production:
ALTER DATABASE postgres SET app.wa_credential_key = 'your-32-char-secret';

-- Encrypted storage (inside store_wa_credentials() function)
pgp_sym_encrypt(plaintext_api_key, app.wa_credential_key)
    → stored as bytea in api_key_encrypted

-- Decryption (inside get_wa_credentials() function, service_role only)
pgp_sym_decrypt(api_key_encrypted::bytea, app.wa_credential_key)
    → plaintext lives only in Edge Function memory
```

### Functions with restricted access

| Function | Access | Purpose |
|---|---|---|
| `store_wa_credentials()` | `service_role` only | Encrypt and store API key + webhook secret |
| `get_wa_credentials()` | `service_role` only | Decrypt for use in Edge Functions |

Both functions are REVOKED from `authenticated`, `anon`, and `public`.

---

## Connection Lifecycle

### 1. Connect

```
Dealer opens Settings → WhatsApp
Enters: Connection ID, API Base URL, API Key, Webhook Secret
Presses "جوڑیں" (Connect)
    ↓
wa-connect Edge Function:
  1. Verify caller JWT (owner/manager only)
  2. Validate connection against our WA API
  3. Call store_wa_credentials() to encrypt and store
  4. Return safe metadata (NO credentials)
    ↓
Flutter clears API key + webhook secret from TextEditingControllers
WaConnectScreen shows Connected state
```

### 2. Active

```
whatsapp_connections.status = 'active'

Periodic health checks via wa-health-check Edge Function:
  - Updates last_health_check_at
  - Updates phone_number and display_name if changed
  - Sets status to 'error' if API reports unhealthy
```

### 3. Test Connection

```
Dealer presses "کنیکشن چیک کریں"
    ↓
wa-health-check Edge Function:
  1. Fetch credentials server-side (get_wa_credentials)
  2. Call our WA API health endpoint
  3. Update last_health_check_at + status in DB
  4. Return: { healthy, phone_number, display_name, error? }
```

### 4. Disconnect

```
Dealer presses "منقطع کریں" → confirmation dialog
    ↓
WaConnectionRepository.disconnect():
  UPDATE whatsapp_connections
  SET status = 'disconnected', disconnected_at = now()
  -- Historical messages preserved
  -- Credentials remain encrypted in DB (not deleted)
  -- wa_inbox, wa_outbound_queue, wa_webhook_events all preserved
```

### 5. Reconnect

```
Dealer presses "جوڑیں" again with same or new credentials
wa-connect handles ON CONFLICT (dealer_id, connection_id) DO UPDATE
Credentials replaced with new encrypted values
Status set back to 'active'
```

---

## Outbound Messaging

### Offline-safe flow

```
1. WaConnectionRepository.queueOutboundMessage()
   → INSERT into wa_outbound_queue with status='queued'
   (Survives offline — record exists locally and in DB)

2. wa-send Edge Function (triggered immediately or by cron):
   → Fetch credentials server-side
   → Send via our WA API
   → Update wa_outbound_queue.status = 'sent'

3. On delivery webhook:
   → wa-webhook updates status = 'delivered' | 'read' | 'failed'
```

### Idempotency

Every outbound message has an `idempotency_key` (UUID generated by the client before the first attempt). If the same key is submitted twice, the second insert fails with a unique constraint violation — only one message is ever sent.

```dart
// Client generates idempotency key before first attempt
final iKey = const Uuid().v4();
await repo.queueOutboundMessage(idempotencyKey: iKey, ...);
// Retrying with the same iKey is safe
```

### Retry policy

```
Attempt 1 → wait 1s → Attempt 2 → wait 2s → Attempt 3 → wait 4s
Max 3 retries (configurable via wa_outbound_queue.max_retries)
After max retries: status = 'failed', error_message recorded
```

### Delivery status tracking

| Status | Meaning |
|---|---|
| `queued` | Waiting to be sent (offline or queue) |
| `sending` | In-flight to our WA API |
| `sent` | Our WA API accepted the message |
| `delivered` | WhatsApp confirms delivery to device |
| `read` | Recipient opened the message |
| `failed` | Permanent failure after max retries |
| `cancelled` | Dealer or system cancelled before send |

---

## Inbound Webhook

### Endpoint

```
POST https://your-supabase-project.supabase.co/functions/v1/wa-webhook
```

Register this URL in our WhatsApp API platform as the webhook endpoint for all connections.

### Signature verification

Every webhook from our WA API includes a signature header:

```
X-Signature: sha256=<hmac_sha256_hex>
```

The `wa-webhook` Edge Function verifies this using the connection's `webhook_secret` (decrypted server-side via `get_wa_credentials()`). Requests with invalid or missing signatures return HTTP 403.

### Routing

Dealer identity is **never** trusted from the webhook body. The routing chain is:

```
webhook body: { connection_id: "conn_abc123", ... }
    ↓
DB lookup: SELECT dealer_id FROM whatsapp_connections
           WHERE connection_id = 'conn_abc123' AND status = 'active'
    ↓
dealer_id determined server-side — cannot be spoofed
```

### Idempotency

Every inbound event has a provider `event_id`. Before processing:

```sql
-- Check if already processed
SELECT id FROM wa_webhook_events
WHERE dealer_id = ? AND event_id = ?
-- If exists: return 200 (already handled), skip processing
-- If not: process and INSERT (UNIQUE constraint on dealer_id + event_id)
```

Duplicate webhooks (our WA API retries on timeout) are safely no-ops.

### STOP compliance

If a recipient sends `STOP`, `UNSUBSCRIBE`, or `بند کرو`:

```
wa-webhook detects the message body
    ↓
UPDATE parties SET wa_opt_in = false
WHERE dealer_id = ? AND phone = ?
    ↓
wa_sequences enrollment paused for this party (Phase 2)
```

---

## Tenant Isolation

Each dealer's connection is completely isolated:

| Isolation point | Mechanism |
|---|---|
| DB: credentials unreachable cross-tenant | RLS + `get_wa_credentials()` requires matching `p_dealer_id` |
| Webhook routing | `connection_id` → server-side lookup → `dealer_id` |
| Flutter client | Never receives API key or webhook secret |
| Edge Functions | `dealer_id` always from JWT claims, never from request body |
| Outbound send | `wa-send` verifies `dealer_id` matches connection's `dealer_id` |

A request from Dealer A cannot:
- Read Dealer B's connection credentials
- Send messages through Dealer B's connection
- Receive Dealer B's webhook events
- Modify Dealer B's connection status

---

## Failure Handling

| Failure | Behavior |
|---|---|
| Invalid API key | `wa-connect` returns 422; credentials not stored |
| Connection validation fails | 422 with error message; nothing stored |
| Message send API timeout | Queued message retried with exponential backoff |
| Message send auth failure | status = 'failed'; error_message = 'auth_failed'; no retry |
| Webhook signature invalid | HTTP 403; event not processed; not counted as duplicate |
| Webhook unknown connection_id | HTTP 200 (silent); event not processed |
| WA API rate limit | Retry with backoff; `wa_outbound_queue.status` stays 'queued' |
| Network outage | Messages queued in `wa_outbound_queue`; sent when reconnected |
| Credential key missing | DB function raises exception; 500 returned; credentials never decrypted |

---

## Environment Secrets Required

Set these in Supabase Edge Function secrets before any WhatsApp testing:

```bash
supabase secrets set WA_API_BASE_URL="https://api.ourwhatsapp.example.com/v1"
supabase secrets set WA_API_KEY="platform-level-api-key"
supabase secrets set APP_STORE_LINK="https://munshi.app/download"

# If using webhook signature verification
# (set this to the webhook signing secret from our WA API platform)
# Note: per-connection secrets are stored in DB; this is a platform-level fallback
```

And in the DB:
```sql
ALTER DATABASE postgres SET app.wa_credential_key = 'your-32-char-random-secret';
```

---

## Testing the Integration

### 1. Manual connection test (staging)

```
1. Log in as owner in staging app
2. Navigate to Settings → WhatsApp
3. Enter test Connection ID, API Key, Webhook Secret from staging WA API
4. Press "جوڑیں"
5. Verify: connected status shown, phone number displayed, no credentials visible
6. Press "کنیکشن چیک کریں" — verify health check passes
7. Press "منقطع کریں" — verify disconnected state shown
```

### 2. Webhook test

```bash
# Use our WA API's test webhook sender, or:
curl -X POST https://your-project.supabase.co/functions/v1/wa-webhook \
  -H "Content-Type: application/json" \
  -H "X-Signature: sha256=<valid_hmac>" \
  -d '{"connection_id":"test_conn","events":[{"type":"message","event_id":"evt_001","from":"+923001234567","message_type":"text","body":"hello","timestamp":"2026-10-02T10:00:00Z"}]}'
```

### 3. Idempotency test

```bash
# Send same webhook twice — second should be no-op
# Verify wa_webhook_events has only one row with event_id = 'evt_001'
```

### 4. Cross-tenant test

```sql
-- As Dealer A: try to read Dealer B's connection credentials
SELECT * FROM get_wa_credentials('dealer_b_id', 'conn_b_123');
-- Expected: 0 rows (function enforces dealer_id match)
```
