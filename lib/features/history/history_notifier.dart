import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/api/employee_api.dart';
import '../../core/api/dio_client.dart';
import '../../core/storage/history_cache.dart';
import '../../core/storage/doc_cache.dart';
import '../../core/utils/offline_sync.dart';

class HistoryState {
  final int year;
  final int month;
  final Map<String, dynamic>? summary;
  final Map<String, String> holidays;
  final List<Map<String, dynamic>> presences;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  const HistoryState({
    required this.year,
    required this.month,
    this.summary,
    this.holidays = const {},
    this.presences = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  HistoryState copyWith({
    int? year,
    int? month,
    Map<String, dynamic>? summary,
    Map<String, String>? holidays,
    List<Map<String, dynamic>>? presences,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HistoryState(
      year: year ?? this.year,
      month: month ?? this.month,
      summary: summary ?? this.summary,
      holidays: holidays ?? this.holidays,
      presences: presences ?? this.presences,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier()
      : super(HistoryState(
          year: DateTime.now().year,
          month: DateTime.now().month,
        ));

  Future<void> loadHistory({bool forceRefresh = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final year = state.year;
    final month = state.month;
    final isOnline = await OfflineSync.isConnected();

    // Gunakan cache jika fresh dan tidak forceRefresh
    if (!forceRefresh && await HistoryCache.isFresh(year, month) && isOnline) {
      final cached = await HistoryCache.load(year, month);
      if (cached != null) {
        _applyData(cached);
        state = state.copyWith(isLoading: false);
        return;
      }
    }

    if (isOnline) {
      try {
        final response = await EmployeeApi.getPresencesHistory(month, year);
        final data = response.data['data'] as Map<String, dynamic>;
        await HistoryCache.save(year, month, data);
        _applyData(data);

        // Pre-download dokumen izin
        await _cacheIzinDocuments();

        state = state.copyWith(isLoading: false);
      } on DioException catch (_) {
        // Fallback ke cache
        final cached = await HistoryCache.load(year, month);
        if (cached != null) {
          _applyData(cached);
        }
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Anda sedang offline — tidak dapat memuat data terbaru',
        );
      }
    } else {
      // Offline: load dari cache
      final cached = await HistoryCache.load(year, month);
      if (cached != null) {
        _applyData(cached);
      }
      state = state.copyWith(isLoading: false);
    }
  }

  void _applyData(Map<String, dynamic> data) {
    final rawHolidays = data['holidays'] as Map<String, dynamic>? ?? {};
    final holidays = rawHolidays.map(
      (k, v) => MapEntry(k, v.toString()),
    );

    final rawPresences = data['presences'] as List<dynamic>? ?? [];
    final presences = <Map<String, dynamic>>[];
    int futureAbsentCount = 0;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final raw in rawPresences) {
      final p = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      final dateStr = p['date'] as String?;
      bool skip = false;
      if (dateStr != null) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final date = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          if (date.isAfter(today)) {
            if (p['status'] == 'absent') {
              skip = true;
              futureAbsentCount++;
            }
          }
        }
      }
      if (!skip) {
        presences.add(p);
      }
    }

    final summary = data['summary'] != null
        ? Map<String, dynamic>.from(data['summary'] as Map<String, dynamic>)
        : null;

    if (summary != null && summary.containsKey('absent')) {
      summary['absent'] = (summary['absent'] as int) - futureAbsentCount;
      if ((summary['absent'] as int) < 0) summary['absent'] = 0;
    }

    state = state.copyWith(
      summary: summary,
      holidays: holidays,
      presences: presences,
    );
  }

  /// Pre-download dokumen izin saat HistoryScreen load (bukan saat modal dibuka).
  Future<void> _cacheIzinDocuments() async {
    for (final presence in state.presences) {
      final presenceId = presence['id'] as int?;
      final dokumenUrl = presence['izin_dokumen'] as String?;
      if (presenceId == null || dokumenUrl == null) continue;

      final existing = await DocCache.getLocalPath(presenceId);
      if (existing == null) {
        await DocCache.downloadAndCache(
          presenceId,
          dokumenUrl,
          DioClient.instance,
        );
      }
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true);
    await loadHistory(forceRefresh: true);
    state = state.copyWith(isRefreshing: false);
  }

  void changeMonth(int delta) {
    var newMonth = state.month + delta;
    var newYear = state.year;
    if (newMonth > 12) {
      newMonth = 1;
      newYear++;
    } else if (newMonth < 1) {
      newMonth = 12;
      newYear--;
    }
    state = state.copyWith(month: newMonth, year: newYear);
    loadHistory();
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>(
  (ref) => HistoryNotifier(),
);
