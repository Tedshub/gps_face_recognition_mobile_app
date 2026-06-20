import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/summary_card.dart';
import '../../widgets/calendar_view.dart';

import 'history_notifier.dart';
import 'presence_modal.dart';

/// HistoryScreen — Tab 1
/// Menampilkan: SummaryCards, navigasi bulan, CalendarView dengan tap ke PresenceModal.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const _monthNames = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(historyProvider.notifier).loadHistory(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final summary = history.summary;

    final totalWorking = summary != null
        ? ((summary['present'] as int? ?? 0) +
            (summary['late'] as int? ?? 0) +
            (summary['absent'] as int? ?? 0) +
            (summary['izin'] as int? ?? 0) +
            (summary['early_leave'] as int? ?? 0))
        : 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Riwayat Presensi Saya',
          style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold),
        ),
        actions: [],
        elevation: 0,
      ),
      body: history.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF22C55E)),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(historyProvider.notifier).refresh(),
              color: const Color(0xFF22C55E),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Offline notice
                  if (history.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Text(
                        history.errorMessage!,
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ),

                  // Summary Cards Grid
                  if (summary != null) ...[
                    Column(
                      children: [
                        // Row 1: 2 items
                        Row(
                          children: [
                            Expanded(
                              child: SummaryCard(
                                icon: Icons.check_circle,
                                color: const Color(0xFF22c55e),
                                count: summary['present'] as int? ?? 0,
                                label: 'Hadir Tepat',
                                totalWorkingDays: totalWorking,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SummaryCard(
                                icon: Icons.access_time,
                                color: const Color(0xFFf59e0b),
                                count: summary['late'] as int? ?? 0,
                                label: 'Terlambat',
                                totalWorkingDays: totalWorking,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Row 2: 3 items
                        Row(
                          children: [
                            Expanded(
                              child: SummaryCard(
                                icon: Icons.cancel,
                                color: const Color(0xFFef4444),
                                count: summary['absent'] as int? ?? 0,
                                label: 'Tidak Hadir',
                                totalWorkingDays: totalWorking,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SummaryCard(
                                icon: Icons.arrow_back,
                                color: const Color(0xFFf97316),
                                count: summary['early_leave'] as int? ?? 0,
                                label: 'Pulang Cepat',
                                totalWorkingDays: totalWorking,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SummaryCard(
                                icon: Icons.description,
                                color: const Color(0xFF6366f1),
                                count: summary['izin'] as int? ?? 0,
                                label: 'Total Izin',
                                totalWorkingDays: totalWorking,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Month Navigation Row
                  Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            ref.read(historyProvider.notifier).changeMonth(-1),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_monthNames[history.month]} ${history.year}',
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            ref.read(historyProvider.notifier).changeMonth(1),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Calendar View
                  CalendarView(
                    year: history.year,
                    month: history.month,
                    presences: history.presences,
                    holidays: history.holidays,
                    onDayTapped: (presence) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => PresenceModal(presence: presence),
                      );
                    },
                  ),
                ],
              ),
            ),
    ));
  }
}
