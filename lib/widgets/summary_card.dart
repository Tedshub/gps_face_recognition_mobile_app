import 'package:flutter/material.dart';

/// Kartu ringkasan metrik presensi (dipakai di HistoryScreen).
/// Menampilkan: icon, jumlah, label, dan persentase.
class SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;
  final int totalWorkingDays;

  const SummaryCard({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    required this.totalWorkingDays,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = totalWorkingDays > 0
        ? ((count / totalWorkingDays) * 100).round()
        : 0;

    return Container(
      padding: const EdgeInsets.all(10), // Padding lebih kecil
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          // Count
          Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Label
          Text(
            label,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Percentage chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$percentage%',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
