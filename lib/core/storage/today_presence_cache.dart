import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache lokal untuk data presensi hari ini.
/// Data disimpan per tanggal (format yyyy-MM-dd) sehingga data kemarin
/// tidak pernah ditampilkan kembali pada hari berikutnya.
///
/// Key: today_presence_YYYY-MM-DD (contoh: today_presence_2026-06-17)
class TodayPresenceCache {
  static const _prefix = 'today_presence_';

  static String _key(String date) => '$_prefix$date';

  static String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Simpan data presensi hari ini.
  static Future<void> save(Map<String, dynamic> presenceData) async {
    final prefs = await SharedPreferences.getInstance();
    final date = _todayDate();
    await prefs.setString(_key(date), jsonEncode(presenceData));
  }

  /// Baca data presensi untuk hari ini (tanggal = sekarang).
  /// Mengembalikan null jika tidak ada data atau data bukan hari ini.
  static Future<Map<String, dynamic>?> loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayDate();
    final jsonStr = prefs.getString(_key(today));
    
    if (jsonStr == null || jsonStr == 'null') return null;
    
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Simpan informasi bahwa hari ini belum ada presensi (null state).
  static Future<void> saveNull() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_todayDate()), 'null');
  }

  /// Hapus cache hari ini (misal setelah sukses sync ke server dan
  /// ingin memaksa refresh dari server).
  static Future<void> clearToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(_todayDate()));
  }

  /// Hapus semua cache today_presence (saat logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
