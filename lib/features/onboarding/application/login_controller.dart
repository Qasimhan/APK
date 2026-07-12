import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pairing_controller.dart';

class LoginController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> login({
    required int staffId,
    required String staffName,
    required String staffRole,
    required String pin,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(onboardingRepositoryProvider).loginStaff(
            staffId: staffId,
            staffName: staffName,
            staffRole: staffRole,
            pin: pin,
          ),
    );
  }
}

final loginControllerProvider =
    AsyncNotifierProvider<LoginController, void>(LoginController.new);
