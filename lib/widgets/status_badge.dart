import 'package:flutter/material.dart';

/// Chip badge berwarna berdasarkan status presensi.
/// Dipakai di CalendarView, TodayPresenceCard, dan PresenceModal.
///
/// Status color map sesuai SKILL.md:
/// present     → Color(0xFF22c55e) green
/// late        → Color(0xFFf59e0b) amber
/// absent      → Color(0xFFef4444) red
/// izin        → Color(0xFF6366f1) indigo
/// early_leave → Color(0xFFf97316) orange
/// libur       → Color(0xFF94a3b8) slate
/// pending     → Color(0xFFd1d5db) grey
class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  static const _labels = {
    'present': 'TEPAT WAKTU',
    'late': 'TERLAMBAT',
    'absent': 'ABSEN',
    'izin': 'IZIN',
    'early_leave': 'PULANG CEPAT',
    'late_early_leave': 'TERLAMBAT & PULANG CEPAT',
    'libur': 'LIBUR',
    'pending': 'PENDING',
  };

  static const _colors = {
    'present': Color(0xFF22c55e),
    'late': Color(0xFFFBBF24),
    'absent': Color(0xFFef4444),
    'izin': Color(0xFFB45309),
    'early_leave': Color(0xFFf97316),
    'late_early_leave': Color(0xFFea580c),
    'libur': Color(0xFF94a3b8),
    'pending': Color(0xFF9CA3AF),
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[status] ?? status.toUpperCase();
    final color = _colors[status] ?? const Color(0xFFd1d5db);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// Warna untuk status tertentu (berguna untuk kalender).
  static Color colorForStatus(String status) =>
      _colors[status] ?? const Color(0xFF9CA3AF);
}
