# SECURITY — Munshi
**Version:** 1.1 | **Date:** 2026-10-02 | **Updated:** Pilot hardening pass

---

## 1. Threat Model

| Threat | Severity | Mitigation |
|---|---|---|
| Cross-tenant data access | Critical | RLS on every table; tested explicitly |
| Unauthorized role escalation | High | RLS role checks; no client-side-only guards |
| Stolen WA API key / webhook secret | Critical | pgp_sym_encrypt in DB; service_role only access; never returned to client |
| Exposed private documents | High | Private storage buckets; signed URLs (15-min) |
| Replay of payment/sync ops | High | Idempotency keys on all financial writes |
| CNIC/PII exposure | High | AES-256 encrypted in FlutterSecureStorage before DB insert |
| Voice note exposure | Medium | Private bucket; signed URLs |
| Support impersonation without audit | High | Impersonation requires explicit auth + audit event |
| Brute-force OTP | Medium | Rate limiting: 3 attempts per 15 min per phone (otp_attempts table) |
| Webhook replay (WA API) | Medium | HMAC-SHA256 signature verification + event_id idempotency |
| Service-role key in mobile app | Critical | Service-role used only in Edge Functions |
| JWT custom claims missing | Critical | Must register custom_access_token_hook (see §3) |

---

## 2. Multi-Tenant Isolation

Every table that holds dealer data has:
- `dealer_id uuid NOT NULL REFERENCES dealers(id)`
- An RLS policy enforced via custom JWT claims

JWT custom claims populated by `custom_access_token_hook`:
```json
{
  "dealer_id": "uuid",
  "user_role": "owner|manager|agent|munshi",
  "user_id": "uuid",
  "office_id": "uuid|null"
}
```

RLS helper functions (defined in migration 001):
- `auth.dealer_id()` → reads `dealer_id` from JWT claims
- `auth.current_role()` → reads `user_role` from JWT claims
- `auth.current_user_id()` → reads `user_id` from JWT claims

---

## 3. JWT Custom Claims Hook — REQUIRED SETUP

**This is the most critical deployment step. Without it, all RLS policies return NULL and tenant isolation is broken.**

### What it does
The `custom_access_token_hook` function (defined in migration 003) injects dealer context into every JWT at login/refresh. Without this hook, `auth.dealer_id()` returns NULL and every RLS policy fails open or closed depending on the policy definition.

### Registration steps (Supabase Dashboard)

1. Open your Supabase project dashboard
2. Navigate to: **Authentication → Hooks**
3. Click **Add Hook**
4. Select hook type: **Custom Access Token**
5. Select function: `public.custom_access_token_hook`
6. Save

### Verification

After registration, log in as a test user and inspect the JWT:

```bash
# Decode the JWT (base64 decode the middle segment)
echo "YOUR_JWT_ACCESS_TOKEN" | cut -d. -f2 | base64 -d | python3 -m json.tool
```

Expected claims:
```json
{
  "dealer_id": "11111111-...",
  "user_role": "owner",
  "user_id": "22222222-...",
  "office_id": null
}
```

If `dealer_id` is missing or null, the hook is not registered correctly.

### Testing the hook

```sql
-- Run in Supabase SQL editor after logging in as a test user
SELECT auth.dealer_id();   -- should return your dealer UUID
SELECT auth.current_role(); -- should return 'owner'|'manager'|etc.
```

### What happens without the hook

- `auth.dealer_id()` returns NULL
- All `WHERE dealer_id = auth.dealer_id()` policies match nothing (safe — no cross-tenant leak) OR fail entirely
- Users cannot access their own data
- The app will show empty screens or errors

---

## 4. WhatsApp Credential Security

WA API credentials (API key, webhook secret) follow this security model:

```
Flutter UI (one-time entry)
    ↓ HTTPS POST
wa-connect Edge Function (service_role)
    ↓
store_wa_credentials() DB function
    ↓ pgp_sym_encrypt(credential, server_key)
whatsapp_connections.api_key_encrypted
whatsapp_connections.webhook_secret_encrypted
```

**Decryption path (server-only):**
```
Edge Function (service_role)
    ↓
get_wa_credentials() DB function
    ↓ pgp_sym_decrypt(ciphertext, server_key)
plaintext credential (lives only in Edge Function memory, never returned to client)
```

**Server key setup:**
```sql
-- Set in supabase/config.toml (local) or Supabase Dashboard (production)
ALTER DATABASE postgres SET app.wa_credential_key = 'your-32-char-secret-key';
```

For production, use a strong random key:
```bash
openssl rand -hex 32
```

**Never** store this key in:
- `.env` files committed to git
- Flutter source code
- Client-readable DB fields
- Log files

---

## 5. CNIC Encryption

CNIC is sensitive PII (Pakistani National ID). Encryption model:

```
User enters CNIC in UI
    ↓
PartyRepository.createParty()
    ↓
EncryptionService.encrypt(cnic, dealerId: dealerId)
    ↓ AES-256-CBC, random IV per call, dealer-scoped key
    ↓ Key stored in FlutterSecureStorage (hardware-backed)
encrypted CNIC stored in parties.cnic column
```

**Decryption:** only when explicitly requested (e.g., "View CNIC" with viewCnic permission).

**Key management:** The encryption key never leaves the device. If the device is wiped, encrypted CNIC cannot be recovered — by design. Future: consider server-side key escrow for enterprise accounts.

---

## 6. Role-Based Access Control

| Capability | owner | manager | agent | munshi |
|---|---|---|---|---|
| View all deals | ✅ | ✅ | assigned only | ✅ |
| Record payment | ✅ | ✅ | ❌ | ✅ |
| Edit commission % | ✅ | ✅ | ❌ | ❌ |
| Pay staff commission | ✅ | configurable | ❌ | ❌ |
| View subscription | ✅ | ❌ | ❌ | ❌ |
| Manage WhatsApp | ✅ | ✅ | ❌ | ❌ |
| View CNIC | ✅ | ✅ | ❌ | ❌ |
| View audit log | ✅ | ❌ | ❌ | ❌ |
| Export data | ✅ | ✅ | ❌ | ❌ |
| Invite staff | ✅ | ✅ | ❌ | ❌ |

Enforcement layers (all three required):
1. Flutter `PermissionService` — hides/disables UI elements
2. Flutter `PermissionGuard` widget — blocks screen access
3. Supabase RLS policies — database-level enforcement

---

## 7. Storage Security

| Bucket | Access | Notes |
|---|---|---|
| `property-photos` | Public-read via CDN | Non-sensitive |
| `avatars` | Public-read | Non-sensitive |
| `share-cards` | Public-read | Generated cards |
| `documents` | **Private** | Signed URLs, 15-min expiry |
| `voice-notes` | **Private** | Signed URLs, 15-min expiry |
| `receipts` | **Private** | Signed URLs |

---

## 8. Secrets Management

| Secret | Storage | Notes |
|---|---|---|
| Supabase service role key | Edge Function env only | `supabase secrets set` |
| Supabase anon key | Flutter app (ok — RLS enforced) | Public key |
| WA API key per dealer | `whatsapp_connections.api_key_encrypted` | pgp_sym_encrypt |
| WA webhook secret per dealer | `whatsapp_connections.webhook_secret_encrypted` | pgp_sym_encrypt |
| WA credential encryption key | DB session config `app.wa_credential_key` | Set via `ALTER DATABASE` |
| Meta app secret (if used) | Edge Function env | `supabase secrets set META_APP_SECRET` |
| Twilio credentials | Edge Function env | `supabase secrets set TWILIO_*` |
| OTP signing secret | Supabase Auth internal | Never exposed |
| CNIC encryption key | FlutterSecureStorage | Hardware-backed per device |

---

## 9. OTP Security

- Max 3 OTP requests per phone per 15 minutes (enforced in `otp-send` Edge Function via `otp_attempts` table)
- OTP value **never** logged anywhere
- Voice OTP: code spoken as individual digits in Urdu with pauses
- OTP expiry: 10 minutes (Supabase Auth default)
- Phone normalized to E.164 before any OTP operation

---

## 10. RLS Test Checklist

Run these tests before every pilot onboarding:

### Setup
```sql
-- Create test tenants in staging environment
-- Dealer A: owner (phone +923001111111), agent (phone +923001111112)
-- Dealer B: owner (phone +923002222221)
```

### Cross-tenant isolation tests

```sql
-- As Dealer A owner: verify can read own deals
SELECT COUNT(*) FROM deals WHERE dealer_id = 'dealer_a_id'; -- should return dealer A count

-- As Dealer A owner: verify cannot read Dealer B deals
SELECT COUNT(*) FROM deals WHERE dealer_id = 'dealer_b_id'; -- should return 0

-- As Dealer A owner: verify cannot insert into Dealer B
INSERT INTO deals (dealer_id, stage) VALUES ('dealer_b_id', 'inquiry'); -- should fail

-- As Dealer B: cannot read Dealer A WhatsApp connection
SELECT api_key_encrypted FROM whatsapp_connections WHERE dealer_id = 'dealer_a_id'; -- 0 rows

-- As Dealer A: cannot call get_wa_credentials for Dealer B
SELECT * FROM get_wa_credentials('dealer_b_id', 'conn123'); -- should return 0 rows
```

### Role permission tests

```sql
-- As agent: cannot insert payment
-- (test via Supabase client with agent JWT)
-- Expected: RLS violation / 0 rows affected

-- As munshi: can insert payment
-- Expected: success

-- As agent: cannot update dealer settings  
-- Expected: RLS violation

-- As owner: can read audit_log for own dealer
-- Expected: rows returned

-- As manager: cannot read audit_log
-- Expected: 0 rows (policy requires owner role)
```

### Financial immutability tests

```sql
-- No one can UPDATE a payment row
UPDATE payments SET amount_rs = 999 WHERE id = 'any_id'; -- should fail (no UPDATE policy)

-- No one can DELETE a payment row
DELETE FROM payments WHERE id = 'any_id'; -- should fail (no DELETE policy)

-- deal_events are INSERT-only
UPDATE deal_events SET kind = 'tampered' WHERE id = 'any_id'; -- should fail
```

---

## 11. Production Deployment Checklist

```
[ ] JWT custom_access_token_hook registered in Supabase Dashboard
[ ] app.wa_credential_key set in production DB config
[ ] META_APP_SECRET set in Edge Function secrets (if using Meta WA)
[ ] WA_API_BASE_URL and WA_API_KEY set in Edge Function secrets
[ ] TWILIO_* secrets set (if using Twilio for OTP)
[ ] LOCAL_SMS_API_* set (if using local Pakistani SMS)
[ ] VOICE_API_* set (if using local voice provider)
[ ] All migrations applied (001 through 005)
[ ] Private storage buckets verified
[ ] RLS test suite run in staging
[ ] APK does not contain service_role key
[ ] .env files not committed to git
[ ] Supabase PITR enabled
```

---

## 1. Threat Model

| Threat | Severity | Mitigation |
|---|---|---|
| Cross-tenant data access | Critical | RLS on every table; tested explicitly |
| Unauthorized role escalation | High | RLS role checks; no client-side-only guards |
| Stolen Meta WhatsApp token | High | Encrypted at rest; never in mobile app |
| Exposed private documents | High | Private storage buckets; signed URLs (15-min) |
| Replay of payment/sync ops | High | Idempotency keys on all financial writes |
| CNIC/PII exposure | High | Encrypted in app layer; private bucket |
| Voice note exposure | Medium | Private bucket; signed URLs |
| Support impersonation without audit | High | Impersonation requires explicit auth + audit event |
| Brute-force OTP | Medium | Rate limiting on otp-send Edge Function |
| Webhook replay (Meta) | Medium | Signature verification + idempotent webhook handler |
| Service-role key in mobile app | Critical | Service-role used only in Edge Functions |

---

## 2. Multi-Tenant Isolation

Every table that holds dealer data has:
- `dealer_id uuid NOT NULL REFERENCES dealers(id)`
- An RLS policy enforced via a custom claim in the JWT

JWT custom claims populated at login:
```json
{
  "dealer_id": "uuid",
  "role": "owner|manager|agent|munshi",
  "office_id": "uuid"
}
```

RLS policy template:
```sql
-- Read: own dealer only
CREATE POLICY "tenant_read" ON table_name
  FOR SELECT USING (dealer_id = (auth.jwt() ->> 'dealer_id')::uuid);

-- Write: own dealer + role check
CREATE POLICY "tenant_write" ON table_name
  FOR INSERT WITH CHECK (
    dealer_id = (auth.jwt() ->> 'dealer_id')::uuid
    AND (auth.jwt() ->> 'role') IN ('owner', 'manager', 'agent')
  );
```

Audit log and deal_events have INSERT-only policies. No UPDATE or DELETE is granted to any dealer user role.

Financial tables (payments, receipt_counters) have INSERT-only policies. No dealer user can UPDATE or DELETE a payment row.

---

## 3. Role-Based Access Control

| Capability | owner | manager | agent | munshi |
|---|---|---|---|---|
| View all deals | ✅ | ✅ | assigned only | ✅ |
| Create deal | ✅ | ✅ | ✅ | ✅ |
| Edit deal stage | ✅ | ✅ | assigned | ❌ |
| View all payments | ✅ | configurable | ❌ | configurable |
| Record payment | ✅ | ✅ | ❌ | ✅ |
| View commission splits | ✅ | ✅ | own only | configurable |
| Edit commission % | ✅ | ✅ | ❌ | ❌ |
| Pay staff commission | ✅ | configurable | ❌ | ❌ |
| View staff commission | ✅ | ✅ | own only | ❌ |
| Invite staff | ✅ | ✅ | ❌ | ❌ |
| Manage WhatsApp | ✅ | configurable | ❌ | ❌ |
| View subscription | ✅ | ❌ | ❌ | ❌ |
| Export data | ✅ | ✅ | ❌ | ❌ |
| View audit log | ✅ | ❌ | ❌ | ❌ |
| Delete records | ✅ | ✅ | ❌ | ❌ |
| View documents | ✅ | ✅ | assigned | configurable |

---

## 4. Storage Security

Buckets:
| Bucket | Access | Notes |
|---|---|---|
| `property-photos` | Public-read via CDN | Non-sensitive |
| `avatars` | Public-read | Non-sensitive |
| `share-cards` | Public-read | Generated cards |
| `documents` | **Private** | Signed URLs, 15-min expiry |
| `voice-notes` | **Private** | Signed URLs, 15-min expiry |
| `receipts` | **Private** | Signed URLs |

Private bucket policy: only Edge Functions (service role) can generate signed URLs. Dealer mobile app requests signed URLs from an Edge Function that verifies RLS ownership first.

---

## 5. Secrets Management

| Secret | Storage | Notes |
|---|---|---|
| Supabase service role key | Edge Function env only | Never in Flutter app |
| Supabase anon key | Flutter app (ok — RLS enforced) | Public key, RLS is the guard |
| Meta WhatsApp token per dealer | `dealers.wa_token_encrypted` (pgcrypto) | Never returned to client |
| Meta app secret | Edge Function env | Webhook signature verification |
| OTP signing secret | Supabase Auth internal | Never exposed |
| Supabase JWT secret | Supabase Auth internal | Never exposed |

Production secrets loaded via:
- Supabase Edge Function secrets (`supabase secrets set`)
- Flutter: `.env.prod` (gitignored), loaded via `flutter_dotenv`
- Never hardcoded in source

---

## 6. WhatsApp Security

- Meta webhook: verify `X-Hub-Signature-256` HMAC on every incoming request
- Webhook handler is idempotent: duplicate `wa_msg_id` is a no-op
- Per-dealer token encrypted with `pgcrypto.encrypt(token, key, 'aes')`
- Template-only marketing messages (pre-approved, no freeform marketing)
- `wa_opt_in = false` → no marketing messages, enforced at `sequence-scheduler` level
- STOP reply → `wa_opt_in = false` set immediately, ack sent

---

## 7. OTP Security

- OTP: 6-digit, valid 10 minutes, single-use
- Rate limit: max 3 OTP requests per phone per 15 minutes (enforced in Edge Function)
- Voice OTP: same token, delivered via text-to-speech call (for non-readers)
- OTP entry UI: big digit boxes, no clipboard paste restriction (accessibility)
- Session expiry: 30-day JWT, with silent refresh; forced re-auth on subscription changes

---

## 8. Data Protection

- CNIC: stored encrypted at application layer before persistence
- Voice notes: private bucket; signed URL generated per-request
- Audit log: accessible only to owner role; platform admin for support
- CSV export: tenant-scoped; generates audit event; never includes other tenant data

---

## 9. Security Test Checklist

Before any production release:
- [ ] Dealer A cannot read Dealer B's deals via REST API
- [ ] Dealer A cannot read Dealer B's parties via REST API
- [ ] Agent cannot access owner subscription settings
- [ ] Munshi cannot access restricted money fields
- [ ] Expired session cannot call any authenticated endpoint
- [ ] Soft-deleted record is not returned to client
- [ ] Private document URL is not accessible without a valid signed URL
- [ ] Replayed payment idempotency key is rejected
- [ ] Replayed sync operation is rejected
- [ ] Meta webhook with invalid signature is rejected
- [ ] OTP brute-force is blocked after 3 attempts
