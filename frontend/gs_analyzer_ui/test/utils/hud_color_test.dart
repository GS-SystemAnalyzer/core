import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';

void main() {
  group('HudColor.resolveAccent', () {
    test('resolves accent with 1 argument (defaults to dark mode)', () {
      final accent = HudColor.resolveAccent('green');
      expect(accent, equals(HudColor.darkAccentGreen));

      final defaultAccent = HudColor.resolveAccent(null);
      expect(defaultAccent, equals(HudColor.darkAccentCyan));
    });

    test('resolves light and dark accent colors correctly', () {
      expect(
        HudColor.resolveAccent('green', Brightness.light),
        equals(HudColor.lightAccentGreen),
      );
      expect(
        HudColor.resolveAccent('green', Brightness.dark),
        equals(HudColor.darkAccentGreen),
      );

      expect(
        HudColor.resolveAccent('cyan', Brightness.light),
        equals(HudColor.lightAccentCyan),
      );
      expect(
        HudColor.resolveAccent('cyan', Brightness.dark),
        equals(HudColor.darkAccentCyan),
      );

      expect(
        HudColor.resolveAccent('amber', Brightness.light),
        equals(HudColor.lightAccentAmber),
      );
      expect(
        HudColor.resolveAccent('amber', Brightness.dark),
        equals(HudColor.darkAccentAmber),
      );

      expect(
        HudColor.resolveAccent('red', Brightness.light),
        equals(HudColor.lightAccentRed),
      );
      expect(
        HudColor.resolveAccent('red', Brightness.dark),
        equals(HudColor.darkAccentRed),
      );

      expect(
        HudColor.resolveAccent('purple', Brightness.light),
        equals(HudColor.lightAccentPurple),
      );
      expect(
        HudColor.resolveAccent('purple', Brightness.dark),
        equals(HudColor.darkAccentPurple),
      );

      expect(
        HudColor.resolveAccent('blue', Brightness.light),
        equals(HudColor.lightAccentBlue),
      );
      expect(
        HudColor.resolveAccent('blue', Brightness.dark),
        equals(HudColor.darkAccentBlue),
      );
    });

    test('falls back to cyan for unknown or null keys', () {
      expect(
        HudColor.resolveAccent('unknown', Brightness.light),
        equals(HudColor.lightAccentCyan),
      );
      expect(
        HudColor.resolveAccent('unknown', Brightness.dark),
        equals(HudColor.darkAccentCyan),
      );
      expect(
        HudColor.resolveAccent(null, Brightness.light),
        equals(HudColor.lightAccentCyan),
      );
      expect(
        HudColor.resolveAccent(null, Brightness.dark),
        equals(HudColor.darkAccentCyan),
      );
    });
  });
}
