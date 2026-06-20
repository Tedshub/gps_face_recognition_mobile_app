import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache riwayat presensi bulanan di shared_preferences.
/// Key: history_cache_YYYY_MM (contoh: history_cache_2026_06)
/// Cache dianggap stale setelah 5 menit jika online.
class HistoryCache {
  static String _key(int year, int month) =>
      'history_cache_${year}_${month.toString().padLeft(2, '0')}';

  static String _timestampKey(int year, int month) =>
      'history_cache_ts_${year}_${month.toString().padLeft(2, '0')}';

  /// Simpan data history bulanan ke cache.
  static Future<void> save(int year, int month, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(year, month), jsonEncode(data));
    await prefs.setInt(
      _timestampKey(year, month),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Baca cache. Mengembalikan null jika tidak ada.
  static Future<Map<String, dynamic>?> load(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key(year, month));
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  /// Cek apakah cache masih fresh (< 5 menit).
  static Future<bool> isFresh(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_timestampKey(year, month));
    if (ts == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age < 5 * 60 * 1000; // 5 menit
  }

  /// Hapus semua cache history (saat logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) => k.startsWith('history_cache_'),
    );
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
