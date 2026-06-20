import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Model untuk satu item presensi offline yang antre untuk di-sync.
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'office_id': officeId,
        'latitude': latitude,
        'longitude': longitude,
        'is_face_valid': isFaceValid,
        'timestamp': timestamp,
        'synced': synced,
      };

  factory OfflinePresenceItem.fromJson(Map<String, dynamic> json) =>
      OfflinePresenceItem(
        id: json['id'] as String,
        officeId: json['office_id'] as int,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        isFaceValid: json['is_face_valid'] as bool,
        timestamp: json['timestamp'] as String,
        synced: json['synced'] as bool? ?? false,
      );
}

/// Antrian presensi offline di shared_preferences.
/// Key: offline_presence_queue (JSON array)
class PresenceQueue {
  static const _key = 'offline_presence_queue';
  static const _uuid = Uuid();

  /// Baca semua item dari queue.
  static Future<List<OfflinePresenceItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => OfflinePresenceItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Tambah item baru ke queue.
  static Future<void> enqueue({
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
  }) async {
    final items = await getAll();
    items.add(OfflinePresenceItem(
      id: _uuid.v4(),
      officeId: officeId,
      latitude: latitude,
      longitude: longitude,
      isFaceValid: isFaceValid,
      timestamp: DateTime.now().toIso8601String(),
    ));
    await _save(items);
  }

  /// Tandai item sebagai synced berdasarkan id.
  static Future<void> markSynced(String id) async {
    final items = await getAll();
    for (final item in items) {
      if (item.id == id) item.synced = true;
    }
    await _save(items);
  }

  /// Hapus semua item yang sudah synced atau bersihkan seluruh queue (logout).
  static Future<void> clearSynced() async {
    final items = await getAll();
    final remaining = items.where((e) => !e.synced).toList();
    await _save(remaining);
  }

  /// Hapus seluruh queue (logout).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _save(List<OfflinePresenceItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
