import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  /// Looks up a single cached product by scanned barcode. Returns null
  /// if the barcode isn't in the local cache (caller decides whether to
  /// fall back to a live PC lookup).
  Future<Product?> getProductByBarcode(String barcode) {
    return (select(products)..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Bulk-replaces the local product cache with a fresh pull from the
  /// PC (used right after pairing, and on every subsequent full sync).
  Future<void> upsertProducts(List<ProductsCompanion> rows) {
    return batch((b) {
      b.insertAllOnConflictUpdate(products, rows);
    });
  }

  /// Applies a single incremental stock/price update, e.g. from a
  /// WebSocket push (Phase 8) rather than a full re-sync.
  Future<void> upsertProduct(ProductsCompanion row) {
    return into(products).insertOnConflictUpdate(row);
  }

  Future<void> deleteProduct(int id) {
    return (delete(products)..where((p) => p.id.equals(id))).go();
  }

  Stream<List<Product>> watchAllProducts() => select(products).watch();

  Stream<List<Product>> watchProducts(String query) {
    final normalized = query.trim().toLowerCase();
    final statement = select(products)
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    if (normalized.isNotEmpty) {
      final pattern = '%$normalized%';
      statement.where((p) =>
          p.name.lower().like(pattern) | p.barcode.lower().like(pattern));
    }

    return statement.watch();
  }
}
