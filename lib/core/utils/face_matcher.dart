import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Hasil deteksi dan pencocokan wajah dari satu frame kamera.
class FaceMatchResult {
  /// Apakah ada wajah yang terdeteksi di frame.
  final bool hasFace;

  /// Apakah wajah yang terdeteksi cocok dengan foto referensi.
  final bool isMatch;

  /// Apakah wajah terlalu jauh dari kamera
  final bool isTooFar;

  /// Apakah pose wajah valid (lihat lurus)
  final bool isPoseValid;

  /// Bounding box wajah dalam ruang koordinat image logis (sudah dirotasi).
  /// Null jika tidak ada wajah terdeteksi.
  final Rect? boundingBox;

  /// Nilai cosine similarity tertinggi yang dicapai (untuk debug / fine-tuning threshold).
  /// Null jika tidak ada wajah atau tidak ada referensi.
  final double? debugSimilarity;

  const FaceMatchResult({
    this.hasFace = false,
    this.isMatch = false,
    this.isTooFar = false,
    this.isPoseValid = true,
    this.boundingBox,
    this.debugSimilarity,
  });
}

/// Face matching menggunakan MobileFaceNet TFLite untuk menghitung Embedding (192 Dimensi).
class FaceMatcher {
  static final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  static Interpreter? _interpreter;

  // Cache for reference embeddings
  static final Map<String, List<double>> _referenceCache = {};

  static Future<void> init() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
    } catch (e) {
      debugPrint("Gagal load MobileFaceNet: $e");
    }
  }

  /// Prapemrosesan: Cache embedding foto referensi agar tidak dihitung berulang.
  static Future<void> loadReferenceEmbeddings(List<String> referencePaths) async {
    await init();
    if (_interpreter == null) return;

    _referenceCache.clear();
    for (final path in referencePaths) {
      final refFile = File(path);
      if (!await refFile.exists()) {
        debugPrint('[FaceMatcher] File referensi tidak ditemukan: $path');
        continue;
      }

      final refInputImage = InputImage.fromFilePath(path);
      final refFaces = await _detector.processImage(refInputImage);
      if (refFaces.isEmpty) {
        debugPrint('[FaceMatcher] Tidak ada wajah terdeteksi di referensi: $path');
        continue;
      }

      final refBytes = await refFile.readAsBytes();
      img.Image? refImg = img.decodeImage(refBytes);
      if (refImg == null) {
        debugPrint('[FaceMatcher] Gagal decode image referensi: $path');
        continue;
      }

      // Pastikan rotasi Exif dari kamera diaplikasikan
      refImg = img.bakeOrientation(refImg);

      final refFace = refFaces.first;

      // [Fix #4] Validasi minimum bounding box sebelum crop
      final refBox = refFace.boundingBox;
      if (refBox.width < 20 || refBox.height < 20) {
        debugPrint('[FaceMatcher] Bounding box referensi terlalu kecil: ${refBox.width}x${refBox.height}');
        continue;
      }

      final refCrop = _cropFace(refImg, refBox);
      if (refCrop == null) continue;

      final refResized = img.copyResize(refCrop, width: 112, height: 112);
      final embedding = _getEmbedding(refResized);
      if (embedding != null) {
        _referenceCache[path] = embedding;
        debugPrint('[FaceMatcher] Referensi di-cache: $path');
      }
    }
    debugPrint('[FaceMatcher] Total referensi ter-cache: ${_referenceCache.length}');
  }

  /// Cocokkan frame kamera dengan foto referensi.
  ///
  /// Selalu menjalankan deteksi wajah (ML Kit) sehingga bounding box
  /// tetap tersedia meski belum ada referensi atau model belum siap.
  ///
  /// [Fix #2] Perbaikan koordinat: Bounding box ML Kit mengacu pada ruang
  /// koordinat image yang belum dirotasi secara piksel (ML Kit melakukan rotasi
  /// virtual secara internal berdasarkan metadata `rotation`). Oleh karena itu,
  /// konversi CameraImage → img.Image dilakukan TANPA rotasi terlebih dahulu,
  /// lalu crop dilakukan langsung dari koordinat ML Kit yang sudah valid.
  /// Rotasi hanya dilakukan SETELAH crop agar dimensi 112x112 tetap benar.
  ///
  /// Mengembalikan [FaceMatchResult] yang berisi:
  /// - [FaceMatchResult.hasFace]: apakah wajah terdeteksi
  /// - [FaceMatchResult.isMatch]: apakah cocok dengan referensi (cosine >= 0.45)
  /// - [FaceMatchResult.boundingBox]: posisi wajah di ruang image logis (setelah rotasi)
  /// - [FaceMatchResult.debugSimilarity]: nilai similarity tertinggi untuk debug
  static Future<FaceMatchResult> match(
    CameraImage cameraImage,
    List<String> referencePhotoPaths,
    InputImageRotation rotation,
  ) async {
    try {
      final inputImage = _cameraImageToInputImage(cameraImage, rotation);
      if (inputImage == null) return const FaceMatchResult();

      // Deteksi wajah — selalu dijalankan agar bounding box tersedia
      final liveFaces = await _detector.processImage(inputImage);
      if (liveFaces.isEmpty) return const FaceMatchResult();

      final liveFace = liveFaces.first;
      final faceBox = liveFace.boundingBox;

      // [Fix #6] Validasi jarak wajah dan pose (Sesuai dengan FACE-CAPTURE.md)
      // Jarak wajah ideal: Bounding box harus memakan area yang cukup.
      // Di capture diset >= 35%, di presensi/attendance diberikan toleransi sedikit (>= 25%).
      final imageArea = cameraImage.width * cameraImage.height;
      final faceArea = faceBox.width * faceBox.height;
      final faceRatio = faceArea / imageArea;
      
      final bool isTooFar = faceRatio < 0.25;

      // Pose (Tahap 1: lihat lurus ke kamera)
      // Toleransi Yaw +/- 20, Pitch +/- 15, Roll +/- 15
      bool isPoseValid = true;
      if (liveFace.headEulerAngleY != null && liveFace.headEulerAngleY!.abs() > 20) {
        isPoseValid = false;
      }
      if (liveFace.headEulerAngleX != null && liveFace.headEulerAngleX!.abs() > 15) {
        isPoseValid = false;
      }
      if (liveFace.headEulerAngleZ != null && liveFace.headEulerAngleZ!.abs() > 15) {
        isPoseValid = false;
      }

      // Jika model atau cache belum siap, kembalikan status terdeteksi
      if (_interpreter == null || _referenceCache.isEmpty) {
        debugPrint('[FaceMatcher] Interpreter atau cache belum siap. Cache size: ${_referenceCache.length}');
        return FaceMatchResult(
          hasFace: true, 
          isTooFar: isTooFar,
          isPoseValid: isPoseValid,
          boundingBox: faceBox
        );
      }
      
      // Jika wajah terlalu jauh atau pose tidak valid, jangan lakukan komputasi embedding (hemat CPU dan hindari false match)
      if (isTooFar || !isPoseValid) {
        debugPrint('[FaceMatcher] Wajah belum valid: isTooFar=$isTooFar, isPoseValid=$isPoseValid');
        return FaceMatchResult(
          hasFace: true,
          isTooFar: isTooFar,
          isPoseValid: isPoseValid,
          boundingBox: faceBox,
        );
      }

      // [Fix #2] Konversi CameraImage → img.Image TANPA rotasi terlebih dahulu.
      // Bounding box dari ML Kit (faceBox) valid di ruang koordinat image asli
      // (sebelum rotasi piksel), sehingga crop bisa langsung menggunakan faceBox.
      img.Image? liveImgRaw = _convertCameraImage(cameraImage);
      if (liveImgRaw == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      // [Fix #2] Crop dulu dari image asli (koordinat sesuai faceBox ML Kit)
      // [Fix #4] Validasi ukuran bounding box minimum
      if (faceBox.width < 20 || faceBox.height < 20) {
        debugPrint('[FaceMatcher] Bounding box live terlalu kecil: ${faceBox.width}x${faceBox.height}');
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      final liveCropRaw = _cropFace(liveImgRaw, faceBox);
      if (liveCropRaw == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      // [Fix #2] Setelah crop, baru rotasi agar orientasi wajah tegak
      final liveCropRotated = _rotateImage(liveCropRaw, rotation);
      final liveResized = img.copyResize(liveCropRotated, width: 112, height: 112);
      final liveEmbedding = _getEmbedding(liveResized);
      if (liveEmbedding == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      // Bandingkan dengan setiap foto referensi di cache
      double bestSimilarity = 0.0;
      for (final refPath in referencePhotoPaths) {
        final refEmbedding = _referenceCache[refPath];
        if (refEmbedding == null) continue;
        final similarity = _cosineSimilarity(liveEmbedding, refEmbedding);

        // [Fix #5] Debug log: tampilkan similarity tiap referensi
        debugPrint('[FaceMatcher] similarity=$similarity (ref: ${refPath.split('/').last})');

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
        }

        // [Fix #1] Threshold diturunkan dari 0.82 → 0.60 agar realistis
        // untuk kondisi live kamera vs foto referensi statis.
        // MobileFaceNet pada kondisi real-world lazimnya menghasilkan
        // similarity 0.60-0.95 untuk orang yang sama.
        if (similarity >= 0.60) {
          debugPrint('[FaceMatcher] ✅ MATCH! similarity=$similarity');
          return FaceMatchResult(
            hasFace: true,
            isMatch: true,
            boundingBox: faceBox,
            debugSimilarity: similarity,
          );
        }
      }

      debugPrint('[FaceMatcher] ❌ No match. Best similarity=$bestSimilarity');
      return FaceMatchResult(
        hasFace: true,
        boundingBox: faceBox,
        debugSimilarity: bestSimilarity > 0 ? bestSimilarity : null,
      );
    } catch (e) {
      debugPrint('FaceMatcher.match error: $e');
      return const FaceMatchResult();
    }
  }

  /// Mengubah gambar (112x112) menjadi Tensor Float32 Array [1, 112, 112, 3]
  /// lalu menjalankan inferensi TFLite untuk mendapatkan 192 array dimensi.
  static List<double>? _getEmbedding(img.Image image) {
    if (_interpreter == null) return null;

    var input = List.generate(
        1, (i) => List.generate(
            112, (j) => List.generate(
                112, (k) => List.filled(3, 0.0))));

    // Normalisasi: (pixel - 127.5) / 127.5
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = image.getPixel(x, y);
        input[0][y][x][0] = (pixel.r - 127.5) / 127.5;
        input[0][y][x][1] = (pixel.g - 127.5) / 127.5;
        input[0][y][x][2] = (pixel.b - 127.5) / 127.5;
      }
    }

    var output = List.generate(1, (i) => List.filled(192, 0.0));
    try {
      _interpreter!.run(input, output);
      return output[0];
    } catch (e) {
      debugPrint("Gagal inferensi: $e");
      return null;
    }
  }

  /// Rumus Cosine Similarity = (A dot B) / (||A|| * ||B||)
  static double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += v1[i] * v1[i];
      normB += v2[i] * v2[i];
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Crop area wajah dari gambar berdasarkan bounding box.
  static img.Image? _cropFace(img.Image source, dynamic boundingBox) {
    try {
      // Tambahkan margin 20% agar dagu dan rahang tidak terpotong
      final marginX = (boundingBox.width * 0.20).toInt();
      final marginY = (boundingBox.height * 0.20).toInt();

      final x = (boundingBox.left.toInt() - marginX).clamp(0, source.width - 1);
      final y = (boundingBox.top.toInt() - marginY).clamp(0, source.height - 1);
      final w = (boundingBox.width.toInt() + marginX * 2).clamp(1, source.width - x);
      final h = (boundingBox.height.toInt() + marginY * 2).clamp(1, source.height - y);

      // [Fix #4] Validasi ukuran crop minimum agar tidak mengirim patch kosong
      if (w < 20 || h < 20) {
        debugPrint('[FaceMatcher] Crop terlalu kecil: ${w}x$h, skip.');
        return null;
      }

      return img.copyCrop(source, x: x, y: y, width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  /// Konversi CameraImage (YUV_420_888 dari CameraX) ke InputImage ML Kit.
  ///
  /// Bug umum: menggabungkan plane bytes langsung termasuk stride/padding
  /// menyebabkan ukuran tidak cocok → PlatformException(InputImageConverterError).
  ///
  /// Fix: konversi ke NV21 secara manual (strip stride, interleave V+U),
  /// lalu gunakan InputImageFormat.nv21 yang ML Kit Android terima dengan benar.
  static InputImage? _cameraImageToInputImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    try {
      if (Platform.isIOS || image.format.group == ImageFormatGroup.bgra8888) {
        // Pada iOS format default adalah bgra8888 (1 plane).
        if (image.planes.isEmpty) return null;
        return InputImage.fromBytes(
          bytes: image.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      }

      // Android: YUV_420_888
      if (image.planes.length < 3) return null;
      final Uint8List nv21 = _yuv420ToNv21(image);

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21, // NV21 tanpa padding — ML Kit OK
          bytesPerRow: image.width,      // NV21 tidak punya row padding
        ),
      );
    } catch (e) {
      debugPrint('_cameraImageToInputImage error: $e');
      return null;
    }
  }

  /// Konversi YUV_420_888 (3 plane terpisah dengan stride) ke format NV21.
  ///
  /// Struktur NV21 = Y plane (tanpa padding) + VU interleaved (tanpa padding).
  /// Stride pada tiap plane di-strip agar ukuran bytes tepat sesuai resolusi.
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int w = image.width;
    final int h = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    // Total size NV21: Y (w*h) + UV interleaved (w*h/2)
    final Uint8List nv21 = Uint8List(w * h + (w * h) ~/ 2);
    int idx = 0;

    // 1. Salin Y plane baris demi baris (strip row padding)
    for (int row = 0; row < h; row++) {
      final int rowOffset = row * yPlane.bytesPerRow;
      for (int col = 0; col < w; col++) {
        nv21[idx++] = yPlane.bytes[rowOffset + col];
      }
    }

    // 2. Interleave V, U (NV21 = V terlebih dahulu, baru U)
    final int uvH = h ~/ 2;
    final int uvW = w ~/ 2;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int row = 0; row < uvH; row++) {
      final int rowOffset = row * uPlane.bytesPerRow;
      for (int col = 0; col < uvW; col++) {
        final int uvIdx = rowOffset + col * uvPixelStride;
        nv21[idx++] = vPlane.bytes[uvIdx]; // V dulu (NV21)
        nv21[idx++] = uPlane.bytes[uvIdx]; // lalu U
      }
    }

    return nv21;
  }

  /// Konversi CameraImage ke img.Image secara manual (karena decodeImage tidak mendukung raw YUV/BGRA).
  static img.Image? _convertCameraImage(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888(image);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static img.Image _convertBGRA8888(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }

  static img.Image _convertYUV420(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final imgImage = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final index = y * yRowStride + x;

        final yp = yPlane.bytes[index];
        final up = uPlane.bytes[uvIndex];
        final vp = vPlane.bytes[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgImage;
  }

  /// Putar gambar agar orientasinya sesuai.
  /// Digunakan setelah crop — bukan sebelum — agar koordinat bounding box tetap valid.
  static img.Image _rotateImage(img.Image image, InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return img.copyRotate(image, angle: 90);
      case InputImageRotation.rotation180deg:
        return img.copyRotate(image, angle: 180);
      case InputImageRotation.rotation270deg:
        return img.copyRotate(image, angle: 270);
      case InputImageRotation.rotation0deg:
        return image;
    }
  }

  static void dispose() {
    _detector.close();
    _interpreter?.close();
    _interpreter = null;
  }
}
