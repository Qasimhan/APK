import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';
import 'daos/product_dao.dart';
import 'daos/staff_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/session_dao.dart';
import 'daos/pairing_dao.dart';
import 'daos/shop_profile_dao.dart';

part 'db.g.dart';

@DriftDatabase(
  tables: [
    ShopProfile,
    Products,
    Staff,
    Sales,
    SaleItems,
    PendingActions,
    PairingConfig,
    SessionTable,
  ],
  daos: [
    ProductDao,
    StaffDao,
    SalesDao,
    SyncQueueDao,
    SessionDao,
    PairingDao,
    ShopProfileDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Used by unit tests to run fully in-memory, with no file I/O.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'pos_mobile.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
