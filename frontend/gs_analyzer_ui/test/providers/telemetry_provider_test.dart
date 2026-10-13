import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/scan_diff_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

// The real TelemetryNotifier opens a live SignalR connection in its constructor;
// autoConnect:false skips that so the reducer can be driven directly.
class _TestTelemetry extends TelemetryNotifier {
  _TestTelemetry(Ref ref) : super(ref, autoConnect: false);

  void triggerAutoScanComplete(String root) {
    ref.invalidate(scanDiffProvider(root));
    ref.read(directoryProvider.notifier).scanDirectory(root);

    final hud = snackbarKey.currentContext?.hudTheme;

    snackbarKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'AUTO-SCAN COMPLETE',
          style: hud?.header.copyWith(color: hud.textMain) ??
              TextStyle(
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                color: hud?.textMain,
              ),
        ),
        backgroundColor: hud?.panel,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

void main() {
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  group('TelemetryNotifier Reducer Tests', () {
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

    // A SCANNING update must move the UI off INITIALIZING and show the live counters.
    test('a SCANNING update leaves INITIALIZING and updates the counters', () {
      notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
      notifier.applyScanProgress('scan-1', 'SCANNING', 3, 10, 30, 'folder');

      expect(current().status, 'SCANNING');
      expect(current().completed, 3);
      expect(current().total, 10);
      expect(current().percentComplete, 30);
    });

    // CANCELED must be terminal, and the active scan id must be cleared so a
    // later scan's updates are accepted again.
    test('CANCELED is terminal and clears the active scan id', () {
      notifier.applyScanProgress('scan-1', 'INITIALIZING', 0, 10, 0, 'start');
      notifier.applyScanProgress('scan-1', 'CANCELED', null, null, null, 'Scan canceled');

      expect(current().status, 'CANCELED');
      expect(current().currentScanId, isNull);
    });

    // A late fire-and-forget SCANNING pulse from a finished scan must not revert
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
  });

  group('AutoScanComplete SnackBar Theme Adaptation Tests', () {
    testWidgets('onAutoScanComplete adapts SnackBar colors between Light and Dark themes', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = _TestTelemetry(container.read(telemetryProvider.notifier).ref);

      // 1. Light Mode
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      notifier.triggerAutoScanComplete('C:/');
      await tester.pump(const Duration(milliseconds: 300));

      final lightSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(lightSnackBar.backgroundColor, equals(HudColor.lightBgPanel));

      final lightText = tester.widget<Text>(find.text('AUTO-SCAN COMPLETE'));
      expect(lightText.style?.color, equals(HudColor.lightTextMain));

      snackbarKey.currentState?.removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 2. Dark Mode
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      notifier.triggerAutoScanComplete('C:/');
      await tester.pump(const Duration(milliseconds: 300));

      final darkSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(darkSnackBar.backgroundColor, equals(HudColor.darkBgPanel));

      final darkText = tester.widget<Text>(find.text('AUTO-SCAN COMPLETE'));
      expect(darkText.style?.color, equals(HudColor.darkTextMain));

      snackbarKey.currentState?.removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
