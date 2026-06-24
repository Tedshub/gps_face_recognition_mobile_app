import 'local_db_helper.dart';
import 'presence_queue.dart';

// ---------------------------------------------------------------------------
// IzinQueue — dipetakan ke OfflineQueueStorage (SQLite, bukan SharedPreferences)
// ---------------------------------------------------------------------------

class OfflineIzinItem {
  final String id;
  final String jenisIzin;
  final String izinKeterangan;

  /// offlineDate: tanggal izin dalam format 'yyyy-MM-dd'
  final String offlineDate;

  /// officeId — diperlukan oleh endpoint offline-sync
  final int officeId;

  /// Path lokal dokumen (tidak didukung oleh endpoint offline-sync, diabaikan saat sync)
  final String? dokumenPath;

  bool synced;

  OfflineIzinItem({
    required this.id,
    required this.jenisIzin,
    required this.izinKeterangan,
    required this.offlineDate,
    required this.officeId,
    this.dokumenPath,
    this.synced = false,
  });

  factory OfflineIzinItem.fromMap(Map<String, dynamic> map) => OfflineIzinItem(
        id: map['id'] as String,
        jenisIzin: map['jenis_izin'] as String? ?? '',
        izinKeterangan: map['izin_keterangan'] as String? ?? '',
        offlineDate: map['offline_date'] as String? ?? '',
        officeId: map['office_id'] as int? ?? 0,
        synced: (map['sync_status'] as String?) == 'synced',
      );
}

class IzinQueue {

  /// Baca semua item izin pending.
  static Future<List<OfflineIzinItem>> getAll() async {
    final rows = await LocalDbHelper.instance.getPendingQueueItems();
    return rows
        .where((r) => r['type'] == 'izin')
        .map((r) => OfflineIzinItem.fromMap(r))
        .toList();
  }

  /// Tambah izin ke antrian dengan officeId dan tanggal izin.
  static Future<void> enqueue({
    required String jenisIzin,
    required String izinKeterangan,
    required int officeId,
    required String offlineDate,
    String? dokumenPath,
  }) async {
    await OfflineQueueStorage.enqueueIzin(
      officeId: officeId,
      offlineDate: offlineDate,
      jenisIzin: jenisIzin,
      izinKeterangan: izinKeterangan,
    );
  }

  static Future<void> markSynced(String id) async {
    await OfflineQueueStorage.markSynced(id);
  }

  static Future<void> clearSynced() async {
    await OfflineQueueStorage.clearSynced();
  }

  static Future<void> clearAll() async {
    await LocalDbHelper.instance.clearAllQueueItems();
  }
}
