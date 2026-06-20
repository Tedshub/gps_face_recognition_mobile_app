import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Model satu item izin yang menunggu dikirim ke server.
class OfflineIzinItem {
  final String id;
  final String jenisIzin;
  final String izinKeterangan;

  /// Path lokal dokumen pendukung (bisa null).
  final String? dokumenPath;

  /// Waktu pengajuan di device (ISO8601).
  final String timestamp;

  bool synced;

  OfflineIzinItem({
    required this.id,
    required this.jenisIzin,
    required this.izinKeterangan,
    this.dokumenPath,
    required this.timestamp,
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'jenis_izin': jenisIzin,
        'izin_keterangan': izinKeterangan,
        'dokumen_path': dokumenPath,
        'timestamp': timestamp,
        'synced': synced,
      };

  factory OfflineIzinItem.fromJson(Map<String, dynamic> json) => OfflineIzinItem(
        id: json['id'] as String,
        jenisIzin: json['jenis_izin'] as String,
        izinKeterangan: json['izin_keterangan'] as String,
        dokumenPath: json['dokumen_path'] as String?,
        timestamp: json['timestamp'] as String,
        synced: json['synced'] as bool? ?? false,
      );
}

/// Antrian offline untuk pengajuan izin/cuti.
/// Key: offline_izin_queue (JSON array)
class IzinQueue {
  static const _key = 'offline_izin_queue';
  static const _uuid = Uuid();

  /// Baca semua item dari queue.
  static Future<List<OfflineIzinItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => OfflineIzinItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Tambah item baru ke antrian.
  static Future<void> enqueue({
    required String jenisIzin,
    required String izinKeterangan,
    String? dokumenPath,
  }) async {
    final items = await getAll();
    items.add(OfflineIzinItem(
      id: _uuid.v4(),
      jenisIzin: jenisIzin,
      izinKeterangan: izinKeterangan,
      dokumenPath: dokumenPath,
      timestamp: DateTime.now().toIso8601String(),
    ));
    await _save(items);
  }

  /// Tandai item sebagai sudah synced.
  static Future<void> markSynced(String id) async {
    final items = await getAll();
    for (final item in items) {
      if (item.id == id) item.synced = true;
    }
    await _save(items);
  }

  /// Hapus item yang sudah synced.
  static Future<void> clearSynced() async {
    final items = await getAll();
    final remaining = items.where((e) => !e.synced).toList();
    await _save(remaining);
  }

  /// Hapus seluruh antrian (saat logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _save(List<OfflineIzinItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
