import 'package:equatable/equatable.dart';

enum PartyType {
  buyer, seller, investor;

  String get dbValue => name;
  String get labelUr => switch (this) {
    PartyType.buyer    => 'خریدار',
    PartyType.seller   => 'فروخت کنندہ',
    PartyType.investor => 'سرمایہ کار',
  };
  static PartyType fromDb(String? v) => switch (v) {
    'seller'   => PartyType.seller,
    'investor' => PartyType.investor,
    _          => PartyType.buyer,
  };
}

enum PartySource {
  walkin, zameen, facebook, referral, other;

  String get dbValue => name == 'walkin' ? 'walkin' : name;
  String get labelUr => switch (this) {
    PartySource.walkin   => 'براہ راست',
    PartySource.zameen   => 'زمین ڈاٹ کام',
    PartySource.facebook => 'فیس بک',
    PartySource.referral => 'سفارش',
    PartySource.other    => 'دیگر',
  };
  static PartySource fromDb(String? v) => switch (v) {
    'zameen'   => PartySource.zameen,
    'facebook' => PartySource.facebook,
    'referral' => PartySource.referral,
    'other'    => PartySource.other,
    _          => PartySource.walkin,
  };
}

class Party extends Equatable {
  final String id;
  final String dealerId;
  final PartyType type;
  final String name;
  final String? nameAudioUrl;
  final String? phone;
  final String? photoUrl;
  final String? cnic;           // encrypted at app layer
  final PartySource source;
  final bool waOptIn;
  final DateTime? waOptInAt;
  final String? notesText;
  final String? notesAudioUrl;
  final DateTime createdAt;

  const Party({
    required this.id,
    required this.dealerId,
    required this.type,
    required this.name,
    this.nameAudioUrl,
    this.phone,
    this.photoUrl,
    this.cnic,
    this.source = PartySource.walkin,
    this.waOptIn = false,
    this.waOptInAt,
    this.notesText,
    this.notesAudioUrl,
    required this.createdAt,
  });

  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) return words[0][0];
    return '${words[0][0]}${words.last[0]}';
  }

  factory Party.fromMap(Map<String, dynamic> m) => Party(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    type: PartyType.fromDb(m['type'] as String?),
    name: m['name'] as String? ?? '',
    nameAudioUrl: m['name_audio_url'] as String?,
    phone: m['phone'] as String?,
    photoUrl: m['photo_url'] as String?,
    cnic: m['cnic'] as String?,
    source: PartySource.fromDb(m['source'] as String?),
    waOptIn: m['wa_opt_in'] as bool? ?? false,
    waOptInAt: m['wa_opt_in_at'] != null
        ? DateTime.tryParse(m['wa_opt_in_at'] as String)
        : null,
    notesText: m['notes_text'] as String?,
    notesAudioUrl: m['notes_audio_url'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toInsertMap() => {
    'dealer_id': dealerId,
    'type': type.dbValue,
    'name': name,
    'name_audio_url': nameAudioUrl,
    'phone': phone,
    'photo_url': photoUrl,
    'source': source.dbValue,
    'wa_opt_in': waOptIn,
    'wa_opt_in_at': waOptIn ? DateTime.now().toIso8601String() : null,
    'notes_text': notesText,
    'notes_audio_url': notesAudioUrl,
  };

  @override
  List<Object?> get props => [id, name, phone, waOptIn];
}
