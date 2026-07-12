import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'staff_dao.g.dart';

@DriftAccessor(tables: [Staff])
class StaffDao extends DatabaseAccessor<AppDatabase> with _$StaffDaoMixin {
  StaffDao(super.db);

  /// Cached staff list (name + role only — no PINs stored on device)
  /// shown as tappable cards on the login screen.
  Future<List<StaffMember>> getStaffList() {
    return select(staff).get();
  }

  Stream<List<StaffMember>> watchStaffList() => select(staff).watch();

  /// Bulk-replaces the cached staff list, called right after pairing
  /// and on subsequent full syncs.
  Future<void> upsertStaff(List<StaffCompanion> rows) {
    return batch((b) {
      b.insertAllOnConflictUpdate(staff, rows);
    });
  }
}
