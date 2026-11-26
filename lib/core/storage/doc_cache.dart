import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache untuk dokumen presensi (seperti surat dokter/izin).
/// Dokumen didownload dari URL dan disimpan di internal storage
/// agar bisa dibuka secara offline. path
class DocCache {
  static String _key(int presenceId) => 'doc_cache_$presenceId';

  /// Path direktori dokumen. Null jika belum dicache.
  static Future<String?> getLocalPath(int presenceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(presenceId));
  }

  /// Download dokumen dari URL dan simpan ke disk.
  /// Lokasi: getApplicationDocumentsDirectory()/izin_docs/{presenceId}.{ext}
  static Future<String?> downloadAndCache(
    int presenceId,
    String url,
    Dio dio,
  ) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/izin_docs');
      if (!await dir.exists()) await dir.create(recursive: true);

      final ext = url.split('.').last.split('?').first;
      final localPath = '${dir.path}/$presenceId.$ext';

      await dio
          .download(url, localPath)
          .timeout(const Duration(seconds: 15));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(presenceId), localPath);
      return localPath;
    } catch (e, stack) {
      debugPrint('DocCache download error: $e\n$stack');
      return null; // Jangan rethrow — biarkan background cache gagal secara diam-diam
    }
  }

  /// Hapus seluruh cache dokumen (saat logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('doc_cache_'));
    for (final k in keys) {
      await prefs.remove(k);
    }
    // Hapus folder izin_docs
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/izin_docs');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
