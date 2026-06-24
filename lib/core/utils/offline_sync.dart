import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api/employee_api.dart';
import '../storage/presence_queue.dart';
import '../services/background_sync_service.dart';

/// Mengelola sinkronisasi presensi dan izin offline ke server
/// menggunakan endpoint bulk: POST /employee/presences/offline-sync
///
/// Cara kerja:
/// 1. Subscribe ke connectivity_plus stream. Saat koneksi kembali:
///    - Baca semua item pending (check_in, check_out, izin) dari SQLite
///    - Kirim sebagai satu batch ke endpoint offline-sync
///    - Proses hasil per-record (success/skipped → hapus, failed → tandai)
/// 2. Juga dijalankan saat AppLifecycleState.resumed (dari DashboardScreen).
/// 3. Callback [onSyncCompleted] dipanggil jika ada item yang berhasil
///    ter-sync agar UI dapat refresh.
class OfflineSync {
  static final Connectivity _connectivity = Connectivity();
  static BuildContext? _context;

  /// Callback yang dipanggil setelah sync berhasil (minimal 1 item).
  /// Dapat diset dari DashboardNotifier untuk memicu refresh UI.
  static void Function()? onSyncCompleted;

  /// Set context untuk menampilkan SnackBar.
  static void setContext(BuildContext context) {
    _context = context;
  }

  static bool? _lastConnectionStatus;

  /// Mulai mendengarkan perubahan konektivitas.
  static void startListening() {
    _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.any(
        (r) => r == ConnectivityResult.mobile || r == ConnectivityResult.wifi,
      );

      if (_lastConnectionStatus != null && _lastConnectionStatus != hasConnection) {
        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            SnackBar(
              content: Text(
                hasConnection ? 'Koneksi terhubung. Anda sedang online.' : 'Koneksi terputus. Anda sedang offline.',
              ),
              backgroundColor: hasConnection ? Colors.green : Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      _lastConnectionStatus = hasConnection;

      if (hasConnection) {
        // Tunda eksekusi 2 detik untuk memastikan DNS/DHCP Android sudah benar-benar siap
        // setelah transisi jaringan (mencegah SocketException: Failed host lookup).
        Future.delayed(const Duration(seconds: 2), () {
          syncNow();
          BackgroundSyncService.scheduleImmediateSync();
        });
      }
    });
  }

  static Future<void>? _syncTask;

  /// Jalankan sync segera (dipanggil saat app resume, koneksi kembali,
  /// atau startup saat online).
  ///
  /// Urutan:
  /// 1. Ambil semua item pending dari SQLite (check_in, check_out, izin)
  /// 2. Urutkan: check_in sebelum check_out, dari tanggal terlama ke terbaru
  /// 3. Kirim sebagai batch ke POST /employee/presences/offline-sync
  /// 4. Proses hasil per-record dari server
  static Future<void> syncNow() async {
    if (_syncTask != null) {
      await _syncTask;
      return;
    }

    _syncTask = _doSyncNow();
    try {
      await _syncTask;
    } finally {
      _syncTask = null;
    }
  }

  static Future<void> _doSyncNow() async {
      // Ambil semua item pending dari SQLite
      final pendingItems = await OfflineQueueStorage.getPending();

      if (pendingItems.isEmpty) return;

      // Urutkan: terlama dulu, check_in sebelum check_out di tanggal yang sama
      pendingItems.sort((a, b) {
        final aTime = a.checkInTime ?? a.offlineDate ?? a.createdAt;
        final bTime = b.checkInTime ?? b.offlineDate ?? b.createdAt;
        final timeCompare = aTime.compareTo(bTime);
        if (timeCompare != 0) return timeCompare;
        // Prioritas tipe: check_in(0) < izin(1) < check_out(2)
        const order = {'check_in': 0, 'izin': 1, 'check_out': 2};
        return (order[a.type] ?? 1).compareTo(order[b.type] ?? 1);
      });

      // Batasi 50 record per batch (sesuai limit endpoint)
      const batchSize = 50;
      int totalSuccessCount = 0;

      for (int start = 0; start < pendingItems.length; start += batchSize) {
        final batch = pendingItems.sublist(
          start,
          (start + batchSize).clamp(0, pendingItems.length),
        );

        final records = batch.map((item) => item.toApiRecord()).toList();

        try {
          final response = await EmployeeApi.syncOfflinePresences(records);
          final data = response.data as Map<String, dynamic>?;

          if (data != null && data['success'] == true) {
            final results = data['data']?['results'] as List<dynamic>? ?? [];

            for (int i = 0; i < results.length && i < batch.length; i++) {
              final result = results[i] as Map<String, dynamic>;
              final item = batch[i];
              final status = result['status'] as String? ?? 'failed';

              if (status == 'success' || status == 'skipped') {
                // Hapus dari antrian (sukses maupun duplikat)
                await OfflineQueueStorage.markSynced(item.id);
                totalSuccessCount++;
              } else {
                // Gagal — tandai agar tidak dikirim ulang terus-menerus
                final msg = result['message'] as String? ?? 'Gagal diproses server';
                await OfflineQueueStorage.markFailed(item.id, msg);
              }
            }
          } else {
             // Berhasil hit endpoint tapi format success bukan true, mungkin error logic dari backend.
             if (_context != null && _context!.mounted) {
               ScaffoldMessenger.of(_context!).showSnackBar(
                 SnackBar(content: Text('Sync ditolak server: ${response.data}')),
               );
             }
          }
        } on DioException catch (e) {
          // Jika validasi struktur gagal (422) → tandai semua sebagai failed
          if (e.response != null &&
              (e.response!.statusCode == 422 ||
                  e.response!.statusCode == 400)) {
            for (final item in batch) {
              final msg = e.response?.data['message'] as String? ??
                  'Validasi struktur request gagal';
              await OfflineQueueStorage.markFailed(item.id, msg);
            }
            if (_context != null && _context!.mounted) {
              ScaffoldMessenger.of(_context!).showSnackBar(
                SnackBar(content: Text('Gagal Sync: ${e.response?.statusCode} - ${e.response?.data}')),
              );
            }
          } else {
            // 401/403/500/network error → biarkan, coba lagi berikutnya
            if (_context != null && _context!.mounted) {
              if (e.response != null) {
                ScaffoldMessenger.of(_context!).showSnackBar(
                  SnackBar(content: Text('Error Sync Server: ${e.response?.statusCode} - ${e.response?.data}')),
                );
              } else {
                ScaffoldMessenger.of(_context!).showSnackBar(
                  SnackBar(content: Text('Gagal terhubung ke server (Network/Timeout). Pesan: ${e.message}')),
                );
              }
            }
          }
        } catch (e) {
          // Network error — biarkan semua item tetap pending
          if (_context != null && _context!.mounted) {
            ScaffoldMessenger.of(_context!).showSnackBar(
              SnackBar(content: Text('Koneksi Error saat Sync: $e')),
            );
          }
        }
      }

      // Bersihkan item yang sudah synced
      await OfflineQueueStorage.clearSynced();

      // --- Notifikasi + callback ---
      if (totalSuccessCount > 0) {
        onSyncCompleted?.call();

        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            SnackBar(
              content: Text(
                '$totalSuccessCount data offline berhasil disinkronisasi',
              ),
              backgroundColor: const Color(0xFF22c55e),
            ),
          );
        }
      }
  }

  /// Cek apakah device saat ini terhubung ke internet.
  static Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return results.any(
      (r) => r == ConnectivityResult.mobile || r == ConnectivityResult.wifi,
    );
  }
}
