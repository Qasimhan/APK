import 'package:drift/drift.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/secure_device_storage.dart';
import '../../../data/db/db.dart';

/// QR payload scanned from the desktop app's pairing screen (Desktop
/// Phase 6): `{ "ip": "...", "port": ..., "token": "..." }`.
class PairingQrPayload {
  final String ip;
  final int port;
  final String token;

  PairingQrPayload({required this.ip, required this.port, required this.token});

  factory PairingQrPayload.fromJson(Map<String, dynamic> json) {
    return PairingQrPayload(
      ip: json['ip'] as String,
      port: json['port'] as int,
      token: json['token'] as String,
    );
  }
}

class OnboardingRepository {
  OnboardingRepository(this._db);

  final AppDatabase _db;

  /// Full pairing sequence: exchange the scanned QR token for a
  /// long-lived device token, persist it, then immediately pull and
  /// cache shop profile + product catalog + staff list.
  ///
  /// Throws [PosApiException] on any network/auth failure — the caller
  /// (PairingController) is responsible for surfacing that to the UI.
  Future<void> pairAndSync(PairingQrPayload qr) async {
    final client = PosApiClient(ip: qr.ip, port: qr.port);
    final deviceToken = await client.exchangePairingToken(qr.token);

    await SecureDeviceStorage.saveDeviceToken(deviceToken);
    await _db.pairingDao.setPairingConfig(
      pcIp: qr.ip,
      pcPort: qr.port,
      pairingToken: deviceToken,
    );

    await _pullInitialSync(ip: qr.ip, port: qr.port, deviceToken: deviceToken);
  }

  /// Re-runs just the sync pull using the already-stored pairing info
  /// (e.g. a manual "refresh catalog" action from Settings later on).
  Future<void> refreshSync() async {
    final config = await _db.pairingDao.getPairingConfig();
    if (config == null) {
      throw const PosApiException('Device is not paired yet.');
    }
    await _pullInitialSync(
      ip: config.pcIp,
      port: config.pcPort,
      deviceToken: config.pairingToken,
    );
  }

  Future<void> _pullInitialSync({
    required String ip,
    required int port,
    required String deviceToken,
  }) async {
    final client = PosApiClient(ip: ip, port: port, deviceToken: deviceToken);
    final payload = await client.fetchInitialSync(deviceToken);

    final profile = payload.shopProfile;
    await _db.shopProfileDao.setShopProfile(
      ShopProfileCompanion.insert(
        name: profile['name'] as String,
        address: Value(profile['address'] as String?),
        phone: Value(profile['phone'] as String?),
        currency: Value(profile['currency'] as String? ?? 'USD'),
        logoUrl: Value(profile['logo_url'] as String?),
        lastSyncedAt: Value(DateTime.now()),
      ),
    );

    await _db.productDao.upsertProducts(
      payload.products
          .map((p) => ProductsCompanion.insert(
                id: Value(p['id'] as int),
                barcode: p['barcode'] as String,
                name: p['name'] as String,
                description: Value(p['description'] as String?),
                price: (p['price'] as num).toDouble(),
                stockQty: Value(p['stock_qty'] as int? ?? 0),
                lastSyncedAt: Value(DateTime.now()),
              ))
          .toList(),
    );

    await _db.staffDao.upsertStaff(
      payload.staff
          .map((s) => StaffCompanion.insert(
                id: Value(s['id'] as int),
                name: s['name'] as String,
                role: s['role'] as String,
                lastSyncedAt: Value(DateTime.now()),
              ))
          .toList(),
    );
  }

  /// Verifies a staff PIN against the PC and, on success, opens a
  /// local session for that staff member.
  Future<void> loginStaff({
    required int staffId,
    required String staffName,
    required String staffRole,
    required String pin,
  }) async {
    final config = await _db.pairingDao.getPairingConfig();
    if (config == null) {
      throw const PosApiException('Device is not paired yet.');
    }

    final client = PosApiClient(
      ip: config.pcIp,
      port: config.pcPort,
      deviceToken: config.pairingToken,
    );

    // The session token itself isn't persisted separately in this
    // The server returns a per-session token alongside staff verify —
    // persist it in secure storage so we'll attach it to subsequent
    // API and WebSocket requests (Phase 11 security hardening).
    final sessionToken = await client.verifyStaffPin(
      staffId: staffId,
      pin: pin,
      deviceToken: config.pairingToken,
    );
    await SecureDeviceStorage.saveSessionToken(sessionToken);

    await _db.sessionDao.setSession(
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
    );
  }
}
