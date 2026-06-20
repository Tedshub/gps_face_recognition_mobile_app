import 'package:dio/dio.dart';
import '../storage/auth_storage.dart';

/// Singleton Dio instance dengan:
/// - Base URL dari konstanta
/// - Auth interceptor: inject Bearer token ke setiap request
/// - Response interceptor: handle 401 (clear token + trigger navigation)
/// - Error interceptor: mapping error ke pesan yang bermakna
///
/// Gunakan [DioClient.instance] di seluruh app.
class DioClient {
  static const String baseUrl = 'https://presensimayong.dssrks.co.id/api';

  static Dio? _instance;

  /// Callback yang dipanggil saat 401 diterima (navigate ke /login).
  /// Set di main.dart setelah GoRouter siap.
  static void Function()? onUnauthorized;

  static Dio get instance {
    _instance ??= _createDio();
    return _instance!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          // Content-Type sengaja TIDAK di-set di sini agar Dio otomatis
          // menyesuaikannya: 'application/json' untuk Map, dan
          // 'multipart/form-data' untuk FormData
        },
      ),
    );

    // Auth interceptor: tambahkan Bearer token ke setiap request
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await AuthStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException err, handler) async {
          if (err.response?.statusCode == 401) {
            // Cegah infinite loop: jangan panggil onUnauthorized jika error 401 
            // berasal dari endpoint login atau logout itu sendiri.
            final path = err.requestOptions.path;
            if (!path.contains('/auth/login') && !path.contains('/auth/logout')) {
              await AuthStorage.deleteToken();
              onUnauthorized?.call();
            }
          }
          return handler.next(err);
        },
      ),
    );

    return dio;
  }

  /// Reset instance (berguna saat testing atau ganti base URL).
  static void reset() {
    _instance = null;
  }
}
