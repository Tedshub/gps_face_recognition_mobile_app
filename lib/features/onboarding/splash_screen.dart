import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/security_checker.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSecurityAndProceed();
  }

  Future<void> _checkSecurityAndProceed() async {
    // Memberikan sedikit waktu render agar splash screen muncul (mencegah blank screen)
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final status = await SecurityChecker.checkDeviceSecurity();
    
    if (!mounted) return;

    if (!status.isSafe) {
      // Jika terdeteksi fake GPS / emulator / root, blokir.
      context.go('/security-blocked');
    } else {
      // Jika aman, lanjut ke dashboard. 
      // (GoRouter otomatis akan meredirect ke /onboarding atau /login jika belum auth).
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF22C55E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo sederhana
            Icon(
              Icons.fingerprint, // atau Icons.location_on
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 24),
            Text(
              'Presensi App',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(
              color: Colors.white,
            ),
            SizedBox(height: 16),
            Text(
              'Memeriksa keamanan...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
