import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/temp_cleaner_model.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class TempCleanerState {
  final bool isLoading;
  final bool isCleaning;
  final TempPreviewResponse? preview;
  final Set<String> selectedPaths;
  final TempCleanResult? cleanResult;
  final String? errorMessage;

  TempCleanerState({
    this.isLoading = false,
    this.isCleaning = false,
    this.preview,
    this.selectedPaths = const {},
    this.cleanResult,
    this.errorMessage,
  });

  TempCleanerState copyWith({
    bool? isLoading,
    bool? isCleaning,
    TempPreviewResponse? preview,
    Set<String>? selectedPaths,
    TempCleanResult? cleanResult,
    String? errorMessage,
    bool clearPreview = false,
    bool clearCleanResult = false,
    bool clearError = false,
  }) {
    return TempCleanerState(
      isLoading: isLoading ?? this.isLoading,
      isCleaning: isCleaning ?? this.isCleaning,
      preview: clearPreview ? null : (preview ?? this.preview),
      selectedPaths: selectedPaths ?? this.selectedPaths,
      cleanResult: clearCleanResult ? null : (cleanResult ?? this.cleanResult),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class TempCleanerNotifier extends StateNotifier<TempCleanerState> {
  final Ref ref;
  final ApiService _apiService;

  TempCleanerNotifier(this.ref, [ApiService? apiService])
      : _apiService = apiService ?? ApiService(),
        super(TempCleanerState());

  Future<void> fetchPreview() async {
    state = state.copyWith(
      isLoading: true,
      isCleaning: false,
      clearPreview: true,
      clearCleanResult: true,
      clearError: true,
    );

    try {
      final result = await _apiService.getTempPreview();

      // Auto-select all location paths by default.
      final allPaths = result.locations.map((loc) => loc.path).toSet();

      state = state.copyWith(
        isLoading: false,
        isCleaning: false,
        preview: result,
        selectedPaths: allPaths,
      );
    } catch (e) {
      appLogger.i('TEMP PREVIEW CRASHED: $e');
      state = state.copyWith(
        isLoading: false,
        isCleaning: false,
        errorMessage: e.toString(),
      );
    }
  }

  void togglePath(String path) {
    final updated = Set<String>.from(state.selectedPaths);
    if (updated.contains(path)) {
      updated.remove(path);
    } else {
      updated.add(path);
    }
    state = state.copyWith(selectedPaths: updated);
  }

  Future<void> cleanSelected() async {
    if (state.selectedPaths.isEmpty) return;

    state = state.copyWith(
      isLoading: true,
      isCleaning: true,
      clearCleanResult: true,
      clearError: true,
    );

    try {
      final result = await _apiService.cleanTempFiles(
        state.selectedPaths.toList(),
      );

      // Immediately fetch fresh preview so state reflects the actual post-clean filesystem.
      TempPreviewResponse? freshPreview;
      Set<String> remainingPaths = const {};
      try {
        freshPreview = await _apiService.getTempPreview();
        remainingPaths = freshPreview.locations.map((loc) => loc.path).toSet();
      } catch (previewErr) {
        appLogger.i('TEMP POST-CLEAN PREVIEW FAILED: $previewErr');
      }

      state = state.copyWith(
        isLoading: false,
        isCleaning: false,
        cleanResult: result,
        preview: freshPreview,
        clearPreview: freshPreview == null,
        selectedPaths: remainingPaths,
      );
    } catch (e) {
      appLogger.i('TEMP CLEAN CRASHED: $e');
      state = state.copyWith(
        isLoading: false,
        isCleaning: false,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() {
    state = TempCleanerState();
  }
}

final tempCleanerProvider =
    StateNotifierProvider<TempCleanerNotifier, TempCleanerState>(
      (ref) => TempCleanerNotifier(ref),
    );

final tempCleanProgressProvider = StateProvider<double>((ref) => 0.0);
final tempCleanTargetProvider = StateProvider<String>((ref) => '');
final tempCleanCompletedProvider = StateProvider<int>((ref) => 0);
final tempCleanTotalProvider = StateProvider<int>((ref) => 0);
