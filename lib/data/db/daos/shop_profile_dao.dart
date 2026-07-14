import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'shop_profile_dao.g.dart';

@DriftAccessor(tables: [ShopProfile])
class ShopProfileDao extends DatabaseAccessor<AppDatabase>
    with _$ShopProfileDaoMixin {
  ShopProfileDao(super.db);

  /// Single-row cache — there's only ever one shop profile on a paired
  /// device.
  Future<ShopProfileData?> getShopProfile() {
    return select(shopProfile).getSingleOrNull();
  }

  Stream<ShopProfileData?> watchShopProfile() {
    return select(shopProfile).watchSingleOrNull();
  }

  /// Replaces the cached shop profile after a successful sync pull.
  Future<void> setShopProfile(ShopProfileCompanion row) async {
    await transaction(() async {
      await delete(shopProfile).go();
      await into(shopProfile).insert(row);
    });
  }
}
