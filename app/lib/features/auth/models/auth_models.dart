import 'package:equatable/equatable.dart';

/// Authenticated session — stored in memory and Riverpod state.
/// Contains the current user's dealer context.
class AppSession extends Equatable {
  final String userId;
  final String dealerId;
  final String phone;
  final String name;
  final String role; // 'owner'|'manager'|'agent'|'munshi'
  final String? officeId;
  final String language; // 'ur'|'en'
  final String uiMode;   // 'simple'|'detail'
  final bool voiceEnabled;
  final String plan;     // 'starter'|'pro'
  final String dealerStatus;

  const AppSession({
    required this.userId,
    required this.dealerId,
    required this.phone,
    required this.name,
    required this.role,
    this.officeId,
    this.language = 'ur',
    this.uiMode = 'simple',
    this.voiceEnabled = true,
    this.plan = 'starter',
    this.dealerStatus = 'trial',
  });

  bool get isOwner   => role == 'owner';
  bool get isManager => role == 'manager';
  bool get isAgent   => role == 'agent';
  bool get isMunshi  => role == 'munshi';

  bool get isPro     => plan == 'pro';
  bool get isActive  => dealerStatus == 'active' || dealerStatus == 'trial';

  factory AppSession.fromMaps({
    required Map<String, dynamic> user,
    required Map<String, dynamic> dealer,
  }) {
    return AppSession(
      userId: user['id'] as String,
      dealerId: dealer['id'] as String,
      phone: user['phone'] as String? ?? '',
      name: user['name'] as String? ?? '',
      role: user['role'] as String? ?? 'agent',
      officeId: user['office_id'] as String?,
      language: dealer['language'] as String? ?? 'ur',
      uiMode: dealer['ui_mode'] as String? ?? 'simple',
      voiceEnabled: dealer['voice_enabled'] as bool? ?? true,
      plan: dealer['plan'] as String? ?? 'starter',
      dealerStatus: dealer['status'] as String? ?? 'trial',
    );
  }

  @override
  List<Object?> get props => [userId, dealerId, role, plan, dealerStatus];
}

/// OTP send result
class OtpSendResult {
  final bool success;
  final String? error;
  const OtpSendResult.success() : success = true, error = null;
  const OtpSendResult.failure(String err) : success = false, error = err;
}
