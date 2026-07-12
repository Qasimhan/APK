import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'session_dao.g.dart';

@DriftAccessor(tables: [SessionTable])
class SessionDao extends DatabaseAccessor<AppDatabase>
    with _$SessionDaoMixin {
  SessionDao(super.db);

  /// There's only ever one active session row on the device at a time.
  Future<ActiveSession?> getCurrentSession() {
    return select(sessionTable).getSingleOrNull();
  }

  Stream<ActiveSession?> watchCurrentSession() {
    return select(sessionTable).watchSingleOrNull();
  }

  /// Replaces the current session (e.g. after a successful PIN login).
  /// Only one row is ever kept — clear then insert.
  Future<void> setSession({
    required int staffId,
    required String staffName,
    required String staffRole,
  }) async {
    await transaction(() async {
      await delete(sessionTable).go();
      await into(sessionTable).insert(
        SessionTableCompanion.insert(
          staffId: staffId,
          staffName: staffName,
          staffRole: staffRole,
        ),
      );
    });
  }

  /// Logs the current staff member out. Pairing (pairing_config) is
  /// untouched — only the active session ends.
  Future<void> clearSession() {
    return delete(sessionTable).go();
  }
}
