import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper untuk flutter_secure_storage.
/// Menyimpan dan membaca Bearer token autentikasi Laravel Sanctum.
class AuthStorage {
  /// Gunakan encryptedSharedPreferences: true pada Android agar token
  /// tidak hilang akibat Android Keystore key-rotation, backup/restore OS,
  /// atau device reboot pada beberapa versi Android.
  /// Ini jauh lebih stabil daripada default Android Keystore.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  static const _tokenKey = 'auth_token';

  /// Simpan token ke secure storage.
  /// Token juga disalin ke SharedPreferences agar dapat diakses
  /// oleh background isolate (Workmanager callbackDispatcher).
  static Future<void> saveToken(String token) async {
    try {
      await _storage
          .write(key: _tokenKey, value: token)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await _storage.deleteAll().timeout(const Duration(seconds: 3));
        await _storage
            .write(key: _tokenKey, value: token)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Fallback ke SharedPreferences di bawah jika Keystore device bermasalah
      }
    }
    // Mirror ke SharedPreferences untuk akses background isolate & fallback
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_auth_token', token);
  }

  /// Baca token. Mengembalikan null jika tidak ada token tersimpan.
  static Future<String?> getToken() async {
    try {
      final token = await _storage
          .read(key: _tokenKey)
          .timeout(const Duration(seconds: 5));
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {
      try {
        await _storage.deleteAll().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bg_auth_token');
  }

  /// Hapus token (dipakai saat logout).
  static Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey).timeout(const Duration(seconds: 3));
    } catch (_) {}
    // Hapus juga mirror di SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bg_auth_token');
  }

  /// Baca token dari SharedPreferences (hanya untuk background isolate).
  /// Jangan gunakan di foreground — gunakan [getToken] untuk foreground.
  static Future<String?> getTokenForBackground() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bg_auth_token');
  }
}
