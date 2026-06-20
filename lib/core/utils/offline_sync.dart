import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api/employee_api.dart';
import '../storage/presence_queue.dart';
import '../storage/izin_queue.dart';

/// Mengelola sinkronisasi presensi dan izin offline ke server.
///
/// Cara kerja:
/// 1. Subscribe ke connectivity_plus stream. Saat koneksi kembali:
///    - Baca queue presensi dari shared_preferences, kirim ke server
///    - Baca queue izin dari shared_preferences, kirim ke server
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

  /// Mulai mendengarkan perubahan konektivitas.
  static void startListening() {
    _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.any(
        (r) => r == ConnectivityResult.mobile || r == ConnectivityResult.wifi,
      );
      if (hasConnection) {
        syncNow();
      }
    });
  }

  static bool _isSyncing = false;

  /// Jalankan sync segera (dipanggil saat app resume, koneksi kembali,
  /// atau startup saat online).
  ///
  /// Urutan:
  /// 1. Proses antrian presensi offline
  /// 2. Proses antrian izin offline
  /// 3. Tampilkan notifikasi + panggil callback jika ada yang berhasil
  static Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      int successCount = 0;

      // --- Sync antrian presensi ---
      final presenceItems = await PresenceQueue.getAll();
      final unsyncedPresences = presenceItems.where((e) => !e.synced).toList();

      for (final item in unsyncedPresences) {
        try {
          await EmployeeApi.submitPresence(
            officeId: item.officeId,
            latitude: item.latitude,
            longitude: item.longitude,
            isFaceValid: item.isFaceValid,
          );
          await PresenceQueue.markSynced(item.id);
          successCount++;
        } on DioException catch (e) {
          if (e.response != null &&
              (e.response!.statusCode == 422 ||
                  e.response!.statusCode == 400 ||
                  e.response!.statusCode == 403)) {
            // Error dari server (misal validasi gagal, jarak terlalu jauh, dll)
            // Hapus dari antrian agar tidak macet selamanya.
            await PresenceQueue.markSynced(item.id);
            successCount++; // Paksa UI refresh untuk menampilkan state dari server
          }
        } catch (_) {
          // Biarkan untuk percobaan berikutnya (network error)
        }
      }
      await PresenceQueue.clearSynced();

      // --- Sync antrian izin ---
      final izinItems = await IzinQueue.getAll();
      final unsyncedIzin = izinItems.where((e) => !e.synced).toList();

      for (final item in unsyncedIzin) {
        try {
          await EmployeeApi.submitIzin(
            jenisIzin: item.jenisIzin,
            izinKeterangan: item.izinKeterangan,
            dokumenPath: item.dokumenPath,
          );
          await IzinQueue.markSynced(item.id);
          successCount++;
        } on DioException catch (e) {
          if (e.response != null &&
              (e.response!.statusCode == 422 ||
                  e.response!.statusCode == 400 ||
                  e.response!.statusCode == 403)) {
            await IzinQueue.markSynced(item.id);
            successCount++;
          }
        } catch (_) {
          // Biarkan untuk percobaan berikutnya
        }
      }
      await IzinQueue.clearSynced();

      // --- Notifikasi + callback ---
      if (successCount > 0) {
        // Panggil callback agar UI dapat refresh data terbaru dari server
        onSyncCompleted?.call();

        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            SnackBar(
              content: Text(
                '$successCount data offline berhasil diproses sinkronisasi',
              ),
              backgroundColor: const Color(0xFF22c55e),
            ),
          );
        }
      }
    } finally {
      _isSyncing = false;
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
