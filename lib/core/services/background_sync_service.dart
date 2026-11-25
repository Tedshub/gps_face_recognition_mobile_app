import 'dart:convert';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/presence_queue.dart';

// ===========================================================================
// PENTING: callbackDispatcher berjalan di isolate terpisah dari Flutter UI.
//
// Batasan isolate background:
//  - TIDAK bisa akses FlutterSecureStorage (butuh Flutter engine aktif)
//  - TIDAK bisa pakai Dio dengan interceptor Flutter
//  - BISA akses SharedPreferences (native Android SharedPreferences)
//  - BISA akses SQLite via sqflite
//  - BISA buat HTTP request via dart:io HttpClient
//
// Oleh karena itu:
//  - Token dibaca dari SharedPreferences (key: 'bg_auth_token')
//    yang di-mirror saat login/saveToken di AuthStorage
//  - HTTP request dibuat manual dengan dart:io HttpClient
// ===========================================================================

const String _baseUrl = 'https://presensimayong.my.id/api';
const String _syncEndpoint = '$_baseUrl/employee/presences/offline-sync';

/// Dispatcher yang dipanggil Workmanager saat task background berjalan.
/// Harus top-level function dan ditandai @pragma('vm:entry-point').
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 1. Cek konektivitas
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult.contains(ConnectivityResult.none) ||
          connectivityResult.isEmpty;

      if (isOffline) {
        // Belum ada koneksi — retry nanti oleh Workmanager
        return false;
      }

      // 2. Baca token dari SharedPreferences (accessible dari background isolate)
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('bg_auth_token');

      if (token == null || token.isEmpty) {
        // Belum login — tidak ada yang perlu di-sync
        return true;
      }

      // 3. Ambil semua antrian pending dari SQLite
      final pendingItems = await OfflineQueueStorage.getPending();

      if (pendingItems.isEmpty) {
        return true;
      }

      // 4. Urutkan: terlama dulu, check_in sebelum check_out di hari yang sama
      pendingItems.sort((a, b) {
        final aTime = a.checkInTime ?? a.offlineDate ?? a.createdAt;
        final bTime = b.checkInTime ?? b.offlineDate ?? b.createdAt;
        final timeCompare = aTime.compareTo(bTime);
        if (timeCompare != 0) return timeCompare;
        const order = {'check_in': 0, 'izin': 1, 'check_out': 2};
        return (order[a.type] ?? 1).compareTo(order[b.type] ?? 1);
      });

      // 5. Kirim batch ke server (maks 50 sesuai limit endpoint)
      const batchSize = 50;
      bool allSuccess = true;

      for (int start = 0; start < pendingItems.length; start += batchSize) {
        final batch = pendingItems.sublist(
          start,
          (start + batchSize).clamp(0, pendingItems.length),
        );

        final records = batch.map((item) => item.toApiRecord()).toList();

        try {
          final success = await _postOfflineSync(token, records, batch);
          if (!success) allSuccess = false;
        } catch (e) {
          allSuccess = false;
          // Network error — biarkan, retry oleh Workmanager
        }
      }

      // 6. Hapus item yang sudah synced dari SQLite
      await OfflineQueueStorage.clearSynced();

      return allSuccess;
    } catch (e) {
      return false;
    }
  });
}

/// Kirim batch records ke endpoint offline-sync menggunakan dart:io HttpClient.
/// Mengembalikan true jika setidaknya komunikasi dengan server berhasil.
Future<bool> _postOfflineSync(
  String token,
  List<Map<String, dynamic>> records,
  List<OfflineQueueItem> batch,
) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 20);

  try {
    final uri = Uri.parse(_syncEndpoint);
    final request = await client.postUrl(uri);

    // Set headers
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');

    // Set body
    final body = jsonEncode({'records': records});
    request.headers.contentLength = utf8.encode(body).length;
    request.write(body);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      final data = jsonDecode(responseBody) as Map<String, dynamic>?;

      if (data != null && data['success'] == true) {
        final results = data['data']?['results'] as List<dynamic>? ?? [];

        for (int i = 0; i < results.length && i < batch.length; i++) {
          final result = results[i] as Map<String, dynamic>;
          final item = batch[i];
          final status = result['status'] as String? ?? 'failed';

          if (status == 'success' || status == 'skipped') {
            await OfflineQueueStorage.markSynced(item.id);
          } else {
            final msg = result['message'] as String? ?? 'Gagal diproses server';
            await OfflineQueueStorage.markFailed(item.id, msg);
          }
        }
        return true;
      }
    } else if (response.statusCode == 422 || response.statusCode == 400) {
      // Validasi struktur gagal — tandai semua sebagai failed
      for (final item in batch) {
        await OfflineQueueStorage.markFailed(item.id, 'Validasi request gagal (${response.statusCode})');
      }
      return true; // Komunikasi berhasil, meski data ditolak
    } else if (response.statusCode == 401) {
      // Token expired — jangan retry terus-menerus
      return true;
    }

    return false;
  } finally {
    client.close();
  }
}

// ===========================================================================
// BackgroundSyncService — konfigurasi dan registrasi task Workmanager
// ===========================================================================

class BackgroundSyncService {
  static const String _syncTaskName = 'presenceSyncTask';
  static const String _uniqueTaskId = 'presenceSyncUnique';

  /// Inisialisasi Workmanager. Harus dipanggil di main() sebelum runApp().
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  /// Daftarkan periodic task untuk sinkronisasi otomatis.
  ///
  /// - [frequency]: seberapa sering task dijalankan (minimum 15 menit di Android)
  /// - Task hanya berjalan saat ada koneksi internet (constraint: networkType.connected)
  /// - [existingWorkPolicy.keep]: jika task sudah terdaftar, tidak override
  static void registerPeriodicSync({
    Duration frequency = const Duration(minutes: 15),
  }) {
    Workmanager().registerPeriodicTask(
      _uniqueTaskId,
      _syncTaskName,
      frequency: frequency,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  /// Jalankan sinkronisasi sekali-jalan segera (one-time task).
  /// Berguna untuk memicu sync saat koneksi baru pulih di background.
  static void scheduleImmediateSync() {
    Workmanager().registerOneOffTask(
      '${_uniqueTaskId}_oneoff_${DateTime.now().millisecondsSinceEpoch}',
      _syncTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  /// Batalkan semua task yang terdaftar (saat logout).
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }

  /// Batalkan hanya periodic task (jika perlu re-register).
  static Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(_uniqueTaskId);
  }
}
