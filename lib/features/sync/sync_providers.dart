import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import 'sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.read(databaseProvider);
  final svc = SyncService(db);
  ref.onDispose(() => svc.dispose());
  return svc;
});

final pendingActionsCountProvider = StreamProvider<int>((ref) {
  final db = ref.read(databaseProvider);
  // Watch pending actions and return count
  return db.syncQueueDao.watchPendingActions().map((list) => list.length);
});
