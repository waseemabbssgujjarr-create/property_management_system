import 'package:equatable/equatable.dart';

enum FollowupKind {
  call, visit, whatsapp, other;

  String get dbValue => name;
  String get labelUr => switch (this) {
    FollowupKind.call      => 'کال',
    FollowupKind.visit     => 'وزٹ',
    FollowupKind.whatsapp  => 'واٹس ایپ',
    FollowupKind.other     => 'دیگر',
  };
  static FollowupKind fromDb(String? v) => switch (v) {
    'visit'    => FollowupKind.visit,
    'whatsapp' => FollowupKind.whatsapp,
    _          => FollowupKind.call,
  };
}

enum FollowupStatus {
  pending, done, snoozed, cancelled;

  String get dbValue => name;
  static FollowupStatus fromDb(String? v) => switch (v) {
    'done'      => FollowupStatus.done,
    'snoozed'   => FollowupStatus.snoozed,
    'cancelled' => FollowupStatus.cancelled,
    _           => FollowupStatus.pending,
  };
}

class Followup extends Equatable {
  final String id;
  final String dealerId;
  final String? dealId;
  final String? partyId;
  final String? assignedTo;
  final FollowupKind kind;
  final DateTime dueAt;
  final DateTime? doneAt;
  final DateTime? snoozedUntil;
  final FollowupStatus status;
  final String? noteText;
  final String? noteAudioUrl;

  // Populated via join
  final String? partyName;
  final String? partyPhone;
  final String? partyPhotoUrl;

  const Followup({
    required this.id,
    required this.dealerId,
    this.dealId,
    this.partyId,
    this.assignedTo,
    this.kind = FollowupKind.call,
    required this.dueAt,
    this.doneAt,
    this.snoozedUntil,
    this.status = FollowupStatus.pending,
    this.noteText,
    this.noteAudioUrl,
    this.partyName,
    this.partyPhone,
    this.partyPhotoUrl,
  });

  bool get isOverdue =>
      status == FollowupStatus.pending && dueAt.isBefore(DateTime.now());

  bool get isDueToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return dueAt.isAfter(today) && dueAt.isBefore(tomorrow);
  }

  factory Followup.fromMap(Map<String, dynamic> m) => Followup(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    dealId: m['deal_id'] as String?,
    partyId: m['party_id'] as String?,
    assignedTo: m['assigned_to'] as String?,
    kind: FollowupKind.fromDb(m['kind'] as String?),
    dueAt: DateTime.parse(m['due_at'] as String),
    doneAt: m['done_at'] != null
        ? DateTime.tryParse(m['done_at'] as String)
        : null,
    snoozedUntil: m['snoozed_until'] != null
        ? DateTime.tryParse(m['snoozed_until'] as String)
        : null,
    status: FollowupStatus.fromDb(m['status'] as String?),
    noteText: m['note_text'] as String?,
    noteAudioUrl: m['note_audio_url'] as String?,
    partyName: (m['parties'] as Map?)?['name'] as String?,
    partyPhone: (m['parties'] as Map?)?['phone'] as String?,
    partyPhotoUrl: (m['parties'] as Map?)?['photo_url'] as String?,
  );

  @override
  List<Object?> get props => [id, status, dueAt];
}
