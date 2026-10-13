import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_connection_native.dart'
    if (dart.library.html) 'db_connection_stub.dart';

part 'drift_database.g.dart';

// ── Table definitions ─────────────────────────────────────────────────────

/// Sync queue — every local write before it reaches Supabase.
class SyncOperations extends Table {
  TextColumn get id             => text()();
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get operationType  => text()();  // 'insert'|'update'|'delete'|'upload'
  TextColumn get targetTable    => text()();  // renamed from tableName to avoid Drift conflict
  TextColumn get rowId          => text().nullable()();
  TextColumn get payload        => text()();  // JSON string
  TextColumn get attachmentPath => text().nullable()();  // local file path
  TextColumn get status         => text().withDefault(const Constant('queued'))();
  IntColumn  get retryCount     => integer().withDefault(const Constant(0))();
  TextColumn get lastError      => text().nullable()();
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt   => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached deals (offline read + create)
class CachedDeals extends Table {
  TextColumn  get id              => text()();
  TextColumn  get dealerId        => text()();
  TextColumn  get stage           => text()();
  TextColumn  get propertyId      => text().nullable()();
  TextColumn  get buyerPartyId    => text().nullable()();
  TextColumn  get sellerPartyId   => text().nullable()();
  IntColumn   get dealPriceRs     => integer().nullable()();
  RealColumn  get commBuyerPct    => real().withDefault(const Constant(1.0))();
  RealColumn  get commSellerPct   => real().withDefault(const Constant(1.0))();
  IntColumn   get expectedCommRs  => integer().nullable()();
  TextColumn  get tokenType       => text().nullable()();
  IntColumn   get tokenRs         => integer().nullable()();
  TextColumn  get tokenExpiresAt  => text().nullable()();
  IntColumn   get bayanaRs        => integer().nullable()();
  TextColumn  get notesText       => text().nullable()();
  TextColumn  get notesAudioUrl   => text().nullable()();
  TextColumn  get createdAt       => text()();
  TextColumn  get syncStatus      => text().withDefault(const Constant('synced'))();
  IntColumn   get serverRevision  => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached parties
class CachedParties extends Table {
  TextColumn get id           => text()();
  TextColumn get dealerId     => text()();
  TextColumn get type         => text()();
  TextColumn get name         => text()();
  TextColumn get nameAudioUrl => text().nullable()();
  TextColumn get phone        => text().nullable()();
  TextColumn get photoUrl     => text().nullable()();
  TextColumn get source       => text().nullable()();
  BoolColumn get waOptIn      => boolean().withDefault(const Constant(false))();
  TextColumn get notesText    => text().nullable()();
  TextColumn get createdAt    => text()();
  TextColumn get syncStatus   => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached properties
class CachedProperties extends Table {
  TextColumn  get id          => text()();
  TextColumn  get dealerId    => text()();
  TextColumn  get kind        => text()();
  TextColumn  get society     => text()();
  TextColumn  get block       => text().nullable()();
  RealColumn  get sizeMarla   => real().nullable()();
  TextColumn  get sizeLabel   => text().nullable()();
  IntColumn   get demandRs    => integer().nullable()();
  TextColumn  get status      => text().withDefault(const Constant('available'))();
  TextColumn  get createdAt   => text()();
  TextColumn  get syncStatus  => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached followups
class CachedFollowups extends Table {
  TextColumn  get id          => text()();
  TextColumn  get dealerId    => text()();
  TextColumn  get dealId      => text().nullable()();
  TextColumn  get partyId     => text().nullable()();
  TextColumn  get kind        => text()();
  TextColumn  get dueAt       => text()();
  TextColumn  get status      => text().withDefault(const Constant('pending'))();
  TextColumn  get noteText    => text().nullable()();
  TextColumn  get noteAudioUrl => text().nullable()();
  TextColumn  get createdAt   => text()();
  TextColumn  get syncStatus  => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached payments (local copies — never delete these)
class CachedPayments extends Table {
  TextColumn  get id              => text()();
  TextColumn  get dealerId        => text()();
  TextColumn  get dealId          => text().nullable()();
  TextColumn  get kind            => text()();
  IntColumn   get amountRs        => integer()();
  TextColumn  get direction       => text()();
  TextColumn  get method          => text().nullable()();
  TextColumn  get receiptNo       => text().nullable()();
  TextColumn  get noteText        => text().nullable()();
  TextColumn  get occurredAt      => text()();
  TextColumn  get idempotencyKey  => text().unique()();
  TextColumn  get syncStatus      => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Voice notes (audio stored locally — uploaded to Supabase Storage when online)
class CachedVoiceNotes extends Table {
  TextColumn  get id          => text()();
  TextColumn  get dealerId    => text()();
  TextColumn  get refTable    => text()();
  TextColumn  get refId       => text()();
  TextColumn  get localPath   => text()();           // local file
  TextColumn  get remoteUrl   => text().nullable()(); // populated after upload
  TextColumn  get transcriptUr => text().nullable()();
  IntColumn   get durationS   => integer().nullable()();
  TextColumn  get createdAt   => text()();
  TextColumn  get syncStatus  => text().withDefault(const Constant('queued'))();

  @override
  Set<Column> get primaryKey => {id};
}

// Database connection is platform-conditional:
// - Native: NativeDatabase backed by a real SQLite file
// - Web: In-memory NativeDatabase (no persistent offline on web)
// See db_connection_native.dart and db_connection_stub.dart

@DriftDatabase(tables: [
  SyncOperations,
  CachedDeals,
  CachedParties,
  CachedProperties,
  CachedFollowups,
  CachedPayments,
  CachedVoiceNotes,
])
class MunshiLocalDb extends _$MunshiLocalDb {
  MunshiLocalDb() : super(openAppDatabase());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Handle future schema migrations here
    },
  );
}

// ── Provider ─────────────────────────────────────────────────────────────

final localDbProvider = Provider<MunshiLocalDb>((ref) {
  final db = MunshiLocalDb();
  ref.onDispose(db.close);
  return db;
});
