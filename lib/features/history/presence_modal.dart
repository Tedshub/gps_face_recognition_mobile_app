import 'package:flutter/material.dart';
import '../../widgets/status_badge.dart';

/// Bottom sheet detail untuk presensi yang di-tap di CalendarView.
/// Menampilkan: tanggal, status badge, check-in/out time, early_leave, office, izin info, dokumen button.
class PresenceModal extends StatefulWidget {
  final Map<String, dynamic> presence;

  const PresenceModal({super.key, required this.presence});

  @override
  State<PresenceModal> createState() => _PresenceModalState();
}

class _PresenceModalState extends State<PresenceModal> {
  @override
  Widget build(BuildContext context) {
    final p = widget.presence;
    final baseStatus = p['status'] as String? ?? 'pending';
    final earlyLeave = p['early_leave'] == true || p['early_leave'] == 1 || p['early_leave'] == '1';
    
    String displayStatus = baseStatus;
    if (baseStatus == 'late' && earlyLeave) {
      displayStatus = 'late_early_leave';
    } else if (baseStatus == 'present' && earlyLeave) {
      displayStatus = 'early_leave';
    }

    final isIzin = baseStatus == 'izin';
    final office = p['office'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detail Presensi',
                          style: TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p['date'] as String? ?? '-',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    StatusBadge(status: displayStatus),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE5E7EB)),
                const SizedBox(height: 12),

                // Check-in / Check-out
                _buildRow('Check-In', p['check_in_time'] as String? ?? '-'),
                const SizedBox(height: 8),
                _buildRow(
                    'Check-Out', p['check_out_time'] as String? ?? '-'),

                // Early leave flag
                if (earlyLeave) ...[
                  const SizedBox(height: 8),
                  _buildRow('Pulang Cepat', 'Ya',
                      valueColor: const Color(0xFFf97316)),
                ],

                // Office
                if (office != null) ...[
                  const SizedBox(height: 8),
                  _buildRow('Kantor',
                      office['office_name'] as String? ?? '-'),
                ],

                // Izin info
                if (isIzin) ...[
                  const SizedBox(height: 8),
                  _buildRow('Jenis Izin', p['jenis_izin'] as String? ?? '-'),
                  const SizedBox(height: 8),
                  _buildRow(
                      'Keterangan', p['izin_keterangan'] as String? ?? '-'),
                ],

                // Holiday info
                if (p['holiday_name'] != null) ...[
                  const SizedBox(height: 8),
                  _buildRow('Hari Libur', p['holiday_name'] as String),
                ],


              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value,
      {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Color(0xFF1F2937),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
