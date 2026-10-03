import 'package:equatable/equatable.dart';

enum WaConnectionStatus {
  pending, connecting, active, disconnected, error;

  String get dbValue => name;
  String get labelUr => switch (this) {
    WaConnectionStatus.pending      => 'منتظر',
    WaConnectionStatus.connecting   => 'جڑ رہا ہے',
    WaConnectionStatus.active       => 'جڑا ہوا',
    WaConnectionStatus.disconnected => 'منقطع',
    WaConnectionStatus.error        => 'خرابی',
  };

  bool get isConnected => this == WaConnectionStatus.active;

  static WaConnectionStatus fromDb(String? v) => switch (v) {
    'connecting'   => WaConnectionStatus.connecting,
    'active'       => WaConnectionStatus.active,
    'disconnected' => WaConnectionStatus.disconnected,
    'error'        => WaConnectionStatus.error,
    _              => WaConnectionStatus.pending,
  };
}

/// WhatsApp connection — safe metadata only.
/// API key and webhook secret are NEVER included in this model.
/// They live only in encrypted DB columns, accessed via service-role functions.
class WaConnection extends Equatable {
  final String id;
  final String dealerId;
  final String? officeId;
  final String connectionId;       // masked for display
  final String apiBaseUrl;
  final String? phoneNumber;
  final String? displayName;
  final WaConnectionStatus status;
  final String? errorMessage;
  final DateTime? lastHealthCheckAt;
  final DateTime? lastWebhookAt;
  final DateTime? lastMessageSentAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WaConnection({
    required this.id,
    required this.dealerId,
    this.officeId,
    required this.connectionId,
    required this.apiBaseUrl,
    this.phoneNumber,
    this.displayName,
    this.status = WaConnectionStatus.pending,
    this.errorMessage,
    this.lastHealthCheckAt,
    this.lastWebhookAt,
    this.lastMessageSentAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Masked connection ID for display (show first 4 + last 4 chars).
  String get maskedConnectionId {
    if (connectionId.length <= 8) return '****';
    return '${connectionId.substring(0, 4)}...${connectionId.substring(connectionId.length - 4)}';
  }

  factory WaConnection.fromMap(Map<String, dynamic> m) => WaConnection(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    officeId: m['office_id'] as String?,
    connectionId: m['connection_id'] as String,
    apiBaseUrl: m['api_base_url'] as String? ?? '',
    phoneNumber: m['phone_number'] as String?,
    displayName: m['display_name'] as String?,
    status: WaConnectionStatus.fromDb(m['status'] as String?),
    errorMessage: m['error_message'] as String?,
    lastHealthCheckAt: m['last_health_check_at'] != null
        ? DateTime.tryParse(m['last_health_check_at'] as String)
        : null,
    lastWebhookAt: m['last_webhook_at'] != null
        ? DateTime.tryParse(m['last_webhook_at'] as String)
        : null,
    lastMessageSentAt: m['last_message_sent_at'] != null
        ? DateTime.tryParse(m['last_message_sent_at'] as String)
        : null,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  @override
  List<Object?> get props => [id, status, connectionId, lastHealthCheckAt];
}

/// Input for creating/updating a connection.
/// Contains the sensitive credentials — used only when saving via Edge Function.
/// NEVER stored in Dart state after the initial save.
class WaConnectionInput {
  final String connectionId;
  final String apiKey;           // sent to Edge Function, never stored in Dart
  final String webhookSecret;    // sent to Edge Function, never stored in Dart
  final String apiBaseUrl;
  final String? phoneNumber;
  final String? displayName;

  const WaConnectionInput({
    required this.connectionId,
    required this.apiKey,
    required this.webhookSecret,
    required this.apiBaseUrl,
    this.phoneNumber,
    this.displayName,
  });
}

/// Health check result returned from Edge Function.
class WaHealthCheckResult {
  final bool isHealthy;
  final String? phoneNumber;
  final String? displayName;
  final String? errorMessage;
  final DateTime checkedAt;

  const WaHealthCheckResult({
    required this.isHealthy,
    this.phoneNumber,
    this.displayName,
    this.errorMessage,
    required this.checkedAt,
  });
}
