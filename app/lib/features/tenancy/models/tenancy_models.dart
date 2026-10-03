import 'package:equatable/equatable.dart';

class DealerProfile extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String? city;
  final List<String> areas;
  final String? logoUrl;
  final String uiMode;
  final bool voiceEnabled;
  final String language;
  final String plan;
  final String status;

  const DealerProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.city,
    this.areas = const [],
    this.logoUrl,
    this.uiMode = 'simple',
    this.voiceEnabled = true,
    this.language = 'ur',
    this.plan = 'starter',
    this.status = 'trial',
  });

  factory DealerProfile.fromMap(Map<String, dynamic> m) => DealerProfile(
    id: m['id'] as String,
    name: m['name'] as String,
    phone: m['phone'] as String,
    city: m['city'] as String?,
    areas: (m['areas'] as List?)?.cast<String>() ?? [],
    logoUrl: m['logo_url'] as String?,
    uiMode: m['ui_mode'] as String? ?? 'simple',
    voiceEnabled: m['voice_enabled'] as bool? ?? true,
    language: m['language'] as String? ?? 'ur',
    plan: m['plan'] as String? ?? 'starter',
    status: m['status'] as String? ?? 'trial',
  );

  @override
  List<Object?> get props => [id, name, phone, plan, status];
}

class StaffMember extends Equatable {
  final String id;
  final String dealerId;
  final String name;
  final String? nameAudioUrl;
  final String phone;
  final String role;
  final String? officeId;
  final double? defaultCommissionPct;
  final bool active;

  const StaffMember({
    required this.id,
    required this.dealerId,
    required this.name,
    required this.phone,
    required this.role,
    this.nameAudioUrl,
    this.officeId,
    this.defaultCommissionPct,
    this.active = true,
  });

  factory StaffMember.fromMap(Map<String, dynamic> m) => StaffMember(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    name: m['name'] as String,
    phone: m['phone'] as String? ?? '',
    role: m['role'] as String? ?? 'agent',
    nameAudioUrl: m['name_audio_url'] as String?,
    officeId: m['office_id'] as String?,
    defaultCommissionPct:
        (m['default_commission_pct'] as num?)?.toDouble(),
    active: m['active'] as bool? ?? true,
  );

  String get roleDisplayUr => switch (role) {
    'owner'   => 'مالک',
    'manager' => 'مینیجر',
    'agent'   => 'ایجنٹ',
    'munshi'  => 'منشی',
    _         => role,
  };

  @override
  List<Object?> get props => [id, dealerId, role, active];
}
