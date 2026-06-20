import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'user_storage.dart';

/// Mengelola download dan penyimpanan foto wajah referensi ke disk lokal.
/// Lokasi: getApplicationDocumentsDirectory()/face_photos/face_N.jpg
class FaceStorage {
  static Future<String> get _faceDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/face_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Download semua foto wajah dari list URL.
  /// Menyimpan sebagai face_0.jpg, face_1.jpg, dst.
  /// Memperbarui UserStorage.saveFacePhotosPaths() setelah selesai.
  static Future<List<String>> downloadFacePhotos(
    List<String> urls,
    Dio dio,
  ) async {
    final dir = await _faceDir;
    final localPaths = <String>[];

    for (int i = 0; i < urls.length; i++) {
      final localPath = '$dir/face_$i.jpg';
      try {
        await dio.download(urls[i], localPath);
        localPaths.add(localPath);
      } catch (e) {
        // Skip foto yang gagal didownload, lanjutkan ke berikutnya
      }
    }

    await UserStorage.saveFacePhotosPaths(localPaths);
    return localPaths;
  }

  /// Hapus semua file foto wajah dari disk (dipakai saat logout).
  static Future<void> deleteAllFacePhotos() async {
    try {
      final dir = await _faceDir;
      final directory = Directory(dir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Abaikan error jika direktori tidak ditemukan
    }
    await UserStorage.saveFacePhotosPaths([]);
  }
}
