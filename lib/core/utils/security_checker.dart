import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';
import 'package:geolocator/geolocator.dart';

class SecurityStatus {
  final bool isSafe;
  final String message;

  SecurityStatus({required this.isSafe, this.message = ''});
}

class SecurityChecker {
  /// Memeriksa status keamanan perangkat:
  /// 1. Apakah perangkat di-root / Jailbroken?
  /// 2. Apakah perangkat ini Emulator?
  /// 3. Apakah terdeteksi Mock Location?
  ///
  /// FAIL-SECURE: jika terjadi error pada pengecekan mock location,
  /// akses tetap diblokir untuk mencegah bypass.
  static Future<SecurityStatus> checkDeviceSecurity() async {
    // --- 1. Cek Root / Jailbreak ---
    try {
      final isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        return SecurityStatus(
          isSafe: false,
          message: 'Perangkat terdeteksi Root/Jailbreak. Aplikasi tidak dapat digunakan.',
        );
      }
    } catch (e) {
      debugPrint('Root/jailbreak check error: $e');
      // Jika gagal cek root, tetap lanjut ke cek berikutnya.
    }

    // --- 2. Cek Emulator (hanya release mode) ---
    if (kReleaseMode) {
      try {
        final isRealDevice = await SafeDevice.isRealDevice;
        if (!isRealDevice) {
          return SecurityStatus(
            isSafe: false,
            message: 'Emulator terdeteksi. Harap gunakan perangkat asli.',
          );
        }
      } catch (e) {
        debugPrint('Real device check error: $e');
        // Jika gagal cek emulator, tetap lanjut.
      }
    }

    // --- 3. Cek Mock Location (FAIL-SECURE) ---
    // Jika terjadi error, blokir akses karena tidak bisa memverifikasi keamanan.
    try {
      final isMockLocation = await SafeDevice.isMockLocation;
      if (isMockLocation) {
        return SecurityStatus(
          isSafe: false,
          message: 'Kecurangan GPS (Fake GPS) terdeteksi. Nonaktifkan Fake GPS untuk menggunakan aplikasi.',
        );
      }
    } catch (e) {
      debugPrint('Mock location check error: $e');
      // FAIL-SECURE: tidak dapat memverifikasi mock location → blokir akses.
      return SecurityStatus(
        isSafe: false,
        message: 'Gagal memverifikasi keamanan GPS. Pastikan tidak ada aplikasi Fake GPS aktif.',
      );
    }

    // --- 4. Cek Geolocation isMocked secara langsung (Active Fetching) ---
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        // Izin sudah diberikan, tarik paksa data GPS terbaru dengan timeout singkat (3 detik)
        // agar splash screen tidak terhenti terlalu lama.
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 3),
        );
        if (position.isMocked) {
          return SecurityStatus(
            isSafe: false,
            message: 'Kecurangan GPS (Fake GPS) terdeteksi dari sistem lokasi. Nonaktifkan Fake GPS.',
          );
        }
      }
    } catch (e) {
      debugPrint('Geolocator active fetch check error: $e');
      // Timeout atau GPS mati. 
      // Kita asumsikan aman dulu untuk splash screen, nanti dashboard yang akan menghandle jika GPS mati.
    }

    return SecurityStatus(isSafe: true);
  }
}
