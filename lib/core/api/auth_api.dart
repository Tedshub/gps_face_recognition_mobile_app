import 'package:dio/dio.dart';
import 'dio_client.dart';

/// API calls untuk autentikasi: login, logout, me.
class AuthApi {
  static Dio get _dio => DioClient.instance;

  /// Login dengan NIP dan password.
  /// Request: { "nip": int, "password": string }
  /// Response: { "data": { "token": string, "user": {..., "office": {...} } } }
  static Future<Response> login(int nip, String password) async {
    return await _dio.post(
      '/auth/login',
      data: {'nip': nip, 'password': password},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  /// Logout: invalidate token di server.
  static Future<Response> logout() async {
    return await _dio.post('/auth/logout');
  }

  /// Get full profile termasuk face_photos array.
  /// Dipanggil untuk load profil karyawan dan foto wajah
  static Future<Response> profile() async {
    return await _dio.get('/employee/profile');
  }
}
