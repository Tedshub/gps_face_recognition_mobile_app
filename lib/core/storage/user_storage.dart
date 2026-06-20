import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper shared_preferences untuk data user dan office.
/// Key 'user_data' berisi JSON dari response login/me.
class UserStorage {
  static const _userKey = 'user_data';
  static const _facePhotosKey = 'face_photos_local';

  /// Simpan data user (JSON string dari response API).
  static Future<void> saveUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userData));
  }

  /// Baca data user. Mengembalikan null jika belum ada.
  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_userKey);
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  /// Simpan list path lokal foto wajah.
  static Future<void> saveFacePhotosPaths(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_facePhotosKey, jsonEncode(paths));
  }

  /// Baca list path lokal foto wajah.
  static Future<List<String>> getFacePhotosPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_facePhotosKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => e.toString()).toList();
  }

  /// Hapus semua data user (saat logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_facePhotosKey);
  }
}
