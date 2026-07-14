import 'package:drift/drift.dart';

// -----------------------------------------------------------------------
// Table definitions — mirrors the desktop app's schema for the subset
// of data the phone needs to cache locally.
// -----------------------------------------------------------------------

/// Single-row cache of the shop's profile info.
@DataClassName('ShopProfileData')
class ShopProfile extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get logoUrl => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
}

/// Cached product catalog, keyed by the desktop's product id.
class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get barcode => text().unique()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  // Local cached file path for the product image, not a remote URL —
  // populated by the sync layer after downloading the image once.
  TextColumn get imagePath => text().nullable()();
  RealColumn get price => real()();
  IntColumn get stockQty => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached staff list for the login screen. No PIN stored locally —
/// PIN is always verified server-side against the PC.
///
/// Named `StaffMember` for the generated row class since "Staff" has no
/// distinct singular form and would otherwise collide with this Table
/// class's own name.
@DataClassName('StaffMember')
class Staff extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get role => text()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local sale history / receipts created on this device.
class Sales extends Table {
  TextColumn get id => text()(); // client-generated UUID (idempotency key)
  RealColumn get total => real()();
  TextColumn get paymentMethod => text()();
  IntColumn get staffId => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // pending | synced | failed | rejected
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Line items belonging to a local sale.
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get saleId =>
      text().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer()();
  IntColumn get qty => integer()();
  RealColumn get priceAtSale => real()();
}

/// Offline action queue — anything that needs to reach the PC but
/// hasn't been confirmed yet (sale, stock adjustment, product change).
class PendingActions extends Table {
  IntColumn get id => integer().autoIncrement()();
  // sale | stock_adjust | product_create | product_update
  TextColumn get actionType => text()();
  TextColumn get payload => text()(); // JSON-encoded
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // pending | synced | failed | rejected
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
}

/// Single-row record of this device's pairing with a PC.
@DataClassName('PairingConfigData')
class PairingConfig extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get pcIp => text()();
  IntColumn get pcPort => integer()();
  TextColumn get pairingToken => text()();
  DateTimeColumn get pairedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Single-row record of the currently logged-in staff member.
/// Cleared on logout; pairing itself is untouched by logout.
@DataClassName('ActiveSession')
class SessionTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get staffId => integer()();
  TextColumn get staffName => text()();
  TextColumn get staffRole => text()();
  DateTimeColumn get loggedInAt => dateTime().withDefault(currentDateAndTime)();
}
