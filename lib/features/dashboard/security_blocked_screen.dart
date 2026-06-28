import 'package:flutter/material.dart';

/// Layar pemblokiran akses yang ditampilkan saat Fake GPS / Mock Location
/// terdeteksi aktif pada perangkat.
///
/// Layar ini bersifat terminal — tidak ada tombol, tidak ada navigasi balik.
/// User harus menutup aplikasi sepenuhnya, menonaktifkan Fake GPS,
/// lalu membuka ulang aplikasi.
class SecurityBlockedScreen extends StatelessWidget {
  const SecurityBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Cegah tombol back sistem agar user tidak dapat melewati blokir.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ikon peringatan
              const Icon(
                Icons.gpp_bad_outlined,
                size: 96,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(height: 28),
              // Judul
              const Text(
                'Akses Ditolak',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              // Pesan
              const Text(
                'Kecurangan GPS terdeteksi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
