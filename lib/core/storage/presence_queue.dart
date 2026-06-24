import 'package:uuid/uuid.dart';
import 'local_db_helper.dart';

/// Model untuk satu item dalam antrian offline.
/// Mendukung tipe: check_in, check_out, izin.
class OfflineQueueItem {
  final String id;

  /// Tipe record: 'check_in' | 'check_out' | 'izin'
  final String type;

  final int officeId;
  final bool isFaceValid;

  /// Waktu check-in asli (format: 'yyyy-MM-dd HH:mm:ss')
  final String? checkInTime;

  /// Waktu check-out asli (format: 'yyyy-MM-dd HH:mm:ss') — hanya untuk check_out
  final String? checkOutTime;

  /// Tanggal izin (format: 'yyyy-MM-dd') — hanya untuk izin
  final String? offlineDate;

  final double? latitude;
  final double? longitude;

  final String? jenisIzin;
  final String? izinKeterangan;

  final String syncStatus; // 'pending' | 'synced' | 'failed'
  final String? errorMessage;
  final String createdAt;

  OfflineQueueItem({
    required this.id,
    required this.type,
    required this.officeId,
    this.isFaceValid = false,
    this.checkInTime,
    this.checkOutTime,
    this.offlineDate,
    this.latitude,
    this.longitude,
    this.jenisIzin,
    this.izinKeterangan,
    this.syncStatus = 'pending',
    this.errorMessage,
    required this.createdAt,
  });

  factory OfflineQueueItem.fromMap(Map<String, dynamic> map) => OfflineQueueItem(
        id: map['id'] as String,
        type: map['type'] as String,
        officeId: map['office_id'] as int,
        isFaceValid: (map['is_face_valid'] as int? ?? 0) == 1,
        checkInTime: map['check_in_time'] as String?,
        checkOutTime: map['check_out_time'] as String?,
        offlineDate: map['offline_date'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        jenisIzin: map['jenis_izin'] as String?,
        izinKeterangan: map['izin_keterangan'] as String?,
        syncStatus: map['sync_status'] as String? ?? 'pending',
        errorMessage: map['error_message'] as String?,
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'type': type,
        'office_id': officeId,
        'is_face_valid': isFaceValid ? 1 : 0,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'offline_date': offlineDate,
        'latitude': latitude,
        'longitude': longitude,
        'jenis_izin': jenisIzin,
        'izin_keterangan': izinKeterangan,
        'is_synced': 0,
        'sync_status': syncStatus,
        'error_message': errorMessage,
        'created_at': createdAt,
      };

  /// Konversi ke payload record untuk endpoint offline-sync.
  Map<String, dynamic> toApiRecord() {
    final record = <String, dynamic>{
      'type': type,
      'office_id': officeId,
      'is_offline_sync': true,
    };

    switch (type) {
      case 'check_in':
        record['is_face_valid'] = isFaceValid;
        record['check_in_time'] = checkInTime;
        record['latitude'] = latitude;
        record['longitude'] = longitude;
        break;
      case 'check_out':
        record['is_face_valid'] = isFaceValid;
        record['check_in_time'] = checkInTime;
        record['check_out_time'] = checkOutTime;
        record['latitude'] = latitude;
        record['longitude'] = longitude;
        break;
      case 'izin':
        record['offline_date'] = offlineDate;
        record['jenis_izin'] = jenisIzin;
        record['izin_keterangan'] = izinKeterangan;
        break;
    }

    return record;
  }
}

/// Antrian offline terpadu (check_in, check_out, izin) di SQLite.
class OfflineQueueStorage {
  static const _uuid = Uuid();

  /// Ambil semua item pending urut dari terlama.
  static Future<List<OfflineQueueItem>> getPending() async {
    final rows = await LocalDbHelper.instance.getPendingQueueItems();
    return rows.map((r) => OfflineQueueItem.fromMap(r)).toList();
  }

  /// Enqueue check-in offline.
  static Future<void> enqueueCheckIn({
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
    required String checkInTime, // format: 'yyyy-MM-dd HH:mm:ss'
  }) async {
    final item = OfflineQueueItem(
      id: _uuid.v4(),
      type: 'check_in',
      officeId: officeId,
      isFaceValid: isFaceValid,
      checkInTime: checkInTime,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now().toIso8601String(),
    );
    await LocalDbHelper.instance.insertOfflineQueueItem(item.toInsertMap());
  }

  /// Enqueue check-out offline.
  static Future<void> enqueueCheckOut({
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
    required String checkInTime,  // waktu check-in asli
    required String checkOutTime, // waktu check-out asli
  }) async {
    final item = OfflineQueueItem(
      id: _uuid.v4(),
      type: 'check_out',
      officeId: officeId,
      isFaceValid: isFaceValid,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now().toIso8601String(),
    );
    await LocalDbHelper.instance.insertOfflineQueueItem(item.toInsertMap());
  }

  /// Enqueue izin offline.
  static Future<void> enqueueIzin({
    required int officeId,
    required String offlineDate, // format: 'yyyy-MM-dd'
    required String jenisIzin,
    required String izinKeterangan,
  }) async {
    final item = OfflineQueueItem(
      id: _uuid.v4(),
      type: 'izin',
      officeId: officeId,
      offlineDate: offlineDate,
      jenisIzin: jenisIzin,
      izinKeterangan: izinKeterangan,
      createdAt: DateTime.now().toIso8601String(),
    );
    await LocalDbHelper.instance.insertOfflineQueueItem(item.toInsertMap());
  }

  /// Tandai item berhasil disinkronkan.
  static Future<void> markSynced(String id) async {
    await LocalDbHelper.instance.markQueueItemSynced(id);
  }

  /// Tandai item gagal dengan pesan error.
  static Future<void> markFailed(String id, String errorMessage) async {
    await LocalDbHelper.instance.markQueueItemFailed(id, errorMessage);
  }

  /// Hapus item yang sudah berhasil disinkronkan.
  static Future<void> clearSynced() async {
    await LocalDbHelper.instance.deleteSyncedQueueItems();
  }

  /// Hapus semua antrian (saat logout).
  static Future<void> clearAll() async {
    await LocalDbHelper.instance.clearAllQueueItems();
  }
}

// ---------------------------------------------------------------------------
// Backward-compat: PresenceQueue (dipetakan ke OfflineQueueStorage)
// ---------------------------------------------------------------------------

class OfflinePresenceItem {
  final String id;
  final int officeId;
  final double latitude;
  final double longitude;
  final bool isFaceValid;
  final String timestamp;
  bool synced;

  OfflinePresenceItem({
    required this.id,
    required this.officeId,
    required this.latitude,
    required this.longitude,
    required this.isFaceValid,
    required this.timestamp,
    this.synced = false,
  });
}

class PresenceQueue {

  static Future<List<OfflinePresenceItem>> getAll() async {
    final rows = await LocalDbHelper.instance.getPendingQueueItems();
    return rows
        .where((r) => r['type'] == 'check_in' || r['type'] == 'check_out')
        .map((r) => OfflinePresenceItem(
              id: r['id'] as String,
              officeId: r['office_id'] as int,
              latitude: (r['latitude'] as num?)?.toDouble() ?? 0.0,
              longitude: (r['longitude'] as num?)?.toDouble() ?? 0.0,
              isFaceValid: (r['is_face_valid'] as int? ?? 0) == 1,
              timestamp: (r['check_in_time'] ?? r['created_at']) as String,
            ))
        .toList();
  }

  static Future<void> enqueue({
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
  }) async {
    final now = DateTime.now();
    final formatted =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await OfflineQueueStorage.enqueueCheckIn(
      officeId: officeId,
      latitude: latitude,
      longitude: longitude,
      isFaceValid: isFaceValid,
      checkInTime: formatted,
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
