import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/widgets/side_bar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SideBarTreeWidget renders streaming directory nodes without stuck spinner', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(directoryProvider.notifier).state = container
        .read(directoryProvider)
        .copyWith(
          currentPath: 'C:/',
          isLoading: true,
          displayNodes: [],
          errorMessage: null,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SideBarTreeWidget(onNuke: (_, __) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    final chunk = [
      {
        'name': 'Projects',
        'path': 'C:/Projects',
        'parentPath': 'C:/',
        'type': 'Directory',
        'sizeBytes': 2048,
        'lastModified': DateTime.now().toIso8601String(),
        'isHidden': false,
        'isSystem': false,
        'ownBytes': 0,
        'recursiveBytes': 2048,
        'recursiveBytesFinal': true,
      }
    ];

    container.read(directoryProvider.notifier).receiveStreamChunk(null, 'C:/', chunk);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('SideBarTreeWidget adapts width to treeSidebarWidthProvider and shrinks icons as width decreases', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(directoryProvider.notifier).state = container
        .read(directoryProvider)
        .copyWith(
          currentPath: 'C:/',
          isLoading: false,
          displayNodes: [],
        );

    final chunk = [
      {
        'name': 'Projects',
        'path': 'C:/Projects',
        'parentPath': 'C:/',
        'type': 'Directory',
        'sizeBytes': 2048,
        'lastModified': DateTime.now().toIso8601String(),
        'isHidden': false,
        'isSystem': false,
        'ownBytes': 0,
        'recursiveBytes': 2048,
        'recursiveBytesFinal': true,
      }
    ];

    container.read(directoryProvider.notifier).receiveStreamChunk(null, 'C:/', chunk);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SideBarTreeWidget(onNuke: (_, __) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    // Default width is 260.0
    final animatedContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(animatedContainer.constraints?.maxWidth ?? (animatedContainer.child as dynamic), isNotNull);

    // Shrink sidebar width to 105.0px (mid-shrink)
    container.read(treeSidebarWidthProvider.notifier).state = 105.0;
    await tester.pump();

    final iconWidget = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
    expect(iconWidget.size! < 16.0, true, reason: 'Folder icon must shrink down as sidebar width decreases');

    // Collapse sidebar
    container.read(treeExpandedProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final box = tester.renderObject(find.byType(AnimatedContainer)) as RenderBox;
    expect(box.size.width, 0.0);
  });
}
