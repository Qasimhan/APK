import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';

/// One AppDatabase instance for the lifetime of the app. Every DAO
/// (product, staff, sales, pairing, session, sync queue, shop profile)
/// hangs off this same instance so writes in one screen are
/// immediately visible to watchers in another.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
