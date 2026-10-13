import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/age_heatmap_model.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/age_heatmap_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
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

  group('DirectoryNodeWidget age heatmap indicator theme adaptation', () {
    testWidgets('renders heatmap color bar adapting to active theme mode', (tester) async {
      final targetNode = StorageNode(
        name: 'FreshFolder',
        path: 'C:/test/FreshFolder',
        type: 'Directory',
        sizeBytes: 2048,
        lastModified: DateTime.now(),
      );

      final heatmapResult = AgeHeatmapResult(
        root: 'C:/test',
        nodes: [
          AgeHeatmapNode(
            path: 'C:/test/FreshFolder',
            sizeBytes: 2048,
            ageBucket: 'fresh',
            lastModified: DateTime.now(),
          ),
        ],
        summary: const {
          'fresh': AgeBucketSummary(count: 1, totalBytes: 2048),
        },
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: 'C:/test'),
            ),
            ageHeatmapEnabledProvider.overrideWith((ref) => true),
            ageHeatmapProvider('C:/test').overrideWith((ref) async => heatmapResult),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: targetNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightBarFinder = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 4 && w.constraints?.maxHeight == 32,
      );
      expect(lightBarFinder, findsOneWidget);
      final lightBarContainer = tester.widget<Container>(lightBarFinder);
      final lightBarDec = lightBarContainer.decoration as BoxDecoration;
      expect(lightBarDec.color, equals(HudColor.lightAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(ref)..state = const DirectoryState(currentPath: 'C:/test'),
            ),
            ageHeatmapEnabledProvider.overrideWith((ref) => true),
            ageHeatmapProvider('C:/test').overrideWith((ref) async => heatmapResult),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: targetNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkBarFinder = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 4 && w.constraints?.maxHeight == 32,
      );
      expect(darkBarFinder, findsOneWidget);
      final darkBarContainer = tester.widget<Container>(darkBarFinder);
      final darkBarDec = darkBarContainer.decoration as BoxDecoration;
      expect(darkBarDec.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
