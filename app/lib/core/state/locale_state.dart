import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App locale state — persisted.
/// Default: ur (Urdu) — always. English is the toggle, never the default.
class LocaleNotifier extends AsyncNotifier<Locale> {
  static const _key = 'munshi_locale';

  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    return stored == 'en' ? const Locale('en') : const Locale('ur');
  }

  Future<void> setLocale(Locale locale) async {
    state = AsyncData(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }

  Future<void> toggleLocale() async {
    final current = state.valueOrNull ?? const Locale('ur');
    await setLocale(
      current.languageCode == 'ur' ? const Locale('en') : const Locale('ur'),
    );
  }
}

final localeProvider = AsyncNotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);

final localeSyncProvider = Provider<Locale>((ref) {
  return ref.watch(localeProvider).valueOrNull ?? const Locale('ur');
});

extension LocaleX on Locale {
  bool get isUrdu => languageCode == 'ur';
  bool get isEnglish => languageCode == 'en';
  TextDirection get textDirection =>
      isUrdu ? TextDirection.rtl : TextDirection.ltr;
}
