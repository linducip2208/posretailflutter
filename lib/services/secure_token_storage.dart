import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token otentikasi WAJIB di secure storage (Keystore/Keychain),
/// bukan SharedPreferences plaintext.
class SecureTokenStorage {
  static const _tokenKey = 'auth_token';
  static const _legacyPrefsKey = 'auth_token';

  static final SecureTokenStorage _instance = SecureTokenStorage._();
  factory SecureTokenStorage() => _instance;
  SecureTokenStorage._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> readToken() async {
    var token = await _secure.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) return token;
    // Migrasi sekali jalan dari penyimpanan lama (plaintext prefs).
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_legacyPrefsKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _secure.write(key: _tokenKey, value: legacy);
      await prefs.remove(_legacyPrefsKey);
      return legacy;
    }
    return null;
  }

  Future<void> writeToken(String token) =>
      _secure.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _secure.delete(key: _tokenKey);
}
