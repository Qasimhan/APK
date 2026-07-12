import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the long-lived device token issued at pairing time. This is
/// the credential Phase 11's security hardening cares most about, so
/// it lives in flutter_secure_storage, never in the Drift database or
/// SharedPreferences.
class SecureDeviceStorage {
  SecureDeviceStorage._();

  static const _storage = FlutterSecureStorage();
  static const _deviceTokenKey = 'device_token';
  static const _sessionTokenKey = 'session_token';

  static Future<void> saveDeviceToken(String token) {
    return _storage.write(key: _deviceTokenKey, value: token);
  }

  static Future<String?> readDeviceToken() {
    return _storage.read(key: _deviceTokenKey);
  }

  static Future<void> clearDeviceToken() {
    return _storage.delete(key: _deviceTokenKey);
  }

  /// Session token (staff session) storage — sensitive, kept in secure
  /// storage rather than in Drift or SharedPreferences.
  static Future<void> saveSessionToken(String token) {
    return _storage.write(key: _sessionTokenKey, value: token);
  }

  static Future<String?> readSessionToken() {
    return _storage.read(key: _sessionTokenKey);
  }

  static Future<void> clearSessionToken() {
    return _storage.delete(key: _sessionTokenKey);
  }
}
