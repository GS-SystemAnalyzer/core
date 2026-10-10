import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

// Minimised-state flags — one per long-running operation.
final scanMinimizedProvider = StateProvider<bool>((ref) => false);
final nukeMinimizedProvider = StateProvider<bool>((ref) => false);
final tempCleanMinimizedProvider = StateProvider<bool>((ref) => false);
final exportMinimizedProvider = StateProvider<bool>((ref) => false);

// Whether a large-export is in progress (lifted from ExportScanDialog._isExporting).
final exportActiveProvider = StateProvider<bool>((ref) => false);

// The drive name of the in-flight export, so a minimised export pill can
// re-open the right ExportScanDialog on restore.
final exportDriveProvider = StateProvider<String?>((ref) => null);

// Persisted pill position — loaded from shared_preferences key 'ui.scanPillOffset'.
// Defaults to Offset(16, -80) (bottom-left, just above the window bottom edge).
class ScanPillOffsetNotifier extends StateNotifier<Offset> {
  static const _key = 'ui.scanPillOffset';

  ScanPillOffsetNotifier() : super(const Offset(16, -80)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('${_key}_dx');
    final dy = prefs.getDouble('${_key}_dy');
    if (dx != null && dy != null) {
      state = Offset(dx, dy);
    }
  }

  Future<void> update(Offset offset) async {
    state = offset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_key}_dx', offset.dx);
    await prefs.setDouble('${_key}_dy', offset.dy);
  }
}

final scanPillOffsetProvider =
    StateNotifierProvider<ScanPillOffsetNotifier, Offset>(
      (ref) => ScanPillOffsetNotifier(),
    );
