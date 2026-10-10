import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/widgets/minimized_op_pill.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}

/// Moves a synthetic mouse pointer over [finder] to trigger MouseRegion hover.
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed ring shows the integer percent — no decimal, no % glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'SCANNING',
          accent: Colors.cyanAccent,
          progress: 0.62,
          target: 'C:/Users/G00dS0ul/Downloads',
          onRestore: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('op_ring')), findsOneWidget);
    expect(find.text('62'), findsOneWidget);
    expect(find.text('62%'), findsNothing);
    expect(find.text('62.0'), findsNothing);
    // Label and bar belong to the expanded pill, not the resting ring.
    expect(find.text('SCANNING'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('collapsed ring is indeterminate with no spinner when progress is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'EXPORTING',
          accent: Colors.cyanAccent,
          progress: null,
          target: 'C:/',
          onRestore: () {},
        ),
      ),
    );

    // A static ring is used for indeterminate — never a (spinning)
    // CircularProgressIndicator.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('\u22EF'), findsOneWidget);
  });

  testWidgets('hover expands to the full pill, exit collapses back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'SCANNING',
          accent: Colors.cyanAccent,
          progress: 0.62,
          target: 'C:/Users/G00dS0ul/Downloads',
          onRestore: () {},
        ),
      ),
    );

    expect(find.text('SCANNING'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(() => gesture.removePointer());
    await gesture.moveTo(tester.getCenter(find.byType(MinimizedOpPill)));
    await tester.pumpAndSettle();

    // Expanded: label + progress bar now present.
    expect(find.text('SCANNING'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Move the pointer away → 250ms grace + animation → collapses.
    await gesture.moveTo(const Offset(2000, 2000));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('SCANNING'), findsNothing);
  });

  testWidgets('complete state shows a check in the ring', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'SCAN COMPLETE',
          accent: Colors.greenAccent,
          progress: 1.0,
          target: 'C:/',
          state: OpVisualState.complete,
          onRestore: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('failed state shows an alert glyph in the ring', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'SCAN FAILED',
          accent: Colors.redAccent,
          progress: null,
          target: 'C:/',
          state: OpVisualState.failed,
          onRestore: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.priority_high), findsOneWidget);
  });

  testWidgets('expanded pill omits the abort icon when onAbort is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'EXPORTING',
          accent: Colors.cyanAccent,
          progress: 0.4,
          target: 'C:/',
          onRestore: () {},
        ),
      ),
    );

    await _hover(tester, find.byType(MinimizedOpPill));

    expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('tapping the resting ring invokes onRestore (open dialog)', (
    tester,
  ) async {
    var restored = false;
    await tester.pumpWidget(
      _wrap(
        MinimizedOpPill(
          label: 'SCANNING',
          accent: Colors.cyanAccent,
          progress: 0.5,
          target: 'C:/',
          onRestore: () => restored = true,
        ),
      ),
    );

    await tester.tap(find.byType(MinimizedOpPill));
    expect(restored, isTrue);
  });
}
