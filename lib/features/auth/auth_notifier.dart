import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/auth_api.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/storage/user_storage.dart';
import '../../core/storage/face_storage.dart';
import '../../core/storage/history_cache.dart';
import '../../core/storage/presence_queue.dart';
import '../../core/storage/izin_queue.dart';
import '../../core/storage/today_presence_cache.dart';
import '../../core/storage/doc_cache.dart';
import '../../core/api/dio_client.dart';
import '../../core/services/background_sync_service.dart';

/// State autentikasi.
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Riverpod Notifier untuk auth state.
/// Mengelola login, logout, dan session restore saat app launch.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  /// Restore session dari secure storage saat app launch.
  Future<void> restoreSession() async {
    final token = await AuthStorage.getToken();
    if (token != null && token.isNotEmpty) {
      state = state.copyWith(status: AuthStatus.authenticated);
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// Login dengan NIP dan password.
  ///
  /// Alur:
  /// 1. POST /auth/login → dapatkan token + data user dasar
  /// 2. Simpan token + data user ke storage
  /// 3. GET /employee/profile → dapatkan data lengkap termasuk
  ///    koordinat kantor (office) dan face_photos
  /// 4. Simpan data lengkap ke UserStorage
  /// 5. Download semua foto wajah ke penyimpanan lokal device
  Future<void> login(int nip, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      debugPrint('[AUTH] Mencoba login NIP=$nip...');
      final response = await AuthApi.login(nip, password);
      debugPrint('[AUTH] Response status: ${response.statusCode}');

      final data = response.data['data'];
      final token = data['token'] as String;
      final userData = data['user'] as Map<String, dynamic>;

      // Simpan token dan data user dasar
      await AuthStorage.saveToken(token);
      await UserStorage.saveUser(userData);
      debugPrint('[AUTH] Token tersimpan. User: ${userData['name']}');

      // Set status authenticated dulu agar UI tidak menunggu
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
      );
      debugPrint('[AUTH] Login sukses! Status: ${state.status}');

      // Fetch profil lengkap (koordinat kantor + face_photos) di background
      _fetchProfileAndDownloadFaces();
    } on DioException catch (e) {
      debugPrint(
          '[AUTH] DioException: ${e.response?.statusCode} ${e.response?.data}');
      debugPrint('[AUTH] DioException type: ${e.type}');
      String msg = 'Terjadi kesalahan. Silakan coba lagi.';

      if (e.response?.statusCode == 422) {
        final errors = e.response?.data['errors'];
        if (errors != null && errors['nip'] != null) {
          msg = errors['nip'][0] as String;
        } else {
          msg = e.response?.data['message'] ?? msg;
        }
      } else if (e.response?.statusCode == 403) {
        msg = 'Akses ditolak. Hanya karyawan yang dapat login.';
      } else if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        msg = 'Tidak dapat terhubung ke server';
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
    } catch (e, st) {
      debugPrint('[AUTH] Catch error: $e');
      debugPrint('[AUTH] Stacktrace: $st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Terjadi kesalahan sistem: $e',
      );
    }
  }

  /// Fetch profil lengkap dari server dan download foto wajah ke disk lokal.
  /// Dijalankan di background setelah login berhasil agar UI tidak menunggu.
  Future<void> _fetchProfileAndDownloadFaces() async {
    try {
      debugPrint('[AUTH] Fetching full profile (office + face_photos)...');
      final profileResponse = await AuthApi.profile();
      final profileData =
          profileResponse.data['data'] as Map<String, dynamic>;

      // Simpan data profil lengkap (termasuk koordinat kantor)
      await UserStorage.saveUser(profileData);
      debugPrint('[AUTH] Profile tersimpan: ${profileData['name']}');

      // Download foto wajah ke disk lokal
      final faceUrls = (profileData['face_photos'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      if (faceUrls.isNotEmpty) {
        debugPrint('[AUTH] Downloading ${faceUrls.length} foto wajah...');
        final localPaths =
            await FaceStorage.downloadFacePhotos(faceUrls, DioClient.instance);
        debugPrint('[AUTH] ${localPaths.length} foto wajah tersimpan di disk.');
      } else {
        debugPrint('[AUTH] Tidak ada foto wajah untuk didownload.');
      }
    } catch (e) {
      debugPrint('[AUTH] Gagal fetch profil/download foto: $e');
      // Abaikan error — foto lama (jika ada) masih akan digunakan
    }
  }

  /// Logout: invalidate token di server, hapus semua data lokal.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      await AuthApi.logout();
    } catch (_) {
      // Abaikan error logout — tetap lanjutkan clear local data
    }

    await AuthStorage.deleteToken();
    await UserStorage.clearAll();
    await FaceStorage.deleteAllFacePhotos();
    await HistoryCache.clearAll();
    await PresenceQueue.clearAll();
    await IzinQueue.clearAll();
    await TodayPresenceCache.clearAll();
    await DocCache.clearAll();
    await BackgroundSyncService.cancelAll();

    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      isLoading: false,
    );
  }
}

/// Provider global untuk auth state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
