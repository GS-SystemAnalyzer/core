import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/startup_program.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';

final startupProvider =
    StateNotifierProvider<StartupNotifier, AsyncValue<List<StartupProgram>>>(
  (ref) => StartupNotifier(ApiService())..load(),
);

class StartupNotifier extends StateNotifier<AsyncValue<List<StartupProgram>>> {
  StartupNotifier(this._api) : super(const AsyncValue.loading());

  final ApiService _api;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final programs = await _api.getStartupPrograms();
      state = AsyncValue.data(programs);
    } catch (e, st) {
      appLogger.i('[Startup] Load failed: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggle(StartupProgram program) async {
    final target = !program.isEnabled;
    _patch(program.id, program.copyWith(isEnabled: target));
    try {
      await _api.setStartupEnabled(
        program.id,
        target,
        scope: program.scope,
      );
    } catch (e) {
      _patch(program.id, program.copyWith(isEnabled: program.isEnabled));
      rethrow;
    }
  }

  Future<void> remove(StartupProgram program) async {
    final current = state.value ?? const <StartupProgram>[];
    state = AsyncValue.data(
      current.where((p) => p.id != program.id).toList(),
    );
    try {
      await _api.deleteStartupProgram(program.id);
    } catch (e) {
      await load();
      rethrow;
    }
  }

  void _patch(String id, StartupProgram updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final p in current)
        if (p.id == id) updated else p,
    ]);
  }
}
