# OFFLINE SYNC DESIGN — Munshi
**Version:** 1.0 | **Date:** 2026-10-02

---

## 1. Principle

**The device is the source of truth for the owner's daily work.
The server is the source of truth for financial records and multi-device consistency.**

The app must be fully usable without any network:
- View all cached data
- Create deals, properties, parties
- Record payments (queued)
- Add follow-ups
- Capture photos (queued)
- Record voice notes (queued)
- Generate local receipt number (provisional, reconciled on sync)

When network returns:
- All queued operations execute in order
- No duplicates
- No silent failures
- Conflicts are surfaced visibly

---

## 2. Architecture

```
Flutter App
├── Drift (SQLite)           ← local copy of all data
│   ├── cached_records/      ← mirror of server state
│   ├── sync_queue/          ← pending operations
│   └── sync_tombstones/     ← deleted record IDs
│
└── SyncEngine               ← background service
    ├── enqueue()            ← adds operation to queue
    ├── processQueue()       ← sends to Supabase when online
    ├── handleConflict()     ← resolution policy
    └── retryFailed()        ← exponential backoff
```

---

## 3. Sync Queue Operation

Every local write creates a `SyncOperation` before touching Drift:

```dart
// SyncOperation model
class SyncOperation {
  final String id;                    // local UUID
  final String idempotencyKey;        // UUID sent to server — prevents duplicates
  final String operationType;         // 'insert'|'update'|'delete'|'upload'
  final String tableName;
  final String? rowId;
  final Map<String, dynamic> payload;
  final List<String> attachmentPaths; // local file paths
  final SyncStatus status;            // queued|uploading|synced|failed|conflict
  final int retryCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int serverRevision;           // for conflict detection
}
```

---

## 4. Conflict Resolution Policy

| Record Type | Policy | Rationale |
|---|---|---|
| Money / payments | **Server wins; surface conflict** | Financial integrity > convenience |
| Deal stage changes | **Server wins; log both** | Stage machine enforced server-side |
| Text notes | **Last write wins (client)** | Low stakes, dealer trust |
| Voice notes | **Client wins** (new audio always uploaded) | Audio is user's voice |
| Property details | **Server wins** | Inventory must be consistent |
| Party contact info | **Last write wins** | Contact info changes are safe |
| Follow-up completion | **Client wins** (done = done) | Trust the action |

**Financial conflict procedure:**
1. Server rejects duplicate idempotency key → client shows "already recorded"
2. Server returns different balance than expected → surface as orange warning
3. Conflict preserved in audit log with both versions
4. User must explicitly acknowledge financial discrepancies

---

## 5. Idempotency

Every operation that touches financial data includes an `idempotency_key` (UUID generated client-side before the first attempt).

Server endpoint: if `idempotency_key` already exists in `payments`:
- Return the existing record (200 OK)
- Do NOT create a duplicate

This means: if a payment is recorded offline, synced once, network drops, and the queue retries — the server returns the existing payment, the client marks the operation synced.

---

## 6. Attachment Sync

Attachments (photos, voice notes, documents) follow a separate queue:
1. Save file to local app storage
2. Enqueue `SyncOperation(type: 'upload', localPath: '...', bucket: '...', dealId: '...')`
3. On sync: upload file to Supabase Storage
4. On success: update local record's `url` field with the storage URL
5. On failure: retry with exponential backoff (1s, 2s, 4s, 8s, max 5 retries)
6. After 5 failures: surface in sync status UI with manual retry option

---

## 7. Sync Status UI

Sync state is always visible in the app bar as a small icon:
- 🟡 Pulsing amber = operations in queue ("save ho raha hai")
- ✅ Green check (3s then fades) = all synced ("ho gaya")
- 🔴 Red dot = failed operations ("sync nahi hua")

Tap the icon: opens sync status sheet showing:
- Queued operations count
- Failed operations (with retry buttons)
- Last successful sync time

Voice: if voice is enabled, plays Urdu audio when sync completes ("ho gaya") or fails ("save nahi hua — dobara koshish karein").

---

## 8. Drift Schema Alignment

The Drift local schema mirrors the Supabase schema with additions for sync:

```dart
// Additional columns in every synced Drift table:
TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
TextColumn get idempotencyKey => text().nullable()();
IntColumn get serverRevision => integer().withDefault(const Constant(0))();
DateTimeColumn get lastSyncedAt => dateTime().nullable()();
```

---

## 9. Full Offline Bootstrap

On first install (or after cache clear):
1. Authenticate → receive JWT
2. Pull full dataset for this dealer (paginated, max 1000 records per table)
3. Store in Drift
4. Show loading progress as colored progress bar (no text needed)
5. When complete: "tayar hai" (ready) + green check
6. From this point, app works fully offline

On subsequent launches:
- Load from Drift immediately (no loading spinner)
- Background sync pull of changes since last sync
- Merge changes into Drift

---

## 10. Recovery

If Drift database becomes corrupted:
1. App detects on startup (hash check)
2. Shows recovery screen: icon + "ek baar internet se reload karo" + reload button
3. Pulls fresh from server
4. No data is lost — server is the permanent record

If sync queue has unrecoverable items:
1. After 5 retries: move to `failed_operations` table
2. Notify user with details and manual retry
3. Never silently discard financial operations
