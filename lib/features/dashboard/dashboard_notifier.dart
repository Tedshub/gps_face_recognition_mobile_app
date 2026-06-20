import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/api/employee_api.dart';
import '../../core/api/dio_client.dart';
import '../../core/storage/user_storage.dart';
import '../../core/storage/face_storage.dart';
import '../../core/storage/today_presence_cache.dart';
import '../../core/utils/offline_sync.dart';

/// State untuk DashboardScreen.
class DashboardState {
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? todayPresence;
  /// Data dari endpoint /employee/presences/time-status.
  /// Berisi status buka/tutup check-in, check-out, dan izin.
  final Map<String, dynamic>? timeStatus;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  const DashboardState({
    this.userData,
    this.todayPresence,
    this.timeStatus,
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  DashboardState copyWith({
    Map<String, dynamic>? userData,
    Map<String, dynamic>? todayPresence,
    Map<String, dynamic>? timeStatus,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearTodayPresence = false,
    bool clearError = false,
  }) {
    return DashboardState(
      userData: userData ?? this.userData,
      todayPresence:
          clearTodayPresence ? null : (todayPresence ?? this.todayPresence),
      timeStatus: timeStatus ?? this.timeStatus,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Riverpod Notifier untuk DashboardScreen.
class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier() : super(const DashboardState()) {
    // Saat ada sync offline yang selesai, refresh dashboard dari server
    OfflineSync.onSyncCompleted = () => loadDashboard();
  }

  /// Startup refresh — dipanggil sekali saat app terbuka dan user sudah login.
  ///
  /// Jika online:
  ///   1. Sync antrian offline (presensi + izin)
  ///   2. Download / refresh foto wajah
  ///   3. Fetch dashboard dari server, simpan ke cache
  ///
  /// Jika offline:
  ///   1. Load user dari local storage
  ///   2. Load today_presence dari TodayPresenceCache (hanya hari ini)
  Future<void> startupRefresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    // Selalu load data lokal dulu agar UI tidak kosong
    final localUser = await UserStorage.getUser();
    final cachedPresence = await TodayPresenceCache.loadToday();

    state = state.copyWith(
      userData: localUser,
      todayPresence: cachedPresence,
    );

    final isOnline = await OfflineSync.isConnected();

    if (isOnline) {
      // 1. Sync offline queue terlebih dahulu
      await OfflineSync.syncNow();

      // 2. Refresh foto wajah di background (tidak blocking UI)
      _refreshFacePhotosInBackground();

      // 3. Fetch dashboard terbaru dari server
      await _fetchDashboardFromServer(localUser);
    } else {
      // Offline — tampilkan data dari cache
      state = state.copyWith(isLoading: false);
    }
  }

  /// Refresh foto wajah tanpa memblokir UI.
  Future<void> _refreshFacePhotosInBackground() async {
    try {
      final faceResponse = await EmployeeApi.getFacePhotos();
      final faceUrls =
          (faceResponse.data['data']['face_photos'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
      if (faceUrls.isNotEmpty) {
        await FaceStorage.downloadFacePhotos(faceUrls, DioClient.instance);
      }
    } catch (_) {
      // Abaikan error refresh foto — foto lama masih valid
    }
  }

  /// Fetch time-status tanpa melempar exception — kembalikan null jika gagal.
  Future<Response?> _fetchTimeStatusSafe() async {
    try {
      return await EmployeeApi.getTimeStatus();
    } catch (_) {
      return null;
    }
  }

  /// Fetch dashboard dari server dan update state + cache.
  Future<void> _fetchDashboardFromServer(
      Map<String, dynamic>? fallbackUser) async {
    try {
      // Fetch dashboard dan time-status secara paralel
      final dashboardFuture = EmployeeApi.getDashboard();
      final timeStatusFuture = _fetchTimeStatusSafe();
      final response = await dashboardFuture;
      final timeStatusResponse = await timeStatusFuture;

      final data = response.data['data'];
      final userData = data['user'] as Map<String, dynamic>?;
      final todayPresence = data['today_presence'] as Map<String, dynamic>?;

      // Ambil timeStatus dari response (null jika endpoint gagal)
      final timeStatus =
          timeStatusResponse?.data['data'] as Map<String, dynamic>?;

      // Simpan today_presence ke cache lokal
      if (todayPresence != null) {
        await TodayPresenceCache.save(todayPresence);
      } else {
        await TodayPresenceCache.saveNull();
      }

      if (userData != null) {
        final localUser = await UserStorage.getUser();
        final mergedUser = localUser != null ? {...localUser, ...userData} : userData;
        await UserStorage.saveUser(mergedUser);

        // Update state dengan mergedUser agar office tetap ada di state UI
        state = state.copyWith(
          userData: mergedUser,
          todayPresence: todayPresence,
          timeStatus: timeStatus,
          isLoading: false,
          clearTodayPresence: todayPresence == null,
        );
      } else {
        state = state.copyWith(
          userData: fallbackUser,
          todayPresence: todayPresence,
          timeStatus: timeStatus,
          isLoading: false,
          clearTodayPresence: todayPresence == null,
        );
      }
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _mapError(e),
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load data dashboard — dipanggil setelah submit presensi/izin online
  /// untuk refresh card "Presensi Hari Ini".
  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, clearError: true);

    final localUser = await UserStorage.getUser();
    state = state.copyWith(userData: localUser);

    final isOnline = await OfflineSync.isConnected();
    if (isOnline) {
      await _fetchDashboardFromServer(localUser);
    } else {
      // Fallback ke cache
      final cachedPresence = await TodayPresenceCache.loadToday();
      state = state.copyWith(
        todayPresence: cachedPresence,
        isLoading: false,
      );
    }
  }

  /// Update card "Presensi Hari Ini" langsung setelah presensi/izin offline.
  /// Data juga disimpan ke TodayPresenceCache agar persisten.
  Future<void> updateTodayPresenceFromOffline(
      Map<String, dynamic> presenceData) async {
    await TodayPresenceCache.save(presenceData);
    state = state.copyWith(todayPresence: presenceData);
  }

  /// Refresh: update face photos + re-fetch dashboard.
  Future<String> refresh() async {
    state = state.copyWith(isRefreshing: true);

    final isOnline = await OfflineSync.isConnected();
    if (!isOnline) {
      state = state.copyWith(isRefreshing: false);
      return 'offline';
    }

    try {
      await _refreshFacePhotosInBackground();
      await loadDashboard();
      state = state.copyWith(isRefreshing: false);
      return 'success';
    } catch (_) {
      state = state.copyWith(isRefreshing: false);
      return 'error';
    }
  }

  String _mapError(DioException e) {
    if (e.response?.statusCode == 422) {
      return e.response?.data['message'] ?? 'Validasi gagal';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server';
    }
    return 'Terjadi kesalahan server';
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(),
);
