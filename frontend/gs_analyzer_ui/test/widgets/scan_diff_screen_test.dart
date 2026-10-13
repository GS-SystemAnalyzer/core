import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/drive_info.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/scan_diff_provider.dart';
import 'package:gs_analyzer_ui/screen/scan_diff_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DriveInfo _drive() => DriveInfo.fromJson({
  'name': r'C:\',
  'label': 'System',
  'type': 'fixed',
  'format': 'NTFS',
  'totalBytes': 1000,
  'freeBytes': 500,
  'usedBytes': 500,
});

Map<String, dynamic> _diffJson({
  bool hasBaseline = true,
  int added = 1,
  int grown = 1,
}) => {
  'root': 'C:/',
  'hasBaseline': hasBaseline,
  'baselineScannedAt': hasBaseline ? '2026-07-14T09:12:00Z' : null,
  'currentScannedAt': '2026-07-15T14:03:00Z',
  'added': List.generate(
    added,
    (i) => {
      'path': 'C:/added/file$i.iso',
      'isDirectory': false,
      'currentBytes': 5100273664,
      'previousBytes': 0,
      'deltaBytes': 5100273664,
      'childCount': null,
      'lastModified': null,
    },
  ),
  'removed': const [],
  'grown': List.generate(
    grown,
    (i) => {
      'path': 'C:/grown/dir$i',
      'isDirectory': true,
      'currentBytes': 3221225472,
      'previousBytes': 1073741824,
      'deltaBytes': 2147483648,
      'childCount': null,
      'lastModified': null,
    },
  ),
  'shrunk': const [],
  'summary': {
    'addedCount': added,
    'addedBytes': added * 5100273664,
    'removedCount': 0,
    'removedBytes': 0,
    'grownCount': grown,
    'grownDeltaBytes': grown * 2147483648,
    'shrunkCount': 0,
    'shrunkDeltaBytes': 0,
    'netDeltaBytes': added * 5100273664 + grown * 2147483648,
  },
};

Future<void> _pump(WidgetTester tester, MockClient client, {ThemeData? theme}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(ApiService(client)),
        // Seed a single fixed drive so currentDriveProvider resolves to C:\.
        drivesProvider.overrideWith(() => _StubDrivesNotifier([_drive()])),
      ],
      child: MaterialApp(
        theme: theme,
        home: const ScanDiffScreen(),
      ),
    ),
  );
}

class _StubDrivesNotifier extends DrivesNotifier {
  _StubDrivesNotifier(this._drives);
  final List<DriveInfo> _drives;
  @override
  List<DriveInfo> build() => _drives;
}

void main() {
  testWidgets('renders the summary strip and change sections on success', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode(_diffJson()), 200),
    );
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.text('WHAT_CHANGED'), findsOneWidget);
    // Section headers include their counts.
    expect(find.textContaining('ADDED'), findsWidgets);
    expect(find.textContaining('GROWN'), findsWidgets);
    // The added file surfaces by name.
    expect(find.textContaining('file0.iso'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('first-scan (no baseline) shows the BASELINE SAVED state', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(_diffJson(hasBaseline: false, added: 0, grown: 0)),
        200,
      ),
    );
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.textContaining('FIRST SCAN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('409 (no scan cached) shows the RUN A SCAN state', (tester) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'error': 'NO_SCAN_CACHED', 'message': 'x'}),
        409,
      ),
    );
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.textContaining('NO SCAN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  group('ScanDiffScreen Theme Adaptation Tests', () {
    testWidgets('adapts scaffold panel, appbar header, summary strip, and chips between themes', (tester) async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_diffJson()), 200),
      );

      // 1. Light Mode
      await _pump(tester, client, theme: HudTheme.lightTheme(HudColor.lightAccentCyan));
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, equals(HudColor.lightBgPanel));

      final lightTitle = tester.widget<Text>(find.text('WHAT_CHANGED'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentCyan));

      final lightClearIcon = tester.widget<Icon>(find.byIcon(Icons.restart_alt));
      expect(lightClearIcon.color, equals(HudColor.lightTextDim));

      final lightChipText = tester.widget<Text>(find.text('+1 ADDED'));
      expect(lightChipText.style?.color, equals(HudColor.lightAccentGreen));

      final lightGrownChip = tester.widget<Text>(find.text('▲1 GROWN'));
      expect(lightGrownChip.style?.color, equals(HudColor.lightAccentAmber));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await _pump(tester, client, theme: HudTheme.darkTheme(HudColor.darkAccentCyan));
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, equals(HudColor.darkBgPanel));

      final darkTitle = tester.widget<Text>(find.text('WHAT_CHANGED'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentCyan));

      final darkClearIcon = tester.widget<Icon>(find.byIcon(Icons.restart_alt));
      expect(darkClearIcon.color, equals(HudColor.darkTextDim));

      final darkChipText = tester.widget<Text>(find.text('+1 ADDED'));
      expect(darkChipText.style?.color, equals(HudColor.darkAccentGreen));

      final darkGrownChip = tester.widget<Text>(find.text('▲1 GROWN'));
      expect(darkGrownChip.style?.color, equals(HudColor.darkAccentAmber));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
