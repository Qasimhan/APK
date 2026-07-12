import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database_provider.dart';
import '../../../core/network/api_client.dart';
import '../data/onboarding_repository.dart';

/// Last pairing error message (for debug UI). Null when last pairing
/// attempt succeeded or no attempt has been made.
final lastPairingErrorProvider = StateProvider<String?>((_) => null);

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(databaseProvider));
});

/// Drives the "Setting up your shop..." loading state on the scan
/// screen: exchanges the QR token, then pulls shop profile + catalog +
/// staff in one AsyncValue the UI can watch directly.
class PairingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // No-op initial state — pairing only starts when pairFromQr is called.
  }

  Future<void> pairFromQr(PairingQrPayload payload) async {
    state = const AsyncLoading();
    // Clear previous error
    ref.read(lastPairingErrorProvider.notifier).state = null;
    try {
      await ref.read(onboardingRepositoryProvider).pairAndSync(payload);
      state = const AsyncData(null);
    } catch (e, st) {
      // Record a human-friendly message for the debug screen
      final message = e is PosApiException ? e.message : e.toString();
      ref.read(lastPairingErrorProvider.notifier).state = message;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refreshSync() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(onboardingRepositoryProvider).refreshSync(),
    );
  }
}

final pairingControllerProvider =
    AsyncNotifierProvider<PairingController, void>(PairingController.new);
