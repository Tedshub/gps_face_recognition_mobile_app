import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper untuk flutter_secure_storage.
/// Menyimpan dan membaca Bearer token autentikasi Laravel Sanctum.
class AuthStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  /// Simpan token ke secure storage.
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Baca token. Mengembalikan null jika tidak ada token tersimpan.
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Hapus token (dipakai saat logout).
  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }
}
