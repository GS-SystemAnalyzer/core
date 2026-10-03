import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/widgets/minimized_op_pill.dart';
import 'package:gs_analyzer_ui/widgets/operation_pill_layer.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_hud_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real TelemetryNotifier starts a live SignalR connection in its constructor
/// (telemetry_provider.dart:247), which leaves a pending reconnect timer and
/// trips the test binding's !timersPending invariant. This fake lets the base
/// constructor run, then immediately stops the service so no timer survives.
class _FakeTelemetry extends TelemetryNotifier {
  _FakeTelemetry(Ref ref) : super(ref, autoConnect: false);
}

Future<void> _pumpLayer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Stack(children: const [OperationPillLayer()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders no pill when nothing is active', (tester) async {
    await _pumpLayer(tester, ProviderContainer());
    expect(find.byType(MinimizedOpPill), findsNothing);
  });

  testWidgets('shows the scan pill when a scan is loading and minimised', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        telemetryProvider.overrideWith((ref) => _FakeTelemetry(ref)),
      ],
    );
    // A running scan: isLoading true. telemetry defaults to IDLE, which the
    // active branch renders as the "SCANNING" pill (resting as a ring).
    container.read(directoryProvider.notifier).state = container
        .read(directoryProvider)
        .copyWith(isLoading: true);
    container.read(scanMinimizedProvider.notifier).state = true;

    await _pumpLayer(tester, container);

    expect(find.byKey(const Key('pill_scan')), findsOneWidget);
    expect(find.byType(MinimizedOpPill), findsOneWidget);
  });

  testWidgets('hides the scan pill when minimised but no scan is loading', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        telemetryProvider.overrideWith((ref) => _FakeTelemetry(ref)),
      ],
    );
    container.read(directoryProvider.notifier).state = container
        .read(directoryProvider)
        .copyWith(isLoading: false);
    container.read(scanMinimizedProvider.notifier).state = true;

    await _pumpLayer(tester, container);

    expect(find.byType(MinimizedOpPill), findsNothing);
  });

  testWidgets('shows the nuke pill (ring shows integer percent) when active and minimised', (
    tester,
  ) async {
    final container = ProviderContainer();
    container.read(isNukeActiveProvider.notifier).state = true;
    container.read(nukeMinimizedProvider.notifier).state = true;
    container.read(nukeProgressProvider.notifier).state = 42.0;
    container.read(nukeTargetProvider.notifier).state = 'C:/file.pdf';

    await _pumpLayer(tester, container);

    expect(find.byKey(const Key('pill_nuke')), findsOneWidget);
    expect(find.text('42'), findsOneWidget); // resting ring, integer only
  });

  testWidgets('does not show the nuke pill when minimised but nuke inactive', (
    tester,
  ) async {
    final container = ProviderContainer();
    container.read(isNukeActiveProvider.notifier).state = false;
    container.read(nukeMinimizedProvider.notifier).state = true;

    await _pumpLayer(tester, container);

    expect(find.byType(MinimizedOpPill), findsNothing);
  });

  testWidgets('dragging the indicator updates the persisted offset', (
    tester,
  ) async {
    final container = ProviderContainer();
    container.read(isNukeActiveProvider.notifier).state = true;
    container.read(nukeMinimizedProvider.notifier).state = true;
    container.read(nukeProgressProvider.notifier).state = 42.0;
    container.read(nukeTargetProvider.notifier).state = 'C:/file.pdf';

    await _pumpLayer(tester, container);

    final before = container.read(scanPillOffsetProvider);
    await tester.drag(find.byType(MinimizedOpPill), const Offset(30, -12));
    await tester.pump();
    final after = container.read(scanPillOffsetProvider);

    expect(after, isNot(equals(before)),
        reason: 'onPanUpdate should move the persisted pill offset.');
  });

  testWidgets('scan card minimise button sets scanMinimizedProvider', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        telemetryProvider.overrideWith((ref) => _FakeTelemetry(ref)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: TelemetryHudWidget()),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(scanMinimizedProvider), isFalse);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(container.read(scanMinimizedProvider), isTrue);
  });

  testWidgets(
    'pill renders with no Overlay ancestor (mounted in MaterialApp.builder like main.dart)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(isNukeActiveProvider.notifier).state = true;
      container.read(nukeMinimizedProvider.notifier).state = true;
      container.read(nukeProgressProvider.notifier).state = 42.0;
      container.read(nukeTargetProvider.notifier).state = 'C:/file.pdf';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            // Exactly how main.dart mounts it: above the Navigator, so the pill
            // layer has NO Overlay ancestor. Tooltip would throw here.
            builder: (context, child) => Stack(
              children: [if (child != null) child, const OperationPillLayer()],
            ),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Pill mounted above the Navigator must not require an Overlay ancestor.',
      );
      expect(find.text('42'), findsOneWidget); // ring renders cleanly
    },
  );
}
