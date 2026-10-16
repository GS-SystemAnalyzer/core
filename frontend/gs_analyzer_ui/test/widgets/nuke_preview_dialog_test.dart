import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/widgets/nuke_preview_dialog.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

void main() {
  testWidgets('recycle-bin toggle updates NukePreviewResult correctly', (
    tester,
  ) async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'totalBytes': 1000,
            'totalFormatted': '1 KB',
            'totalFiles': 2,
            'totalDirectories': 1,
            'planToken': 'plan-abc',
            'stagedPaths': ['C:\\temp\\x'],
            'errors': [],
          },
        }),
        200,
      );
    });

    final apiService = ApiService(client);

    dynamic dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await showDialog(
                  context: context,
                  builder: (context) => NukePreviewDialog(
                    targetPaths: const ['C:\\temp\\x'],
                    apiService: apiService,
                  ),
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    // The switch for recycle bin should be initially off (default)
    expect(find.byType(Switch), findsOneWidget);
    Switch switchWidget = tester.widget(find.byType(Switch));
    expect(switchWidget.value, isFalse);

    // Toggle the switch
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // The button should now be MOVE TO RECYCLE BIN, tap it
    await tester.tap(find.text('MOVE TO RECYCLE BIN').last);
    await tester.pumpAndSettle();

    expect(dialogResult, isNotNull);
    // Since dialog returns a Map or a typed record, I'll access fields
    // Wait, NukePreviewDialog pops a map: {'execute': true, 'useRecycleBin': _useRecycleBin, 'planToken': _preview!.planToken}
    expect(dialogResult.confirmed, isTrue);
    expect(dialogResult.useRecycleBin, isTrue);
    expect(dialogResult.planToken, 'plan-abc');
  });

  group('NukePreviewDialog Theme Adaptation Tests', () {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'totalBytes': 2048,
            'totalFormatted': '2 KB',
            'totalFiles': 1,
            'totalDirectories': 1,
            'planToken': 'plan-123',
            'stagedPaths': ['C:\\temp\\test'],
            'errors': [],
          },
        }),
        200,
      );
    });

    testWidgets('adapts dialog panel, border, title, and buttons between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: NukePreviewDialog(
              targetPaths: const ['C:\\temp\\test'],
              apiService: ApiService(client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));
      final lightShape = lightDialog.shape as RoundedRectangleBorder;
      expect(lightShape.side.color, equals(HudColor.lightAccentRed));

      final lightTitle = tester.widget<Text>(find.text('CONFIRM OBLITERATION'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentRed));

      final lightWarningIcon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined));
      expect(lightWarningIcon.color, equals(HudColor.lightAccentRed));

      final lightAbortText = tester.widget<Text>(find.text('ABORT'));
      expect(lightAbortText.style?.color, equals(HudColor.lightTextMuted));

      final lightExecuteText = tester.widget<Text>(find.text('EXECUTE NUKE'));
      expect(lightExecuteText.style?.color, equals(HudColor.lightAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: NukePreviewDialog(
              targetPaths: const ['C:\\temp\\test'],
              apiService: ApiService(client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));
      final darkShape = darkDialog.shape as RoundedRectangleBorder;
      expect(darkShape.side.color, equals(HudColor.darkAccentRed));

      final darkTitle = tester.widget<Text>(find.text('CONFIRM OBLITERATION'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentRed));

      final darkWarningIcon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_outlined));
      expect(darkWarningIcon.color, equals(HudColor.darkAccentRed));

      final darkAbortText = tester.widget<Text>(find.text('ABORT'));
      expect(darkAbortText.style?.color, equals(HudColor.darkTextMuted));

      final darkExecuteText = tester.widget<Text>(find.text('EXECUTE NUKE'));
      expect(darkExecuteText.style?.color, equals(HudColor.darkAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
