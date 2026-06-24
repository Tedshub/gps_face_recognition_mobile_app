import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../storage/auth_storage.dart';
import '../storage/local_db_helper.dart';

/// Singleton Dio instance dengan:
/// - Base URL dari konstanta
/// - Auth interceptor: inject Bearer token ke setiap request
/// - Response interceptor: handle 401 (clear token + trigger navigation)
/// - Caching interceptor: cache GET requests & fallback to cache if offline
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

    // Interceptors
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await AuthStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Offline Cache Logic for GET requests
          if (options.method == 'GET') {
            final connectivityResult = await Connectivity().checkConnectivity();
            final isOffline = connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty;
            
            if (isOffline) {
              final cachedData = await LocalDbHelper.instance.getCache(options.uri.toString());
              if (cachedData != null) {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    data: jsonDecode(cachedData),
                    statusCode: 200,
                    statusMessage: 'OK (Cached)',
                  ),
                );
              }
            }
          }

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // Save Cache Logic for GET requests
          if (response.requestOptions.method == 'GET' && response.statusCode == 200) {
            final endpoint = response.requestOptions.uri.toString();
            try {
              final stringData = jsonEncode(response.data);
              await LocalDbHelper.instance.saveCache(endpoint, stringData);
            } catch (e) {
              // Ignore if cannot be JSON encoded
            }
          }
          return handler.next(response);
        },
        onError: (DioException err, handler) async {
          // Fallback to cache if request fails due to network issues
          if (err.requestOptions.method == 'GET' && _isNetworkError(err)) {
            final cachedData = await LocalDbHelper.instance.getCache(err.requestOptions.uri.toString());
            if (cachedData != null) {
              return handler.resolve(
                Response(
                  requestOptions: err.requestOptions,
                  data: jsonDecode(cachedData),
                  statusCode: 200,
                  statusMessage: 'OK (Cached fallback)',
                ),
              );
            }
          }

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

  static bool _isNetworkError(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
           err.type == DioExceptionType.sendTimeout ||
           err.type == DioExceptionType.receiveTimeout ||
           err.type == DioExceptionType.connectionError ||
           err.type == DioExceptionType.unknown;
  }

  /// Reset instance (berguna saat testing atau ganti base URL).
  static void reset() {
    _instance = null;
  }
}
