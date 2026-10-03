import 'package:equatable/equatable.dart';

enum PropertyKind {
  plot, file, house, shop, commercial, apartment;

  String get labelUr => switch (this) {
    PropertyKind.plot       => 'پلاٹ',
    PropertyKind.file       => 'فائل',
    PropertyKind.house      => 'گھر',
    PropertyKind.shop       => 'دکان',
    PropertyKind.commercial => 'کمرشل',
    PropertyKind.apartment  => 'اپارٹمنٹ',
  };

  String get dbValue => name;

  static PropertyKind? fromDb(String? v) => switch (v) {
    'plot'       => PropertyKind.plot,
    'file'       => PropertyKind.file,
    'house'      => PropertyKind.house,
    'shop'       => PropertyKind.shop,
    'commercial' => PropertyKind.commercial,
    'apartment'  => PropertyKind.apartment,
    _            => null,
  };
}

enum PropertyStatus {
  available, tokenGiven, bayanaDone, sold, withdrawn;

  String get dbValue => switch (this) {
    PropertyStatus.available   => 'available',
    PropertyStatus.tokenGiven  => 'token_given',
    PropertyStatus.bayanaDone  => 'bayana_done',
    PropertyStatus.sold        => 'sold',
    PropertyStatus.withdrawn   => 'withdrawn',
  };

  String get labelUr => switch (this) {
    PropertyStatus.available   => 'دستیاب',
    PropertyStatus.tokenGiven  => 'ٹوکن دیا',
    PropertyStatus.bayanaDone  => 'بیعانہ ہوا',
    PropertyStatus.sold        => 'فروخت',
    PropertyStatus.withdrawn   => 'واپس',
  };

  static PropertyStatus fromDb(String? v) => switch (v) {
    'token_given'  => PropertyStatus.tokenGiven,
    'bayana_done'  => PropertyStatus.bayanaDone,
    'sold'         => PropertyStatus.sold,
    'withdrawn'    => PropertyStatus.withdrawn,
    _              => PropertyStatus.available,
  };
}

class Property extends Equatable {
  final String id;
  final String dealerId;
  final String? officeId;
  final PropertyKind kind;
  final String society;
  final String? block;
  final String? sector;
  final double? sizeMarla;
  final String? sizeLabel;
  final int? demandRs;
  final PropertyStatus status;
  final String? ownerPartyId;
  final bool exclusive;
  final String? certNo;
  final String? notesText;
  final String? notesAudioUrl;
  final List<String> photoUrls;
  final DateTime? listedAt;
  final DateTime createdAt;

  const Property({
    required this.id,
    required this.dealerId,
    required this.kind,
    required this.society,
    this.officeId,
    this.block,
    this.sector,
    this.sizeMarla,
    this.sizeLabel,
    this.demandRs,
    this.status = PropertyStatus.available,
    this.ownerPartyId,
    this.exclusive = false,
    this.certNo,
    this.notesText,
    this.notesAudioUrl,
    this.photoUrls = const [],
    this.listedAt,
    required this.createdAt,
  });

  String get displayTitle {
    final parts = <String>[];
    if (sizeLabel != null) parts.add(sizeLabel!);
    parts.add(kind.labelUr);
    parts.add(society);
    if (block != null) parts.add('بلاک $block');
    return parts.join(' — ');
  }

  factory Property.fromMap(Map<String, dynamic> m) => Property(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    officeId: m['office_id'] as String?,
    kind: PropertyKind.fromDb(m['kind'] as String?) ?? PropertyKind.plot,
    society: m['society'] as String? ?? '',
    block: m['block'] as String?,
    sector: m['sector'] as String?,
    sizeMarla: (m['size_marla'] as num?)?.toDouble(),
    sizeLabel: m['size_label'] as String?,
    demandRs: m['demand_rs'] as int?,
    status: PropertyStatus.fromDb(m['status'] as String?),
    ownerPartyId: m['owner_party_id'] as String?,
    exclusive: m['exclusive'] as bool? ?? false,
    certNo: m['cert_no'] as String?,
    notesText: m['notes_text'] as String?,
    notesAudioUrl: m['notes_audio_url'] as String?,
    photoUrls: (m['property_photos'] as List?)
        ?.map((p) => (p as Map)['url'] as String)
        .toList() ?? [],
    listedAt: m['listed_at'] != null
        ? DateTime.tryParse(m['listed_at'] as String)
        : null,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toInsertMap() => {
    'dealer_id': dealerId,
    'office_id': officeId,
    'kind': kind.dbValue,
    'society': society,
    'block': block,
    'sector': sector,
    'size_marla': sizeMarla,
    'size_label': sizeLabel,
    'demand_rs': demandRs,
    'status': status.dbValue,
    'owner_party_id': ownerPartyId,
    'exclusive': exclusive,
    'cert_no': certNo,
    'notes_text': notesText,
    'notes_audio_url': notesAudioUrl,
  };

  @override
  List<Object?> get props => [id, status, demandRs];
}
