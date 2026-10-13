import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/directory_node_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  final mockApi = MockApiService();

  Future<void> pumpNode(WidgetTester tester, StorageNode node) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: DirectoryNodeWidget(
              node: node,
              apiService: mockApi,
              onNuke: (_, __) {},
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StorageNode node(String name, {bool isHidden = false, bool isSystem = false}) =>
      StorageNode(
        name: name,
        path: 'C:/$name',
        type: 'Directory',
        sizeBytes: 1024,
        lastModified: DateTime(2026, 1, 1),
        isHidden: isHidden,
        isSystem: isSystem,
      );

  group('DirectoryNodeWidget two-tier visibility styling', () {
    testWidgets('hidden-but-not-system entries render dimmed (0.45 opacity, normal color)',
        (tester) async {
      await pumpNode(tester, node('AppData', isHidden: true));

      final text = tester.widget<Text>(find.text('AppData'));
      expect(text.style?.color, equals(HudColor.darkTextMain.withValues(alpha: 0.45)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('system entries render locked (accentRed), and system wins over hidden',
        (tester) async {
      // A hidden+system entry must take the locked style, not the Tier-1 dim.
      await pumpNode(tester, node('ProtectedData', isHidden: true, isSystem: true));

      final text = tester.widget<Text>(find.text('ProtectedData'));
      expect(text.style?.color, equals(HudColor.darkAccentRed.withValues(alpha: 0.5)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('ordinary entries are unchanged (full opacity, textMain)',
        (tester) async {
      await pumpNode(tester, node('Documents'));

      final text = tester.widget<Text>(find.text('Documents'));
      expect(text.style?.color, equals(HudColor.darkTextMain));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
