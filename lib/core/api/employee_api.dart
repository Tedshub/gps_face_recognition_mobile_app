import 'package:dio/dio.dart';
import 'dio_client.dart';

/// API calls untuk endpoint employee.
class EmployeeApi {
  static Dio get _dio => DioClient.instance;

  /// GET /employee/dashboard
  /// Mengembalikan user + today_presence (null jika belum presensi hari ini).
  static Future<Response> getDashboard() async {
    return await _dio.get('/employee/dashboard');
  }

  /// GET /employee/profile
  /// Full profile + face_photos.
  static Future<Response> getProfile() async {
    return await _dio.get('/employee/profile');
  }

  /// GET /employee/face-photos
  /// Hanya URL foto wajah + count.
  static Future<Response> getFacePhotos() async {
    return await _dio.get('/employee/face-photos');
  }

  /// POST /employee/presences
  /// Check-in atau check-out (server auto-deteksi).
  /// Body: { office_id, latitude, longitude, is_face_valid }
  static Future<Response> submitPresence({
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
  }) async {
    return await _dio.post(
      '/employee/presences',
      data: FormData.fromMap({
        'office_id': officeId.toString(),
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'is_face_valid': isFaceValid ? '1' : '0',
      }),
    );
  }

  /// POST /employee/presences/izin
  /// Submit izin/cuti dengan optional dokumen (multipart/form-data).
  static Future<Response> submitIzin({
    required String jenisIzin,
    required String izinKeterangan,
    String? dokumenPath,
  }) async {
    final formData = FormData.fromMap({
      'jenis_izin': jenisIzin,
      'izin_keterangan': izinKeterangan,
      if (dokumenPath != null)
        'izin_dokumen': await MultipartFile.fromFile(
          dokumenPath,
          filename: dokumenPath.split('/').last,
        ),
    });

    return await _dio.post(
      '/employee/presences/izin',
      data: formData,
    );
  }

  /// GET /employee/presences?month=M&year=Y
  /// Riwayat presensi bulanan dengan summary dan holidays.
  static Future<Response> getPresencesHistory(int month, int year) async {
    return await _dio.get(
      '/employee/presences',
      queryParameters: {'month': month, 'year': year},
    );
  }

  /// GET /employee/presences/today
  /// Status presensi hari ini.
  static Future<Response> getTodayPresence() async {
    return await _dio.get('/employee/presences/today');
  }

  /// GET /employee/presences/time-status
  /// Status buka/tutup check-in, check-out, dan izin saat ini.
  static Future<Response> getTimeStatus() async {
    return await _dio.get('/employee/presences/time-status');
  }
}
