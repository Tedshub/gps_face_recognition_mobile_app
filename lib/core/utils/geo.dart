import 'dart:math';

/// Kalkulasi jarak haversine antara dua koordinat GPS dalam meter.
/// Dipakai untuk validasi geofencing: apakah karyawan dalam radius kantor.
///
/// Client-side check ini hanya untuk UX feedback — server memvalidasi ulang secara independen.
double haversineDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const R = 6371000.0; // radius bumi dalam meter
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}
