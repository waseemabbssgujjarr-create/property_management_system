import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/services/permission_service.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../models/wa_connection_models.dart';
import '../repositories/wa_connection_repository.dart';

/// WhatsApp Connection Setup Screen.
///
/// Allows owner/manager to:
/// - Connect their WhatsApp account via our WA API
/// - View connection status (phone, display name, last health check)
/// - Test the connection
/// - Disconnect
///
/// Security rules:
/// - Connection ID shown masked after save (no full ID displayed)
/// - API key and webhook secret are ONE-WAY — entered here, sent to Edge Function,
///   never displayed again after save (not even masked)
/// - Only owner/manager role can access this screen
class WaConnectScreen extends ConsumerStatefulWidget {
  const WaConnectScreen({super.key});

  @override
  ConsumerState<WaConnectScreen> createState() => _WaConnectScreenState();
}

class _WaConnectScreenState extends ConsumerState<WaConnectScreen> {
  final _connectionIdCtrl  = TextEditingController();
  final _apiKeyCtrl         = TextEditingController();
  final _webhookSecretCtrl  = TextEditingController();
  final _apiBaseUrlCtrl     = TextEditingController(
    text: 'https://api.ourwhatsapp.example.com/v1',
  );

  bool _showApiKey        = false;
  bool _showWebhookSecret = false;
  bool _saving            = false;
  bool _testing           = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _connectionIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _apiBaseUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Permission check — owner or manager only
    final perms = ref.watch(permissionServiceProvider);
    if (perms.cannot(Permission.manageWhatsApp)) {
      return Scaffold(
        appBar: AppBar(title: Text('واٹس ایپ', style: AppTypography.urH2)),
        body: const ErrorState(
          messageUr: 'صرف مالک یا مینیجر واٹس ایپ جوڑ سکتا ہے',
          speakText: 'صرف مالک یا مینیجر واٹس ایپ کنیکشن ترتیب دے سکتا ہے',
        ),
      );
    }

    final session = ref.watch(currentSessionProvider);
    final connectionAsync = ref.watch(waConnectionProvider(session?.dealerId ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: Text('واٹس ایپ', style: AppTypography.urH2),
      ),
      body: connectionAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 3, itemHeight: 80),
        ),
        error: (e, _) => ErrorState.generic(
          onRetry: () => ref.invalidate(waConnectionProvider(session?.dealerId ?? '')),
        ),
        data: (connection) => connection != null && connection.status.isConnected
            ? _ConnectedView(
                connection: connection,
                onTest: () => _testConnection(connection),
                onDisconnect: () => _disconnect(connection),
                testing: _testing,
                error: _error,
                successMessage: _successMessage,
              )
            : _ConnectForm(
                connectionIdCtrl: _connectionIdCtrl,
                apiKeyCtrl: _apiKeyCtrl,
                webhookSecretCtrl: _webhookSecretCtrl,
                apiBaseUrlCtrl: _apiBaseUrlCtrl,
                showApiKey: _showApiKey,
                showWebhookSecret: _showWebhookSecret,
                saving: _saving,
                error: _error,
                onToggleApiKey: () => setState(() => _showApiKey = !_showApiKey),
                onToggleWebhookSecret: () =>
                    setState(() => _showWebhookSecret = !_showWebhookSecret),
                onConnect: _connect,
              ),
      ),
    );
  }

  Future<void> _connect() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    if (_connectionIdCtrl.text.trim().isEmpty ||
        _apiKeyCtrl.text.trim().isEmpty ||
        _webhookSecretCtrl.text.trim().isEmpty) {
      setState(() => _error = 'تمام فیلڈز ضروری ہیں');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final input = WaConnectionInput(
        connectionId:  _connectionIdCtrl.text.trim(),
        apiKey:        _apiKeyCtrl.text.trim(),
        webhookSecret: _webhookSecretCtrl.text.trim(),
        apiBaseUrl:    _apiBaseUrlCtrl.text.trim(),
      );

      await ref.read(waConnectionRepositoryProvider).connect(
        dealerId:    session.dealerId,
        input:       input,
        connectedBy: session.userId,
      );

      // Clear sensitive fields immediately after save
      // They are now encrypted server-side and unretrievable from this client
      _apiKeyCtrl.clear();
      _webhookSecretCtrl.clear();

      HapticFeedback.heavyImpact();
      ref.invalidate(waConnectionProvider(session.dealerId));

      if (mounted) {
        setState(() {
          _saving = false;
          _successMessage = 'واٹس ایپ جڑ گیا';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceAll(RegExp(r'^.*Exception: '), '');
        });
      }
    }
  }

  Future<void> _testConnection(WaConnection connection) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() { _testing = true; _error = null; _successMessage = null; });

    final result = await ref.read(waConnectionRepositoryProvider).testConnection(
      dealerId:     session.dealerId,
      connectionId: connection.connectionId,
    );

    ref.invalidate(waConnectionProvider(session.dealerId));

    if (mounted) {
      setState(() {
        _testing = false;
        if (result.isHealthy) {
          _successMessage = 'کنیکشن ٹھیک ہے ✓';
        } else {
          _error = result.errorMessage ?? 'کنیکشن مسئلہ';
        }
      });
    }
  }

  Future<void> _disconnect(WaConnection connection) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('واٹس ایپ منقطع کریں؟', style: AppTypography.urH2),
        content: Text(
          'تمام پرانے پیغامات محفوظ رہیں گے۔ صرف نئے پیغام رک جائیں گے۔',
          style: AppTypography.urBody,
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('منسوخ', style: AppTypography.urBody),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('منقطع کریں', style: AppTypography.urBodyBold),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await ref.read(waConnectionRepositoryProvider).disconnect(
      dealerId:     session.dealerId,
      connectionId: connection.connectionId,
      disconnectedBy: session.userId,
    );

    ref.invalidate(waConnectionProvider(session.dealerId));
  }
}

// ── Connected state view ──────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  final WaConnection connection;
  final VoidCallback onTest;
  final VoidCallback onDisconnect;
  final bool testing;
  final String? error;
  final String? successMessage;

  const _ConnectedView({
    required this.connection,
    required this.onTest,
    required this.onDisconnect,
    required this.testing,
    this.error,
    this.successMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.success.withAlpha(15),
              borderRadius: AppSpacing.cardRadius,
              border: Border.all(color: AppColors.success.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('جڑا ہوا',
                        style: AppTypography.urBodyBold
                            .copyWith(color: AppColors.success)),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                if (connection.phoneNumber != null)
                  _InfoRow('فون', connection.phoneNumber!),
                if (connection.displayName != null)
                  _InfoRow('نام', connection.displayName!),
                // Show masked connection ID — never full ID
                _InfoRow('کنیکشن', connection.maskedConnectionId),
                if (connection.lastHealthCheckAt != null)
                  _InfoRow(
                    'آخری چیک',
                    _formatDateTime(connection.lastHealthCheckAt!),
                  ),
                if (connection.lastWebhookAt != null)
                  _InfoRow(
                    'آخری پیغام',
                    _formatDateTime(connection.lastWebhookAt!),
                  ),
              ],
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: AppSpacing.base),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(15),
                borderRadius: AppSpacing.cardRadius,
              ),
              child: Text(error!,
                  style: AppTypography.urBody.copyWith(color: AppColors.danger),
                  textDirection: TextDirection.rtl),
            ),
          ],

          if (successMessage != null) ...[
            const SizedBox(height: AppSpacing.base),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(15),
                borderRadius: AppSpacing.cardRadius,
              ),
              child: Text(successMessage!,
                  style: AppTypography.urBody.copyWith(color: AppColors.success),
                  textDirection: TextDirection.rtl),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // Test button
          OutlinedButton.icon(
            onPressed: testing ? null : onTest,
            icon: testing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering_rounded),
            label: Text(testing ? 'چیک ہو رہا ہے...' : 'کنیکشن چیک کریں',
                style: AppTypography.urBodyMedium),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Disconnect button
          OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
            label: Text('منقطع کریں',
                style: AppTypography.urBodyMedium.copyWith(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.urBody.copyWith(color: AppColors.ink500)),
          Text(value,
              style: AppTypography.urBodyMedium,
              textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

// ── Connect form ──────────────────────────────────────────────────────────

class _ConnectForm extends StatelessWidget {
  final TextEditingController connectionIdCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController webhookSecretCtrl;
  final TextEditingController apiBaseUrlCtrl;
  final bool showApiKey;
  final bool showWebhookSecret;
  final bool saving;
  final String? error;
  final VoidCallback onToggleApiKey;
  final VoidCallback onToggleWebhookSecret;
  final VoidCallback onConnect;

  const _ConnectForm({
    required this.connectionIdCtrl,
    required this.apiKeyCtrl,
    required this.webhookSecretCtrl,
    required this.apiBaseUrlCtrl,
    required this.showApiKey,
    required this.showWebhookSecret,
    required this.saving,
    this.error,
    required this.onToggleApiKey,
    required this.onToggleWebhookSecret,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: AppSpacing.cardRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('واٹس ایپ جوڑنے کا طریقہ',
                    style: AppTypography.urBodyBold,
                    textDirection: TextDirection.rtl),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '١. اپنے واٹس ایپ API پلیٹ فارم سے Connection ID، API Key اور Webhook Secret لیں\n'
                  '٢. نیچے درج کریں\n'
                  '٣. "جوڑیں" دبائیں — کریڈنشل محفوظ اور خفیہ ہو جائیں گے',
                  style: AppTypography.urBody,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Connection ID
          TextField(
            controller: connectionIdCtrl,
            textDirection: TextDirection.ltr,
            style: AppTypography.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Connection ID',
              hintText: 'e.g. conn_abc123xyz',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.base),

          // API Base URL
          TextField(
            controller: apiBaseUrlCtrl,
            textDirection: TextDirection.ltr,
            style: AppTypography.body,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.example.com/v1',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.base),

          // API Key — obscured, one-way
          TextField(
            controller: apiKeyCtrl,
            obscureText: !showApiKey,
            textDirection: TextDirection.ltr,
            style: AppTypography.body,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'ایک بار درج کریں — بعد میں نہیں دیکھا جائے گا',
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              suffixIcon: IconButton(
                icon: Icon(showApiKey ? Icons.visibility_off : Icons.visibility),
                onPressed: onToggleApiKey,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'محفوظ ہونے کے بعد API Key دوبارہ نہیں دیکھا جا سکتا',
            style: AppTypography.caption.copyWith(color: AppColors.warn),
          ),
          const SizedBox(height: AppSpacing.base),

          // Webhook Secret — obscured, one-way
          TextField(
            controller: webhookSecretCtrl,
            obscureText: !showWebhookSecret,
            textDirection: TextDirection.ltr,
            style: AppTypography.body,
            decoration: InputDecoration(
              labelText: 'Webhook Secret',
              hintText: 'ایک بار درج کریں',
              prefixIcon: const Icon(Icons.security_rounded),
              suffixIcon: IconButton(
                icon: Icon(showWebhookSecret
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: onToggleWebhookSecret,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Webhook Secret محفوظ ہونے کے بعد دوبارہ نہیں دیکھا جا سکتا',
            style: AppTypography.caption.copyWith(color: AppColors.warn),
          ),

          if (error != null) ...[
            const SizedBox(height: AppSpacing.base),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(15),
                borderRadius: AppSpacing.cardRadius,
              ),
              child: Text(error!,
                  style: AppTypography.urBody.copyWith(color: AppColors.danger),
                  textDirection: TextDirection.rtl),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          ElevatedButton.icon(
            onPressed: saving ? null : onConnect,
            icon: saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.link_rounded),
            label: Text(saving ? 'جوڑا جا رہا ہے...' : 'واٹس ایپ جوڑیں',
                style: AppTypography.urBodyBold),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: AppColors.brand600,
            ),
          ),
        ],
      ),
    );
  }
}
