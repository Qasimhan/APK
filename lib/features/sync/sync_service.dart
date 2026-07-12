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

/// Lightweight sync service: maintains a WebSocket to the paired PC,
/// emits incoming `scan_request` events, and flushes the offline queue
/// when connectivity is restored.
class SyncService {
  SyncService(this._db) {
    _pairingSub = _db.pairingDao.watchPairingConfig().listen(_onPairing);
  }

  final AppDatabase _db;

  WebSocketChannel? _channel;
  StreamSubscription? _pairingSub;
  StreamSubscription? _wsListener;

  // Broadcast stream for incoming remote scan requests (session id strings).
  final _scanRequestController = StreamController<String>.broadcast();
  Stream<String> get scanRequestStream => _scanRequestController.stream;

  // Backoff state
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  void _onPairing(PairingConfigData? cfg) {
    _closeChannel();
    if (cfg != null) {
      _connect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
    }
  }

  void _connect(String ip, int port, String deviceToken) async {
    final uri = Uri(scheme: 'ws', host: ip, port: port, path: '/ws');
    try {
      // Include both device and session tokens (if present) in WS
      // headers so the server can perform proper per-session checks.
      final sessionToken = await SecureDeviceStorage.readSessionToken();
      final headers = <String, String>{'Authorization': 'Bearer $deviceToken'};
      if (sessionToken != null) headers['X-Session-Token'] = sessionToken;
      final channel =
          IOWebSocketChannel.connect(uri.toString(), headers: headers);
      _channel = channel;

      _wsListener = _channel!.stream.listen(_handleMessage,
          onDone: _onDisconnected, onError: _onError, cancelOnError: true);

      _reconnectAttempts = 0;
      // Immediately try flushing pending actions once connected.
      await _flushPendingActions(deviceToken, ip, port);
    } catch (_) {
      _scheduleReconnect(ip, port, deviceToken);
    }
  }

  void _handleMessage(dynamic raw) async {
    try {
      final Map<String, dynamic> msg =
          raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw);
      final type = msg['type'] as String?;
      final payload = msg['payload'];
      if (type == null) return;

      switch (type) {
        case 'stock_update':
        case 'price_update':
          // Expect payload: { product_id: int, stock_qty?: int, price?: num }
          final int productId = payload['product_id'] as int;
          final stock = payload['stock_qty'] as int?;
          final price = payload['price'] as num?;
          if (stock != null || price != null) {
            await _db.productDao.upsertProduct(
              ProductsCompanion(
                id: Value(productId),
                stockQty: stock != null ? Value(stock) : const Value.absent(),
                price: price != null
                    ? Value(price.toDouble())
                    : const Value.absent(),
                lastSyncedAt: Value(DateTime.now()),
              ),
            );
          }
          break;

        case 'product_created':
        case 'product_updated':
          // Expect payload to be a product map similar to initial sync
          final Map<String, dynamic> p =
              Map<String, dynamic>.from(payload as Map);
          await _db.productDao.upsertProduct(
            ProductsCompanion(
              id: Value(p['id'] as int),
              barcode: Value(p['barcode'] as String),
              name: Value(p['name'] as String),
              description: Value(p['description'] as String?),
              price: Value((p['price'] as num).toDouble()),
              stockQty: Value(p['stock_qty'] as int? ?? 0),
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
          break;

        case 'sale_completed':
          // Server notifies about completed sale elsewhere; update affected products
          final List items = payload['items'] as List? ?? [];
          for (final item in items) {
            final pid = item['product_id'] as int?;
            final newStock = item['new_stock_qty'] as int?;
            if (pid != null && newStock != null) {
              await _db.productDao.upsertProduct(
                ProductsCompanion(
                  id: Value(pid),
                  stockQty: Value(newStock),
                  lastSyncedAt: Value(DateTime.now()),
                ),
              );
            }
          }
          break;

        case 'scan_request':
          // payload: { session_id: '...' }
          final sessionId = payload['session_id'] as String?;
          if (sessionId != null) {
            _scanRequestController.add(sessionId);
          }
          break;

        default:
          break;
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  void _onDisconnected() {
    _closeChannel();
    // read last pairing to attempt reconnect
    _db.pairingDao.getPairingConfig().then((cfg) {
      if (cfg != null)
        _scheduleReconnect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
    });
  }

  void _onError(err) {
    _closeChannel();
    _db.pairingDao.getPairingConfig().then((cfg) {
      if (cfg != null)
        _scheduleReconnect(cfg.pcIp, cfg.pcPort, cfg.pairingToken);
    });
  }

  void _scheduleReconnect(String ip, int port, String deviceToken) {
    _reconnectAttempts++;
    final backoff = Duration(seconds: (1 << (_reconnectAttempts.clamp(0, 6))));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () => _connect(ip, port, deviceToken));
  }

  Future<void> _flushPendingActions(
      String deviceToken, String ip, int port) async {
    final sessionToken = await SecureDeviceStorage.readSessionToken();
    final client = PosApiClient(
        ip: ip,
        port: port,
        deviceToken: deviceToken,
        sessionToken: sessionToken,
        allowSelfSigned: true);

    final pending = await _db.syncQueueDao.getPendingActions();
    for (final action in pending) {
      try {
        final payload = jsonDecode(action.payload) as Map<String, dynamic>;
        switch (action.actionType) {
          case 'sale':
            try {
              await client.pushSale(payload);
              await _db.syncQueueDao.markActionSynced(action.id);
              await _db.salesDao
                  .updateSaleSyncStatus(payload['sale_id'] as String, 'synced');
            } on PosApiException catch (e) {
              // If auth failed, clear the local session so UI prompts re-login.
              if (e.statusCode == 401) {
                await _db.sessionDao.clearSession();
                await SecureDeviceStorage.clearSessionToken();
                // stop processing; UI should show login screen via session watch
                return;
              }

              // If the device token was rejected, force re-pair
              if (e.statusCode == 403) {
                await _db.pairingDao.clearPairing();
                await SecureDeviceStorage.clearDeviceToken();
                return;
              }

              // Interpret 409 as rejected (insufficient stock)
              if (e.statusCode == 409) {
                await _db.syncQueueDao.markActionRejected(action.id);
                await _db.salesDao.updateSaleSyncStatus(
                    payload['sale_id'] as String, 'rejected');
              } else {
                // network/other error: leave pending for next reconnect
                return;
              }
            }
            break;

          case 'product_create':
          case 'product_update':
            // If payload contains local image path, attempt upload first
            if (payload.containsKey('image_path')) {
              final imgPath = payload['image_path'] as String?;
              if (imgPath != null && imgPath.isNotEmpty) {
                final file = File(imgPath);
                if (await file.exists()) {
                  final imgMeta = await client.uploadImage(file);
                  payload['image_id'] = imgMeta['id'];
                }
              }
            }

            if (action.actionType == 'product_create') {
              final created = await client.createProduct(payload);
              // Update local cache with server-assigned id if needed
              await _db.productDao.upsertProduct(
                ProductsCompanion(
                  id: Value(created['id'] as int),
                  barcode: Value(created['barcode'] as String),
                  name: Value(created['name'] as String),
                  description: Value(created['description'] as String?),
                  price: Value((created['price'] as num).toDouble()),
                  stockQty: Value(created['stock_qty'] as int? ?? 0),
                  lastSyncedAt: Value(DateTime.now()),
                ),
              );
            } else {
              final id = payload['id'] as int;
              final updated = await client.updateProduct(id, payload);
              await _db.productDao.upsertProduct(
                ProductsCompanion(
                  id: Value(updated['id'] as int),
                  barcode: Value(updated['barcode'] as String),
                  name: Value(updated['name'] as String),
                  description: Value(updated['description'] as String?),
                  price: Value((updated['price'] as num).toDouble()),
                  stockQty: Value(updated['stock_qty'] as int? ?? 0),
                  lastSyncedAt: Value(DateTime.now()),
                ),
              );
            }

            await _db.syncQueueDao.markActionSynced(action.id);
            break;

          default:
            // unsupported action type: mark rejected so it doesn't block queue
            await _db.syncQueueDao.markActionRejected(action.id);
            break;
        }
      } catch (e) {
        // Network/other error — stop processing to preserve order for retry
        return;
      }
    }
  }

  Future<void> sendScanResult(String sessionId, String barcode) async {
    final msg = jsonEncode({
      'type': 'scan_result',
      'payload': {'session_id': sessionId, 'barcode': barcode}
    });
    try {
      _channel?.sink.add(msg);
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
