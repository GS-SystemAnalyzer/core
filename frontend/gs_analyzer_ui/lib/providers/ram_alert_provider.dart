import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/ram_alert.dart';

class RamAlertNotifier extends StateNotifier<RamAlert?> {
  RamAlertNotifier() : super(null);

  void handleRamAlert(RamAlert alert) {
    state = alert;
  }

  void handleRamAlertCleared() {
    state = null;
  }
}

final ramAlertProvider = StateNotifierProvider<RamAlertNotifier, RamAlert?>((
  ref,
) {
  return RamAlertNotifier();
});
