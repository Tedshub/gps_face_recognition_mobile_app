import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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

  /// Bounding box wajah dalam ruang koordinat image logis (sudah dirotasi).
  /// Null jika tidak ada wajah terdeteksi.
  final Rect? boundingBox;

  const FaceMatchResult({
    this.hasFace = false,
    this.isMatch = false,
    this.boundingBox,
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
      if (!await refFile.exists()) continue;

      final refInputImage = InputImage.fromFilePath(path);
      final refFaces = await _detector.processImage(refInputImage);
      if (refFaces.isEmpty) continue;

      final refBytes = await refFile.readAsBytes();
      img.Image? refImg = img.decodeImage(refBytes);
      if (refImg == null) continue;

      // Pastikan rotasi Exif dari kamera diaplikasikan
      refImg = img.bakeOrientation(refImg);

      final refFace = refFaces.first;
      final refCrop = _cropFace(refImg, refFace.boundingBox);
      if (refCrop == null) continue;

      final refResized = img.copyResize(refCrop, width: 112, height: 112);
      final embedding = _getEmbedding(refResized);
      if (embedding != null) {
        _referenceCache[path] = embedding;
      }
    }
  }

  /// Cocokkan frame kamera dengan foto referensi.
  ///
  /// Selalu menjalankan deteksi wajah (ML Kit) sehingga bounding box
  /// tetap tersedia meski belum ada referensi atau model belum siap.
  /// Mengembalikan [FaceMatchResult] yang berisi:
  /// - [FaceMatchResult.hasFace]: apakah wajah terdeteksi
  /// - [FaceMatchResult.isMatch]: apakah cocok dengan referensi (cosine ≥ 0.70)
  /// - [FaceMatchResult.boundingBox]: posisi wajah di ruang image logis
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

      // Jika model atau cache belum siap, cukup laporkan wajah terdeteksi
      if (_interpreter == null || _referenceCache.isEmpty) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      img.Image? liveImg = _convertCameraImage(cameraImage);
      if (liveImg == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      liveImg = _rotateImage(liveImg, rotation);

      final liveCrop = _cropFace(liveImg, faceBox);
      if (liveCrop == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      final liveResized = img.copyResize(liveCrop, width: 112, height: 112);
      final liveEmbedding = _getEmbedding(liveResized);
      if (liveEmbedding == null) {
        return FaceMatchResult(hasFace: true, boundingBox: faceBox);
      }

      // Bandingkan dengan setiap foto referensi di cache
      for (final refPath in referencePhotoPaths) {
        final refEmbedding = _referenceCache[refPath];
        if (refEmbedding == null) continue;
        final similarity = _cosineSimilarity(liveEmbedding, refEmbedding);
        if (similarity >= 0.82) {
          return FaceMatchResult(
            hasFace: true,
            isMatch: true,
            boundingBox: faceBox,
          );
        }
      }

      return FaceMatchResult(hasFace: true, boundingBox: faceBox);
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

  /// Putar gambar agar orientasinya sesuai dengan apa yang dilihat oleh ML Kit.
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
