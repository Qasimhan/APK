import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/db/db.dart';

/// True once the device has completed pairing (a row exists in
/// pairing_config). Feeds the router guard's first branch.
final pairingStatusProvider = StreamProvider<PairingConfigData?>((ref) {
  return ref.watch(databaseProvider).pairingDao.watchPairingConfig();
});

/// True once a staff member has an active local session. Feeds the
/// router guard's second branch.
final sessionStatusProvider = StreamProvider<ActiveSession?>((ref) {
  return ref.watch(databaseProvider).sessionDao.watchCurrentSession();
});
