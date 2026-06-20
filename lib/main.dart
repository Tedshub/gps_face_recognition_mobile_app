import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/dio_client.dart';
import 'features/auth/auth_notifier.dart';
import 'features/dashboard/dashboard_notifier.dart';
import 'navigation/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // ProviderScope diperlukan untuk flutter_riverpod
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();

    // Set Dio 401 callback: ketika token invalid, redirect ke /login
    DioClient.onUnauthorized = () {
      ref.read(authProvider.notifier).logout();
    };

    // Restore session dari secure storage saat app launch.
    // Setelah session berhasil di-restore dan user authenticated,
    // startupRefresh() akan dipanggil untuk:
    //   - Jika online: sync queue offline + refresh semua data dari server
    //   - Jika offline: load data lokal (user + presensi hari ini dari cache)
    Future.microtask(() async {
      await ref.read(authProvider.notifier).restoreSession();
      final authState = ref.read(authProvider);
      if (authState.status == AuthStatus.authenticated) {
        ref.read(dashboardProvider.notifier).startupRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Presensi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.light,
        ).copyWith(
          surface: Colors.white,
          primary: const Color(0xFF22C55E),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F2937),
          elevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFFF0FDF4),
          contentTextStyle: const TextStyle(color: Color(0xFF1F2937)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFDCFCE7),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Color(0xFF16A34A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              );
            }
            return const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(
                color: Color(0xFF16A34A),
                size: 24,
              );
            }
            return const IconThemeData(
              color: Color(0xFF9CA3AF),
              size: 24,
            );
          }),
        ),
      ),
      routerConfig: router,
    );
  }
}
