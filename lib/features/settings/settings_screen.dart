import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/auth_state.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/db/database_provider.dart';
import '../../core/network/secure_device_storage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionStatusProvider);
    final themeAsync = ref.watch(themeModeProvider);

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
            data: (mode) => Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: mode,
                  onChanged: (v) => ref
                      .read(themeModeProvider.notifier)
                      .setMode(v ?? ThemeMode.system),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: mode,
                  onChanged: (v) => ref
                      .read(themeModeProvider.notifier)
                      .setMode(v ?? ThemeMode.system),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System'),
                  value: ThemeMode.system,
                  groupValue: mode,
                  onChanged: (v) => ref
                      .read(themeModeProvider.notifier)
                      .setMode(v ?? ThemeMode.system),
                ),
              ],
            ),
            loading: () => const Text('Loading appearance'),
            error: (_, __) => const Text('Error loading appearance'),
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
