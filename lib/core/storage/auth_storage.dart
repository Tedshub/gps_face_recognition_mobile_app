import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper untuk flutter_secure_storage.
/// Menyimpan dan membaca Bearer token autentikasi Laravel Sanctum.
class AuthStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  /// Simpan token ke secure storage.
  /// Token juga disalin ke SharedPreferences agar dapat diakses
  /// oleh background isolate (Workmanager callbackDispatcher).
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    // Mirror ke SharedPreferences untuk akses background isolate
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_auth_token', token);
  }

  /// Baca token. Mengembalikan null jika tidak ada token tersimpan.
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Hapus token (dipakai saat logout).
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
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
