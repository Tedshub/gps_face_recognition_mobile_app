import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../core/storage/user_storage.dart';
import '../core/utils/face_matcher.dart';

/// Widget live camera preview dengan face detection overlay dan matching.
///
/// Fitur:
/// - Toggle front/back camera
/// - Toggle aktif/nonaktif (kamera off by default)
/// - Overlay: abu-abu (tidak ada wajah) / merah (tidak cocok) / hijau (cocok)
/// - Face matching throttled 1 frame/detik
/// - 1.5 detik debounce sebelum isFaceValid = true
class CameraView extends StatefulWidget {
  final void Function(bool isValid) onFaceValidChanged;

  const CameraView({
    super.key,
    required this.onFaceValidChanged,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

enum _OverlayState { neutral, noFace, noMatch, matched }

class _CameraViewState extends State<CameraView> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraActive = false;
  bool _isFrontCamera = true;
  bool _isInitializing = false;

  _OverlayState _overlayState = _OverlayState.neutral;
  Timer? _throttleTimer;
  bool _isProcessing = false;

  List<String> _referencePhotoPaths = [];

  /// Hasil pencocokan wajah terakhir — untuk menggambar bounding box.
  FaceMatchResult? _lastResult;

  /// Ukuran logis image kamera setelah rotasi (landscape → portrait).
  Size _imageLogicalSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadReferencePaths();
  }

  Future<void> _loadReferencePaths() async {
    _referencePhotoPaths = await UserStorage.getFacePhotosPaths();
    // Prapemrosesan: Cache TFLite Embedding
    await FaceMatcher.loadReferenceEmbeddings(_referencePhotoPaths);
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;
    setState(() => _isInitializing = true);

    // Reload reference embeddings setiap kali kamera diaktifkan
    // agar selalu sinkron dengan foto profil terbaru.
    await _loadReferencePaths();

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _isFrontCamera
          ? _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _cameras.first,
            )
          : _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first,
            );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      _controller!.startImageStream(_onCameraImage);

      setState(() {
        _isCameraActive = true;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _stopCamera() async {
    _throttleTimer?.cancel();
    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    if (mounted) {
      setState(() {
        _isCameraActive = false;
        _overlayState = _OverlayState.neutral;
      });
    }
    widget.onFaceValidChanged(false);
  }

  void _onCameraImage(CameraImage image) {
    if (_isProcessing || _throttleTimer?.isActive == true) return;

    // Throttle: 1 frame per detik agar tidak membebani CPU
    _throttleTimer = Timer(const Duration(seconds: 1), () {});
    _isProcessing = true;

    final rotation = _isFrontCamera
        ? InputImageRotation.rotation270deg
        : InputImageRotation.rotation90deg;

    // Setelah rotasi 90°/270°, lebar dan tinggi image saling bertukar.
    // Ini digunakan untuk mentransformasi koordinat bounding box ML Kit
    // ke koordinat layar.
    final logicalSize = Size(
      image.height.toDouble(), // lebar setelah rotasi portrait
      image.width.toDouble(),  // tinggi setelah rotasi portrait
    );

    final paths = List<String>.from(_referencePhotoPaths);

    FaceMatcher.match(image, paths, rotation).then((result) {
      if (!mounted) return;
      _isProcessing = false;

      final _OverlayState newState;
      if (result.isMatch) {
        newState = _OverlayState.matched;
      } else if (result.hasFace) {
        newState = _OverlayState.noMatch;
      } else {
        newState = _OverlayState.noFace;
      }

      setState(() {
        _overlayState = newState;
        _lastResult = result;
        _imageLogicalSize = logicalSize;
      });

      widget.onFaceValidChanged(result.isMatch);
    }).catchError((_) {
      _isProcessing = false;
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        children: [
          // Control buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Kamera Wajah',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Toggle front/back
                if (_isCameraActive)
                  IconButton(
                    onPressed: () async {
                      setState(() => _isFrontCamera = !_isFrontCamera);
                      await _stopCamera();
                      await _initCamera();
                    },
                    icon: const Icon(Icons.flip_camera_ios, color: Color(0xFF6B7280)),
                    tooltip: 'Ganti Kamera',
                  ),
                // Toggle aktif/nonaktif
                TextButton.icon(
                  onPressed: _isInitializing
                      ? null
                      : () async {
                          if (_isCameraActive) {
                            await _stopCamera();
                          } else {
                            await _initCamera();
                          }
                        },
                  icon: Icon(
                    _isCameraActive ? Icons.videocam_off : Icons.videocam,
                    size: 18,
                  ),
                  label: Text(_isCameraActive ? 'Matikan' : 'Aktifkan'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF22C55E),
                  ),
                ),
              ],
            ),
          ),

          // Camera preview atau placeholder
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _isCameraActive && _controller != null && _controller!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        // Overlay frame
                        _buildOverlayFrame(),
                      ],
                    )
                  : _buildPlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayFrame() {
    Color frameColor;
    String label;

    switch (_overlayState) {
      case _OverlayState.matched:
        frameColor = const Color(0xFF22c55e);
        label = 'Wajah Cocok ✓';
        break;
      case _OverlayState.noMatch:
        frameColor = const Color(0xFFef4444);
        label = 'Wajah Tidak Cocok';
        break;
      case _OverlayState.noFace:
        frameColor = const Color(0xFFf59e0b);
        label = 'Tidak Ada Wajah';
        break;
      case _OverlayState.neutral:
        frameColor = Colors.white54;
        label = 'Arahkan wajah ke kamera';
        break;
    }

    final hasBoundingBox =
        _lastResult?.boundingBox != null && !_imageLogicalSize.isEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Bounding box wajah dinamis (mengikuti posisi wajah yang terdeteksi)
        if (hasBoundingBox)
          CustomPaint(
            painter: _FaceBoundingBoxPainter(
              boundingBox: _lastResult!.boundingBox!,
              imageLogicalSize: _imageLogicalSize,
              color: frameColor,
              isFrontCamera: _isFrontCamera,
            ),
          ),
        // Corner guide frame (panduan posisi, selalu tampil)
        // Sedikit redup jika bounding box sudah tampil agar tidak tumpang tindih
        CustomPaint(
          painter: _FaceFramePainter(
            color: hasBoundingBox
                ? frameColor.withValues(alpha: 0.35)
                : frameColor,
          ),
        ),
        // Label status di bagian bawah
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: frameColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF0FDF4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.face_retouching_natural,
            size: 64,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 12),
          Text(
            'Kamera tidak aktif',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
            ),
          ),
          if (_isInitializing) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: Color(0xFF22C55E)),
          ],
        ],
      ),
    );
  }
}

/// Painter untuk corner frame — panduan posisi wajah.
class _FaceFramePainter extends CustomPainter {
  final Color color;

  _FaceFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    const cornerSize = 30.0;
    const margin = 40.0;

    final left = margin;
    final top = margin;
    final right = size.width - margin;
    final bottom = size.height - margin;

    // Top-left
    canvas.drawLine(Offset(left, top + cornerSize), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerSize, top), paint);

    // Top-right
    canvas.drawLine(Offset(right - cornerSize, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerSize), paint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom - cornerSize), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerSize, bottom), paint);

    // Bottom-right
    canvas.drawLine(Offset(right - cornerSize, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerSize), paint);
  }

  @override
  bool shouldRepaint(_FaceFramePainter old) => old.color != color;
}

/// Painter untuk bounding box wajah dinamis yang mengikuti posisi wajah terdeteksi.
///
/// Mentransformasi koordinat ML Kit (ruang image logis) ke koordinat canvas
/// dengan memperhitungkan skala dan mirroring kamera depan.
class _FaceBoundingBoxPainter extends CustomPainter {
  final Rect boundingBox;
  final Size imageLogicalSize;
  final Color color;
  final bool isFrontCamera;

  _FaceBoundingBoxPainter({
    required this.boundingBox,
    required this.imageLogicalSize,
    required this.color,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (imageLogicalSize.isEmpty) return;

    // Faktor skala dari ruang image ke ruang canvas
    final scaleX = canvasSize.width / imageLogicalSize.width;
    final scaleY = canvasSize.height / imageLogicalSize.height;

    final double scaledLeft;
    if (isFrontCamera) {
      // Mirror sumbu X: preview kamera depan ditampilkan seperti cermin,
      // sedangkan bounding box ML Kit berasal dari image yang tidak di-mirror.
      scaledLeft =
          (imageLogicalSize.width - boundingBox.left - boundingBox.width) *
              scaleX;
    } else {
      scaledLeft = boundingBox.left * scaleX;
    }

    final scaledTop = boundingBox.top * scaleY;
    final scaledWidth = boundingBox.width * scaleX;
    final scaledHeight = boundingBox.height * scaleY;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Rounded rectangle di sekeliling wajah
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scaledLeft, scaledTop, scaledWidth, scaledHeight),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FaceBoundingBoxPainter old) =>
      old.boundingBox != boundingBox ||
      old.color != color ||
      old.imageLogicalSize != imageLogicalSize ||
      old.isFrontCamera != isFrontCamera;
}
