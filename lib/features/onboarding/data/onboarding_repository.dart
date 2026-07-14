import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/secure_device_storage.dart';
import '../../../data/db/db.dart';

/// QR payload scanned from the desktop app's pairing screen:
/// `{ "ip": "...", "port": ..., "token": "..." }` — per
/// MOBILE_API_REFERENCE.md this is always plain JSON (never a URL),
/// and the connection is ALWAYS HTTPS with a self-signed cert (there is
/// no "scheme"/"protocol" field to check — the desktop server never
/// speaks plain HTTP).
class PairingQrPayload {
  final String ip;
  final int port;
  final String token;

  PairingQrPayload({required this.ip, required this.port, required this.token});

  factory PairingQrPayload.fromJson(Map<String, dynamic> json) {
    final ip = json['ip'];
    final token = json['token'];
    final port = json['port'];
    if (ip is! String || ip.isEmpty || token is! String || token.isEmpty) {
      throw const FormatException('Invalid pairing QR payload');
    }
    return PairingQrPayload(
      ip: ip,
      port: port is int ? port : int.tryParse('$port') ?? 8443,
      token: token,
    );
  }

  /// Parses whatever `mobile_scanner` reads off the QR code. Per
  /// MOBILE_API_REFERENCE.md the desktop always encodes plain JSON
  /// (`{"ip":...,"port":...,"token":...}`), but this also accepts a
  /// URL-style payload (`?ip=...&port=...&token=...`) as a fallback in
  /// case an older/alternate desktop build encodes it that way.
  factory PairingQrPayload.fromRaw(String raw) {
    final trimmed = raw.trim();

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return PairingQrPayload.fromJson(decoded);
      }
    } catch (_) {
      // Not JSON; try URI format below.
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final ip =
          uri.queryParameters['ip'] ?? (uri.host.isNotEmpty ? uri.host : null);
      final token = uri.queryParameters['token'];
      final portStr = uri.queryParameters['port'];
      final port = portStr != null
          ? int.tryParse(portStr) ?? 8443
          : (uri.hasPort ? uri.port : 8443);

      if (ip != null && ip.isNotEmpty && token != null && token.isNotEmpty) {
        return PairingQrPayload(ip: ip, port: port, token: token);
      }
    }

    throw const FormatException('Unsupported pairing QR format');
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
    final result = await _withTransportFallback(
      qr.ip,
      qr.port,
      (client) async {
        final deviceToken = await client.exchangePairingToken(qr.token);

        await SecureDeviceStorage.saveDeviceToken(deviceToken);
        await _db.pairingDao.setPairingConfig(
          pcIp: qr.ip,
          pcPort: qr.port,
          pairingToken: deviceToken,
        );

        await _pullInitialSyncWithFallback(
          ip: qr.ip,
          port: qr.port,
          deviceToken: deviceToken,
        );
        return deviceToken;
      },
    );

    if (result == null) {
      throw const PosApiException('Pairing failed unexpectedly.');
    }
  }

  /// Re-runs just the sync pull using the already-stored pairing info
  /// (e.g. a manual "refresh catalog" action from Settings, or the
  /// debug screen's "Refresh sync" button).
  Future<void> refreshSync() async {
    final config = await _db.pairingDao.getPairingConfig();
    if (config == null) {
      throw const PosApiException('Device is not paired yet.');
    }
    await _pullInitialSyncWithFallback(
      ip: config.pcIp,
      port: config.pcPort,
      deviceToken: config.pairingToken,
    );
  }

  Future<void> _pullInitialSyncWithFallback({
    required String ip,
    required int port,
    required String deviceToken,
  }) async {
    final payload = await _withTransportFallback(
      ip,
      port,
      (client) async => client.fetchInitialSync(),
      deviceToken: deviceToken,
    );

    if (payload == null) {
      throw const PosApiException('Initial sync failed unexpectedly.');
    }

    // "shop" is null if the desktop hasn't completed first-run setup
    // yet — don't crash, just skip caching a profile until it exists.
    final shop = payload.shop;
    if (shop != null) {
      await _db.shopProfileDao.setShopProfile(
        ShopProfileCompanion.insert(
          name: shop['name'] as String,
          address: Value(shop['address'] as String?),
          phone: Value(shop['phone'] as String?),
          currency: Value(shop['currency'] as String? ?? 'USD'),
          // Server field is "logo_path", not "logo_url".
          logoUrl: Value(shop['logo_path'] as String?),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
    }

    await _db.productDao.upsertProducts(
      payload.products
          .map((p) => ProductsCompanion.insert(
                id: Value(p['id'] as int),
                // NOTE: server allows barcode to be null, but the
                // local `products.barcode` column is currently
                // non-nullable + unique. Products with no barcode from
                // the desktop will need a schema change
                // (`text().nullable()()`) to sync correctly — flagging
                // this rather than silently coercing null to ''.
                barcode: p['barcode'] as String,
                name: p['name'] as String,
                description: Value(p['description'] as String?),
                imagePath: Value(p['image_path'] as String?),
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

    final result = await _withTransportFallback(
      config.pcIp,
      config.pcPort,
      (client) => client.verifyStaffPin(staffId: staffId, pin: pin),
      deviceToken: config.pairingToken,
    );

    if (result == null) {
      throw const PosApiException('Login failed unexpectedly.');
    }
    await SecureDeviceStorage.saveSessionToken(result.sessionToken);

    await _db.sessionDao.setSession(
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
    );
  }

  Future<T?> _withTransportFallback<T>(
    String ip,
    int port,
    Future<T> Function(PosApiClient client) action, {
    String? deviceToken,
    String? sessionToken,
  }) async {
    final attempts = <bool>[true, false];
    PosApiException? lastConnectivityError;

    for (final allowSelfSigned in attempts) {
      try {
        final client = PosApiClient(
          ip: ip,
          port: port,
          deviceToken: deviceToken,
          sessionToken: sessionToken,
          allowSelfSigned: allowSelfSigned,
        );
        return await action(client);
      } catch (error) {
        if (error is PosApiException && _isConnectivityError(error)) {
          lastConnectivityError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastConnectivityError != null) {
      throw lastConnectivityError;
    }
    return null;
  }

  bool _isConnectivityError(PosApiException error) {
    return error.statusCode == null &&
        error.message.toLowerCase().contains('couldn\'t reach');
  }
}
