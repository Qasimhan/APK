import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/auth_state.dart';
import '../../core/scan/scan_feedback_provider.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/db/database_provider.dart';
import '../../core/network/secure_device_storage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionStatusProvider);
    final themeAsync = ref.watch(themeModeProvider);
    final scanFeedbackAsync = ref.watch(scanFeedbackProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          sessionAsync.when(
            data: (s) => s == null
                ? const Text('Not logged in')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Staff: ${s.staffName} (${s.staffRole})'),
                      const SizedBox(height: 4),
                      Text('ID: ${s.staffId}'),
                    ],
                  ),
            loading: () => const Text('Loading session...'),
            error: (_, __) => const Text('Error loading session'),
          ),
          const SizedBox(height: 24),
          const Text('Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          themeAsync.when(
            data: (mode) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.settings_brightness_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).setMode(selection.first),
            ),
            loading: () => const Text('Loading appearance'),
            error: (_, __) => const Text('Error loading appearance'),
          ),
          const SizedBox(height: 24),
          const Text('Scan Feedback',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          scanFeedbackAsync.when(
            data: (settings) => Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sound on scan'),
                  subtitle: const Text(
                      'Play a click when a barcode or QR code is detected'),
                  value: settings.soundEnabled,
                  onChanged: (value) => ref
                      .read(scanFeedbackProvider.notifier)
                      .setSoundEnabled(value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vibration on scan'),
                  subtitle: const Text(
                      'Vibrate briefly when a barcode or QR code is detected'),
                  value: settings.vibrationEnabled,
                  onChanged: (value) => ref
                      .read(scanFeedbackProvider.notifier)
                      .setVibrationEnabled(value),
                ),
              ],
            ),
            loading: () => const Text('Loading scan feedback settings...'),
            error: (_, __) =>
                const Text('Error loading scan feedback settings'),
          ),
          const SizedBox(height: 24),
          const Text('Account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer),
            onPressed: () async {
              // Clear the current session and navigate to onboarding login.
              await ref.read(databaseProvider).sessionDao.clearSession();
              await SecureDeviceStorage.clearSessionToken();
              if (context.mounted) context.go('/onboarding/login');
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}
