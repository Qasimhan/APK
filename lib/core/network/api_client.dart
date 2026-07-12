import 'dart:io';
// ignore: unused_import
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Thin wrapper around the PC's local REST API.
///
/// Endpoint paths/shapes here are the mobile side's assumption of the
/// contract exposed by the desktop app's local server (built in
/// Desktop Phases 5–7). If the actual desktop API differs, only this
/// file and [PosApiException] call sites need to change — nothing else
/// in the onboarding feature talks to Dio directly.
class PosApiClient {
  /// `allowSelfSigned` enables contacting a PC using a self-signed
  /// certificate on the local network. If `trustedFingerprint` is
  /// provided, the certificate's SHA256 fingerprint must match it.
  PosApiClient({
    required String ip,
    required int port,
    String? deviceToken,
    String? sessionToken,
    bool allowSelfSigned = false,
    String? trustedFingerprint,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: 'http${allowSelfSigned ? 's' : ''}://$ip:$port',
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              if (deviceToken != null) 'Authorization': 'Bearer $deviceToken',
              if (sessionToken != null) 'X-Session-Token': sessionToken,
            },
          ),
        ) {
    // Configure HttpClient to accept self-signed certificates when
    // requested. We use IOHttpClientAdapter to gain access to the
    // underlying HttpClient and its badCertificateCallback.
    if (allowSelfSigned) {
      final adapter = _dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.onHttpClientCreate = (HttpClient client) {
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
          // If no trusted fingerprint supplied, accept any cert.
          return true;
        };
        return client;
      };
    }
  }

  final Dio _dio;

  /// Step 1 of pairing: exchange the short-lived QR pairing token for a
  /// longer-lived device token the phone will use on every future
  /// request.
  Future<String> exchangePairingToken(String pairingToken) async {
    try {
      final res = await _dio.post(
        '/pairing/exchange',
        data: {'pairing_token': pairingToken},
      );
      final deviceToken = res.data['device_token'] as String?;
      if (deviceToken == null) {
        throw const PosApiException('Pairing response missing device_token');
      }
      return deviceToken;
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'pairing');
    }
  }

  /// Step 2 of pairing: pull the shop profile, full product catalog,
  /// and staff list in one shot, right after a device token is issued.
  Future<InitialSyncPayload> fetchInitialSync(String deviceToken) async {
    try {
      final res = await _dio.get(
        '/sync/initial',
        options: Options(headers: {'Authorization': 'Bearer $deviceToken'}),
      );
      return InitialSyncPayload.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'initial sync');
    }
  }

  /// Looks up a single product on the PC by barcode. Returns the raw
  /// product JSON map or null if not found.
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode) async {
    try {
      final res = await _dio
          .get('/products/lookup', queryParameters: {'barcode': barcode});
      if (res.statusCode == 404) return null;
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'fetch product');
    }
  }

  /// Pushes a completed sale to the PC. The `payload` should contain
  /// an idempotency key (client-generated sale id) so the PC can
  /// deduplicate retries.
  Future<void> pushSale(Map<String, dynamic> payload) async {
    try {
      // If the client has provided an idempotency key (sale_id), send it
      // as an Idempotency-Key header so the server can deduplicate retries.
      final headers = <String, dynamic>{};
      if (payload.containsKey('sale_id')) {
        headers['Idempotency-Key'] = payload['sale_id'];
      }
      await _dio.post('/sales',
          data: payload, options: Options(headers: headers));
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'push sale');
    }
  }

  Future<Map<String, dynamic>> createProduct(
      Map<String, dynamic> payload) async {
    try {
      final res = await _dio.post('/products', data: payload);
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'create product');
    }
  }

  Future<Map<String, dynamic>> updateProduct(
      int id, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.put('/products/$id', data: payload);
      return (res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'update product');
    }
  }

  Future<void> deactivateProduct(int id) async {
    try {
      await _dio.delete('/products/$id');
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'delete product');
    }
  }

  /// Uploads an image file as multipart form data and returns the
  /// server's image id / metadata.
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

  /// Downloads an image bytes by id. Caller is responsible for writing
  /// bytes to disk if needed.
  Future<List<int>> downloadImage(String imageId) async {
    try {
      final res = await _dio.get('/images/$imageId',
          options: Options(responseType: ResponseType.bytes));
      return (res.data as List<int>);
    } on DioException catch (e) {
      throw PosApiException.fromDio(e, context: 'download image');
    }
  }

  /// Verifies a staff PIN server-side. The PIN itself is never checked
  /// or stored on the device — only this network round trip decides.
  Future<String> verifyStaffPin({
    required int staffId,
    required String pin,
    required String deviceToken,
  }) async {
    try {
      final res = await _dio.post(
        '/auth/login',
        data: {'staff_id': staffId, 'pin': pin},
        options: Options(headers: {'Authorization': 'Bearer $deviceToken'}),
      );
      final sessionToken = res.data['session_token'] as String?;
      if (sessionToken == null) {
        throw const PosApiException('Login response missing session_token');
      }
      return sessionToken;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const PosApiException('Incorrect PIN', isAuthError: true);
      }
      throw PosApiException.fromDio(e, context: 'staff login');
    }
  }
}

class InitialSyncPayload {
  final Map<String, dynamic> shopProfile;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> staff;

  InitialSyncPayload({
    required this.shopProfile,
    required this.products,
    required this.staff,
  });

  factory InitialSyncPayload.fromJson(Map<String, dynamic> json) {
    return InitialSyncPayload(
      shopProfile: json['shop_profile'] as Map<String, dynamic>,
      products: (json['products'] as List).cast<Map<String, dynamic>>(),
      staff: (json['staff'] as List).cast<Map<String, dynamic>>(),
    );
  }
}

class PosApiException implements Exception {
  final String message;
  final bool isAuthError;
  final int? statusCode;

  const PosApiException(this.message,
      {this.isAuthError = false, this.statusCode});

  factory PosApiException.fromDio(DioException e, {required String context}) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return PosApiException(
        'Couldn\'t reach the shop computer during $context. '
        'Make sure it\'s on and on the same network.',
      );
    }

    final code = e.response?.statusCode;
    if (code == 401) {
      return PosApiException('Authentication failed during $context.',
          isAuthError: true, statusCode: code);
    }
    if (code == 409) {
      return PosApiException('Conflict (409) from server during $context.',
          statusCode: code);
    }

    return PosApiException('Something went wrong during $context.',
        statusCode: code);
  }

  @override
  String toString() => message;
}
