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

    try {
      final year = state.year;
      final month = state.month;
      final isOnline = await OfflineSync.isConnected();

      // Gunakan cache jika fresh dan tidak forceRefresh
      if (!forceRefresh && await HistoryCache.isFresh(year, month) && isOnline) {
        try {
          final cached = await HistoryCache.load(year, month);
          if (cached != null) {
            _applyData(cached);
            state = state.copyWith(isLoading: false);
            return;
          }
        } catch (_) {
          // Abaikan cache yang rusak/usang, lanjut ambil dari API
        }
      }

      if (isOnline) {
        try {
          final response = await EmployeeApi.getPresencesHistory(month, year);
          final data = Map<String, dynamic>.from(
            response.data['data'] as Map,
          );
          _applyData(data);
          await HistoryCache.save(year, month, data);

          // Selesaikan loading dulu agar UI tidak spinner
          state = state.copyWith(isLoading: false);

          // Pre-download dokumen izin di background, tidak memblokir UI
          _cacheIzinDocuments().catchError((_) {});
        } on DioException catch (_) {
          // Fallback ke cache
          await _loadCachedFallback(
            year,
            month,
            'Anda sedang offline — tidak dapat memuat data terbaru',
          );
        } catch (_) {
          // Tangkap semua error lain agar isLoading selalu direset
          await _loadCachedFallback(
            year,
            month,
            'Gagal memuat data riwayat.',
          );
        }
      } else {
        // Offline: load dari cache
        await _loadCachedFallback(year, month, null);
      }
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Gagal memuat data riwayat.',
      );
    } finally {
      if (mounted && state.isLoading) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  Future<void> _loadCachedFallback(
    int year,
    int month,
    String? errorMessage,
  ) async {
    try {
      final cached = await HistoryCache.load(year, month);
      if (cached != null) {
        _applyData(cached);
      }
    } catch (_) {
      // Abaikan jika cache rusak
    }
    state = state.copyWith(
      isLoading: false,
      errorMessage: errorMessage,
    );
  }

  void _applyData(Map<String, dynamic> data) {
    final rawHolidaysData = data['holidays'];
    final rawHolidays = rawHolidaysData is Map
        ? Map<String, dynamic>.from(rawHolidaysData)
        : <String, dynamic>{};
    final holidays = rawHolidays.map(
      (k, v) => MapEntry(k, v.toString()),
    );

    final rawPresencesData = data['presences'];
    final rawPresences =
        rawPresencesData is List ? rawPresencesData : <dynamic>[];
    final presences = <Map<String, dynamic>>[];
    int futureAbsentCount = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final raw in rawPresences) {
      if (raw is! Map) continue;
      final p = Map<String, dynamic>.from(raw);
      final dateStr = p['date'] as String?;
      bool skip = false;
      if (dateStr != null) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            final date = DateTime(y, m, d);
            if (date.isAfter(today) && p['status'] == 'absent') {
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

    final rawSummary = data['summary'];
    final summary = rawSummary is Map
        ? Map<String, dynamic>.from(rawSummary)
        : null;

    if (summary != null && summary.containsKey('absent')) {
      var absent = (summary['absent'] as num?)?.toInt() ?? 0;
      absent -= futureAbsentCount;
      if (absent < 0) absent = 0;
      summary['absent'] = absent;
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
