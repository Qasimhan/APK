import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanFeedbackSettings {
  const ScanFeedbackSettings({
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  final bool soundEnabled;
  final bool vibrationEnabled;
}

class ScanFeedbackNotifier extends AsyncNotifier<ScanFeedbackSettings> {
  static const _soundKey = 'scan_feedback_sound_enabled';
  static const _vibrationKey = 'scan_feedback_vibration_enabled';

  @override
  Future<ScanFeedbackSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return ScanFeedbackSettings(
      soundEnabled: prefs.getBool(_soundKey) ?? true,
      vibrationEnabled: prefs.getBool(_vibrationKey) ?? true,
    );
  }

  Future<void> setSoundEnabled(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      ScanFeedbackSettings(
        soundEnabled: value,
        vibrationEnabled: current.vibrationEnabled,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
  }

  Future<void> setVibrationEnabled(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      ScanFeedbackSettings(
        soundEnabled: current.soundEnabled,
        vibrationEnabled: value,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationKey, value);
  }
}

final scanFeedbackProvider =
    AsyncNotifierProvider<ScanFeedbackNotifier, ScanFeedbackSettings>(
  () => ScanFeedbackNotifier(),
);

Future<void> playScanFeedback(ScanFeedbackSettings settings) async {
  if (settings.vibrationEnabled) {
    await HapticFeedback.mediumImpact();
  }
  if (settings.soundEnabled) {
    await SystemSound.play(SystemSoundType.click);
  }
}
