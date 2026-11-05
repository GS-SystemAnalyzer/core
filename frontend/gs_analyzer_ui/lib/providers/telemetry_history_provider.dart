import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/telemetry_history_model.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/services/benchmark_trace.dart';

final apiServiceProvider = Provider((ref) => ApiService());

class TelemetryHistoryState {
  final TelemetryHistoryResponse? response;
  final bool isLoading;
  final int minutes;
  final String? error;

  TelemetryHistoryState({
    this.response,
    this.isLoading = false,
    this.minutes = 5,
    this.error,
  });

  TelemetryHistoryState copyWith({
    TelemetryHistoryResponse? response,
    bool? isLoading,
    int? minutes,
    String? error,
  }) {
    return TelemetryHistoryState(
      response: response ?? this.response,
      isLoading: isLoading ?? this.isLoading,
      minutes: minutes ?? this.minutes,
      error: error, // null means clear error if not specified
    );
  }
}

class TelemetryHistoryNotifier extends StateNotifier<TelemetryHistoryState> {
  final ApiService _apiService;
  final String _metric;
  Timer? _timer;
  final BenchmarkTrace? _trace = BenchmarkTrace.current;
  int _generation = 0, _inFlight = 0;
  bool _traceDisposed = false;

  TelemetryHistoryNotifier(this._apiService, this._metric)
    : super(TelemetryHistoryState()) {
    _fetchHistory();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchHistory(silent: true);
    });
  }

  Future<void> _fetchHistory({bool silent = false}) {
    final operation = _fetchHistoryCore(silent: silent);
    return _trace == null ? operation : _trace.own(operation);
  }

  Future<void> _fetchHistoryCore({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    final trace = _trace;
    final minutes = state.minutes;
    final generation = ++_generation;
    final requestId = trace == null ? null : BenchmarkTrace.newId();
    final request = trace?.begin('history.request', operationId: requestId);
    _inFlight++;
    trace?.emit('history.requested', operationId: requestId,
      counts: {'minutes': minutes, 'generation': generation, 'in_flight': _inFlight});
    void observePublication() {
      trace?.emit('history.publication_attempt', operationId: requestId,
        outcome: _traceDisposed ? 'post_dispose' : generation != _generation || minutes != state.minutes ? 'stale' : 'current',
        counts: {'minutes': minutes, 'generation': generation});
    }
    try {
      final response = await (trace == null
          ? _apiService.fetchTelemetryHistory(_metric, minutes)
          : trace.withRequest(requestId!, () => _apiService.fetchTelemetryHistory(_metric, minutes)));
      observePublication();
      if (response != null) {
        state = state.copyWith(
          isLoading: false,
          response: response,
          error: null,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to fetch history for $_metric',
        );
      }
      trace?.emit('history.applied', operationId: requestId,
        counts: {'minutes': minutes, 'generation': generation});
      request?.end(outcome: response == null ? 'unavailable' : 'returned');
    } catch (e) {
      request?.end(outcome: 'failed');
      observePublication();
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      _inFlight--;
      trace?.emit('history.settled', operationId: requestId, counts: {'in_flight': _inFlight});
    }
  }

  void setMinutes(int newMinutes) {
    if (state.minutes != newMinutes) {
      state = state.copyWith(minutes: newMinutes);
      _fetchHistory(); // fetch immediately on change
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _traceDisposed = true;
    _trace?.emit('history.dispose', counts: {'in_flight': _inFlight});
    super.dispose();
  }
}

// We use FamilyStateNotifier from riverpod to pass the metric as an argument
final telemetryHistoryProvider = StateNotifierProvider.autoDispose
    .family<TelemetryHistoryNotifier, TelemetryHistoryState, String>((
      ref,
      metric,
    ) {
      final apiService = ref.watch(apiServiceProvider);
      return TelemetryHistoryNotifier(apiService, metric);
    });
