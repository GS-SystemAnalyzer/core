import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/age_heatmap_model.dart';
import 'package:gs_analyzer_ui/providers/age_heatmap_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/age_heatmap_overlay.dart';

void main() {
  group('bucketColor Helper Tests', () {
    testWidgets('resolves bucket colors correctly in Light Mode', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(bucketColor('fresh', capturedContext), equals(HudColor.lightAccentCyan));
      expect(bucketColor('recent', capturedContext), equals(HudColor.lightAccentGreen));
      expect(bucketColor('aging', capturedContext), equals(HudColor.lightAccentAmber));
      expect(bucketColor('stale', capturedContext), equals(HudColor.lightAccentRed));
      expect(bucketColor('unknown', capturedContext), equals(HudColor.lightTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('resolves bucket colors correctly in Dark Mode', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(bucketColor('fresh', capturedContext), equals(HudColor.darkAccentCyan));
      expect(bucketColor('recent', capturedContext), equals(HudColor.darkAccentGreen));
      expect(bucketColor('aging', capturedContext), equals(HudColor.darkAccentAmber));
      expect(bucketColor('stale', capturedContext), equals(HudColor.darkAccentRed));
      expect(bucketColor('unknown', capturedContext), equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('AgeHeatmapOverlay Widget Tests', () {
    const testPath = 'C:/test';

    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(1280, 800);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    final sampleResult = AgeHeatmapResult(
      root: testPath,
      nodes: [
        AgeHeatmapNode(
          path: 'C:/test/file1.txt',
          sizeBytes: 1024,
          ageBucket: 'fresh',
          lastModified: DateTime.now(),
        ),
      ],
      summary: const {
        'fresh': AgeBucketSummary(count: 1, totalBytes: 1024),
        'recent': AgeBucketSummary(count: 2, totalBytes: 2048),
        'aging': AgeBucketSummary(count: 0, totalBytes: 0),
        'stale': AgeBucketSummary(count: 5, totalBytes: 5120),
      },
    );

    testWidgets('renders loading state when provider is loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: testPath),
            ),
            ageHeatmapProvider(testPath).overrideWith(
              (ref) => Completer<AgeHeatmapResult>().future,
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: AgeHeatmapOverlay(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LOADING AGE HEATMAP...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('renders no-scan prompt on AgeHeatmapNoScanException', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: testPath),
            ),
            ageHeatmapProvider(testPath).overrideWith(
              (ref) async => throw const AgeHeatmapNoScanException(),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: AgeHeatmapOverlay(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RUN A SCAN FIRST'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders error message on generic error', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: testPath),
            ),
            ageHeatmapProvider(testPath).overrideWith(
              (ref) async => throw Exception('Network failed'),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: AgeHeatmapOverlay(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HEATMAP ERROR: Exception: Network failed'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders overlay legend bar and summary grid and adapts themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: testPath),
            ),
            ageHeatmapProvider(testPath).overrideWith(
              (ref) async => sampleResult,
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: AgeHeatmapOverlay(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FILE AGE MAP'), findsOneWidget);
      expect(find.text('FRESH'), findsOneWidget);
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.text('AGING'), findsOneWidget);
      expect(find.text('STALE'), findsOneWidget);

      final lightContainer = tester.widget<Container>(find.byType(Container).first);
      final lightBox = lightContainer.decoration as BoxDecoration;
      expect(lightBox.color, equals(HudColor.lightBgPanel));

      final lightTitle = tester.widget<Text>(find.text('FILE AGE MAP'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: testPath),
            ),
            ageHeatmapProvider(testPath).overrideWith(
              (ref) async => sampleResult,
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: AgeHeatmapOverlay(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(find.byType(Container).first);
      final darkBox = darkContainer.decoration as BoxDecoration;
      expect(darkBox.color, equals(HudColor.darkBgPanel));

      final darkTitle = tester.widget<Text>(find.text('FILE AGE MAP'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
