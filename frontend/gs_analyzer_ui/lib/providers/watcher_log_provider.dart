import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/watcher_event.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/services/telemetry_service.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';

class WatcherLogState {
  final List<WatcherEvent> events;
  final bool isPaused;
  final WatcherChangeKind? filterKind;

  WatcherLogState({
    required this.events,
    this.isPaused = false,
    this.filterKind,
  });

  WatcherLogState copyWith({
    List<WatcherEvent>? events,
    bool? isPaused,
    WatcherChangeKind? filterKind,
  }) {
    return WatcherLogState(
      events: events ?? this.events,
      isPaused: isPaused ?? this.isPaused,
      filterKind: filterKind != null
          ? (filterKind == WatcherChangeKind.modified
                ? this.filterKind
                : filterKind) // workaround if we need null
          : this.filterKind,
    );
  }
}

class WatcherLogNotifier extends StateNotifier<WatcherLogState> {
  final ApiService _api;
  final TelemetryService _telemetry;
  final List<WatcherEvent> _pendingEvents = [];
  bool _initialized = false;
  bool _isAutoScrollLocked = false;

  WatcherLogNotifier(this._api, this._telemetry)
    : super(WatcherLogState(events: [])) {
    _telemetry.onWatcherEventLogged = _onSignalREvent;
    init();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final rawLogs = await _api.getWatcherLog(limit: 500);
    final events = rawLogs.map((json) => WatcherEvent.fromJson(json)).toList();

    state = WatcherLogState(
      events: events,
      isPaused: state.isPaused,
      filterKind: state.filterKind,
    );
  }

  void _onSignalREvent(Map<String, dynamic> rawEvent) {
    final event = WatcherEvent.fromJson(rawEvent);

    if (state.isPaused || _isAutoScrollLocked) {
      _pendingEvents.insert(0, event);
      if (_pendingEvents.length > 500) {
        _pendingEvents.removeLast();
      }
    } else {
      // Not paused, append immediately
      _addEventToState(event);
    }
  }

  void _addEventToState(WatcherEvent event) {
    // If it's a deduplicated event, we might need to replace the top one if it matches
    // But since the backend sends the fully updated event with new occurrences count,
    // we just replace it if it's the same path and kind within the same window.
    // Or simplest: if the very top event matches kind and path, replace it.

    List<WatcherEvent> newEvents = List.from(state.events);

    if (newEvents.isNotEmpty) {
      final top = newEvents.first;
      if (top.kind == event.kind &&
          top.path == event.path &&
          event.occurrences > top.occurrences) {
        newEvents[0] = event; // Update in-place
      } else {
        newEvents.insert(0, event);
      }
    } else {
      newEvents.insert(0, event);
    }

    if (newEvents.length > 500) {
      newEvents.removeLast();
    }

    state = WatcherLogState(
      events: newEvents,
      isPaused: state.isPaused,
      filterKind: state.filterKind,
    );
  }

  void togglePause() {
    if (state.isPaused) {
      // Resuming -> flush pending (unless scroll locked)
      if (!_isAutoScrollLocked) {
        _flushPending();
      } else {
        state = WatcherLogState(
          events: state.events,
          isPaused: false,
          filterKind: state.filterKind,
        );
      }
    } else {
      // Pausing
      state = WatcherLogState(
        events: state.events,
        isPaused: true,
        filterKind: state.filterKind,
      );
    }
  }

  void setAutoScrollLock(bool locked) {
    if (_isAutoScrollLocked == locked) return;
    _isAutoScrollLocked = locked;
    if (!locked && !state.isPaused) {
      _flushPending();
    }
  }

  void _flushPending() {
    if (_pendingEvents.isEmpty) {
      // Still need to update state if we were paused and just resuming
      state = WatcherLogState(
        events: state.events,
        isPaused: false,
        filterKind: state.filterKind,
      );
      return;
    }
    List<WatcherEvent> newEvents = List.from(_pendingEvents);
    newEvents.addAll(state.events);
    if (newEvents.length > 500) {
      newEvents = newEvents.sublist(0, 500);
    }
    _pendingEvents.clear();

    state = WatcherLogState(
      events: newEvents,
      isPaused: false,
      filterKind: state.filterKind,
    );
  }

  void setFilter(WatcherChangeKind? kind) {
    state = WatcherLogState(
      events: state.events,
      isPaused: state.isPaused,
      filterKind: kind,
    );
  }

  Future<void> clearLog() async {
    final success = await _api.clearWatcherLog();
    if (success) {
      _pendingEvents.clear();
      state = WatcherLogState(
        events: [],
        isPaused: state.isPaused,
        filterKind: state.filterKind,
      );
    }
  }

  List<WatcherEvent> get filteredEvents {
    if (state.filterKind == null) return state.events;
    return state.events.where((e) => e.kind == state.filterKind).toList();
  }
}

final watcherLogProvider =
    StateNotifierProvider<WatcherLogNotifier, WatcherLogState>((ref) {
      final api = ApiService();
      final telemetryNotifier = ref.read(telemetryProvider.notifier);
      return WatcherLogNotifier(api, telemetryNotifier.service!);
    });
