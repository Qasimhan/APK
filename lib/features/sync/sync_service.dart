import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:drift/drift.dart' show Value;

import '../../data/db/db.dart';
import '../../core/network/api_client.dart';
import '../../core/network/secure_device_storage.dart';

/// Lightweight sync service: maintains a WebSocket to the paired PC
/// for live `stock_updated`/`sale_completed` pushes, and flushes the
/// offline action queue (products/sales created on this phone) when
/// connectivity is restored.
///
/// Event set and payload shapes here are taken directly from
/// MOBILE_API_REFERENCE.md §4 — the server ONLY ever sends
/// `stock_updated` and `sale_completed`. There is no `product_created`,
/// `product_updated`, `price_update`, or `scan_request`/`scan_result`
/// event server-side (a prior version of this file listened for those,
/// which is why desktop-side changes never reliably reached the phone —
/// the type strings didn't match anything the server actually sends,
/// so every incoming message fell through to the `default` case and was
/// dropped).
class SyncService {
  SyncService(this._db) {
    _pairingSub = _db.pairingDao.watchPairingConfig().listen(_onPairing);
  }

  final AppDatabase _db;

  WebSocketChannel? _channel;
  StreamSubscription? _pairingSub;
  StreamSubscription? _wsListener;

  // NOTE: `scan_request`/`scan_result` do NOT exist server-side per
  // MOBILE_API_REFERENCE.md §4 ("if a mobile dev plan describes a
  // remote scan mode relayed over this socket, it does not exist
  // server-side yet"). Kept here as inert stubs only so pos_screen.dart's
  // existing "remote scan" UI still compiles — that stream will never
  // emit until the desktop team actually adds this event. Flag to
  // whoever owns pos_screen.dart: this UI currently does nothing.
  final _scanRequestController = StreamController<String>.broadcast();
  Stream<String> get scanRequestStream => _scanRequestController.stream;

  // Backoff state
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // True once _flushPendingActions is actively running, so callers
  // (e.g. "I just added a product") can trigger an immediate flush
  // without racing a concurrent one.
  bool _flushing = false;
  String? _connectedIp;
  int? _connectedPort;
  String? _connectedDeviceToken;

  void _onPairing(PairingConfigData? cfg) {
    _closeChannel();
    if (cfg != null) {
      _connect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
    }
  }

  void _connect(String ip, int port, String deviceToken) async {
    _connectedIp = ip;
    _connectedPort = port;
    _connectedDeviceToken = deviceToken;

    // Per MOBILE_API_REFERENCE.md §4: "GET /ws?token=<device_token>
    // — device token via query string" — the WebSocket upgrade route
    // authenticates via the query parameter specifically, not the
    // Authorization header (a previous version of this code only sent
    // the header, which the server's /ws handler doesn't read, so the
    // socket was never actually authenticated).
    final uri = Uri(
      scheme: 'wss',
      host: ip,
      port: port,
      path: '/ws',
      queryParameters: {'token': deviceToken},
    );
    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        customClient: HttpClient()
          ..badCertificateCallback = (cert, host, port) => true,
      );
      _channel = channel;

      _wsListener = _channel!.stream.listen(_handleMessage,
          onDone: _onDisconnected, onError: _onError, cancelOnError: true);

      _reconnectAttempts = 0;
      // Immediately try flushing pending actions once connected.
      await _flushPendingActions();
    } catch (_) {
      _scheduleReconnect(ip, port, deviceToken);
    }
  }

  void _handleMessage(dynamic raw) async {
    try {
      final Map<String, dynamic> msg =
          raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw);
      final type = msg['type'] as String?;
      final payload = msg['payload'] as Map<String, dynamic>?;
      if (type == null || payload == null) return;

      switch (type) {
        case 'stock_updated':
          // { "product_id": 1, "stock_qty": 39 }
          final productId = payload['product_id'] as int?;
          final stockQty = payload['stock_qty'] as int?;
          if (productId != null && stockQty != null) {
            await _db.productDao.upsertProduct(
              ProductsCompanion(
                id: Value(productId),
                stockQty: Value(stockQty),
                lastSyncedAt: Value(DateTime.now()),
              ),
            );
          }
          break;

        case 'sale_completed':
          // { "sale_id":7, "total":19.42, "cashier_id":1,
          //   "item_count":2, "stock_updates":[{"product_id":1,"stock_qty":39}] }
          final stockUpdates = payload['stock_updates'] as List? ?? [];
          for (final update in stockUpdates) {
            final productId = update['product_id'] as int?;
            final stockQty = update['stock_qty'] as int?;
            if (productId != null && stockQty != null) {
              await _db.productDao.upsertProduct(
                ProductsCompanion(
                  id: Value(productId),
                  stockQty: Value(stockQty),
                  lastSyncedAt: Value(DateTime.now()),
                ),
              );
            }
          }
          break;

        default:
          // Unknown/future event type — ignore rather than crash.
          break;
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  void _onDisconnected() {
    _closeChannel();
    _db.pairingDao.getPairingConfig().then((cfg) {
      if (cfg != null) {
        _scheduleReconnect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
      }
    });
  }

  void _onError(err) {
    _closeChannel();
    _db.pairingDao.getPairingConfig().then((cfg) {
      if (cfg != null) {
        _scheduleReconnect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
      }
    });
  }

  void _scheduleReconnect(String ip, int port, String deviceToken) {
    _reconnectAttempts++;
    final backoff = Duration(seconds: (1 << (_reconnectAttempts.clamp(0, 6))));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () => _connect(ip, port, deviceToken));
  }

  /// Public entry point so UI code (e.g. right after adding a product,
  /// or completing a sale) can request an immediate push attempt
  /// instead of waiting for the next WebSocket reconnect cycle.
  Future<void> flushNow() async {
    if (_connectedIp == null ||
        _connectedPort == null ||
        _connectedDeviceToken == null) {
      final cfg = await _db.pairingDao.getPairingConfig();
      if (cfg == null) return;
      _connectedIp = cfg.pcIp;
      _connectedPort = cfg.pcPort;
      _connectedDeviceToken = cfg.pairingToken;
    }
    await _flushPendingActions();
  }

  Future<void> _flushPendingActions() async {
    if (_flushing) return;
    if (_connectedIp == null ||
        _connectedPort == null ||
        _connectedDeviceToken == null) {
      return;
    }
    _flushing = true;
    try {
      // Read the session token fresh on every flush attempt — it can
      // change (login/logout) independently of the device pairing, so
      // it must never be cached on this long-lived service.
      final sessionToken = await SecureDeviceStorage.readSessionToken();
      final client = PosApiClient(
        ip: _connectedIp!,
        port: _connectedPort!,
        deviceToken: _connectedDeviceToken!,
        sessionToken: sessionToken,
      );

      final pending = await _db.syncQueueDao.getPendingActions();
      for (final action in pending) {
        try {
          final payload = jsonDecode(action.payload) as Map<String, dynamic>;
          switch (action.actionType) {
            case 'sale':
              await _flushSale(client, action, payload);
              break;
            case 'product_create':
              await _flushProductCreate(client, action, payload);
              break;
            case 'product_update':
              await _flushProductUpdate(client, action, payload);
              break;
            default:
              // Unsupported action type: mark rejected so it doesn't
              // block the queue forever.
              await _db.syncQueueDao.markActionRejected(action.id);
              break;
          }
        } on PosApiException catch (e) {
          // Session expired — stop processing; UI should prompt
          // re-login via the session watch, not clear pairing.
          if (e.isAuthError) {
            await _db.sessionDao.clearSession();
            await SecureDeviceStorage.clearSessionToken();
            return;
          }
          // Device token rejected — force full re-pair.
          if (e.statusCode == 403) {
            await _db.pairingDao.clearPairing();
            await SecureDeviceStorage.clearDeviceToken();
            return;
          }
          // Real business rejection (e.g. duplicate barcode, 400/409
          // that isn't auth-related): mark rejected, keep processing
          // the rest of the queue rather than blocking on one bad item.
          if (e.statusCode == 400 ||
              e.statusCode == 409 ||
              e.statusCode == 422) {
            await _db.syncQueueDao.markActionRejected(action.id);
            continue;
          }
          // Network/unknown error: leave pending for next reconnect,
          // stop here to preserve ordering.
          return;
        } catch (_) {
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushSale(PosApiClient client, PendingAction action,
      Map<String, dynamic> payload) async {
    final saleId = await client.pushSale(payload);
    await _db.syncQueueDao.markActionSynced(action.id);
    await _db.salesDao
        .updateSaleSyncStatus(payload['sale_id'] as String, 'synced');
    // ignore: unused_local_variable
    final _ = saleId;
  }

  Future<void> _flushProductCreate(PosApiClient client, PendingAction action,
      Map<String, dynamic> payload) async {
    await _maybeUploadImage(client, payload);
    final created = await client.createProduct(payload);
    await _upsertFromServerProduct(created);
    await _db.syncQueueDao.markActionSynced(action.id);
  }

  Future<void> _flushProductUpdate(PosApiClient client, PendingAction action,
      Map<String, dynamic> payload) async {
    await _maybeUploadImage(client, payload);
    final id = payload['id'] as int;
    final updated = await client.updateProduct(id, payload);
    await _upsertFromServerProduct(updated);
    await _db.syncQueueDao.markActionSynced(action.id);
  }

  Future<void> _maybeUploadImage(
      PosApiClient client, Map<String, dynamic> payload) async {
    final imgPath = payload['image_path'] as String?;
    if (imgPath == null || imgPath.isEmpty) return;
    final file = File(imgPath);
    if (!await file.exists()) return;
    try {
      final imgMeta = await client.uploadImage(file);
      payload['image_path'] = imgMeta['path'] ?? imgMeta['id'];
    } catch (_) {
      // Image upload isn't part of the confirmed API contract yet —
      // don't let a failure here block the product create/update.
    }
  }

  Future<void> _upsertFromServerProduct(Map<String, dynamic> p) async {
    await _db.productDao.upsertProduct(
      ProductsCompanion(
        id: Value(p['id'] as int),
        barcode: Value(p['barcode'] as String? ?? ''),
        name: Value(p['name'] as String),
        description: Value(p['description'] as String?),
        imagePath: Value(p['image_path'] as String?),
        price: Value((p['price'] as num).toDouble()),
        stockQty: Value(p['stock_qty'] as int? ?? 0),
        lastSyncedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Inert per the note above — the server never reads anything on
  /// this socket for `scan_result`, and never sent a `scan_request` to
  /// trigger this in the first place. Left as a no-op so callers don't
  /// need to be changed until the desktop team confirms this feature.
  Future<void> sendScanResult(String sessionId, String barcode) async {
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'scan_result',
        'payload': {'session_id': sessionId, 'barcode': barcode},
      }));
    } catch (_) {
      // ignore if not connected
    }
  }

  void _closeChannel() {
    _wsListener?.cancel();
    _wsListener = null;
    try {
      _channel?.sink.close(status.goingAway);
    } catch (_) {}
    _channel = null;
    _reconnectTimer?.cancel();
  }

  void dispose() {
    _pairingSub?.cancel();
    _closeChannel();
    _scanRequestController.close();
  }
}