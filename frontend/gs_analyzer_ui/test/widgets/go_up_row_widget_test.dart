import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/go_up_row_widget.dart';

class MockDirectoryNotifier extends StateNotifier<DirectoryState>
    implements DirectoryNotifier {
  bool navigateUpCalled = false;

  MockDirectoryNotifier([DirectoryState state = const DirectoryState()])
      : super(state);

  @override
  void navigateUp() {
    navigateUpCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('GoUpRowWidget renders label, return icon, and triggers navigateUp on tap',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockNotifier = MockDirectoryNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          directoryProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: GoUpRowWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('[..] GO UP A DIRECTORY'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_return_outlined), findsOneWidget);

    await tester.tap(find.byType(GoUpRowWidget));
    await tester.pumpAndSettle();

    expect(mockNotifier.navigateUpCalled, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  group('GoUpRowWidget Theme Adaptation Tests', () {
    testWidgets('GoUpRowWidget adapts border decoration, icon color, and text style between themes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockNotifier = MockDirectoryNotifier();

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => mockNotifier),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: GoUpRowWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(GoUpRowWidget),
          matching: find.byType(Container),
        ).first,
      );
      final lightDec = lightContainer.decoration as BoxDecoration;
      expect(
        (lightDec.border as Border).bottom.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.1)),
      );

      final lightIcon = tester.widget<Icon>(find.byIcon(Icons.keyboard_return_outlined));
      expect(lightIcon.color, equals(HudColor.lightAccentCyan));

      final lightText = tester.widget<Text>(find.text('[..] GO UP A DIRECTORY'));
      expect(lightText.style?.color, equals(HudColor.lightTextMain));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => mockNotifier),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: GoUpRowWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(GoUpRowWidget),
          matching: find.byType(Container),
        ).first,
      );
      final darkDec = darkContainer.decoration as BoxDecoration;
      expect(
        (darkDec.border as Border).bottom.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.1)),
      );

      final darkIcon = tester.widget<Icon>(find.byIcon(Icons.keyboard_return_outlined));
      expect(darkIcon.color, equals(HudColor.darkAccentCyan));

      final darkText = tester.widget<Text>(find.text('[..] GO UP A DIRECTORY'));
      expect(darkText.style?.color, equals(HudColor.darkTextMain));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
