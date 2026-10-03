import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voice on/off state.
/// Default: on. Owner can toggle in settings.
/// When off: no automatic TTS, but manual 🔊 taps still work.
class VoiceStateNotifier extends AsyncNotifier<bool> {
  static const _key = 'munshi_voice_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? true;
    await setEnabled(!current);
  }
}

final voiceStateProvider = AsyncNotifierProvider<VoiceStateNotifier, bool>(
  VoiceStateNotifier.new,
);

final voiceEnabledProvider = Provider<bool>((ref) {
  return ref.watch(voiceStateProvider).valueOrNull ?? true;
});
