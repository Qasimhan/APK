import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../tables.dart';
import '../db.dart';

part 'sales_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Sales, SaleItems])
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.db);

  /// Creates a local sale record plus its line items in one transaction,
  /// and returns the client-generated sale id (also used as the
  /// idempotency key when this sale is later pushed to the PC).
  Future<String> createLocalSale({
    required double total,
    required String paymentMethod,
    required int staffId,
    required List<({int productId, int qty, double priceAtSale})> items,
  }) async {
    final saleId = _uuid.v4();

    await transaction(() async {
      await into(sales).insert(
        SalesCompanion.insert(
          id: saleId,
          total: total,
          paymentMethod: paymentMethod,
          staffId: staffId,
        ),
      );

      for (final item in items) {
        await into(saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: item.productId,
            qty: item.qty,
            priceAtSale: item.priceAtSale,
          ),
        );
      }
    });

    return saleId;
  }

  Future<Sale?> getSaleById(String id) {
    return (select(sales)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<List<SaleItem>> getItemsForSale(String saleId) {
    return (select(saleItems)..where((i) => i.saleId.equals(saleId))).get();
  }

  Future<void> updateSaleSyncStatus(String saleId, String status) {
    return (update(sales)..where((s) => s.id.equals(saleId))).write(
      SalesCompanion(syncStatus: Value(status)),
    );
  }

  Stream<List<Sale>> watchRecentSales({int limit = 50}) {
    return (select(sales)
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
          ..limit(limit))
        .watch();
  }
}
