import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/hud_accent_toggle.dart';

double contrast(Color a, Color b) {
  final left = a.computeLuminance();
  final right = b.computeLuminance();
  return left > right ? (left + 0.05) / (right + 0.05) : (right + 0.05) / (left + 0.05);
}

Future<Color> renderedFill(WidgetTester tester, Finder label) async {
  final capture = find.byKey(const ValueKey('accent-capture'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(capture);
  final origin = tester.getTopLeft(capture);
  final rect = tester.getRect(label);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = (rect.left - 4 - origin.dx).floor();
      final y = (rect.center.dy - origin.dy).floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final index = (y * image.width + x) * 4;
      return Color.fromARGB(pixels.getUint8(index + 3), pixels.getUint8(index),
          pixels.getUint8(index + 1), pixels.getUint8(index + 2));
    } finally {
      image.dispose();
    }
  }))!;
}

Future<double> renderedGlyphCenter(WidgetTester tester, Finder label) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('accent-capture')));
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final bounds = MatrixUtils.transformRect(paragraph.getTransformTo(boundary), paragraph.paintBounds);
  final foreground = paragraph.text.style!.color!.toARGB32();
  final ratio = tester.view.devicePixelRatio;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var first = -1;
      var last = -1;
      for (var y = (bounds.top * ratio).floor().clamp(0, image.height).toInt();
          y < (bounds.bottom * ratio).ceil().clamp(0, image.height).toInt(); y++) {
        for (var x = (bounds.left * ratio).floor().clamp(0, image.width).toInt();
            x < (bounds.right * ratio).ceil().clamp(0, image.width).toInt(); x++) {
          final index = (y * image.width + x) * 4;
          if ((pixels.getUint8(index) - ((foreground >> 16) & 255)).abs() <= 32 &&
              (pixels.getUint8(index + 1) - ((foreground >> 8) & 255)).abs() <= 32 &&
              (pixels.getUint8(index + 2) - (foreground & 255)).abs() <= 32) {
            if (first < 0) first = y;
            last = y;
            break;
          }
        }
      }
      expect(first, greaterThanOrEqualTo(0), reason: 'Visible foreground glyph pixels');
      return (first + last + 1) / (2 * ratio);
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  Future<void> host(WidgetTester tester, [ThemeData? theme, ValueChanged<int>? onChanged, bool compact = false]) async {
    var selected = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(MaterialApp(theme: theme,
      home: Scaffold(body: Center(child: RepaintBoundary(key: const ValueKey('accent-capture'),
        child: StatefulBuilder(builder: (context, setState) => HudAccentToggle<int>(
          compact: compact,
          showSelectedIcon: !compact,
          segments: const [
            ButtonSegment(value: 1, label: Text('FIRST')),
            ButtonSegment(value: 2, label: Text('SECOND')),
          ],
          selected: selected,
          onChanged: (value) {
            setState(() => selected = value);
            onChanged?.call(value);
          },
        )),
      )))));
    await tester.pumpAndSettle();
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final key in ['cyan', 'green', 'amber', 'red', 'purple', 'blue']) {
      testWidgets('rendered selection follows $key with readable text/checkmark in ${brightness.name}', (tester) async {
        final accent = HudColor.resolveAccent(key, brightness);
        final theme = brightness == Brightness.dark ? HudTheme.darkTheme(accent) : HudTheme.lightTheme(accent);
        await host(tester, theme);
        final label = find.text('FIRST');
        final foreground = tester.renderObject<RenderParagraph>(label).text.style!.color!;
        final fill = await renderedFill(tester, label);
        expect(fill.toARGB32(), accent.toARGB32());
        expect(contrast(foreground, fill), greaterThanOrEqualTo(4.5));
        final check = find.byIcon(Icons.check);
        final icon = tester.widget<Icon>(check);
        final checkColor = icon.color ?? IconTheme.of(tester.element(check)).color!;
        expect(contrast(checkColor, fill), greaterThanOrEqualTo(4.5));
        await tester.tap(find.text('SECOND'));
        await tester.pumpAndSettle();
        expect(tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>)).selected, {2});
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final key in ['cyan', 'green', 'amber', 'red', 'purple', 'blue']) {
      testWidgets('compact selection stays small readable and stable $key ${brightness.name}', (tester) async {
        final accent = HudColor.resolveAccent(key, brightness);
        final theme = brightness == Brightness.dark ? HudTheme.darkTheme(accent) : HudTheme.lightTheme(accent);
        await host(tester, theme, null, true);
        final label = find.text('FIRST');
        final foreground = tester.renderObject<RenderParagraph>(label).text.style!.color!;
        final fill = await renderedFill(tester, label);
        final group = find.byType(HudAccentToggle<int>);
        final original = tester.getRect(group).size;
        expect(original.height, 28);
        expect(original.width, lessThanOrEqualTo(170));
        expect(find.byIcon(Icons.check), findsNothing);
        expect(fill.toARGB32(), accent.toARGB32());
        expect(contrast(foreground, fill), greaterThanOrEqualTo(4.5));
        await tester.tap(find.text('SECOND'));
        await tester.pumpAndSettle();
        expect(tester.getRect(group).size, original);
        expect(tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>)).selected, {2});
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('compact labels are vertically centered ${brightness.name} scale=$scale', (tester) async {
        tester.view.devicePixelRatio = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        final accent = HudColor.resolveAccent('cyan', brightness);
        await host(tester, brightness == Brightness.dark ? HudTheme.darkTheme(accent) : HudTheme.lightTheme(accent), null, true);
        final group = find.byType(HudAccentToggle<int>);
        for (final selection in ['FIRST', 'SECOND']) {
          await tester.tap(find.text(selection));
          await tester.pumpAndSettle();
          for (final caption in ['FIRST', 'SECOND']) {
            final label = find.text(caption);
            final paragraph = tester.renderObject<RenderParagraph>(label);
            final textBounds = MatrixUtils.transformRect(paragraph.getTransformTo(null), paragraph.paintBounds);
            final pill = tester.getRect(group);
            final inner = tester.getRect(find.ancestor(of: label, matching: find.byType(TextButton)).first);
            final offset = textBounds.center.dy - pill.center.dy;
            final reason = '$caption: pill=${pill.height}, inner=${inner.height}, label-center-offset=$offset';
            expect(offset, closeTo(0, 1), reason: reason);
            expect(inner.height, closeTo(pill.height, 0.01), reason: reason);
            final origin = tester.getTopLeft(find.byKey(const ValueKey('accent-capture')));
            expect(await renderedGlyphCenter(tester, label), closeTo(pill.center.dy - origin.dy, 2));
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('keyboard traversal and activation select a segment', (tester) async {
    var selected = 1;
    await host(tester, HudTheme.darkTheme(HudColor.darkAccentAmber), (value) => selected = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bare MaterialApp fallback keeps selected text readable', (tester) async {
    await host(tester);
    final label = find.text('FIRST');
    final fill = await renderedFill(tester, label);
    final text = tester.renderObject<RenderParagraph>(label).text.style!.color!;
    expect(contrast(text, fill), greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact keyboard selection and fallback remain accessible', (tester) async {
    var selected = 1;
    await host(tester, null, (value) => selected = value, true);
    final label = find.text('FIRST');
    final fill = await renderedFill(tester, label);
    final text = tester.renderObject<RenderParagraph>(label).text.style!.color!;
    expect(contrast(text, fill), greaterThanOrEqualTo(4.5));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });
}
