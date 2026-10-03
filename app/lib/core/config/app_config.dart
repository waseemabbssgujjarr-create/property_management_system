import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central app configuration loaded from environment.
/// Never hardcode values here — always read from .env files.
class AppConfig {
  AppConfig._();

  static late AppConfig _instance;
  static AppConfig get instance => _instance;

  late final String supabaseUrl;
  late final String supabaseAnonKey;
  late final AppEnvironment environment;
  late final String appName;
  late final FeatureFlags features;

  static Future<void> load(AppEnvironment env) async {
    final file = switch (env) {
      AppEnvironment.development => '.env.dev',
      AppEnvironment.staging => '.env.staging',
      AppEnvironment.production => '.env.prod',
    };
    await dotenv.load(fileName: file);

    _instance = AppConfig._()
      ..supabaseUrl = dotenv.env['SUPABASE_URL']!
      ..supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!
      ..environment = env
      ..appName = dotenv.env['APP_NAME'] ?? 'Munshi'
      ..features = FeatureFlags.fromEnv();
  }

  bool get isDev => environment == AppEnvironment.development;
  bool get isStaging => environment == AppEnvironment.staging;
  bool get isProd => environment == AppEnvironment.production;
}

enum AppEnvironment { development, staging, production }

/// Feature flags — read from env at startup, overridable at runtime via
/// Supabase app_config table (loaded after auth).
class FeatureFlags {
  final bool whatsApp;
  final bool demandMatching;
  final bool dealerCircles;
  final bool documents;
  final bool webConsole;
  final bool billing;

  const FeatureFlags({
    required this.whatsApp,
    required this.demandMatching,
    required this.dealerCircles,
    required this.documents,
    required this.webConsole,
    required this.billing,
  });

  factory FeatureFlags.fromEnv() {
    bool flag(String key, {bool def = false}) {
      final v = dotenv.env[key];
      if (v == null) return def;
      return v.toLowerCase() == 'true';
    }

    return FeatureFlags(
      whatsApp: flag('FEATURE_WHATSAPP'),
      demandMatching: flag('FEATURE_DEMAND_MATCHING'),
      dealerCircles: flag('FEATURE_DEALER_CIRCLES'),
      documents: flag('FEATURE_DOCUMENTS', def: true),
      webConsole: flag('FEATURE_WEB_CONSOLE'),
      billing: flag('FEATURE_BILLING', def: true),
    );
  }

  /// Override from server-side app_config table
  FeatureFlags copyWith({
    bool? whatsApp,
    bool? demandMatching,
    bool? dealerCircles,
    bool? documents,
    bool? webConsole,
    bool? billing,
  }) {
    return FeatureFlags(
      whatsApp: whatsApp ?? this.whatsApp,
      demandMatching: demandMatching ?? this.demandMatching,
      dealerCircles: dealerCircles ?? this.dealerCircles,
      documents: documents ?? this.documents,
      webConsole: webConsole ?? this.webConsole,
      billing: billing ?? this.billing,
    );
  }
}
