import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/api/auth_api.dart';
import '../../core/api/dio_client.dart';
import '../../core/storage/user_storage.dart';
import '../../core/storage/face_storage.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/utils/offline_sync.dart';

class ProfileState {
  final Map<String, dynamic>? userData;
  final List<String> facePhotosPaths;
  final bool isLoading;
  final bool isRefreshing;

  const ProfileState({
    this.userData,
    this.facePhotosPaths = const [],
    this.isLoading = false,
    this.isRefreshing = false,
  });

  ProfileState copyWith({
    Map<String, dynamic>? userData,
    List<String>? facePhotosPaths,
    bool? isLoading,
    bool? isRefreshing,
  }) {
    return ProfileState(
      userData: userData ?? this.userData,
      facePhotosPaths: facePhotosPaths ?? this.facePhotosPaths,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState());

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true);

    // Cek dulu dari local storage
    final localUser = await UserStorage.getUser();
    final localPaths = await UserStorage.getFacePhotosPaths();

    if (localUser != null) {
      state = state.copyWith(
        userData: localUser,
        facePhotosPaths: localPaths,
        isLoading: false,
      );
    }

    // Jika ada token, sync dari server (/auth/me)
    final token = await AuthStorage.getToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      final profileResponse = await AuthApi.profile();
      // Response: { "success": true, "data": { ...user..., "face_photos": [...] } }
      final data = profileResponse.data['data'] as Map<String, dynamic>;
      final faceUrls = (data['face_photos'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // Simpan user (tanpa field face_photos agar konsisten dengan UserStorage)
      final userData = Map<String, dynamic>.from(data)
        ..remove('face_photos');
      await UserStorage.saveUser(userData);

      // Download face photos hanya jika ada
      List<String> updatedPaths = localPaths;
      if (faceUrls.isNotEmpty) {
        updatedPaths = await FaceStorage.downloadFacePhotos(
            faceUrls, DioClient.instance);
      }

      state = state.copyWith(
        userData: userData,
        facePhotosPaths: updatedPaths,
        isLoading: false,
      );
    } on DioException catch (_) {
      // Gunakan data lokal jika API gagal
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true);

    final isOnline = await OfflineSync.isConnected();
    if (!isOnline) {
      state = state.copyWith(isRefreshing: false);
      return;
    }

    try {
      // Gunakan /employee/profile
      final profileResponse = await AuthApi.profile();
      final data = profileResponse.data['data'] as Map<String, dynamic>;
      final faceUrls = (data['face_photos'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final userData = Map<String, dynamic>.from(data)
        ..remove('face_photos');
      await UserStorage.saveUser(userData);

      List<String> updatedPaths = state.facePhotosPaths;
      if (faceUrls.isNotEmpty) {
        updatedPaths = await FaceStorage.downloadFacePhotos(
            faceUrls, DioClient.instance);
      }

      state = state.copyWith(
        userData: userData,
        facePhotosPaths: updatedPaths,
        isRefreshing: false,
      );
    } on DioException catch (_) {
      state = state.copyWith(isRefreshing: false);
    }
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>(
  (ref) => ProfileNotifier(),
);
