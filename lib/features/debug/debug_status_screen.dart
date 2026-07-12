import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/secure_device_storage.dart';
import '../../../core/network/auth_state.dart';
import '../../../data/db/database_provider.dart';
import '../../../features/sync/sync_providers.dart';
import '../onboarding/data/onboarding_repository.dart';
import '../onboarding/application/pairing_controller.dart';

class DebugStatusScreen extends ConsumerStatefulWidget {
  const DebugStatusScreen({super.key});

  @override
  ConsumerState<DebugStatusScreen> createState() => _DebugStatusScreenState();
}

class _DebugStatusScreenState extends ConsumerState<DebugStatusScreen> {
  String? _lastSyncMessage;

  Future<void> _doRefresh() async {
    setState(() {
      _lastSyncMessage = null;
    });

    final db = ref.read(databaseProvider);
    final repo = OnboardingRepository(db);
    try {
      await repo.refreshSync();
      setState(() {
        _lastSyncMessage = 'Refresh sync completed successfully.';
      });
    } catch (e) {
      setState(() {
        _lastSyncMessage = 'Refresh sync failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairingAsync = ref.watch(pairingStatusProvider);
    final sessionAsync = ref.watch(sessionStatusProvider);
    final pendingAsync = ref.watch(pendingActionsCountProvider);
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Status'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Connection & Tokens',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            pairingAsync.when(
              data: (pairing) {
                if (pairing == null) return const Text('Pairing: Not paired');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paired to: ${pairing.pcIp}:${pairing.pcPort}'),
                    Text(
                        'Pairing token (stored): ${pairing.pairingToken.substring(0, pairing.pairingToken.length > 8 ? 8 : pairing.pairingToken.length)}...'),
                    Text('Paired at: ${pairing.pairedAt}'),
                  ],
                );
              },
              loading: () => const Text('Pairing: loading...'),
              error: (e, s) => Text('Pairing: error: $e'),
            ),
            const SizedBox(height: 12),
            // Show last pairing error if any (set by PairingController)
            Builder(builder: (context) {
              final lastPairErr = ref.watch(lastPairingErrorProvider);
              if (lastPairErr == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('Last pairing error:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(lastPairErr),
                ],
              );
            }),
            FutureBuilder<String?>(
              future: SecureDeviceStorage.readDeviceToken(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done)
                  return const Text('Device token: checking...');
                final token = snap.data;
                return Text(
                    'Device token: ${token == null ? 'not stored' : '${token.substring(0, token.length > 8 ? 8 : token.length)}...'}');
              },
            ),
            FutureBuilder<String?>(
              future: SecureDeviceStorage.readSessionToken(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done)
                  return const Text('Session token: checking...');
                final token = snap.data;
                return Text(
                    'Session token: ${token == null ? 'not stored' : '${token.substring(0, token.length > 8 ? 8 : token.length)}...'}');
              },
            ),
            const SizedBox(height: 20),
            const Text('Local Cache',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StreamBuilder<int>(
              stream: db.productDao.watchAllProducts().map((l) => l.length),
              builder: (context, snap) {
                if (!snap.hasData) return const Text('Products: loading...');
                return Text('Products: ${snap.data}');
              },
            ),
            StreamBuilder<int>(
              stream: db.staffDao.watchStaffList().map((l) => l.length),
              builder: (context, snap) {
                if (!snap.hasData) return const Text('Staff: loading...');
                return Text('Staff: ${snap.data}');
              },
            ),
            const SizedBox(height: 12),
            pendingAsync.when(
              data: (count) => Text('Pending actions: $count'),
              loading: () => const Text('Pending actions: loading...'),
              error: (e, s) => Text('Pending actions: error: $e'),
            ),
            const SizedBox(height: 20),
            const Text('Session State',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            sessionAsync.when(
              data: (session) {
                if (session == null)
                  return const Text('No active session (logged out)');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Staff: ${session.staffName} (id ${session.staffId})'),
                    Text('Role: ${session.staffRole}'),
                    Text('Logged in at: ${session.loggedInAt}'),
                  ],
                );
              },
              loading: () => const Text('Session: loading...'),
              error: (e, s) => Text('Session: error: $e'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await _doRefresh();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_lastSyncMessage ?? 'Done')));
                  },
                  child: const Text('Refresh sync'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    // Clear stored tokens for quick testing
                    await SecureDeviceStorage.clearSessionToken();
                    await SecureDeviceStorage.clearDeviceToken();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cleared stored tokens')));
                    setState(() {});
                  },
                  child: const Text('Clear tokens'),
                ),
              ],
            ),
            if (_lastSyncMessage != null) ...[
              const SizedBox(height: 12),
              Text('Last: $_lastSyncMessage'),
            ],
            const SizedBox(height: 40),
            const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'If staff list is empty: add staff on the desktop app, then tap Refresh sync.'),
            const SizedBox(height: 8),
            const Text(
                'If pairing is missing: go through onboarding Pairing flow (scan QR from desktop).'),
          ],
        ),
      ),
    );
  }
}
