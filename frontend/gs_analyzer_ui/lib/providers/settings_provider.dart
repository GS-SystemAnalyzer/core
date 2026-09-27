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

  const SettingsState({
    this.savedSettings,
    this.currentSettings,
    this.isLoading = true,
    this.validationErrors = const [],
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

  SettingsState copyWith({
    AppSettings? savedSettings,
    AppSettings? currentSettings,
    bool? isLoading,
    List<String>? validationErrors,
  }) {
    return SettingsState(
      savedSettings: savedSettings ?? this.savedSettings,
      currentSettings: currentSettings ?? this.currentSettings,
      isLoading: isLoading ?? this.isLoading,
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final ApiService _api = ApiService();

  SettingsNotifier() : super(const SettingsState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final cacheJson = prefs.getString('gs_settings_cache');

    if (cacheJson != null) {
      try {
        final saved = AppSettings.fromjson(jsonDecode(cacheJson));
        state = state.copyWith(
          savedSettings: saved,
          currentSettings: saved.clone(),
          isLoading: false,
        );
      } catch (e) {
        appLogger.i('Error loading settings cache: $e');
      }
    }

    final remoteData = await _api.getSettings();
    if (!mounted) return;

    if (remoteData != null) {
      final saved = AppSettings.fromjson(remoteData);
      state = state.copyWith(
        savedSettings: saved,
        currentSettings: saved.clone(),
        isLoading: false,
      );
      prefs.setString('gs_settings_cache', jsonEncode(remoteData));
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  void updateUI() {
    state = state.copyWith(
      currentSettings: state.currentSettings?.clone(),
      validationErrors: [],
    );
  }

  Future<bool> saveChanges() async {
    if (state.currentSettings == null) return false;

    state = state.copyWith(isLoading: true);

    final response = await _api.saveSettings(state.currentSettings!.toJson());
    if (response?['success'] == true) {
      final newSave = state.currentSettings!.clone();
      state = state.copyWith(
        savedSettings: newSave,
        currentSettings: newSave.clone(),
        validationErrors: [],
        isLoading: false,
      );

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('gs_settings_cache', jsonEncode(newSave.toJson()));
      return true;
    } else {
      state = state.copyWith(
        validationErrors: response?['errors'] != null
            ? List<String>.from(response?['errors'])
            : [],
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> resetToDefaults() async {
    state = state.copyWith(isLoading: true);

    final defaultData = await _api.resetSettings();
    if (defaultData != null) {
      final defaultSettings = AppSettings.fromjson(defaultData);

      state = state.copyWith(
        savedSettings: defaultSettings,
        currentSettings: defaultSettings.clone(),
        validationErrors: [],
        isLoading: false,
      );

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('gs_settings_cache', jsonEncode(defaultData));
      return true;
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
