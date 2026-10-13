import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/providers/extension_breakdown_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/extension_breakdown_screen.dart';

const _root = r'C:\TestDrive';

ExtensionBreakdownItem _item(
  String ext,
  String category, {
  int fileCount = 1,
  int totalBytes = 1024,
}) {
  return ExtensionBreakdownItem(
    ext: ext,
    category: category,
    fileCount: fileCount,
    totalBytes: totalBytes,
    sizeFormatted: '1.0 KB',
    percentOfDisk: 50.0,
    averageFileSizeBytes: 1024,
    averageSizeFormatted: '1.0 KB',
    largestFilePath: '$_root\\big$ext',
    largestFileBytes: 1024,
    largestSizeFormatted: '1.0 KB',
  );
}

Widget _wrap(dynamic overrides, {ThemeData? theme}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      home: const ExtensionBreakdownScreen(scanRoot: _root, driveName: 'C:'),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while the breakdown is loading', (tester) async {
    await tester.pumpWidget(
      _wrap([
        // A future that never completes keeps the provider in the loading state.
        extensionBreakdownProvider(
          _root,
        ).overrideWith((ref) => Completer<ExtensionBreakdownResult>().future),
      ]),
    );

    await tester
        .pump(); // single frame — do NOT pumpAndSettle (spinner animates forever)

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('RUN A SCAN FIRST'), findsNothing);
  });

  testWidgets('shows the no-scan view when the API reports no cached scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        extensionBreakdownProvider(_root).overrideWith(
          (ref) =>
              Future<ExtensionBreakdownResult>.error(FileTypeNoScanException()),
        ),
      ]),
    );

    await tester.pumpAndSettle();

    expect(find.text('RUN A SCAN FIRST'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders extension rows when data is available', (tester) async {
    final result = ExtensionBreakdownResult(
      root: _root,
      extensions: [
        _item('.mp4', 'media', fileCount: 2, totalBytes: 8000),
        _item('.txt', 'documents', fileCount: 3, totalBytes: 1500),
      ],
    );

    await tester.pumpWidget(
      _wrap([extensionBreakdownProvider(_root).overrideWith((ref) => result)]),
    );

    await tester.pumpAndSettle();

    expect(find.text('.mp4'), findsOneWidget);
    expect(find.text('.txt'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('RUN A SCAN FIRST'), findsNothing);
  });

  testWidgets('builds without rows when the breakdown is empty', (
    tester,
  ) async {
    final empty = ExtensionBreakdownResult(root: _root, extensions: const []);

    await tester.pumpWidget(
      _wrap([extensionBreakdownProvider(_root).overrideWith((ref) => empty)]),
    );

    await tester.pumpAndSettle();

    // No data rows, but the screen still renders its header.
    expect(find.text('.mp4'), findsNothing);
    expect(find.textContaining('EXTENSION_BREAKDOWN'), findsOneWidget);
  });

  group('ExtensionBreakdownScreen Theme Adaptation Tests', () {
    testWidgets('adapts scaffold, header, search bar, and list row colors between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final result = ExtensionBreakdownResult(
        root: _root,
        extensions: [
          _item('.mp4', 'media', fileCount: 2, totalBytes: 8000),
        ],
      );

      // 1. Light Theme
      await tester.pumpWidget(
        _wrap(
          [extensionBreakdownProvider(_root).overrideWith((ref) => result)],
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, equals(HudColor.lightBgBase));

      final lightAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(lightAppBar.backgroundColor, equals(HudColor.lightBgPanel));

      final lightAppBarTitle = tester.widget<Text>(find.textContaining('EXTENSION_BREAKDOWN'));
      expect(lightAppBarTitle.style?.color, equals(HudColor.lightAccentCyan));

      final lightCsvIcon = tester.widget<Icon>(find.byIcon(Icons.download));
      expect(lightCsvIcon.color, equals(HudColor.lightAccentCyan));

      final lightSearchField = tester.widget<TextField>(find.byType(TextField));
      expect(lightSearchField.style?.color, equals(HudColor.lightTextMain));
      expect(lightSearchField.decoration?.fillColor, equals(HudColor.lightBgPanel));
      final lightPrefixIcon = lightSearchField.decoration?.prefixIcon as Icon;
      expect(lightPrefixIcon.color, equals(HudColor.lightTextMain.withValues(alpha: 0.38)));

      final lightExtText = tester.widget<Text>(find.text('.mp4'));
      expect(lightExtText.style?.color, equals(HudColor.lightTextMain));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Theme
      await tester.pumpWidget(
        _wrap(
          [extensionBreakdownProvider(_root).overrideWith((ref) => result)],
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, equals(HudColor.darkBgBase));

      final darkAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(darkAppBar.backgroundColor, equals(HudColor.darkBgPanel));

      final darkAppBarTitle = tester.widget<Text>(find.textContaining('EXTENSION_BREAKDOWN'));
      expect(darkAppBarTitle.style?.color, equals(HudColor.darkAccentCyan));

      final darkCsvIcon = tester.widget<Icon>(find.byIcon(Icons.download));
      expect(darkCsvIcon.color, equals(HudColor.darkAccentCyan));

      final darkSearchField = tester.widget<TextField>(find.byType(TextField));
      expect(darkSearchField.style?.color, equals(HudColor.darkTextMain));
      expect(darkSearchField.decoration?.fillColor, equals(HudColor.darkBgPanel));
      final darkPrefixIcon = darkSearchField.decoration?.prefixIcon as Icon;
      expect(darkPrefixIcon.color, equals(HudColor.darkTextMain.withValues(alpha: 0.38)));

      final darkExtText = tester.widget<Text>(find.text('.mp4'));
      expect(darkExtText.style?.color, equals(HudColor.darkTextMain));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts detail bottom sheet and stats to theme on item click', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final result = ExtensionBreakdownResult(
        root: _root,
        extensions: [
          _item('.mp4', 'media', fileCount: 2, totalBytes: 8000),
        ],
      );

      // 1. Light Mode Bottom Sheet
      await tester.pumpWidget(
        _wrap(
          [extensionBreakdownProvider(_root).overrideWith((ref) => result)],
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('.mp4'));
      await tester.pumpAndSettle();

      final lightSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(lightSheet.backgroundColor, equals(HudColor.lightBgPanel));

      final lightLargestHeader = tester.widget<Text>(find.text('LARGEST FILE RECORDED'));
      expect(lightLargestHeader.style?.color, equals(HudColor.lightAccentCyan));

      final lightPath = tester.widget<Text>(find.text('$_root\\big.mp4'));
      expect(lightPath.style?.color, equals(HudColor.lightTextMain));

      final lightCopyBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'COPY PATH'));
      expect(
        lightCopyBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.lightTextMain),
      );

      final lightExplorerBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'FIND IN EXPLORER'));
      expect(
        lightExplorerBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.lightAccentCyan),
      );

      final lightStatLabel = tester.widget<Text>(find.text('TOTAL FILES'));
      expect(
        lightStatLabel.style?.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.38)),
      );

      // Test Copy Path SnackBar styling
      await tester.tap(find.widgetWithText(ElevatedButton, 'COPY PATH'));
      await tester.pumpAndSettle();

      expect(find.text('Path copied to clipboard'), findsOneWidget);
      final lightSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(lightSnackBar.backgroundColor, equals(HudColor.lightBgPanel));

      ScaffoldMessenger.of(tester.element(find.byType(ExtensionBreakdownScreen))).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode Bottom Sheet
      await tester.pumpWidget(
        _wrap(
          [extensionBreakdownProvider(_root).overrideWith((ref) => result)],
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('.mp4'));
      await tester.pumpAndSettle();

      final darkSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(darkSheet.backgroundColor, equals(HudColor.darkBgPanel));

      final darkLargestHeader = tester.widget<Text>(find.text('LARGEST FILE RECORDED'));
      expect(darkLargestHeader.style?.color, equals(HudColor.darkAccentCyan));

      final darkPath = tester.widget<Text>(find.text('$_root\\big.mp4'));
      expect(darkPath.style?.color, equals(HudColor.darkTextMain));

      final darkCopyBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'COPY PATH'));
      expect(
        darkCopyBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.darkTextMain),
      );

      final darkExplorerBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'FIND IN EXPLORER'));
      expect(
        darkExplorerBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.darkAccentCyan),
      );

      final darkStatLabel = tester.widget<Text>(find.text('TOTAL FILES'));
      expect(
        darkStatLabel.style?.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.38)),
      );

      // Test Copy Path SnackBar styling
      await tester.tap(find.widgetWithText(ElevatedButton, 'COPY PATH'));
      await tester.pumpAndSettle();

      expect(find.text('Path copied to clipboard'), findsOneWidget);
      final darkSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(darkSnackBar.backgroundColor, equals(HudColor.darkBgPanel));

      ScaffoldMessenger.of(tester.element(find.byType(ExtensionBreakdownScreen))).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
