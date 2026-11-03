import 'package:gs_analyzer_ui/utils/logger.dart';
import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class SettingsState {
  final AppSettings? savedSettings;
  final AppSettings? currentSettings;
  final bool isLoading;
  final List<String> validationErrors;
  final bool serviceConfirmed;
  final String? persistenceError;

  const SettingsState({
    this.savedSettings,
    this.currentSettings,
    this.isLoading = true,
    this.validationErrors = const [],
    this.serviceConfirmed = false,
    this.persistenceError,
  });

  bool get hasUnsavedChanges {
    if (savedSettings == null || currentSettings == null) return false;
    return jsonEncode(savedSettings!.toJson()) !=
        jsonEncode(currentSettings!.toJson());
  }

  int get thermalThreshold =>
      currentSettings?.alerts.thermalThresholdCelsius ?? 85;
  int get ramThreshold => currentSettings?.alerts.ramThresholdPercent ?? 85;
  int get cpuThreshold => currentSettings?.alerts.cpuThresholdPercent ?? 95;
  bool get ramCadenceConfirmed => serviceConfirmed &&
      savedSettings != null &&
      savedSettings!.monitoring.ramPollIntervalMs >= MonitoringSettings.minRamPollIntervalMs &&
      savedSettings!.monitoring.ramPollIntervalMs <= MonitoringSettings.maxRamPollIntervalMs;

  SettingsState copyWith({
    AppSettings? savedSettings,
    AppSettings? currentSettings,
    bool? isLoading,
    List<String>? validationErrors,
    bool? serviceConfirmed,
    String? persistenceError,
    bool clearPersistenceError = false,
  }) {
    return SettingsState(
      savedSettings: savedSettings ?? this.savedSettings,
      currentSettings: currentSettings ?? this.currentSettings,
      isLoading: isLoading ?? this.isLoading,
      validationErrors: validationErrors ?? this.validationErrors,
      serviceConfirmed: serviceConfirmed ?? this.serviceConfirmed,
      persistenceError: clearPersistenceError ? null : persistenceError ?? this.persistenceError,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final ApiService _api;
  int _draftRevision = 0;
  int _commitRevision = 0;
  late final Future<void> initialized;

  SettingsNotifier([ApiService? api]) : _api = api ?? ApiService(), super(const SettingsState()) {
    initialized = _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final cacheJson = prefs.getString('gs_settings_cache');
      if (cacheJson != null) {
        try {
          final cached = Map<String, dynamic>.from(jsonDecode(cacheJson));
          final monitoring = cached['monitoring'] is Map
              ? Map<String, dynamic>.from(cached['monitoring'])
              : <String, dynamic>{};
          final period = monitoring['ramPollIntervalMs'];
          if (period is! int || !_supportedRamPeriod(period)) {
            monitoring['ramPollIntervalMs'] = MonitoringSettings.defaultRamPollIntervalMs;
          }
          cached['monitoring'] = monitoring;
          final saved = AppSettings.fromjson(cached);
          state = state.copyWith(savedSettings: saved, currentSettings: saved.clone(),
              isLoading: false, serviceConfirmed: false);
        } catch (e) {
          appLogger.i('Error loading settings cache: $e');
        }
      }
      final revision = _draftRevision;
      final committed = _commitRevision;
      final remoteData = await _api.getSettings();
      if (!mounted || committed != _commitRevision) return;
      if (remoteData == null) {
        state = state.copyWith(isLoading: false, serviceConfirmed: false);
        return;
      }
      final saved = AppSettings.fromjson(remoteData);
      final valid = _supportedRamPeriod(saved.monitoring.ramPollIntervalMs);
      final draft = revision != _draftRevision || state.hasUnsavedChanges
          ? state.currentSettings
          : saved.clone();
      state = state.copyWith(savedSettings: saved, currentSettings: draft,
          isLoading: false, serviceConfirmed: valid,
          persistenceError: valid ? null : 'Backend RAM cadence is not supported; update the backend before confirming it.',
          clearPersistenceError: valid);
      if (!await prefs.setString('gs_settings_cache', jsonEncode(saved.toJson())) && mounted) {
        state = state.copyWith(persistenceError: 'Unable to persist the local settings cache.');
      }
    } catch (e) {
      if (mounted) state = state.copyWith(isLoading: false,
          persistenceError: 'Unable to load confirmed settings: $e');
    }
  }

  static bool _supportedRamPeriod(int period) =>
      period >= MonitoringSettings.minRamPollIntervalMs &&
      period <= MonitoringSettings.maxRamPollIntervalMs;

  void updateUI() {
    _draftRevision++;
    state = state.copyWith(
      currentSettings: state.currentSettings?.clone(),
      validationErrors: [],
    );
  }

  Future<bool> saveChanges() async {
    if (state.currentSettings == null) return false;
    final submitted = state.currentSettings!.clone();
    final revision = _draftRevision;
    if (!_supportedRamPeriod(submitted.monitoring.ramPollIntervalMs)) {
      state = state.copyWith(validationErrors: ['RAM Poll Interval must be between ${MonitoringSettings.minRamPollIntervalMs}ms and ${MonitoringSettings.maxRamPollIntervalMs}ms.']);
      return false;
    }
    state = state.copyWith(isLoading: true, clearPersistenceError: true);
    try {
      final response = await _api.saveSettings(submitted.toJson());
      if (!mounted) return false;
      if (response?['success'] != true || response?['data'] is! Map) {
        state = state.copyWith(isLoading: false,
            validationErrors: response?['errors'] is List ? List<String>.from(response!['errors']) : [],
            persistenceError: response?['message']?.toString() ?? 'The backend did not acknowledge the submitted settings.');
        return false;
      }
      final acknowledged = AppSettings.fromjson(Map<String, dynamic>.from(response!['data']));
      if (!_supportedRamPeriod(acknowledged.monitoring.ramPollIntervalMs)) {
        state = state.copyWith(isLoading: false, serviceConfirmed: false,
            persistenceError: 'The backend acknowledged an unsupported RAM cadence.');
        return false;
      }
      _commitRevision++;
      final prefs = await SharedPreferences.getInstance();
      final cached = await prefs.setString('gs_settings_cache', jsonEncode(acknowledged.toJson()));
      if (!mounted) return false;
      state = state.copyWith(savedSettings: acknowledged,
          currentSettings: revision == _draftRevision ? acknowledged.clone() : state.currentSettings,
          validationErrors: [], isLoading: false, serviceConfirmed: true,
          persistenceError: cached ? null : 'Settings were saved by the backend, but the local cache write failed.',
          clearPersistenceError: cached);
      return cached;
    } catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, persistenceError: 'Unable to save settings: $e');
      return false;
    }
  }

  Future<bool> resetToDefaults() async {
    final revision = _draftRevision;
    state = state.copyWith(isLoading: true);

    final defaultData = await _api.resetSettings();
    if (defaultData != null) {
      final defaultSettings = AppSettings.fromjson(defaultData);
      _commitRevision++;

      state = state.copyWith(
        savedSettings: defaultSettings,
        currentSettings: revision == _draftRevision ? defaultSettings.clone() : state.currentSettings,
        validationErrors: [],
        isLoading: false,
        serviceConfirmed: _supportedRamPeriod(defaultSettings.monitoring.ramPollIntervalMs),
      );

      final prefs = await SharedPreferences.getInstance();
      final cached = await prefs.setString('gs_settings_cache', jsonEncode(defaultData));
      if (!cached && mounted) state = state.copyWith(persistenceError: 'Unable to persist the local settings cache.');
      return cached;
    } else {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  Future<bool> clearCache() async {
    state = state.copyWith(isLoading: true);
    final success = await _api.clearCache();
    state = state.copyWith(isLoading: false);
    return success;
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);
