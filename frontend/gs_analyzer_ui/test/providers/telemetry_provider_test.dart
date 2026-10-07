import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';

// The real TelemetryNotifier opens a live SignalR connection in its constructor;
// autoConnect:false skips that so the reducer can be driven directly (same approach as
// operation_pill_layer_test.dart). Regression tests for issue #206 — ScanProgress reducer.
class _TestTelemetry extends TelemetryNotifier {
  _TestTelemetry(Ref ref) : super(ref, autoConnect: false);
}

void main() {
  late ProviderContainer container;
  late TelemetryNotifier notifier;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        telemetryProvider.overrideWith((ref) => _TestTelemetry(ref)),
      ],
    );
    notifier = container.read(telemetryProvider.notifier);
  });
  tearDown(() => container.dispose());

  TelemetryState current() => container.read(telemetryProvider);

  // #206 2a (end-to-end with the backend fix): a SCANNING update must move the UI off
  // INITIALIZING and show the live counters.
  test('a SCANNING update leaves INITIALIZING and updates the counters', () {
    notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
    notifier.applyScanProgress('scan-1', 'SCANNING', 3, 10, 30, 'folder');

    expect(current().status, 'SCANNING');
    expect(current().completed, 3);
    expect(current().total, 10);
    expect(current().percentComplete, 30);
  });

  // #206 2c/2d: CANCELED must be terminal, and the active scan id must be cleared so a
  // later scan's updates are accepted again.
  test('CANCELED is terminal and clears the active scan id', () {
    notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
    notifier.applyScanProgress('scan-1', 'CANCELED', null, null, null, 'Scan canceled');

    expect(current().status, 'CANCELED');
    expect(current().currentScanId, isNull);
  });

  // #206 O-5: a late fire-and-forget SCANNING pulse from a finished scan must not revert
  // the terminal state (the per-directory send is not ordered against COMPLETED).
  test('a straggler SCANNING after COMPLETED does not revert the terminal state', () {
    notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
    notifier.applyScanProgress('scan-1', 'COMPLETED', null, null, null, 'done');
    notifier.applyScanProgress('scan-1', 'SCANNING', 9, 10, 90, 'late folder');

    expect(current().status, 'COMPLETED');
  });

  // A fresh scan after a terminal state must be accepted and reset the counters.
  test('a new scan after a terminal state is accepted and resets the counters', () {
    notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
    notifier.applyScanProgress('scan-1', 'COMPLETED', null, null, null, 'done');
    notifier.applyScanProgress('scan-2', 'INITIALIZING', 0, 5, 0, 'start2');

    expect(current().currentScanId, 'scan-2');
    expect(current().status, 'INITIALIZING');
    expect(current().total, 5);
  });
}
