import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/large_file_model.dart';
import 'package:gs_analyzer_ui/providers/large_file_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/large_file_scanner_panel.dart';

class MockLargeFileNotifier extends StateNotifier<LargeFileState>
    implements LargeFileNotifier {
  MockLargeFileNotifier(LargeFileState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleFiles = [
    LargeFileModel(
      path: 'C:/Users/test/large_archive.zip',
      sizeBytes: 5242880000,
      sizeFormatted: '5.24 GB',
    ),
    LargeFileModel(
      path: 'C:/Users/test/installer.iso',
      sizeBytes: 3145728000,
      sizeFormatted: '3.15 GB',
    ),
  ];

  group('LargeFileScannerPanel Tests', () {
    testWidgets('renders empty awaiting state by default', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            largeFileProvider.overrideWith(
              (ref) => MockLargeFileNotifier(LargeFileState()),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LARGE FILE HUNTER PROTOCOL'), findsOneWidget);
      expect(find.text('AWAITING LARGE FILE SCAN COMMAND....'), findsOneWidget);
      expect(find.text('INIT SCAN'), findsOneWidget);
      expect(find.text('CLOSE TOOL'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders loading state when scan is active', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            largeFileProvider.overrideWith(
              (ref) => MockLargeFileNotifier(LargeFileState(isLoading: true)),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SCANNING DEEP SECTORS...'), findsOneWidget);
      expect(find.text('ABORT SCAN'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('renders large files list with formatted sizes and delete icons', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            largeFileProvider.overrideWith(
              (ref) => MockLargeFileNotifier(LargeFileState(largeFiles: sampleFiles)),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('C:/Users/test/large_archive.zip'), findsOneWidget);
      expect(find.text('5.24 GB'), findsOneWidget);
      expect(find.text('C:/Users/test/installer.iso'), findsOneWidget);
      expect(find.text('3.15 GB'), findsOneWidget);
      expect(find.text('NUKE ALL (2)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('close tool button resets storageMode to diskAnalyzer', (tester) async {
      final container = ProviderContainer(
        overrides: [
          largeFileProvider.overrideWith(
            (ref) => MockLargeFileNotifier(LargeFileState()),
          ),
          storageModeProvider.overrideWith((ref) => StorageMode.largeFileScanner),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(storageModeProvider), StorageMode.largeFileScanner);
      await tester.tap(find.text('CLOSE TOOL'));
      await tester.pumpAndSettle();

      expect(container.read(storageModeProvider), StorageMode.diskAnalyzer);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts colors between Light and Dark themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            largeFileProvider.overrideWith(
              (ref) => MockLargeFileNotifier(LargeFileState(largeFiles: sampleFiles)),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightHeaderFinder = find.ancestor(
        of: find.text('LARGE FILE HUNTER PROTOCOL'),
        matching: find.byType(Container),
      ).first;
      final lightHeaderContainer = tester.widget<Container>(lightHeaderFinder);
      final lightHeaderDec = lightHeaderContainer.decoration as BoxDecoration;
      expect(lightHeaderDec.color, equals(HudColor.lightBgPanel));

      final lightTitle = tester.widget<Text>(find.text('LARGE FILE HUNTER PROTOCOL'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentCyan));

      final lightCloseText = tester.widget<Text>(find.text('CLOSE TOOL'));
      expect(lightCloseText.style?.color, equals(HudColor.lightTextMuted));

      final lightFileText = tester.widget<Text>(find.text('C:/Users/test/large_archive.zip'));
      expect(lightFileText.style?.color, equals(HudColor.lightTextMain));

      final lightSizeText = tester.widget<Text>(find.text('5.24 GB'));
      expect(lightSizeText.style?.color, equals(HudColor.lightAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            largeFileProvider.overrideWith(
              (ref) => MockLargeFileNotifier(LargeFileState(largeFiles: sampleFiles)),
            ),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: LargeFileScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkHeaderFinder = find.ancestor(
        of: find.text('LARGE FILE HUNTER PROTOCOL'),
        matching: find.byType(Container),
      ).first;
      final darkHeaderContainer = tester.widget<Container>(darkHeaderFinder);
      final darkHeaderDec = darkHeaderContainer.decoration as BoxDecoration;
      expect(darkHeaderDec.color, equals(HudColor.darkBgPanel));

      final darkTitle = tester.widget<Text>(find.text('LARGE FILE HUNTER PROTOCOL'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentCyan));

      final darkCloseText = tester.widget<Text>(find.text('CLOSE TOOL'));
      expect(darkCloseText.style?.color, equals(HudColor.darkTextMuted));

      final darkFileText = tester.widget<Text>(find.text('C:/Users/test/large_archive.zip'));
      expect(darkFileText.style?.color, equals(HudColor.darkTextMain));

      final darkSizeText = tester.widget<Text>(find.text('5.24 GB'));
      expect(darkSizeText.style?.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
