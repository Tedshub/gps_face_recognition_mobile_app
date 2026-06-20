import 'package:flutter/material.dart';
import 'status_badge.dart';

/// Kalender bulanan dengan grid 7 kolom dan StatusBadge per hari.
/// Hari dengan record presensi bisa di-tap untuk membuka PresenceModal.
class CalendarView extends StatelessWidget {
  final int year;
  final int month;
  final List<Map<String, dynamic>> presences;
  final Map<String, String> holidays;
  final void Function(Map<String, dynamic> presence)? onDayTapped;

  const CalendarView({
    super.key,
    required this.year,
    required this.month,
    required this.presences,
    required this.holidays,
    this.onDayTapped,
  });

  static const _dayHeaders = ['MIN', 'SEN', 'SEL', 'RAB', 'KAM', 'JUM', 'SAB'];

  Map<int, Map<String, dynamic>> _buildPresenceMap() {
    final map = <int, Map<String, dynamic>>{};
    for (final p in presences) {
      final dateStr = p['date'] as String?;
      if (dateStr == null) continue;
      final parts = dateStr.split('-');
      if (parts.length != 3) continue;
      final day = int.tryParse(parts[2]);
      if (day != null) map[day] = p;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final presenceMap = _buildPresenceMap();
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 0 = Sunday

    final totalCells = startWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        // Header row
        Row(
          children: _dayHeaders
              .map(
                (h) => Expanded(
                  child: Center(
                    child: Text(
                      h,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),

        // Calendar grid
        for (int row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final cellIndex = row * 7 + col;
              final day = cellIndex - startWeekday + 1;

              if (day < 1 || day > daysInMonth) {
                return const Expanded(child: SizedBox(height: 52));
              }

              final presence = presenceMap[day];
              final dateStr =
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isHoliday = holidays.containsKey(dateStr);

              String? displayStatus;
              if (presence != null) {
                final baseStatus = presence['status'] as String? ?? 'pending';
                final isEarlyLeave = presence['early_leave'] == true || presence['early_leave'] == 1 || presence['early_leave'] == '1';

                if (baseStatus == 'late' && isEarlyLeave) {
                  displayStatus = 'late_early_leave';
                } else if (baseStatus == 'present' && isEarlyLeave) {
                  displayStatus = 'early_leave';
                } else {
                  displayStatus = baseStatus;
                }
              }

              return Expanded(
                child: GestureDetector(
                  onTap: presence != null ? () => onDayTapped?.call(presence) : null,
                  child: Container(
                    height: 52,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: displayStatus != null
                          ? StatusBadge.colorForStatus(displayStatus)
                              .withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: displayStatus != null
                          ? Border.all(
                              color: StatusBadge.colorForStatus(displayStatus)
                                  .withValues(alpha: 0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: isHoliday
                                ? const Color(0xFF94a3b8)
                                : Color(0xFF1F2937),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (displayStatus != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: StatusBadge(
                              status: displayStatus,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}
