import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Thin wrapper around the PC's local REST API.
///
/// This contract is taken directly from `MOBILE_API_REFERENCE.md`
/// (verified against the desktop server source) — every path, field
/// name, and header below is confirmed, not guessed.
class PosApiClient {
  /// `allowSelfSigned` enables contacting a PC using a self-signed
  /// certificate on the local network. The desktop server is ALWAYS
  /// HTTPS with a self-signed cert, so this should always be `true`
  /// in practice. If `trustedFingerprint` is provided, the
  /// certificate's SHA256 fingerprint must match it.
  PosApiClient({
    required String ip,
    required int port,
    String? deviceToken,
    String? sessionToken,
    bool allowSelfSigned = true,
    String? trustedFingerprint,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: 'http${allowSelfSigned ? 's' : ''}://$ip:$port',
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              // Device token proves this phone is paired at all.
              if (deviceToken != null) 'Authorization': 'Bearer $deviceToken',
              // Session token proves a specific staff member is logged
              // in. NOTE: this is only correct for as long as this
              // client instance lives — see api_client_provider notes
              // on why callers should build a fresh client (or at
              // least a fresh session token) per request rather than
              // holding one client long-term.
              if (sessionToken != null) 'X-Session-Token': sessionToken,
            },
          ),
        ) {
    if (allowSelfSigned) {
      final adapter = _dio.httpClientAdapter as IOHttpClientAdapter;
      // dio 5.x: `onHttpClientCreate` is deprecated in favor of
      // `createHttpClient`.
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          if (trustedFingerprint != null && trustedFingerprint.isNotEmpty) {
            try {
              final fingerprint = crypto.sha256.convert(cert.der).toString();
              return fingerprint.toLowerCase() ==
                  trustedFingerprint.toLowerCase();
            } catch (_) {
              return false;
            }
          }
          return true;
        };
        return client;
      };
    }
  }

  final Dio _dio;

  /// `POST /pair` — public, no auth. Exchanges the QR code's
  /// short-lived pairing token for a long-lived device token.
  Future<String> exchangePairingToken(String pairingToken) async {
    try {
      final res = await _dio.post('/pair', data: {'token': pairingToken});
      final deviceToken =
          (res.data as Map<String, dynamic>)['device_token'] as String?;
      if (deviceToken == null || deviceToken.isEmpty) {
        throw const PosApiException('Pairing response missing device_token.');
      }
      return deviceToken;
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'pairing');
    }
  }

  /// `GET /health` — public, no auth.
  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get('/health');
      return (res.data as Map<String, dynamic>)['status'] == 'ok';
    } on DioException {
      return false;
    }
  }

  /// `GET /sync/initial` — device token only. One-shot bootstrap,
  /// called immediately after pairing.
  Future<InitialSyncPayload> fetchInitialSync() async {
    try {
      final res = await _dio.get('/sync/initial');
      return InitialSyncPayload.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'initial sync');
    }
  }

  /// `GET /staff` — device token only. Only active staff; never
  /// includes PINs. Use this for the staff picker list.
  Future<List<Map<String, dynamic>>> fetchStaffList() async {
    try {
      final res = await _dio.get('/staff');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'fetch staff');
    }
  }

  /// `GET /products` — device token + session token (Cashier+).
  Future<List<Map<String, dynamic>>> fetchProducts() async {
    try {
      final res = await _dio.get('/products');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'fetch products');
    }
  }

  /// `GET /products/by-barcode/{barcode}` — device token + session
  /// token (Cashier+). Returns null on 404.
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode) async {
    try {
      final res = await _dio.get('/products/by-barcode/$barcode');
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw PosApiException.fromDio(e, context: 'fetch product');
    }
  }

  /// `POST /sales` — device token + session token (Cashier+). The
  /// cashier is always taken server-side from the session token — a
  /// staff_id/cashier_id in the body is ignored even if sent.
  ///
  /// On success returns the sale id. On insufficient stock the server
  /// returns 409 with a structured body — that's surfaced as a
  /// [PosApiException] with `statusCode == 409` and
  /// `insufficientStockItems` populated; callers should check for that
  /// specifically rather than treating every failure the same way.
  Future<int> pushSale(Map<String, dynamic> payload) async {
    try {
      final res = await _dio.post('/sales', data: payload);
      return (res.data as Map<String, dynamic>)['sale_id'] as int;
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'push sale');
    }
  }

  Future<Map<String, dynamic>> voidSale(int saleId) async {
    try {
      final res = await _dio.post('/sales/$saleId/void');
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'void sale');
    }
  }

  /// `POST /products` — device token + session token (Manager+).
  ///
  /// IMPORTANT: request body is **camelCase** (the one exception to
  /// snake_case in this API). `db` is a snake_case-ish map coming from
  /// local Drift/queue storage; this converts it to the wire shape.
  /// `categoryId` key must always be present (may be `null`).
  Future<Map<String, dynamic>> createProduct(
      Map<String, dynamic> localPayload) async {
    try {
      final res =
          await _dio.post('/products', data: _toProductWireBody(localPayload));
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'create product');
    }
  }

  /// `PUT /products/{id}` — device token + session token (Manager+).
  /// Full-record replace, same body/response shape as create.
  Future<Map<String, dynamic>> updateProduct(
      int id, Map<String, dynamic> localPayload) async {
    try {
      final res = await _dio.put('/products/$id',
          data: _toProductWireBody(localPayload));
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'update product');
    }
  }

  /// `PATCH /products/{id}/stock` — device token + session token
  /// (Manager+). Delta-based (negative to sell/void, positive to
  /// restock) — NOT a general product editor, use [updateProduct] for
  /// that.
  Future<Map<String, dynamic>> adjustProductStock(int id, int delta) async {
    try {
      final res =
          await _dio.patch('/products/$id/stock', data: {'delta': delta});
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'adjust stock');
    }
  }

  /// Converts a local (snake_case-ish) product map into the server's
  /// expected camelCase request body. Accepts either snake_case or
  /// camelCase keys from the caller so both the sync queue's stored
  /// payloads and any future direct calls work without duplicating this
  /// mapping everywhere.
  Map<String, dynamic> _toProductWireBody(Map<String, dynamic> p) {
    Object? pick(String snake, String camel) =>
        p.containsKey(camel) ? p[camel] : p[snake];
    return {
      'name': pick('name', 'name'),
      'barcode': pick('barcode', 'barcode'),
      'price': pick('price', 'price'),
      'cost': pick('cost', 'cost') ?? 0,
      // Must always be present, even if null.
      'categoryId': pick('category_id', 'categoryId'),
      'categoryName': pick('category_name', 'categoryName'),
      'stockQty': pick('stock_qty', 'stockQty') ?? 0,
      'description': pick('description', 'description'),
      'imagePath': pick('image_path', 'imagePath'),
    };
  }

  /// Uploads an image file as multipart form data. NOTE: not part of
  /// the confirmed `MOBILE_API_REFERENCE.md` contract — the desktop
  /// team hasn't documented an images endpoint yet. Left in place for
  /// when/if that's added; don't rely on this until confirmed.
  Future<Map<String, dynamic>> uploadImage(File file) async {
    try {
      final name = file.path.split(Platform.pathSeparator).last;
      final form = FormData.fromMap({
        'file':
            MultipartFile.fromBytes(await file.readAsBytes(), filename: name),
      });
      final res = await _dio.post('/images', data: form);
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'upload image');
    }
  }

  /// `GET /products/{id}/image` — device token only. Server falls
  /// back to a bundled placeholder if there's no image, so no local
  /// fallback logic is needed here.
  Future<List<int>> downloadProductImage(int productId) async {
    try {
      final res = await _dio.get('/products/$productId/image',
          options: Options(responseType: ResponseType.bytes));
      return (res.data as List<int>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'download image');
    }
  }

  /// `POST /auth/login` — device token only. The staff PIN login.
  /// Response's `token` field is the SESSION token (not `session_token`
  /// — this key name previously caused every login to fail with
  /// "Login response missing session_token").
  Future<StaffLoginResult> verifyStaffPin({
    required int staffId,
    required String pin,
  }) async {
    try {
      final res = await _dio.post(
        '/auth/login',
        data: {'staff_id': staffId, 'pin': pin},
      );
      final data = res.data as Map<String, dynamic>;
      final sessionToken = data['token'] as String?;
      if (sessionToken == null || sessionToken.isEmpty) {
        throw const PosApiException('Login response missing token.');
      }
      return StaffLoginResult(
        sessionToken: sessionToken,
        userId: data['user_id'] as int,
        name: data['name'] as String,
        role: data['role'] as String,
        expiresAt: data['expires_at'] as int?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const PosApiException('Incorrect PIN', isAuthError: true);
      }
      throw PosApiException.fromDio(e, context: 'staff login');
    }
  }
}

class StaffLoginResult {
  final String sessionToken;
  final int userId;
  final String name;
  final String role;
  final int? expiresAt;

  StaffLoginResult({
    required this.sessionToken,
    required this.userId,
    required this.name,
    required this.role,
    required this.expiresAt,
  });
}

class InitialSyncPayload {
  /// Null if the desktop hasn't completed first-run setup yet.
  final Map<String, dynamic>? shop;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> staff;

  InitialSyncPayload({
    required this.shop,
    required this.products,
    required this.staff,
  });

  factory InitialSyncPayload.fromJson(Map<String, dynamic> json) {
    return InitialSyncPayload(
      // Server field is "shop", not "shop_profile" — and it can
      // legitimately be null pre-setup.
      shop: json['shop'] as Map<String, dynamic>?,
      products: (json['products'] as List).cast<Map<String, dynamic>>(),
      staff: (json['staff'] as List).cast<Map<String, dynamic>>(),
    );
  }
}

class PosApiException implements Exception {
  final String message;
  final bool isAuthError;
  final int? statusCode;

  /// Populated only for `POST /sales` 409 responses — per-item
  /// shortfall details from the server's `items` array.
  final List<Map<String, dynamic>>? insufficientStockItems;

  const PosApiException(
    this.message, {
    this.isAuthError = false,
    this.statusCode,
    this.insufficientStockItems,
  });

  factory PosApiException.fromDio(DioException e, {required String context}) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return PosApiException(
        'Couldn\'t reach the shop computer during $context. '
        'Make sure it\'s on and on the same network.',
      );
    }

    if (e.type == DioExceptionType.badCertificate) {
      return PosApiException(
        'Couldn\'t verify the shop computer\'s security certificate '
        'during $context. Try regenerating the pairing QR code on the '
        'desktop app and scanning again.',
      );
    }

    final code = e.response?.statusCode;
    final data = e.response?.data;
    final serverMessage = _extractServerMessage(data);

    if (code == 401) {
      // Per the API reference: a 401 specifically on a
      // session-protected route (with pairing/login/staff-list still
      // working) means a missing/expired X-Session-Token — not a bad
      // device token. Surface that distinctly rather than a generic
      // "authentication failed" so the UI can prompt re-login instead
      // of forcing a full re-pair.
      return PosApiException(
        serverMessage ?? 'Session expired or missing — please log in again.',
        isAuthError: true,
        statusCode: code,
      );
    }

    if (code == 403) {
      return PosApiException(
        serverMessage ??
            'This device\'s pairing was rejected — re-pair with the desktop.',
        statusCode: code,
      );
    }

    if (code == 409) {
      // Sales-specific structured conflict body.
      if (data is Map<String, dynamic> && data['items'] is List) {
        return PosApiException(
          serverMessage ?? 'Insufficient stock for one or more items.',
          statusCode: code,
          insufficientStockItems:
              (data['items'] as List).cast<Map<String, dynamic>>(),
        );
      }
      return PosApiException(
        serverMessage ?? 'Conflict (409) from server during $context.',
        statusCode: code,
      );
    }

    if (code == 400 || code == 422) {
      return PosApiException(
        serverMessage ?? 'Invalid data sent during $context.',
        statusCode: code,
      );
    }

    if (code == 404) {
      return PosApiException(
        serverMessage ?? 'Not found (404) during $context.',
        statusCode: code,
      );
    }

    if (serverMessage != null) {
      return PosApiException(
        '$serverMessage (during $context, status: ${code ?? 'unknown'})',
        statusCode: code,
      );
    }

    return PosApiException('Something went wrong during $context.',
        statusCode: code);
  }

  static String? _extractServerMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      for (final key in const ['error', 'message', 'detail', 'details']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }

  @override
  String toString() => message;
}
