import 'package:flutter/material.dart';

/// Kartu yang menampilkan jarak GPS karyawan ke kantor.
/// Green = dalam radius, Red = di luar radius.
class LocationStatusCard extends StatelessWidget {
  final double? distanceMeters;
  final double? radiusMeters;
  final bool isWithinRadius;
  final bool isLoading;
  final EdgeInsetsGeometry margin;

  const LocationStatusCard({
    super.key,
    required this.distanceMeters,
    required this.radiusMeters,
    required this.isWithinRadius,
    this.isLoading = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final color = isWithinRadius
        ? const Color(0xFF22c55e)
        : const Color(0xFFef4444);

    final icon = isWithinRadius
        ? Icons.location_on
        : Icons.location_off;

    String message;
    if (isLoading || distanceMeters == null) {
      message = 'Mendapatkan lokasi...';
    } else if (isWithinRadius) {
      message =
          'Dalam radius (${distanceMeters!.toStringAsFixed(0)} m)';
    } else {
      message =
          'Di luar radius (${distanceMeters!.toStringAsFixed(0)} m)';
    }

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
