import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/data/db/db.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Fully in-memory — no file I/O, fresh schema per test.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('ProductDao — barcode lookup', () {
    test('returns null for a barcode not in the cache', () async {
      final result = await db.productDao.getProductByBarcode('unknown-123');
      expect(result, isNull);
    });

    test('upsertProducts then getProductByBarcode finds the product', () async {
      await db.productDao.upsertProducts([
        ProductsCompanion.insert(
          id: const Value(1),
          barcode: '0123456789012',
          name: 'Cola 500ml',
          price: 1.5,
        ),
      ]);

      final result = await db.productDao.getProductByBarcode('0123456789012');
      expect(result, isNotNull);
      expect(result!.name, 'Cola 500ml');
      expect(result.price, 1.5);
    });

    test('upsertProducts updates an existing product on conflict', () async {
      await db.productDao.upsertProducts([
        ProductsCompanion.insert(
          id: const Value(1),
          barcode: '0123456789012',
          name: 'Cola 500ml',
          price: 1.5,
        ),
      ]);

      // Same id, new price — should overwrite, not duplicate.
      await db.productDao.upsertProducts([
        ProductsCompanion.insert(
          id: const Value(1),
          barcode: '0123456789012',
          name: 'Cola 500ml',
          price: 1.75,
        ),
      ]);

      final result = await db.productDao.getProductByBarcode('0123456789012');
      expect(result!.price, 1.75);
    });
  });

  group('SalesDao — local sale creation', () {
    test('createLocalSale writes the sale and its line items', () async {
      final saleId = await db.salesDao.createLocalSale(
        total: 9.5,
        paymentMethod: 'cash',
        staffId: 42,
        items: [
          (productId: 1, qty: 2, priceAtSale: 3.0),
          (productId: 2, qty: 1, priceAtSale: 3.5),
        ],
      );

      final sale = await db.salesDao.getSaleById(saleId);
      expect(sale, isNotNull);
      expect(sale!.total, 9.5);
      expect(sale.syncStatus, 'pending');

      final items = await db.salesDao.getItemsForSale(saleId);
      expect(items, hasLength(2));
      expect(items.map((i) => i.productId), containsAll([1, 2]));
    });

    test('updateSaleSyncStatus moves a sale from pending to synced', () async {
      final saleId = await db.salesDao.createLocalSale(
        total: 5.0,
        paymentMethod: 'card',
        staffId: 1,
        items: [(productId: 1, qty: 1, priceAtSale: 5.0)],
      );

      await db.salesDao.updateSaleSyncStatus(saleId, 'synced');

      final sale = await db.salesDao.getSaleById(saleId);
      expect(sale!.syncStatus, 'synced');
    });
  });

  group('SessionDao — read/write current session', () {
    test('getCurrentSession returns null when no one is logged in', () async {
      final session = await db.sessionDao.getCurrentSession();
      expect(session, isNull);
    });

    test('setSession then getCurrentSession returns the logged-in staff',
        () async {
      await db.sessionDao.setSession(
        staffId: 7,
        staffName: 'Amina',
        staffRole: 'cashier',
      );

      final session = await db.sessionDao.getCurrentSession();
      expect(session, isNotNull);
      expect(session!.staffName, 'Amina');
      expect(session.staffRole, 'cashier');
    });

    test('setSession replaces any previous session (only one row kept)',
        () async {
      await db.sessionDao.setSession(
        staffId: 7,
        staffName: 'Amina',
        staffRole: 'cashier',
      );
      await db.sessionDao.setSession(
        staffId: 9,
        staffName: 'Bilal',
        staffRole: 'manager',
      );

      final session = await db.sessionDao.getCurrentSession();
      expect(session!.staffId, 9);
      expect(session.staffName, 'Bilal');
    });

    test('clearSession logs the staff member out', () async {
      await db.sessionDao.setSession(
        staffId: 7,
        staffName: 'Amina',
        staffRole: 'cashier',
      );
      await db.sessionDao.clearSession();

      final session = await db.sessionDao.getCurrentSession();
      expect(session, isNull);
    });
  });
}
