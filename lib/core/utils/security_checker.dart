import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

class SecurityStatus {
  final bool isSafe;
  final String message;

  SecurityStatus({required this.isSafe, this.message = ''});
}

class SecurityChecker {
  /// Memeriksa status keamanan perangkat:
  /// 1. Apakah perangkat di-root / Jailbroken?
  /// 2. Apakah terdeteksi Mock Location?
  /// 3. Apakah perangkat ini Emulator? (opsional, bisa dinonaktifkan jika testing di emulator)
  static Future<SecurityStatus> checkDeviceSecurity() async {
    try {
      // 1. Cek Root / Jailbreak
      final isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        return SecurityStatus(
          isSafe: false,
          message: 'Perangkat terdeteksi Root/Jailbreak. Aplikasi tidak dapat digunakan.',
        );
      }

      // 2. Cek Emulator
      // Jika Anda mengembangkan aplikasi dan perlu mengetes di emulator,
      // Anda bisa membungkus pengecekan ini dengan kDebugMode:
      if (kReleaseMode) {
        final isRealDevice = await SafeDevice.isRealDevice;
        if (!isRealDevice) {
          return SecurityStatus(
            isSafe: false,
            message: 'Emulator terdeteksi. Harap gunakan perangkat asli.',
          );
        }
      }

      // 3. Cek Mock Location dari safe_device
      // (Geolocator juga akan mengecek ini secara real-time pada stream)
      final isMockLocation = await SafeDevice.isMockLocation;
      if (isMockLocation) {
        return SecurityStatus(
          isSafe: false,
          message: 'Kecurangan GPS (Mock Location) terdeteksi. Aplikasi tidak dapat digunakan.',
        );
      }

      return SecurityStatus(isSafe: true);
    } catch (e) {
      debugPrint('Security check error: $e');
      // Jika terjadi error saat mengecek, asumsikan aman sementara,
      // atau bisa juga diblokir. Kita asumsikan aman agar tidak memblokir user secara salah.
      return SecurityStatus(isSafe: true);
    }
  }
}
