import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple vs Detail mode — determines which UI level to show.
/// Simple: 3 big buttons, voice-first, icon-first (default, owner).
/// Detail: full screens, tables, forms (munshi/manager).
///
/// CRITICAL: persisted across restarts so an owner who sets Simple mode
/// always sees Simple mode on app launch — never a detail screen accidentally.
enum AppMode { simple, detail }

class AppModeNotifier extends AsyncNotifier<AppMode> {
  static const _key = 'munshi_app_mode';

  @override
  Future<AppMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    return stored == 'detail' ? AppMode.detail : AppMode.simple;
  }

  Future<void> setMode(AppMode mode) async {
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> toggleMode() async {
    final current = state.valueOrNull ?? AppMode.simple;
    await setMode(current == AppMode.simple ? AppMode.detail : AppMode.simple);
  }
}

final appModeProvider = AsyncNotifierProvider<AppModeNotifier, AppMode>(
  AppModeNotifier.new,
);

/// Convenience sync accessor (returns simple if not yet loaded).
final appModeSyncProvider = Provider<AppMode>((ref) {
  return ref.watch(appModeProvider).valueOrNull ?? AppMode.simple;
});
