import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../core/api/employee_api.dart';
import '../../core/storage/user_storage.dart';
import '../../core/storage/presence_queue.dart'; // OfflineQueueStorage, PresenceQueue
import '../../core/storage/izin_queue.dart';
import '../../core/utils/geo.dart';
import '../../core/utils/offline_sync.dart';

import '../../widgets/location_status_card.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/camera_view.dart';
import '../auth/auth_notifier.dart';
import 'dashboard_notifier.dart';
import '../../core/utils/security_checker.dart';

/// DashboardScreen — Tab 0
/// Menampilkan: lokasi GPS, status presensi hari ini, kamera wajah, form izin.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  // GPS
  bool _locationPermissionDenied = false;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  bool _isGpsEnabled = true;

  /// Posisi GPS terakhir yang diketahui — digunakan untuk submit presensi.
  Position? _lastPosition;

  // Face
  bool _isFaceValid = false;

  // Izin form
  final _izinFormKey = GlobalKey<FormState>();
  String _jenisIzin = 'Izin';
  final _keteranganController = TextEditingController();
  String? _dokumenPath;
  String? _dokumenName;
  bool _showCheckoutCamera = false;
  bool _showCheckinCamera = false;
  bool _isSubmittingIzin = false;
  bool _isSubmittingPresence = false;

  // Security
  bool _isSecurityCompromised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineSync.setContext(context);
    OfflineSync.startListening();
    _requestLocationAndStart();

    // Startup refresh — sync queue jika online, load cache jika offline.
    Future.microtask(
      () => ref.read(dashboardProvider.notifier).startupRefresh(),
    );
  }

  /// Menjalankan pengecekan keamanan.
  /// PENTING: Fungsi ini HANYA dapat memblokir akses, TIDAK pernah membuka kunci.
  /// Sekali terblokir, hanya restart aplikasi yang dapat mengubahnya.
  Future<void> _runSecurityCheck() async {
    // Jika sudah terblokir, tidak perlu cek ulang.
    if (_isSecurityCompromised) return;

    final status = await SecurityChecker.checkDeviceSecurity();
    if (!status.isSafe && mounted) {
      _isSecurityCompromised = true;
      // Hentikan location stream karena sudah terblokir.
      _locationSub?.cancel();
      _locationSub = null;
      // Navigasi ke layar blokir terpisah.
      context.go('/security-blocked');
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusSub?.cancel();
    _locationSub?.cancel();
    _keteranganController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OfflineSync.syncNow();
      // Jalankan pengecekan keamanan setiap kali app kembali ke foreground.
      // Ini memastikan fake GPS yang diaktifkan saat app di background terdeteksi.
      _runSecurityCheck();
    }
  }

  Future<void> _requestLocationAndStart() async {
    final status = await Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() => _locationPermissionDenied = true);
      return;
    }

    _startLocationStream();
  }

  /// Memulai stream GPS.
  /// Mengambil koordinat kantor dari UserStorage secara langsung agar
  /// bisa berjalan walaupun dashboardProvider belum selesai loading.
  Future<void> _startLocationStream() async {
    _locationSub?.cancel();

    Map<String, dynamic>? office;
    final dashboard = ref.read(dashboardProvider);
    office = dashboard.userData?['office'] as Map<String, dynamic>?;

    if (office == null) {
      final localUser = await UserStorage.getUser();
      office = localUser?['office'] as Map<String, dynamic>?;
    }

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    } catch (_) {}

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (mounted) {
        setState(() => _isGpsEnabled = serviceEnabled);
      }

      _serviceStatusSub ??= Geolocator.getServiceStatusStream().listen((status) {
        if (mounted) {
          setState(() {
            _isGpsEnabled = status == ServiceStatus.enabled;
          });
          if (_isGpsEnabled && _locationSub == null) {
            _initStreamOnly();
          } else if (!_isGpsEnabled) {
            _locationSub?.cancel();
            _locationSub = null;
          }
        }
      });

      if (serviceEnabled) {
        _initStreamOnly();
      }
    } catch (_) {}
  }

  void _triggerSecurityBlock() {
    if (_isSecurityCompromised) return;
    _isSecurityCompromised = true;
    _locationSub?.cancel();
    _locationSub = null;
    if (mounted) {
      context.go('/security-blocked');
    }
  }

  void _initStreamOnly() {
    _locationSub?.cancel();
    try {
      // 1. Cek posisi terakhir diketahui secara cepat
      Geolocator.getLastKnownPosition().then((pos) {
        if (pos != null && mounted) {
          if (pos.isMocked) {
            _triggerSecurityBlock();
          } else {
            setState(() => _lastPosition = pos);
          }
        }
      }).catchError((_) {});

      // 2. Active Fetching: Tarik data terbaru secara paksa (mengatasi masalah stream yang tidak jalan karena distanceFilter 5m)
      Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      ).then((pos) {
        if (mounted) {
          if (pos.isMocked) {
            _triggerSecurityBlock();
          } else {
            setState(() => _lastPosition = pos);
          }
        }
      }).catchError((_) {});

      // 3. Listen ke stream untuk update secara berkelanjutan
      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (mounted) {
          if (position.isMocked) {
            _triggerSecurityBlock();
          } else if (!_isSecurityCompromised) {
            setState(() {
              _lastPosition = position;
            });
          }
        }
      }, onError: (error) {
        debugPrint('Location stream error: $error');
      });
    } catch (_) {}
  }


  Future<void> _handleRefresh() async {
    final result = await ref.read(dashboardProvider.notifier).refresh();
    if (!mounted) return;

    final msg = result == 'offline'
        ? 'Offline — menggunakan data lokal'
        : result == 'success'
            ? 'Data diperbarui'
            : 'Gagal memperbarui data';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );

    // Restart location stream karena office data mungkin berubah
    _startLocationStream();
  }

  Future<void> _handlePresence() async {
    if (_isSubmittingPresence) return;

    final dashboard = ref.read(dashboardProvider);
    final office = dashboard.userData?['office'] as Map<String, dynamic>?;
    if (office == null) return;

    final officeId = office['id'] as int;
    final officeLat = (office['latitude'] as num).toDouble();
    final officeLon = (office['longitude'] as num).toDouble();
    final officeRadius = (office['radius'] as num).toDouble();

    // Lakukan satu kali lagi tarikan agresif untuk mengecek GPS Fake sesaat sebelum proses pengiriman
    try {
      final forcedPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      );
      if (forcedPos.isMocked) {
        _triggerSecurityBlock();
        return;
      }
    } catch (_) {
      // Abaikan error timeout/dll, biarkan sistem fallback menggunakan _lastPosition
    }

    // Koordinat GPS aktual (bisa dari stream atau dari forcedPos jika stream tidak jalan)
    final lat = _lastPosition?.latitude ?? 0.0;
    final lng = _lastPosition?.longitude ?? 0.0;

    final distanceMeters = haversineDistance(lat, lng, officeLat, officeLon);
    final isWithinRadius = distanceMeters <= officeRadius;

    // Validasi lokasi di device (offline maupun online)
    if (!isWithinRadius) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anda berada di luar radius kantor. '
            'Jarak: ${distanceMeters.toStringAsFixed(0)} m, '
            'Batas: ${officeRadius.toStringAsFixed(0)} m.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validasi wajah
    if (!_isFaceValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Validasi wajah gagal. Arahkan wajah ke kamera.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmittingPresence = true);

    try {
      final isOnline = await OfflineSync.isConnected();
      final todayPresence = dashboard.todayPresence;

      if (isOnline) {
        // --- Online: kirim langsung ke server ---
        try {
          final response = await EmployeeApi.submitPresence(
            officeId: officeId,
            latitude: lat,
            longitude: lng,
            isFaceValid: _isFaceValid,
          );

          if (!mounted) return;

          // Ambil data presensi dari response dan update cache
          final presenceData = response.data['data'] as Map<String, dynamic>?;
          if (presenceData != null) {
            await ref
                .read(dashboardProvider.notifier)
                .updateTodayPresenceFromOffline(presenceData);
          }

          if (!mounted) return;
          final msg = response.data['message'] as String? ??
              'Presensi berhasil dicatat';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: const Color(0xFF22c55e),
            ),
          );

          // Refresh untuk mendapatkan status terbaru
          ref.read(dashboardProvider.notifier).loadDashboard();
        } on DioException catch (e) {
          if (!mounted) return;
          final msg = e.response?.data['message'] ?? 'Gagal melakukan presensi';
          final distance = e.response?.data['data']?['distance_meters'];
          final radius = e.response?.data['data']?['allowed_radius'];
          final detail = distance != null
              ? '\n(Jarak: ${distance}m, Batas: ${radius}m)'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('$msg$detail'), backgroundColor: Colors.red),
          );
        }
      } else {
        // --- Offline: simpan ke antrian dengan timestamp asli saat ini ---
        final now = DateTime.now();

        // Format waktu sesuai yang dibutuhkan endpoint: 'yyyy-MM-dd HH:mm:ss'
        final formattedNow =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        final todayDate =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        // Tentukan tipe: check-in atau check-out
        final isCheckIn = todayPresence == null;

        if (isCheckIn) {
          // Simpan sebagai check_in dengan waktu asli saat ini
          await OfflineQueueStorage.enqueueCheckIn(
            officeId: officeId,
            latitude: lat,
            longitude: lng,
            isFaceValid: _isFaceValid,
            checkInTime: formattedNow, // waktu asli check-in offline
          );
        } else {
          // Simpan sebagai check_out — sertakan check_in_time dari data yang ada
          final existingCheckInTime = todayPresence['check_in_time'] as String?;
          // Normalisasi check_in_time ke format 'yyyy-MM-dd HH:mm:ss'
          String checkInFormatted = formattedNow;
          if (existingCheckInTime != null) {
            try {
              final ciDt = DateTime.parse(existingCheckInTime).toLocal();
              checkInFormatted =
                  '${ciDt.year}-${ciDt.month.toString().padLeft(2, '0')}-${ciDt.day.toString().padLeft(2, '0')} '
                  '${ciDt.hour.toString().padLeft(2, '0')}:${ciDt.minute.toString().padLeft(2, '0')}:${ciDt.second.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          await OfflineQueueStorage.enqueueCheckOut(
            officeId: officeId,
            latitude: lat,
            longitude: lng,
            isFaceValid: _isFaceValid,
            checkInTime: checkInFormatted,
            checkOutTime: formattedNow, // waktu asli check-out offline
          );
        }

        // Bangun data presensi lokal untuk update card segera
        Map<String, dynamic> offlinePresenceData;
        if (isCheckIn) {
          offlinePresenceData = {
            'id': null,
            'date': todayDate,
            'check_in_time': formattedNow,
            'check_out_time': null,
            'status': 'present', // status sementara, server yang final
            'early_leave': false,
            'latitude': lat,
            'longitude': lng,
            'jenis_izin': null,
            'izin_keterangan': null,
            'izin_dokumen': null,
            'office': {
              'id': officeId,
              'office_name': office['office_name'] ?? '',
            },
            '_offline': true, // Marker bahwa ini data offline belum sync
          };
        } else {
          // Update check_out_time pada data yang sudah ada
          offlinePresenceData = Map<String, dynamic>.from(todayPresence);
          offlinePresenceData['check_out_time'] = formattedNow;
          offlinePresenceData['_offline'] = true;
        }

        // Update cache + state agar card langsung terupdate
        await ref
            .read(dashboardProvider.notifier)
            .updateTodayPresenceFromOffline(offlinePresenceData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCheckIn
                  ? 'Check-In disimpan — akan dikirim saat online'
                  : 'Check-Out disimpan — akan dikirim saat online',
            ),
            backgroundColor: const Color(0xFF22c55e),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingPresence = false;
          _showCheckoutCamera = false; // Sembunyikan kamera setelah submit
          _showCheckinCamera = false;  // Reset kamera check-in juga
        });
      }
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _dokumenPath = result.files.single.path;
        _dokumenName = result.files.single.name;
      });
    }
  }

  Future<void> _submitIzin() async {
    if (!_izinFormKey.currentState!.validate()) return;

    setState(() => _isSubmittingIzin = true);

    final isOnline = await OfflineSync.isConnected();

    if (isOnline) {
      // --- Online: kirim langsung ---
      try {
        final response = await EmployeeApi.submitIzin(
          jenisIzin: _jenisIzin,
          izinKeterangan: _keteranganController.text,
          dokumenPath: _dokumenPath,
        );
        if (!mounted) return;

        // Update cache dengan data izin dari server
        final presenceData =
            response.data['data'] as Map<String, dynamic>?;
        if (presenceData != null) {
          await ref
              .read(dashboardProvider.notifier)
              .updateTodayPresenceFromOffline(presenceData);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Izin berhasil diajukan'),
            backgroundColor: Color(0xFF22c55e),
          ),
        );
        _keteranganController.clear();
        setState(() {
          _dokumenPath = null;
          _dokumenName = null;
        });
        ref.read(dashboardProvider.notifier).loadDashboard();
      } on DioException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                e.response?.data['message'] ?? 'Gagal mengajukan izin'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _isSubmittingIzin = false);
      }
    } else {
      // --- Offline: simpan ke antrian ---
      try {
        // Ambil officeId dari userData melalui provider
        final dashboardState = ref.read(dashboardProvider);
        final officeIdForIzin =
            (dashboardState.userData?['office']?['id'] as int?) ?? 0;
        final now = DateTime.now();
        final todayDateStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        await IzinQueue.enqueue(
          jenisIzin: _jenisIzin,
          izinKeterangan: _keteranganController.text,
          officeId: officeIdForIzin,
          offlineDate: todayDateStr, // tanggal izin = hari ini saat offline
        );

        // Bangun data izin lokal untuk update card (reuse todayDateStr)
        final offlineIzinData = {
          'id': null,
          'date': todayDateStr,
          'check_in_time': null,
          'check_out_time': null,
          'status': 'izin',
          'early_leave': false,
          'latitude': null,
          'longitude': null,
          'jenis_izin': _jenisIzin,
          'izin_keterangan': _keteranganController.text,
          'izin_dokumen': null,
          'office': null,
          '_offline': true,
        };

        await ref
            .read(dashboardProvider.notifier)
            .updateTodayPresenceFromOffline(offlineIzinData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin disimpan — akan dikirim saat online',
            ),
            backgroundColor: Color(0xFF22c55e),
          ),
        );
        _keteranganController.clear();
        setState(() {
          _dokumenPath = null;
          _dokumenName = null;
        });
      } finally {
        if (mounted) setState(() => _isSubmittingIzin = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isAuth = auth.status == AuthStatus.authenticated;

    final dashboard = ref.watch(dashboardProvider);
    final userData = dashboard.userData;
    final todayPresence = dashboard.todayPresence;
    final office = userData?['office'] as Map<String, dynamic>?;

    final isIzin = todayPresence?['status'] == 'izin';
    final isCheckedOut = todayPresence?['check_out_time'] != null;
    final isOfflineData = todayPresence?['_offline'] == true;

    // Data time-status dari server
    final timeStatus = dashboard.timeStatus;
    final checkinStatus = timeStatus?['checkin'] as Map<String, dynamic>?;
    final checkoutStatus = timeStatus?['checkout'] as Map<String, dynamic>?;
    final izinStatus = timeStatus?['izin'] as Map<String, dynamic>?;

    // Cek apakah presensi saat ini dibuka (check-in / check-out)
    bool isPresenceOpen = true;
    if (timeStatus != null) {
      if (todayPresence == null) {
        isPresenceOpen = checkinStatus?['is_open'] as bool? ?? true;
      } else {
        isPresenceOpen = checkoutStatus?['is_open'] as bool? ?? true;
      }
    }

    // Kalkulasi jarak & radius secara dinamis
    double? distanceMeters;
    bool isWithinRadius = false;
    if (office != null && _lastPosition != null) {
      final officeLat = (office['latitude'] as num).toDouble();
      final officeLon = (office['longitude'] as num).toDouble();
      final officeRadius = (office['radius'] as num).toDouble();
      distanceMeters = haversineDistance(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        officeLat,
        officeLon,
      );
      isWithinRadius = distanceMeters <= officeRadius;
    }

    // Presensi diizinkan jika wajah cocok dan dalam radius (validasi lokal)
    // ignore: unused_local_variable
    final canPresence = _isFaceValid && isWithinRadius;

    // Restart stream jika office baru tersedia setelah loading
    if (office != null && _lastPosition == null && _locationSub == null) {
      _startLocationStream();
    }

    if (!isAuth) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('Dashboard Presensi',
              style: TextStyle(
                  color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 64, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 16),
              const Text(
                'Silahkan login terlebih dahulu',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  context.go('/profile');
                },
                child: const Text('Ke Halaman Login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Dashboard Presensi',
          style: TextStyle(
              color: Color(0xFF1F2937), fontWeight: FontWeight.bold),
        ),
        actions: [
          if (userData != null) ...[
            IconButton(
              icon: const Icon(Icons.calendar_month,
                  color: Color(0xFF6B7280)),
              tooltip: 'Jadwal & Izin',
              onPressed: () => _showTimeStatusModal(context),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  color: Color(0xFF6B7280)),
              tooltip: 'Panduan Presensi',
              onPressed: () => context.push('/presence-guide'),
            ),
          ],
        ],
        elevation: 0,
      ),
      body: dashboard.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF22C55E)),
            )
          : RefreshIndicator(
              onRefresh: _handleRefresh,
              color: const Color(0xFF22C55E),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location permission banner
                  if (_locationPermissionDenied)
                    MaterialBanner(
                      content: const Text(
                        'Izin lokasi diperlukan untuk presensi',
                        style: TextStyle(color: Color(0xFF1F2937)),
                      ),
                      backgroundColor: const Color(0xFFFEF3C7),
                      actions: [
                        TextButton(
                          onPressed: openAppSettings,
                          child: const Text(
                            'Buka Pengaturan',
                            style: TextStyle(color: Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  // Greeting & Location Status Card in one row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Halo, ${userData?['name'] ?? 'Karyawan'} 👋',
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (office != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  office['office_name'] ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: LocationStatusCard(
                            margin: EdgeInsets.zero,
                            distanceMeters: distanceMeters,
                            radiusMeters: office != null
                                ? (office['radius'] as num?)?.toDouble()
                                : null,
                            isWithinRadius: isWithinRadius,
                            isLoading: distanceMeters == null &&
                                !_locationPermissionDenied,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Today Presence & Ajukan Izin in one row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTodayPresenceCard(
                              todayPresence,
                              isOfflineData,
                              checkinStatus: checkinStatus,
                              checkoutStatus: checkoutStatus,
                            ),
                          ),
                          const SizedBox(width: 8),
                        Expanded(
                            flex: 2,
                            child: InkWell(
                              onTap: () {
                                // Cek apakah pengajuan izin dibuka
                                if (izinStatus != null) {
                                  final isOpen =
                                      izinStatus['is_open'] as bool? ?? true;
                                  if (!isOpen) {
                                    final reason =
                                        izinStatus['reason'] as String? ?? '';
                                    // Tentukan pesan yang lebih spesifik
                                    String alertMsg;
                                    final openTime =
                                        izinStatus['open_time'] as String?;
                                    final closeTime =
                                        izinStatus['close_time'] as String?;

                                    if (reason.toLowerCase().contains('belum') ||
                                        reason
                                            .toLowerCase()
                                            .contains('belum waktunya')) {
                                      alertMsg =
                                          'Pengajuan izin belum dibuka, silahkan tunggu pukul ${openTime ?? "05.00"}';
                                    } else if (reason
                                            .toLowerCase()
                                            .contains('ditutup') ||
                                        reason
                                            .toLowerCase()
                                            .contains('sudah tutup')) {
                                      alertMsg =
                                          'Pengajuan izin sudah ditutup pukul ${closeTime ?? "19.00"}'
                                          '${openTime != null ? ', dibuka kembali pukul $openTime' : ''}';
                                    } else {
                                      // fallback: gunakan reason dari server
                                      alertMsg = reason;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(alertMsg),
                                        backgroundColor:
                                            const Color(0xFFB45309),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                }
                                _showIzinModal(context);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFFBBF24)
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_document,
                                        color: Color(0xFFB45309), size: 28),
                                    SizedBox(height: 8),
                                    Text(
                                      'Ajukan Izin',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFB45309),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!_isGpsEnabled)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.location_off, color: Color(0xFFEF4444), size: 24),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'GPS belum diaktifkan, silahkan aktifkan GPS terlebih dahulu',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Camera (hidden if izin, sudah check-out, atau presensi ditutup)
                  if (!isIzin && !isCheckedOut && isPresenceOpen) ...[
                    // ── CHECK-IN ──
                    if (todayPresence == null) ...[
                      if (!_showCheckinCamera) ...[
                        // Tombol untuk mengaktifkan kamera check-in
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ElevatedButton.icon(
                            onPressed: () => setState(() => _showCheckinCamera = true),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Klik untuk Presensi Masuk'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Frame kamera check-in — autoStart langsung aktifkan kamera
                        CameraView(
                          autoStart: true,
                          onCancel: () => setState(() {
                            _showCheckinCamera = false;
                            _isFaceValid = false;
                          }),
                          onFaceValidChanged: (valid) {
                            setState(() => _isFaceValid = valid);
                            if (valid && isWithinRadius && !_isSubmittingPresence && !_locationPermissionDenied) {
                              _handlePresence();
                            }
                          },
                        ),

                        // Info validasi
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Center(
                            child: Text(
                              _buildValidationHint(
                                  isOnline: true, isWithinRadius: isWithinRadius),
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ]
                    // ── CHECK-OUT ──
                    else if (_showCheckoutCamera) ...[
                      // Frame kamera check-out — autoStart langsung aktifkan kamera
                      CameraView(
                        autoStart: true,
                        onCancel: () => setState(() {
                          _showCheckoutCamera = false;
                          _isFaceValid = false;
                        }),
                        onFaceValidChanged: (valid) {
                          setState(() => _isFaceValid = valid);
                          if (valid && isWithinRadius && !_isSubmittingPresence && !_locationPermissionDenied) {
                            _handlePresence();
                          }
                        },
                      ),

                      // Info validasi
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Center(
                          child: Text(
                            _buildValidationHint(
                                isOnline: true, isWithinRadius: isWithinRadius),
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Tombol untuk membuka kamera Check-Out
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ElevatedButton.icon(
                          onPressed: () => _showCheckoutConfirmation(context),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Buka Kamera untuk Presensi Pulang'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ] else if (isIzin) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                        ),
                        child: const Center(
                          child: Text(
                            'Terimakasih telah mengajukan izin hari ini, sampai jumpa lagi di esok hari.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else if (isCheckedOut) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                        ),
                        child: const Center(
                          child: Text(
                            'Terimakasih telah melakukan seluruh presensi hari ini, sampai jumpa lagi di hari esok.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],


                ],
              ),
            ),
    ));
  }

  /// Buat teks hint validasi berdasarkan kondisi saat ini.
  String _buildValidationHint({required bool isOnline, required bool isWithinRadius}) {
    final hints = <String>[];
    if (!isWithinRadius) hints.add('di dalam radius kantor');
    if (!_isFaceValid) hints.add('wajah terdeteksi & cocok');
    if (hints.isEmpty) {
      return isOnline
          ? 'Memproses presensi otomatis...'
          : 'Presensi offline dicatat otomatis. Akan dikirim saat online.';
    }
    return 'Diperlukan: ${hints.join(' & ')}';
  }

  Widget _buildTodayPresenceCard(
      Map<String, dynamic>? presence,
      bool isOfflineData, {
    Map<String, dynamic>? checkinStatus,
    Map<String, dynamic>? checkoutStatus,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Presensi Hari Ini',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isOfflineData) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Belum sync',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (presence == null) ...[
            const Text(
              'Belum presensi hari ini',
              style: TextStyle(color: Color(0xFF1F2937), fontSize: 15),
            ),
            // Tampilkan info status check-in/check-out dari time-status
            if (checkinStatus != null) ...[
              const SizedBox(height: 4),
              _buildTimeStatusInfo(checkinStatus, checkoutStatus),
            ],
          ]
          else if (presence['status'] == 'izin') ...[
            Text(
              'Izin hari ini — ${presence['jenis_izin'] ?? ""}',
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            Row(
              children: [
                if (presence['check_in_time'] != null)
                  Expanded(
                    child: Text(
                      'Masuk: ${_formatTime(presence['check_in_time'])}',
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ),
                StatusBadge(status: presence['status'] ?? 'pending'),
              ],
            ),
            if (presence['check_out_time'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pulang: ${_formatTime(presence['check_out_time'])}',
                        style: const TextStyle(
                            color: Color(0xFF6B7280), fontSize: 13),
                      ),
                    ),
                    StatusBadge(
                      status: (presence['early_leave'] == true ||
                              presence['early_leave'] == 1 ||
                              presence['early_leave'] == '1')
                          ? 'early_leave'
                          : 'present',
                    ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Belum check-out',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Format waktu dari ISO string menjadi HH:mm yang lebih ringkas.
  String _formatTime(String? isoTime) {
    if (isoTime == null) return '-';
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoTime;
    }
  }

  /// Widget info status check-in / check-out berdasarkan data time-status.
  ///
  /// Logika prioritas:
  /// 1. Check-in belum dibuka (sebelum open_time) → tampilkan waktu buka
  /// 2. Check-in sudah ditutup → tampilkan pesan tutup
  ///    2a. Jika checkout juga tutup karena batas waktu → tampilkan batas checkout
  /// 3. Check-in masih terbuka → tidak tampilkan apa-apa (SizedBox.shrink)
  Widget _buildTimeStatusInfo(
    Map<String, dynamic> checkin,
    Map<String, dynamic>? checkout,
  ) {
    final checkinOpen = checkin['is_open'] as bool? ?? true;
    final checkinReason = checkin['reason'] as String? ?? '';
    final checkinOpenTime = checkin['open_time'] as String?;

    // Belum waktunya check-in (sebelum open_time — pagi hari)
    if (!checkinOpen && checkinReason.toLowerCase().contains('belum')) {
      return Row(
        children: [
          const Icon(Icons.access_time, size: 13, color: Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Check-in belum dibuka'
              '${checkinOpenTime != null ? ', buka pukul $checkinOpenTime' : ''}',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }

    // Check-in sudah ditutup (melewati close_time atau jadwal check-out)
    if (!checkinOpen) {
      final checkoutOpen = checkout?['is_open'] as bool? ?? true;
      final checkoutReason = (checkout?['reason'] as String? ?? '').toLowerCase();
      final checkoutDeadline = checkout?['deadline_time'] as String?;

      // Checkout juga sudah tutup DAN bukan karena "belum check-in"
      // (bukan karena user belum check-in, tapi karena deadline terlewati)
      final checkoutClosedByDeadline = !checkoutOpen &&
          !checkoutReason.contains('belum') &&
          (checkoutReason.contains('batas') ||
              checkoutReason.contains('deadline') ||
              checkoutReason.contains('ditutup'));

      if (checkoutClosedByDeadline) {
        return Row(
          children: [
            const Icon(Icons.block, size: 13, color: Color(0xFFEF4444)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Check-out sudah ditutup'
                '${checkoutDeadline != null ? ' (batas $checkoutDeadline)' : ''}',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      }

      // Check-in ditutup — tampilkan open_time (kapan besok bisa check-in)
      return Row(
        children: [
          const Icon(Icons.lock_clock, size: 13, color: Color(0xFFEF4444)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Check-in sudah ditutup'
              '${checkinOpenTime != null ? ', dibuka pukul $checkinOpenTime' : ''}',
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }

    // Check-in masih terbuka — tidak perlu tampilkan info tambahan
    return const SizedBox.shrink();
  }

  /// Fetch live time-status dan tampilkan modal sederhana.
  /// Menggunakan satu Dialog dengan FutureBuilder agar tidak ada double-navigator
  /// operation yang menyebabkan '_debugLocked' assertion error.
  void _showTimeStatusModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _fetchTimeStatus(),
              builder: (_, snapshot) {
                // Loading
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 120,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF22C55E)),
                    ),
                  );
                }

                // Error
                if (snapshot.hasError || snapshot.data == null) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Tidak dapat terhubung ke server',
                        style: TextStyle(
                            color: Color(0xFF1F2937), fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tutup'),
                      ),
                    ],
                  );
                }

                // Success
                return _buildTimeStatusContent(ctx, snapshot.data!);
              },
            ),
          ),
        );
      },
    );
  }

  /// Helper: fetch data time-status dari server.
  Future<Map<String, dynamic>?> _fetchTimeStatus() async {
    try {
      final response = await EmployeeApi.getTimeStatus();
      final body = response.data as Map<String, dynamic>?;
      if (body?['success'] == true) {
        return body!['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  Widget _buildTimeStatusContent(
      BuildContext ctx, Map<String, dynamic> data) {
    final currentTime = data['current_time'] as String? ?? '-';
    final currentDate = data['current_date'] as String? ?? '-';
    final checkin = data['checkin'] as Map<String, dynamic>? ?? {};
    final checkout = data['checkout'] as Map<String, dynamic>? ?? {};
    final izin = data['izin'] as Map<String, dynamic>? ?? {};

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Jadwal',
              style: TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.close, color: Color(0xFF6B7280), size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$currentDate  •  $currentTime',
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
        ),
        const Divider(height: 20),

        // Check-in
        _buildScheduleRow(
          icon: Icons.login,
          iconColor: const Color(0xFF22C55E),
          label: 'Check-In',
          isOpen: checkin['is_open'] as bool? ?? false,
          reason: checkin['reason'] as String?,
          rows: [
            if (checkin['scheduled_time'] != null)
              _kv('Jadwal', checkin['scheduled_time'] as String),
            if (checkin['open_time'] != null)
              _kv('Dibuka', checkin['open_time'] as String),
            if (checkin['close_time'] != null)
              _kv('Ditutup', checkin['close_time'] as String),
          ],
        ),
        const SizedBox(height: 12),

        // Check-out
        _buildScheduleRow(
          icon: Icons.logout,
          iconColor: const Color(0xFF3B82F6),
          label: 'Check-Out',
          isOpen: checkout['is_open'] as bool? ?? false,
          reason: checkout['reason'] as String?,
          rows: [
            if (checkout['scheduled_time'] != null)
              _kv('Jadwal', checkout['scheduled_time'] as String),
            if (checkout['deadline_time'] != null)
              _kv('Batas', checkout['deadline_time'] as String),
          ],
        ),
        const SizedBox(height: 12),

        // Izin
        _buildScheduleRow(
          icon: Icons.edit_document,
          iconColor: const Color(0xFFB45309),
          label: 'Pengajuan Izin',
          isOpen: izin['is_open'] as bool? ?? false,
          reason: izin['reason'] as String?,
          rows: [
            if (izin['open_time'] != null)
              _kv('Dibuka', izin['open_time'] as String),
            if (izin['close_time'] != null)
              _kv('Ditutup', izin['close_time'] as String),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Baris jadwal satu item (check-in / check-out / izin).
  Widget _buildScheduleRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isOpen,
    String? reason,
    required List<Widget> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isOpen ? 'Buka' : 'Tutup',
                  style: TextStyle(
                    color: isOpen
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...rows,
          ],
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Key-value row kecil untuk jadwal waktu.
  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              key,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Tampilkan modal konfirmasi sebelum user membuka kamera check-out.
  /// Mencegah user tidak sengaja melakukan presensi pulang setelah check-in.
  void _showCheckoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Color(0xFF3B82F6), size: 24),
              SizedBox(width: 8),
              Text(
                'Konfirmasi Presensi Pulang',
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Anda sudah melakukan presensi masuk, apakah anda ingin melanjutkan untuk melakukan presensi pulang?',
            style: TextStyle(
              color: Color(0xFF374151),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'Tidak',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _showCheckoutCamera = true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Ya',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showIzinModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Ajukan Izin / Cuti',
                          style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Color(0xFF6B7280)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _izinFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Jenis izin dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _jenisIzin,
                            dropdownColor: Colors.white,
                            style:
                                const TextStyle(color: Color(0xFF1F2937)),
                            decoration: InputDecoration(
                              labelText: 'Jenis Izin *',
                              labelStyle: const TextStyle(
                                  color: Color(0xFF6B7280)),
                              filled: true,
                              fillColor: const Color(0xFFF0FDF4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Izin', child: Text('Izin')),
                              DropdownMenuItem(
                                  value: 'Cuti', child: Text('Cuti')),
                            ],
                            onChanged: (v) {
                              setState(() => _jenisIzin = v!);
                              setModalState(() {});
                            },
                          ),
                          const SizedBox(height: 12),

                          // Keterangan
                          TextFormField(
                            controller: _keteranganController,
                            style:
                                const TextStyle(color: Color(0xFF1F2937)),
                            maxLines: 3,
                            maxLength: 1000,
                            decoration: InputDecoration(
                              labelText: 'Keterangan *',
                              labelStyle: const TextStyle(
                                  color: Color(0xFF6B7280)),
                              counterStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF)),
                              filled: true,
                              fillColor: const Color(0xFFF0FDF4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty
                                    ? 'Keterangan wajib diisi'
                                    : null,
                          ),
                          const SizedBox(height: 8),

                          // Dokumen picker
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await _pickDocument();
                                  setModalState(() {});
                                },
                                icon: const Icon(Icons.attach_file, size: 16),
                                label: const Text(
                                    'Pilih Dokumen (Opsional)'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B7280),
                                  side: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                              ),
                            ],
                          ),
                          if (_dokumenName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _dokumenName!,
                                style: const TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Submit izin
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isSubmittingIzin
                                  ? null
                                  : () async {
                                      setModalState(
                                          () => _isSubmittingIzin = true);
                                      await _submitIzin();
                                      if (!mounted) return;
                                      setModalState(() {});
                                      if (_keteranganController.text.isEmpty) {
                                        // ignore: use_build_context_synchronously
                                        Navigator.pop(ctx);
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isSubmittingIzin
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Ajukan Izin',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
