import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/models/watcher_event.dart';
import 'package:gs_analyzer_ui/utils/csv_exporter.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

void main() {
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  final testItem = ExtensionBreakdownItem(
    ext: '.log',
    category: 'text',
    fileCount: 12,
    totalBytes: 10240,
    sizeFormatted: '10.0 KB',
    percentOfDisk: 5.5,
    averageFileSizeBytes: 853,
    averageSizeFormatted: '853 B',
    largestFilePath: 'C:\\logs\\test,data"quotes".log',
    largestFileBytes: 4096,
    largestSizeFormatted: '4.0 KB',
  );

  final testEvent = WatcherEvent(
    path: 'C:\\logs\\app,test"quoted".log',
    oldPath: 'C:\\logs\\old,path.log',
    kind: WatcherChangeKind.modified,
    timestamp: DateTime.utc(2026, 6, 1, 10, 30, 0),
    isDirectory: false,
    occurrences: 4,
  );

  final List<String> createdFiles = [];

  tearDown(() {
    for (final path in createdFiles) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    createdFiles.clear();
  });

  group('CsvExporter Theme & Functionality Tests', () {
    testWidgets('exportExtensionBreakdown exports CSV and adapts SnackBar to Light Theme', (tester) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await CsvExporter.exportExtensionBreakdown(testContext, [testItem]);
      });
      await tester.pump(const Duration(milliseconds: 300));

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);

      final snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.backgroundColor, equals(HudColor.lightBgPanel));

      final textWidget = tester.widget<Text>(find.descendant(of: snackBarFinder, matching: find.byType(Text)));
      expect(textWidget.data, contains('Exported to'));
      expect(textWidget.style?.color, equals(HudColor.lightTextMuted));

      final filePath = textWidget.data!.replaceFirst('Exported to ', '').trim();
      createdFiles.add(filePath);

      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('Extension,Category,File Count,Total Size (Bytes)'));
      expect(content, contains('.log,text,12,10240,10.0 KB,5.5,853,853 B,4096,4.0 KB,"C:\\logs\\test,data""quotes"".log"'));

      ScaffoldMessenger.of(testContext).removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('exportExtensionBreakdown exports CSV and adapts SnackBar to Dark Theme', (tester) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await CsvExporter.exportExtensionBreakdown(testContext, [testItem]);
      });
      await tester.pump(const Duration(milliseconds: 300));

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);

      final snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.backgroundColor, equals(HudColor.darkBgPanel));

      final textWidget = tester.widget<Text>(find.descendant(of: snackBarFinder, matching: find.byType(Text)));
      expect(textWidget.data, contains('Exported to'));
      expect(textWidget.style?.color, equals(HudColor.darkTextMuted));

      final filePath = textWidget.data!.replaceFirst('Exported to ', '').trim();
      createdFiles.add(filePath);

      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      ScaffoldMessenger.of(testContext).removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('exportWatcherEventLog exports CSV and adapts SnackBar to Light Theme', (tester) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await CsvExporter.exportWatcherEventLog(testContext, [testEvent]);
      });
      await tester.pump(const Duration(milliseconds: 300));

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);

      final snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.backgroundColor, equals(HudColor.lightBgPanel));

      final textWidget = tester.widget<Text>(find.descendant(of: snackBarFinder, matching: find.byType(Text)));
      expect(textWidget.data, contains('Exported to'));
      expect(textWidget.style?.color, equals(HudColor.lightTextMuted));

      final filePath = textWidget.data!.replaceFirst('Exported to ', '').trim();
      createdFiles.add(filePath);

      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('Timestamp,Kind,Path,OldPath,IsDirectory,Occurrences'));
      expect(content, contains('"C:\\logs\\app,test""quoted"".log"'));
      expect(content, contains('"C:\\logs\\old,path.log"'));
      expect(content, contains('modified'));
      expect(content, contains('4'));

      ScaffoldMessenger.of(testContext).removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('exportWatcherEventLog exports CSV and adapts SnackBar to Dark Theme', (tester) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await CsvExporter.exportWatcherEventLog(testContext, [testEvent]);
      });
      await tester.pump(const Duration(milliseconds: 300));

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);

      final snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.backgroundColor, equals(HudColor.darkBgPanel));

      final textWidget = tester.widget<Text>(find.descendant(of: snackBarFinder, matching: find.byType(Text)));
      expect(textWidget.data, contains('Exported to'));
      expect(textWidget.style?.color, equals(HudColor.darkTextMuted));

      final filePath = textWidget.data!.replaceFirst('Exported to ', '').trim();
      createdFiles.add(filePath);

      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      ScaffoldMessenger.of(testContext).removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
