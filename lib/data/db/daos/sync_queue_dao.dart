import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [PendingActions])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  /// Enqueues an offline action (sale / stock_adjust / product_create /
  /// product_update) with its JSON payload, to be pushed once
  /// connectivity to the PC is available (Phase 8).
  Future<int> enqueue({
    required String actionType,
    required String payloadJson,
  }) {
    return into(pendingActions).insert(
      PendingActionsCompanion.insert(
        actionType: actionType,
        payload: payloadJson,
      ),
    );
  }

  /// All actions still waiting to be sent, oldest first — so retries
  /// preserve the original order of operations.
  Future<List<PendingAction>> getPendingActions() {
    return (select(pendingActions)
          ..where((a) => a.syncStatus.equals('pending'))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .get();
  }

  Future<void> markActionSynced(int id) {
    return (update(pendingActions)..where((a) => a.id.equals(id))).write(
      const PendingActionsCompanion(syncStatus: Value('synced')),
    );
  }

  Future<void> markActionRejected(int id) {
    return (update(pendingActions)..where((a) => a.id.equals(id))).write(
      const PendingActionsCompanion(syncStatus: Value('rejected')),
    );
  }

  /// Dequeues (deletes) a synced action once it's been fully processed
  /// and there's no further need to keep it around for inspection.
  Future<void> dequeue(int id) {
    return (delete(pendingActions)..where((a) => a.id.equals(id))).go();
  }

  Stream<List<PendingAction>> watchPendingActions() {
    return (select(pendingActions)
          ..where((a) => a.syncStatus.equals('pending')))
        .watch();
  }
}
