import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_history_provider.dart';
import 'package:gs_analyzer_ui/screen/ram_scannner_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gs_analyzer_ui/widgets/global_sidebar_widget.dart';
import 'package:gs_analyzer_ui/widgets/hud_accent_toggle.dart';

class WidgetRamApi extends Mock implements ApiService {}
class WidgetSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  WidgetSettings(bool compact) : super(SettingsState(isLoading: false,
      currentSettings: AppSettings.fromjson({'appearance': {'compactMode': compact}})));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> payload({bool legacy = false, bool unavailable = false, bool capacity = true, bool critical = false}) => {
  'processMemorySemantics': 'windows-private-ws',
  'global': {'totalGb': 4, 'activeGb': critical ? 3.9 : 2, 'cacheGb': 2,
    if (capacity) 'physicalTotalBytes': 4294967296},
  'processes': [{
    'processId': 42, 'name': 'sample', 'user': 'User', 'status': 'RUNNING',
    'workingSetBytes': 2147483648, 'ramMb': 2048,
    if (!legacy) 'privateWorkingSetBytes': unavailable ? null : 1073741824,
    if (!legacy) 'commitBytes': 8589934592,
  }],
};

void expectCenteredSegments(WidgetTester tester, Finder group, List<String> captions) {
  final pill = tester.getRect(group);
  for (final caption in captions) {
    final label = find.descendant(of: group, matching: find.text(caption));
    final paragraph = tester.renderObject<RenderParagraph>(label);
    final textBounds = MatrixUtils.transformRect(paragraph.getTransformTo(null), paragraph.paintBounds);
    final inner = tester.getRect(find.ancestor(of: label, matching: find.byType(TextButton)).first);
    final offset = textBounds.center.dy - pill.center.dy;
    final reason = '$caption: pill=${pill.height}, inner=${inner.height}, label-center-offset=$offset';
    expect(offset, closeTo(0, 1), reason: reason);
    expect(inner.top, greaterThanOrEqualTo(pill.top - 0.01), reason: reason);
    expect(inner.bottom, lessThanOrEqualTo(pill.bottom + 0.01), reason: reason);
    expect(textBounds.top, greaterThanOrEqualTo(pill.top), reason: reason);
    expect(textBounds.bottom, lessThanOrEqualTo(pill.bottom), reason: reason);
  }
}

void main() {
  late WidgetRamApi api;
  setUp(() {
    api = WidgetRamApi();
    when(() => api.startRamRadar()).thenAnswer((_) async {});
    when(() => api.fetchTelemetryHistory(any(), any())).thenAnswer((_) async => null);
  });

  Future<ProviderContainer> host(WidgetTester tester, {bool light = false, bool compact = true, bool loading = false,
      Map<String, dynamic>? data, Color? accent, bool sidebar = false}) async {
    final container = ProviderContainer(overrides: [
      ramProvider.overrideWith((ref) => RamNotifier(ref, api)),
      settingsProvider.overrideWith((ref) => WidgetSettings(compact)),
      apiServiceProvider.overrideWithValue(api),
      navigationProvider.overrideWith((ref) => AppRoute.memory),
    ]);
    addTearDown(container.dispose);
    if (!loading) container.read(ramProvider.notifier).updateProcesses(data ?? payload());
    await tester.binding.setSurfaceSize(Size(sidebar ? 720 : 520, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(theme: light ? HudTheme.lightTheme(accent ?? HudColor.lightAccentCyan) : HudTheme.darkTheme(accent ?? HudColor.darkAccentCyan),
        home: RepaintBoundary(key: const ValueKey('ram-screen-pixels'),
          child: Scaffold(body: sidebar ? const Row(children: [
            GlobalSidebarWidget(), Expanded(child: RamScannerScreen()),
          ]) : const RamScannerScreen())))));
    await tester.pump();
    if (sidebar) {
      await tester.tap(find.byTooltip('Expand Menu'));
      await tester.pumpAndSettle();
    }
    return container;
  }

  testWidgets('selected segment uses the user accent and readable rendered text', (tester) async {
    await host(tester, accent: HudColor.darkAccentAmber);
    await tester.pumpAndSettle();
    final label = find.descendant(of: find.byType(HudAccentToggle<ProcessMemoryMetric>), matching: find.text('PRIVATE WS'));
    final paragraph = tester.renderObject<RenderParagraph>(label);
    final foreground = paragraph.text.style!.color!;
    final labelBounds = tester.getRect(label);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('ram-screen-pixels')));
    final fill = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final x = (labelBounds.left - 4).floor();
        final y = labelBounds.center.dy.floor();
        expect(x, inInclusiveRange(0, image.width - 1));
        expect(y, inInclusiveRange(0, image.height - 1));
        final index = (y * image.width + x) * 4;
        return Color.fromARGB(pixels.getUint8(index + 3), pixels.getUint8(index),
          pixels.getUint8(index + 1), pixels.getUint8(index + 2));
      } finally {
        image.dispose();
      }
    }))!;
    final a = foreground.computeLuminance();
    final b = fill.computeLuminance();
    final contrast = a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
    expect(fill.toARGB32(), HudColor.darkAccentAmber.toARGB32());
  });

  testWidgets('column switches exclusively between value and percentage with a trailing control', (tester) async {
    final container = await host(tester);
    expect(find.text('1024.0 MIB'), findsOneWidget);
    expect(find.textContaining('OF RAM CAPACITY'), findsNothing);
    await tester.tap(find.text('PERCENTAGE'));
    await tester.pumpAndSettle();
    expect(find.text('1024.0 MIB'), findsNothing);
    expect(find.text('25.0%'), findsOneWidget);
    await tester.ensureVisible(find.text('COMMIT'));
    await tester.tap(find.text('COMMIT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(container.read(ramProvider).selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    expect(container.read(ramProvider).memoryDisplayMode, ProcessMemoryDisplayMode.percentage);
    await tester.tap(find.text('LIVE VIEW'));
    await tester.pumpAndSettle();
    expect(container.read(ramProvider).selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    expect(find.text('8192.0 MIB'), findsNothing);
    expect(find.text('200.0%'), findsOneWidget);
    final metricRect = tester.getRect(find.byKey(const ValueKey('ram-memory-metric')));
    final displayRect = tester.getRect(find.byKey(const ValueKey('ram-memory-display')));
    expect(displayRect.left, greaterThan(metricRect.right));
    expect(displayRect.center.dy, closeTo(metricRect.center.dy, 1));
    await tester.tap(find.text('VALUE'));
    await tester.pumpAndSettle();
    expect(find.text('8192.0 MIB'), findsOneWidget);
    expect(find.text('200.0%'), findsNothing);
    verify(() => api.startRamRadar()).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('measured zero and a missing denominator stay honest in either format', (tester) async {
    final zero = payload();
    zero['processes'][0]['privateWorkingSetBytes'] = 0;
    final container = await host(tester, data: zero);
    expect(find.text('0.0 MIB'), findsOneWidget);
    await tester.tap(find.text('PERCENTAGE'));
    await tester.pumpAndSettle();
    expect(find.text('0.0%'), findsOneWidget);
    container.read(ramProvider.notifier).updateProcesses(payload(capacity: false));
    await tester.pump();
    expect(find.text('N/A'), findsOneWidget);
    await tester.tap(find.text('VALUE'));
    await tester.pumpAndSettle();
    expect(find.text('1024.0 MIB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric and display choices survive legacy frames route and theme changes', (tester) async {
    final container = await host(tester);
    final notifier = container.read(ramProvider.notifier);
    await tester.tap(find.text('PERCENTAGE'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('COMMIT'));
    await tester.tap(find.text('COMMIT'));
    await tester.pumpAndSettle();
    notifier.updateProcesses(payload(legacy: true));
    await tester.pump();
    expect(find.text('LEGACY WS ESTIMATE'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: Scaffold(body: Text('OTHER ROUTE')))));
    await tester.pump();
    notifier.updateProcesses(payload());
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(theme: HudTheme.lightTheme(HudColor.lightAccentGreen),
        home: const RepaintBoundary(key: ValueKey('ram-screen-pixels'),
          child: Scaffold(body: RamScannerScreen())))));
    await tester.pumpAndSettle();
    expect(container.read(ramProvider).selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    expect(container.read(ramProvider).memoryDisplayMode, ProcessMemoryDisplayMode.percentage);
    expect(find.text('200.0%'), findsOneWidget);
    verify(() => api.startRamRadar()).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy and unavailable values are visibly distinguished', (tester) async {
    final container = await host(tester, data: payload(legacy: true));
    expect(find.text('LEGACY WS ESTIMATE'), findsOneWidget);
    container.read(ramProvider.notifier).updateProcesses(payload(unavailable: true, capacity: false));
    await tester.pump();
    expect(find.text('N/A'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    expect(find.text('N/A % OF RAM CAPACITY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final light in [false, true]) {
    for (final density in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('RAM groups stay compact fully visible stable and vertically centered light=$light density=$density scale=$scale', (tester) async {
          tester.view.devicePixelRatio = scale;
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = await host(tester, light: light, compact: density, sidebar: true, data: payload(critical: true));
          final metricGroup = find.byType(HudAccentToggle<ProcessMemoryMetric>);
          final displayGroup = find.byType(HudAccentToggle<ProcessMemoryDisplayMode>);
          final viewport = find.byKey(const ValueKey('ram-memory-metric'));
          final originalMetric = tester.getRect(metricGroup);
          final originalDisplay = tester.getRect(displayGroup);
          expect(originalMetric.height, closeTo(28, 0.01));
          expect(originalDisplay.height, closeTo(28, 0.01));
          expect(originalMetric.width, lessThanOrEqualTo(250));
          expect(originalDisplay.width, lessThanOrEqualTo(170));
          final notifier = container.read(ramProvider.notifier);
          for (final metric in ProcessMemoryMetric.values) {
            for (final mode in ProcessMemoryDisplayMode.values) {
              notifier.setMemoryMetric(metric);
              notifier.setMemoryDisplayMode(mode);
              await tester.pumpAndSettle();
              final left = tester.getRect(metricGroup);
              final right = tester.getRect(displayGroup);
              final clip = tester.getRect(viewport);
              expect(left.size, originalMetric.size);
              expect(right.size, originalDisplay.size);
              expect(left.left, greaterThanOrEqualTo(clip.left - 0.01));
              expect(left.right, lessThanOrEqualTo(clip.right + 0.01));
              expect(left.overlaps(right), isFalse);
              expect(left.center.dy, closeTo(right.center.dy, 0.01));
              expectCenteredSegments(tester, metricGroup, ['PRIVATE WS', 'TOTAL WS', 'COMMIT']);
              expectCenteredSegments(tester, displayGroup, ['VALUE', 'PERCENTAGE']);
              expect(tester.takeException(), isNull);
            }
          }
        });
      }
    }
  }

  for (final light in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets('minimum body with critical banner adapts light=$light compact=$compact', (tester) async {
        await host(tester, light: light, compact: compact, data: payload(critical: true), sidebar: true);
        expect(find.text('RAM CRITICAL ALERT: REDUCE SYSTEM LOAD'), findsOneWidget);
        expect(find.byType(SegmentedButton<ProcessMemoryMetric>), findsOneWidget);
        expect(find.text('1024.0 MIB'), findsOneWidget);
        expect(find.byTooltip('Collapse Menu'), findsOneWidget);
        expect(find.text('PERCENTAGE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('loading and empty process states remain usable', (tester) async {
    final container = await host(tester, loading: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    container.read(ramProvider.notifier).updateProcesses({'global': {'totalGb': 4}, 'processes': []});
    await tester.pump();
    expect(find.text('NO PROCESS DATA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
